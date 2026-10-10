import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/article.dart';
import '../models/site_filter.dart';
import '../models/ucenter.dart';
import '../models/ucenter_form.dart';
import '../models/ucenter_table.dart';
import 'http_client.dart';

/// JSON 控制器的统一回包（`List.php` / `Get.php` / `userfilter_fun.php` /
/// `shezhi_fun.php` 都是 `{code, msg, …}`）。
class UcenterResult {
  final int code;
  final String message;
  final String raw;

  const UcenterResult({
    required this.code,
    required this.message,
    required this.raw,
  });

  static const UcenterResult empty = UcenterResult(
    code: -1,
    message: '',
    raw: '',
  );

  bool get ok => code == 0;

  /// 会话失效：网站用 1001 表示没登录 / 令牌过期。
  bool get needLogin => code == 1001;

  factory UcenterResult.fromText(String body) {
    if (body.trim().isEmpty) return UcenterResult.empty;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return UcenterResult.empty;
      final code = decoded['code'];
      return UcenterResult(
        code: code is num ? code.toInt() : int.tryParse('$code') ?? -1,
        message: decoded['msg']?.toString() ?? '',
        raw: body,
      );
    } on FormatException {
      return UcenterResult.empty;
    }
  }
}

/// 登录结果：`code == 1` 是出错（验证码/账号密码），`2` 是服务端要求跳转，
/// 其余视为成功（与网站 `cmd.php?act=verify` 的约定一致）。
class LoginResult {
  final bool ok;
  final String message;

  /// 服务端要求跳转的地址（`code == 2`，如需要邮箱验证）。
  final String? redirectUrl;

  const LoginResult({
    required this.ok,
    required this.message,
    this.redirectUrl,
  });

  factory LoginResult.fromText(String body) {
    if (body.trim().isEmpty) {
      return const LoginResult(ok: false, message: '登录失败，请重试');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const LoginResult(ok: false, message: '登录失败，请重试');
      }
      final code = decoded['code']?.toString() ?? '';
      final message = decoded['msg']?.toString() ?? '';
      if (code == '1') return LoginResult(ok: false, message: message);
      if (code == '2') {
        return LoginResult(
          ok: false,
          message: message,
          redirectUrl: decoded['href']?.toString(),
        );
      }
      return LoginResult(ok: true, message: message);
    } on FormatException {
      return const LoginResult(ok: false, message: '登录失败，请重试');
    }
  }
}

/// 今日签到状态（`Get.php act=MemTs`）。
///
/// 网站用同一个接口刷导航上的红点：`qian == 0` 表示今天还没签到、可以签。
class UcenterCheckInStatus {
  /// 今天还能签到（服务端 `qian == 0`）。
  final bool canCheckIn;

  /// 当前积分（`giod`）。
  final String points;

  const UcenterCheckInStatus({required this.canCheckIn, this.points = ''});

  /// 解析失败/不可用 → null（调用方按「不打扰」处理）。
  static UcenterCheckInStatus? fromText(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      if (decoded['code']?.toString() != '0') return null;
      final data = decoded['data'];
      if (data is! Map) return null;
      final qian = data['qian'];
      final canCheckIn = qian is num
          ? qian.toInt() == 0
          : int.tryParse('$qian') == 0;
      return UcenterCheckInStatus(
        canCheckIn: canCheckIn,
        points: data['giod']?.toString() ?? '',
      );
    } on FormatException {
      return null;
    }
  }
}

/// 规则行：网站 `userfilter_fun.php act=list` 的一行。///
/// 行的字段与筛选引擎的规则行同构（`Status`/`fanwei`/八组词/价格），直接复用
/// [FilterRule] 的解析；只有 id 是列表接口独有的。
class UcenterRuleRow {
  final String id;
  final FilterRule rule;

  const UcenterRuleRow({required this.id, required this.rule});

  factory UcenterRuleRow.fromMap(Map<String, dynamic> map) {
    final id = map['ID'] ?? map['id'] ?? '';
    return UcenterRuleRow(
      id: id.toString(),
      rule: FilterRule.fromJson(Map<String, dynamic>.from(map)),
    );
  }
}

/// 可选的预设头像（`Get.php act=UserImgList`）。
class UcenterAvatarOption {
  final String url;
  final bool selected;

  const UcenterAvatarOption({required this.url, this.selected = false});
}

/// 用户中心域的全部接口。
///
/// 网站用户中心（mochu_us 插件 + layui SPA）没有统一的 REST，接口分三处：
///  - `…/src/views/*.php`：服务端渲染的页面片段（首页统计、导航、各设置页表单）
///  - `…/json/List.php`：分页表格
///  - `…/json/Get.php`、`userfilter_fun.php`、`shezhi_fun.php`：写操作与表单
/// 都需要 `GET /Ucenter` 里那个 `basecrsfcode` 令牌；令牌按会话缓存，遇到
/// 「未登录/令牌失效」会强制刷新一次再重试。
class UcenterService {
  final HttpClient _client = HttpClient();

  /// 令牌按会话缓存，且**跨实例共享**：用户中心各页面各自 new 一个服务，
  /// 令牌是同一个会话的东西，缓存成实例字段会导致每次进页面都多请求一次 /Ucenter。
  static String? _csrf;
  static bool _csrfLoaded = false;

  /// 登录态切换（登录/注销）后必须丢弃令牌。
  static void resetSession() {
    _csrf = null;
    _csrfLoaded = false;
  }

  Future<String> _ensureCsrf({bool forceRefresh = false}) async {
    if (!forceRefresh && _csrfLoaded && _csrf != null) return _csrf!;
    final token = await _client.fetchUserCenterCsrfToken();
    if (token == null || token.isEmpty) {
      throw Exception('无法获取用户中心令牌，请重新登录');
    }
    _csrf = token;
    _csrfLoaded = true;
    return _csrf!;
  }

  /// 带令牌的表单 POST；服务端说没登录/令牌失效就换新令牌重试一次。
  Future<UcenterResult> _postJson(
    String file, {
    required Map<String, dynamic> data,
    Map<String, dynamic>? query,
    bool retryOnAuthFailure = true,
  }) async {
    final token = await _ensureCsrf();
    final body = await _client.postUcenterJson(
      file,
      query: query,
      data: {...data, 'csrfToken': token},
    );
    var result = UcenterResult.fromText(body);
    if (retryOnAuthFailure && result.needLogin) {
      await _ensureCsrf(forceRefresh: true);
      final retryBody = await _client.postUcenterJson(
        file,
        query: query,
        data: {...data, 'csrfToken': _csrf},
      );
      result = UcenterResult.fromText(retryBody);
    }
    return result;
  }

  // ------------------------------------------------------------------ 登录

  /// 登录页的验证码图片。
  Future<Uint8List> fetchCaptcha() => _client.fetchCaptcha();

  /// 账号密码登录（密码按网站前端约定做 MD5）。
  Future<LoginResult> login({
    required String username,
    required String password,
    required String vercode,
    bool keepLoggedIn = true,
  }) async {
    final body = await _client.login(
      username: username,
      passwordMd5: md5.convert(utf8.encode(password)).toString(),
      vercode: vercode,
      savedate: keepLoggedIn ? 30 : 1,
    );
    return LoginResult.fromText(body);
  }

  // -------------------------------------------------------------- 首页统计

  /// 用户中心首页：统计卡片 + 公告。
  Future<UcenterHome> fetchHome() async {
    final html = await _client.postUcenterView('index');
    return UcenterHome.parse(html);
  }

  /// 头像 / 昵称 / 等级标识。
  Future<UcenterProfile> fetchProfile() async {
    final html = await _client.postUcenterView('Nav');
    return parseUcenterProfile(html);
  }

  // ---------------------------------------------------------------- 表格

  /// 一页分页表格数据。
  Future<UcenterTablePage> fetchTable({
    required String act,
    int page = 1,
    int limit = 20,
    Map<String, dynamic> extra = const {},
  }) async {
    final token = await _ensureCsrf();
    final body = await _client.postUcenterJson(
      'List.php',
      data: {
        'csrfToken': token,
        'act': act,
        'page': '$page',
        'limit': '$limit',
        ...extra,
      },
    );
    return UcenterTablePage.fromJson(body);
  }

  /// 拉一个服务端渲染页面片段（掉登录时抛异常，由页面统一提示）。
  Future<String> fetchViewOrThrow(String view) async {
    final html = await _client.postUcenterView(view);
    if (ucenterSessionExpired(html)) {
      throw Exception(kUcenterSessionExpiredMessage);
    }
    return html;
  }

  /// 收藏列表（原 `ApiService.fetchCollectList`，并入这里统一处理令牌与掉登录）。
  Future<({List<CollectListItem> items, int total})> fetchCollectList({
    int page = 1,
    int limit = 20,
  }) async {
    final table = await fetchTable(
      act: 'CollList',
      page: page,
      limit: limit,
      extra: const {'group': 'all'},
    );
    if (table.needLogin) {
      throw Exception(table.message.isEmpty ? '请先登录' : table.message);
    }
    final items = table.rows
        .map((row) => CollectListItem.fromApiMap(row.raw))
        .where((e) => e.collectId.isNotEmpty)
        .toList();
    return (items: items, total: table.total);
  }

  /// 取消收藏。
  Future<({bool ok, String message})> deleteCollect(String collectId) async {
    final result = await _postJson('Get.php', data: {
      'act': 'CollDel',
      'id': collectId,
    });
    final message = result.message.isEmpty
        ? (result.ok ? '已取消收藏' : '取消收藏失败')
        : result.message;
    return (ok: result.ok, message: message);
  }

  /// 删除自己的评论。
  Future<UcenterResult> deleteComment(String id) =>
      _postJson('Get.php', data: {'act': 'commDel', 'id': id});

  /// 关闭工单。
  Future<UcenterResult> closeTicket(String id) =>
      _postJson('Get.php', data: {'act': 'GongDanClose', 'id': id});

  // -------------------------------------------------------------- 每日签到

  /// 今日签到状态；取不到（断网/掉登录）返回 null，调用方按「不打扰」处理。
  Future<UcenterCheckInStatus?> fetchCheckInStatus() async {
    final result = await _postJson('Get.php', data: {'act': 'MemTs'});
    if (result.needLogin || result.raw.isEmpty) return null;
    return UcenterCheckInStatus.fromText(result.raw);
  }

  /// 签到（`cmd.php?act=qiandao`）。
  ///
  /// 成功后服务端返回最新积分与提示文案；失败时 `message` 是失败原因（如今天已签到、
  /// 会员限制），由调用方决定是否提示。
  Future<({bool ok, String message, String points})> checkIn() async {
    final body = await _client.checkIn();
    if (body.trim().isEmpty) {
      return (ok: false, message: '', points: '');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return (ok: false, message: '', points: '');
      }
      final code = decoded['code']?.toString() ?? '';
      return (
        ok: code != '1',
        message: decoded['msg']?.toString() ?? '',
        points: decoded['giod']?.toString() ?? '',
      );
    } on FormatException {
      return (ok: false, message: '', points: '');
    }
  }

  // -------------------------------------------------------------- 规则行

  /// 某个频道的规则行（我的关注三个位、各筛选页）。
  Future<List<UcenterRuleRow>> fetchFilterRows(String channel) async {
    final token = await _ensureCsrf();
    final body = await _client.postUcenterJson(
      'userfilter_fun.php',
      data: {
        'csrfToken': token,
        'act': 'list',
        'channel': channel,
        'page': '1',
        'limit': '100',
      },
    );
    final result = UcenterResult.fromText(body);
    if (result.needLogin) {
      throw Exception(result.message.isEmpty ? '请先登录' : result.message);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const <UcenterRuleRow>[];
    final list = decoded['data'];
    if (list is! List) return const <UcenterRuleRow>[];
    return list
        .whereType<Map>()
        .map((e) => UcenterRuleRow.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 开关一条规则行。
  Future<UcenterResult> setFilterRowStatus({
    required String channel,
    required String id,
    required bool enabled,
  }) => _postJson(
    'userfilter_fun.php',
    data: {
      'act': 'switchs',
      'channel': channel,
      'id': id,
      'status': enabled ? 'true' : 'false',
    },
  );

  /// 删除一条规则行。
  Future<UcenterResult> deleteFilterRow({
    required String channel,
    required String id,
  }) => _postJson(
    'userfilter_fun.php',
    data: {'act': 'deldata', 'channel': channel, 'id': id},
  );

  /// 取规则编辑表单（`id` 为空表示新增）。
  ///
  /// 字段由服务端给，原生渲染后按同样的字段名回传，网站加字段也能跟上。
  Future<UcenterForm> loadFilterEditorForm({
    required String channel,
    String id = '',
  }) async {
    final result = await _postJson(
      'userfilter_fun.php',
      data: {'act': 'edit_html', 'channel': channel, 'id': id},
    );
    if (!result.ok) {
      throw Exception(
        result.message.isEmpty ? '无法打开编辑表单' : result.message,
      );
    }
    final html =
        (jsonDecode(result.raw) as Map)['html']?.toString() ?? '';
    final form = UcenterForm.parse(html);
    // 服务端片段里的令牌是随页面下发的，保存时以当前会话令牌为准。
    final token = await _ensureCsrf();
    return form.withValues({'csrfToken': token, 'channel': channel});
  }

  /// 保存规则行（字段即编辑表单回传的那些）。
  Future<UcenterResult> saveFilterRow({
    required String channel,
    required Map<String, dynamic> fields,
  }) => _postJson(
    'userfilter_fun.php',
    data: {...fields, 'channel': channel},
  );

  // -------------------------------------------------------------- 设置表单

  /// 取某个设置页视图片段里的当前值。
  ///
  /// 设置页没有 JSON 读接口，当前值就渲染在片段里（`value=` / `checked`）。
  Future<Map<String, String>> fetchSettingsValues({
    required String view,
    required Iterable<String> names,
  }) async {
    final html = await _client.postUcenterView(view);
    return readValues(html, names);
  }

  /// 保存设置页（`shezhi_fun.php?type=<filter>`）。
  Future<UcenterResult> saveSettings({
    required String type,
    required Map<String, dynamic> fields,
  }) async {
    final token = await _ensureCsrf();
    final body = await _client.postUcenterJson(
      'shezhi_fun.php',
      query: {'type': type, 'csrfToken': token},
      data: fields,
    );
    return UcenterResult.fromText(body);
  }

  /// 取某个设置页的完整表单（字段、选项、当前值都在视图片段里）。
  Future<UcenterForm> fetchSettingsForm(String view) async {
    final html = await _client.postUcenterView(view);
    if (ucenterSessionExpired(html)) {
      throw Exception(kUcenterSessionExpiredMessage);
    }
    return UcenterForm.parse(html);
  }

  // ---------------------------------------------------------------- 资料

  /// 保存基本资料（`Get.php act=postdata`）。
  Future<UcenterResult> saveProfile(Map<String, String> fields) =>
      _postJson('Get.php', data: {...fields, 'act': 'postdata'});

  /// 可选头像列表（`Get.php act=UserImgList` 返回一段 `<li><img>`）。
  Future<List<UcenterAvatarOption>> fetchAvatarOptions() async {
    final result = await _postJson('Get.php', data: {'act': 'UserImgList'});
    if (!result.ok) return const <UcenterAvatarOption>[];
    final html = (jsonDecode(result.raw) as Map)['html']?.toString() ?? '';
    final document = html_parser.parse(html);
    final options = <UcenterAvatarOption>[];
    for (final item in document.querySelectorAll('li')) {
      final src = item.querySelector('img')?.attributes['src']?.trim() ?? '';
      if (src.isEmpty) continue;
      options.add(
        UcenterAvatarOption(
          url: src,
          selected: (item.attributes['class'] ?? '').contains('on'),
        ),
      );
    }
    return options;
  }

  /// 换头像（`Get.php act=UserImgSave`）。
  Future<UcenterResult> saveAvatar(String url) =>
      _postJson('Get.php', data: {'act': 'UserImgSave', 'url': url});

  /// 重置密码（`Get.php act=newpassword`）。
  Future<UcenterResult> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) => _postJson(
    'Get.php',
    data: {
      'act': 'newpassword',
      'pass': oldPassword,
      'newpass': newPassword,
      'newpass_s': confirmPassword,
    },
  );

  /// 绑定邮箱第一步：给该邮箱发 6 位验证码。
  Future<UcenterResult> requestBindEmail(String email) =>
      _postJson('Get.php', data: {'act': 'bangemail_isemail', 'email': email});

  /// 绑定邮箱第二步：提交验证码。
  Future<UcenterResult> confirmBindEmail(String code) =>
      _postJson('Get.php', data: {'act': 'bangemail_vfcode', 'emailvfcode': code});

  /// 解绑邮箱第一步：给已绑定的邮箱发验证码。
  Future<UcenterResult> requestUnbindEmail() =>
      _postJson('Get.php', data: {'act': 'Jieemail_isemail'});

  /// 解绑邮箱第二步：提交验证码。
  Future<UcenterResult> confirmUnbindEmail(String code) =>
      _postJson('Get.php', data: {'act': 'Jieemail_vfcode', 'code': code});

  /// 当前绑定的邮箱（从「认证绑定」页片段里读）。
  Future<String> fetchBoundEmail() async {
    final html = await _client.postUcenterView('Databangding');
    final span = html_parser
        .parse(html)
        .querySelector('#emailnamespan')
        ?.text
        .trim();
    return span ?? '';
  }

  /// 拉一个服务端渲染页面片段里的表格（流水账单这类没有 JSON 接口的页面）。
  Future<List<UcenterFragmentTable>> fetchFragmentTables(String view) async {
    final html = await fetchViewOrThrow(view);
    return parseFragmentTables(html);
  }
}

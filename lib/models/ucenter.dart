import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 用户中心的数据模型。
///
/// 2026-11-25 网站改版后：首页统计来自 `Get.php act=IndexBoard` 的 JSON，
/// 头像 / 昵称 / 等级 / 会员状态来自壳页 `window.__UC_BOOT__.user`；旧的
/// `views/index.php` / `views/Nav.php` 片段解析只作为兼容保留（网站已移除
/// 这些片段，见 [UcenterHome.parse] / [parseUcenterProfile]）。
class UcenterStat {
  /// 卡片标题，线上是「账号级别」「积分」「收藏文章」「评论总数」。
  final String label;

  /// 卡片数值（等级是文案，如「注册用户」）。
  final String value;

  const UcenterStat({required this.label, required this.value});

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  factory UcenterStat.fromJson(Map<String, dynamic> json) => UcenterStat(
    label: json['label']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
  );
}

/// 用户中心首页看板（`POST json/Get.php`，`act=IndexBoard`）。
///
/// 2026-11-25 网站把用户中心换成 Vue 单页应用后，首页不再有
/// `views/index.php` 片段，改由这个 JSON 接口下发：积分、收藏数、评论数、
/// 今日签到状态、待办、推荐与登录记录。
class UcenterBoard {
  final int points;
  final int collectCount;
  final int commentCount;
  final bool signed;
  final String notice;
  final List<UcenterBoardTui> tui;

  const UcenterBoard({
    this.points = 0,
    this.collectCount = 0,
    this.commentCount = 0,
    this.signed = false,
    this.notice = '',
    this.tui = const <UcenterBoardTui>[],
  });

  factory UcenterBoard.fromJson(Map<String, dynamic> data) {
    final tui = <UcenterBoardTui>[];
    final list = data['tui'];
    if (list is List) {
      for (final item in list.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final title = map['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        tui.add(
          UcenterBoardTui(
            title: title,
            url: map['url']?.toString() ?? '',
            time: map['time']?.toString() ?? '',
          ),
        );
      }
    }
    return UcenterBoard(
      points: _intValue(data['giod']),
      collectCount: _intValue(data['coll_count']),
      commentCount: _intValue(data['comment_count']),
      signed: _intValue(data['signed']) == 1,
      notice: data['notice']?.toString() ?? '',
      tui: tui,
    );
  }
}

/// 首页看板里的推荐条目（`data.tui[]`）。
class UcenterBoardTui {
  final String title;
  final String url;
  final String time;

  const UcenterBoardTui({
    required this.title,
    this.url = '',
    this.time = '',
  });
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  final text = '${value ?? ''}'.replaceAll(',', '').trim();
  return int.tryParse(text) ?? 0;
}

class UcenterHome {
  /// 首页四张统计卡片，按线上顺序。
  final List<UcenterStat> stats;

  /// 网站公告（HTML 片段文本，取纯文本展示）。
  final String announcement;

  /// 会话过期：网站对未登录请求返回「温馨提示：您的登陆已到期」片段，
  /// 没有这个标记的页面才当作正常数据。
  final bool sessionExpired;

  const UcenterHome({
    this.stats = const <UcenterStat>[],
    this.announcement = '',
    this.sessionExpired = false,
  });

  static const UcenterHome empty = UcenterHome();

  /// 由 `Get.php act=IndexBoard` 的看板数据构造首页统计。
  ///
  /// 卡片标题沿用旧版（`账号级别` / `积分` / `收藏文章` / `评论总数`），
  /// [UcenterHome.statValue] 仍按前缀取值，页面不用改。
  factory UcenterHome.fromBoard(
    UcenterBoard board, {
    UcenterProfile profile = UcenterProfile.empty,
  }) {
    final stats = <UcenterStat>[
      if (profile.levelText.isNotEmpty)
        UcenterStat(label: '账号级别', value: profile.levelText),
      UcenterStat(label: '积分', value: '${board.points}'),
      UcenterStat(label: '收藏文章', value: '${board.collectCount}'),
      UcenterStat(label: '评论总数', value: '${board.commentCount}'),
    ];
    return UcenterHome(stats: stats, announcement: board.notice);
  }

  /// 按标题取统计值，取不到返回空串。
  ///
  /// 线上标题带后缀冒号（`账号级别：`），这里按前缀匹配，标题措辞微调也不影响。
  String statValue(String labelPrefix) {
    for (final stat in stats) {
      if (stat.label.startsWith(labelPrefix)) return stat.value;
    }
    return '';
  }

  String get level => statValue('账号级别');
  String get points => statValue('积分');
  String get collects => statValue('收藏文章');
  String get comments => statValue('评论总数');

  /// 解析 `views/index.php` 的响应。
  ///
  /// 每张卡片形如：
  /// ```html
  /// <div class="layui-card">
  ///   <div class="layui-card-header">积分：<span…><a lay-href="Pay">充值</a></span></div>
  ///   <div class="layui-card-body layuiadmin-card-list">
  ///     <p class="layuiadmin-big-font level">668</p>
  ///   </div>
  /// </div>
  /// ```
  factory UcenterHome.parse(String html) {
    final document = html_parser.parse(html);
    final expired = ucenterSessionExpired(html);
    if (expired) return const UcenterHome(sessionExpired: true);

    final stats = <UcenterStat>[];
    for (final card in document.querySelectorAll('.layui-card')) {
      final header = card.querySelector('.layui-card-header')?.text.trim() ?? '';
      // 统计卡片标题形如「账号级别：<span>购买会员</span>」——标签取冒号前那一段；
      // 公告、待办这类卡片没有冒号，不算统计。
      final colon = header.contains('：')
          ? header.indexOf('：')
          : header.indexOf(':');
      if (colon <= 0) continue;
      final label = header.substring(0, colon).trim();
      final value =
          card.querySelector('p.layuiadmin-big-font')?.text.trim() ??
          card.querySelector('.layui-card-body')?.text.trim() ??
          '';
      if (label.isEmpty || value.isEmpty) continue;
      stats.add(UcenterStat(label: label, value: value));
    }

    final announcement =
        document.querySelector('.gonggao')?.text.trim() ?? '';
    return UcenterHome(stats: stats, announcement: announcement);
  }
}

class UcenterProfile {
  /// 昵称（导航里 `<p><span class="viple0 viple">注册用户</span>芸芸众生</p>`）。
  final String nickname;

  /// 等级文案（同上 span），另带 `viple0` 里的等级序号用于配色。
  final String levelText;
  final int? levelIndex;

  /// 头像地址，取不到时为空串（页面显示占位图标）。
  final String avatarUrl;

  /// 用户 id（壳页 `__UC_BOOT__.user.id`）。
  final int? id;

  /// 是否 VIP（`user.isvip == 1`）。
  final bool isVip;

  /// VIP 到期时间（壳页原样文案，可能为空）。
  final String vipExpire;

  const UcenterProfile({
    this.nickname = '',
    this.levelText = '',
    this.levelIndex,
    this.avatarUrl = '',
    this.id,
    this.isVip = false,
    this.vipExpire = '',
  });

  static const UcenterProfile empty = UcenterProfile();

  /// 由新版壳页 `window.__UC_BOOT__.user` 构造。
  ///
  /// `levelName` 是普通等级（如「评论者」），`vipLevelName` 是会员等级
  /// （如「注册用户」）；页面只展示一个徽标，优先会员等级，没有就退回普通等级。
  factory UcenterProfile.fromBoot(Map<String, dynamic> user) {
    final levelName = user['levelName']?.toString().trim() ?? '';
    final vipLevelName = user['vipLevelName']?.toString().trim() ?? '';
    final level = user['level'];
    return UcenterProfile(
      nickname: user['name']?.toString().trim() ?? '',
      levelText: vipLevelName.isNotEmpty ? vipLevelName : levelName,
      levelIndex: level is num ? level.toInt() : int.tryParse('$level'),
      avatarUrl: user['avatar']?.toString().trim() ?? '',
      id: user['id'] is num
          ? (user['id'] as num).toInt()
          : int.tryParse('${user['id'] ?? ''}'),
      isVip: _intValue(user['isvip']) == 1,
      vipExpire: user['vipExpire']?.toString() ?? '',
    );
  }
}

/// 解析 `views/Nav.php` 的响应（用户中心侧栏/顶栏片段）。
UcenterProfile parseUcenterProfile(String html) {
  final document = html_parser.parse(html);
  final avatar =
      document.querySelector('img.nav-avatar')?.attributes['src']?.trim() ??
      '';

  final userNav = document.querySelector('.usernav');
  String nickname = '';
  String levelText = '';
  int? levelIndex;

  if (userNav != null) {
    final badge = userNav.querySelector('span[class*=viple]');
    if (badge != null) {
      levelText = badge.text.trim();
      final match = RegExp(r'viple(\d+)').firstMatch(
        badge.attributes['class'] ?? '',
      );
      if (match != null) levelIndex = int.tryParse(match.group(1)!);
    }
    final nameParagraph = _firstParagraph(userNav);
    if (nameParagraph != null) {
      final text = nameParagraph.text.trim();
      nickname = levelText.isNotEmpty && text.startsWith(levelText)
          ? text.substring(levelText.length).trim()
          : text;
    }
  }

  return UcenterProfile(
    nickname: nickname,
    levelText: levelText,
    levelIndex: levelIndex,
    avatarUrl: avatar,
  );
}

/// 新版用户中心壳页（`GET /Ucenter`）内联的启动数据。
///
/// 2026-11-25 起用户中心是 Vue 单页应用，头像/昵称/等级/会员状态不再由
/// `views/Nav.php` 片段下发，而是在壳页里写一份
/// `window.__UC_BOOT__ = {host, guest, user, csrf, cfg, menuUser…}`。
class UcenterBoot {
  final String host;
  final bool guest;
  final String csrf;
  final Map<String, dynamic>? user;
  final Map<String, dynamic> cfg;

  const UcenterBoot({
    this.host = '',
    this.guest = true,
    this.csrf = '',
    this.user,
    this.cfg = const <String, dynamic>{},
  });

  /// 从壳页 HTML 里截出 `__UC_BOOT__` 的 JSON 并解析；找不到返回 null
  /// （未登录时 `/Ucenter` 会 302 到登录页，页面里没有这段数据）。
  static UcenterBoot? parse(String html) {
    final marker = html.indexOf('__UC_BOOT__');
    if (marker < 0) return null;
    final start = html.indexOf('{', marker);
    if (start < 0) return null;
    final json = _readJsonObject(html, start);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final user = map['user'];
      final cfg = map['cfg'];
      return UcenterBoot(
        host: map['host']?.toString() ?? '',
        guest: map['guest'] == true,
        csrf: map['csrf']?.toString() ?? '',
        user: user is Map ? Map<String, dynamic>.from(user) : null,
        cfg: cfg is Map
            ? Map<String, dynamic>.from(cfg)
            : const <String, dynamic>{},
      );
    } on FormatException {
      return null;
    }
  }
}

/// 从 [start] 处的 `{` 开始，按括号配对截出一段完整 JSON（跳过字符串里的括号）。
String? _readJsonObject(String source, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return null;
}

/// 掉登录时统一提示的文案（`friendlyErrorMessage` 会原样展示中文消息）。
const String kUcenterSessionExpiredMessage = '登录状态已失效，请重新登录';

/// 未登录/会话过期时，用户中心的服务端片段会回一段「温馨提示：您的登陆已到期」，
/// 而不是 4xx。识别它，才能把「掉登录」和「页面没数据」区分开。
bool ucenterSessionExpired(String html) {
  if (html.contains('posttips')) return true;
  return html.contains('登陆已到期') || html.contains('登录已到期');
}

dom.Element? _firstParagraph(dom.Element root) {
  for (final element in root.querySelectorAll('p')) {
    if (element.querySelector('[class*=viple]') != null) return element;
  }
  return root.querySelector('p');
}

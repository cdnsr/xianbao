import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 用户中心首页的数据：统计卡片（账号级别 / 积分 / 收藏文章 / 评论总数）、公告，
/// 以及导航片段里的头像、昵称、等级标识。
///
/// 网站用户中心是 layui SPA，首页与导航都是服务端渲染的 HTML 片段
/// （`POST …/mochu_us/src/views/{index,Nav}.php`），没有 JSON 接口，所以这里
/// 按线上真实片段的结构解析。片段结构变了要跟着调，夹具取自线上响应。
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

  const UcenterProfile({
    this.nickname = '',
    this.levelText = '',
    this.levelIndex,
    this.avatarUrl = '',
  });

  static const UcenterProfile empty = UcenterProfile();
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

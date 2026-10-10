import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 用户中心分页表格（`POST …/mochu_us/json/List.php`）的响应模型。
///
/// 网站用 layui table：请求体是 `{csrfToken, act, page, limit}`（部分 act 另有参数），
/// 响应是 `{code, msg, count, data[]}`，`code == 1001` 表示没登录（带 `href` 跳转）。
/// 行的字段名就是网站表格的 `field`（`Title`/`Centenr`/`Status`…），值是允许带 HTML
/// 的字符串，所以两种都留着：`cells` 是去标签后的纯文本，`raw` 是原样文本。
class UcenterTableRow {
  final Map<String, String> cells;
  final Map<String, String> raw;

  const UcenterTableRow({required this.cells, required this.raw});

  String cell(String key) => cells[key] ?? '';

  /// 标题列里的文章链接（`<a href="/haodan/123.html">…</a>`），没有则 null。
  String? get articleUrl {
    for (final entry in raw.entries) {
      final html = entry.value;
      if (!html.contains('<a ')) continue;
      final href = RegExp(
        r'''href=["']([^"']+)["']''',
      ).firstMatch(html)?.group(1);
      if (href != null && href.isNotEmpty && href != '#') return href;
    }
    return null;
  }

  /// 操作列里内联 JS 调用的记录 id：`del_coll('123')` / `del_gongdan('123')` 等。
  ///
  /// 服务端把 id 直接写在操作列 HTML 里，没有独立的 id 字段，所以按 JS 参数提取。
  String? get actionId {
    final html = raw.values.firstWhere(
      (value) => value.contains("('") || value.contains('("'),
      orElse: () => '',
    );
    if (html.isEmpty) return null;
    final match = RegExp(r"""\(['"](\d+)['"]\)""").firstMatch(html);
    return match?.group(1);
  }

  factory UcenterTableRow.fromMap(Map<String, dynamic> map) {
    final raw = <String, String>{};
    final cells = <String, String>{};
    map.forEach((key, value) {
      final text = value?.toString() ?? '';
      raw[key] = text;
      cells[key] = _stripHtml(text);
    });
    return UcenterTableRow(cells: cells, raw: raw);
  }
}

/// 一页表格数据；[needLogin] 为真表示会话失效（服务端 code 1001）。
class UcenterTablePage {
  final int total;
  final List<UcenterTableRow> rows;
  final String message;
  final bool needLogin;

  const UcenterTablePage({
    this.total = 0,
    this.rows = const <UcenterTableRow>[],
    this.message = '',
    this.needLogin = false,
  });

  static const UcenterTablePage empty = UcenterTablePage();

  factory UcenterTablePage.fromJson(String body) {
    if (body.trim().isEmpty) return UcenterTablePage.empty;
    final decoded = jsonDecode(body);
    if (decoded is! Map) return UcenterTablePage.empty;
    final code = decoded['code'];
    final needLogin = code == 1001 || code == '1001';
    final list = decoded['data'] is List
        ? (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => UcenterTableRow.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : <UcenterTableRow>[];
    final total = (decoded['count'] as num?)?.toInt() ?? list.length;
    return UcenterTablePage(
      total: total,
      rows: needLogin ? const <UcenterTableRow>[] : list,
      message: decoded['msg']?.toString() ?? '',
      needLogin: needLogin,
    );
  }
}

/// 列表页的一列。
class UcenterColumn {
  final String key;
  final String label;

  /// 主行文案（标题类），移动端列表用它做大字。
  final bool primary;

  const UcenterColumn(this.key, this.label, {this.primary = false});
}

/// 行尾操作。
enum UcenterRowAction {
  none,

  /// 评论管理：删除（`Get.php act=commDel`）。
  deleteComment,

  /// 工单：关闭（`Get.php act=GongDanClose`）。
  closeTicket,

  /// 收藏：取消收藏（`Get.php act=CollDel`）。
  deleteCollect,
}

/// 一个列表页的接口与展示定义。
class UcenterListSpec {
  /// `List.php` 的 `act`。
  final String act;

  final String title;
  final String emptyText;

  /// 额外请求参数（如收藏的 `group`）。
  final Map<String, String> extraParams;

  final List<UcenterColumn> columns;
  final UcenterRowAction action;

  const UcenterListSpec({
    required this.act,
    required this.title,
    required this.emptyText,
    this.extraParams = const {},
    required this.columns,
    this.action = UcenterRowAction.none,
  });
}

/// 各列表页的定义（列名取自线上 `views/*.php` 里的 layui 表格 `field`）。
const Map<String, UcenterListSpec> ucenterListSpecs = {
  'comments': UcenterListSpec(
    act: 'CommentList',
    title: '评论管理',
    emptyText: '暂无评论',
    columns: [
      UcenterColumn('Centenr', '评论内容', primary: true),
      UcenterColumn('Laiyuan', '评论来源'),
      UcenterColumn('Satus', '状态'),
      UcenterColumn('Posttime', '评论时间'),
    ],
    action: UcenterRowAction.deleteComment,
  ),
  'tickets': UcenterListSpec(
    act: 'GongDanList',
    title: '工单系统',
    emptyText: '暂无工单',
    columns: [
      UcenterColumn('Title', '工单标题', primary: true),
      UcenterColumn('Type', '类型'),
      UcenterColumn('Status', '状态'),
      UcenterColumn('Time', '提交时间'),
    ],
    action: UcenterRowAction.closeTicket,
  ),
  'orders': UcenterListSpec(
    act: 'BuyPostList',
    title: '已购订单',
    emptyText: '暂无订单',
    columns: [
      UcenterColumn('Title', '标题', primary: true),
      UcenterColumn('Nber', '查询单号'),
      UcenterColumn('Ord', '交易类型'),
      UcenterColumn('Moy', '交易金额'),
      UcenterColumn('Time', '交易时间'),
    ],
  ),
  'notices': UcenterListSpec(
    act: 'TongZhiXiList',
    title: '系统通知',
    emptyText: '暂无通知',
    columns: [
      UcenterColumn('Title', '标题', primary: true),
      UcenterColumn('lei', '类型'),
      UcenterColumn('state', '状态'),
      UcenterColumn('Time', '时间'),
    ],
  ),
};

/// 去掉片段里的标签，取出用于列表展示的纯文本。
String _stripHtml(String input) {
  if (!input.contains('<')) return input.trim();
  final text = html_parser.parse(input).documentElement?.text ?? '';
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 服务端渲染片段里的表格（流水账单这类没有 JSON 接口的页面）。
///
/// 表头从 `<th>`（没有则取首行 `<td>`）读，行从 `<tbody><tr>` 读；多张表按出现顺序
/// 返回，表头为空的表会被跳过。
class UcenterFragmentTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  const UcenterFragmentTable({
    this.title = '',
    this.headers = const <String>[],
    this.rows = const <List<String>>[],
  });

  bool get isEmpty => rows.isEmpty;
}

/// 解析片段里的所有表格。
List<UcenterFragmentTable> parseFragmentTables(String html) {
  final document = html_parser.parse(html);
  final tables = <UcenterFragmentTable>[];

  for (final table in document.querySelectorAll('table')) {
    List<String> headers = [];
    final headRow = table.querySelector('thead tr');
    if (headRow != null) {
      headers = headRow
          .querySelectorAll('th,td')
          .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toList();
    }

    final rows = <List<String>>[];
    for (final tr in table.querySelectorAll('tbody tr')) {
      final cells = tr
          .querySelectorAll('td')
          .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toList();
      if (cells.isEmpty) continue;
      if (headers.isEmpty) {
        // 没有 thead 时把首行当表头。
        headers = cells;
        continue;
      }
      rows.add(cells);
    }

    if (headers.isEmpty) continue;
    // 表格标题：向上找所属卡片里的 `.layui-card-header`。
    tables.add(
      UcenterFragmentTable(
        title: _cardHeaderOf(table) ?? '',
        headers: headers,
        rows: rows,
      ),
    );
  }
  return tables;
}

/// 向上找所属 `.layui-card` 的标题（片段没有卡片结构时返回 null）。
String? _cardHeaderOf(dom.Element element) {
  dom.Element? current = element.parent;
  for (var depth = 0; current != null && depth < 6; depth++) {
    if (current.classes.contains('layui-card')) {
      final header = current
          .querySelector('.layui-card-header')
          ?.text
          .trim();
      return header == null || header.isEmpty ? null : header;
    }
    current = current.parent;
  }
  return null;
}

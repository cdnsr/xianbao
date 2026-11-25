import 'package:flutter/material.dart';

import '../../services/ucenter_service.dart';
import 'rule_rows_page.dart';
import 'ucenter_view_page.dart';

/// 一个筛选入口：规则行页（表格）或整表单页。
class _ChannelEntry {
  final String title;
  final String description;

  /// 规则行页用：接口位置。
  final UcenterFilterTarget? target;

  /// 整表单页用：新版用户中心的哈希路由。
  final String? route;

  const _ChannelEntry.rows({
    required this.title,
    required this.description,
    required UcenterFilterTarget this.target,
  }) : route = null;

  const _ChannelEntry.form({
    required this.title,
    required this.description,
    required String this.route,
  }) : target = null;
}

/// 筛选设置：各频道的规则行 / 表单 + 历史筛选数据。
///
/// 各页在网站上的实现并不一样（见 [UcenterFilterTarget]）：首页/豆瓣/微博/好单/两个
/// 全局页是规则行表格，值得买是独立端点且不带 channel，排行榜单是一张整表单。
class FilterSettingsPage extends StatelessWidget {
  const FilterSettingsPage({super.key});

  static const String _hint =
      '规则行：关键词/屏蔽词、分类词、楼主词与价格区间，行与行之间是「或」的关系。\n'
      '普通会员 1 行、单字段 ≤10 个词；VIP 15 行、参与服务端筛选的词合计 ≤300 个。';

  static const List<_ChannelEntry> _entries = [
    _ChannelEntry.rows(
      title: '首页文章筛选',
      description: '首页主列表与实时刷新',
      target: UcenterFilterTarget.shouye,
    ),
    _ChannelEntry.rows(
      title: '豆瓣分类筛选',
      description: '豆瓣线报与各子组',
      target: UcenterFilterTarget.douban,
    ),
    _ChannelEntry.rows(
      title: '微博线报筛选',
      description: '分类看中段、商城看尾段',
      target: UcenterFilterTarget.weibo,
    ),
    _ChannelEntry.rows(
      title: '好单线报筛选',
      description: '分类看中段、商城看尾段',
      target: UcenterFilterTarget.haodan,
    ),
    _ChannelEntry.rows(
      title: '值得买监控词',
      description: '值得买条目的监控词（独立接口）',
      target: UcenterFilterTarget.zhidemai,
    ),
    _ChannelEntry.form(
      title: '排行榜单筛选',
      description: '排行榜与热帖的筛选条件',
      route: 'bangdanfilter',
    ),
    _ChannelEntry.rows(
      title: '全局列表筛选（服务端）',
      description: '按范围对首页/分类页/推送统一生效',
      target: UcenterFilterTarget.global,
    ),
    _ChannelEntry.rows(
      title: '全局列表筛选（用户端）',
      description: '浏览器本地过滤，词量上限 5000',
      target: UcenterFilterTarget.globalFe,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('筛选设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final entry in _entries) ...[
            ListTile(
              title: Text(entry.title),
              subtitle: Text(entry.description),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _open(context, entry),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            title: const Text('历史筛选数据查看'),
            subtitle: const Text('历史遗留配置（只读，可复制）'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UcenterViewPage(
                  route: 'Shaixuan_history',
                  title: '历史筛选数据',
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, _ChannelEntry entry) {
    final target = entry.target;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => target != null
            ? RuleRowsPage(
                target: target,
                title: entry.title,
                hint: _hint,
              )
            : UcenterViewPage(
                route: entry.route!,
                title: entry.title,
              ),
      ),
    );
  }
}

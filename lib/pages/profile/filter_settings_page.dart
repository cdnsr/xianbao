import 'package:flutter/material.dart';

import '../../utils/external_link.dart';
import 'rule_rows_page.dart';

/// 一个筛选频道的入口定义。
class _ChannelEntry {
  final String channel;
  final String title;
  final String description;

  const _ChannelEntry({
    required this.channel,
    required this.title,
    required this.description,
  });
}

/// 筛选设置：各频道的规则行 + 历史筛选数据。
///
/// 8 个频道的规则行共用同一套接口（`userfilter_fun.php`，靠 `channel` 区分），
/// 所以原生侧也是同一个 [RuleRowsPage]；「历史筛选数据查看」点开用浏览器。
class FilterSettingsPage extends StatelessWidget {
  const FilterSettingsPage({super.key});

  static const String _hint =
      '规则行：关键词/屏蔽词、分类词、楼主词与价格区间，行与行之间是「或」的关系。\n'
      '普通会员 1 行、单字段 ≤10 个词；VIP 15 行、参与服务端筛选的词合计 ≤300 个。';

  static const List<_ChannelEntry> _entries = [
    _ChannelEntry(
      channel: 'shouye',
      title: '首页文章筛选',
      description: '首页主列表与实时刷新',
    ),
    _ChannelEntry(
      channel: 'douban',
      title: '豆瓣分类筛选',
      description: '豆瓣线报与各子组',
    ),
    _ChannelEntry(
      channel: 'weibo',
      title: '微博线报筛选',
      description: '分类看中段、商城看尾段',
    ),
    _ChannelEntry(
      channel: 'haodan',
      title: '好单线报筛选',
      description: '分类看中段、商城看尾段',
    ),
    _ChannelEntry(
      channel: 'zhidemai',
      title: '值得买监控词',
      description: '值得买条目的商城与分类',
    ),
    _ChannelEntry(
      channel: 'bangdan',
      title: '排行榜单筛选',
      description: '各排行榜与热帖',
    ),
    _ChannelEntry(
      channel: 'global',
      title: '全局列表筛选（服务端）',
      description: '按范围对首页/分类页/推送统一生效',
    ),
    _ChannelEntry(
      channel: 'globallist',
      title: '全局列表筛选（用户端）',
      description: '浏览器本地过滤，词量上限 5000',
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RuleRowsPage(
                    channel: entry.channel,
                    title: entry.title,
                    hint: _hint,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            title: const Text('历史筛选数据查看'),
            subtitle: const Text('查看被规则筛掉的内容（网站页面）'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openUcenterPage('Shaixuan_history'),
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
}

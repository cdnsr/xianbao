import 'package:flutter/material.dart';

import 'ucenter_view_page.dart';

/// 推送设置（App 内查看）。
///
/// 推送是网站的独立插件 xbpush（渠道 / 规则 / 日志 / 历史），这一轮还没原生化，
/// 但不再跳浏览器：用 App 内置的页面查看器打开，登录态会自动同步过去。
class PushSettingsPage extends StatelessWidget {
  const PushSettingsPage({super.key});

  static const List<({String label, String description, String route})> _entries =
      [
        (
          label: '推送渠道',
          description: 'Bark、钉钉、企业微信等 19 种渠道的配置',
          route: 'Shezhi_tuisong',
        ),
        (
          label: '推送规则',
          description: '推什么内容、发到哪些渠道',
          route: 'TuisongRule',
        ),
        (
          label: '推送日志',
          description: '最近 14 天的推送记录与失败原因',
          route: 'TuisongLog',
        ),
        (
          label: '历史推送数据查看',
          description: '旧版推送配置迁移',
          route: 'TuisongHistory',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('推送设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '推送设置还没原生化，下面几项在 App 内打开网站页面（已带上登录态，'
                    '右上角可切换重新加载或在浏览器打开）。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final entry in _entries)
            ListTile(
              title: Text(entry.label),
              subtitle: Text(entry.description),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UcenterViewPage(
                    route: entry.route,
                    title: entry.label,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'rule_rows_page.dart';

/// 我的关注：三个关注位各自的规则行（网站 `Shezhi_guanzhu` 的三个页签）。
class FollowSettingsPage extends StatelessWidget {
  const FollowSettingsPage({super.key});

  static const List<({String channel, String title})> _slots = [
    (channel: 'guanzhu1', title: '我的关注①'),
    (channel: 'guanzhu2', title: '我的关注②'),
    (channel: 'guanzhu3', title: '我的关注③'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的关注'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '每个关注位可以配一套召回与屏蔽规则：命中的内容才会出现在前台的「我的关注」里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const Divider(height: 1),
          for (final slot in _slots) ...[
            ListTile(
              title: Text(slot.title),
              subtitle: const Text('召回关键词、屏蔽词与楼主规则'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RuleRowsPage(
                    channel: slot.channel,
                    title: slot.title,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

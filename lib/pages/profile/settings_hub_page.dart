import 'package:flutter/material.dart';

import 'settings_form_page.dart';

/// 基本设置入口：六页设置（浏览 / 实时线报 / 顶部导航 / 摸鱼 / 自定义 CSS / JS）。
class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const order = ['jiben', 'shishi', 'daohang', 'moyu', 'css', 'js'];
    const descriptions = {
      'jiben': '标题标红、分页方式、新标签页',
      'shishi': '列表自动刷新的开关与间隔',
      'daohang': '电脑端 / 手机端顶部导航',
      'moyu': '伪装标题、图标与轮换',
      'css': '自定义 CSS 样式',
      'js': '自定义 JS 脚本',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('基本设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final key in order) ...[
            ListTile(
              title: Text(ucenterSettingsSpecs[key]!.title),
              subtitle: Text(descriptions[key] ?? ''),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsFormPage(spec: ucenterSettingsSpecs[key]!),
                ),
              ),
            ),
            const Divider(height: 1),
          ],
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
                    '带会员标记的项在服务端只对会员开放，非会员的字段会以只读形式展示。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

import 'package:flutter/material.dart';

import 'settings_form_page.dart';

/// 一组设置页的入口（基本设置六页 / 商品转链三页共用）。
class SettingsHubPage extends StatelessWidget {
  final String title;

  /// [ucenterSettingsSpecs] 里的键，按给定顺序展示。
  final List<String> keys;

  /// 底部说明，空则不显示。
  final String note;

  const SettingsHubPage({
    super.key,
    this.title = '基本设置',
    this.keys = ucenterBasicSettingsKeys,
    this.note = '带会员标记的项在服务端只对会员开放，非会员的字段会以只读形式展示。',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final key in keys)
            if (ucenterSettingsSpecs[key] != null) ...[
              ListTile(
                title: Text(ucenterSettingsSpecs[key]!.title),
                subtitle: Text(ucenterSettingsSpecs[key]!.description),
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
          if (note.isNotEmpty)
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
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
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

/// 商品转链入口。
class TransferHubPage extends StatelessWidget {
  const TransferHubPage({super.key});

  @override
  Widget build(BuildContext context) => const SettingsHubPage(
    title: '商品转链',
    keys: ucenterTransferKeys,
    note: '转链需要各平台联盟的密钥，保存后由服务端在打开文章时替换链接。',
  );
}

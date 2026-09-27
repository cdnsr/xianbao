import 'package:flutter/material.dart';

import '../services/short_link_resolver.dart';
import '../services/union_link_service.dart';

/// Opens the 京东联盟转链 settings (drawer → 京东转链).
Future<void> showUnionSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const UnionSettingsDialog(),
  );
}

/// Lets the user point the app at their own 京东联盟 link-conversion service.
///
/// Off by default: with the fields empty nothing changes, and every JD link
/// keeps behaving as it does today.
class UnionSettingsDialog extends StatefulWidget {
  const UnionSettingsDialog({super.key});

  @override
  State<UnionSettingsDialog> createState() => _UnionSettingsDialogState();
}

class _UnionSettingsDialogState extends State<UnionSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    final service = UnionLinkService.instance;
    _urlController = TextEditingController(text: service.serviceUrl);
    _tokenController = TextEditingController(text: service.token);
    _urlController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onChanged);
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final url = _urlController.text.trim();

    if (url.isNotEmpty && !url.startsWith('http')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('服务地址需要以 http 开头')),
      );
      return;
    }

    await UnionLinkService.instance.save(
      serviceUrl: url,
      token: _tokenController.text,
    );
    // Links expanded earlier this session were resolved without the service.
    ShortLinkResolver.instance.clearCache();
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(url.isEmpty ? '已关闭京东转链' : '已保存，后续还原出的商品链接会走你的联盟账号')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _urlController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('京东转链'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '填写你自己部署的京东联盟转链服务后，文章里能还原出来的京东商品链接会换成你账号的推广链。'
              '留空则不启用，行为与现在完全一致。服务端见仓库 server/jd-union/。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'https://xxx.workers.dev',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              autocorrect: false,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '口令（服务端 APP_TOKEN，可留空）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '注意：只能覆盖能还原出商品页的链接（约三分之一的京东短链），'
              '领券/活动类链接的目标是加密的，换不了。佣金是否真的记到你名下，'
              '请用一笔小额订单在自己的联盟后台确认。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(enabled ? '保存' : '关闭转链'),
        ),
      ],
    );
  }
}

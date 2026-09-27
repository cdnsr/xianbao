import 'package:flutter/material.dart';

/// Shared "could not load" state: a friendly message plus a retry action.
///
/// Used wherever a network-backed screen has nothing to show, so failures read
/// the same everywhere instead of leaking raw exception or WebView text.
class LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  final IconData icon;

  const LoadErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = '重新加载',
    this.icon = Icons.cloud_off_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

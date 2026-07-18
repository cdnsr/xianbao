import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../utils/version_compare.dart';
import 'about_dialog.dart';

/// Shared entry points for auto / manual update checks.
class UpdateCoordinator {
  UpdateCoordinator._();

  static bool _busy = false;
  static bool _dialogVisible = false;

  /// App startup auto-check (original flow): only show UpdateDialog when a
  /// newer version is available and not ignored. Fail toast ≤ once / 7 days.
  /// Manual checks use About → showUpdateCheckDialog, not this path.
  static Future<void> checkOnStartup(BuildContext context) async {
    if (_busy || _dialogVisible) return;
    _busy = true;
    final service = UpdateService();
    try {
      final result = await service.checkForUpdate();
      if (!context.mounted) return;

      if (result.status == UpdateCheckStatus.hasUpdate &&
          result.remote != null) {
        final ignored = await service.getIgnoreVersion();
        if (!context.mounted) return;
        if (ignored == result.remote!.version) return;
        await _showDialog(context, service, result, manual: false);
      } else if (result.status == UpdateCheckStatus.error) {
        final last = await service.getFailTipTime();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - last >= 7 * 24 * 60 * 60 * 1000) {
          await service.setFailTipTime(now);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('检查更新失败，请稍后在侧边栏「关于」中手动检查')),
          );
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// Manual check (e.g. About → 检查更新): use dedicated update window.
  static Future<void> checkManual(BuildContext context) async {
    if (_busy || _dialogVisible) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在检查或更新中…')),
        );
      }
      return;
    }
    await showUpdateCheckDialog(context);
  }

  static Future<void> _showDialog(
    BuildContext context,
    UpdateService service,
    UpdateCheckResult result, {
    required bool manual,
  }) async {
    if (_dialogVisible || !context.mounted) return;
    _dialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => UpdateDialog(
          service: service,
          result: result,
          allowIgnore: true,
        ),
      );
    } finally {
      _dialogVisible = false;
    }
  }
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.service,
    required this.result,
    this.allowIgnore = true,
  });

  final UpdateService service;
  final UpdateCheckResult result;
  final bool allowIgnore;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  bool _installing = false;
  double? _progress; // 0..1, null = indeterminate
  String? _error;
  String? _apkPath;

  RemoteVersionInfo get remote => widget.result.remote!;
  String get current => widget.result.currentVersion;

  List<VersionHistoryItem> get _newerHistory {
    return remote.history
        .where((h) => isVersionNewer(h.version, current))
        .toList();
  }

  @override
  void dispose() {
    if (_downloading) {
      widget.service.cancelDownload();
    }
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_downloading || _installing) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await widget.service.downloadApk(
        remote.version,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            if (total > 0) {
              _progress = received / total;
            } else {
              _progress = null;
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _apkPath = path;
        _progress = 1;
      });
      await _install(path);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _progress = null;
            _error = '已取消下载';
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = null;
          _error = '下载失败：$e';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = null;
          _error = '下载失败：$e';
        });
      }
    }
  }

  Future<void> _install(String path) async {
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await widget.service.installApk(path);
      if (mounted) {
        setState(() => _installing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _ignore() async {
    await widget.service.setIgnoreVersion(remote.version);
    if (mounted) Navigator.of(context).pop();
  }

  String _formatPercent() {
    final p = _progress;
    if (p == null) return '下载中…';
    return '下载中 ${(p * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = _newerHistory;

    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '最新版本：${remote.version}',
                style: theme.textTheme.titleSmall,
              ),
              Text(
                '当前版本：$current',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text('更新说明', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(
                remote.desc.isEmpty ? '（无说明）' : remote.desc,
                style: theme.textTheme.bodyMedium,
              ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('历史更新', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final item in history) ...[
                  Text(
                    'v${item.version}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    item.desc.isEmpty ? '（无说明）' : item.desc,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (_downloading || _progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  _installing ? '正在调起安装…' : _formatPercent(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowIgnore && !_downloading && !_installing)
          TextButton(
            onPressed: _ignore,
            child: const Text('忽略此版本'),
          ),
        TextButton(
          onPressed: _downloading
              ? () {
                  widget.service.cancelDownload();
                }
              : () => Navigator.of(context).pop(),
          child: Text(_downloading ? '取消下载' : '稍后再说'),
        ),
        FilledButton(
          onPressed: (_downloading || _installing)
              ? null
              : () {
                  if (_apkPath != null) {
                    _install(_apkPath!);
                  } else {
                    _startDownload();
                  }
                },
          child: Text(
            _installing
                ? '安装中…'
                : (_apkPath != null ? '重新安装' : '立即更新'),
          ),
        ),
      ],
    );
  }
}
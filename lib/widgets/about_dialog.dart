import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update_service.dart';
import '../utils/version_compare.dart';

/// About panel similar to the product screenshot (drawer → 关于).
Future<void> showAboutAppDialog(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AboutAppDialog(packageInfo: info),
  );
}

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key, required this.packageInfo});

  final PackageInfo packageInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = packageInfo.version;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.local_offer_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '线报酷',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '版本 $version',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '线报信息聚合客户端',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showUpdateCheckDialog(context);
                },
                icon: const Icon(Icons.system_update_alt, size: 20),
                label: const Text('检查更新'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Update window similar to screen2: checking / latest / has-update.
Future<void> showUpdateCheckDialog(
  BuildContext context, {
  bool autoStartCheck = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => UpdateCheckDialog(autoStartCheck: autoStartCheck),
  );
}

class UpdateCheckDialog extends StatefulWidget {
  const UpdateCheckDialog({super.key, this.autoStartCheck = true});

  final bool autoStartCheck;

  @override
  State<UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<UpdateCheckDialog> {
  final UpdateService _service = UpdateService();

  bool _checking = true;
  bool _downloading = false;
  bool _installing = false;
  double? _progress;
  String? _error;
  String? _apkPath;
  UpdateCheckResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
    }
  }

  @override
  void dispose() {
    if (_downloading) {
      _service.cancelDownload();
    }
    super.dispose();
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
      _apkPath = null;
      _progress = null;
    });
    final result = await _service.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
      if (result.status == UpdateCheckStatus.error) {
        _error = result.errorMessage ?? '检查更新失败';
      }
    });
  }

  Future<void> _startDownload() async {
    final remote = _result?.remote;
    if (remote == null || _downloading || _installing) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await _service.downloadApk(
        remote.version,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : null;
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
      await _service.installApk(path);
      if (mounted) setState(() => _installing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = e.toString();
        });
      }
    }
  }

  String _percentText() {
    final p = _progress;
    if (p == null) return '下载中…';
    return '下载中 ${(p * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final hasUpdate = result?.status == UpdateCheckStatus.hasUpdate;
    final upToDate = result?.status == UpdateCheckStatus.upToDate;
    final remote = result?.remote;
    final current = result?.currentVersion ?? '';

    final history = <VersionHistoryItem>[];
    if (hasUpdate && remote != null) {
      for (final h in remote.history) {
        if (isVersionNewer(h.version, current)) history.add(h);
      }
    }

    String title;
    if (_checking) {
      title = '检查更新';
    } else if (hasUpdate) {
      title = '发现新版本';
    } else if (upToDate) {
      title = '检查更新';
    } else {
      title = '检查更新';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_alt, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildBody(
                    theme: theme,
                    hasUpdate: hasUpdate,
                    upToDate: upToDate,
                    remote: remote,
                    current: current,
                    history: history,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                ),
              ],
              if (_downloading || _progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  _installing ? '正在调起安装…' : _percentText(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              _buildActions(
                hasUpdate: hasUpdate,
                upToDate: upToDate,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required ThemeData theme,
    required bool hasUpdate,
    required bool upToDate,
    required RemoteVersionInfo? remote,
    required String current,
    required List<VersionHistoryItem> history,
  }) {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检查更新…'),
          ],
        ),
      );
    }

    if (hasUpdate && remote != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(theme, '最新版本', remote.version),
          _infoRow(theme, '当前版本', current),
          const SizedBox(height: 12),
          Text('更新说明', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(
            remote.desc.isEmpty ? '（无说明）' : remote.desc,
            style: theme.textTheme.bodyMedium,
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('历史更新', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in history) ...[
              Text('v${item.version}', style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              SelectableText(
                item.desc.isEmpty ? '（无说明）' : item.desc,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      );
    }

    if (upToDate) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '当前已是最新版本',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '版本 $current',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // error
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text('检查更新失败', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            _error ?? '请稍后重试',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label：',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions({
    required bool hasUpdate,
    required bool upToDate,
  }) {
    if (_checking) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      );
    }

    // No update or error → only Close (and retry on error)
    if (!hasUpdate) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_result?.status == UpdateCheckStatus.error)
            TextButton(
              onPressed: _runCheck,
              child: const Text('重试'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    // Has update → Close + Update
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_downloading)
          TextButton(
            onPressed: () => _service.cancelDownload(),
            child: const Text('取消下载'),
          )
        else
          TextButton(
            onPressed: (_installing) ? null : () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        const SizedBox(width: 8),
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
                : (_apkPath != null ? '重新安装' : '更新'),
          ),
        ),
      ],
    );
  }
}
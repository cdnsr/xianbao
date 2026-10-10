import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/http_client.dart';

/// 站内图片（文章正文图、用户头像等）。
///
/// 站点对图片有防盗链，直接用 `Image.network` 会 403，所以统一走
/// [HttpClient.downloadImage]：它带站点 Referer、内存 LRU 缓存、同样的 URL 只发一次
/// 请求，并在失败时重试。加载中显示 [placeholder]，失败显示 [errorWidget]
/// （默认是一块可重试的占位）。
class RemoteImage extends StatefulWidget {
  final String url;

  /// 圆形头像用 `BoxFit.cover` + [borderRadius]；正文图用 `BoxFit.contain`。
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// 加载中占位；给 null 则显示居中的小进度圈。
  final Widget? placeholder;

  /// 失败占位；给 null 则显示默认的「图片加载失败 + 重试」。
  final Widget? errorWidget;

  const RemoteImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _loading = true;
      _failed = false;
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    } else {
      _loading = true;
      _failed = false;
    }
    if (widget.url.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    try {
      final bytes = await HttpClient().downloadImage(
        widget.url,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
        _failed = bytes.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child;
    if (_loading) {
      child =
          widget.placeholder ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    } else if (!_failed && _bytes != null && _bytes!.isNotEmpty) {
      child = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => _fallback(theme),
      );
    } else {
      child = _fallback(theme);
    }

    final radius = widget.borderRadius;
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _fallback(ThemeData theme) {
    if (widget.errorWidget != null) return widget.errorWidget!;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 24,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _load(forceRefresh: true),
              child: Text('重试', style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/http_client.dart';
import '../services/qr_code_service.dart';
import '../utils/html_utils.dart';

/// Renders article HTML as selectable native text, links, and images.
class ArticleContentView extends StatelessWidget {
  final String contentHtml;

  const ArticleContentView({super.key, required this.contentHtml});

  @override
  Widget build(BuildContext context) {
    final segments = HtmlUtils.parseContent(contentHtml);
    final children = <Widget>[];
    final inlineSegments = <ContentSegment>[];

    void flushInlineSegments() {
      if (inlineSegments.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _SelectableContent(segments: List.of(inlineSegments)),
        ),
      );
      inlineSegments.clear();
    }

    for (final segment in segments) {
      if (segment.type == ContentSegmentType.image) {
        flushInlineSegments();
        children.add(_ArticleImage(url: segment.url!));
      } else {
        inlineSegments.add(segment);
      }
    }
    flushInlineSegments();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _SelectableContent extends StatefulWidget {
  final List<ContentSegment> segments;

  const _SelectableContent({required this.segments});

  @override
  State<_SelectableContent> createState() => _SelectableContentState();
}

class _SelectableContentState extends State<_SelectableContent> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant _SelectableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final normalStyle = theme.textTheme.bodyMedium;
    final linkStyle = normalStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final spans = <InlineSpan>[];

    for (final segment in widget.segments) {
      switch (segment.type) {
        case ContentSegmentType.link:
          final recognizer = TapGestureRecognizer()
            ..onTap = () => _openExternalUrl(context, segment.url!);
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: segment.content,
              style: linkStyle,
              recognizer: recognizer,
            ),
          );
        case ContentSegmentType.emoji:
          final emojiSize = (normalStyle?.fontSize ?? 14) + 6;
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _InlineEmojiImage(url: segment.url!, size: emojiSize),
              ),
            ),
          );
        case ContentSegmentType.text:
          spans.add(TextSpan(text: segment.content, style: normalStyle));
        case ContentSegmentType.image:
          // Block images are handled outside selectable text.
          break;
      }
    }

    return SelectableText.rich(TextSpan(children: spans));
  }
}

/// Small inline forum smiley/emoji image, sized like surrounding text.
class _InlineEmojiImage extends StatefulWidget {
  final String url;
  final double size;

  const _InlineEmojiImage({required this.url, required this.size});

  @override
  State<_InlineEmojiImage> createState() => _InlineEmojiImageState();
}

class _InlineEmojiImageState extends State<_InlineEmojiImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _InlineEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await HttpClient().downloadImage(widget.url);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _failed = bytes.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (_failed) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.emoji_emotions_outlined, size: size * 0.9),
      );
    }
    if (_bytes == null) {
      return SizedBox(width: size, height: size);
    }
    return Image.memory(
      _bytes!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        return Icon(Icons.emoji_emotions_outlined, size: size * 0.9);
      },
    );
  }
}

class _ArticleImage extends StatelessWidget {
  final String url;

  const _ArticleImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _showFullScreenImage(context, url),
        onLongPress: () => _showImageActions(context, url),
        // Prefer Dio so Referer/User-Agent match the website and anti-hotlink works.
        child: _DioImage(url: url, height: 200),
      ),
    );
  }
}

void _showFullScreenImage(BuildContext context, String url) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _FullScreenImagePage(url: url),
      fullscreenDialog: true,
    ),
  );
}

void _showImageActions(BuildContext context, String url) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('解析当前二维码'),
            onTap: () {
              Navigator.pop(sheetContext);
              _recognizeQrCode(context, url);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('保存图片到相册'),
            onTap: () {
              Navigator.pop(sheetContext);
              _saveImage(context, url);
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility),
            title: const Text('查看大图'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showFullScreenImage(context, url);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('没有可用的浏览器');
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('无法打开链接: $error')));
  }
}

Future<void> _recognizeQrCode(BuildContext context, String url) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('正在解析二维码...')),
          ],
        ),
      ),
    ),
  );

  String? result;
  Object? failure;
  try {
    final bytes = await HttpClient().downloadImage(url);
    result = await QrCodeService.decode(bytes);
  } catch (error) {
    failure = error;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (failure != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('二维码解析失败: $failure')));
    return;
  }
  if (result == null || result.trim().isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('未识别到二维码')));
    return;
  }
  await _showQrResult(context, result);
}

Future<void> _showQrResult(BuildContext context, String result) async {
  final uri = Uri.tryParse(result.trim());
  final canOpen =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('二维码解析结果'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(child: SelectableText(result)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: result));
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制解析结果')));
          },
          child: const Text('复制'),
        ),
        if (canOpen)
          TextButton(
            onPressed: () => _openExternalUrl(context, result.trim()),
            child: const Text('打开链接'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> _saveImage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        messenger.showSnackBar(const SnackBar(content: Text('需要相册权限才能保存图片')));
        return;
      }
    }

    messenger.showSnackBar(const SnackBar(content: Text('正在保存图片...')));
    final bytes = await HttpClient().downloadImage(url);
    await Gal.putImageBytes(
      bytes,
      name: 'xianbao_${DateTime.now().millisecondsSinceEpoch}',
    );
    messenger.showSnackBar(const SnackBar(content: Text('图片已保存到相册')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('保存失败: $error')));
  }
}

/// Full-screen image viewer with zoom, QR recognition, and saving.
class _FullScreenImagePage extends StatelessWidget {
  final String url;

  const _FullScreenImagePage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '解析二维码',
            onPressed: () => _recognizeQrCode(context, url),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '保存',
            onPressed: () => _saveImage(context, url),
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onLongPress: () => _showImageActions(context, url),
          child: InteractiveViewer(
            child: _DioImage(url: url, height: double.infinity),
          ),
        ),
      ),
    );
  }
}

/// Fetches protected images through the shared Dio client as a fallback.
class _DioImage extends StatefulWidget {
  final String url;
  final double height;

  const _DioImage({required this.url, required this.height});

  @override
  State<_DioImage> createState() => _DioImageState();
}

class _DioImageState extends State<_DioImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DioImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _loading = true;
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
    final height = widget.height == double.infinity ? 300.0 : widget.height;
    if (_loading) {
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_failed && _bytes != null && _bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _bytes!,
          width: double.infinity,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => _buildErrorWidget(context),
        ),
      );
    }
    return _buildErrorWidget(context);
  }

  Widget _buildErrorWidget(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: widget.height == double.infinity ? 300 : widget.height,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text('图片加载失败', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

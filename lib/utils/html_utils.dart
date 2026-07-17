import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

/// Utilities for turning article HTML into native-renderable content.
class HtmlUtils {
  static const String defaultBaseUrl = 'https://new.xianbao.fun/';

  static final RegExp _plainUrlPattern = RegExp(
    r'''https?://[^\s<>"'\u201c\u201d，。；：！？、（）【】《》]+''',
    caseSensitive: false,
  );

  /// Matches forum smiley / emoji image paths (including proxied imgurl=...).
  static final RegExp _smileyPathPattern = RegExp(
    r'(?:/|^)(?:static/)?(?:image(?:s)?/)?(?:smiley|smilies|emoji|emoticon|emote|face)(?:s)?/',
    caseSensitive: false,
  );

  static const Set<String> _blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'div',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'li',
    'main',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tr',
    'ul',
  };

  static const Set<String> _ignoredTags = {
    'script',
    'style',
    'noscript',
    'template',
  };

  /// Extract plain text from an HTML fragment.
  ///
  /// Preserves plain-text URLs and appends link hrefs so 复制文案 stays usable.
  static String toPlainText(String html) {
    final segments = parseContent(html);
    final buffer = StringBuffer();
    for (final segment in segments) {
      switch (segment.type) {
        case ContentSegmentType.text:
          buffer.write(segment.content);
          break;
        case ContentSegmentType.link:
          final label = segment.content.trim();
          final url = segment.url ?? '';
          if (label.isEmpty || label == url) {
            buffer.write(url);
          } else if (url.isEmpty) {
            buffer.write(label);
          } else {
            buffer.write('$label $url');
          }
          break;
        case ContentSegmentType.image:
        case ContentSegmentType.emoji:
          break;
      }
    }
    return buffer.toString().trim();
  }

  /// Extract content image URLs (excludes smiley/emoji images).
  static List<String> extractImages(
    String html, {
    String baseUrl = defaultBaseUrl,
  }) {
    return parseContent(html, baseUrl: baseUrl)
        .where((segment) => segment.type == ContentSegmentType.image)
        .map((segment) => segment.url!)
        .toList();
  }

  /// Extract explicit HTML links and plain-text web URLs.
  static List<({String text, String url})> extractLinks(
    String html, {
    String baseUrl = defaultBaseUrl,
  }) {
    return parseContent(html, baseUrl: baseUrl)
        .where((segment) => segment.type == ContentSegmentType.link)
        .map((segment) => (text: segment.content, url: segment.url!))
        .toList();
  }

  /// Whether [url] points to a forum smiley / emoji image rather than content.
  static bool isSmileyImageUrl(String url) {
    final decoded = Uri.decodeFull(url);
    final candidates = <String>[url, decoded];

    try {
      final uri = Uri.parse(url);
      for (final value in uri.queryParameters.values) {
        candidates.add(value);
        candidates.add(Uri.decodeFull(value));
      }
    } on FormatException {
      // Keep using the raw URL only.
    }

    for (final candidate in candidates) {
      final lower = candidate.toLowerCase().replaceAll('\\', '/');
      if (_smileyPathPattern.hasMatch(lower)) return true;
      if (lower.contains('/smiley/') || lower.contains('/smilies/')) {
        return true;
      }
    }
    return false;
  }

  /// Split article HTML recursively while preserving DOM order.
  static List<ContentSegment> parseContent(
    String html, {
    String baseUrl = defaultBaseUrl,
  }) {
    final fragment = parseFragment(html);
    final baseUri = Uri.parse(baseUrl);
    final segments = <ContentSegment>[];

    void addText(String value) {
      if (value.isEmpty) return;
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
      if (normalized.isEmpty) return;

      var cursor = 0;
      for (final match in _plainUrlPattern.allMatches(normalized)) {
        final rawMatch = match.group(0)!;
        final url = _removeTrailingPunctuation(rawMatch);
        final urlEnd = match.start + url.length;

        _appendText(segments, normalized.substring(cursor, match.start));
        final resolved = _resolveWebUrl(url, baseUri);
        if (resolved == null) {
          _appendText(segments, url);
        } else {
          segments.add(ContentSegment.link(url, resolved));
        }
        cursor = urlEnd;
      }
      _appendText(segments, normalized.substring(cursor));
    }

    void addBreak() {
      if (segments.isEmpty) return;
      final last = segments.last;
      if (last.type == ContentSegmentType.text && last.content.endsWith('\n')) {
        return;
      }
      _appendText(segments, '\n');
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        addText(node.data);
        return;
      }
      if (node is! dom.Element) return;

      final tag = node.localName?.toLowerCase() ?? '';
      if (_ignoredTags.contains(tag)) return;

      if (tag == 'img') {
        final source = _imageSource(node);
        final url = source == null ? null : _resolveWebUrl(source, baseUri);
        if (url != null) {
          if (isSmileyImageUrl(url) || _isTinyInlineImage(node)) {
            segments.add(ContentSegment.emoji(url));
          } else {
            segments.add(ContentSegment.image(url));
          }
        }
        return;
      }

      if (tag == 'br') {
        addBreak();
        return;
      }

      if (tag == 'a' && node.querySelector('img') == null) {
        final href = node.attributes['href'];
        final url = href == null ? null : _resolveWebUrl(href, baseUri);
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (url != null && text.isNotEmpty) {
          segments.add(ContentSegment.link(text, url));
          return;
        }
      }

      for (final child in node.nodes) {
        walk(child);
      }
      if (_blockTags.contains(tag)) addBreak();
    }

    for (final node in fragment.nodes) {
      walk(node);
    }

    return _cleanSegments(segments);
  }

  static String? _imageSource(dom.Element image) {
    for (final attribute in const ['src', 'data-src', 'data-original']) {
      final value = image.attributes[attribute]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final srcset = image.attributes['srcset']?.trim();
    if (srcset == null || srcset.isEmpty) return null;
    return srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
  }

  /// Treat explicitly tiny HTML images (e.g. width/height <= 48) as inline.
  static bool _isTinyInlineImage(dom.Element image) {
    int? parseSize(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      final match = RegExp(r'(\d+)').firstMatch(raw);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final width = parseSize(image.attributes['width']);
    final height = parseSize(image.attributes['height']);
    if (width != null && width <= 48) return true;
    if (height != null && height <= 48) return true;

    final style = image.attributes['style'] ?? '';
    final styleWidth = RegExp(
      r'width\s*:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(style);
    final styleHeight = RegExp(
      r'height\s*:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(style);
    if (styleWidth != null) {
      final value = int.tryParse(styleWidth.group(1)!);
      if (value != null && value <= 48) return true;
    }
    if (styleHeight != null) {
      final value = int.tryParse(styleHeight.group(1)!);
      if (value != null && value <= 48) return true;
    }
    return false;
  }

  static String? _resolveWebUrl(String rawUrl, Uri baseUri) {
    final value = rawUrl.trim();
    if (value.isEmpty) return null;
    try {
      final uri = baseUri.resolve(value);
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return uri.toString();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _removeTrailingPunctuation(String value) {
    const punctuation = '.,;:!?)]}，。；：！？、）】》';
    var end = value.length;
    while (end > 0 && punctuation.contains(value[end - 1])) {
      end--;
    }
    return value.substring(0, end);
  }

  static void _appendText(List<ContentSegment> segments, String text) {
    if (text.isEmpty) return;
    if (segments.isNotEmpty && segments.last.type == ContentSegmentType.text) {
      final previous = segments.removeLast();
      segments.add(ContentSegment.text(previous.content + text));
    } else {
      segments.add(ContentSegment.text(text));
    }
  }

  static List<ContentSegment> _cleanSegments(List<ContentSegment> segments) {
    if (segments.isEmpty) return const [];
    final cleaned = <ContentSegment>[];

    for (final segment in segments) {
      if (segment.type != ContentSegmentType.text) {
        cleaned.add(segment);
        continue;
      }
      final text = segment.content
          .replaceAll(RegExp(r' *\n *'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n');
      if (text.isNotEmpty) _appendText(cleaned, text);
    }

    while (cleaned.isNotEmpty &&
        cleaned.first.type == ContentSegmentType.text &&
        cleaned.first.content.trim().isEmpty) {
      cleaned.removeAt(0);
    }
    while (cleaned.isNotEmpty &&
        cleaned.last.type == ContentSegmentType.text &&
        cleaned.last.content.trim().isEmpty) {
      cleaned.removeLast();
    }
    if (cleaned.isNotEmpty && cleaned.first.type == ContentSegmentType.text) {
      final first = cleaned.removeAt(0);
      cleaned.insert(0, ContentSegment.text(first.content.trimLeft()));
    }
    if (cleaned.isNotEmpty && cleaned.last.type == ContentSegmentType.text) {
      final last = cleaned.removeLast();
      cleaned.add(ContentSegment.text(last.content.trimRight()));
    }
    return cleaned;
  }
}

enum ContentSegmentType { text, image, link, emoji }

/// A text, image, link, or inline emoji unit in article DOM order.
class ContentSegment {
  final ContentSegmentType type;
  final String content;
  final String? url;

  const ContentSegment._({required this.type, required this.content, this.url});

  factory ContentSegment.text(String text) =>
      ContentSegment._(type: ContentSegmentType.text, content: text);

  factory ContentSegment.image(String url) =>
      ContentSegment._(type: ContentSegmentType.image, content: url, url: url);

  factory ContentSegment.link(String text, String url) =>
      ContentSegment._(type: ContentSegmentType.link, content: text, url: url);

  factory ContentSegment.emoji(String url) =>
      ContentSegment._(type: ContentSegmentType.emoji, content: url, url: url);
}

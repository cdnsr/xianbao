import 'dart:convert';
import 'dart:io';

/// Normalizes cookie strings exchanged between WebView and Dio.
class CookieHeaderCodec {
  const CookieHeaderCodec._();

  /// Android WebView may return a JSON string literal, including its quotes.
  static String decodeJavaScriptResult(Object? result) {
    if (result == null) return '';

    final raw = result.toString().trim();
    if (raw.isEmpty || raw == 'null') return '';

    if (raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) return decoded;
      } on FormatException {
        // Some platforms already return the unwrapped JavaScript string.
      }
    }
    return raw;
  }

  /// Parses valid name/value pairs and drops data that Dart's HTTP stack
  /// cannot represent in a Cookie header.
  static Map<String, String> parse(String? source) {
    if (source == null) return const {};

    final decoded = decodeJavaScriptResult(source);
    final pairs = <String, String>{};
    for (final part in decoded.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;

      final name = trimmed.substring(0, separator).trim();
      final value = trimmed.substring(separator + 1).trim();
      if (isValidPair(name, value)) {
        pairs[name] = value;
      }
    }
    return pairs;
  }

  static bool isValidPair(String name, String value) {
    try {
      final parsed = Cookie.fromSetCookieValue('$name=$value');
      return parsed.name == name && parsed.value == value;
    } on FormatException {
      return false;
    } on HttpException {
      return false;
    }
  }

  static String? normalize(String? source) {
    final pairs = parse(source);
    return pairs.isEmpty ? null : build(pairs);
  }

  static String? merge(String? existing, String incoming) {
    final merged = <String, String>{...parse(existing), ...parse(incoming)};
    return merged.isEmpty ? null : build(merged);
  }

  static String build(Map<String, String> pairs) {
    return pairs.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}

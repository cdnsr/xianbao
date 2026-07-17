import 'article.dart';

/// The 11 homepage filters emitted by the website's meta.php script.
class ArticleFilterRules {
  final String blockedCategories;
  final String blockedAuthors;
  final String allowedAuthors;
  final String extraBlockedAuthors;
  final String blockedTitles;
  final String allowedTitles;
  final String extraBlockedTitles;
  final String blockedContent;
  final String allowedContent;
  final String extraBlockedContent;
  final String blockedAuthorAge;

  const ArticleFilterRules({
    this.blockedCategories = '',
    this.blockedAuthors = '',
    this.allowedAuthors = '',
    this.extraBlockedAuthors = '',
    this.blockedTitles = '',
    this.allowedTitles = '',
    this.extraBlockedTitles = '',
    this.blockedContent = '',
    this.allowedContent = '',
    this.extraBlockedContent = '',
    this.blockedAuthorAge = '',
  });

  factory ArticleFilterRules.fromMetaScript(String script) {
    var marker = 'listfilter(xindata,';
    var start = script.indexOf(marker);
    if (start < 0) {
      marker = 'liebiaoshaixuan(';
      start = script.indexOf(marker);
    }
    if (start < 0) return const ArticleFilterRules();
    final end = _findCallEnd(script, start + marker.length);
    if (end < 0) return const ArticleFilterRules();
    final source = script.substring(start + marker.length, end);
    final values = RegExp(
      r'''["']((?:\\.|[^"'])*)["']''',
    ).allMatches(source).map((match) => _unescape(match.group(1)!)).toList();
    while (values.length < 11) {
      values.add('');
    }
    return ArticleFilterRules(
      blockedCategories: values[0],
      blockedAuthors: values[1],
      allowedAuthors: values[2],
      extraBlockedAuthors: values[3],
      blockedTitles: values[4],
      allowedTitles: values[5],
      extraBlockedTitles: values[6],
      blockedContent: values[7],
      allowedContent: values[8],
      extraBlockedContent: values[9],
      blockedAuthorAge: values[10],
    );
  }

  static String _unescape(String value) => value
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\\', r'\');

  static int _findCallEnd(String source, int start) {
    String? quote;
    var escaped = false;
    for (var i = start; i < source.length; i++) {
      final char = source[i];
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == ')') {
        return i;
      }
    }
    return -1;
  }

  bool allows(ArticleListItem article) {
    if (_matches(blockedCategories, article.category) ||
        _authorAgeBlocked(article)) {
      return false;
    }
    final keepAuthor = _matchesRule(
      allowedAuthors,
      article.category,
      article.author,
    );
    if ((_matchesRule(blockedAuthors, article.category, article.author) &&
            !keepAuthor) ||
        _matchesRule(extraBlockedAuthors, article.category, article.author)) {
      return false;
    }
    final keepTitle = _matchesRule(
      allowedTitles,
      article.category,
      article.title,
    );
    if (!keepAuthor &&
        ((!keepTitle &&
                _matchesRule(blockedTitles, article.category, article.title)) ||
            _matchesRule(
              extraBlockedTitles,
              article.category,
              article.title,
            ))) {
      return false;
    }
    final keepContent = _matchesRule(
      allowedContent,
      article.category,
      article.summary,
    );
    if (!keepAuthor &&
        !keepTitle &&
        ((!keepContent &&
                _matchesRule(
                  blockedContent,
                  article.category,
                  article.summary,
                )) ||
            _matchesRule(
              extraBlockedContent,
              article.category,
              article.summary,
            ))) {
      return false;
    }
    return true;
  }

  static bool _matchesRule(String rules, String category, String value) {
    if (rules.isEmpty || value.isEmpty) return false;
    if (!rules.contains('###')) return _matches(rules, value);
    for (final rule in _splitRules(rules)) {
      final separator = rule.indexOf('###');
      if (separator < 0) continue;
      if (_matches(rule.substring(0, separator), category) &&
          _matches(rule.substring(separator + 3), value)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _splitRules(String value) => value
      .split(RegExp(r'<br\s*/?>', caseSensitive: false))
      .map((rule) => rule.trim())
      .where((rule) => rule.isNotEmpty)
      .toList();

  static bool _matches(String pattern, String value) {
    if (pattern.isEmpty || value.isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(value);
    } on FormatException {
      return value.toLowerCase().contains(pattern.toLowerCase());
    }
  }

  bool _authorAgeBlocked(ArticleListItem article) {
    final value = article.authorRegistrationTime;
    if (blockedAuthorAge.isEmpty || value == null) return false;
    final text = value.toString().trim();
    final timestamp = int.tryParse(text);
    final registeredAt = timestamp == null
        ? DateTime.tryParse(text)
        : DateTime.fromMillisecondsSinceEpoch(
            timestamp < 1000000000000 ? timestamp * 1000 : timestamp,
          );
    if (registeredAt == null) return false;
    final ageDays = DateTime.now().difference(registeredAt).inDays;
    for (final rule in _splitRules(blockedAuthorAge)) {
      final parts = rule.split('###');
      final threshold = int.tryParse(parts.last.trim());
      if (threshold == null || threshold <= ageDays) continue;
      if (parts.length == 1 || _matches(parts.first, article.category)) {
        return true;
      }
    }
    return false;
  }
}

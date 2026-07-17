import 'package:html/parser.dart';
import 'package:html/dom.dart' as dom;

/// A navigation category parsed from the website sidebar.
class CategoryItem {
  final String name;
  final String slug;
  final String url;
  final List<CategoryItem> children;

  CategoryItem({
    required this.name,
    required this.slug,
    required this.url,
    this.children = const [],
  });

  bool get isCategoryPage => url.startsWith('/category-');
  bool get hasChildren => children.isNotEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    'slug': slug,
    'url': url,
    'children': children.map((child) => child.toJson()).toList(),
  };

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    return CategoryItem(
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      url: json['url'] as String? ?? '',
      children: rawChildren is List
          ? rawChildren
                .whereType<Map>()
                .map(
                  (child) =>
                      CategoryItem.fromJson(Map<String, dynamic>.from(child)),
                )
                .toList()
          : const [],
    );
  }

  static List<CategoryItem> parseCategories(String html) {
    final document = parse(html);
    final navUl = document.querySelector('ul.nav-ul');
    if (navUl == null) return [];

    final items = <CategoryItem>[];
    for (final li in _directChildren(navUl, 'li')) {
      final item = _parseLi(li);
      if (item != null) items.add(item);
    }
    return items;
  }

  static List<dom.Element> _directChildren(dom.Element parent, String tagName) {
    final result = <dom.Element>[];
    for (final child in parent.children) {
      if (child.localName == tagName) {
        result.add(child);
      }
    }
    return result;
  }

  static CategoryItem? _parseLi(dom.Element li) {
    dom.Element? a;
    for (final child in li.children) {
      if (child.localName == 'a') {
        a = child;
        break;
      }
    }
    if (a == null) return null;
    final href = a.attributes['href'] ?? '';
    final name = a.text.trim();
    if (name.isEmpty || href == '#') return null;

    String slug = '';
    final match = RegExp(r'/category-([a-z0-9-]+)/').firstMatch(href);
    if (match != null) {
      slug = match.group(1)!;
    }

    final children = <CategoryItem>[];
    dom.Element? subUl;
    for (final child in li.children) {
      if (child.localName == 'ul') {
        subUl = child;
        break;
      }
    }
    if (subUl != null) {
      for (final subLi in _directChildren(subUl, 'li')) {
        final child = _parseLi(subLi);
        if (child != null) children.add(child);
      }
    }

    return CategoryItem(name: name, slug: slug, url: href, children: children);
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';
import '../models/category.dart';

class HomeCacheData {
  final List<ArticleListItem> articles;
  final List<CategoryItem> categories;
  final int totalPages;
  final DateTime savedAt;

  const HomeCacheData({
    required this.articles,
    required this.categories,
    required this.totalPages,
    required this.savedAt,
  });

  Map<String, Object?> toJson() => {
    'version': 1,
    'articles': articles.map((article) => article.toJson()).toList(),
    'categories': categories.map((category) => category.toJson()).toList(),
    'totalPages': totalPages,
    'savedAt': savedAt.toIso8601String(),
  };

  factory HomeCacheData.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported home cache version');
    }

    return HomeCacheData(
      articles: _decodeList(json['articles'], ArticleListItem.fromJson),
      categories: _decodeList(json['categories'], CategoryItem.fromJson),
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static List<T> _decodeList<T>(
    Object? source,
    T Function(Map<String, dynamic>) decoder,
  ) {
    if (source is! List) return [];
    return source
        .whereType<Map>()
        .map((item) => decoder(Map<String, dynamic>.from(item)))
        .toList();
  }
}

class HomeCacheService {
  static const _cacheKey = 'home_cache_v1';
  static const maxArticles = 60;

  Future<HomeCacheData?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final source = preferences.getString(_cacheKey);
      if (source == null || source.isEmpty) return null;
      return HomeCacheData.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(HomeCacheData data) async {
    try {
      final limited = HomeCacheData(
        articles: data.articles.take(maxArticles).toList(),
        categories: data.categories,
        totalPages: data.totalPages,
        savedAt: data.savedAt,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(limited.toJson()));
    } catch (_) {
      // Cache failures must never block live homepage content.
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/article.dart';

/// One entry copied verbatim from `/plus/json/push.json`.
///
/// Note `cateid` is a **string** while `comments` is a number - the server is
/// inconsistent, and casting both with `as num?` threw a TypeError that the
/// caller swallowed, silently killing the 5s auto-refresh.
Map<String, dynamic> _pushEntry() => <String, dynamic>{
  'id': 7101027,
  'title': '艾维诺宝贝润肤乳30g*2支 12.9元',
  'content': '🔴𝐁𝐮𝐠❗❗艾维诺宝贝润肤乳',
  'content_html': '<b>x</b>',
  'datetime': '2026-09-27',
  'shorttime': '08:40',
  'shijianchuo': 1790469624,
  'cateid': '30',
  'catename': '好单线报-日用-淘宝',
  'comments': 0,
  'louzhu': '发报员Y',
  'louzhuregtime': null,
  'url': '/haodan/7101027.html',
};

void main() {
  group('ArticleListItem.fromPushMap', () {
    test('parses a real push entry without throwing', () {
      final item = ArticleListItem.fromPushMap(_pushEntry());

      expect(item.url, '/haodan/7101027.html');
      expect(item.title, '艾维诺宝贝润肤乳30g*2支 12.9元');
      expect(item.category, '好单线报-日用-淘宝');
      expect(item.author, '发报员Y');
      expect(item.time, '2026-09-27 08:40');
    });

    test('reads cateid given as a string (regression)', () {
      final item = ArticleListItem.fromPushMap(_pushEntry());
      expect(item.figureClass, 'cg30');
      expect(item.figureAsset, 'assets/cateicon/30.png');
    });

    test('reads cateid given as a number', () {
      final entry = _pushEntry()..['cateid'] = 30;
      expect(ArticleListItem.fromPushMap(entry).figureClass, 'cg30');
    });

    test('falls back to the requested category id', () {
      final entry = _pushEntry()..remove('cateid');
      final item = ArticleListItem.fromPushMap(entry, fallbackCateId: 16);
      expect(item.figureClass, 'cg16');
    });

    test('leaves the icon empty when no category id is available', () {
      final entry = _pushEntry()..remove('cateid');
      final item = ArticleListItem.fromPushMap(entry);
      expect(item.figureClass, '');
      expect(item.figureAsset, isNull);
    });

    test('accepts comments as a number, a string, or missing', () {
      expect(ArticleListItem.fromPushMap(_pushEntry()).commentCount, 0);

      final asString = _pushEntry()..['comments'] = '5';
      expect(ArticleListItem.fromPushMap(asString).commentCount, 5);

      final asNum = _pushEntry()..['comments'] = 7;
      expect(ArticleListItem.fromPushMap(asNum).commentCount, 7);

      final missing = _pushEntry()..remove('comments');
      expect(ArticleListItem.fromPushMap(missing).commentCount, 0);
    });

    test('tolerates absent optional fields', () {
      final item = ArticleListItem.fromPushMap(<String, dynamic>{});
      expect(item.url, '');
      expect(item.title, '');
      expect(item.commentCount, 0);
      expect(item.figureClass, '');
    });

    test('handles a cateid that is not numeric', () {
      final entry = _pushEntry()..['cateid'] = '';
      expect(ArticleListItem.fromPushMap(entry).figureClass, '');
    });
  });
}

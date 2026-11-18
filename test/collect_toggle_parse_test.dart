import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/article.dart';

/// 文章页收藏开关的回包解析。
///
/// 夹具是 2026-11-18 线上实测的 `function_user.php?act=addshoucang` 回包：
///  - 收藏成功：`{"code":0,"msg":"收藏成功","size":1}`
///  - 取消收藏：`{"code":2,"msg":"取消成功","size":0}`
///  - 没带/带错 csrf 令牌：`{"code":1,"csrf_expired":1,"msg":"网页已过期，请手动刷新整个页面！"}`
///  - 未登录：`{"code":1,"msg":"请登录 或 注册"}`
///
/// 关键点：「令牌过期」和「未登录」都是 `code: 1`，靠 `csrf_expired` / 文案区分，
/// 判错会把已登录的用户赶去登录页。
void main() {
  CollectToggleResult parse(String body) =>
      CollectToggleResult.fromJson(jsonDecode(body) as Map<String, dynamic>);

  group('CollectToggleResult.fromJson', () {
    test('code 0 = 已收藏，带收藏数', () {
      final result = parse(r'{"code":0,"msg":"收藏成功","size":1}');
      expect(result.isCollected, isTrue);
      expect(result.size, 1);
      expect(result.needLogin, isFalse);
      expect(result.csrfExpired, isFalse);
      expect(result.message, '收藏成功');
    });

    test('code 2 = 已取消收藏', () {
      final result = parse(r'{"code":2,"msg":"取消成功","size":0}');
      expect(result.isCollected, isFalse);
      expect(result.size, 0);
      expect(result.needLogin, isFalse);
      expect(result.csrfExpired, isFalse);
    });

    test('csrf_expired = 令牌过期，不是掉登录', () {
      final result = parse(
        r'{"code":1,"csrf_expired":1,"msg":"网页已过期，请手动刷新整个页面！"}',
      );
      expect(result.csrfExpired, isTrue);
      expect(result.needLogin, isFalse);
      expect(result.isCollected, isFalse);
    });

    test('没有 csrf_expired 字段、只靠文案也认得出令牌过期', () {
      final result = parse('{"code":1,"msg":"网页已经过期，请重新刷新网页"}');
      expect(result.csrfExpired, isTrue);
      expect(result.needLogin, isFalse);
    });

    test('code 1 且不是令牌过期 = 需要登录', () {
      final result = parse(
        r'{"code":1,"msg":"请登录 或 注册"}',
      );
      expect(result.needLogin, isTrue);
      expect(result.csrfExpired, isFalse);
    });

    test('回包不是 JSON 时用 failure 构造，保留令牌过期标记', () {
      final result = CollectToggleResult.failure(
        code: 1,
        message: '',
        csrfExpired: true,
      );
      expect(result.csrfExpired, isTrue);
      expect(result.needLogin, isFalse);
      expect(result.isCollected, isFalse);
      expect(result.size, 0);
    });
  });
}

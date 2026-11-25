import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/ucenter.dart';

void main() {
  group('UcenterBoard（IndexBoard）', () {
    test('解析积分 / 收藏 / 评论与签到状态', () {
      final board = UcenterBoard.fromJson({
        'giod': 1675,
        'giod_name': '积分',
        'signed': 1,
        'coll_count': 18,
        'comment_count': 0,
        'notice': '',
        'tui': [
          {
            'id': '1',
            'title': '推荐一条',
            'url': 'https://new.xianbao.fun/gonggao/1.html',
            'time': '2026/11/25',
          },
        ],
      });

      expect(board.points, 1675);
      expect(board.collectCount, 18);
      expect(board.commentCount, 0);
      expect(board.signed, isTrue);
      expect(board.tui, hasLength(1));
      expect(board.tui.first.title, '推荐一条');
    });

    test('数字是带千分位的字符串时也能解析', () {
      final board = UcenterBoard.fromJson({
        'giod': '1,675',
        'coll_count': '18',
        'comment_count': '0',
        'signed': '1',
      });
      expect(board.points, 1675);
      expect(board.collectCount, 18);
      expect(board.signed, isTrue);
    });

    test('看板转成首页统计卡片', () {
      final home = UcenterHome.fromBoard(
        UcenterBoard.fromJson({
          'giod': 1675,
          'coll_count': 18,
          'comment_count': 0,
        }),
        profile: const UcenterProfile(levelText: '注册用户'),
      );
      expect(home.level, '注册用户');
      expect(home.points, '1675');
      expect(home.collects, '18');
      expect(home.comments, '0');
    });
  });

  group('UcenterBoot（壳页 __UC_BOOT__）', () {
    test('解析已登录用户与 csrf', () {
      const html =
          '<script>window.__UC_BOOT__={"host":"https://new.xianbao.fun/",'
          '"guest":false,"user":{"id":31413,"name":"测试用户","level":5,'
          '"levelName":"评论者","vipLevelName":"注册用户","isvip":0,'
          '"vipExpire":"","avatar":"https://example.com/avatar.png"},'
          '"csrf":"abc123"};</script>';

      final boot = UcenterBoot.parse(html);
      expect(boot, isNotNull);
      expect(boot!.guest, isFalse);
      expect(boot.csrf, 'abc123');

      final profile = UcenterProfile.fromBoot(boot.user!);
      expect(profile.id, 31413);
      expect(profile.nickname, '测试用户');
      expect(profile.levelText, '注册用户');
      expect(profile.isVip, isFalse);
      expect(profile.avatarUrl, 'https://example.com/avatar.png');
    });

    test('登录页没有 boot 数据', () {
      expect(UcenterBoot.parse('<html><title>用户登录</title></html>'), isNull);
    });

    test('JSON 字符串里的括号不会截断', () {
      const html =
          '<script>window.__UC_BOOT__={"cfg":{"note":"{a}"},"guest":true};'
          '</script>';
      final boot = UcenterBoot.parse(html);
      expect(boot, isNotNull);
      expect(boot!.guest, isTrue);
      expect(boot.user, isNull);
    });
  });
}

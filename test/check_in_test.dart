import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/services/check_in_service.dart';
import 'package:xianbao/services/ucenter_service.dart';

/// 每日签到（静默）的行为测试。
///
/// 回包夹具是线上实测的：
///  - 成功：`{"code":0,"msg":"签到成功…奖励21积分！","giod":"709"}`
///  - 今天已签：`{"code":1,"msg":"你今天签过到啦！","giod":"709"}`

/// 内存版的「最近提示日期」存储，替掉真实的 shared_preferences。
class _FakeTipStore {
  String? date;
  int saves = 0;

  Future<String?> load() async => date;
  Future<void> save(String value) async {
    date = value;
    saves++;
  }
}

void main() {
  group('UcenterCheckInResult.fromText', () {
    test('成功：ok，不是失败', () {
      final result = UcenterCheckInResult.fromText(
        '{"code":0,"msg":"签到成功<br/>注册会员随机奖励21积分！","giod":"709"}',
      );
      expect(result.ok, isTrue);
      expect(result.failed, isFalse);
      expect(result.alreadyDone, isFalse);
      expect(result.points, '709');
    });

    test('今天已签过：code=1 但不算失败（不能弹提示）', () {
      final result = UcenterCheckInResult.fromText(
        '{"code":1,"msg":"你今天签过到啦！","giod":"709"}',
      );
      expect(result.ok, isFalse);
      expect(result.alreadyDone, isTrue);
      expect(result.failed, isFalse);
    });

    test('其它 code=1：算真失败', () {
      final result = UcenterCheckInResult.fromText(
        '{"code":1,"msg":"签到失败：会员等级不足"}',
      );
      expect(result.failed, isTrue);
      expect(result.message, '签到失败：会员等级不足');
    });

    test('空响应 / 坏 JSON：算失败（会走兜底文案）', () {
      expect(UcenterCheckInResult.fromText('').failed, isTrue);
      expect(UcenterCheckInResult.fromText('<html>').failed, isTrue);
    });
  });

  group('日期键与节流判定', () {
    test('日期键是本地日历日，月日补零', () {
      expect(checkInDateKey(DateTime(2026, 10, 10)), '2026-10-10');
      expect(checkInDateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('同一天只提示一次，跨天重新可以提示', () {
      expect(
        shouldShowCheckInTip(lastShownDate: null, today: '2026-10-10'),
        isTrue,
      );
      expect(
        shouldShowCheckInTip(lastShownDate: '2026-10-09', today: '2026-10-10'),
        isTrue,
      );
      expect(
        shouldShowCheckInTip(lastShownDate: '2026-10-10', today: '2026-10-10'),
        isFalse,
      );
    });
  });

  group('CheckInCoordinator.run', () {
    setUp(CheckInCoordinator.resetForTest);

    Future<String?> runOnce({
      required Future<UcenterCheckInResult> Function() checkIn,
      _FakeTipStore? tipStore,
      DateTime? now,
    }) {
      final fake = tipStore ?? _FakeTipStore();
      return CheckInCoordinator.run(
        checkIn: checkIn,
        loadLastTipDate: fake.load,
        saveTipDate: fake.save,
        now: now ?? DateTime(2026, 10, 10),
      );
    }

    test('签到成功：静默，也不写提示日期', () async {
      final fake = _FakeTipStore();
      final tip = await runOnce(
        tipStore: fake,
        checkIn: () async => UcenterCheckInResult.fromText(
          '{"code":0,"msg":"签到成功","giod":"709"}',
        ),
      );
      expect(tip, isNull);
      expect(fake.saves, 0);
    });

    test('今天已签过：静默（每天第二次启动不该弹提示）', () async {
      final fake = _FakeTipStore();
      final tip = await runOnce(
        tipStore: fake,
        checkIn: () async => UcenterCheckInResult.fromText(
          '{"code":1,"msg":"你今天签过到啦！","giod":"709"}',
        ),
      );
      expect(tip, isNull);
      expect(fake.saves, 0);
    });

    test('真失败：带出服务端原因，并记下当天已提示', () async {
      final fake = _FakeTipStore();
      final tip = await runOnce(
        tipStore: fake,
        checkIn: () async => UcenterCheckInResult.fromText(
          '{"code":1,"msg":"签到失败：会员等级不足"}',
        ),
      );
      expect(tip, '签到失败：会员等级不足');
      expect(fake.date, '2026-10-10');
    });

    test('请求抛异常：算失败，给兜底文案', () async {
      final tip = await runOnce(checkIn: () async => throw Exception('timeout'));
      expect(tip, '签到失败，请稍后再试');
    });

    test('当天已经提示过：再失败也不弹', () async {
      final fake = _FakeTipStore()..date = '2026-10-10';
      final tip = await runOnce(
        tipStore: fake,
        checkIn: () async => UcenterCheckInResult.fromText(
          '{"code":1,"msg":"又失败了"}',
        ),
      );
      expect(tip, isNull);
      expect(fake.saves, 0);
    });

    test('第二天再失败：重新提示一次', () async {
      final fake = _FakeTipStore()..date = '2026-10-09';
      final tip = await runOnce(
        tipStore: fake,
        checkIn: () async =>
            UcenterCheckInResult.fromText('{"code":1,"msg":"还是失败"}'),
        now: DateTime(2026, 10, 10),
      );
      expect(tip, '还是失败');
      expect(fake.date, '2026-10-10');
    });

    test('并发去重：前一次还在跑时再调用直接返回 null', () async {
      final first = CheckInCoordinator.run(
        checkIn: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return UcenterCheckInResult.fromText('{"code":0,"msg":"ok"}');
        },
        loadLastTipDate: () async => null,
        saveTipDate: (_) async {},
      );
      final second = await CheckInCoordinator.run(
        checkIn: () async => UcenterCheckInResult.fromText('{"code":0}'),
        loadLastTipDate: () async => null,
        saveTipDate: (_) async {},
      );
      expect(second, isNull);
      await first;
    });
  });

  group('UcenterCheckInStatus.fromText（Get.php act=MemTs，仅备用）', () {
    test('code=0 时解析 qian 与积分', () {
      final parsed = UcenterCheckInStatus.fromText(
        '{"code":"0","data":{"giod":668,"qian":0,"gong":1}}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.canCheckIn, isTrue);
      expect(parsed.points, '668');
    });

    test('令牌过期（code=1）→ null，签到流程不依赖它', () {
      expect(
        UcenterCheckInStatus.fromText(
          '{"code":1,"msg":"网页已过期，请手动刷新整个页面！"}',
        ),
        isNull,
      );
    });
  });
}

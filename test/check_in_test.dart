import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/services/check_in_service.dart';
import 'package:xianbao/services/ucenter_service.dart';

/// 每日签到（静默）的行为测试：成功不提示、只有真失败才给文案、失败提示当天只弹一次。

UcenterCheckInStatus status({required bool canCheckIn, String points = '668'}) =>
    UcenterCheckInStatus(canCheckIn: canCheckIn, points: points);

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

({Future<String?> Function() load, Future<void> Function(String) save}) store(
  _FakeTipStore fake,
) => (load: fake.load, save: fake.save);

void main() {
  group('UcenterCheckInStatus.fromText（Get.php act=MemTs）', () {
    test('qian=0 表示今天还能签，并带上积分', () {
      final parsed = UcenterCheckInStatus.fromText(
        '{"code":"0","msg":"","data":{"giod":668,"qian":0,"gong":1}}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.canCheckIn, isTrue);
      expect(parsed.points, '668');
    });

    test('qian!=0 表示今天已经签过了', () {
      final parsed = UcenterCheckInStatus.fromText(
        '{"code":"0","data":{"giod":691,"qian":1,"gong":0}}',
      );
      expect(parsed!.canCheckIn, isFalse);
    });

    test('qian 是字符串也能解析', () {
      expect(
        UcenterCheckInStatus.fromText('{"code":"0","data":{"qian":"0"}}')!
            .canCheckIn,
        isTrue,
      );
    });

    test('code 非 0 / 空响应 / 坏 JSON 一律返回 null（不打扰）', () {
      expect(
        UcenterCheckInStatus.fromText('{"code":1001,"msg":"请先登录"}'),
        isNull,
      );
      expect(UcenterCheckInStatus.fromText('{"code":"0"}'), isNull);
      expect(UcenterCheckInStatus.fromText(''), isNull);
      expect(UcenterCheckInStatus.fromText('<html>'), isNull);
    });
  });

  group('checkInTip / 日期键 / 节流判定', () {
    test('成功 → 没有任何提示', () {
      expect(checkInTip(true, '签到成功，+23积分'), isNull);
      expect(checkInTip(true, ''), isNull);
    });

    test('失败 → 原样带出服务端消息；没有消息时给兜底', () {
      expect(checkInTip(false, '今天已经签到过了'), '今天已经签到过了');
      expect(checkInTip(false, '  '), '签到失败，请稍后再试');
    });

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
      required Future<UcenterCheckInStatus?> Function() fetchStatus,
      required Future<({bool ok, String message, String points})> Function()
      checkIn,
      _FakeTipStore? tipStore,
      DateTime? now,
    }) {
      final fake = tipStore ?? _FakeTipStore();
      final s = store(fake);
      return CheckInCoordinator.run(
        fetchStatus: fetchStatus,
        checkIn: checkIn,
        loadLastTipDate: s.load,
        saveTipDate: s.save,
        now: now ?? DateTime(2026, 10, 10),
      );
    }

    test('今天已签到：不再发签到请求，也不提示', () async {
      var checked = false;
      final tip = await runOnce(
        fetchStatus: () async => status(canCheckIn: false),
        checkIn: () async {
          checked = true;
          return (ok: true, message: '', points: '');
        },
      );
      expect(tip, isNull);
      expect(checked, isFalse);
    });

    test('状态查不到（断网/掉登录）：不提示', () async {
      expect(
        await runOnce(
          fetchStatus: () async => throw Exception('未登录'),
          checkIn: () async => (ok: true, message: '', points: ''),
        ),
        isNull,
      );

      CheckInCoordinator.resetForTest();
      expect(
        await runOnce(
          fetchStatus: () async => null,
          checkIn: () async => (ok: true, message: '', points: ''),
        ),
        isNull,
      );
    });

    test('签到成功：静默（返回 null），也不写提示日期', () async {
      final fake = _FakeTipStore();
      final tip = await runOnce(
        tipStore: fake,
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async =>
            (ok: true, message: '签到成功，积分 +23', points: '691'),
      );
      expect(tip, isNull);
      expect(fake.saves, 0);
    });

    test('签到失败：把服务端原因带出来，并记下当天已提示', () async {
      final fake = _FakeTipStore();
      final tip = await runOnce(
        tipStore: fake,
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async => (ok: false, message: '签到失败：会员等级不足', points: ''),
      );
      expect(tip, '签到失败：会员等级不足');
      expect(fake.date, '2026-10-10');
    });

    test('签到请求抛异常：属于真失败，给兜底文案', () async {
      final tip = await runOnce(
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async => throw Exception('timeout'),
      );
      expect(tip, '签到失败，请稍后再试');
    });

    test('当天已经提示过：再失败也不弹', () async {
      final fake = _FakeTipStore()..date = '2026-10-10';
      final tip = await runOnce(
        tipStore: fake,
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async => (ok: false, message: '又失败了', points: ''),
      );
      expect(tip, isNull);
      expect(fake.saves, 0);
    });

    test('第二天再失败：重新提示一次', () async {
      final fake = _FakeTipStore()..date = '2026-10-09';
      final tip = await runOnce(
        tipStore: fake,
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async => (ok: false, message: '还是失败', points: ''),
        now: DateTime(2026, 10, 10),
      );
      expect(tip, '还是失败');
      expect(fake.date, '2026-10-10');
    });

    test('并发去重：前一次还在跑时再调用直接返回 null', () async {
      final first = CheckInCoordinator.run(
        fetchStatus: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return status(canCheckIn: true);
        },
        checkIn: () async => (ok: true, message: '', points: ''),
        loadLastTipDate: () async => null,
        saveTipDate: (_) async {},
      );
      final second = await CheckInCoordinator.run(
        fetchStatus: () async => status(canCheckIn: true),
        checkIn: () async => (ok: true, message: '', points: ''),
        loadLastTipDate: () async => null,
        saveTipDate: (_) async {},
      );
      expect(second, isNull);
      await first;
    });
  });
}

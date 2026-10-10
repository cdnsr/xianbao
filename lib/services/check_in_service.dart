import 'package:shared_preferences/shared_preferences.dart';

import 'ucenter_service.dart';

/// 每日签到：静默完成，失败才提示。
///
/// 触发点（`MainShell` 里监听登录态）：
///  - App 首次打开、且已经是登录态 —— 启动时补当天这一次；
///  - 登录成功（含登录页登录、老会话恢复）—— 立刻补一次。
///
/// 静默原则：
///  - 签到成功**不提示**；
///  - 只有「确实该签到、但签到失败」才返回文案，交给页面在屏幕中间提示；
///  - **失败提示同一天只弹一次**（[CheckInTipStore] 落盘当天日期），避免每次启动
///    或每次进页面都重复骚扰；
///  - 未登录、状态查不到（断网/掉登录）、今天已经签过 —— 都算「不打扰」，返回 null。
///
/// 先查状态再签到，避免每次启动都发写请求，也避免把网站「今天已经签到过了」的报错
/// 当成失败弹给用户。
class CheckInCoordinator {
  /// 并发去重：两个触发点同时命中时只跑一次。
  static bool _running = false;

  /// 尝试签到。返回 null = 无需提示；返回文案 = 中间提示这句话。
  static Future<String?> attempt({
    UcenterService? service,
    CheckInTipStore? tipStore,
    DateTime? now,
  }) {
    final ucenter = service ?? UcenterService();
    final store = tipStore ?? CheckInTipStore();
    return run(
      fetchStatus: ucenter.fetchCheckInStatus,
      checkIn: ucenter.checkIn,
      loadLastTipDate: store.loadLastTipDate,
      saveTipDate: store.saveTipDate,
      now: now,
    );
  }

  /// 判定主体（网络与存储都做成参数，便于单测覆盖各分支）。
  static Future<String?> run({
    required Future<UcenterCheckInStatus?> Function() fetchStatus,
    required Future<({bool ok, String message, String points})> Function()
    checkIn,
    required Future<String?> Function() loadLastTipDate,
    required Future<void> Function(String date) saveTipDate,
    DateTime? now,
  }) async {
    if (_running) return null;
    _running = true;
    try {
      final UcenterCheckInStatus? status;
      try {
        status = await fetchStatus();
      } catch (_) {
        // 状态都查不到（断网/掉登录）：不提示，免得每次启动都骚扰。
        return null;
      }
      if (status == null || !status.canCheckIn) return null;

      final ({bool ok, String message, String points}) result;
      try {
        result = await checkIn();
      } catch (_) {
        // 明确该签到、请求却挂了：这是真的签到失败。
        return _tipOrNull(
          ok: false,
          message: '',
          loadLastTipDate: loadLastTipDate,
          saveTipDate: saveTipDate,
          now: now,
        );
      }
      return _tipOrNull(
        ok: result.ok,
        message: result.message,
        loadLastTipDate: loadLastTipDate,
        saveTipDate: saveTipDate,
        now: now,
      );
    } finally {
      _running = false;
    }
  }

  /// 失败才提示，且同一天只提示一次。
  static Future<String?> _tipOrNull({
    required bool ok,
    required String message,
    required Future<String?> Function() loadLastTipDate,
    required Future<void> Function(String date) saveTipDate,
    DateTime? now,
  }) async {
    final tip = checkInTip(ok, message);
    if (tip == null) return null;

    final dateKey = checkInDateKey(now ?? DateTime.now());
    final lastShown = await loadLastTipDate();
    if (!shouldShowCheckInTip(lastShownDate: lastShown, today: dateKey)) {
      return null;
    }
    await saveTipDate(dateKey);
    return tip;
  }

  /// 供测试重置「正在跑」的标记。
  static void resetForTest() => _running = false;
}

/// 签到失败的提示文案：成功 → null（静默），失败 → 服务端文案（没有则兜底）。
String? checkInTip(bool ok, String serverMessage) {
  if (ok) return null;
  final message = serverMessage.trim();
  return message.isEmpty ? '签到失败，请稍后再试' : message;
}

/// 当天是否该弹失败提示：同一天只弹一次。
bool shouldShowCheckInTip({
  required String? lastShownDate,
  required String today,
}) => lastShownDate != today;

/// 提示节流用的日期键（本地日历日，`2026-10-10`）。
String checkInDateKey(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

/// 「签到失败提示」最近弹出的日期，存在本地。
///
/// 只节流**提示**、不节流尝试：当天晚些时候网络恢复或限制解除时，签到该拿到还是
/// 要拿到（成功本来就不提示）。
class CheckInTipStore {
  static const String _key = 'check_in_tip_date';

  Future<String?> loadLastTipDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTipDate(String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, date);
    } catch (_) {
      // 存不上最多多弹一次提示，不值得打断签到流程。
    }
  }
}

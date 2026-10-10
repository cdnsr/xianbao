import 'package:shared_preferences/shared_preferences.dart';

import 'ucenter_service.dart';

/// 每日签到：静默完成，失败才提示。
///
/// 触发点（`MainShell` 里监听登录态）：
///  - App 首次打开、且已经是登录态 —— 启动时补当天这一次；
///  - 登录成功（含登录页登录、老会话恢复）—— 立刻补一次。
///
/// 判定原则：
///  - **直接调签到接口**，不看状态接口。状态接口要求有效令牌、且它的 `qian` 取值方向
///    从线上脚本判断不出来，拿它当闸门会出现「该签的时候不签」；签到接口本身幂等
///    （重复签只回「你今天签过到啦」），直接调最可靠；
///  - 成功、以及「今天已签过」都**不提示**；
///  - 真正的失败（服务端报错、请求异常）才提示，且**同一天只提示一次**
///    （[CheckInTipStore] 落盘当天日期），避免每次启动都骚扰。
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
      checkIn: ucenter.checkIn,
      loadLastTipDate: store.loadLastTipDate,
      saveTipDate: store.saveTipDate,
      now: now,
    );
  }

  /// 判定主体（网络与存储都做成参数，便于单测覆盖各分支）。
  static Future<String?> run({
    required Future<UcenterCheckInResult> Function() checkIn,
    required Future<String?> Function() loadLastTipDate,
    required Future<void> Function(String date) saveTipDate,
    DateTime? now,
  }) async {
    if (_running) return null;
    _running = true;
    try {
      final UcenterCheckInResult result;
      try {
        result = await checkIn();
      } catch (_) {
        // 请求挂了（断网、会话过期）：今天没签成，按失败提示（当天只一次）。
        return _tipOrNull(
          message: '',
          loadLastTipDate: loadLastTipDate,
          saveTipDate: saveTipDate,
          now: now,
        );
      }
      // 成功、或者「今天已经签过」都不打扰。
      if (!result.failed) return null;
      return _tipOrNull(
        message: result.message,
        loadLastTipDate: loadLastTipDate,
        saveTipDate: saveTipDate,
        now: now,
      );
    } finally {
      _running = false;
    }
  }

  /// 失败提示，且同一天只提示一次。
  static Future<String?> _tipOrNull({
    required String message,
    required Future<String?> Function() loadLastTipDate,
    required Future<void> Function(String date) saveTipDate,
    DateTime? now,
  }) async {
    final dateKey = checkInDateKey(now ?? DateTime.now());
    final lastShown = await loadLastTipDate();
    if (!shouldShowCheckInTip(lastShownDate: lastShown, today: dateKey)) {
      return null;
    }
    await saveTipDate(dateKey);
    final text = message.trim();
    return text.isEmpty ? '签到失败，请稍后再试' : text;
  }

  /// 供测试重置「正在跑」的标记。
  static void resetForTest() => _running = false;
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
/// 只节流**提示**、不节流**尝试**：当天晚些时候网络恢复或限制解除时，签到该拿到还是
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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/services/app_state.dart';

/// 登录态探测的时序测试。
///
/// 复现并钉住这个 bug：启动后先未登录浏览（首页 Tab 会打一次登录态探测），随后去
/// 登录成功，那次**登录前发出、登录后才回来**的探测结果会把状态改回「未登录」，
/// 用户接着点收藏就被提示「请先登录后再收藏」。
void main() {
  group('AppState.refreshLoginState 的时序', () {
    test('登录期间回来的旧探测结果必须丢弃', () async {
      final completer = Completer<bool?>();
      final state = AppState(loginProbe: () => completer.future);

      // 登录前发出探测（此时服务端视角是未登录）。
      final staleProbe = state.refreshLoginState();
      // 用户在这期间登录成功。
      await state.onLoginSuccess();
      expect(state.isLoggedIn, isTrue);

      // 旧探测这才回来，说「未登录」——不能覆盖刚登录好的状态。
      completer.complete(false);
      await staleProbe;
      expect(state.isLoggedIn, isTrue);
    });

    test('没有登录/注销时，探测结果照常生效', () async {
      var loggedIn = true;
      final state = AppState(loginProbe: () async => loggedIn);

      await state.refreshLoginState();
      expect(state.isLoggedIn, isTrue);

      loggedIn = false;
      await state.refreshLoginState();
      expect(state.isLoggedIn, isFalse);
    });

    test('探测未知（断网）时不动状态', () async {
      final state = AppState(loginProbe: () async => null);
      await state.refreshLoginState();
      expect(state.isLoggedIn, isFalse);

      await state.onLoginSuccess();
      await state.refreshLoginState();
      // 未知结果不该把已登录状态改掉。
      expect(state.isLoggedIn, isTrue);
    });

    test('登录会推进会话纪元，探测期间登录过就不再采纳结果', () async {
      final completers = <Completer<bool?>>[];
      final state = AppState(
        loginProbe: () {
          final c = Completer<bool?>();
          completers.add(c);
          return c.future;
        },
      );

      final first = state.refreshLoginState();
      await state.onLoginSuccess();
      completers.first.complete(false);
      await first;
      expect(state.isLoggedIn, isTrue);

      // 之后的探测（登录之后发出）照常生效。
      final second = state.refreshLoginState();
      completers.last.complete(true);
      await second;
      expect(state.isLoggedIn, isTrue);
    });
  });

  group('AppState.verifySessionAfterLogin', () {
    test('服务端确认已登录 → true', () async {
      final state = AppState(loginProbe: () async => true);
      expect(await state.verifySessionAfterLogin(), isTrue);
    });

    test('服务端明确说未登录 → false（登录页提示重试）', () async {
      final state = AppState(loginProbe: () async => false);
      expect(await state.verifySessionAfterLogin(), isFalse);
    });

    test('探测未知 / 抛异常 → 按成功处理，不因一次抖动挡人', () async {
      expect(
        await AppState(loginProbe: () async => null).verifySessionAfterLogin(),
        isTrue,
      );
      expect(
        await AppState(
          loginProbe: () async => throw Exception('offline'),
        ).verifySessionAfterLogin(),
        isTrue,
      );
    });
  });
}

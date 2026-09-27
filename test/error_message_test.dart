import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xianbao/utils/error_message.dart';

DioException _dio(DioExceptionType type, {int? status, Object? inner}) {
  return DioException(
    requestOptions: RequestOptions(path: '/'),
    type: type,
    error: inner,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: RequestOptions(path: '/'),
            statusCode: status,
          ),
  );
}

void main() {
  group('friendlyErrorMessage', () {
    test('never surfaces the raw DioException text', () {
      final raw = _dio(DioExceptionType.connectionError);
      // Sanity check the thing we are guarding against.
      expect(raw.toString(), contains('DioException'));
      expect(raw.toString(), contains('connection error'));

      expect(friendlyErrorMessage(raw), '网络不可用，请检查网络连接后重试。');
    });

    test('maps timeouts', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(friendlyErrorMessage(_dio(type)), '网络连接超时，请稍后重试。');
      }
    });

    test('maps a wrapped SocketException on unknown', () {
      expect(
        friendlyErrorMessage(
          _dio(DioExceptionType.unknown, inner: const SocketException('nope')),
        ),
        '网络不可用，请检查网络连接后重试。',
      );
    });

    test('maps status codes', () {
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 404)),
          '内容不存在或已被删除。');
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 401)),
          '登录状态已失效，请重新登录后重试。');
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 403)),
          '没有访问权限，请重新登录后重试。');
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 503)),
          '服务器暂时不可用（503），请稍后重试。');
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse, status: 302)),
          '请求失败（302），请稍后重试。');
      expect(friendlyErrorMessage(_dio(DioExceptionType.badResponse)),
          genericErrorMessage);
    });

    test('maps cancelled requests', () {
      expect(friendlyErrorMessage(_dio(DioExceptionType.cancel)), '请求已取消。');
    });

    test("keeps the app's own Chinese messages", () {
      expect(
        friendlyErrorMessage(Exception('无法获取用户中心令牌，请重新登录')),
        '无法获取用户中心令牌，请重新登录',
      );
    });

    test('replaces English messages from other exceptions', () {
      expect(
        friendlyErrorMessage(Exception('Some English failure')),
        genericErrorMessage,
      );
      expect(friendlyErrorMessage('a bare string'), genericErrorMessage);
      expect(friendlyErrorMessage(null), genericErrorMessage);
    });
  });

  group('friendlyWebViewErrorMessage', () {
    WebResourceError err(WebResourceErrorType? type) => WebResourceError(
          errorCode: 0,
          description: 'net::ERR_INTERNET_DISCONNECTED (must not leak)',
          errorType: type,
          isForMainFrame: true,
        );

    test('maps offline-ish failures and never leaks the description', () {
      for (final type in [
        WebResourceErrorType.hostLookup,
        WebResourceErrorType.connect,
        WebResourceErrorType.io,
      ]) {
        final message = friendlyWebViewErrorMessage(err(type));
        expect(message, offlineErrorMessage);
        expect(message, isNot(contains('net::')));
      }
    });

    test('maps timeout / tls / rate limit', () {
      expect(friendlyWebViewErrorMessage(err(WebResourceErrorType.timeout)),
          timeoutErrorMessage);
      expect(
        friendlyWebViewErrorMessage(err(WebResourceErrorType.failedSslHandshake)),
        tlsErrorMessage,
      );
      expect(friendlyWebViewErrorMessage(err(WebResourceErrorType.tooManyRequests)),
          '请求过于频繁，请稍后重试。');
    });

    test('falls back for unknown or missing types', () {
      expect(friendlyWebViewErrorMessage(err(null)), '网页加载失败，请检查网络后重试。');
      expect(friendlyWebViewErrorMessage(err(WebResourceErrorType.unknown)),
          '网页加载失败，请检查网络后重试。');
    });
  });
}

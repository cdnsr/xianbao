import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Turns thrown errors into short, user-facing Chinese messages.
///
/// Raw exception text such as
/// `DioException [connection error]: The connection errored: ...` is long,
/// English-only and meaningless to users, so it is never shown as-is.
String friendlyErrorMessage(Object? error) {
  if (error == null) return genericErrorMessage;

  if (error is DioException) return _fromDio(error);
  if (error is TimeoutException) return timeoutErrorMessage;
  if (error is SocketException) return offlineErrorMessage;
  if (error is HandshakeException) return tlsErrorMessage;

  // Messages the app raises itself are already written for users in Chinese
  // (e.g. `Exception('无法获取用户中心令牌，请重新登录')`), so keep those.
  return _ownMessage(error) ?? genericErrorMessage;
}

/// Friendly message for a WebView resource error.
///
/// Keyed on [WebResourceError.errorType]; the platform's own `description` is
/// English and is deliberately not shown.
String friendlyWebViewErrorMessage(WebResourceError error) {
  switch (error.errorType) {
    case WebResourceErrorType.hostLookup:
    case WebResourceErrorType.connect:
    case WebResourceErrorType.io:
      return offlineErrorMessage;
    case WebResourceErrorType.timeout:
      return timeoutErrorMessage;
    case WebResourceErrorType.failedSslHandshake:
      return tlsErrorMessage;
    case WebResourceErrorType.tooManyRequests:
      return '请求过于频繁，请稍后重试。';
    case WebResourceErrorType.badUrl:
    case WebResourceErrorType.unsupportedScheme:
      return '链接无效，无法打开。';
    default:
      return '网页加载失败，请检查网络后重试。';
  }
}

const String genericErrorMessage = '加载失败，请检查网络后重试。';
const String offlineErrorMessage = '网络不可用，请检查网络连接后重试。';
const String timeoutErrorMessage = '网络连接超时，请稍后重试。';
const String tlsErrorMessage = '安全连接失败，请稍后重试。';

String _fromDio(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return timeoutErrorMessage;
    case DioExceptionType.connectionError:
      return offlineErrorMessage;
    case DioExceptionType.badCertificate:
      return tlsErrorMessage;
    case DioExceptionType.cancel:
      return '请求已取消。';
    case DioExceptionType.badResponse:
      return _fromStatusCode(error.response?.statusCode);
    case DioExceptionType.unknown:
      return _fromInnerError(error.error);
  }
}

String _fromStatusCode(int? status) {
  if (status == null) return genericErrorMessage;
  if (status == 404) return '内容不存在或已被删除。';
  if (status == 401) return '登录状态已失效，请重新登录后重试。';
  if (status == 403) return '没有访问权限，请重新登录后重试。';
  if (status >= 500) return '服务器暂时不可用（$status），请稍后重试。';
  return '请求失败（$status），请稍后重试。';
}

String _fromInnerError(Object? inner) {
  if (inner is SocketException) return offlineErrorMessage;
  if (inner is TimeoutException) return timeoutErrorMessage;
  if (inner is HandshakeException) return tlsErrorMessage;
  return genericErrorMessage;
}

/// True when [text] carries any CJK character. The app's own user-facing
/// messages are Chinese; framework and platform messages are not.
bool _hasCjk(String text) {
  for (final rune in text.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
  }
  return false;
}

/// Returns the error's own message when it is already user-facing Chinese,
/// stripping the `Exception: ` style prefix. Null otherwise.
String? _ownMessage(Object error) {
  if (error is! Exception) return null;
  var text = error.toString();
  final separator = text.indexOf(': ');
  if (separator >= 0) text = text.substring(separator + 2);
  text = text.trim();
  if (text.isEmpty || !_hasCjk(text)) return null;
  return text;
}

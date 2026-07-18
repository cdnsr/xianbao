import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/version_compare.dart';

/// Remote version metadata (publish/version.json).
class RemoteVersionInfo {
  const RemoteVersionInfo({
    required this.version,
    required this.desc,
    this.history = const [],
  });

  final String version;
  final String desc;
  final List<VersionHistoryItem> history;

  factory RemoteVersionInfo.fromJson(Map<String, dynamic> json) {
    final historyRaw = json['history'];
    final history = <VersionHistoryItem>[];
    if (historyRaw is List) {
      for (final item in historyRaw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final ver = map['version']?.toString() ?? '';
          if (ver.isEmpty) continue;
          history.add(
            VersionHistoryItem(
              version: ver,
              desc: map['desc']?.toString() ?? '',
            ),
          );
        }
      }
    }
    return RemoteVersionInfo(
      version: json['version']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
      history: history,
    );
  }
}

class VersionHistoryItem {
  const VersionHistoryItem({required this.version, required this.desc});
  final String version;
  final String desc;
}

enum UpdateCheckStatus { checking, upToDate, hasUpdate, error }

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.remote,
    this.errorMessage,
  });

  final UpdateCheckStatus status;
  final String currentVersion;
  final RemoteVersionInfo? remote;
  final String? errorMessage;

  bool get hasUpdate => status == UpdateCheckStatus.hasUpdate;
}

/// Check / download / install updates (lx-music style version.json + Release APK).
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static const String githubOwner = 'cdnsr';
  static const String githubRepo = 'xianbao';
  static const String _prefIgnoreVersion = 'update_ignore_version';
  static const String _prefFailTipTime = 'update_fail_tip_time';
  static const int historyKeep = 20;

  /// Multi-mirror list (same idea as lx-music-mobile).
  static const List<String> versionJsonUrls = [
    'https://raw.githubusercontent.com/$githubOwner/$githubRepo/main/publish/version.json',
    'https://cdn.jsdelivr.net/gh/$githubOwner/$githubRepo@main/publish/version.json',
    'https://fastly.jsdelivr.net/gh/$githubOwner/$githubRepo@main/publish/version.json',
    'https://gcore.jsdelivr.net/gh/$githubOwner/$githubRepo@main/publish/version.json',
  ];

  final Dio _dio;
  CancelToken? _downloadCancel;

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<RemoteVersionInfo> fetchRemoteVersion() async {
    Object? lastError;
    for (final url in versionJsonUrls) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final resp = await _dio.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
              headers: const {'Accept': 'application/json,text/plain,*/*'},
            ),
          );
          final body = resp.data;
          if (body == null) throw StateError('empty body');
          final text = body is String ? body : body.toString();
          final decoded = jsonDecode(text);
          if (decoded is! Map) throw StateError('invalid json');
          final info = RemoteVersionInfo.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (info.version.isEmpty) throw StateError('missing version');
          return info;
        } catch (e) {
          lastError = e;
          debugPrint('UpdateService: fetch failed ($url): $e');
        }
      }
    }

    // Fallback: GitHub Releases API (latest tag_name).
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'xianbao-android',
          },
        ),
      );
      final data = resp.data;
      if (data == null) throw StateError('empty release');
      var tag = data['tag_name']?.toString() ?? '';
      if (tag.startsWith('v') || tag.startsWith('V')) {
        tag = tag.substring(1);
      }
      // Drop +build if present.
      final plus = tag.indexOf('+');
      if (plus >= 0) tag = tag.substring(0, plus);
      if (tag.isEmpty) throw StateError('empty tag');
      final body = data['body']?.toString() ?? '';
      return RemoteVersionInfo(version: tag, desc: body, history: const []);
    } catch (e) {
      lastError = e;
      debugPrint('UpdateService: GitHub API fallback failed: $e');
    }

    throw StateError('无法获取版本信息: $lastError');
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    final current = await currentVersion();
    try {
      final remote = await fetchRemoteVersion();
      if (isVersionNewer(remote.version, current)) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.hasUpdate,
          currentVersion: current,
          remote: remote,
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        currentVersion: current,
        remote: remote,
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: current,
        errorMessage: e.toString(),
      );
    }
  }

  Future<String?> getIgnoreVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefIgnoreVersion);
  }

  Future<void> setIgnoreVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null || version.isEmpty) {
      await prefs.remove(_prefIgnoreVersion);
    } else {
      await prefs.setString(_prefIgnoreVersion, version);
    }
  }

  Future<int> getFailTipTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefFailTipTime) ?? 0;
  }

  Future<void> setFailTipTime(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefFailTipTime, ms);
  }

  /// Map Android ABI to CI APK name segment.
  static String mapAbiToApkArch(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 'armv8';
      case 'armeabi-v7a':
      case 'armeabi':
        return 'armv7';
      case 'x86_64':
        return 'x86_64';
      case 'x86':
        return 'x86_64';
      default:
        return 'armv8';
    }
  }

  Future<String> resolveApkArch() async {
    if (!Platform.isAndroid) return 'armv8';
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      const prefer = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86', 'armeabi'];
      for (final abi in prefer) {
        if (android.supportedAbis.contains(abi)) {
          return mapAbiToApkArch(abi);
        }
      }
      if (android.supportedAbis.isNotEmpty) {
        return mapAbiToApkArch(android.supportedAbis.first);
      }
    } catch (e) {
      debugPrint('UpdateService: resolveApkArch failed: $e');
    }
    return 'armv8';
  }

  List<String> apkDownloadUrls(String version, String arch) {
    final file = 'xianbao-v$version-$arch-release.apk';
    final direct =
        'https://github.com/$githubOwner/$githubRepo/releases/download/v$version/$file';
    return [
      direct,
      // Common China-friendly GitHub proxies (best-effort).
      'https://ghproxy.net/$direct',
      'https://mirror.ghproxy.com/$direct',
    ];
  }

  void cancelDownload() {
    _downloadCancel?.cancel('user cancelled');
    _downloadCancel = null;
  }

  /// Download APK to temp file. Returns local path.
  Future<String> downloadApk(
    String version, {
    void Function(int received, int total)? onProgress,
  }) async {
    final arch = await resolveApkArch();
    final urls = apkDownloadUrls(version, arch);
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/xianbao-update.apk';
    final file = File(savePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    Object? lastError;
    for (final url in urls) {
      _downloadCancel = CancelToken();
      try {
        await _dio.download(
          url,
          savePath,
          cancelToken: _downloadCancel,
          onReceiveProgress: (received, total) {
            onProgress?.call(received, total);
          },
          options: Options(
            receiveTimeout: const Duration(minutes: 10),
            sendTimeout: const Duration(seconds: 30),
            followRedirects: true,
            validateStatus: (s) => s != null && s >= 200 && s < 400,
            headers: const {'User-Agent': 'xianbao-android'},
          ),
        );
        final saved = File(savePath);
        if (!await saved.exists() || await saved.length() < 1024) {
          throw StateError('下载文件无效');
        }
        return savePath;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = e;
        debugPrint('UpdateService: download failed ($url): $e');
      } catch (e) {
        lastError = e;
        debugPrint('UpdateService: download failed ($url): $e');
      }
    }
    throw StateError('下载失败: $lastError');
  }

  Future<bool> ensureInstallPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    return result.isGranted;
  }

  Future<void> installApk(String path) async {
    final ok = await ensureInstallPermission();
    if (!ok) {
      throw StateError('需要允许“安装未知应用”权限才能更新');
    }
    final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done && result.type != ResultType.noAppToOpen) {
      // noAppToOpen sometimes still launches installer on some ROMs; only fail hard cases.
      if (result.type == ResultType.permissionDenied ||
          result.type == ResultType.fileNotFound ||
          result.type == ResultType.error) {
        throw StateError(result.message.isNotEmpty ? result.message : '无法打开安装包');
      }
    }
  }
}
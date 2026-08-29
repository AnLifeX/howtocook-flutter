import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../storage/hive_service.dart';
import 'github_mirror_resolver.dart';

/// 服务端 manifest.json 解析结果。
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String downloadUrlArm64;
  final String downloadUrlArm32;
  final String sha256;
  final String sha256Arm64;
  final String sha256Arm32;
  final int size;
  final String notes;
  final String publishedAt;

  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    this.downloadUrlArm64 = '',
    this.downloadUrlArm32 = '',
    required this.sha256,
    this.sha256Arm64 = '',
    this.sha256Arm32 = '',
    required this.size,
    required this.notes,
    required this.publishedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionName: (json['versionName'] as String?)?.trim() ?? '',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        downloadUrl: (json['downloadUrl'] as String?)?.trim() ?? '',
        downloadUrlArm64: (json['downloadUrlArm64'] as String?)?.trim() ?? '',
        downloadUrlArm32: (json['downloadUrlArm32'] as String?)?.trim() ?? '',
        sha256: ((json['sha256'] as String?) ?? '').trim().toLowerCase(),
        sha256Arm64: ((json['sha256Arm64'] as String?) ?? '').trim().toLowerCase(),
        sha256Arm32: ((json['sha256Arm32'] as String?) ?? '').trim().toLowerCase(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        notes: (json['notes'] as String?) ?? '',
        publishedAt: (json['publishedAt'] as String?) ?? '',
      );

  /// 根据设备 ABI 返回最合适的下载 URL 和 SHA256
  Future<({String url, String sha256})> resolveForDevice() async {
    if (!Platform.isAndroid) return (url: downloadUrl, sha256: sha256);
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      if (abis.contains('arm64-v8a') && downloadUrlArm64.isNotEmpty) {
        return (url: downloadUrlArm64, sha256: sha256Arm64.isNotEmpty ? sha256Arm64 : sha256);
      }
      if (abis.any((a) => a.startsWith('armeabi')) && downloadUrlArm32.isNotEmpty) {
        return (url: downloadUrlArm32, sha256: sha256Arm32.isNotEmpty ? sha256Arm32 : sha256);
      }
    } catch (_) {}
    return (url: downloadUrl, sha256: sha256);
  }
}

/// 更新检查结果，UI 层根据 [hasUpdate] 决定是否提示。
class UpdateCheckResult {
  final UpdateInfo? info;
  final bool hasUpdate;
  final int currentVersionCode;
  final String currentVersionName;

  const UpdateCheckResult({
    required this.info,
    required this.hasUpdate,
    required this.currentVersionCode,
    required this.currentVersionName,
  });
}

/// 应用自更新服务。
///
/// 所有 github.com 请求（manifest 与 APK）都经 [GithubMirrorResolver] 产生
/// 候选源，按「ghfast.top 镜像 → 官方」顺序尝试。
class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  static const String _skippedVersionKey = 'skipped_version_code';
  static const String _defaultManifestUrl =
      'https://github.com/AnLifeX/howtocook-flutter/releases/latest/download/manifest.json';

  String get _manifestUrl {
    final override = dotenv.env['RELEASE_MANIFEST_URL']?.trim();
    return (override != null && override.isNotEmpty) ? override : _defaultManifestUrl;
  }

  /// 检查远端是否有可用更新。
  ///
  /// [respectSkippedVersion] 为 true 时，被用户跳过的版本视为无更新。
  /// 设置页的手动按钮应传 false，强制展示。
  Future<UpdateCheckResult> checkForUpdate({
    bool respectSkippedVersion = true,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    // split-per-abi 构建时 Flutter 会给 versionCode 加 ABI 前缀
    // (arm64=2000, arm32=1000, x86_64=3000)，需还原为 pubspec 中的原始值
    final rawCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    final currentCode = rawCode >= 1000 ? rawCode % 1000 : rawCode;
    final currentName = packageInfo.version;

    final info = await _fetchManifest(_manifestUrl);
    if (info == null) {
      return UpdateCheckResult(
        info: null,
        hasUpdate: false,
        currentVersionCode: currentCode,
        currentVersionName: currentName,
      );
    }

    final manifestCode = info.versionCode >= 1000
        ? info.versionCode % 1000
        : info.versionCode;
    final skipped = respectSkippedVersion ? getSkippedVersion() : null;
    final hasUpdate =
        (_compareVersionNames(info.versionName, currentName) > 0 ||
            manifestCode > currentCode) &&
        manifestCode != skipped;

    return UpdateCheckResult(
      info: info,
      hasUpdate: hasUpdate,
      currentVersionCode: currentCode,
      currentVersionName: currentName,
    );
  }

  /// 记录用户跳过的版本号。
  Future<void> skipVersion(int versionCode) async {
    await HiveService.getUpdatePrefsBox().put(_skippedVersionKey, versionCode);
  }

  /// 读取被跳过的版本号。
  int? getSkippedVersion() {
    final raw = HiveService.getUpdatePrefsBox().get(_skippedVersionKey);
    return raw is int ? raw : null;
  }

  Future<UpdateInfo?> _fetchManifest(String manifestUrl) async {
    final candidates = GithubMirrorResolver.candidates(manifestUrl);
    for (final url in candidates) {
      try {
        debugPrint('🔎 拉取更新 manifest：$url');
        final resp = await _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final body = resp.data;
        if (body == null || body.isEmpty) continue;
        final json = jsonDecode(body) as Map<String, dynamic>;
        return UpdateInfo.fromJson(json);
      } catch (e) {
        debugPrint('⚠️  manifest 拉取失败 ($url)：$e');
      }
    }
    return null;
  }

  /// 语义版本比较：返回 >0 表示 a 更新，0 相等，<0 表示 b 更新
  static int _compareVersionNames(String a, String b) {
    final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (int i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }

}

/// 单例 Provider
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

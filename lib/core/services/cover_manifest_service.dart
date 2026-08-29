import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum CoverCacheAction { keep, remove, download }

int compareCoverVersions(String left, String right) {
  final leftParts = left
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final rightParts = right
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

CoverCacheAction decideBundledCoverCacheAction({
  required bool aiGenerated,
  required String? cachedHash,
  required String bundledHash,
  String? downloadedHash,
  String? downloadedVersion,
  required String bundledVersion,
}) {
  if (!aiGenerated || cachedHash == null || cachedHash == bundledHash) {
    return CoverCacheAction.keep;
  }
  final downloadedIsNewer =
      downloadedHash == cachedHash &&
      downloadedVersion != null &&
      compareCoverVersions(downloadedVersion, bundledVersion) > 0;
  return downloadedIsNewer ? CoverCacheAction.keep : CoverCacheAction.remove;
}

CoverCacheAction decideRemoteCoverCacheAction({
  required bool aiGenerated,
  required String? cachedHash,
  required String? bundledHash,
  required String remoteHash,
}) {
  if (!aiGenerated || cachedHash == remoteHash) return CoverCacheAction.keep;
  if (bundledHash == remoteHash) {
    return cachedHash == null ? CoverCacheAction.keep : CoverCacheAction.remove;
  }
  return CoverCacheAction.download;
}

@immutable
class CoverManifestEntry {
  final String recipeId;
  final String recipeName;
  final String category;
  final String path;
  final String sha256;
  final int bytes;
  final int width;
  final int height;
  final bool aiGenerated;
  final String? aiCoverVersion;

  const CoverManifestEntry({
    required this.recipeId,
    required this.recipeName,
    required this.category,
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.width,
    required this.height,
    required this.aiGenerated,
    this.aiCoverVersion,
  });

  factory CoverManifestEntry.fromJson(Map<String, dynamic> json) {
    return CoverManifestEntry(
      recipeId: json['recipeId'] as String,
      recipeName: json['recipeName'] as String,
      category: json['category'] as String,
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      bytes: (json['bytes'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      aiGenerated: json['aiGenerated'] as bool? ?? false,
      aiCoverVersion: json['aiCoverVersion'] as String?,
    );
  }

  Map<String, dynamic> toDownloadedJson(String coverVersion) => {
    'recipeId': recipeId,
    'recipeName': recipeName,
    'category': category,
    'sha256': sha256,
    'coverVersion': coverVersion,
  };
}

@immutable
class CoverManifest {
  final String coverVersion;
  final String dataVersion;
  final List<CoverManifestEntry> covers;

  const CoverManifest({
    required this.coverVersion,
    required this.dataVersion,
    required this.covers,
  });

  factory CoverManifest.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 2 ||
        json['mediaType'] != 'recipe-cover-snapshot') {
      throw const FormatException('不受支持的封面清单格式');
    }
    final coversJson = json['covers'];
    if (coversJson is! List) throw const FormatException('封面清单缺少 covers');
    return CoverManifest(
      coverVersion: json['coverVersion'] as String,
      dataVersion: json['dataVersion'] as String,
      covers: coversJson
          .map(
            (item) => CoverManifestEntry.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, CoverManifestEntry> get byRecipeId => {
    for (final entry in covers) entry.recipeId: entry,
  };
}

@immutable
class CoverUpdateCandidate {
  final String coverVersion;
  final CoverManifestEntry entry;
  final String localPath;

  const CoverUpdateCandidate({
    required this.coverVersion,
    required this.entry,
    required this.localPath,
  });
}

@immutable
class CoverUpdatePlan {
  final CoverManifest manifest;
  final List<CoverUpdateCandidate> downloads;
  final int removedStaleCaches;

  const CoverUpdatePlan({
    required this.manifest,
    required this.downloads,
    required this.removedStaleCaches,
  });
}

class CoverManifestService {
  static const bundledManifestPath = 'assets/covers/manifest.json';
  static const _downloadedIndexName = '.downloaded-cover-index.json';

  final AssetBundle _assetBundle;
  final Future<Directory> Function() _documentsDirectory;

  CoverManifestService({
    AssetBundle? assetBundle,
    Future<Directory> Function()? documentsDirectory,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  Future<CoverManifest?> loadBundledManifest() async {
    try {
      final content = await _assetBundle.loadString(bundledManifestPath);
      return CoverManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(content) as Map),
      );
    } catch (error) {
      debugPrint('⚠️ 无法读取内置封面清单: $error');
      return null;
    }
  }

  /// 返回当前菜谱可展示的 AI 封面（本地更新缓存优先，其次 APK 内置资源）。
  ///
  /// 下载索引里只记录 AI 封面，因此即使远端新增的封面尚未包含在当前 APK 的
  /// manifest 中，也能通过索引恢复。旧版索引按 ID 找不到时再用分类和菜名兼容。
  Future<String?> resolveAiCoverPath({
    required String recipeId,
    required List<String> legacyIds,
    required String recipeName,
    required String category,
  }) async {
    final coverRoot = await _coverCacheRoot();
    final downloaded = await _readDownloadedIndex(coverRoot);
    Map<String, dynamic>? downloadedEntry = downloaded[recipeId];
    downloadedEntry ??= downloaded.values
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (entry) =>
              entry?['category'] == category &&
              entry?['recipeName'] == recipeName,
          orElse: () => null,
        );
    if (downloadedEntry != null) {
      final file = File(p.join(coverRoot.path, category, '$recipeName.webp'));
      await _recoverPreviousCover(file);
      if (await file.exists()) return file.path;
    }

    final bundled = await loadBundledManifest();
    if (bundled == null) return null;
    final acceptedIds = <String>{recipeId, ...legacyIds};
    final entry = bundled.covers.cast<CoverManifestEntry?>().firstWhere(
      (item) =>
          item != null &&
          item.aiGenerated &&
          ((acceptedIds.contains(item.recipeId)) ||
              (item.category == category && item.recipeName == recipeName)),
      orElse: () => null,
    );
    return entry == null ? null : 'assets/${entry.path}';
  }

  Future<int> reconcileBundledAiCoverCache() async {
    final bundled = await loadBundledManifest();
    if (bundled == null) return 0;
    final coverRoot = await _coverCacheRoot();
    final downloaded = await _readDownloadedIndex(coverRoot);
    var removed = 0;
    var indexChanged = false;

    for (final entry in bundled.covers.where((item) => item.aiGenerated)) {
      final file = _coverFile(coverRoot, entry);
      await _recoverPreviousCover(file);
      if (!await file.exists()) continue;
      final cachedHash = await _hashFile(file);
      final downloadedEntry = downloaded[entry.recipeId];
      final action = decideBundledCoverCacheAction(
        aiGenerated: entry.aiGenerated,
        cachedHash: cachedHash,
        bundledHash: entry.sha256,
        downloadedHash: downloadedEntry?['sha256'] as String?,
        downloadedVersion: downloadedEntry?['coverVersion'] as String?,
        bundledVersion: bundled.coverVersion,
      );
      if (action != CoverCacheAction.remove) continue;
      await _evictAndDelete(file);
      downloaded.remove(entry.recipeId);
      indexChanged = true;
      removed++;
    }

    if (indexChanged) await _writeDownloadedIndex(coverRoot, downloaded);
    if (removed > 0) debugPrint('✅ 已清理 $removed 张被新版内置 AI 封面替代的旧缓存');
    return removed;
  }

  Future<CoverUpdatePlan> prepareRemoteUpdates(CoverManifest remote) async {
    final bundled = await loadBundledManifest();
    final bundledEntries =
        bundled?.byRecipeId ?? const <String, CoverManifestEntry>{};
    final coverRoot = await _coverCacheRoot();
    final downloaded = await _readDownloadedIndex(coverRoot);
    final candidates = <CoverUpdateCandidate>[];
    var removed = 0;
    var indexChanged = false;

    for (final entry in remote.covers.where((item) => item.aiGenerated)) {
      final file = _coverFile(coverRoot, entry);
      await _recoverPreviousCover(file);
      final cachedHash = await file.exists() ? await _hashFile(file) : null;
      final action = decideRemoteCoverCacheAction(
        aiGenerated: entry.aiGenerated,
        cachedHash: cachedHash,
        bundledHash: bundledEntries[entry.recipeId]?.sha256,
        remoteHash: entry.sha256,
      );
      switch (action) {
        case CoverCacheAction.keep:
          if (cachedHash == entry.sha256) {
            downloaded[entry.recipeId] = entry.toDownloadedJson(
              remote.coverVersion,
            );
            indexChanged = true;
          }
        case CoverCacheAction.remove:
          await _evictAndDelete(file);
          downloaded.remove(entry.recipeId);
          indexChanged = true;
          removed++;
        case CoverCacheAction.download:
          candidates.add(
            CoverUpdateCandidate(
              coverVersion: remote.coverVersion,
              entry: entry,
              localPath: file.path,
            ),
          );
      }
    }

    if (indexChanged) await _writeDownloadedIndex(coverRoot, downloaded);
    return CoverUpdatePlan(
      manifest: remote,
      downloads: candidates,
      removedStaleCaches: removed,
    );
  }

  Future<void> recordDownloadedCover({
    required String coverVersion,
    required CoverManifestEntry entry,
  }) async {
    final coverRoot = await _coverCacheRoot();
    final downloaded = await _readDownloadedIndex(coverRoot);
    downloaded[entry.recipeId] = entry.toDownloadedJson(coverVersion);
    await _writeDownloadedIndex(coverRoot, downloaded);
  }

  Future<Directory> _coverCacheRoot() async {
    final documents = await _documentsDirectory();
    return Directory(p.join(documents.path, 'recipe_images', 'covers'));
  }

  File _coverFile(Directory root, CoverManifestEntry entry) {
    if (_isUnsafePathPart(entry.category) ||
        _isUnsafePathPart(entry.recipeName)) {
      throw const FormatException('封面清单包含不安全路径');
    }
    return File(p.join(root.path, entry.category, '${entry.recipeName}.webp'));
  }

  bool _isUnsafePathPart(String value) =>
      value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains('\\');

  Future<Map<String, Map<String, dynamic>>> _readDownloadedIndex(
    Directory root,
  ) async {
    final file = File(p.join(root.path, _downloadedIndexName));
    final previous = File('${file.path}.previous');
    if (!await file.exists() && await previous.exists()) {
      await previous.rename(file.path);
    }
    if (!await file.exists()) return {};
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      final entries = json['entries'];
      if (entries is! Map) return {};
      return entries.map(
        (key, value) =>
            MapEntry(key.toString(), Map<String, dynamic>.from(value as Map)),
      );
    } catch (error) {
      debugPrint('⚠️ 本地封面索引损坏，将重新建立: $error');
      return {};
    }
  }

  Future<void> _writeDownloadedIndex(
    Directory root,
    Map<String, Map<String, dynamic>> entries,
  ) async {
    await root.create(recursive: true);
    final file = File(p.join(root.path, _downloadedIndexName));
    final temporary = File('${file.path}.next');
    final previous = File('${file.path}.previous');
    await temporary.writeAsString(
      jsonEncode({'schemaVersion': 1, 'entries': entries}),
      flush: true,
    );
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    try {
      await temporary.rename(file.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }

  Future<String> _hashFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _recoverPreviousCover(File file) async {
    final previous = File('${file.path}.previous');
    if (!await previous.exists()) return;
    if (await file.exists()) {
      await previous.delete();
    } else {
      await previous.rename(file.path);
    }
  }

  Future<void> _evictAndDelete(File file) async {
    if (!await file.exists()) return;
    PaintingBinding.instance.imageCache.evict(FileImage(file));
    await file.delete();
  }
}

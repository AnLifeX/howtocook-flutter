import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/core/services/cover_manifest_service.dart';

class _ManifestAssetBundle extends CachingAssetBundle {
  final String manifest;

  _ManifestAssetBundle(this.manifest);

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(manifest));
    return ByteData.view(bytes.buffer);
  }
}

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, dynamic> _entry({
  required String id,
  required String name,
  required String hash,
  required bool aiGenerated,
}) => {
  'recipeId': id,
  'recipeName': name,
  'category': 'test',
  'path': 'covers/test/$name.webp',
  'sha256': hash,
  'bytes': 10,
  'width': 512,
  'height': 512,
  'aiGenerated': aiGenerated,
  'aiCoverVersion': aiGenerated ? '2026.07.29.1' : null,
};

String _manifest(List<Map<String, dynamic>> covers) => jsonEncode({
  'schemaVersion': 2,
  'mediaType': 'recipe-cover-snapshot',
  'coverVersion': '2026.07.30.1',
  'dataVersion': '2026.07.28.1',
  'covers': covers,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('安装包封面缓存迁移', () {
    test('只删除已被新 AI 封面替代的旧缓存', () {
      expect(
        decideBundledCoverCacheAction(
          aiGenerated: true,
          cachedHash: 'old',
          bundledHash: 'new',
          bundledVersion: '2026.07.30.1',
        ),
        CoverCacheAction.remove,
      );
      expect(
        decideBundledCoverCacheAction(
          aiGenerated: false,
          cachedHash: 'old',
          bundledHash: 'bundled-old',
          bundledVersion: '2026.07.30.1',
        ),
        CoverCacheAction.keep,
      );
    });

    test('保留比安装包更新且有记录的下载封面', () {
      expect(
        decideBundledCoverCacheAction(
          aiGenerated: true,
          cachedHash: 'remote-new',
          bundledHash: 'bundled-old',
          downloadedHash: 'remote-new',
          downloadedVersion: '2026.08.01.1',
          bundledVersion: '2026.07.30.1',
        ),
        CoverCacheAction.keep,
      );
    });
  });

  group('远程封面替换', () {
    test('远端与内置一致时删除遮挡内置图的旧缓存', () {
      expect(
        decideRemoteCoverCacheAction(
          aiGenerated: true,
          cachedHash: 'old-cache',
          bundledHash: 'new-cover',
          remoteHash: 'new-cover',
        ),
        CoverCacheAction.remove,
      );
    });

    test('远端比内置更新时下载并替换', () {
      expect(
        decideRemoteCoverCacheAction(
          aiGenerated: true,
          cachedHash: 'old-cache',
          bundledHash: 'bundled-cover',
          remoteHash: 'remote-cover',
        ),
        CoverCacheAction.download,
      );
    });

    test('远端没有 AI 封面时保留旧缓存', () {
      expect(
        decideRemoteCoverCacheAction(
          aiGenerated: false,
          cachedHash: 'old-cache',
          bundledHash: 'bundled-cover',
          remoteHash: 'remote-cover',
        ),
        CoverCacheAction.keep,
      );
    });
  });

  test('封面版本按数字段比较', () {
    expect(
      compareCoverVersions('2026.07.30.2', '2026.07.30.1'),
      greaterThan(0),
    );
    expect(
      compareCoverVersions('2026.08.01.1', '2026.07.30.9'),
      greaterThan(0),
    );
    expect(compareCoverVersions('2026.07.30.1', '2026.07.30.1'), 0);
  });

  test('文件迁移删除已有 AI 替代图的旧缓存并保留其他封面', () async {
    final root = await Directory.systemTemp.createTemp('cover-migration-');
    addTearDown(() => root.delete(recursive: true));
    final aiFile = File(
      '${root.path}${Platform.pathSeparator}recipe_images${Platform.pathSeparator}'
      'covers${Platform.pathSeparator}test${Platform.pathSeparator}AI菜.webp',
    );
    final legacyFile = File(
      '${root.path}${Platform.pathSeparator}recipe_images${Platform.pathSeparator}'
      'covers${Platform.pathSeparator}test${Platform.pathSeparator}旧菜.webp',
    );
    await aiFile.parent.create(recursive: true);
    await aiFile.writeAsString('old-ai-cache');
    await legacyFile.writeAsString('old-cover-cache');

    final manifest = _manifest([
      _entry(
        id: 'ai',
        name: 'AI菜',
        hash: _hash('bundled-ai'),
        aiGenerated: true,
      ),
      _entry(
        id: 'legacy',
        name: '旧菜',
        hash: _hash('bundled-old'),
        aiGenerated: false,
      ),
    ]);
    final service = CoverManifestService(
      assetBundle: _ManifestAssetBundle(manifest),
      documentsDirectory: () async => root,
    );

    expect(await service.reconcileBundledAiCoverCache(), 1);
    expect(await aiFile.exists(), isFalse);
    expect(await legacyFile.exists(), isTrue);
  });

  test('远端比内置更新时保留旧图直到新图下载成功', () async {
    final root = await Directory.systemTemp.createTemp('cover-update-');
    addTearDown(() => root.delete(recursive: true));
    final cachedFile = File(
      '${root.path}${Platform.pathSeparator}recipe_images${Platform.pathSeparator}'
      'covers${Platform.pathSeparator}test${Platform.pathSeparator}AI菜.webp',
    );
    await cachedFile.parent.create(recursive: true);
    await cachedFile.writeAsString('old-cache');

    final bundledJson = _entry(
      id: 'ai',
      name: 'AI菜',
      hash: _hash('bundled-ai'),
      aiGenerated: true,
    );
    final remoteJson = Map<String, dynamic>.from(bundledJson)
      ..['sha256'] = _hash('remote-ai');
    final service = CoverManifestService(
      assetBundle: _ManifestAssetBundle(_manifest([bundledJson])),
      documentsDirectory: () async => root,
    );
    final remote = CoverManifest.fromJson(
      jsonDecode(_manifest([remoteJson])) as Map<String, dynamic>,
    );

    final plan = await service.prepareRemoteUpdates(remote);
    expect(plan.downloads, hasLength(1));
    expect(plan.removedStaleCaches, 0);
    expect(await cachedFile.readAsString(), 'old-cache');
  });

  test('只把 AI 生成封面作为详情页首图', () async {
    final root = await Directory.systemTemp.createTemp('cover-resolve-');
    addTearDown(() => root.delete(recursive: true));
    final service = CoverManifestService(
      assetBundle: _ManifestAssetBundle(
        _manifest([
          _entry(
            id: 'ai-id',
            name: 'AI菜',
            hash: _hash('ai'),
            aiGenerated: true,
          ),
          _entry(
            id: 'detail-id',
            name: '普通菜',
            hash: _hash('detail'),
            aiGenerated: false,
          ),
        ]),
      ),
      documentsDirectory: () async => root,
    );

    expect(
      await service.resolveAiCoverPath(
        recipeId: 'ai-id',
        legacyIds: const [],
        recipeName: 'AI菜',
        category: 'test',
      ),
      'assets/covers/test/AI菜.webp',
    );
    expect(
      await service.resolveAiCoverPath(
        recipeId: 'detail-id',
        legacyIds: const [],
        recipeName: '普通菜',
        category: 'test',
      ),
      isNull,
    );
  });
}

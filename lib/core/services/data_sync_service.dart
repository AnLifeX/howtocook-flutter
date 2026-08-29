import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart' as bd;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:howtocook/core/services/cover_manifest_service.dart';
import 'package:howtocook/core/services/image_download_manager.dart';
import 'package:howtocook/core/services/recipe_id_migration_service.dart';
import 'package:howtocook/core/storage/hive_service.dart';
import 'package:howtocook/features/recipe/application/providers/recipe_providers.dart';
import 'package:howtocook/features/tips/application/providers/tip_providers.dart';

part 'data_sync_service.g.dart';
part 'data_sync_service.freezed.dart';

/// 同步状态枚举
enum SyncStatus {
  idle, // 空闲
  checking, // 检查更新
  downloading, // 下载中
  paused, // 已暂停
  completed, // 已完成
  error, // 出错
}

/// 同步配置
class SyncConfig {
  final bool downloadCoverImages; // 下载封面图
  final bool downloadDetailImages; // 下载详情图
  final bool onlyWifi;
  final int maxConcurrentDownloads;

  const SyncConfig({
    this.downloadCoverImages = true,
    this.downloadDetailImages = false, // 默认不下载详情图
    this.onlyWifi = false,
    this.maxConcurrentDownloads = 3,
  });
}

/// 数据同步服务
@Riverpod(keepAlive: true)
class DataSyncService extends _$DataSyncService {
  late String _remoteBaseUrl;
  String _remoteDataBasePath = '';
  String _localDataBasePath = '';
  int _remoteSchemaVersion = 1;
  static const String _localDataDirName = 'recipe_data';
  static const String _dataTaskGroup = 'howtocook-recipe-data';
  final List<bd.DownloadTask> _activeDataTasks = [];
  bool _cancelRequested = false;

  static const List<String> _candidateBaseUrls = [
    'https://anlifex.github.io/HowToCook-assets',
    'https://cdn.jsdelivr.net/gh/AnLifeX/HowToCook-assets@main',
    'https://fastly.jsdelivr.net/gh/AnLifeX/HowToCook-assets@main',
    'https://ghfast.top/https://raw.githubusercontent.com/AnLifeX/HowToCook-assets/refs/heads/main',
  ];

  final Dio _dio = Dio();

  @override
  DataSyncState build() {
    _remoteBaseUrl = _candidateBaseUrls.first;

    return const DataSyncState(
      status: SyncStatus.idle,
      progress: 0,
      downloadedRecipes: 0,
      totalRecipes: 0,
      downloadedTips: 0,
      totalTips: 0,
      downloadedImages: 0,
      totalImages: 0,
    );
  }

  /// 开始数据同步
  Future<void> startSync(SyncConfig config) async {
    if (state.status == SyncStatus.downloading ||
        state.status == SyncStatus.paused ||
        state.status == SyncStatus.checking) {
      return;
    }
    _cancelRequested = false;
    try {
      state = state.copyWith(
        status: SyncStatus.checking,
        progress: 0,
        downloadedRecipes: 0,
        totalRecipes: 0,
        downloadedTips: 0,
        totalTips: 0,
        downloadedImages: 0,
        totalImages: 0,
        message: '正在读取 V2 稳定通道...',
        error: null,
      );
      debugPrint('🔄 开始检查数据更新...');

      // 1. 下载远程索引
      final remoteIndex = await downloadRemoteIndex();
      if (remoteIndex == null) {
        state = state.copyWith(status: SyncStatus.error, error: '无法下载远程索引文件');
        return;
      }

      // 2. 检查本地索引
      debugPrint('\n🔍 检查本地索引文件...');
      final localIndex = await loadLocalIndex();
      state = state.copyWith(message: '正在比较本地与远程数据...');

      if (localIndex == null || localIndex.isEmpty) {
        debugPrint('⚠️  本地索引为空，可能是首次同步或数据丢失');
      } else {
        debugPrint('✅ 本地索引加载成功，开始比对...');
      }

      // 3. 识别需要更新的食谱与教程
      final recipeUpdates = identifyUpdates(localIndex, remoteIndex);
      final tipUpdates = identifyTipUpdates(localIndex, remoteIndex);

      state = state.copyWith(
        totalRecipes: recipeUpdates.length,
        totalTips: tipUpdates.length,
        totalImages: _estimateImageCount(recipeUpdates),
        progress: 5,
      );

      final totalJsonTasks = recipeUpdates.length + tipUpdates.length;

      if (totalJsonTasks == 0) {
        // JSON 无变化时也重试可能曾中断的幂等 ID 迁移。
        state = state.copyWith(
          status: SyncStatus.downloading,
          progress: 95,
          message: '正在确认本地数据迁移状态...',
        );
        await _downloadAndMigrateRecipeIds(remoteIndex);
        state = state.copyWith(
          status: SyncStatus.completed,
          progress: 100,
          message: 'V2 数据已是最新版本',
        );
        debugPrint('✅ 数据已是最新，无需更新');
        return;
      }

      // 4. 开始下载更新的 JSON 文件
      state = state.copyWith(
        status: SyncStatus.downloading,
        progress: 5,
        message: '准备下载 $totalJsonTasks 个 JSON 文件...',
      );
      debugPrint(
        '📥 开始下载 ${recipeUpdates.length} 个食谱与 ${tipUpdates.length} 个教程更新...',
      );

      final coverImageTasks = <DownloadTask>[];
      final detailImageTasks = <DownloadTask>[];
      final jsonDownloaded = await _downloadJsonBatch(
        recipeUpdates: recipeUpdates,
        tipUpdates: tipUpdates,
        onlyWifi: config.onlyWifi,
      );
      if (!jsonDownloaded || _cancelRequested) {
        return;
      }

      for (final update in recipeUpdates) {
        if (config.downloadCoverImages) {
          final coverTask = await extractCoverImageTask(update);
          if (coverTask != null) coverImageTasks.add(coverTask);
        }
        if (config.downloadDetailImages) {
          detailImageTasks.addAll(await extractDetailImageTasks(update));
        }
      }

      // 5. 先原子激活 V2；迁移失败时 legacyIds 仍能兼容旧收藏。
      state = state.copyWith(progress: 92, message: '正在校验并激活 V2 数据...');
      debugPrint('\n💾 保存更新后的本地索引...');
      await saveLocalIndex(remoteIndex);
      debugPrint('✅ 本地索引保存完成');
      state = state.copyWith(progress: 96, message: '正在迁移旧版收藏和笔记...');
      await _downloadAndMigrateRecipeIds(remoteIndex);

      // 6. 开始下载图片
      final allImageTasks = [...coverImageTasks, ...detailImageTasks];
      if (allImageTasks.isNotEmpty) {
        debugPrint('🖼️ 开始下载图片...');
        debugPrint('  - 封面图: ${coverImageTasks.length} 张');
        debugPrint('  - 详情图: ${detailImageTasks.length} 张');

        allImageTasks.sort((a, b) => a.priority.compareTo(b.priority));
        ref
            .read(imageDownloadManagerProvider.notifier)
            .addDownloadTasks(allImageTasks);
      }

      state = state.copyWith(
        status: SyncStatus.completed,
        progress: 100,
        message: 'V2 数据已下载、迁移并激活',
      );
      _refreshRecipeProviders();
      debugPrint('✅ 数据同步完成');
    } catch (e) {
      if (_cancelRequested) return;
      state = state.copyWith(status: SyncStatus.error, error: e.toString());
      debugPrint('❌ 数据同步失败: $e');
    } finally {
      if (state.status != SyncStatus.paused) _activeDataTasks.clear();
    }
  }

  void _refreshRecipeProviders() {
    ref.invalidate(bundledDataLoaderProvider);
    ref.invalidate(recipeRepositoryProvider);
    ref.invalidate(manifestProvider);
    ref.invalidate(allRecipesProvider);
    ref.invalidate(favoriteRecipesProvider);
    ref.invalidate(favoriteIdsProvider);
    ref.invalidate(tipRepositoryProvider);
    ref.invalidate(allTipsProvider);
    ref.invalidate(favoriteTipsProvider);
  }

  Future<bool> _downloadJsonBatch({
    required List<RecipeUpdate> recipeUpdates,
    required List<TipUpdate> tipUpdates,
    required bool onlyWifi,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final tasks = <bd.DownloadTask>[];
    final recipeTaskIds = <String>{};
    final tipTaskIds = <String>{};

    Future<void> addTask({
      required String taskId,
      required String url,
      required String localPath,
      required bool recipe,
    }) async {
      final target = File(localPath);
      await target.parent.create(recursive: true);
      final (baseDirectory, directory, filename) = await bd.Task.split(
        filePath: target.path,
      );
      tasks.add(
        bd.DownloadTask(
          taskId: taskId,
          url: url,
          filename: filename,
          directory: directory,
          baseDirectory: baseDirectory,
          group: _dataTaskGroup,
          updates: bd.Updates.status,
          retries: 2,
          allowPause: true,
          priority: 0,
          requiresWiFi: onlyWifi,
          displayName: recipe ? '菜谱数据' : '烹饪教程',
        ),
      );
      (recipe ? recipeTaskIds : tipTaskIds).add(taskId);
    }

    for (final update in recipeUpdates) {
      await addTask(
        taskId: 'data_recipe_${update.recipeId}',
        url:
            '$_remoteBaseUrl/$_remoteDataBasePath/recipes/${update.category}/${update.recipeId}.json',
        localPath:
            '${documents.path}/$_localDataDirName/$_remoteDataBasePath/recipes/${update.category}/${update.recipeId}.json',
        recipe: true,
      );
    }
    for (final update in tipUpdates) {
      await addTask(
        taskId: 'data_tip_${update.tipId}',
        url:
            '$_remoteBaseUrl/$_remoteDataBasePath/tips/${update.category}/${update.tipId}.json',
        localPath:
            '${documents.path}/$_localDataDirName/$_remoteDataBasePath/tips/${update.category}/${update.tipId}.json',
        recipe: false,
      );
    }

    _activeDataTasks
      ..clear()
      ..addAll(tasks);
    final completedRecipeIds = <String>{};
    final completedTipIds = <String>{};
    final downloader = bd.FileDownloader();
    await downloader.ready;
    downloader.configureNotificationForGroup(
      _dataTaskGroup,
      running: const bd.TaskNotification(
        '正在下载 V2 菜谱数据',
        '{progress} · {networkSpeed}',
      ),
      paused: const bd.TaskNotification('V2 数据下载已暂停', '返回应用可继续或取消'),
      complete: const bd.TaskNotification('V2 数据下载完成', '正在校验并激活数据'),
      error: const bd.TaskNotification('V2 数据下载失败', '请返回应用重试'),
      progressBar: true,
    );

    final batch = await downloader.downloadBatch(
      tasks,
      batchProgressCallback: (succeeded, failed) {
        if (_cancelRequested || state.status == SyncStatus.paused) return;
        final completed = succeeded + failed;
        state = state.copyWith(
          progress: 5 + ((completed / tasks.length) * 85).round(),
          message: '后台下载数据 $completed/${tasks.length}',
        );
      },
      taskStatusCallback: (update) {
        if (update.status != bd.TaskStatus.complete) return;
        final taskId = update.task.taskId;
        if (recipeTaskIds.contains(taskId)) completedRecipeIds.add(taskId);
        if (tipTaskIds.contains(taskId)) completedTipIds.add(taskId);
        if (_cancelRequested) return;
        state = state.copyWith(
          downloadedRecipes: completedRecipeIds.length,
          downloadedTips: completedTipIds.length,
        );
      },
    );

    if (_cancelRequested) return false;
    if (batch.numFailed > 0 ||
        completedRecipeIds.length != recipeUpdates.length ||
        completedTipIds.length != tipUpdates.length) {
      state = state.copyWith(
        status: SyncStatus.error,
        error: '有 ${batch.numFailed} 个数据文件下载失败，已保留当前数据版本',
      );
      return false;
    }
    return true;
  }

  Future<void> pauseSync() async {
    if (state.status != SyncStatus.downloading || _activeDataTasks.isEmpty) {
      return;
    }
    final paused = await bd.FileDownloader().pauseAll(tasks: _activeDataTasks);
    if (paused.isEmpty) return;
    state = state.copyWith(status: SyncStatus.paused, message: '数据下载已暂停');
  }

  Future<void> resumeSync() async {
    if (state.status != SyncStatus.paused || _activeDataTasks.isEmpty) return;
    state = state.copyWith(
      status: SyncStatus.downloading,
      message: '正在继续后台下载...',
    );
    await bd.FileDownloader().resumeAll(tasks: _activeDataTasks);
  }

  Future<void> cancelSync() async {
    if (_activeDataTasks.isEmpty) return;
    _cancelRequested = true;
    await bd.FileDownloader().cancelTasksWithIds(
      _activeDataTasks.map((task) => task.taskId),
    );
    _activeDataTasks.clear();
    state = const DataSyncState(
      status: SyncStatus.idle,
      progress: 0,
      downloadedRecipes: 0,
      totalRecipes: 0,
      downloadedTips: 0,
      totalTips: 0,
      downloadedImages: 0,
      totalImages: 0,
      message: '数据下载已取消',
    );
  }

  /// 下载远程清单文件
  Future<Map<String, dynamic>?> downloadRemoteIndex() async {
    for (final baseUrl in _candidateBaseUrls) {
      try {
        final nonce = DateTime.now().millisecondsSinceEpoch;
        final channelUrl = '$baseUrl/channels/v2-stable.json?t=$nonce';
        debugPrint('🌐 正在下载 V2 稳定通道: $channelUrl');
        final channelResponse = await _dio.get(
          channelUrl,
          options: Options(receiveTimeout: const Duration(seconds: 10)),
        );
        if (channelResponse.statusCode != 200) continue;

        final channel = _asJsonMap(channelResponse.data);
        if (channel['schemaVersion'] != 2 || channel['channel'] != 'stable') {
          throw const FormatException('不受支持的 V2 通道格式');
        }
        final manifestPath = channel['manifestPath'] as String?;
        if (manifestPath == null || manifestPath.isEmpty) {
          throw const FormatException('V2 通道缺少 manifestPath');
        }

        final manifestUrl = '$baseUrl/$manifestPath';
        debugPrint('🌐 正在下载 V2 清单: $manifestUrl');
        final manifestResponse = await _dio.get(
          manifestUrl,
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        );
        if (manifestResponse.statusCode != 200) continue;

        final data = _asJsonMap(manifestResponse.data);
        if (data['schemaVersion'] != 2 || data['basePath'] == null) {
          throw const FormatException('远程清单不是有效的 V2 manifest');
        }

        _remoteBaseUrl = baseUrl;
        _remoteDataBasePath = data['basePath'] as String;
        _remoteSchemaVersion = 2;
        debugPrint('✅ V2 远程清单下载成功 (源: $baseUrl):');
        debugPrint('   - 数据版本: ${data['dataVersion']}');
        debugPrint('   - 资源路径: $_remoteDataBasePath');
        debugPrint('   - 总食谱数: ${data['totalRecipes']}');
        return data;
      } on DioException catch (e) {
        debugPrint('⚠️ 源 $baseUrl 失败: ${e.type} - ${e.message}');
        continue;
      } catch (e) {
        debugPrint('⚠️ 源 $baseUrl 失败: $e');
        continue;
      }
    }

    debugPrint('❌ 所有数据源均无法连接');
    return null;
  }

  /// 下载独立于菜谱数据版本的 AI 封面快照清单。
  Future<CoverManifest?> downloadRemoteCoverManifest() async {
    for (final baseUrl in _candidateBaseUrls) {
      try {
        final nonce = DateTime.now().millisecondsSinceEpoch;
        final channelUrl = '$baseUrl/channels/v2-covers-stable.json?t=$nonce';
        debugPrint('🌐 正在下载封面稳定通道: $channelUrl');
        final channelResponse = await _dio.get(
          channelUrl,
          options: Options(receiveTimeout: const Duration(seconds: 10)),
        );
        if (channelResponse.statusCode != 200) continue;

        final channel = _asJsonMap(channelResponse.data);
        if (channel['schemaVersion'] != 2 ||
            channel['channel'] != 'stable' ||
            channel['mediaType'] != 'recipe-cover-snapshot') {
          throw const FormatException('不受支持的封面稳定通道格式');
        }
        final manifestPath = channel['manifestPath'] as String?;
        if (manifestPath == null ||
            manifestPath.isEmpty ||
            manifestPath.contains('..') ||
            manifestPath.contains('://')) {
          throw const FormatException('封面通道缺少安全的 manifestPath');
        }

        final manifestUrl = '$baseUrl/$manifestPath?t=$nonce';
        final manifestResponse = await _dio.get(
          manifestUrl,
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        );
        if (manifestResponse.statusCode != 200) continue;
        final manifest = CoverManifest.fromJson(
          _asJsonMap(manifestResponse.data),
        );
        if (manifest.coverVersion != channel['coverVersion']) {
          throw const FormatException('封面通道与清单版本不一致');
        }
        _remoteBaseUrl = baseUrl;
        debugPrint(
          '✅ 封面清单下载成功: ${manifest.coverVersion} '
          '(${manifest.covers.where((item) => item.aiGenerated).length} 张 AI 封面)',
        );
        return manifest;
      } on DioException catch (error) {
        debugPrint('⚠️ 封面源 $baseUrl 失败: ${error.type} - ${error.message}');
      } catch (error) {
        debugPrint('⚠️ 封面源 $baseUrl 失败: $error');
      }
    }
    debugPrint('❌ 所有封面数据源均无法连接');
    return null;
  }

  /// 比较远端、内置资源和本地缓存，只生成确实需要替换的 AI 封面任务。
  Future<CoverSyncPlan> prepareCoverSync() async {
    final remote = await downloadRemoteCoverManifest();
    if (remote == null) throw StateError('无法下载远程封面清单');
    final updatePlan = await CoverManifestService().prepareRemoteUpdates(
      remote,
    );
    final tasks = updatePlan.downloads
        .map((candidate) {
          final entry = candidate.entry;
          final encodedPath = entry.path
              .split('/')
              .map(Uri.encodeComponent)
              .join('/');
          return DownloadTask(
            id: 'cover_${remote.coverVersion}_${entry.recipeId}',
            category: entry.category,
            recipeId: entry.recipeId,
            imageUrl:
                '$_remoteBaseUrl/$encodedPath?v=${Uri.encodeQueryComponent(remote.coverVersion)}',
            localPath: candidate.localPath,
            priority: 0,
            replaceExisting: true,
            expectedSha256: entry.sha256,
            coverVersion: remote.coverVersion,
            coverEntry: entry,
          );
        })
        .toList(growable: false);
    return CoverSyncPlan(
      coverVersion: remote.coverVersion,
      totalAiCovers: remote.covers.where((item) => item.aiGenerated).length,
      removedStaleCaches: updatePlan.removedStaleCaches,
      tasks: tasks,
    );
  }

  Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw FormatException('响应不是 JSON 对象: ${data.runtimeType}');
  }

  /// 加载本地清单文件
  Future<Map<String, dynamic>?> loadLocalIndex() async {
    try {
      // 1. 首先尝试从文档目录读取已下载的索引
      final localData = await _loadFromDocumentsDirectory();
      if (localData != null) {
        debugPrint('✅ 从文档目录加载本地索引成功');
        return localData;
      }

      // 2. 如果文档目录没有，则从assets中读取预置数据
      debugPrint('📦 文档目录无数据，尝试从assets加载预置索引...');
      final assetsData = await _loadFromAssets();
      if (assetsData != null) {
        debugPrint('✅ 从assets加载预置索引成功');
        return assetsData;
      }

      // 3. 如果都没有，返回空索引
      debugPrint('⚠️  未找到任何本地索引数据');
      return {};
    } catch (e) {
      debugPrint('❌ 加载本地清单失败: $e');
      debugPrint('   - 错误类型: ${e.runtimeType}');
      return {};
    }
  }

  /// 从文档目录加载索引
  Future<Map<String, dynamic>?> _loadFromDocumentsDirectory() async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${cacheDir.path}/$_localDataDirName');
      final manifestPath = '${cacheDir.path}/$_localDataDirName/manifest.json';
      var file = File(manifestPath);

      // 上次切换若中断在 rename 之间，使用保留的旧 manifest 恢复。
      final previousFile = File('$manifestPath.previous');
      if (!await file.exists() && await previousFile.exists()) {
        file = await previousFile.rename(manifestPath);
      }

      debugPrint('📁 尝试从文档目录加载索引: $manifestPath');

      // 检查数据目录是否存在
      if (!await dataDir.exists()) {
        debugPrint('   - ❌ 数据目录不存在');
        return null;
      }
      debugPrint('   - ✅ 数据目录存在');

      // 检查清单文件是否存在
      if (!await file.exists()) {
        debugPrint('   - ❌ 清单文件不存在');
        return null;
      }
      debugPrint('   - ✅ 清单文件存在');

      // 检查文件大小
      final fileSize = await file.length();
      debugPrint('   - 文件大小: $fileSize 字节');

      if (fileSize == 0) {
        debugPrint('   - ❌ 文件为空');
        return null;
      }

      final content = await file.readAsString();
      debugPrint('   - 文件内容长度: ${content.length} 字符');

      if (content.isEmpty) {
        debugPrint('   - ❌ 文件内容为空');
        return null;
      }

      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['schemaVersion'] == 2 && data['basePath'] is String) {
        _remoteSchemaVersion = 2;
        _localDataBasePath = data['basePath'] as String;
      }

      debugPrint('✅ 文档目录索引加载成功:');
      debugPrint('   - 版本: ${data['version']}');
      debugPrint('   - 生成时间: ${data['generatedAt']}');
      debugPrint('   - 总食谱数: ${data['totalRecipes']}');
      debugPrint(
        '   - 实际食谱数组长度: ${(data['recipes'] as List<dynamic>?)?.length ?? 0}',
      );

      return data;
    } catch (e) {
      debugPrint('❌ 从文档目录加载索引失败: $e');
      return null;
    }
  }

  /// 从assets加载预置索引
  Future<Map<String, dynamic>?> _loadFromAssets() async {
    try {
      debugPrint('📦 尝试从assets加载预置索引...');

      final String manifestContent = await rootBundle.loadString(
        'assets/manifest.json',
      );

      if (manifestContent.isEmpty) {
        debugPrint('   - ❌ assets中的manifest.json为空');
        return null;
      }

      debugPrint('   - ✅ assets文件读取成功，内容长度: ${manifestContent.length} 字符');

      final data = jsonDecode(manifestContent) as Map<String, dynamic>;

      debugPrint('✅ assets索引解析成功:');
      debugPrint('   - 版本: ${data['version']}');
      debugPrint('   - 生成时间: ${data['generatedAt']}');
      debugPrint('   - 总食谱数: ${data['totalRecipes']}');
      debugPrint(
        '   - 实际食谱数组长度: ${(data['recipes'] as List<dynamic>?)?.length ?? 0}',
      );

      if (data['recipes'] is List && (data['recipes'] as List).isNotEmpty) {
        final firstRecipe = (data['recipes'] as List)[0];
        if (firstRecipe is Map) {
          debugPrint(
            '   - 示例食谱: ${firstRecipe['name']} (${firstRecipe['id']})',
          );
        }
      }

      return data;
    } catch (e) {
      debugPrint('❌ 从assets加载索引失败: $e');
      debugPrint('   - 错误类型: ${e.runtimeType}');
      return null;
    }
  }

  /// 识别需要更新的食谱
  List<RecipeUpdate> identifyUpdates(
    Map<String, dynamic>? localIndex,
    Map<String, dynamic> remoteIndex,
  ) {
    debugPrint('🔍 开始分析需要更新的食谱...');

    final updates = <RecipeUpdate>[];
    final remoteRecipes = remoteIndex['recipes'] as List<dynamic>? ?? [];

    // 本地索引格式：{recipes: []}
    final localRecipes = localIndex?['recipes'] as List<dynamic>? ?? [];
    final remoteVersion = remoteIndex['dataVersion'] ?? remoteIndex['version'];
    final localVersion = localIndex?['dataVersion'] ?? localIndex?['version'];
    final versionChanged =
        remoteIndex['schemaVersion'] == 2 &&
        remoteVersion != null &&
        remoteVersion != localVersion;

    debugPrint('📊 数据统计:');
    debugPrint('   - 远程食谱数量: ${remoteRecipes.length}');
    debugPrint('   - 本地食谱数量: ${localRecipes.length}');

    // 创建本地食谱的映射表以便快速查找
    final localRecipeMap = <String, Map<String, dynamic>>{};
    debugPrint('\n📋 构建本地食谱映射表:');
    for (final recipe in localRecipes) {
      final recipeId = recipe['id'] as String;
      final recipeName = recipe['name'] as String? ?? '未知';
      final recipeHash = recipe['hash'] as String? ?? '无hash';
      localRecipeMap[recipeId] = recipe as Map<String, dynamic>;
      debugPrint('   - $recipeId ($recipeName): $recipeHash');
    }

    debugPrint('\n🌐 开始比对食谱...');
    int newCount = 0;
    int updateCount = 0;
    int unchangedCount = 0;
    int sampleCount = 0; // 只显示前3个示例

    for (int i = 0; i < remoteRecipes.length; i++) {
      final remoteRecipe = remoteRecipes[i];
      final recipeId = remoteRecipe['id'] as String;
      final recipeName = remoteRecipe['name'] as String? ?? '未知';
      final category = remoteRecipe['category'] as String;
      final recipeHash = remoteRecipe['hash'] as String;

      final localRecipe = versionChanged ? null : localRecipeMap[recipeId];

      if (localRecipe == null) {
        if (sampleCount < 3) {
          debugPrint(
            '   - 示例$sampleCount: $recipeName ($recipeId) - ❌ 不存在 (新增)',
          );
          sampleCount++;
        }
        updates.add(
          RecipeUpdate(
            category: category,
            recipeId: recipeId,
            lastModified: remoteRecipe['generatedAt'] as String? ?? '',
            isNew: true,
            hash: recipeHash,
          ),
        );
        newCount++;
      } else {
        final localHash = localRecipe['hash'] as String? ?? '无hash';

        if (localHash != recipeHash) {
          if (sampleCount < 3) {
            debugPrint(
              '   - 示例$sampleCount: $recipeName ($recipeId) - 🔄 hash不匹配 (更新)',
            );
            debugPrint('     本地hash: $localHash');
            debugPrint('     远程hash: $recipeHash');
            sampleCount++;
          }
          updates.add(
            RecipeUpdate(
              category: category,
              recipeId: recipeId,
              lastModified: remoteRecipe['generatedAt'] as String? ?? '',
              isNew: false,
              hash: recipeHash,
            ),
          );
          updateCount++;
        } else {
          unchangedCount++;
        }
      }
    }

    if (newCount > 3) {
      debugPrint('   - ... 还有 ${newCount - 3} 个新增食谱');
    }
    if (updateCount > 3) {
      debugPrint('   - ... 还有 ${updateCount - 3} 个更新食谱');
    }

    debugPrint('\n📈 比对结果汇总:');
    debugPrint('   - 新增食谱: $newCount 个');
    debugPrint('   - 更新食谱: $updateCount 个');
    debugPrint('   - 无需更新: $unchangedCount 个');
    debugPrint('   - 总计需要处理: ${updates.length} 个');

    return updates;
  }

  List<TipUpdate> identifyTipUpdates(
    Map<String, dynamic>? localIndex,
    Map<String, dynamic> remoteIndex,
  ) {
    debugPrint('🔍 开始分析需要更新的教程...');

    final updates = <TipUpdate>[];
    final remoteTips = remoteIndex['tips'] as List<dynamic>? ?? [];
    final localTips = localIndex?['tips'] as List<dynamic>? ?? [];
    final remoteVersion = remoteIndex['dataVersion'] ?? remoteIndex['version'];
    final localVersion = localIndex?['dataVersion'] ?? localIndex?['version'];
    final versionChanged =
        remoteIndex['schemaVersion'] == 2 &&
        remoteVersion != null &&
        remoteVersion != localVersion;

    debugPrint('📊 教程数据统计:');
    debugPrint('   - 远程教程数量: ${remoteTips.length}');
    debugPrint('   - 本地教程数量: ${localTips.length}');

    final localTipMap = <String, Map<String, dynamic>>{};
    for (final tip in localTips) {
      if (tip is Map<String, dynamic>) {
        final tipId = tip['id'] as String?;
        if (tipId != null) {
          localTipMap[tipId] = tip;
        }
      }
    }

    int newCount = 0;
    int updateCount = 0;
    int unchangedCount = 0;
    int sampleCount = 0;

    for (final remoteTip in remoteTips) {
      if (remoteTip is! Map<String, dynamic>) {
        continue;
      }
      final tipId = remoteTip['id'] as String?;
      if (tipId == null) continue;
      final category = remoteTip['category'] as String? ?? 'general';
      final title = remoteTip['title'] as String? ?? '未知';
      final remoteHash = remoteTip['hash'] as String? ?? '';

      final localTip = versionChanged ? null : localTipMap[tipId];
      final localHash = localTip?['hash'] as String? ?? '';

      if (localTip == null) {
        if (sampleCount < 3) {
          debugPrint('   - 示例$sampleCount: $title ($tipId) - ✅ 新增');
          sampleCount++;
        }
        updates.add(
          TipUpdate(
            category: category,
            tipId: tipId,
            hash: remoteHash,
            isNew: true,
          ),
        );
        newCount++;
      } else if (remoteHash != localHash) {
        if (sampleCount < 3) {
          debugPrint('   - 示例$sampleCount: $title ($tipId) - 🔁 发生变更');
          sampleCount++;
        }
        updates.add(
          TipUpdate(
            category: category,
            tipId: tipId,
            hash: remoteHash,
            isNew: false,
          ),
        );
        updateCount++;
      } else {
        unchangedCount++;
      }
    }

    if (updateCount > 3) {
      debugPrint('   - ... 还有 ${updateCount - 3} 个更新教程');
    }

    debugPrint('\n📈 教程比对结果汇总');
    debugPrint('   - 新增教程: $newCount 个');
    debugPrint('   - 更新教程: $updateCount 个');
    debugPrint('   - 无需更新: $unchangedCount 个');
    debugPrint('   - 总计需要处理 ${updates.length} 个教程');

    return updates;
  }

  /// 下载单个食谱JSON文件
  Future<bool> downloadRecipeJson(RecipeUpdate update) async {
    try {
      final url =
          '$_remoteBaseUrl/$_remoteDataBasePath/recipes/${update.category}/${update.recipeId}.json';
      final cacheDir = await getApplicationDocumentsDirectory();
      final localPath =
          '${cacheDir.path}/$_localDataDirName/$_remoteDataBasePath/recipes/${update.category}/${update.recipeId}.json';

      final file = File(localPath);
      await file.parent.create(recursive: true);

      final response = await _dio.get(url);
      if (response.data is String) {
        await file.writeAsString(response.data as String);
      } else {
        await file.writeAsString(jsonEncode(response.data));
      }

      debugPrint('✅ 食谱JSON下载完成: ${update.category}/${update.recipeId}');
      return true;
    } catch (e) {
      debugPrint('❌ 食谱JSON下载失败: ${update.category}/${update.recipeId}, 错误: $e');
      return false;
    }
  }

  /// 下载单个教程 JSON 文件
  Future<bool> downloadTipJson(TipUpdate update) async {
    try {
      final url =
          '$_remoteBaseUrl/$_remoteDataBasePath/tips/${update.category}/${update.tipId}.json';
      final cacheDir = await getApplicationDocumentsDirectory();
      final localPath =
          '${cacheDir.path}/$_localDataDirName/$_remoteDataBasePath/tips/${update.category}/${update.tipId}.json';

      final file = File(localPath);
      await file.parent.create(recursive: true);

      final response = await _dio.get(url);
      if (response.data is String) {
        await file.writeAsString(response.data as String);
      } else {
        await file.writeAsString(jsonEncode(response.data));
      }

      debugPrint('✅ 教程 JSON 下载完成: ${update.category}/${update.tipId}');
      return true;
    } catch (e) {
      debugPrint('❌ 教程 JSON 下载失败: ${update.category}/${update.tipId}, 错误: $e');
      return false;
    }
  }

  /// 提取封面图下载任务（按菜名）
  Future<DownloadTask?> extractCoverImageTask(RecipeUpdate update) async {
    try {
      // V2 封面使用独立快照清单，由 prepareCoverSync 统一按哈希更新。
      if (_remoteSchemaVersion == 2) return null;

      final cacheDir = await getApplicationDocumentsDirectory();
      final jsonPath =
          '${cacheDir.path}/$_localDataDirName/recipes/${update.category}/${update.recipeId}.json';
      final file = File(jsonPath);

      if (!await file.exists()) {
        debugPrint('⚠️  JSON文件不存在，跳过封面图提取: $jsonPath');
        return null;
      }

      final content = await file.readAsString();
      final recipeData = jsonDecode(content);
      final recipeName = recipeData['name'] as String;

      // 封面图按菜名存储：covers/{category}/{name}.webp
      final coverUrl =
          '$_remoteBaseUrl/covers/${update.category}/$recipeName.webp';
      final localPath =
          '${cacheDir.path}/recipe_images/covers/${update.category}/$recipeName.webp';

      // 检查文件是否已存在，如果存在则跳过
      final coverFile = File(localPath);
      if (await coverFile.exists()) {
        debugPrint('   ⏭️  跳过已下载的封面图: $recipeName.webp');
        return null;
      }

      debugPrint('📋 封面图下载任务:');
      debugPrint('   - 分类: ${update.category}');
      debugPrint('   - 菜名: $recipeName');
      debugPrint('   - URL: $coverUrl');
      debugPrint('   - 本地: $localPath');

      return DownloadTask(
        id: 'cover_${update.category}_${update.recipeId}',
        category: update.category,
        recipeId: update.recipeId,
        imageUrl: coverUrl,
        localPath: localPath,
        priority: 0, // 封面图优先级最高
      );
    } catch (e) {
      debugPrint('❌ 提取封面图任务失败: ${update.category}/${update.recipeId}, 错误: $e');
      return null;
    }
  }

  /// 从assets中的食谱JSON提取详情图下载任务
  Future<List<DownloadTask>> extractDetailImageTasksFromAssets(
    RecipeUpdate update,
  ) async {
    if (_remoteSchemaVersion == 2) {
      return _extractV2DetailImageTasks(update);
    }

    final tasks = <DownloadTask>[];

    try {
      // 从assets读取JSON文件，路径格式：assets/recipes/{category}/{recipeId}.json
      final assetPath =
          'assets/recipes/${update.category}/${update.recipeId}.json';

      String content;
      try {
        content = await rootBundle.loadString(assetPath);
      } catch (e) {
        // Assets中没有该文件，跳过
        return tasks;
      }

      final recipeData = jsonDecode(content);
      final images = recipeData['images'] as List<dynamic>? ?? [];

      if (images.isEmpty) {
        return tasks;
      }

      final cacheDir = await getApplicationDocumentsDirectory();

      // 提取纯净的 recipeId（去掉分类前缀）
      // 例如: "aquatic_2749d071" -> "2749d071"
      final recipeIdParts = update.recipeId.split('_');
      final pureRecipeId = recipeIdParts.length > 1
          ? recipeIdParts.sublist(1).join('_')
          : update.recipeId;

      for (int i = 0; i < images.length; i++) {
        // 详情图按纯净ID存储：images/{category}/{pureRecipeId}_$i.webp
        final imageUrl =
            '$_remoteBaseUrl/images/${update.category}/${update.recipeId}_$i.webp';
        final localPath =
            '${cacheDir.path}/recipe_images/details/${update.category}/${pureRecipeId}_$i.webp';

        // 检查文件是否已存在，如果存在则跳过
        final file = File(localPath);
        if (await file.exists()) {
          debugPrint('   ⏭️  跳过已下载的图片: ${pureRecipeId}_$i.webp');
          continue;
        }

        tasks.add(
          DownloadTask(
            id: 'detail_${update.category}_${update.recipeId}_$i',
            category: update.category,
            recipeId: update.recipeId,
            imageUrl: imageUrl,
            localPath: localPath,
            priority: 1,
          ),
        );
      }

      return tasks;
    } catch (e) {
      debugPrint(
        '❌ 从Assets提取详情图任务失败: ${update.category}/${update.recipeId}, 错误: $e',
      );
      return tasks;
    }
  }

  /// 从文档目录的食谱JSON中提取详情图下载任务（按ID）
  Future<List<DownloadTask>> extractDetailImageTasks(
    RecipeUpdate update,
  ) async {
    if (_remoteSchemaVersion == 2) {
      return _extractV2DetailImageTasks(update);
    }

    final tasks = <DownloadTask>[];

    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      // 修复：recipeId已经包含了category前缀，不需要再拼接
      final jsonPath =
          '${cacheDir.path}/$_localDataDirName/recipes/${update.category}/${update.recipeId}.json';
      final file = File(jsonPath);

      if (!await file.exists()) {
        debugPrint('!  JSON文件不存在，跳过详情图提取: $jsonPath');
        return tasks;
      }

      final content = await file.readAsString();
      final recipeData = jsonDecode(content);
      final images = recipeData['images'] as List<dynamic>? ?? [];

      if (images.isEmpty) {
        return tasks;
      }

      // 提取纯净的 recipeId（去掉分类前缀）
      // 例如: "aquatic_2749d071" -> "2749d071"
      final recipeIdParts = update.recipeId.split('_');
      final pureRecipeId = recipeIdParts.length > 1
          ? recipeIdParts.sublist(1).join('_')
          : update.recipeId;

      for (int i = 0; i < images.length; i++) {
        // 详情图按纯净ID存储：images/{category}/{pureRecipeId}_$i.webp
        final imageUrl =
            '$_remoteBaseUrl/images/${update.category}/${update.recipeId}_$i.webp';
        final localPath =
            '${cacheDir.path}/recipe_images/details/${update.category}/${pureRecipeId}_$i.webp';

        // 检查文件是否已存在，如果存在则跳过
        final file = File(localPath);
        if (await file.exists()) {
          debugPrint('   ⏭️  跳过已下载的图片: ${pureRecipeId}_$i.webp');
          continue;
        }

        debugPrint('   [$i] URL: $imageUrl');
        debugPrint('   [$i] 本地: $localPath');

        tasks.add(
          DownloadTask(
            id: 'detail_${update.category}_${update.recipeId}_$i',
            category: update.category,
            recipeId: update.recipeId,
            imageUrl: imageUrl,
            localPath: localPath,
            priority: 1, // 详情图优先级次之
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 提取详情图任务失败: ${update.category}/${update.recipeId}, 错误: $e');
    }

    return tasks;
  }

  Future<List<DownloadTask>> _extractV2DetailImageTasks(
    RecipeUpdate update,
  ) async {
    final tasks = <DownloadTask>[];
    try {
      final documents = await getApplicationDocumentsDirectory();
      File? recipeFile;
      String? dataBasePath;
      final candidatePaths = <String>{
        if (_remoteDataBasePath.isNotEmpty) _remoteDataBasePath,
        if (_localDataBasePath.isNotEmpty) _localDataBasePath,
      };
      for (final candidate in candidatePaths) {
        final file = File(
          '${documents.path}/$_localDataDirName/$candidate/'
          'recipes/${update.category}/${update.recipeId}.json',
        );
        if (await file.exists()) {
          recipeFile = file;
          dataBasePath = candidate;
          break;
        }
      }
      if (recipeFile == null || dataBasePath == null) return tasks;

      final recipe =
          jsonDecode(await recipeFile.readAsString()) as Map<String, dynamic>;
      final images = recipe['images'] as List<dynamic>? ?? const [];
      for (var index = 0; index < images.length; index++) {
        final relativePath = images[index].toString().replaceAll('\\', '/');
        final localPath =
            '${documents.path}/recipe_images/details/${update.category}/'
            '${update.recipeId}_$index.webp';
        if (await File(localPath).exists()) continue;

        tasks.add(
          DownloadTask(
            id: 'detail_${update.category}_${update.recipeId}_$index',
            category: update.category,
            recipeId: update.recipeId,
            imageUrl: '$_remoteBaseUrl/$dataBasePath/$relativePath',
            localPath: localPath,
            priority: 1,
          ),
        );
      }
    } catch (e) {
      debugPrint(
        '❌ 提取 V2 详情图任务失败: '
        '${update.category}/${update.recipeId}, 错误: $e',
      );
    }
    return tasks;
  }

  /// 保存本地清单文件
  Future<void> saveLocalIndex(Map<String, dynamic> index) async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${cacheDir.path}/$_localDataDirName');
      final manifestPath = '${cacheDir.path}/$_localDataDirName/manifest.json';
      final file = File(manifestPath);
      final nextFile = File('$manifestPath.next');
      final previousFile = File('$manifestPath.previous');

      if (index['schemaVersion'] == 2 && index['basePath'] is String) {
        _remoteSchemaVersion = 2;
        _remoteDataBasePath = index['basePath'] as String;
        _localDataBasePath = _remoteDataBasePath;
      }

      debugPrint('💾 保存本地索引文件:');
      debugPrint('   - 缓存目录: ${cacheDir.path}');
      debugPrint('   - 数据目录: ${dataDir.path}');
      debugPrint('   - 清单路径: $manifestPath');

      // 创建目录
      await file.parent.create(recursive: true);
      debugPrint('   - ✅ 目录创建完成');

      // 检查索引数据
      final recipeCount = (index['recipes'] as List<dynamic>?)?.length ?? 0;
      final tipCount = (index['tips'] as List<dynamic>?)?.length ?? 0;
      debugPrint('   - 索引包含食谱数量: $recipeCount');
      debugPrint('   - 索引包含教程数量: $tipCount');

      // 写入文件
      final jsonContent = jsonEncode(index);
      debugPrint('   - JSON内容长度: ${jsonContent.length} 字符');

      // 版本目录保留一份 manifest；根 manifest 仅作为当前激活指针。
      if (_remoteSchemaVersion == 2 && _remoteDataBasePath.isNotEmpty) {
        final versionManifest = File(
          '${dataDir.path}/$_remoteDataBasePath/manifest.json',
        );
        await versionManifest.parent.create(recursive: true);
        await versionManifest.writeAsString(jsonContent, flush: true);
      }

      await nextFile.writeAsString(jsonContent, flush: true);
      // 先完整写入临时文件；切换失败时自动恢复上一版 manifest。
      if (await previousFile.exists()) await previousFile.delete();
      if (await file.exists()) await file.rename(previousFile.path);
      try {
        await nextFile.rename(file.path);
        if (await previousFile.exists()) await previousFile.delete();
      } catch (_) {
        if (!await file.exists() && await previousFile.exists()) {
          await previousFile.rename(file.path);
        }
        rethrow;
      }

      // 验证写入结果
      final writtenSize = await file.length();
      debugPrint('   - 写入文件大小: $writtenSize 字节');
      debugPrint('   - ✅ 本地清单保存完成');
    } catch (e) {
      debugPrint('❌ 保存本地清单失败: $e');
      debugPrint('   - 错误类型: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<void> _downloadAndMigrateRecipeIds(
    Map<String, dynamic> remoteIndex,
  ) async {
    if (remoteIndex['schemaVersion'] != 2) return;
    final migrations = remoteIndex['migrations'];
    if (migrations is! Map) {
      throw const FormatException('V2 manifest 缺少 migrations');
    }
    final relativePath = migrations['recipeIdsV1ToV2'] as String?;
    if (relativePath == null || relativePath.isEmpty) {
      throw const FormatException('V2 manifest 缺少 V1→V2 ID 映射');
    }

    final url = '$_remoteBaseUrl/$_remoteDataBasePath/$relativePath';
    final response = await _dio.get(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 15)),
    );
    if (response.statusCode != 200) {
      throw StateError('ID 映射下载失败: HTTP ${response.statusCode}');
    }
    final migration = _asJsonMap(response.data);

    final documents = await getApplicationDocumentsDirectory();
    final migrationFile = File(
      '${documents.path}/$_localDataDirName/$_remoteDataBasePath/$relativePath',
    );
    await migrationFile.parent.create(recursive: true);
    await migrationFile.writeAsString(jsonEncode(migration), flush: true);

    await RecipeIdMigrationService().migrate(migration);
  }

  /// 估算图片数量
  int _estimateImageCount(List<RecipeUpdate> updates) {
    // 简单估算：每个食谱平均2张图片
    return updates.length * 2;
  }

  /// 获取本地数据大小
  Future<int> getLocalDataSize() async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${cacheDir.path}/$_localDataDirName');

      if (!await dataDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dataDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('❌ 计算本地数据大小失败: $e');
      return 0;
    }
  }

  /// 清理本地数据
  Future<void> clearLocalData() async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${cacheDir.path}/$_localDataDirName');

      if (await dataDir.exists()) {
        await dataDir.delete(recursive: true);
        debugPrint('🗑️ 本地数据已清理');
      }
      final settings = HiveService.getSettingsBox();
      await settings.delete(RecipeIdMigrationService.activeDataVersionKey);
      await settings.delete(RecipeIdMigrationService.activeDataSchemaKey);
    } catch (e) {
      debugPrint('❌ 清理本地数据失败: $e');
    }
  }
}

/// 食谱更新信息
class RecipeUpdate {
  final String category;
  final String recipeId;
  final String lastModified;
  final bool isNew;
  final String hash;

  RecipeUpdate({
    required this.category,
    required this.recipeId,
    required this.lastModified,
    required this.isNew,
    required this.hash,
  });
}

/// 教程更新信息
class TipUpdate {
  final String category;
  final String tipId;
  final String hash;
  final bool isNew;

  TipUpdate({
    required this.category,
    required this.tipId,
    required this.hash,
    required this.isNew,
  });
}

class CoverSyncPlan {
  final String coverVersion;
  final int totalAiCovers;
  final int removedStaleCaches;
  final List<DownloadTask> tasks;

  const CoverSyncPlan({
    required this.coverVersion,
    required this.totalAiCovers,
    required this.removedStaleCaches,
    required this.tasks,
  });
}

/// 数据同步状态
@freezed
class DataSyncState with _$DataSyncState {
  const factory DataSyncState({
    required SyncStatus status,
    required int progress,
    required int downloadedRecipes,
    required int totalRecipes,
    required int downloadedTips,
    required int totalTips,
    required int downloadedImages,
    required int totalImages,
    String? message,
    String? error,
  }) = _DataSyncState;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/services/app_notification_service.dart';
import 'core/services/cover_manifest_service.dart';
import 'core/services/data_sync_service.dart';
import 'core/services/update_download_service.dart';
import 'core/services/update_service.dart';
import 'core/storage/hive_service.dart';
import 'core/storage/database_manager.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/settings/presentation/widgets/update_dialog.dart';

/// 应用入口
void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储服务
  await _initializeServices();

  // 运行应用
  runApp(const ProviderScope(child: HowToCookApp()));
}

/// 初始化所有服务
Future<void> _initializeServices() async {
  try {
    // 1. 加载环境变量
    await dotenv.load(fileName: '.env');

    // 2. 初始化 Hive
    await HiveService.init();

    if (!kIsWeb) {
      // 只清理已被当前安装包内置 AI 封面替代的旧缓存；其余封面保留。
      try {
        await CoverManifestService().reconcileBundledAiCoverCache();
      } catch (error) {
        debugPrint('⚠️ 封面缓存迁移失败，已保留现有缓存: $error');
      }
    }

    // 3. 初始化 Sqflite（仅在非 Web 平台）
    if (!kIsWeb) {
      await DatabaseManager().database;
      debugPrint('✅ Sqflite 数据库已初始化');
    } else {
      debugPrint('ℹ️ Web 平台：跳过 Sqflite 初始化（使用 Hive 存储）');
    }

    // 初始化 background_downloader（仅 Android）
    await UpdateDownloadNotifier.initialize();

    // 初始化通知服务并请求权限
    if (!kIsWeb) {
      await AppNotificationService.instance.initialize();
      await AppNotificationService.instance.requestPermission();
    }

    debugPrint('✅ 所有服务初始化成功');
  } catch (e, stackTrace) {
    debugPrint('❌ 服务初始化失败: $e');
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  }
}

/// 主应用
class HowToCookApp extends ConsumerStatefulWidget {
  const HowToCookApp({super.key});

  @override
  ConsumerState<HowToCookApp> createState() => _HowToCookAppState();
}

class _HowToCookAppState extends ConsumerState<HowToCookApp> {
  bool _startupChecksScheduled = false;

  @override
  void initState() {
    super.initState();

    AppNotificationService.instance.initialize(onTap: _handleNotificationTap);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_startupChecksScheduled) return;
      _startupChecksScheduled = true;
      Future.delayed(const Duration(seconds: 3), () {
        _silentCheckUpdate();
        _silentCheckDataSync();
      });
    });
  }

  void _handleNotificationTap(String? payload) {
    if (payload == 'data-sync') {
      final router = ref.read(routerProvider);
      router.push('/data-sync');
    } else if (payload == 'ai-chat') {
      final router = ref.read(routerProvider);
      router.go('/ai-chat');
    }
  }

  Future<void> _silentCheckUpdate() async {
    if (!mounted || kIsWeb) return;
    try {
      final service = ref.read(updateServiceProvider);
      final result = await service.checkForUpdate();
      if (!mounted || !result.hasUpdate || result.info == null) return;

      final router = ref.read(routerProvider);
      final navigatorContext =
          router.routerDelegate.navigatorKey.currentContext;
      if (navigatorContext == null || !navigatorContext.mounted) return;

      await showUpdateDialog(
        context: navigatorContext,
        ref: ref,
        info: result.info!,
        currentVersionName: result.currentVersionName,
      );
    } catch (e) {
      debugPrint('⚠️ 启动更新检查失败（已静默忽略）：$e');
    }
  }

  Future<void> _silentCheckDataSync() async {
    if (!mounted || kIsWeb) return;
    try {
      final syncService = ref.read(dataSyncServiceProvider.notifier);

      final remoteIndex = await syncService.downloadRemoteIndex();
      if (remoteIndex == null || !mounted) return;

      final localIndex = await syncService.loadLocalIndex();

      final recipeUpdates = syncService.identifyUpdates(
        localIndex,
        remoteIndex,
      );
      final tipUpdates = syncService.identifyTipUpdates(
        localIndex,
        remoteIndex,
      );

      final newRecipes = recipeUpdates.where((u) => u.isNew).length;
      final updatedRecipes = recipeUpdates.where((u) => !u.isNew).length;
      final newTips = tipUpdates.where((u) => u.isNew).length;
      final updatedTips = tipUpdates.where((u) => !u.isNew).length;

      if (newRecipes + updatedRecipes + newTips + updatedTips > 0) {
        await AppNotificationService.instance.showDataUpdateNotification(
          newRecipes: newRecipes,
          updatedRecipes: updatedRecipes,
          newTips: newTips,
          updatedTips: updatedTips,
        );
      }

      // 检查详情图初始化下载
      if (!mounted) return;
      await _silentCheckMissingImages(syncService, localIndex);
    } catch (e) {
      debugPrint('⚠️ 启动数据同步检查失败（已静默忽略）：$e');
    }
  }

  Future<void> _silentCheckMissingImages(
    DataSyncService syncService,
    Map<String, dynamic>? localIndex,
  ) async {
    if (localIndex == null || localIndex.isEmpty) return;

    final recipes = localIndex['recipes'] as List<dynamic>? ?? [];
    if (recipes.isEmpty) return;

    int missingImages = 0;

    for (final recipe in recipes) {
      final hasImages = recipe['hasImages'] as bool? ?? false;
      if (!hasImages) continue;

      final recipeId = recipe['id'] as String;
      final category = recipe['category'] as String;

      final update = RecipeUpdate(
        category: category,
        recipeId: recipeId,
        lastModified: '',
        isNew: false,
        hash: recipe['hash'] as String? ?? '',
      );

      final tasks = await syncService.extractDetailImageTasksFromAssets(update);
      missingImages += tasks.length;

      if (!mounted) return;
    }

    if (missingImages > 0) {
      await AppNotificationService.instance.showImageDownloadNotification(
        missingImages: missingImages,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(currentThemeModeProvider);

    return MaterialApp.router(
      title: '智能菜谱助手',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // 本地化配置
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'), // 简体中文
        Locale('en', 'US'), // 英文（备用）
      ],
      locale: const Locale('zh', 'CN'), // 默认语言
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/recipe/presentation/screens/recipe_home_screen.dart';
import '../../features/recipe/presentation/screens/recipe_detail_screen.dart';
import '../../features/recipe/presentation/screens/recipe_search_screen.dart';
import '../../features/recipe/presentation/screens/recipe_edit_screen.dart';
import '../../features/recipe/presentation/screens/recipe_create_screen.dart';
import '../../features/recipe/presentation/screens/favorite_recipes_screen.dart';
import '../../features/recipe/presentation/screens/qr_scanner_screen.dart';
import '../../features/recipe/presentation/screens/recipe_preview_screen.dart';
import '../../features/user/presentation/screens/my_creations_screen.dart';
import '../../features/recipe/domain/entities/recipe.dart';
import '../../features/tips/domain/entities/tip.dart';
import '../../features/ai_chat/presentation/screens/ai_chat_screen.dart';
import '../../features/user/presentation/screens/user_screen.dart';
import '../../features/settings/presentation/screens/data_sync_screen.dart';
import '../../features/settings/presentation/screens/model_management_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/tips/presentation/screens/tip_detail_screen.dart';
import '../../features/tips/presentation/screens/tip_editor_screen.dart';
import '../../features/tips/presentation/screens/tip_preview_screen.dart';
import '../../features/tips/presentation/screens/tips_overview_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/main_scaffold.dart';

/// 路由配置 Provider
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/recipes',
    routes: [
      // Shell 路由：包含底部导航的主框架
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/recipes',
                name: 'recipes',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const RecipeHomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai-chat',
                name: 'ai-chat',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const AIChatScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/user',
                name: 'user',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const UserScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // 菜谱详情（全屏页面，不显示底部导航）
      GoRoute(
        path: '/recipe/:id',
        name: 'recipe-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RecipeDetailScreen(recipeId: id);
        },
      ),

      // 菜谱编辑
      GoRoute(
        path: '/recipe/:id/edit',
        name: 'recipe-edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RecipeEditScreen(recipeId: id);
        },
      ),

      // 搜索页面
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) {
          return const RecipeSearchScreen();
        },
      ),

      // 创建菜谱
      GoRoute(
        path: '/create-recipe',
        name: 'create-recipe',
        builder: (context, state) {
          return const RecipeCreateScreen();
        },
      ),

      // 收藏列表
      GoRoute(
        path: '/favorites',
        name: 'favorites',
        builder: (context, state) {
          return const FavoriteRecipesScreen();
        },
      ),

      // 我的自创
      GoRoute(
        path: '/my-creations',
        name: 'my-creations',
        builder: (context, state) {
          return const MyCreationsScreen();
        },
      ),

      // 模型管理
      GoRoute(
        path: '/model-management',
        name: 'model-management',
        builder: (context, state) {
          return const ModelManagementScreen();
        },
      ),

      // 数据同步
      GoRoute(
        path: '/data-sync',
        name: 'data-sync',
        builder: (context, state) {
          return const DataSyncScreen();
        },
      ),

      // 设置
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) {
          return const SettingsScreen();
        },
      ),

      // 关于
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) {
          return const AboutScreen();
        },
      ),

      // 教程中心
      GoRoute(
        path: '/tips',
        name: 'tips-overview',
        builder: (context, state) {
          return const TipsOverviewScreen();
        },
      ),

      // 新建教程
      GoRoute(
        path: '/tips/create',
        name: 'tips-create',
        builder: (context, state) {
          final initialCategory = state.uri.queryParameters['category'];
          return TipEditorScreen(initialCategory: initialCategory);
        },
      ),

      GoRoute(
        path: '/tip-preview',
        name: 'tip-preview',
        builder: (context, state) {
          final tip = state.extra as Tip?;
          if (tip == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('错误')),
              body: const Center(child: Text('未提供教程数据')),
            );
          }
          return TipPreviewScreen(tip: tip);
        },
      ),

      // 编辑教程
      GoRoute(
        path: '/tips/:tipId/edit',
        name: 'tips-edit',
        builder: (context, state) {
          final tipId = state.pathParameters['tipId']!;
          return TipEditorScreen(tipId: tipId);
        },
      ),

      // 教程详情
      // 格式: /tips/:category/:tipsId
      GoRoute(
        path: '/tips/:category/:tipsId',
        name: 'tips-detail',
        builder: (context, state) {
          final category = state.pathParameters['category'] ?? '';
          final tipId = state.pathParameters['tipsId'] ?? '';
          return TipDetailScreen(category: category, tipId: tipId);
        },
      ),

      // 二维码扫描
      GoRoute(
        path: '/qr-scanner',
        name: 'qr-scanner',
        builder: (context, state) {
          return const QRScannerScreen();
        },
      ),

      // 食谱预览（扫码导入）
      GoRoute(
        path: '/recipe-preview',
        name: 'recipe-preview',
        builder: (context, state) {
          debugPrint('🛣️  路由: /recipe-preview 被触发');
          debugPrint('  - state.extra 类型: ${state.extra.runtimeType}');
          debugPrint('  - state.extra 是否为 null: ${state.extra == null}');

          if (state.extra == null) {
            debugPrint('❌ state.extra 为 null！');
            return Scaffold(
              appBar: AppBar(title: const Text('错误')),
              body: const Center(child: Text('未提供食谱数据')),
            );
          }

          final recipe = state.extra as Recipe;
          debugPrint('✅ Recipe 数据接收成功:');
          debugPrint('  - ID: ${recipe.id}');
          debugPrint('  - Name: ${recipe.name}');

          return RecipePreviewScreen(recipe: recipe);
        },
      ),
    ],

    // 错误页面
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              '404',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(color: AppColors.textDisabled),
            ),
            const SizedBox(height: 8),
            const Text('页面不存在'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/recipes'),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    ),
  );
});

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/recipe_data_mode.dart';
import 'package:howtocook/features/ai_chat/infrastructure/services/mcp_service.dart';
import 'package:howtocook/features/ai_chat/infrastructure/services/recipe_tool_service.dart';
import 'package:howtocook/features/recipe/domain/entities/recipe.dart';
import 'package:howtocook/features/recipe/domain/repositories/recipe_repository.dart';

void main() {
  late _MemoryRecipeRepository repository;
  late RecipeToolService service;

  setUp(() {
    repository = _MemoryRecipeRepository([
      _recipe('bundled-1', '番茄炒蛋', RecipeSource.bundled, favorite: true),
      _recipe('local-1', '我的烤鸡', RecipeSource.userCreated),
      _recipe('ai-1', 'AI 香菇饭', RecipeSource.aiGenerated),
    ]);
    service = RecipeToolService(
      localRepository: repository,
      cloudService: MCPService(),
      random: Random(1),
    );
  });

  test('本地工具目录稳定排序，并仅本地暴露收藏工具', () {
    final localNames = service
        .definitionsFor(RecipeDataMode.local)
        .map((tool) => tool['name'] as String)
        .toList();
    final cloudNames = service
        .definitionsFor(RecipeDataMode.cloud)
        .map((tool) => tool['name'] as String)
        .toList();

    expect(localNames, orderedEquals([...localNames]..sort()));
    expect(localNames, contains('getFavoriteRecipes'));
    expect(cloudNames, isNot(contains('getFavoriteRecipes')));
    expect(localNames, isNot(contains('getAllRecipes')));
    expect(localNames, contains('searchRecipes'));
  });

  test('本地搜索同时读取内置、用户和已保存 AI 菜谱，并只返回摘要', () async {
    final result = await service.execute(
      mode: RecipeDataMode.local,
      toolName: 'searchRecipes',
      input: const {'query': '', 'limit': 20},
    );

    expect(result['success'], isTrue);
    final recipes = result['recipes'] as List<dynamic>;
    expect(
      recipes.map((item) => item['id']),
      containsAll(['bundled-1', 'local-1', 'ai-1']),
    );
    expect(recipes.first, isNot(contains('ingredients')));
    expect(recipes.first, isNot(contains('steps')));
  });

  test('执行层拒绝云端模式调用本地收藏工具', () async {
    final result = await service.execute(
      mode: RecipeDataMode.cloud,
      toolName: 'getFavoriteRecipes',
      input: const {},
    );

    expect(result['success'], isFalse);
    expect(result['code'], 'tool_not_allowed');
  });

  test('本地创建只生成结构化草稿，不直接写仓储', () async {
    final before = (await repository.getAllRecipes()).length;
    final result = await service.execute(
      mode: RecipeDataMode.local,
      toolName: 'createRecipe',
      input: const {
        'recipe': {
          'name': '测试汤',
          'ingredients': ['水 500ml'],
          'steps': ['煮沸'],
        },
      },
    );

    expect(result['success'], isTrue);
    expect(result['draftOnly'], isTrue);
    expect((await repository.getAllRecipes()).length, before);
  });
}

Recipe _recipe(
  String id,
  String name,
  RecipeSource source, {
  bool favorite = false,
}) {
  return Recipe(
    id: id,
    name: name,
    category: 'meat_dish',
    categoryName: '荤菜',
    difficulty: 2,
    ingredients: const [Ingredient(name: '盐', text: '盐 1克')],
    steps: const [CookingStep(description: '加热')],
    hash: id,
    source: source,
    isFavorite: favorite,
  );
}

class _MemoryRecipeRepository implements RecipeRepository {
  _MemoryRecipeRepository(this.recipes);

  final List<Recipe> recipes;

  @override
  Future<List<Recipe>> getAllRecipes() async => [...recipes];

  @override
  Future<Recipe?> getRecipeById(String id) async =>
      recipes.where((recipe) => recipe.id == id).firstOrNull;

  @override
  Future<List<Recipe>> getRecipesByCategory(String category) async => recipes
      .where(
        (recipe) =>
            recipe.category == category || recipe.categoryName == category,
      )
      .toList();

  @override
  Future<List<Recipe>> searchRecipes(String query) async => recipes
      .where(
        (recipe) =>
            recipe.name.contains(query) ||
            recipe.ingredients.any((item) => item.text.contains(query)),
      )
      .toList();

  @override
  Future<List<Recipe>> getFavoriteRecipes() async =>
      recipes.where((recipe) => recipe.isFavorite).toList();

  @override
  Future<void> saveRecipe(Recipe recipe) async => recipes.add(recipe);

  @override
  Future<void> deleteRecipe(String id) async =>
      recipes.removeWhere((recipe) => recipe.id == id);

  @override
  Future<bool> isFavorite(String id) async =>
      (await getRecipeById(id))?.isFavorite == true;

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<List<String>> getFavoriteIds() async =>
      (await getFavoriteRecipes()).map((recipe) => recipe.id).toList();

  @override
  Future<String?> getUserNote(String id) async => null;

  @override
  Future<void> updateUserNote(String id, String? note) async {}

  @override
  Future<void> saveRecipes(List<Recipe> recipes) async =>
      this.recipes.addAll(recipes);
}

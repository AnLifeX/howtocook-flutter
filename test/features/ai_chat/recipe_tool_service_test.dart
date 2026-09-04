import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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
    service = RecipeToolService(localRepository: repository, random: Random(1));
  });

  test('本地工具目录稳定排序并包含完整工具集', () {
    final names = service
        .definitions()
        .map((tool) => tool['name'] as String)
        .toList();

    expect(names, orderedEquals([...names]..sort()));
    expect(names, hasLength(11));
    expect(
      names,
      containsAll([
        'getFavoriteRecipes',
        'findRecipesByIngredients',
        'getMyRecipes',
        'getRecipePersonalInfo',
        'listRecipeCategories',
        'searchRecipes',
      ]),
    );
    expect(names, isNot(contains('getAllRecipes')));
  });

  test('本地搜索同时读取内置、用户和已保存 AI 菜谱，并只返回摘要', () async {
    final result = await service.execute(
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

  test('本地搜索兼容常见菜名别名', () async {
    final result = await service.execute(
      toolName: 'searchRecipes',
      input: const {'query': '西红柿炒蛋'},
    );

    expect(result['success'], isTrue);
    expect(result['resultCoverage'], 'complete');
    expect(
      (result['recipes'] as List<dynamic>).map((item) => item['id']),
      contains('bundled-1'),
    );
  });

  test('截断搜索结果明确提示不能判断菜谱不存在', () async {
    repository.recipes.addAll(
      List.generate(
        22,
        (index) =>
            _recipe('extra-$index', '测试菜$index', RecipeSource.userCreated),
      ),
    );
    final result = await service.execute(
      toolName: 'searchRecipes',
      input: const {'query': '', 'limit': 2},
    );

    expect(result['truncated'], isTrue);
    expect(result['resultCoverage'], 'partial');
    expect(result['warning'], contains('不能'));
  });

  test('列表工具默认返回 20 条，但调用方可以传入更大上限', () async {
    repository.recipes.addAll(
      List.generate(
        22,
        (index) =>
            _recipe('extra-$index', '测试菜$index', RecipeSource.userCreated),
      ),
    );
    final tools = service.definitions();
    for (final name in [
      'searchRecipes',
      'getRecipeById',
      'getRecipesByCategory',
      'getFavoriteRecipes',
      'findRecipesByIngredients',
      'getMyRecipes',
    ]) {
      final tool = tools.singleWhere((item) => item['name'] == name);
      final limitSchema =
          (tool['input_schema'] as Map)['properties']['limit'] as Map;
      expect(limitSchema['default'], 20, reason: name);
      expect(limitSchema, isNot(contains('maximum')), reason: name);
    }

    final defaultResult = await service.execute(
      toolName: 'searchRecipes',
      input: const {'query': ''},
    );
    final completeResult = await service.execute(
      toolName: 'searchRecipes',
      input: const {'query': '', 'limit': 25},
    );

    expect(defaultResult['count'], 20);
    expect(defaultResult['truncated'], isTrue);
    expect(completeResult['count'], 25);
    expect(completeResult['truncated'], isFalse);
  });

  test('执行层拒绝未授权工具', () async {
    final result = await service.execute(
      toolName: 'unknownTool',
      input: const {},
    );

    expect(result['success'], isFalse);
    expect(result['code'], 'tool_not_allowed');
  });

  test('本地创建只生成结构化草稿，不直接写仓储', () async {
    final before = (await repository.getAllRecipes()).length;
    final result = await service.execute(
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

  test('现有食材匹配优先返回缺少食材更少的菜谱，并排除忌口', () async {
    repository.recipes.addAll([
      _recipeWithIngredients('tomato-egg', '番茄炒蛋', ['番茄', '鸡蛋']),
      _recipeWithIngredients('egg-rice', '蛋炒饭', ['鸡蛋', '米饭', '火腿']),
    ]);

    final result = await service.execute(
      toolName: 'findRecipesByIngredients',
      input: const {
        'ingredients': ['西红柿', '鸡蛋'],
        'excludeIngredients': ['火腿'],
      },
    );

    final recipes = result['recipes'] as List<dynamic>;
    expect(recipes.first['id'], 'tomato-egg');
    expect(recipes.map((item) => item['id']), isNot(contains('egg-rice')));
    expect(recipes.first['missingIngredientCount'], 0);
  });

  test('本地专属工具可读取分类、我的菜谱和个人信息', () async {
    final categories = await service.execute(
      toolName: 'listRecipeCategories',
      input: const {},
    );
    final mine = await service.execute(
      toolName: 'getMyRecipes',
      input: const {},
    );
    final personal = await service.execute(
      toolName: 'getRecipePersonalInfo',
      input: const {'id': 'bundled-1'},
    );

    expect(categories['categories'], hasLength(1));
    expect(
      (mine['recipes'] as List).map((item) => item['id']),
      containsAll(['local-1', 'ai-1']),
    );
    expect(personal['isFavorite'], isTrue);
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

Recipe _recipeWithIngredients(
  String id,
  String name,
  List<String> ingredients,
) {
  return Recipe(
    id: id,
    name: name,
    category: 'vegetable_dish',
    categoryName: '素菜',
    difficulty: 2,
    ingredients: ingredients
        .map((name) => Ingredient(name: name, text: '$name 适量'))
        .toList(),
    steps: const [CookingStep(description: '加热')],
    hash: id,
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

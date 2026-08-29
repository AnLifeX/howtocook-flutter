import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/core/services/recipe_image_policy.dart';
import 'package:howtocook/features/recipe/domain/entities/recipe.dart';

void main() {
  Recipe recipe({
    required String id,
    required RecipeSource source,
    required List<String> images,
  }) => Recipe(
    id: id,
    name: '测试菜谱',
    category: 'meat_dish',
    categoryName: '荤菜',
    difficulty: 2,
    images: images,
    ingredients: const [Ingredient(name: '盐', text: '盐 1g')],
    steps: const [CookingStep(description: '完成')],
    hash: 'hash',
    source: source,
  );

  test('V2 网络详情图不会被误判为封面', () {
    final value = recipe(
      id: '05a523a7-48b0-44ed-975a-77d45f17cf64',
      source: RecipeSource.cloud,
      images: const [
        'https://anlifex.github.io/HowToCook-assets/versions/2/x/images/meat_dish/id_0.webp',
      ],
    );

    final parts = splitRecipeImages(value);
    expect(parts.customCover, isNull);
    expect(parts.details, hasLength(1));
    expect(cachedDetailRecipeId(value), value.id);
  });

  test('V1 静态详情图使用短 ID 命中旧缓存', () {
    final value = recipe(
      id: 'meat_dish_abcd1234',
      source: RecipeSource.bundled,
      images: const ['assets/images/meat_dish/meat_dish_abcd1234_0.webp'],
    );

    final parts = splitRecipeImages(value);
    expect(parts.customCover, isNull);
    expect(parts.details, hasLength(1));
    expect(cachedDetailRecipeId(value), 'abcd1234');
  });

  test('本地用户封面与详情图能正确拆分', () {
    final value = recipe(
      id: 'local-id',
      source: RecipeSource.userCreated,
      images: const [
        '/data/user/0/app/files/cover.webp',
        'https://example.com/detail.webp',
      ],
    );

    final parts = splitRecipeImages(value);
    expect(parts.customCover, endsWith('cover.webp'));
    expect(parts.details, ['https://example.com/detail.webp']);
  });

  test('用户修改的内置菜谱可用本地文件覆盖 AI 封面', () {
    final value = recipe(
      id: 'v2-id',
      source: RecipeSource.bundled,
      images: const ['/data/user/0/app/files/custom.webp'],
    );

    expect(splitRecipeImages(value).customCover, isNotNull);
  });

  test('用户修改后的 URL 封面在重新加载后仍能识别', () {
    final value = recipe(
      id: 'v2-id',
      source: RecipeSource.userModified,
      images: const [
        'https://example.com/custom-cover.webp',
        'https://anlifex.github.io/HowToCook-assets/versions/2/x/images/meat_dish/id_0.webp',
      ],
    );

    final parts = splitRecipeImages(value);
    expect(parts.customCover, 'https://example.com/custom-cover.webp');
    expect(parts.details, hasLength(1));
  });
}

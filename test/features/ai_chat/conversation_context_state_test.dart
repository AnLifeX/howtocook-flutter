import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/conversation_context_state.dart';
import 'package:howtocook/features/ai_chat/domain/entities/recipe_data_mode.dart';

void main() {
  test('菜谱数据模式随会话上下文序列化', () {
    final state = const ConversationContextState(
      recipeDataMode: RecipeDataMode.cloud,
    );

    expect(
      ConversationContextState.fromJson(state.toJson()).recipeDataMode,
      RecipeDataMode.cloud,
    );
  });

  test('旧会话缺少字段时默认使用本地数据', () {
    expect(
      ConversationContextState.fromJson(const {}).recipeDataMode,
      RecipeDataMode.local,
    );
  });
}

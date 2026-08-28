import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_context_state.dart';

class ConversationRepository {
  static const _indexKey = 'conversations_index';
  static const _uuid = Uuid();

  Box<Map> get _box => HiveService.getChatHistoryBox();
  Box get _settingsBox => HiveService.getSettingsBox();

  // ========== 会话 CRUD ==========

  Future<List<Conversation>> getAll() async {
    final data = _box.get(_indexKey);
    if (data == null) return [];
    try {
      final list = HiveService.deepConvertMap(data)['items'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .map(
            (e) => Conversation.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Failed to load conversations: $e');
      return [];
    }
  }

  Future<Conversation?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Conversation conversation) async {
    final all = await getAll();
    final index = all.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      all[index] = conversation;
    } else {
      all.add(conversation);
    }
    await _saveIndex(all);
  }

  Future<void> delete(String id) async {
    final all = await getAll();
    all.removeWhere((c) => c.id == id);
    await _saveIndex(all);
    // 清理关联数据
    await _box.delete(_messagesKey(id));
    await _box.delete(_recipesKey(id));
    await _box.delete(_contextKey(id));
  }

  Future<void> _saveIndex(List<Conversation> conversations) async {
    final jsonStr = jsonEncode({
      'items': conversations.map((c) => c.toJson()).toList(),
    });
    await _box.put(_indexKey, jsonDecode(jsonStr) as Map);
  }

  // ========== 消息操作 ==========

  String _messagesKey(String convId) => 'conv_${convId}_messages';
  String _recipesKey(String convId) => 'conv_${convId}_recipes';
  String _contextKey(String convId) => 'conv_${convId}_context';

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    final data = _box.get(_messagesKey(conversationId));
    if (data == null) return [];
    try {
      final converted = HiveService.deepConvertMap(data);
      final items = converted['items'] as List<dynamic>?;
      if (items == null) return [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Failed to load messages for $conversationId: $e');
      return [];
    }
  }

  Future<void> saveMessages(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    final jsonStr = jsonEncode({'items': messages});
    await _box.put(_messagesKey(conversationId), jsonDecode(jsonStr) as Map);
  }

  Future<void> clearMessages(String conversationId) async {
    await _box.delete(_messagesKey(conversationId));
    await _box.delete(_contextKey(conversationId));
  }

  Future<ConversationContextState> getContextState(
    String conversationId,
  ) async {
    final data = _box.get(_contextKey(conversationId));
    if (data == null) return const ConversationContextState();
    try {
      return ConversationContextState.fromJson(
        HiveService.deepConvertMap(data),
      );
    } catch (e) {
      debugPrint('Failed to load context state for $conversationId: $e');
      return const ConversationContextState();
    }
  }

  Future<void> saveContextState(
    String conversationId,
    ConversationContextState state,
  ) async {
    final jsonStr = jsonEncode(state.toJson());
    await _box.put(_contextKey(conversationId), jsonDecode(jsonStr) as Map);
  }

  // ========== 食谱关联 ==========

  Future<List<Map<String, dynamic>>> getRecipes(String conversationId) async {
    final data = _box.get(_recipesKey(conversationId));
    if (data == null) return [];
    try {
      final converted = HiveService.deepConvertMap(data);
      final items = converted['items'] as List<dynamic>?;
      if (items == null) return [];
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Failed to load recipes for $conversationId: $e');
      return [];
    }
  }

  Future<void> saveRecipes(
    String conversationId,
    List<Map<String, dynamic>> recipes,
  ) async {
    final jsonStr = jsonEncode({'items': recipes});
    await _box.put(_recipesKey(conversationId), jsonDecode(jsonStr) as Map);
  }

  /// 根据食谱 ID 反查所属会话 ID
  Future<String?> findConversationByRecipeId(String recipeId) async {
    final conversations = await getAll();
    for (final conv in conversations) {
      final recipes = await getRecipes(conv.id);
      for (final recipe in recipes) {
        if (recipe['id'] == recipeId) return conv.id;
      }
    }
    return null;
  }

  // ========== 活跃会话 ==========

  String? getActiveConversationId() {
    return _settingsBox.get('active_conversation_id') as String?;
  }

  Future<void> setActiveConversationId(String? id) async {
    if (id == null) {
      await _settingsBox.delete('active_conversation_id');
    } else {
      await _settingsBox.put('active_conversation_id', id);
    }
  }

  // ========== 创建新会话 ==========

  Conversation createNew({String title = '新对话'}) {
    final now = DateTime.now();
    return Conversation(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ========== 旧数据迁移 ==========

  Future<bool> needsMigration() async {
    final migrated = _settingsBox.get('chat_data_migrated');
    if (migrated == true) return false;
    final oldData = _settingsBox.get('chat_messages');
    return oldData != null;
  }

  Future<String?> migrateOldData() async {
    final oldMessages = _settingsBox.get('chat_messages');
    if (oldMessages == null) {
      await _settingsBox.put('chat_data_migrated', true);
      return null;
    }

    try {
      final conv = createNew(title: '历史对话');

      // 迁移消息
      List<Map<String, dynamic>> messageList;
      if (oldMessages is List) {
        messageList = oldMessages.map((item) {
          if (item is Map) {
            return HiveService.deepConvertMap(item);
          }
          return <String, dynamic>{};
        }).toList();
      } else {
        messageList = [];
      }

      final messageCount = messageList.length;

      // 尝试从首条用户消息提取标题
      String title = '历史对话';
      for (final msg in messageList) {
        if (msg['role'] == 'user') {
          final content = msg['content'];
          if (content is List && content.isNotEmpty) {
            final first = content[0];
            if (first is Map && first['type'] == 'text') {
              final text = first['text'] as String? ?? '';
              title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
              break;
            }
          }
          break;
        }
      }

      final updatedConv = conv.copyWith(
        title: title,
        messageCount: messageCount,
        lastMessagePreview: _extractLastPreview(messageList),
      );

      await save(updatedConv);
      await saveMessages(updatedConv.id, messageList);

      // 迁移 AI 食谱
      final oldRecipes = _settingsBox.get('ai_created_recipes');
      if (oldRecipes is List) {
        final recipeList = oldRecipes.map((item) {
          if (item is Map) {
            return HiveService.deepConvertMap(item);
          }
          return <String, dynamic>{};
        }).toList();
        await saveRecipes(updatedConv.id, recipeList);
      }

      // 清理旧数据
      await _settingsBox.delete('chat_messages');
      await _settingsBox.delete('ai_created_recipes');
      await _settingsBox.put('chat_data_migrated', true);
      await setActiveConversationId(updatedConv.id);

      debugPrint(
        'Migrated $messageCount messages to conversation: ${updatedConv.id}',
      );
      return updatedConv.id;
    } catch (e) {
      debugPrint('Migration failed: $e');
      await _settingsBox.put('chat_data_migrated', true);
      return null;
    }
  }

  String? _extractLastPreview(List<Map<String, dynamic>> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      final content = msg['content'];
      if (content is List) {
        for (final item in content) {
          if (item is Map && item['type'] == 'text') {
            final text = item['text'] as String? ?? '';
            if (text.isNotEmpty) {
              return text.length > 50 ? '${text.substring(0, 50)}...' : text;
            }
          }
        }
      }
    }
    return null;
  }
}

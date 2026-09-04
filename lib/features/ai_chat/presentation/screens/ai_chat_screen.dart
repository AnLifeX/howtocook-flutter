import 'dart:io';
import 'dart:async'; // 用于 scheduleMicrotask
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 用于 kDebugMode
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/android_background_execution_service.dart';
import '../../../../core/services/app_notification_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/main_scaffold.dart';
import '../../../../core/storage/hive_service.dart';
import '../../../sync/infrastructure/bundled_data_loader.dart';
import '../../../recipe/domain/entities/recipe.dart';
import '../../../recipe/application/providers/recipe_providers.dart';
import '../../application/providers/ai_providers.dart';
import '../../application/services/ai_chat_task_coordinator.dart';
import '../../domain/entities/ai_model_config.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/ai_usage_metrics.dart';
import '../../domain/entities/conversation_context_state.dart';
import '../../domain/entities/recipe_data_mode.dart';
import '../../infrastructure/repositories/conversation_repository.dart';
import '../../infrastructure/services/ai_service_factory.dart';
import '../../infrastructure/services/mcp_service.dart';
import '../../infrastructure/services/recipe_tool_service.dart';
import '../../infrastructure/services/recipe_recognizer.dart';
import '../../infrastructure/services/tip_recognizer.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';

/// MCP 工具调用记录（用于调试面板）
class MCPToolCall {
  final String toolName;
  final DateTime timestamp;
  final Map<String, dynamic> input;
  final Map<String, dynamic> output;
  final String? error;
  final Duration duration;

  MCPToolCall({
    required this.toolName,
    required this.timestamp,
    required this.input,
    required this.output,
    this.error,
    required this.duration,
  });
}

/// AI 聊天页面
///
/// 功能：
/// - 发送和接收消息
/// - 模型切换（Claude、OpenAI、DeepSeek）
/// - 图片上传（多模态）
/// - 聊天记录持久化
/// - MCP 工具默认集成
class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({super.key});

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen>
    with AutomaticKeepAliveClientMixin<AIChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final MCPService _mcpService = MCPService();
  late final RecipeToolService _recipeToolService;
  late final RecipeRecognizer _recipeRecognizer;
  late final TipRecognizer _tipRecognizer;

  bool _isLoading = false;
  bool _isStreaming = false;
  String _streamingText = '';
  String _streamingReasoningText = '';
  String? _aiStatusText;
  bool _shouldStopStreaming = false;
  String? _selectedImagePath;
  Timer? _partialSaveTimer;
  List<Map<String, dynamic>> _mcpTools = const [];
  // 新创建的食谱（用于在聊天中显示卡片和跳转到预览页面）
  final Map<String, Recipe> _createdRecipes = {};
  // MCP 工具调用历史（仅 debug 模式）
  final List<MCPToolCall> _mcpCallHistory = [];

  // 会话管理
  final ConversationRepository _conversationRepo = ConversationRepository();
  String? _currentConversationId;
  List<Conversation> _conversations = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 深度思考开关
  bool _enableThinking = false;
  ConversationContextState _contextState = const ConversationContextState();
  bool _isCompressingContext = false;
  String? _activeTaskConversationId;

  final AIChatTaskCoordinator _taskCoordinator = AIChatTaskCoordinator.instance;
  final AndroidBackgroundExecutionService _backgroundExecution =
      AndroidBackgroundExecutionService.instance;

  static const double _contextWarningRatio = 0.70;
  static const double _contextCompressionRatio = 0.82;
  static const int _messagesKeptAfterCompression = 8;

  @override
  bool get wantKeepAlive => true;

  void _taskSetState(VoidCallback mutation) {
    if (mounted) {
      setState(mutation);
    } else {
      mutation();
    }
    if (_activeTaskConversationId != null) {
      final latestAssistantText = _messages.isEmpty
          ? ''
          : _messages.last.content
                .whereType<TextContent>()
                .map((item) => item.text)
                .join();
      _taskCoordinator.update(
        statusText: _aiStatusText,
        partialText: _streamingText.isNotEmpty
            ? _streamingText
            : latestAssistantText,
      );
    }
  }

  bool _blockConversationMutationWhileRunning() {
    if (!_taskCoordinator.isRunning) return false;
    if (mounted) {
      AppSnackBar.show(
        context,
        '当前回复和工具调用尚未完成，完成或终止后再切换会话',
        bottomOffset: AppSnackBar.kChatBottomOffset,
      );
    }
    return true;
  }

  String get _currentConversationTitle {
    final activeId = _currentConversationId;
    if (activeId == null) return '新对话';
    return _conversations
            .where((conversation) => conversation.id == activeId)
            .map((conversation) => conversation.title)
            .firstOrNull ??
        '新对话';
  }

  // System Prompt（根据模型能力动态生成）
  String _buildSystemPrompt({required bool supportsTools}) {
    if (!supportsTools) {
      return '''你是“小厨”，专业、亲切、重视食品安全的烹饪助手。
回答烹饪问题时给出清晰可执行的建议，并结合消息末尾提供的当前时间判断季节、餐次和时令。
当前模型无法访问应用菜谱库或创建食谱；需要这些能力时，简短说明并建议用户切换到支持工具调用的模型，或前往菜谱页面搜索。''';
    }

    final mode = _contextState.recipeDataMode;
    return '''你是“小厨”，专业、亲切、重视食品安全的烹饪助手，可以通过应用内置工具访问菜谱。
当前会话使用${mode.label}模式：${mode.description}。
涉及菜谱库、具体食谱、推荐或创建食谱时优先使用合适的工具；普通烹饪常识可直接回答。
工具结果要整理成自然语言，不输出原始 JSON；可补充实用技巧和风险提示。
搜索食谱时先用 searchRecipes 获取原始 ID，需要完整做法时再将原 ID 传给 getRecipeById，不得改写。
搜索结果若 truncated=true 仅代表返回了部分匹配项，不得据此断言某菜谱不存在。首次搜索为零时，先用精简菜名、常见别名或主要食材再搜索一次；仍无结果时只能说明“当前查询未找到”。
创建成功后在回复中提及食谱名称，客户端会显示可预览和保存的卡片。
结合消息末尾提供的当前时间判断季节、餐次和时令。''';
  }

  String _buildRuntimeContext(DateTime now) {
    final weekday = const [
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ][now.weekday - 1];
    final period = switch (now.hour) {
      < 6 => '凌晨',
      < 9 => '早晨',
      < 12 => '上午',
      < 14 => '中午',
      < 18 => '下午',
      < 22 => '晚上',
      _ => '深夜',
    };
    final minute = now.minute.toString().padLeft(2, '0');
    return '[运行时信息：当前为 ${now.year}年${now.month}月${now.day}日 $weekday $period ${now.hour}:$minute（Asia/Shanghai）。仅在与问题相关时使用。]';
  }

  @override
  void initState() {
    super.initState();
    _recipeToolService = RecipeToolService(
      localRepository: ref.read(recipeRepositoryProvider),
      cloudService: _mcpService,
    );
    final dataLoader = BundledDataLoader();
    _recipeRecognizer = RecipeRecognizer(dataLoader);
    _tipRecognizer = TipRecognizer(dataLoader);
    _initConversations();
    _loadSettings();
    _loadMCPTools();
  }

  /// 加载 MCP 工具列表
  void _loadMCPTools() {
    assert(_v2CreateRecipeInputSchema['type'] == 'object');
    _mcpTools = _recipeToolService
        .definitionsFor(_contextState.recipeDataMode)
        .map(
          (tool) => Map<String, dynamic>.from(_canonicalizeJson(tool) as Map),
        )
        .toList();
    debugPrint(
      'Recipe tools loaded: ${_mcpTools.length} (${_contextState.recipeDataMode.name})',
    );
  }

  dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalizeJson(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalizeJson).toList();
    return value;
  }

  static const Map<String, dynamic> _v2CreateRecipeInputSchema = {
    'type': 'object',
    'properties': {
      'recipe': {
        'type': 'object',
        'description': '完整的 V2 结构化菜谱。尽量填写简介、分类、难度、热量、必备项、用量计算、工具、操作、提示和警告。',
        'properties': {
          'name': {'type': 'string'},
          'description': {'type': 'string'},
          'category': {'type': 'string'},
          'categoryName': {'type': 'string'},
          'difficulty': {'type': 'integer', 'minimum': 1, 'maximum': 5},
          'estimatedCaloriesKcal': {'type': 'integer', 'minimum': 1},
          'requirements': {
            'type': 'array',
            'description': '烹饪前必须具备的原料和工具。',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'text': {'type': 'string'},
                    'kind': {
                      'type': 'string',
                      'enum': ['ingredient', 'tool', 'unknown'],
                    },
                    'group': {'type': 'string'},
                  },
                  'required': ['text'],
                },
              ],
            },
          },
          'ingredients': {
            'type': 'array',
            'description': '所有食材的可计算用量，包括水、油等基础材料。',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'text': {
                      'type': 'string',
                      'description': '包含食材名和用量的完整文本，例如“鸡蛋 3 颗”，不能只写“3 颗”',
                    },
                    'optional': {'type': 'boolean'},
                    'source': {'type': 'string'},
                    'table': {
                      'type': 'object',
                      'additionalProperties': {'type': 'string'},
                    },
                  },
                  'required': ['name', 'text'],
                },
              ],
            },
          },
          'tools': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'calculationNotes': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'steps': {
            'type': 'array',
            'description': '按顺序执行的操作；description 不要自带数字序号。',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'kind': {
                      'type': 'string',
                      'enum': ['step', 'heading'],
                    },
                    'title': {'type': 'string'},
                    'description': {'type': 'string'},
                  },
                  'required': ['description'],
                },
              ],
            },
          },
          'tips': {'type': 'string'},
          'warnings': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['name', 'ingredients', 'steps'],
      },
      'checkDuplicate': {'type': 'boolean', 'default': true},
      'similarityThreshold': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'default': 0.75,
      },
    },
    'required': ['recipe'],
  };

  @override
  void dispose() {
    _partialSaveTimer?.cancel();
    _saveChatHistory(conversationId: _activeTaskConversationId);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 初始化会话系统
  Future<void> _initConversations() async {
    try {
      // 检查旧数据迁移
      if (await _conversationRepo.needsMigration()) {
        await _conversationRepo.migrateOldData();
        debugPrint('Old chat data migrated');
      }

      // 加载会话列表
      _conversations = await _conversationRepo.getAll();

      // 恢复上次活跃会话
      var activeId = _conversationRepo.getActiveConversationId();
      if (activeId != null) {
        final exists = _conversations.any((c) => c.id == activeId);
        if (!exists) activeId = null;
      }

      // 无会话时自动创建
      if (_conversations.isEmpty) {
        final conv = _conversationRepo.createNew();
        await _conversationRepo.save(conv);
        _conversations = [conv];
        activeId = conv.id;
      }

      activeId ??= _conversations.first.id;
      _currentConversationId = activeId;
      await _conversationRepo.setActiveConversationId(activeId);

      // 加载当前会话的消息和食谱
      await _loadConversationData(activeId);
    } catch (e, stackTrace) {
      debugPrint('Failed to init conversations: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// 加载指定会话的消息和食谱
  Future<void> _loadConversationData(String conversationId) async {
    try {
      final messagesJson = await _conversationRepo.getMessages(conversationId);
      final recipesJson = await _conversationRepo.getRecipes(conversationId);
      final contextState = await _conversationRepo.getContextState(
        conversationId,
      );

      setState(() {
        _messages.clear();
        _createdRecipes.clear();
        _contextState = contextState;
        _messages.addAll(
          messagesJson.map((json) => ChatMessage.fromJson(json)).toList(),
        );
        for (final item in recipesJson) {
          try {
            final recipe = Recipe.fromJson(item);
            _createdRecipes[recipe.id] = recipe;
          } catch (e) {
            debugPrint('Failed to parse recipe: $e');
          }
        }
      });
      _loadMCPTools();

      debugPrint(
        'Loaded ${_messages.length} messages, ${_createdRecipes.length} recipes for $conversationId',
      );
      _scrollToBottom();
    } catch (e, stackTrace) {
      debugPrint('Failed to load conversation data: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final hiveService = HiveService();
      final enableThinking = await hiveService.getSetting(
        'enable_thinking',
        defaultValue: false,
      );

      setState(() {
        _enableThinking = enableThinking as bool;
      });
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  /// 保存当前会话的消息和食谱
  Future<void> _saveChatHistory({String? conversationId}) async {
    final convId =
        conversationId ?? _activeTaskConversationId ?? _currentConversationId;
    if (convId == null) return;
    try {
      final jsonString = jsonEncode(_messages.map((m) => m.toJson()).toList());
      final jsonList = (jsonDecode(jsonString) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      await _conversationRepo.saveMessages(convId, jsonList);
      await _conversationRepo.saveContextState(convId, _contextState);

      // 更新会话元数据
      await _updateConversationMeta(conversationId: convId);

      // 保存 AI 创建的食谱
      await _saveCreatedRecipes(conversationId: convId);
    } catch (e, stackTrace) {
      debugPrint('Failed to save chat history: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// 更新当前会话的元数据（标题、最后消息、消息数）
  Future<void> _updateConversationMeta({String? conversationId}) async {
    final convId = conversationId ?? _currentConversationId;
    if (convId == null) return;
    final conv = await _conversationRepo.getById(convId);
    if (conv == null) return;

    String title = conv.title;
    // 首条用户消息自动命名（仅当标题为默认值时）
    if (title == '新对话' && _messages.isNotEmpty) {
      for (final msg in _messages) {
        if (msg.role == MessageRole.user) {
          final text = _extractTextFromMessage(msg);
          if (text.isNotEmpty) {
            title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
          }
          break;
        }
      }
    }

    // 提取最后一条消息摘要
    String? lastPreview;
    if (_messages.isNotEmpty) {
      final lastMsg = _messages.last;
      final text = _extractTextFromMessage(lastMsg);
      if (text.isNotEmpty) {
        lastPreview = text.length > 50 ? '${text.substring(0, 50)}...' : text;
      }
    }

    final hasNewMessages = _messages.length != conv.messageCount;
    final updated = conv.copyWith(
      title: title,
      updatedAt: hasNewMessages ? DateTime.now() : conv.updatedAt,
      lastMessagePreview: lastPreview,
      messageCount: _messages.length,
    );
    await _conversationRepo.save(updated);

    // 刷新本地会话列表
    _conversations = await _conversationRepo.getAll();
    if (mounted) setState(() {});
  }

  String _extractTextFromMessage(ChatMessage message) {
    for (final item in message.content) {
      if (item is TextContent) return item.text;
    }
    return '';
  }

  /// 保存 AI 创建的食谱（独立方法，可在创建时立即调用）
  Future<void> _saveCreatedRecipes({String? conversationId}) async {
    final convId =
        conversationId ?? _activeTaskConversationId ?? _currentConversationId;
    if (convId == null) return;
    try {
      final recipesJson = _createdRecipes.values
          .map((recipe) => recipe.toJson())
          .toList();
      final jsonStr = jsonEncode(recipesJson);
      final jsonList = (jsonDecode(jsonStr) as List)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      await _conversationRepo.saveRecipes(convId, jsonList);
      debugPrint('Saved ${_createdRecipes.length} AI-created recipes');
    } catch (e) {
      debugPrint('Failed to save created recipes: $e');
    }
  }

  String? _buildFinalReasoning(StringBuffer accumulated, String? current) {
    if (accumulated.isEmpty && (current == null || current.isEmpty)) {
      return null;
    }
    if (accumulated.isEmpty) return current;
    if (current == null || current.isEmpty) return accumulated.toString();
    return '${accumulated.toString()}\n\n$current';
  }

  AIUsageMetrics _mergeUsage(AIUsageMetrics? current, AIUsageMetrics next) {
    if (current == null) return next;
    return AIUsageMetrics(
      inputTokens: current.inputTokens > next.inputTokens
          ? current.inputTokens
          : next.inputTokens,
      outputTokens: current.outputTokens > next.outputTokens
          ? current.outputTokens
          : next.outputTokens,
      cacheReadTokens: current.cacheReadTokens > next.cacheReadTokens
          ? current.cacheReadTokens
          : next.cacheReadTokens,
      cacheWriteTokens: current.cacheWriteTokens > next.cacheWriteTokens
          ? current.cacheWriteTokens
          : next.cacheWriteTokens,
      cacheMissTokens:
          current.effectiveCacheMissTokens > next.effectiveCacheMissTokens
          ? current.effectiveCacheMissTokens
          : next.effectiveCacheMissTokens,
    );
  }

  void _recordUsage(AIUsageMetrics? usage) {
    if (usage == null || (usage.inputTokens == 0 && usage.outputTokens == 0)) {
      return;
    }
    if (mounted) {
      setState(() {
        _contextState = _contextState.recordUsage(usage);
      });
    } else {
      _contextState = _contextState.recordUsage(usage);
    }
  }

  int _estimateTextTokens(String text) {
    var asciiChars = 0;
    var nonAsciiTokens = 0;
    for (final rune in text.runes) {
      if (rune <= 0x7f) {
        asciiChars++;
      } else {
        nonAsciiTokens++;
      }
    }
    return nonAsciiTokens + (asciiChars / 4).ceil();
  }

  int _estimateMessageTokens(ChatMessage message) {
    var tokens = 6;
    for (final item in message.content) {
      if (item is TextContent) {
        tokens += _estimateTextTokens(item.text);
      } else if (item is ImageContent) {
        tokens += 1200;
      } else if (item is ToolUseContent) {
        tokens += _estimateTextTokens(jsonEncode(item.input)) + 20;
      } else if (item is ToolResultContent) {
        tokens += _estimateTextTokens(jsonEncode(item.result)) + 20;
      }
    }
    if (message.runtimeContext != null) {
      tokens += _estimateTextTokens(message.runtimeContext!);
    }
    return tokens;
  }

  int _estimatedContextTokens(AIModelConfig model) {
    var tokens = _estimateTextTokens(
      _buildSystemPrompt(supportsTools: model.capabilities.supportsMCP),
    );
    if (_contextState.hasSummary) {
      tokens += _estimateTextTokens(_contextState.summary!) + 40;
    }
    final start = _contextState.summarizedMessageCount.clamp(
      0,
      _messages.length,
    );
    for (final message in _messages.skip(start)) {
      tokens += _estimateMessageTokens(message);
    }
    if (model.capabilities.supportsMCP && _mcpTools.isNotEmpty) {
      tokens += _estimateTextTokens(jsonEncode(_mcpTools));
    }
    return tokens;
  }

  int _effectiveContextTokens(AIModelConfig model) {
    final localEstimate = _estimatedContextTokens(model);
    return _contextState.currentContextTokens(localEstimate);
  }

  double _contextRatioForModel(AIModelConfig model) {
    if (model.capabilities.contextWindow <= 0) return 0;
    return _effectiveContextTokens(model) / model.capabilities.contextWindow;
  }

  Future<bool> _confirmLongContextIfNeeded() async {
    final model = _resolveActiveModel();
    if (model == null) return true;
    final ratio = _contextRatioForModel(model);
    if (ratio < _contextWarningRatio || _contextState.compressionApproved) {
      return true;
    }
    final percent = (ratio * 100).clamp(0, 999).round();
    final continueConversation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('当前会话上下文较长'),
        content: Text(
          '预计已使用 $percent% 的上下文。建议新建会话；如果继续，达到安全阈值后会自动将较早内容压缩为摘要，聊天记录仍会完整保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('新建会话'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续并允许压缩'),
          ),
        ],
      ),
    );
    if (continueConversation == true) {
      setState(() {
        _contextState = _contextState.copyWith(compressionApproved: true);
      });
      return true;
    }
    await _createNewConversation();
    return false;
  }

  Future<void> _compressContextIfNeeded(AIModelConfig model) async {
    if (!_contextState.compressionApproved ||
        _contextRatioForModel(model) < _contextCompressionRatio ||
        _isCompressingContext) {
      return;
    }
    final historyEnd = _messages.length - 1;
    final cutIndex = historyEnd - _messagesKeptAfterCompression;
    final startIndex = _contextState.summarizedMessageCount.clamp(
      0,
      historyEnd,
    );
    if (cutIndex <= startIndex) return;

    _isCompressingContext = true;
    if (mounted) {
      setState(() => _aiStatusText = '压缩较早上下文中...');
    }
    try {
      final transcript = StringBuffer();
      if (_contextState.hasSummary) {
        transcript.writeln('已有摘要：\n${_contextState.summary}\n');
      }
      for (final message in _messages.sublist(startIndex, cutIndex)) {
        final role = switch (message.role) {
          MessageRole.user => '用户',
          MessageRole.assistant => '助手',
          MessageRole.system => '系统',
        };
        final text = _extractTextFromMessage(message).trim();
        if (text.isNotEmpty) transcript.writeln('$role：$text');
        if (message.createdRecipeIds?.isNotEmpty == true) {
          transcript.writeln('已创建食谱ID：${message.createdRecipeIds!.join(', ')}');
        }
      }

      final service = AIServiceFactory.create(model);
      AIUsageMetrics? usage;
      final response = await service.sendMessageSync(
        messages: [
          ChatMessage(
            id: 'compact-system',
            role: MessageRole.system,
            content: const [
              MessageContent.text(
                text:
                    '将较早的烹饪对话压缩成可供后续继续对话的中文摘要。保留用户偏好、忌口、人数、已有结论、关键食材用量、食谱名称和未完成事项；删除寒暄、重复和推理过程。只输出摘要。',
              ),
            ],
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          ChatMessage(
            id: 'compact-input',
            role: MessageRole.user,
            content: [MessageContent.text(text: transcript.toString())],
            timestamp: DateTime.now(),
          ),
        ],
        maxTokens: 2048,
        onUsage: (value) => usage = _mergeUsage(usage, value),
      );
      final summary = response.content
          .whereType<TextContent>()
          .map((item) => item.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');
      if (summary.isNotEmpty) {
        _taskSetState(() {
          _contextState = _contextState.copyWith(
            summary: summary,
            summarizedMessageCount: cutIndex,
            compressionApproved: false,
          );
        });
        _recordUsage(usage);
      }
    } catch (e) {
      debugPrint('Context compression failed: $e');
      if (mounted) {
        AppSnackBar.show(
          context,
          '上下文压缩失败，本轮将继续使用完整历史',
          bottomOffset: AppSnackBar.kChatBottomOffset,
        );
      }
    } finally {
      _isCompressingContext = false;
      if (mounted) setState(() => _aiStatusText = '回复中...');
    }
  }

  /// 保存设置
  Future<void> _saveSetting(String key, dynamic value) async {
    try {
      final hiveService = HiveService();
      await hiveService.saveSetting(key, value);
    } catch (e) {
      debugPrint('Failed to save setting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: ConversationDrawer(
        conversations: _conversations,
        activeConversationId: _currentConversationId,
        onNewConversation: () {
          Navigator.pop(context);
          _createNewConversation();
        },
        onConversationSelected: (id) {
          Navigator.pop(context);
          _switchConversation(id);
        },
        onConversationDeleted: (id) {
          _deleteConversation(id);
        },
        onConversationRenamed: (id, newTitle) {
          _renameConversation(id, newTitle);
        },
      ),
      appBar: AppBar(
        toolbarHeight: 52,
        leadingWidth: 44,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '会话列表',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          visualDensity: VisualDensity.compact,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _buildModelSelector(),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _currentConversationTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空聊天记录',
            onPressed: _taskCoordinator.isRunning ? null : _clearHistory,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建会话',
            onPressed: _taskCoordinator.isRunning
                ? null
                : _createNewConversation,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : _buildMessageList(),
            ),
            _buildInputArea(),
          ],
        ),
      ),
      // MCP 调试悬浮按钮（仅 debug 模式）
      floatingActionButton: kDebugMode && _mcpCallHistory.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showMCPDebugPanel,
              tooltip: 'MCP 调试面板',
              backgroundColor: AppColors.warning,
              child: Badge(
                label: Text('${_mcpCallHistory.length}'),
                backgroundColor: AppColors.error,
                textColor: AppColors.surface,
                child: const Icon(Icons.bug_report),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
    );
  }

  Widget _buildDataModeSelector() {
    return PopupMenuButton<RecipeDataMode>(
      tooltip: '菜谱数据：${_contextState.recipeDataMode.label}',
      enabled: !_isLoading,
      initialValue: _contextState.recipeDataMode,
      onSelected: _setRecipeDataMode,
      itemBuilder: (context) => RecipeDataMode.values
          .map(
            (mode) => PopupMenuItem(
              value: mode,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  mode == RecipeDataMode.local
                      ? Icons.phone_android
                      : Icons.cloud_outlined,
                ),
                title: Text(mode.label),
                subtitle: Text(mode.description),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _contextState.recipeDataMode == RecipeDataMode.local
                  ? Icons.phone_android
                  : Icons.cloud_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              _contextState.recipeDataMode.label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRecipeDataMode(RecipeDataMode mode) async {
    if (mode == _contextState.recipeDataMode || _isLoading) return;
    setState(() {
      _contextState = _contextState.copyWith(recipeDataMode: mode);
      _loadMCPTools();
    });
    await _saveChatHistory();
    if (!mounted) return;
    AppSnackBar.show(
      context,
      '已切换为${mode.label}模式',
      bottomOffset: AppSnackBar.kChatBottomOffset,
    );
  }

  /// 构建模型选择器
  Widget _buildModelSelector() {
    final selectedModel = ref.watch(selectedModelConfigProvider);
    final modelsAsync = ref.watch(availableModelsProvider);

    return modelsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => IconButton(
        tooltip: '模型加载失败，点击重试',
        onPressed: () => ref.invalidate(availableModelsProvider),
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
      ),
      data: (models) {
        if (models.isEmpty) {
          return IconButton(
            tooltip: '添加模型',
            onPressed: () => context.push('/model-management'),
            icon: const Icon(Icons.add_circle_outline),
          );
        }

        // 查找当前选中模型的最新版本
        final matchingModel = models
            .where((model) => model.id == selectedModel?.id)
            .firstOrNull;

        if (matchingModel != null) {
          // 找到匹配的模型，检查是否需要更新（对象可能已被编辑）
          if (matchingModel != selectedModel) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedModelConfigProvider.notifier).state =
                  matchingModel;
            });
          }
        } else {
          // 没有找到匹配的模型，回退到第一个模型
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedModelConfigProvider.notifier).state = models.first;
          });
        }

        final currentValue = matchingModel?.id ?? models.first.id;

        final currentModel = models.firstWhere(
          (model) => model.id == currentValue,
        );
        return PopupMenuButton<String>(
          tooltip: '切换模型（${currentModel.displayName}）',
          initialValue: currentValue,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onSelected: (modelId) {
            final nextModel = models.firstWhere((model) => model.id == modelId);
            setState(() {
              ref.read(selectedModelConfigProvider.notifier).state = nextModel;
              if (!nextModel.supportsImageInputEffective) {
                _selectedImagePath = null;
              }
            });
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 116),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.textSecondary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      currentModel.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
          itemBuilder: (context) => models
              .map(
                (model) => PopupMenuItem<String>(
                  value: model.id,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: model.id == currentValue
                              ? const Icon(Icons.check, size: 18)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                model.modelId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildContextStatusButton() {
    final model = ref.watch(selectedModelConfigProvider);
    if (model == null || _messages.isEmpty) {
      return const IconButton(
        tooltip: '暂无上下文数据',
        onPressed: null,
        icon: Icon(Icons.memory_outlined),
      );
    }
    final estimated = _effectiveContextTokens(model);
    final window = model.capabilities.contextWindow;
    final ratio = window <= 0 ? 0.0 : estimated / window;
    final warning = ratio >= _contextWarningRatio;
    final cacheRate = _contextState.cacheHitRate;

    return IconButton(
      tooltip:
          '上下文 ${_formatTokenCount(estimated)} / ${_formatTokenCount(window)}'
          '${cacheRate == null ? '' : ' · 缓存 ${(cacheRate * 100).round()}%'}',
      onPressed: () => _showContextDetails(model),
      icon: Icon(
        warning ? Icons.warning_amber_rounded : Icons.memory_outlined,
        color: warning ? AppColors.warning : AppColors.textSecondary,
      ),
    );
  }

  String _formatTokenCount(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
    }
    return '$value';
  }

  String _formatContextPercent(double ratio) {
    final percent = ratio * 100;
    if (percent > 0 && percent < 10) return '${percent.toStringAsFixed(1)}%';
    return '${percent.round()}%';
  }

  void _showContextDetails(AIModelConfig model) {
    final estimated = _effectiveContextTokens(model);
    final window = model.capabilities.contextWindow;
    final ratio = window <= 0 ? 0.0 : estimated / window;
    final percent = _formatContextPercent(ratio);
    final cacheRate = _contextState.cacheHitRate;
    final cumulativeInput =
        _contextState.totalCacheReadTokens + _contextState.totalCacheMissTokens;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('会话上下文', style: AppTextStyles.cardTitle),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '当前累计上下文',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    percent,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: ratio.clamp(0, 1).toDouble(),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 10),
              Text(
                '${_formatTokenCount(estimated)} / ${_formatTokenCount(window)} tokens',
              ),
              const SizedBox(height: 8),
              Text(
                _contextState.lastInputTokens > 0
                    ? '最近一次完整输入 ${_formatTokenCount(_contextState.lastInputTokens)}，本轮输出 ${_formatTokenCount(_contextState.lastOutputTokens)} tokens'
                    : '服务商尚未返回本会话的 token 用量数据',
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                cacheRate == null
                    ? '缓存命中：暂无数据（部分中转服务不会返回）'
                    : '累计 API 输入流量 ${_formatTokenCount(cumulativeInput)}（不计入窗口）：缓存命中 ${(cacheRate * 100).toStringAsFixed(1)}%，命中 ${_formatTokenCount(_contextState.totalCacheReadTokens)}，未命中 ${_formatTokenCount(_contextState.totalCacheMissTokens)} tokens',
                style: AppTextStyles.bodySmall,
              ),
              if (_contextState.hasSummary) ...[
                const SizedBox(height: 6),
                Text(
                  '较早的 ${_contextState.summarizedMessageCount} 条消息已压缩供模型使用；页面中的完整聊天记录未删除。',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 解析当前有效的模型
  AIModelConfig? _resolveActiveModel() {
    final selected = ref.read(selectedModelConfigProvider);
    final modelsAsyncValue = ref.read(availableModelsProvider);

    // 只有当 provider 有具体数据时，才验证选择是否有效
    // 在 loading/error 状态下，继续使用当前选择
    return modelsAsyncValue.maybeWhen(
      data: (models) {
        if (models.isEmpty) {
          return null;
        }

        final hasSelected = models.any(
          (model) => model.id == selected?.id && model.isEnabled,
        );

        if (hasSelected) {
          return selected;
        }

        // 只有确认当前选择不存在时才回退
        final fallback = models.firstWhere(
          (model) => model.isEnabled,
          orElse: () => models.first,
        );

        if (fallback.id != selected?.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedModelConfigProvider.notifier).state = fallback;
          });
        }

        return fallback;
      },
      // loading/error 状态：保持当前选择，不回退
      orElse: () => selected,
    );
  }

  /// 构建深度思考开关
  Widget _buildThinkingToggle() {
    return GestureDetector(
      onTap: _isLoading
          ? null
          : () {
              setState(() {
                _enableThinking = !_enableThinking;
              });
              _saveSetting('enable_thinking', _enableThinking);

              AppSnackBar.show(
                context,
                _enableThinking ? '已开启深度思考' : '已关闭深度思考',
                duration: const Duration(seconds: 1),
                bottomOffset: AppSnackBar.kChatBottomOffset,
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _enableThinking
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.textSecondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _enableThinking
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.textSecondary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology,
              size: 16,
              color: _enableThinking
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '深度思考',
              style: AppTextStyles.bodySmall.copyWith(
                color: _enableThinking
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: _enableThinking
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    final hasModel = ref.watch(selectedModelConfigProvider) != null;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8C61)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: AppColors.surface,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text('小厨', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              hasModel ? '您的贴心美食顾问' : '先添加一个您自己的 AI 模型',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                hasModel
                    ? '问我任何关于烹饪的问题\n我将为您提供专业建议和菜谱推荐'
                    : '应用不再内置共享 AI Key。您添加的模型配置和 Key 仅保存在本机，应用升级不会覆盖。',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!hasModel)
              FilledButton.icon(
                onPressed: () => context.push('/model-management'),
                icon: const Icon(Icons.add),
                label: const Text('前往模型管理'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestionChip('今天吃什么？'),
                  _buildSuggestionChip('推荐一道家常菜'),
                  _buildSuggestionChip('如何做红烧肉？'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 构建建议问题芯片
  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _inputController.text = text;
      },
      backgroundColor: AppColors.primaryLight.withValues(alpha: 0.1),
      labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
    );
  }

  /// 构建消息列表
  Widget _buildMessageList() {
    // 获取所有可用模型（包括用户自定义模型）用于显示模型名称
    final availableModelsAsync = ref.watch(availableModelsProvider);
    final builtinModels = AIServiceFactory.getBuiltinModels();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        // 获取模型名称（从消息保存的modelId，而不是当前选择的模型）
        // 优先从 availableModelsProvider 查找（包含用户自定义模型）
        // 找不到时回退到 modelId 本身
        String? modelName;
        if (message.role == MessageRole.assistant && message.modelId != null) {
          final models = availableModelsAsync.maybeWhen(
            data: (items) => items,
            orElse: () => builtinModels,
          );
          final model = models
              .where((m) => m.id == message.modelId)
              .firstOrNull;
          // 找不到模型时，显示 modelId 作为后备
          modelName = model?.displayName ?? message.modelId;
        }

        // 判断这是否是最后一条正在流式显示的消息
        final isLastStreaming = index == _messages.length - 1 && _isStreaming;
        final isLastMessage = index == _messages.length - 1;

        return MessageBubble(
          message: message,
          modelName: modelName,
          isStreaming: isLastStreaming,
          streamingText: isLastStreaming ? _streamingText : null,
          streamingReasoningText:
              isLastMessage && _streamingReasoningText.isNotEmpty
              ? _streamingReasoningText
              : null,
          aiStatusText: isLastMessage ? _aiStatusText : null,
          isPending:
              isLastMessage &&
              _isLoading &&
              message.role == MessageRole.assistant,
          recipeRecognizer: _recipeRecognizer,
          createdRecipes: _createdRecipes, // 传递 AI 创建的食谱列表
          onRecipeTap: (recipeId) async {
            if (_createdRecipes.containsKey(recipeId)) {
              final repo = ref.read(recipeRepositoryProvider);
              final saved = await repo.getRecipeById(recipeId);
              if (!context.mounted) return;
              if (saved != null) {
                context.push('/recipe/$recipeId');
              } else {
                final recipe = _createdRecipes[recipeId]!;
                context.push('/recipe-preview', extra: recipe);
              }
            } else {
              context.push('/recipe/$recipeId');
            }
          },
          onDelete: () {
            setState(() {
              _messages.removeAt(index);
            });
            _saveChatHistory();
            AppSnackBar.show(
              context,
              '消息已删除',
              bottomOffset: AppSnackBar.kChatBottomOffset,
            );
          },
          onRetry: message.role == MessageRole.assistant
              ? () {
                  // 重新发送上一条用户消息
                  if (index > 0 &&
                      _messages[index - 1].role == MessageRole.user) {
                    final userMessage = _messages[index - 1];
                    // 移除当前AI消息
                    setState(() {
                      _messages.removeAt(index);
                    });
                    // 触发重新发送（传入用户消息）
                    _resendMessage(userMessage);
                  }
                }
              : null,
          onEdit: message.role == MessageRole.user
              ? () {
                  // 显示编辑对话框
                  _showEditDialog(context, message, index);
                }
              : null,
          tipRecognizer: _tipRecognizer,
          onTipTap: (tipId, category) {
            context.push('/tips/$category/$tipId');
          },
        );
      },
    );
  }

  /// 构建加载指示器
  String _toolStatusText(String toolName) {
    final clean = toolName.replaceFirst('mcp_howtocook_', '');
    return switch (clean) {
      'getRecipeById' => '读取菜谱详情中...',
      'searchRecipes' => '搜索菜谱中...',
      'getAllRecipes' => '获取菜谱列表中...',
      'getRecipesByCategory' => '查询分类中...',
      'createRecipe' => '生成食谱草稿中...',
      'recommendMeals' => '筛选用餐推荐中...',
      'whatToEat' => '搭配今日菜单中...',
      'getFavoriteRecipes' => '读取本地收藏中...',
      'listRecipeCategories' => '整理本地分类中...',
      'findRecipesByIngredients' => '匹配现有食材中...',
      'getMyRecipes' => '读取我的菜谱中...',
      'getRecipePersonalInfo' => '读取收藏和笔记中...',
      'getRecipeDetail' => '获取详情中...',
      _ => '正在执行应用工具...',
    };
  }

  /// 构建输入区域
  Widget _buildInputArea() {
    final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final double extraBottom = hasKeyboard ? 8.0 : 16.0 + kFloatingNavBarHeight;
    final selectedModel = ref.watch(selectedModelConfigProvider);
    final supportsImages = selectedModel?.supportsImageInputEffective == true;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, extraBottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 工具栏
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (supportsImages) ...[
                    ActionChip(
                      avatar: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      label: const Text('图片'),
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: AppColors.primaryLight,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.35),
                      ),
                      tooltip: '拍照或从相册选择',
                      onPressed: _isLoading ? null : _showImageSourcePicker,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildThinkingToggle(),
                  const SizedBox(width: 8),
                  _buildDataModeSelector(),
                ],
              ),
            ),
          ),

          // 图片预览
          if (_selectedImagePath != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 80,
              child: Row(
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            _showLocalImagePreview(_selectedImagePath!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_selectedImagePath!),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 80,
                                  height: 80,
                                  color: AppColors.surfaceAlt,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                  ),
                                ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.textSecondary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: AppColors.surface,
                              size: 16,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedImagePath = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // 输入框行
          Row(
            children: [
              _buildContextStatusButton(),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_isLoading, // 加载时禁用
                  decoration: InputDecoration(
                    hintText: _isLoading ? 'AI 正在回复...' : '输入消息...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _isLoading ? null : _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: _isLoading
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFFFF6B35), Color(0xFFFF8C61)],
                        ),
                  color: _isLoading ? AppColors.textDisabled : null,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isLoading ? Icons.stop : Icons.send,
                    color: AppColors.surface,
                  ),
                  tooltip: _isLoading ? '终止' : '发送',
                  onPressed: _isLoading ? _stopStreaming : _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showImageSourcePicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                subtitle: const Text('打开相机拍摄一张照片'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                subtitle: const Text('选择已有图片'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  /// 拍照或从相册选择图片
  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final persistedPath = await _persistChatImage(image);
        if (!mounted) return;
        setState(() {
          _selectedImagePath = persistedPath;
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          source == ImageSource.camera ? '拍照失败: $e' : '选择图片失败: $e',
          bottomOffset: AppSnackBar.kChatBottomOffset,
        );
      }
    }
  }

  Future<String> _persistChatImage(XFile image) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}chat_images',
    );
    await directory.create(recursive: true);
    final sourcePath = image.path;
    final dot = sourcePath.lastIndexOf('.');
    final extension = dot >= 0 && sourcePath.length - dot <= 6
        ? sourcePath.substring(dot).toLowerCase()
        : '.jpg';
    final target = File(
      '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}$extension',
    );
    return (await File(sourcePath).copy(target.path)).path;
  }

  String _imageMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  void _showLocalImagePreview(String path) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        '图片文件已不存在',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  tooltip: '关闭预览',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发送消息
  Future<void> _sendMessage() async {
    if (_taskCoordinator.isRunning) return;
    final content = _inputController.text.trim();
    if (content.isEmpty && _selectedImagePath == null) return;
    if (_resolveActiveModel() == null) {
      AppSnackBar.show(
        context,
        '请先在模型管理中添加自己的 AI 模型和 API Key',
        bottomOffset: AppSnackBar.kChatBottomOffset,
      );
      return;
    }
    if (!await _confirmLongContextIfNeeded()) return;

    // 创建用户消息
    final messageContent = <MessageContent>[
      if (content.isNotEmpty) MessageContent.text(text: content),
      if (_selectedImagePath != null)
        MessageContent.image(
          data: '', // 将在发送时处理
          mimeType: _imageMimeType(_selectedImagePath!),
          localPath: _selectedImagePath,
        ),
    ];

    final userMessage = ChatMessage(
      id: DateTime.now().toString(),
      role: MessageRole.user,
      content: messageContent,
      timestamp: DateTime.now(),
      runtimeContext: _buildRuntimeContext(DateTime.now()),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _aiStatusText = '回复中...';
      _inputController.clear();
      _selectedImagePath = null;
    });

    _scrollToBottom();

    // 调用实际的发送逻辑
    await _sendMessageInternal();
  }

  /// 重新发送消息（用于重试）
  Future<void> _resendMessage(ChatMessage userMessage) async {
    if (_isLoading || _taskCoordinator.isRunning) return;

    setState(() {
      _isLoading = true;
      _aiStatusText = '回复中...';
    });

    _scrollToBottom();

    await _sendMessageInternal();
  }

  /// 实际的消息发送逻辑（供 _sendMessage 和 _resendMessage 调用）
  Future<void> _sendMessageInternal() async {
    final taskConversationId = _currentConversationId;
    if (taskConversationId == null) {
      _taskSetState(() {
        _isLoading = false;
        _aiStatusText = null;
      });
      return;
    }
    if (!_taskCoordinator.begin(taskConversationId)) {
      _taskSetState(() {
        _isLoading = false;
        _aiStatusText = null;
      });
      return;
    }
    _activeTaskConversationId = taskConversationId;
    final backgroundLeaseAcquired = await _backgroundExecution.acquire();
    var taskFailed = false;

    final tempAssistantMessage = ChatMessage(
      id: DateTime.now().toString(),
      role: MessageRole.assistant,
      content: [MessageContent.text(text: '')],
      timestamp: DateTime.now(),
    );

    _taskSetState(() {
      _messages.add(tempAssistantMessage);
      _streamingText = '';
      _streamingReasoningText = '';
      _shouldStopStreaming = false;
    });

    _scrollToBottom();

    String? requestModelId;
    try {
      // 获取当前有效的模型，应用聊天页的 thinking 开关覆盖
      final baseModel = _resolveActiveModel();
      if (baseModel == null) {
        throw Exception('尚未配置 AI 模型，请先前往“模型管理”添加自己的模型和 API Key');
      }
      final currentModel = baseModel.copyWith(
        capabilities: baseModel.capabilities.copyWith(
          enableThinking: _enableThinking,
        ),
      );
      requestModelId = currentModel.id;
      final aiService = AIServiceFactory.create(currentModel);

      await _compressContextIfNeeded(currentModel);

      // 准备消息历史（不包括刚添加的临时消息）。历史保持追加式，
      // 仅在用户确认后达到阈值时用摘要替换较早的模型上下文。
      var allHistory = _messages.sublist(0, _messages.length - 1);

      // 处理图片：将本地路径转换为 base64
      final processedHistory = <ChatMessage>[];
      for (var msg in allHistory) {
        var hasImage = false;
        final processedContent = <MessageContent>[];

        for (var content in msg.content) {
          if (content is ImageContent &&
              content.data.isEmpty &&
              content.localPath != null) {
            try {
              final imageFile = File(content.localPath!);
              final imageBytes = await imageFile.readAsBytes();
              final base64Image = base64Encode(imageBytes);

              // 添加带 base64 数据的图片内容
              processedContent.add(
                MessageContent.image(
                  data: base64Image,
                  mimeType: content.mimeType ?? 'image/jpeg',
                  localPath: content.localPath,
                ),
              );
              hasImage = true;
            } catch (e) {
              debugPrint('❌ Failed to read image file: $e');
              // 即使失败也添加原内容
              processedContent.add(content);
            }
          } else {
            processedContent.add(content);
          }
        }

        // 如果有图片被处理，创建新的消息对象
        if (hasImage) {
          processedHistory.add(
            ChatMessage(
              id: msg.id,
              role: msg.role,
              content: processedContent,
              timestamp: msg.timestamp,
              modelId: msg.modelId,
              reasoningContent: msg.reasoningContent,
              runtimeContext: msg.runtimeContext,
              createdRecipeIds: msg.createdRecipeIds,
            ),
          );
        } else {
          processedHistory.add(msg);
        }
      }

      allHistory = processedHistory;

      final summarizedCount = _contextState.summarizedMessageCount.clamp(
        0,
        allHistory.length,
      );
      final recentMessages = allHistory
          .skip(summarizedCount)
          .where((msg) => msg.role != MessageRole.system)
          .toList();

      // 检查模型是否支持工具调用（在生成 system prompt 之前）
      final modelInfo = await aiService.getModelInfo();
      final supportsTools = modelInfo['supports_tools'] == true;
      final shouldUseMcpTools = _mcpTools.isNotEmpty && supportsTools;

      // 在第一条消息前添加 system prompt（根据模型能力动态生成）
      var history = [
        ChatMessage(
          id: 'system',
          role: MessageRole.system,
          content: [
            MessageContent.text(
              text: _buildSystemPrompt(supportsTools: supportsTools),
            ),
          ],
          timestamp: DateTime.now(),
        ),
        if (_contextState.hasSummary)
          ChatMessage(
            id: 'conversation-summary',
            role: MessageRole.system,
            content: [
              MessageContent.text(
                text:
                    '以下是较早对话的压缩摘要。将它作为历史事实和用户偏好继续对话；若与较新消息冲突，以较新消息为准：\n${_contextState.summary}',
              ),
            ],
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ...recentMessages,
      ];

      // MCP 工具调用循环
      if (shouldUseMcpTools) {
        debugPrint(
          'Starting recipe tool calling loop with ${_mcpTools.length} tools',
        );

        // 使用非流式API进行工具调用循环（最多10轮）
        var toolCallCount = 0;
        const maxToolCalls = 10;
        // 收集本次对话创建的食谱ID列表
        final createdRecipeIds = <String>[];
        // 跨轮次累积文本（AI 先说话再调工具的场景）
        final accumulatedText = StringBuffer();
        // 跨轮次累积思考内容
        final accumulatedReasoning = StringBuffer();

        _taskSetState(() {
          _streamingReasoningText = '';
        });

        while (toolCallCount < maxToolCalls && !_shouldStopStreaming) {
          toolCallCount++;
          debugPrint('Tool call iteration $toolCallCount');

          _taskSetState(() {
            _aiStatusText = toolCallCount == 1 ? '分析并选择工具中...' : '整理工具结果中...';
          });

          final streamingTextBuffer = StringBuffer();

          AIUsageMetrics? requestUsage;
          final response = await aiService.sendMessageSync(
            messages: history,
            tools: _mcpTools,
            onUsage: (usage) {
              requestUsage = _mergeUsage(requestUsage, usage);
            },
            onTextChunk: (chunk) {
              streamingTextBuffer.write(chunk);
              scheduleMicrotask(() {
                _taskSetState(() {
                  _aiStatusText = null;
                  final lastIndex = _messages.length - 1;
                  final display = accumulatedText.isEmpty
                      ? streamingTextBuffer.toString()
                      : '${accumulatedText.toString()}\n\n${streamingTextBuffer.toString()}';
                  _messages[lastIndex] = ChatMessage(
                    id: tempAssistantMessage.id,
                    role: MessageRole.assistant,
                    content: [MessageContent.text(text: display)],
                    timestamp: tempAssistantMessage.timestamp,
                    modelId: currentModel.id,
                  );
                  _schedulePartialSave();
                });
              });
            },
            onReasoningContent: (value) {
              _taskSetState(() {
                _aiStatusText = '思考中...';
                _streamingReasoningText = accumulatedReasoning.isEmpty
                    ? value
                    : '${accumulatedReasoning.toString()}\n\n$value';
              });
            },
          );
          _recordUsage(requestUsage);

          // A synchronous tool-planning request cannot be interrupted at the
          // socket level, but its late result must not restart a task the user
          // already stopped.
          if (_shouldStopStreaming) break;

          debugPrint(
            '📨 Got response with ${response.content.length} content items',
          );

          // 打印所有 content 类型
          for (var i = 0; i < response.content.length; i++) {
            final content = response.content[i];
            if (content is TextContent) {
              debugPrint('📨 Content[$i]: Text (${content.text.length} chars)');
            } else if (content is ToolUseContent) {
              debugPrint('📨 Content[$i]: ToolUse (name: ${content.name})');
            } else {
              debugPrint('📨 Content[$i]: ${content.runtimeType}');
            }
          }

          // 检查是否有 tool_calls
          final hasToolCalls = response.content.any((c) => c is ToolUseContent);

          if (!hasToolCalls) {
            debugPrint('📨 No tool calls, displaying final response');
            // 如果有前置累积文本，把它拼到最终文本内容前面
            List<MessageContent> finalContent = response.content;
            if (accumulatedText.isNotEmpty) {
              final responseText = response.content
                  .whereType<TextContent>()
                  .map((c) => c.text)
                  .join();
              final merged = '${accumulatedText.toString()}\n\n$responseText'
                  .trim();
              finalContent = [
                MessageContent.text(text: merged),
                ...response.content.where((c) => c is! TextContent),
              ];
            }
            _taskSetState(() {
              final lastIndex = _messages.length - 1;
              _messages[lastIndex] = ChatMessage(
                id: tempAssistantMessage.id,
                role: MessageRole.assistant,
                content: finalContent,
                timestamp: tempAssistantMessage.timestamp,
                modelId: currentModel.id,
                reasoningContent: _buildFinalReasoning(
                  accumulatedReasoning,
                  response.reasoningContent,
                ),
                createdRecipeIds: createdRecipeIds.isNotEmpty
                    ? createdRecipeIds
                    : null,
              );
              _isLoading = false;
              _aiStatusText = null;
              _streamingReasoningText = '';
            });
            break;
          }

          // 有工具调用，执行工具
          debugPrint('Found tool calls, executing...');
          // 把本轮文本追加到跨轮累积区
          final roundText = streamingTextBuffer.toString();
          if (roundText.isNotEmpty) {
            if (accumulatedText.isNotEmpty) accumulatedText.write('\n\n');
            accumulatedText.write(roundText);
          }
          // 把本轮思考内容追加到跨轮累积区
          if (response.reasoningContent != null &&
              response.reasoningContent!.isNotEmpty) {
            if (accumulatedReasoning.isNotEmpty) {
              accumulatedReasoning.write('\n\n');
            }
            accumulatedReasoning.write(response.reasoningContent);
          }
          final toolResults = <MessageContent>[];

          for (final content in response.content) {
            if (content is ToolUseContent) {
              debugPrint('Executing tool: ${content.name}');
              _taskSetState(() {
                _aiStatusText = _toolStatusText(content.name);
              });

              try {
                // 执行 MCP 工具
                final result = await _executeMCPTool(
                  content.name,
                  content.input,
                );
                debugPrint('Tool ${content.name} executed successfully');

                // 如果是 createRecipe 工具且成功，收集创建的食谱 ID
                final cleanToolName = content.name.replaceFirst(
                  'mcp_howtocook_',
                  '',
                );
                if (cleanToolName == 'createRecipe' &&
                    result['success'] == true &&
                    result.containsKey('recipe')) {
                  final recipeData = result['recipe'] as Map<String, dynamic>?;
                  if (recipeData != null && recipeData.containsKey('id')) {
                    final recipeId = recipeData['id'] as String;
                    createdRecipeIds.add(recipeId);
                    debugPrint('✅ Collected created recipe ID: $recipeId');
                  }
                }

                toolResults.add(
                  MessageContent.toolResult(
                    toolUseId: content.toolUseId,
                    result: result,
                  ),
                );
              } catch (e) {
                debugPrint('Tool ${content.name} execution failed: $e');
                toolResults.add(
                  MessageContent.toolResult(
                    toolUseId: content.toolUseId,
                    result: {'error': e.toString()},
                  ),
                );
              }
            }
          }

          // 将 AI 的 tool_calls 和工具结果添加到历史
          // 注意：每个 tool result 需要单独的消息，因为适配器会为每个生成独立的 API 消息
          final toolResultMessages = toolResults.map((result) {
            return ChatMessage(
              id: DateTime.now().toString(),
              role: MessageRole.user, // tool results 的角色（适配器会转换为 'tool'）
              content: [result],
              timestamp: DateTime.now(),
            );
          }).toList();

          history = [...history, response, ...toolResultMessages];
        }

        if (toolCallCount >= maxToolCalls) {
          debugPrint('WARNING: Reached max tool call iterations');
          _taskSetState(() {
            final lastIndex = _messages.length - 1;
            _messages[lastIndex] = ChatMessage(
              id: tempAssistantMessage.id,
              role: MessageRole.assistant,
              content: [MessageContent.text(text: '抱歉，工具调用次数过多，请重新尝试。')],
              timestamp: tempAssistantMessage.timestamp,
              modelId: currentModel.id, // 保存使用的模型ID
              createdRecipeIds: createdRecipeIds.isNotEmpty
                  ? createdRecipeIds
                  : null,
            );
            _isLoading = false;
            _aiStatusText = null;
            _streamingReasoningText = '';
          });
        }
      } else {
        // 没有可用的 MCP 工具或模型不支持工具调用
        // 检查模型是否启用流式输出
        final enableStreaming = currentModel.capabilities.enableStreaming;

        if (enableStreaming) {
          // 使用流式响应
          debugPrint('Using streaming response (streaming enabled)');

          _taskSetState(() {
            _isStreaming = true;
            _streamingText = '';
            _streamingReasoningText = '';
          });

          String? reasoningContent;
          AIUsageMetrics? requestUsage;
          final responseStream = aiService.sendMessage(
            messages: history,
            onUsage: (usage) {
              requestUsage = _mergeUsage(requestUsage, usage);
            },
            onReasoningContent: (value) {
              reasoningContent = value;
              _taskSetState(() {
                _aiStatusText = '思考中...';
                _streamingReasoningText = value;
              });
            },
          );

          // 累积响应文本
          final responseBuffer = StringBuffer();
          var chunkCount = 0;

          await for (final chunk in responseStream) {
            // 检查用户是否点击了终止按钮
            if (_shouldStopStreaming) {
              debugPrint('Streaming stopped by user at chunk $chunkCount');
              break;
            }

            chunkCount++;
            responseBuffer.write(chunk);

            _taskSetState(() {
              _aiStatusText = null;
              _streamingText = responseBuffer.toString();
            });
            _schedulePartialSave();
          }
          _recordUsage(requestUsage);

          debugPrint(
            'Streaming complete. Received $chunkCount chunks, total ${responseBuffer.length} characters',
          );

          // 检查是否包含 XML 格式的工具调用（思考链模式）
          final responseText = responseBuffer.toString();
          final xmlToolCalls = _parseXmlToolCalls(responseText);

          if (xmlToolCalls.isNotEmpty) {
            debugPrint(
              '🔧 Found ${xmlToolCalls.length} XML tool calls in streaming response',
            );

            // 关闭流式状态，但保持加载状态
            _taskSetState(() {
              _isStreaming = false;
            });

            // 收集创建的菜谱 ID
            final createdRecipeIds = <String>[];

            // 执行所有工具调用并收集结果
            final toolResultsXml = StringBuffer();
            for (final toolCall in xmlToolCalls) {
              final toolUseId = toolCall['id'] as String;
              final toolName = toolCall['name'] as String;
              final toolArgs = toolCall['arguments'] as Map<String, dynamic>;

              debugPrint('🔧 Executing XML tool: $toolName (id: $toolUseId)');
              _taskSetState(() {
                _aiStatusText = _toolStatusText(toolName);
              });
              try {
                final result = await _executeMCPTool(toolName, toolArgs);
                toolResultsXml.writeln(
                  _formatToolResultAsXml(toolUseId, toolName, result),
                );

                // 如果是 createRecipe 工具且成功，收集创建的食谱 ID
                final cleanToolName = toolName.replaceFirst(
                  'mcp_howtocook_',
                  '',
                );
                if (cleanToolName == 'createRecipe' &&
                    result['success'] == true &&
                    result.containsKey('recipe')) {
                  final recipeData = result['recipe'] as Map<String, dynamic>?;
                  if (recipeData != null && recipeData.containsKey('id')) {
                    createdRecipeIds.add(recipeData['id'] as String);
                  }
                }
              } catch (e) {
                debugPrint('❌ XML tool execution failed: $e');
                toolResultsXml.writeln(
                  _formatToolResultAsXml(toolUseId, toolName, {
                    'error': e.toString(),
                  }),
                );
              }
            }

            // 移除原文本中的工具调用标签，保留其他内容
            final cleanResponseText = _removeXmlToolCalls(responseText);

            // 更新历史，添加 AI 响应和工具结果
            history = [
              ...history,
              ChatMessage(
                id: DateTime.now().toString(),
                role: MessageRole.assistant,
                content: [MessageContent.text(text: responseText)],
                timestamp: DateTime.now(),
                reasoningContent: reasoningContent,
              ),
              ChatMessage(
                id: DateTime.now().toString(),
                role: MessageRole.user,
                content: [MessageContent.text(text: toolResultsXml.toString())],
                timestamp: DateTime.now(),
              ),
            ];

            // 发送下一轮请求让 AI 处理工具结果
            debugPrint('🔧 Sending tool results back to AI...');
            final nextResponseBuffer = StringBuffer();
            String? nextReasoningContent;

            _taskSetState(() {
              _isStreaming = true;
              _aiStatusText = '回复中...';
              _streamingText = cleanResponseText.isNotEmpty
                  ? '$cleanResponseText\n\n'
                  : '';
              _streamingReasoningText = '';
            });

            AIUsageMetrics? nextRequestUsage;
            final nextStream = aiService.sendMessage(
              messages: history,
              onUsage: (usage) {
                nextRequestUsage = _mergeUsage(nextRequestUsage, usage);
              },
              onReasoningContent: (value) {
                nextReasoningContent = value;
                _taskSetState(() {
                  _aiStatusText = '思考中...';
                  _streamingReasoningText = value;
                });
              },
            );

            await for (final chunk in nextStream) {
              if (_shouldStopStreaming) break;
              nextResponseBuffer.write(chunk);
              _taskSetState(() {
                _aiStatusText = null;
                _streamingText = cleanResponseText.isNotEmpty
                    ? '$cleanResponseText\n\n${nextResponseBuffer.toString()}'
                    : nextResponseBuffer.toString();
              });
            }
            _recordUsage(nextRequestUsage);

            // 最终响应
            final finalText = cleanResponseText.isNotEmpty
                ? '$cleanResponseText\n\n${nextResponseBuffer.toString()}'
                : nextResponseBuffer.toString();

            _taskSetState(() {
              _isStreaming = false;
              _isLoading = false;
              _aiStatusText = null;
              final lastIndex = _messages.length - 1;
              _messages[lastIndex] = ChatMessage(
                id: tempAssistantMessage.id,
                role: MessageRole.assistant,
                content: [MessageContent.text(text: finalText)],
                timestamp: tempAssistantMessage.timestamp,
                modelId: currentModel.id,
                reasoningContent: reasoningContent ?? nextReasoningContent,
                createdRecipeIds: createdRecipeIds.isNotEmpty
                    ? createdRecipeIds
                    : null,
              );
            });
          } else {
            // 没有工具调用，直接显示响应
            _taskSetState(() {
              _isStreaming = false;
              _isLoading = false;
              _aiStatusText = null;
              final lastIndex = _messages.length - 1;
              _messages[lastIndex] = ChatMessage(
                id: tempAssistantMessage.id,
                role: MessageRole.assistant,
                content: [MessageContent.text(text: responseBuffer.toString())],
                timestamp: tempAssistantMessage.timestamp,
                modelId: currentModel.id,
                reasoningContent:
                    (reasoningContent != null && reasoningContent!.isNotEmpty)
                    ? reasoningContent
                    : null,
              );
            });
          }
        } else {
          // 使用非流式响应（等待完整回复）
          debugPrint('Using non-streaming response (streaming disabled)');

          AIUsageMetrics? requestUsage;
          final response = await aiService.sendMessageSync(
            messages: history,
            onUsage: (usage) {
              requestUsage = _mergeUsage(requestUsage, usage);
            },
          );
          _recordUsage(requestUsage);

          if (_shouldStopStreaming) return;

          // 更新最终消息（使用响应中的reasoning内容）
          _taskSetState(() {
            _isLoading = false;
            _aiStatusText = null;
            final lastIndex = _messages.length - 1;
            _messages[lastIndex] = ChatMessage(
              id: tempAssistantMessage.id,
              role: MessageRole.assistant,
              content: response.content,
              timestamp: tempAssistantMessage.timestamp,
              modelId: currentModel.id, // 保存使用的模型ID
              reasoningContent: response.reasoningContent,
            );
          });
        }
      }

      // 保存聊天历史
      await _saveChatHistory(conversationId: taskConversationId);
      _scrollToBottom();
    } catch (e, stackTrace) {
      taskFailed = true;
      debugPrint('Error sending message: $e');
      debugPrint('Stack trace: $stackTrace');

      _taskSetState(() {
        var partialText = _streamingText;
        String? partialReasoning = _streamingReasoningText.isEmpty
            ? null
            : _streamingReasoningText;
        // 重置流式状态
        _isStreaming = false;
        _isLoading = false;
        _aiStatusText = null;
        _streamingText = '';
        _streamingReasoningText = '';

        // 已经输出的正文不能被错误消息覆盖。保留部分回复并在末尾标记中断；
        // 尚未收到正文时才显示纯错误消息。
        if (_messages.isNotEmpty &&
            _messages.last.id == tempAssistantMessage.id) {
          final messageText = _messages.last.content
              .whereType<TextContent>()
              .map((item) => item.text)
              .join();
          if (messageText.trim().isNotEmpty) partialText = messageText;
          partialReasoning ??= _messages.last.reasoningContent;
          _messages.removeLast();
        }
        final cleanError = e.toString().replaceFirst('Exception: ', '');
        final errorText = partialText.trim().isEmpty
            ? '抱歉，本次请求失败：$cleanError'
            : '${partialText.trim()}\n\n> 回复因网络或接口错误中断：$cleanError';
        _messages.add(
          ChatMessage(
            id: DateTime.now().toString(),
            role: MessageRole.assistant,
            content: [MessageContent.text(text: errorText)],
            timestamp: DateTime.now(),
            modelId: requestModelId,
            reasoningContent: partialReasoning,
          ),
        );
      });

      // 保存错误消息
      await _saveChatHistory(conversationId: taskConversationId);

      if (mounted) {
        AppSnackBar.show(
          context,
          '发送失败: $e',
          bottomOffset: AppSnackBar.kChatBottomOffset,
        );
      }
    } finally {
      if (_shouldStopStreaming) {
        _taskSetState(() {
          _isLoading = false;
          _isStreaming = false;
          _aiStatusText = null;
          if (_messages.isNotEmpty &&
              _messages.last.id == tempAssistantMessage.id) {
            final partialText = _messages.last.content
                .whereType<TextContent>()
                .map((item) => item.text)
                .join()
                .trim();
            if (partialText.isEmpty) {
              _messages[_messages.length - 1] = ChatMessage(
                id: tempAssistantMessage.id,
                role: MessageRole.assistant,
                content: [MessageContent.text(text: '（已停止生成）')],
                timestamp: tempAssistantMessage.timestamp,
                modelId: requestModelId,
              );
            }
          }
        });
      }
      await _saveChatHistory(conversationId: taskConversationId);
      if (backgroundLeaseAcquired) {
        await _backgroundExecution.release();
      }
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (!_shouldStopStreaming &&
          lifecycleState != null &&
          lifecycleState != AppLifecycleState.resumed) {
        try {
          await AppNotificationService.instance.showAIChatResult(
            succeeded: !taskFailed,
          );
        } catch (error, stackTrace) {
          debugPrint('Unable to show AI completion notification: $error');
          debugPrint('$stackTrace');
        }
      }
      _activeTaskConversationId = null;
      _taskCoordinator.finish();
      if (mounted) setState(() {});
    }
  }

  void _schedulePartialSave() {
    if (_partialSaveTimer?.isActive == true) return;
    _partialSaveTimer = Timer(const Duration(seconds: 1), () {
      _saveChatHistory();
    });
  }

  /// 解析 XML 格式的工具调用（CherryStudio 风格）
  ///
  /// 从响应文本中提取 `<tool_use>` 标签内容
  /// 返回工具调用列表，每个元素包含 id, name 和 arguments
  List<Map<String, dynamic>> _parseXmlToolCalls(String text) {
    final toolCalls = <Map<String, dynamic>>[];

    // 匹配 <tool_use>...</tool_use> 块（支持可选的 <id> 标签）
    final toolUseRegex = RegExp(
      r'<tool_use>\s*(?:<id>([^<]*)</id>\s*)?<name>([^<]+)</name>\s*<arguments>([^<]*)</arguments>\s*</tool_use>',
      multiLine: true,
      dotAll: true,
    );

    for (final match in toolUseRegex.allMatches(text)) {
      final idFromXml = match.group(1)?.trim();
      final name = match.group(2)?.trim();
      final argumentsStr = match.group(3)?.trim();

      if (name != null && name.isNotEmpty) {
        // 生成稳定的 tool_use_id：如果 XML 中有 id 则使用，否则生成一个
        final toolUseId = (idFromXml != null && idFromXml.isNotEmpty)
            ? idFromXml
            : 'xml-${DateTime.now().microsecondsSinceEpoch}-${toolCalls.length}';

        Map<String, dynamic> arguments = {};
        if (argumentsStr != null && argumentsStr.isNotEmpty) {
          try {
            arguments = jsonDecode(argumentsStr) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('⚠️ Failed to parse tool arguments JSON: $e');
          }
        }

        toolCalls.add({'id': toolUseId, 'name': name, 'arguments': arguments});
        debugPrint(
          '🔧 Parsed XML tool call: id=$toolUseId, name=$name, arguments=$arguments',
        );
      }
    }

    return toolCalls;
  }

  /// 移除响应文本中的 XML 工具调用标签
  ///
  /// 保留工具调用之外的正常文本内容
  String _removeXmlToolCalls(String text) {
    // 移除 <tool_use>...</tool_use> 块
    return text
        .replaceAll(
          RegExp(
            r'<tool_use>\s*<name>[^<]+</name>\s*<arguments>[^<]*</arguments>\s*</tool_use>',
            multiLine: true,
            dotAll: true,
          ),
          '',
        )
        .trim();
  }

  /// 格式化工具结果为 XML 格式（包含 tool_use_id 以便 AI 关联调用和结果）
  String _formatToolResultAsXml(
    String toolUseId,
    String toolName,
    Map<String, dynamic> result,
  ) {
    return '''<tool_use_result>
  <id>$toolUseId</id>
  <name>$toolName</name>
  <result>${jsonEncode(result)}</result>
</tool_use_result>''';
  }

  /// 执行 MCP 工具
  ///
  /// 根据工具名称调用相应的 MCPService 方法
  Future<Map<String, dynamic>> _executeMCPTool(
    String toolName,
    Map<String, dynamic> input,
  ) async {
    // 移除 mcp_howtocook_ 前缀（如果有）
    final cleanToolName = toolName.replaceFirst('mcp_howtocook_', '');

    debugPrint('🔧 ===== MCP Tool Call Start =====');
    debugPrint('🔧 Tool: $cleanToolName');
    debugPrint('🔧 Input: $input');

    // 记录开始时间
    final startTime = DateTime.now();
    Map<String, dynamic>? result;
    String? errorMessage;

    try {
      final executionInput = Map<String, dynamic>.from(input);
      if (cleanToolName == 'createRecipe' &&
          executionInput['recipeText'] == null &&
          executionInput['recipe'] is Map) {
        executionInput['recipeText'] = _legacyCompatibleRecipeText(
          Map<String, dynamic>.from(executionInput['recipe'] as Map),
        );
      }
      final appResult = await _recipeToolService.execute(
        mode: _contextState.recipeDataMode,
        toolName: cleanToolName,
        input: executionInput,
      );
      // 创建工具还需在聊天页生成可预览卡片；其他工具直接使用统一执行器结果。
      if (cleanToolName != 'createRecipe' || appResult['success'] != true) {
        result = appResult;
      }
      if (result == null) {
        switch (cleanToolName) {
          case 'getAllRecipes':
            final recipes = await _mcpService.getAllRecipes();
            result = {
              'success': true,
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'count': recipes.length,
            };
            break;

          case 'getRecipesByCategory':
            // 支持多种参数名
            final categoryValue = input['category'] ?? input['categoryName'];
            final category = categoryValue?.toString();
            if (category == null || category.isEmpty) {
              throw Exception('Missing required parameter: category');
            }
            final recipes = await _mcpService.getRecipesByCategory(category);
            result = {
              'success': true,
              'category': category,
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'count': recipes.length,
            };
            break;

          case 'getRecipeById':
            // 支持多种参数名：query, id, recipeId, recipeName
            final queryValue =
                input['query'] ??
                input['id'] ??
                input['recipeId'] ??
                input['recipeName'];
            final query = queryValue?.toString();
            if (query == null || query.isEmpty) {
              throw Exception('Missing required parameter: query/id');
            }

            // 检查是否是生成的 ID（格式：recipe_数字）
            if (query.startsWith('recipe_')) {
              result = {
                'success': false,
                'error':
                    'Generated ID "$query" cannot be used for detail query. '
                    'Please use the recipe name instead. '
                    'Example: Use "红烧肉" instead of "$query".',
              };
              break;
            }

            final recipeResult = await _mcpService.getRecipeById(query);
            if (recipeResult is Recipe) {
              result = {'success': true, 'recipe': recipeResult.toJson()};
            } else if (recipeResult is Map<String, dynamic>) {
              if (recipeResult.containsKey('possibleMatches')) {
                result = {
                  'success': false,
                  'exactMatch': false,
                  ...recipeResult,
                };
              } else {
                result = {'success': false, ...recipeResult};
              }
            } else {
              result = {'success': false, 'error': recipeResult.toString()};
            }
            break;

          case 'recommendMeals':
            // 支持多种参数名：peopleCount, numberOfPeople, people
            final peopleCount = _parseIntParam(
              input['peopleCount'] ??
                  input['numberOfPeople'] ??
                  input['people'],
              defaultValue: 2,
            );
            final allergies = input['allergies'] as List<dynamic>?;
            final avoidItems = input['avoidItems'] as List<dynamic>?;

            final mealsResult = await _mcpService.recommendMeals(
              peopleCount: peopleCount,
              allergies: allergies?.cast<String>(),
              avoidItems: avoidItems?.cast<String>(),
            );
            result = {'success': true, ...mealsResult};
            break;

          case 'whatToEat':
            // 支持多种参数名：peopleCount, numberOfPeople, people
            // 如果没有提供参数，默认2人
            final peopleCount = _parseIntParam(
              input['peopleCount'] ??
                  input['numberOfPeople'] ??
                  input['people'],
              defaultValue: 2,
            );
            debugPrint('whatToEat with peopleCount: $peopleCount');

            final recipes = await _mcpService.whatToEat(
              peopleCount: peopleCount,
            );
            result = {
              'success': true,
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'count': recipes.length,
              'peopleCount': peopleCount,
            };
            break;

          case 'createRecipe':
            final structuredRecipe = input['recipe'] is Map
                ? Map<String, dynamic>.from(input['recipe'] as Map)
                : null;
            final recipeTextValue = input['recipeText'] ?? input['text'];
            final recipeText = recipeTextValue?.toString();
            if (structuredRecipe == null &&
                (recipeText == null || recipeText.trim().isEmpty)) {
              throw Exception(
                'Missing required parameter: recipe or recipeText',
              );
            }
            final createResult = appResult;
            if (createResult['recipe'] is Map) {
              final recipeData = Map<String, dynamic>.from(
                createResult['recipe'] as Map,
              );
              if (structuredRecipe != null) {
                // 旧 MCP 会丢弃 V2 字段，以模型的原始结构化输入补回。
                recipeData.addAll(structuredRecipe);
              }
              final rawId = recipeData['id']?.toString() ?? '';
              final isUuid = RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                caseSensitive: false,
              ).hasMatch(rawId);
              final recipeId = isUuid ? rawId : const Uuid().v4();
              final ingredients = (recipeData['ingredients'] as List? ?? [])
                  .map((item) {
                    if (item is Map) {
                      final value = Map<String, dynamic>.from(item);
                      final rawText =
                          (value['text'] ??
                                  value['text_quantity'] ??
                                  value['name'] ??
                                  '')
                              .toString();
                      final name =
                          (value['name'] ?? rawText.split(RegExp(r'\s+')).first)
                              .toString();
                      return {
                        ...value,
                        'name': name,
                        'text': completeIngredientText(name, rawText),
                        'optional': value['optional'] == true,
                      };
                    }
                    final text = item.toString();
                    return {
                      'name': text.split(RegExp(r'\s+')).first,
                      'text': text,
                    };
                  })
                  .toList();
              final steps = (recipeData['steps'] as List? ?? []).map((item) {
                if (item is Map) {
                  final value = Map<String, dynamic>.from(item);
                  return {
                    ...value,
                    'kind': value['kind'] ?? 'step',
                    'description': (value['description'] ?? '').toString(),
                  };
                }
                return {'kind': 'step', 'description': item.toString()};
              }).toList();
              final additionalNotes = recipeData['additional_notes'];
              final sanitizedData = <String, dynamic>{
                ...recipeData,
                'schemaVersion': 2,
                'id': recipeId,
                'legacyIds': recipeData['legacyIds'] ?? const <String>[],
                'name': (recipeData['name'] ?? '未命名食谱').toString().replaceFirst(
                  RegExp(r'的做法$'),
                  '',
                ),
                'description': recipeData['description'],
                'category': _normalizeRecipeCategory(recipeData),
                'categoryName': _normalizeRecipeCategoryName(recipeData),
                'difficulty': recipeData['difficulty'] ?? 3,
                'estimatedCaloriesKcal': _parsePositiveIntOrNull(
                  recipeData['estimatedCaloriesKcal'],
                ),
                'requirements': recipeData['requirements'] ?? const [],
                'ingredients': ingredients,
                'tools': recipeData['tools'] ?? const [],
                'calculationNotes': recipeData['calculationNotes'] ?? const [],
                'steps': steps,
                'tips':
                    recipeData['tips'] ??
                    (additionalNotes is List
                        ? additionalNotes.join('\n')
                        : additionalNotes),
                'warnings': recipeData['warnings'] ?? const [],
                'images': recipeData['images'] ?? const [],
                'externalImages': recipeData['externalImages'] ?? const [],
                'hash': recipeData['hash'] ?? recipeId,
                'source': RecipeSource.aiGenerated.name,
              };
              final recipe = Recipe.fromJson(
                sanitizedData,
              ).copyWith(source: RecipeSource.aiGenerated);
              _taskSetState(() => _createdRecipes[recipe.id] = recipe);
              _saveCreatedRecipes(conversationId: _activeTaskConversationId);
              result = {
                ...createResult,
                'success': true,
                'recipe': recipe.toJson(),
              };
            } else {
              result = {
                ...createResult,
                'success': createResult['success'] == true,
              };
            }
            break;

          default:
            throw Exception('Unknown MCP tool: $cleanToolName');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('MCP tool execution error: $e');
      debugPrint('Stack trace: $stackTrace');
      errorMessage = e.toString();
      result = {'success': false, 'error': e.toString()};
    }

    // 记录工具调用（仅在 debug 模式）
    final duration = DateTime.now().difference(startTime);

    debugPrint('🔧 ===== MCP Tool Call End =====');
    debugPrint('🔧 Tool: $cleanToolName');
    debugPrint('🔧 Duration: ${duration.inMilliseconds}ms');
    debugPrint('🔧 Success: ${result['success']}');
    if (errorMessage != null) {
      debugPrint('🔧 Error: $errorMessage');
    }
    debugPrint('🔧 Result keys: ${result.keys.toList()}');
    debugPrint('🔧 ==============================');

    if (kDebugMode) {
      final toolCall = MCPToolCall(
        toolName: cleanToolName,
        timestamp: startTime,
        input: input,
        output: result,
        error: errorMessage,
        duration: duration,
      );

      _taskSetState(() {
        _mcpCallHistory.add(toolCall);
        // 只保留最近 50 条记录
        if (_mcpCallHistory.length > 50) {
          _mcpCallHistory.removeAt(0);
        }
      });
    }

    return result;
  }

  /// 解析整数参数（容错处理）
  String _legacyCompatibleRecipeText(Map<String, dynamic> recipe) {
    String itemText(dynamic item) {
      if (item is Map) {
        final name = (item['name'] ?? '').toString();
        final text = (item['text'] ?? item['description'] ?? item['name'] ?? '')
            .toString();
        return completeIngredientText(name, text);
      }
      return item.toString();
    }

    final ingredients = (recipe['ingredients'] as List? ?? [])
        .map(itemText)
        .where((item) => item.isNotEmpty)
        .toList();
    final steps = (recipe['steps'] as List? ?? [])
        .map(itemText)
        .map((item) => item.replaceFirst(RegExp(r'^[\d①-⑳]+[.、：:\s]+'), ''))
        .where((item) => item.isNotEmpty)
        .toList();
    return jsonEncode({
      'name': recipe['name'],
      'description': recipe['description'],
      'category': recipe['category'],
      'categoryName': recipe['categoryName'],
      'difficulty': recipe['difficulty'],
      'estimatedCaloriesKcal': recipe['estimatedCaloriesKcal'],
      'ingredients': ingredients,
      'tools': recipe['tools'] ?? const [],
      'steps': steps,
      'tips': recipe['tips'],
      'warnings': recipe['warnings'] ?? const [],
    });
  }

  String _normalizeRecipeCategory(Map<String, dynamic> data) {
    const ids = {
      'aquatic',
      'breakfast',
      'condiment',
      'dessert',
      'drink',
      'meat_dish',
      'semi-finished',
      'soup',
      'staple',
      'vegetable_dish',
    };
    const byName = {
      '水产': 'aquatic',
      '早餐': 'breakfast',
      '调料': 'condiment',
      '调味品': 'condiment',
      '甜品': 'dessert',
      '饮料': 'drink',
      '饮品': 'drink',
      '荤菜': 'meat_dish',
      '肉类': 'meat_dish',
      '半成品': 'semi-finished',
      '半成品加工': 'semi-finished',
      '汤': 'soup',
      '汤粥': 'soup',
      '汤羹': 'soup',
      '主食': 'staple',
      '素菜': 'vegetable_dish',
    };
    final raw = data['category']?.toString() ?? '';
    if (ids.contains(raw)) return raw;
    return byName[data['categoryName']?.toString()] ??
        byName[raw] ??
        'vegetable_dish';
  }

  String _normalizeRecipeCategoryName(Map<String, dynamic> data) {
    final explicit = data['categoryName']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    const byId = {
      'aquatic': '水产',
      'breakfast': '早餐',
      'condiment': '调料',
      'dessert': '甜品',
      'drink': '饮料',
      'meat_dish': '荤菜',
      'semi-finished': '半成品',
      'soup': '汤粥',
      'staple': '主食',
      'vegetable_dish': '素菜',
    };
    final category = _normalizeRecipeCategory(data);
    return byId[category] ?? data['category']?.toString() ?? '其他';
  }

  int _parseIntParam(dynamic value, {required int defaultValue}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    debugPrint(
      'Warning: Could not parse int from $value, using default $defaultValue',
    );
    return defaultValue;
  }

  int? _parsePositiveIntOrNull(dynamic value) {
    if (value == null) return null;
    final parsed = switch (value) {
      int number => number,
      num number => number.round(),
      _ => int.tryParse(
        RegExp(
              r'\d+',
            ).firstMatch(value.toString().replaceAll(',', ''))?.group(0) ??
            '',
      ),
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  /// 滚动到底部
  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 终止流式输出
  void _stopStreaming() {
    _taskCoordinator.requestStop();
    _taskSetState(() {
      _shouldStopStreaming = true;
      _aiStatusText = '正在停止...';
      _isStreaming = false;
    });
    debugPrint('User stopped streaming');
  }

  /// 显示编辑对话框
  void _showEditDialog(BuildContext context, ChatMessage message, int index) {
    final textContent = message.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join('\n');

    final TextEditingController editController = TextEditingController(
      text: textContent,
    );
    bool isDisposed = false; // 标记 controller 是否已释放

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // 检查内容是否有改动（安全检查 controller 状态）
          final hasChanged =
              !isDisposed && editController.text.trim() != textContent;

          return AlertDialog(
            title: const Text('编辑消息'),
            content: TextField(
              controller: editController,
              maxLines: null,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入消息内容...',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                // 内容改变时刷新对话框状态（仅当 controller 未释放）
                if (!isDisposed && mounted) {
                  setDialogState(() {});
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // 取消：先标记已释放，再关闭对话框，最后 dispose
                  isDisposed = true;
                  Navigator.pop(dialogContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    editController.dispose();
                  });
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  final newText = editController.text.trim();
                  if (newText.isEmpty) return;

                  // 如果内容没有改动，直接关闭对话框
                  if (!hasChanged) {
                    isDisposed = true;
                    Navigator.pop(dialogContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      editController.dispose();
                    });
                    return;
                  }

                  // 标记 controller 已释放，避免后续使用
                  isDisposed = true;

                  // 先关闭对话框
                  Navigator.pop(dialogContext);

                  // 在下一帧释放 controller（确保对话框动画完成）
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    editController.dispose();
                  });

                  // 等待对话框动画完成
                  await Future.delayed(const Duration(milliseconds: 150));

                  // 检查 widget 是否仍然挂载
                  if (!mounted) return;

                  // 更新消息内容
                  setState(() {
                    _messages[index] = ChatMessage(
                      id: message.id,
                      role: message.role,
                      content: [MessageContent.text(text: newText)],
                      timestamp: message.timestamp,
                      modelId: message.modelId,
                    );
                    // 删除后续所有消息
                    if (index < _messages.length - 1) {
                      _messages.removeRange(index + 1, _messages.length);
                    }
                  });

                  _saveChatHistory();

                  // 如果这是用户消息，延迟重新发送（避免 setState 冲突）
                  if (message.role == MessageRole.user) {
                    scheduleMicrotask(() {
                      if (mounted) {
                        _resendMessage(_messages[index]);
                      }
                    });
                  }
                },
                child: Text(hasChanged ? '发送' : '确定'),
              ),
            ],
          );
        },
      ),
    );
    // 移除 whenComplete，改为在按钮回调中处理 dispose
  }

  /// 清空当前会话消息（保留会话条目）
  void _clearHistory() {
    if (_messages.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空当前会话的所有消息吗？会话仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _messages.clear();
                _createdRecipes.clear();
                _contextState = const ConversationContextState();
              });
              _saveChatHistory();
              Navigator.pop(context);
              AppSnackBar.show(
                context,
                '聊天记录已清空',
                bottomOffset: AppSnackBar.kChatBottomOffset,
              );
            },
            child: Text('确定', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  /// 新建会话
  Future<void> _createNewConversation() async {
    if (_blockConversationMutationWhileRunning()) return;
    // 当前会话为空时，不重复创建
    if (_messages.isEmpty &&
        _conversations.any((item) => item.id == _currentConversationId)) {
      return;
    }

    // 保存当前会话
    await _saveChatHistory();

    final conv = _conversationRepo.createNew();
    await _conversationRepo.save(conv);
    _currentConversationId = conv.id;
    await _conversationRepo.setActiveConversationId(conv.id);

    setState(() {
      _messages.clear();
      _createdRecipes.clear();
      _mcpCallHistory.clear();
      _contextState = const ConversationContextState();
    });

    _conversations = await _conversationRepo.getAll();
  }

  /// 切换会话
  Future<void> _switchConversation(String conversationId) async {
    if (_blockConversationMutationWhileRunning()) return;
    if (conversationId == _currentConversationId) return;

    // 保存当前会话
    await _saveChatHistory();

    _currentConversationId = conversationId;
    await _conversationRepo.setActiveConversationId(conversationId);

    setState(() {
      _mcpCallHistory.clear();
      _streamingText = '';
      _streamingReasoningText = '';
      _isStreaming = false;
      _isLoading = false;
      _aiStatusText = null;
    });

    await _loadConversationData(conversationId);
  }

  /// 删除会话
  Future<void> _deleteConversation(String conversationId) async {
    if (_blockConversationMutationWhileRunning()) return;
    await _conversationRepo.delete(conversationId);
    _conversations = await _conversationRepo.getAll();

    // 如果删除的是当前会话，切换到其他会话
    if (conversationId == _currentConversationId) {
      if (_conversations.isEmpty) {
        // 无会话了，创建新会话
        await _createNewConversation();
      } else {
        await _switchConversation(_conversations.first.id);
      }
    } else {
      setState(() {});
    }
  }

  /// 重命名会话
  Future<void> _renameConversation(String id, String newTitle) async {
    final conv = await _conversationRepo.getById(id);
    if (conv == null) return;
    await _conversationRepo.save(conv.copyWith(title: newTitle));
    _conversations = await _conversationRepo.getAll();
    setState(() {});
  }

  /// 显示 MCP 调试面板
  void _showMCPDebugPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.divider, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'MCP 工具调用记录',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_mcpCallHistory.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('清空'),
                        onPressed: () {
                          setState(() {
                            _mcpCallHistory.clear();
                          });
                          Navigator.pop(context);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // 工具调用列表
              Expanded(
                child: _mcpCallHistory.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无工具调用记录',
                          style: TextStyle(
                            color: AppColors.textDisabled,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _mcpCallHistory.length,
                        itemBuilder: (context, index) {
                          final call =
                              _mcpCallHistory[_mcpCallHistory.length -
                                  1 -
                                  index]; // 倒序显示
                          return _buildMCPCallCard(call);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建 MCP 工具调用卡片
  Widget _buildMCPCallCard(MCPToolCall call) {
    final hasError = call.error != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(
          hasError ? Icons.error : Icons.check_circle,
          color: hasError ? AppColors.error : AppColors.success,
        ),
        title: Text(
          call.toolName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          '${_formatCallTime(call.timestamp)} · ${call.duration.inMilliseconds}ms',
          style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 输入参数
                const Text(
                  '📥 输入参数',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _formatJson(call.input),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 输出结果
                Text(
                  hasError ? '❌ 错误信息' : '📤 输出结果',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasError
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    hasError ? call.error! : _formatJson(call.output),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: hasError ? AppColors.error : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化时间（HH:mm:ss）
  String _formatCallTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  /// 格式化 JSON
  String _formatJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (e) {
      return json.toString();
    }
  }
}

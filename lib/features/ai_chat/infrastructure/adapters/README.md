# AI 模型适配器说明

## 概述

本模块提供了对多个 AI 服务商的统一适配，支持 Claude、OpenAI 和 DeepSeek 三大平台。所有适配器都实现了统一的 `AIService` 接口，支持流式和非流式响应。

## 支持的服务商

### 1. Claude API (Anthropic)

**模型**: Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Sonnet 等

**特性**:
- ✅ 流式响应
- ✅ 图片输入（Vision）
- ✅ 工具调用（MCP）
- ✅ 自定义 API URL

**配置示例** (.env):
```env
CLAUDE_API_KEY=sk-ant-api03-...
```

**使用示例**:
```dart
final adapter = ClaudeAdapter(
  apiKey: 'sk-ant-api03-...',
  modelId: 'claude-3-5-sonnet-20241022',
  customApiUrl: 'https://your-proxy.com/v1', // 可选
);

// 流式响应
final stream = adapter.sendMessage(
  messages: [
    ChatMessage(
      id: '1',
      role: MessageRole.user,
      content: [MessageContent.text(text: '你好')],
      timestamp: DateTime.now(),
    ),
  ],
);

await for (final chunk in stream) {
  debugPrint(chunk); // 逐字输出
}

// 非流式响应
final response = await adapter.sendMessageSync(
  messages: [...],
);
```

### 2. OpenAI API

**模型**: GPT-4 Turbo, GPT-4 Vision, GPT-3.5 Turbo 等

**特性**:
- ✅ 流式响应
- ✅ 图片输入（Vision 模型）
- ✅ 工具调用（Function Calling）
- ✅ 自定义 API URL

**配置示例** (.env):
```env
OPENAI_API_KEY=sk-proj-...
```

**使用示例**:
```dart
final adapter = OpenAIAdapter(
  apiKey: 'sk-proj-...',
  modelId: 'gpt-4-turbo-preview',
  customApiUrl: 'https://api.openai-proxy.com/v1', // 可选
);

// 同 Claude 使用方式
```

### 3. DeepSeek API

**模型**: DeepSeek Chat, DeepSeek Coder 等

**特性**:
- ✅ 流式响应
- ✅ 工具调用
- ✅ 自定义 API URL
- ❌ 图片输入（暂不支持）

**配置示例** (.env):
```env
DEEPSEEK_API_KEY=sk-...
```

**使用示例**:
```dart
final adapter = DeepSeekAdapter(
  apiKey: 'sk-...',
  modelId: 'deepseek-chat',
  customApiUrl: 'https://your-proxy.com/v1', // 可选
);

// 同 Claude 使用方式
```

## AIService 接口

所有适配器都实现了 `AIService` 接口：

```dart
abstract class AIService {
  /// 发送消息（流式响应）
  Stream<String> sendMessage({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
  });

  /// 发送消息（非流式响应）
  Future<ChatMessage> sendMessageSync({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
  });

  /// 验证 API Key 是否有效
  Future<bool> validateApiKey();

  /// 获取模型信息
  Future<Map<String, dynamic>> getModelInfo();
}
```

## 使用 AIServiceFactory

推荐使用工厂类创建适配器实例：

```dart
// 创建模型配置
final config = AIModelConfig(
  id: 'my-claude',
  provider: AIProvider.claude,
  modelId: 'claude-3-5-sonnet-20241022',
  displayName: 'Claude 3.5 Sonnet',
  useBuiltinKey: false,
  customApiKey: 'your-api-key', // 实际应用中由模型管理页安全保存
);

// 通过工厂创建服务
final service = AIServiceFactory.create(config);

// 验证配置
final isValid = await AIServiceFactory.validateConfig(config);
```

## 使用 Riverpod Providers

推荐在应用中使用 Riverpod Providers：

```dart
// 获取当前 AI Service
final aiService = ref.watch(aiServiceProvider);

// 切换模型
ref.read(modelSwitcherProvider.notifier).switchTo(newConfig);

// 获取模型能力
final capabilities = ref.watch(modelCapabilitiesProvider);
if (capabilities.supportsImageInput) {
  // 可以发送图片
}

// 验证用户输入的 API Key
final isValid = await ref.read(
  validateModelConfigProvider(userConfig).future,
);
```

## 图片输入处理

对于支持图片的模型（Claude Vision, GPT-4 Vision）：

```dart
// 创建包含图片的消息
final message = ChatMessage(
  id: '1',
  role: MessageRole.user,
  content: [
    MessageContent.text(text: '这张图片里有什么？'),
    MessageContent.image(
      data: base64ImageData,
      mimeType: 'image/jpeg',
    ),
  ],
  timestamp: DateTime.now(),
);

final response = await service.sendMessageSync(
  messages: [message],
);
```

## 工具调用（MCP）

所有适配器都支持工具调用：

```dart
// 定义 MCP 工具
final tools = [
  {
    'name': 'search_recipes',
    'description': '搜索菜谱',
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '搜索关键词',
        },
      },
      'required': ['query'],
    },
  },
];

// 发送消息并启用工具
final stream = service.sendMessage(
  messages: [...],
  tools: tools,
);
```

## 错误处理

所有适配器都会抛出明确的异常：

```dart
try {
  final response = await service.sendMessageSync(messages: [...]);
} catch (e) {
  if (e.toString().contains('Invalid API key')) {
    // 处理 API Key 错误
  } else if (e.toString().contains('Rate limit exceeded')) {
    // 处理限流
  } else if (e.toString().contains('service unavailable')) {
    // 处理服务不可用
  } else {
    // 其他错误
  }
}
```

## 自定义 API URL

所有适配器都支持自定义 API URL，用于代理或非官方端点：

```dart
final adapter = ClaudeAdapter(
  apiKey: 'your-key',
  modelId: 'claude-3-5-sonnet-20241022',
  customApiUrl: 'https://your-proxy.com/v1',
);
```

**注意事项**:
1. 自定义 URL 应保持与官方 API 兼容的接口
2. URL 中不要包含尾部斜杠
3. 确保代理服务器支持流式响应

## 内置模型列表

使用 `AIServiceFactory.getBuiltinModels()` 获取所有内置模型配置：

```dart
final models = AIServiceFactory.getBuiltinModels();
for (final model in models) {
  debugPrint('${model.displayName}: ${model.description}');
}
```

**内置模型**:
- Claude 3.5 Sonnet (默认)
- Claude 3 Opus
- GPT-4 Turbo
- GPT-4 Vision
- GPT-3.5 Turbo
- DeepSeek Chat
- DeepSeek Coder

## API Key 管理

### 使用内置 Key (.env)

```env
CLAUDE_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-proj-...
DEEPSEEK_API_KEY=sk-...
```

### 使用用户自定义 Key

```dart
final config = AIModelConfig(
  id: 'custom-claude',
  provider: AIProvider.claude,
  modelId: 'claude-3-5-sonnet-20241022',
  displayName: 'My Claude',
  useBuiltinKey: false,
  customApiKey: 'user-provided-key',
);
```

## 最佳实践

1. **优先使用 Providers**: 通过 Riverpod Providers 管理 AI Service，便于状态管理
2. **验证配置**: 在保存用户自定义模型前，使用 `validateConfig` 验证
3. **错误处理**: 始终使用 try-catch 处理 API 调用错误
4. **流式响应**: 对于聊天场景，优先使用流式响应提升用户体验
5. **能力检测**: 使用 `capabilities` 字段检测模型能力，避免发送不支持的内容
6. **API Key 安全**:
   - 开发环境使用 .env 文件（不提交到 Git）
   - 生产环境使用用户自定义 Key
   - 不要在代码中硬编码 API Key

## 扩展新服务商

如需添加新的 AI 服务商，请：

1. 创建新的适配器类，实现 `AIService` 接口
2. 在 `AIProvider` 枚举中添加新服务商
3. 在 `AIServiceFactory` 中添加创建逻辑
4. 在 `getBuiltinModels()` 中添加默认模型配置
5. 更新本文档

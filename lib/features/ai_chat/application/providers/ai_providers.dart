import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/ai_model_config.dart';
import '../../domain/services/ai_service.dart';
import '../../infrastructure/services/ai_service_factory.dart';

part 'ai_providers.g.dart';

/// 当前选中的模型配置 Provider
///
/// App 不再提供内置模型；模型列表加载完成后由聊天页选择用户模型。
final selectedModelConfigProvider = StateProvider<AIModelConfig?>(
  (ref) => null,
);

/// 所有可用的模型配置列表 Provider
///
/// 用户模型存储在 Hive aiModelsBox 中，可增删改，应用升级不会覆盖。
@Riverpod(keepAlive: true)
class AvailableModels extends _$AvailableModels {
  @override
  Future<List<AIModelConfig>> build() async {
    return _loadAllModels();
  }

  /// 添加用户自定义模型
  ///
  /// 自动设置 isBuiltin=false 和时间戳
  /// 抛出 [ArgumentError] 如果尝试添加内置模型
  Future<void> addUserModel(AIModelConfig model) async {
    if (model.isBuiltin) {
      throw ArgumentError('Cannot add builtin model');
    }

    final preparedModel = _prepareUserModel(model);
    await _saveModelToHive(preparedModel);
    await _reloadModels();
  }

  /// 更新用户自定义模型
  ///
  /// 只能更新用户创建的模型，不能修改内置模型
  /// 抛出 [ArgumentError] 如果尝试修改内置模型
  Future<void> updateUserModel(AIModelConfig model) async {
    if (model.isBuiltin) {
      throw ArgumentError('Cannot update builtin model');
    }

    final preparedModel = _prepareUserModel(model);
    await _saveModelToHive(preparedModel);
    await _reloadModels();
  }

  /// 删除用户自定义模型
  ///
  /// 只能删除用户创建的模型，不能删除内置模型
  /// 抛出 [ArgumentError] 如果尝试删除内置模型
  Future<void> deleteUserModel(String modelId) async {
    final box = HiveService.getAIModelsBox();
    await box.delete(modelId);
    await _reloadModels();
  }

  /// 保存模型到 Hive
  ///
  /// 使用自定义序列化确保嵌套对象（如 capabilities）被正确转换为 Map
  /// 解决 Freezed 生成的 toJson() 不调用嵌套对象 toJson() 的问题
  Future<void> _saveModelToHive(AIModelConfig model) async {
    final box = HiveService.getAIModelsBox();
    // 手动序列化，确保嵌套对象正确转换
    final json = _serializeModelConfig(model);
    await box.put(model.id, json);
  }

  /// 手动序列化 AIModelConfig 为纯 Map
  ///
  /// Freezed 生成的 _$$AIModelConfigImplToJson 不会对嵌套对象调用 toJson()
  /// 导致 Hive 无法存储 _$ModelCapabilitiesImpl 类型
  /// 这里手动确保所有嵌套对象都被正确序列化为基本类型
  Map<String, dynamic> _serializeModelConfig(AIModelConfig model) {
    return {
      'id': model.id,
      'provider': model.provider.name,
      'modelId': model.modelId,
      'displayName': model.displayName,
      'description': model.description,
      'isEnabled': model.isEnabled,
      'useBuiltinKey': model.useBuiltinKey,
      'customApiUrl': model.customApiUrl,
      'customApiKey': model.customApiKey,
      'apiFormat': model.apiFormat.wireValue,
      'isDefault': model.isDefault,
      'isBuiltin': model.isBuiltin,
      // 手动序列化嵌套的 capabilities 对象
      'capabilities': {
        'supportsImageInput': model.capabilities.supportsImageInput,
        'supportsFileInput': model.capabilities.supportsFileInput,
        'supportsTools': model.capabilities.supportsTools,
        'enableStreaming': model.capabilities.enableStreaming,
        'enableThinking': model.capabilities.enableThinking,
        'thinkingBudgetTokens': model.capabilities.thinkingBudgetTokens,
        'maxTokens': model.capabilities.maxTokens,
        'contextWindow': model.capabilities.contextWindow,
      },
      'validationStatus': model.validationStatus.name,
      'lastValidated': model.lastValidated?.toIso8601String(),
      'validationError': model.validationError,
      'createdAt': model.createdAt?.toIso8601String(),
      'updatedAt': model.updatedAt?.toIso8601String(),
    };
  }

  /// 重新加载所有模型
  Future<void> _reloadModels() async {
    try {
      state = AsyncValue.data(await _loadAllModels());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// 加载用户自定义模型。
  Future<List<AIModelConfig>> _loadAllModels() async {
    try {
      return await _loadUserModelsFromHive();
    } catch (e) {
      debugPrint('⚠️ Failed to load user models from Hive: $e');
      return const [];
    }
  }

  /// 从 Hive 加载用户自定义模型
  Future<List<AIModelConfig>> _loadUserModelsFromHive() async {
    final box = HiveService.getAIModelsBox();
    final models = <AIModelConfig>[];

    for (final rawValue in box.values) {
      try {
        // 转换 Hive 的 Map 为 JSON Map
        final json = _convertToJsonMap(rawValue);
        final model = AIModelConfig.fromJson(json);

        // 确保用户模型的 isBuiltin 标记为 false
        models.add(model.copyWith(isBuiltin: false, useBuiltinKey: false));
      } catch (e) {
        // 忽略无法解析的模型，继续加载其他模型
        debugPrint('⚠️ Failed to parse model from Hive: $e');
        continue;
      }
    }

    return models;
  }

  /// 准备用户模型（设置元数据）
  AIModelConfig _prepareUserModel(AIModelConfig model) {
    final now = DateTime.now();
    return model.copyWith(
      isBuiltin: false,
      useBuiltinKey: false,
      createdAt: model.createdAt ?? now,
      updatedAt: now,
    );
  }

  /// 深度转换 Map 为 Map String, dynamic
  ///
  /// Hive 返回的 Map 是 LinkedMap，需要转换为标准 JSON Map
  Map<String, dynamic> _convertToJsonMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map) {
        result[stringKey] = _convertToJsonMap(value);
      } else if (value is List) {
        result[stringKey] = _convertToJsonList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  /// 深度转换 List
  List<dynamic> _convertToJsonList(List<dynamic> source) {
    return source.map((item) {
      if (item is Map) {
        return _convertToJsonMap(item);
      } else if (item is List) {
        return _convertToJsonList(item);
      } else {
        return item;
      }
    }).toList();
  }
}

/// AI Service Provider
///
/// 根据当前选中的模型配置创建 AI Service 实例
final aiServiceProvider = Provider<AIService?>((ref) {
  final config = ref.watch(selectedModelConfigProvider);
  if (config == null) return null;
  return AIServiceFactory.create(config);
});

/// 验证模型配置 Provider
///
/// 用于验证用户输入的 API Key 是否有效
final validateModelConfigProvider = FutureProvider.family<bool, AIModelConfig>((
  ref,
  config,
) async {
  return AIServiceFactory.validateConfig(config);
});

/// 模型能力 Provider
///
/// 获取当前模型的能力信息（是否支持图片、工具调用等）
final modelCapabilitiesProvider = Provider<ModelCapabilities>((ref) {
  final config = ref.watch(selectedModelConfigProvider);
  return config?.capabilities ?? const ModelCapabilities();
});

/// 切换模型 Provider
///
/// 用于在 UI 中切换不同的模型
class ModelSwitcher extends StateNotifier<AIModelConfig?> {
  ModelSwitcher(this.ref, AIModelConfig? initialModel) : super(initialModel);

  final Ref ref;

  /// 切换到指定模型
  void switchTo(AIModelConfig model) {
    if (!model.isEnabled) {
      throw Exception('Model is disabled: ${model.displayName}');
    }
    state = model;
  }

  /// 切换到下一个可用模型
  void switchToNext() {
    final availableModelsAsync = ref.read(availableModelsProvider);

    // 从 AsyncValue 中提取模型列表，失败时使用内置模型
    final availableModels = availableModelsAsync.maybeWhen(
      data: (models) => models,
      orElse: () => const <AIModelConfig>[],
    );

    final enabledModels = availableModels.where((m) => m.isEnabled).toList();

    if (enabledModels.isEmpty) {
      throw Exception('No enabled models available');
    }

    final currentIndex = enabledModels.indexWhere((m) => m.id == state?.id);
    final nextIndex = (currentIndex + 1) % enabledModels.length;
    state = enabledModels[nextIndex];
  }
}

/// 模型切换器 Provider
final modelSwitcherProvider =
    StateNotifierProvider<ModelSwitcher, AIModelConfig?>((ref) {
      final initialModel = ref.watch(selectedModelConfigProvider);
      return ModelSwitcher(ref, initialModel);
    });

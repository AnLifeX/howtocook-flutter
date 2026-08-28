// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$availableModelsHash() => r'4b70bfd8aff92ce730fe1fbea4cb096bc9b218b9';

/// 所有可用的模型配置列表 Provider
///
/// 用户模型存储在 Hive aiModelsBox 中，可增删改，应用升级不会覆盖。
///
/// Copied from [AvailableModels].
@ProviderFor(AvailableModels)
final availableModelsProvider =
    AsyncNotifierProvider<AvailableModels, List<AIModelConfig>>.internal(
  AvailableModels.new,
  name: r'availableModelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$availableModelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$AvailableModels = AsyncNotifier<List<AIModelConfig>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

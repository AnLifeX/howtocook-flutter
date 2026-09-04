import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../ai_chat/application/providers/ai_providers.dart';
import '../../../ai_chat/domain/entities/ai_model_config.dart';
import '../../../ai_chat/infrastructure/services/model_capability_database.dart';
import '../../../ai_chat/infrastructure/services/model_validator.dart';

/// 模型管理页面
///
/// 功能：
/// - 展示所有模型（内置 + 用户自定义）
/// - 内置模型不可删除
/// - 添加/编辑/删除用户模型
class ModelManagementScreen extends ConsumerStatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  ConsumerState<ModelManagementScreen> createState() =>
      _ModelManagementScreenState();
}

class _ModelManagementScreenState extends ConsumerState<ModelManagementScreen> {
  String? _deletingModelId;

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(availableModelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理', style: AppTextStyles.appBarTitle),
        actions: [
          IconButton(
            onPressed: () => _openModelForm(),
            icon: const Icon(Icons.add),
            tooltip: '添加模型',
          ),
        ],
      ),
      body: modelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _buildError(error),
        data: (models) => _buildModelSections(models),
      ),
    );
  }

  /// 构建错误页面
  Widget _buildError(Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.error),
          const SizedBox(height: 12),
          Text(
            '加载模型失败',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          IconButton(
            onPressed: () => ref.invalidate(availableModelsProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
          ),
        ],
      ),
    );
  }

  /// 构建模型列表（分组展示）
  Widget _buildModelSections(List<AIModelConfig> models) {
    final userModels = models.where((m) => !m.isBuiltin).toList();

    return RefreshIndicator(
      onRefresh: _refreshModels,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSectionHeader('我的模型', Icons.person_outline),
          if (userModels.isEmpty) _buildEmptyHint(),
          ...userModels.map(_buildModelCard),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '应用不提供内置模型。API Key 仅保存在本机，应用升级不会覆盖这里添加的模型。模型输出质量取决于所选服务商。',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title, style: AppTextStyles.h5),
        ],
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyHint() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '还没有模型，点击右上角 + 添加自己的模型和 API Key。',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// 构建模型卡片
  Widget _buildModelCard(AIModelConfig model) {
    final isDeleting = _deletingModelId == model.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.displayName, style: AppTextStyles.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        _providerLabel(model.provider),
                        style: AppTextStyles.cardSubtitle,
                      ),
                    ],
                  ),
                ),
                if (model.isBuiltin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '内置',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '编辑模型',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: isDeleting
                            ? null
                            : () => _openModelForm(model: model),
                      ),
                      isDeleting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: '删除模型',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.error,
                              ),
                              onPressed: () => _confirmDelete(model),
                            ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildInfoTag(Icons.tag, 'ID: ${model.modelId}'),
                _buildInfoTag(
                  Icons.swap_horiz,
                  _apiFormatLabel(model.apiFormat),
                ),
                _buildInfoTag(
                  Icons.key,
                  model.useBuiltinKey ? '内置 Key' : '自定义 Key',
                ),
              ],
            ),
            if ((model.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                model.description!.trim(),
                style: AppTextStyles.cardSubtitle,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildCapabilityTag(
                  '图片输入',
                  model.capabilities.supportsImageInput,
                ),
                _buildCapabilityTag('工具', model.capabilities.supportsTools),
                _buildCapabilityTag('流式输出', model.capabilities.enableStreaming),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建信息标签
  Widget _buildInfoTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.label.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  /// 构建能力标签
  Widget _buildCapabilityTag(String label, bool enabled) {
    final color = enabled ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: color)),
        ],
      ),
    );
  }

  /// 刷新模型列表
  Future<void> _refreshModels() async {
    ref.invalidate(availableModelsProvider);
    // 等待数据重新加载完成
    await ref.read(availableModelsProvider.future);
  }

  /// 打开模型表单
  Future<void> _openModelForm({AIModelConfig? model}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ModelFormSheet(initialModel: model),
    );

    if (result == true && mounted) {
      AppSnackBar.show(context, model == null ? '模型已添加' : '模型已更新');
    }
  }

  /// 确认删除模型
  Future<void> _confirmDelete(AIModelConfig model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除「${model.displayName}」吗？该操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingModelId = model.id);
    try {
      await ref
          .read(availableModelsProvider.notifier)
          .deleteUserModel(model.id);
      if (mounted) {
        AppSnackBar.show(context, '已删除 ${model.displayName}');
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(context, '删除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _deletingModelId = null);
      }
    }
  }
}

/// 模型表单组件（Bottom Sheet）
class ModelFormSheet extends ConsumerStatefulWidget {
  const ModelFormSheet({super.key, this.initialModel});

  final AIModelConfig? initialModel;

  @override
  ConsumerState<ModelFormSheet> createState() => _ModelFormSheetState();
}

class _ModelFormSheetState extends ConsumerState<ModelFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _maxTokensController;
  late final TextEditingController _contextWindowController;

  late AIProvider _provider;
  late AIAPIFormat _apiFormat;
  late bool _supportsImageInput;
  late bool _supportsFileInput;
  late bool _supportsTools;
  late bool _enableStreaming;
  late bool _enableThinking;
  late TextEditingController _thinkingBudgetController;

  // 模型识别状态
  bool _isKnownModel = false;
  bool _capabilitiesManuallyEdited = false;
  bool _isApplyingCapabilities = false;
  String? _lastCapabilityKey;

  // 保存和验证状态
  bool _isSaving = false;
  bool _isValidatingConfig = false;
  ModelValidationStatus _validationStatus = ModelValidationStatus.pending;
  DateTime? _lastValidatedAt;
  String? _validationErrorMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialModel;
    _provider = initial?.provider ?? AIProvider.deepseek; // 默认选择 DeepSeek
    _apiFormat = initial?.apiFormat ?? AIAPIFormat.auto;
    _displayNameController = TextEditingController(
      text: initial?.displayName ?? '',
    );
    _modelIdController = TextEditingController(text: initial?.modelId ?? '');
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _apiUrlController = TextEditingController(
      text: initial?.customApiUrl ?? _defaultApiUrl(_provider),
    );
    _apiKeyController = TextEditingController(
      text: initial?.customApiKey ?? '',
    );
    _maxTokensController = TextEditingController(
      text: '${initial?.capabilities.maxTokens ?? 4096}',
    );
    _contextWindowController = TextEditingController(
      text: '${initial?.capabilities.contextWindow ?? 128000}',
    );

    _supportsImageInput = initial?.capabilities.supportsImageInput ?? false;
    _supportsFileInput = initial?.capabilities.supportsFileInput ?? false;
    _supportsTools = initial?.capabilities.supportsTools ?? true;
    _enableStreaming = initial?.capabilities.enableStreaming ?? true;
    _enableThinking = initial?.capabilities.enableThinking ?? false;
    _thinkingBudgetController = TextEditingController(
      text: '${initial?.capabilities.thinkingBudgetTokens ?? 10000}',
    );

    // 初始化验证状态
    _validationStatus =
        initial?.validationStatus ?? ModelValidationStatus.pending;
    _lastValidatedAt = initial?.lastValidated;
    _validationErrorMessage = initial?.validationError;

    // 检查是否为已知模型
    if (initial != null && initial.modelId.isNotEmpty) {
      _isKnownModel = ModelCapabilityDatabase.isKnownModel(
        initial.provider,
        initial.modelId,
      );
      _lastCapabilityKey =
          '${initial.provider.name}:${initial.modelId.toLowerCase()}';
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _modelIdController.dispose();
    _descriptionController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    _contextWindowController.dispose();
    _thinkingBudgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.initialModel == null ? '添加模型' : '编辑模型';
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textDisabled,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(title, style: AppTextStyles.h5),
              const SizedBox(height: 16),
              DropdownButtonFormField<AIProvider>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: '服务商'),
                items: AIProvider.values
                    .map(
                      (provider) => DropdownMenuItem(
                        value: provider,
                        child: Text(_providerLabel(provider)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _provider = value;
                    if (!_availableAPIFormats(value).contains(_apiFormat)) {
                      _apiFormat = AIAPIFormat.auto;
                    }
                    _apiUrlController.text = _defaultApiUrl(value, _apiFormat);
                  });
                  _invalidateValidation();
                  _handleModelIdentifierChanged(force: true);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AIAPIFormat>(
                initialValue: _apiFormat,
                decoration: const InputDecoration(labelText: 'API 格式'),
                items: _availableAPIFormats(_provider)
                    .map(
                      (format) => DropdownMenuItem(
                        value: format,
                        child: Text(_apiFormatLabel(format)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _apiFormat = value;
                    _apiUrlController.text = _defaultApiUrl(_provider, value);
                  });
                  _invalidateValidation();
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _apiFormatHint(_provider, _apiFormat),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: '显示名称'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入显示名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modelIdController,
                decoration: const InputDecoration(labelText: '模型 ID'),
                onChanged: (_) {
                  _invalidateValidation();
                  _handleModelIdentifierChanged();
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入模型 ID';
                  }
                  return null;
                },
              ),
              // 模型匹配状态提示
              if (_modelIdController.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        _isKnownModel ? Icons.check_circle : Icons.info_outline,
                        size: 16,
                        color: _isKnownModel
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _isKnownModel ? '已匹配到模型能力并自动填充' : '未找到匹配的模型，使用默认能力',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: _isKnownModel
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '描述（可选）'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiUrlController,
                decoration: const InputDecoration(labelText: 'API URL'),
                onChanged: (_) => _invalidateValidation(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(labelText: 'API Key'),
                obscureText: true,
                onChanged: (_) => _invalidateValidation(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入 API Key';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 验证配置按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving || _isValidatingConfig
                          ? null
                          : _validateModelConfig,
                      icon: _isValidatingConfig
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: Text(_isValidatingConfig ? '验证中...' : '验证配置'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildValidationStatus(),
              const Divider(height: 32),
              Text('模型能力', style: AppTextStyles.h6),
              SwitchListTile.adaptive(
                value: _supportsImageInput,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() {
                  _supportsImageInput = value;
                  _markCapabilitiesEdited();
                }),
                title: Text('支持图片输入', style: AppTextStyles.bodyMedium),
              ),
              SwitchListTile.adaptive(
                value: _supportsFileInput,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() {
                  _supportsFileInput = value;
                  _markCapabilitiesEdited();
                }),
                title: Text('支持文件输入', style: AppTextStyles.bodyMedium),
              ),
              SwitchListTile.adaptive(
                value: _supportsTools,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() {
                  _supportsTools = value;
                  _markCapabilitiesEdited();
                }),
                title: Text('支持应用工具调用', style: AppTextStyles.bodyMedium),
              ),
              SwitchListTile.adaptive(
                value: _enableStreaming,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() {
                  _enableStreaming = value;
                  _markCapabilitiesEdited();
                }),
                title: Text('启用流式输出', style: AppTextStyles.bodyMedium),
                subtitle: Text(
                  '流式输出可实时显示AI回复，关闭后将等待完整回复',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // 思考链开关（Claude 和 DeepSeek 支持）
              if (_provider == AIProvider.claude ||
                  _provider == AIProvider.deepseek)
                SwitchListTile.adaptive(
                  value: _enableThinking,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setState(() {
                    _enableThinking = value;
                    _markCapabilitiesEdited();
                  }),
                  title: Text('启用思考链', style: AppTextStyles.bodyMedium),
                  subtitle: Text(
                    _provider == AIProvider.deepseek
                        ? '让 AI 展示推理过程（Deep Thinking）'
                        : '让 AI 展示推理过程（Extended Thinking）',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              // 思考预算（仅 Claude 启用思考链时显示）
              if (_provider == AIProvider.claude && _enableThinking)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    controller: _thinkingBudgetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '思考预算 Tokens',
                      helperText: '推理过程的 token 预算（建议 5000-20000）',
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _markCapabilitiesEdited();
                    },
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _maxTokensController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '最大 Tokens'),
                      onChanged: (_) {
                        setState(() {});
                        _markCapabilitiesEdited();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _contextWindowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '上下文窗口'),
                      onChanged: (_) {
                        setState(() {});
                        _markCapabilitiesEdited();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.surface,
                              ),
                            )
                          : Text(
                              widget.initialModel == null ? '添加' : '保存',
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.surface,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 保存模型
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(availableModelsProvider.notifier);
    final config = _buildConfig();

    try {
      if (widget.initialModel == null) {
        await notifier.addUserModel(config);
      } else {
        await notifier.updateUserModel(config);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(context, '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 构建模型配置
  AIModelConfig _buildConfig() {
    final existing = widget.initialModel;
    final now = DateTime.now();
    final description = _descriptionController.text.trim();
    final apiUrl = _apiUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    // 解析数字字段
    final maxTokens = int.tryParse(_maxTokensController.text.trim());
    final contextWindow = int.tryParse(_contextWindowController.text.trim());

    return AIModelConfig(
      id: existing?.id ?? const Uuid().v4(),
      provider: _provider,
      modelId: _modelIdController.text.trim(),
      displayName: _displayNameController.text.trim(),
      description: description.isEmpty ? null : description,
      isEnabled: existing?.isEnabled ?? true,
      useBuiltinKey: false,
      customApiUrl: apiUrl.isEmpty ? null : apiUrl,
      customApiKey: apiKey.isEmpty ? null : apiKey,
      apiFormat: _apiFormat,
      isDefault: existing?.isDefault ?? false,
      isBuiltin: false,
      capabilities: ModelCapabilities(
        supportsImageInput: _supportsImageInput,
        supportsFileInput: _supportsFileInput,
        supportsTools: _supportsTools,
        enableStreaming: _enableStreaming,
        enableThinking: _enableThinking,
        thinkingBudgetTokens:
            int.tryParse(_thinkingBudgetController.text) ?? 10000,
        maxTokens: maxTokens ?? 4096,
        contextWindow: contextWindow ?? 128000,
      ),
      validationStatus: _validationStatus,
      lastValidated: _lastValidatedAt,
      validationError: _validationErrorMessage,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // ==================== 辅助方法 ====================

  /// 处理模型 ID 或服务商变化时的能力自动填充
  void _handleModelIdentifierChanged({bool force = false}) {
    final trimmed = _modelIdController.text.trim();
    if (trimmed.isEmpty) {
      // 始终调用 setState 以确保提示区域刷新
      setState(() {
        _isKnownModel = false;
        _lastCapabilityKey = null;
      });
      return;
    }

    // 编辑模式下，首次进入时不自动覆盖
    if (!force &&
        widget.initialModel != null &&
        trimmed == widget.initialModel!.modelId &&
        _provider == widget.initialModel!.provider) {
      return;
    }

    final normalizedKey = '${_provider.name}:${trimmed.toLowerCase()}';
    if (!force && normalizedKey == _lastCapabilityKey) {
      return;
    }

    final isKnown = ModelCapabilityDatabase.isKnownModel(_provider, trimmed);
    final capabilities = ModelCapabilityDatabase.getCapabilities(
      _provider,
      trimmed,
    );
    final hasModelChanged = normalizedKey != _lastCapabilityKey;

    setState(() {
      _lastCapabilityKey = normalizedKey;
      _isKnownModel = isKnown;
      // 只在模型变化且用户未手动编辑时自动填充
      if (isKnown &&
          (force || hasModelChanged || !_capabilitiesManuallyEdited)) {
        _applyCapabilities(capabilities);
        _capabilitiesManuallyEdited = false;
      }
    });
  }

  /// 应用能力配置
  void _applyCapabilities(ModelCapabilities capabilities) {
    _isApplyingCapabilities = true;
    _supportsImageInput = capabilities.supportsImageInput;
    _supportsFileInput = capabilities.supportsFileInput;
    _supportsTools = capabilities.supportsTools;
    _enableStreaming = capabilities.enableStreaming;
    _enableThinking = capabilities.enableThinking;
    _thinkingBudgetController.text = capabilities.thinkingBudgetTokens
        .toString();
    _maxTokensController.text = capabilities.maxTokens.toString();
    _contextWindowController.text = capabilities.contextWindow.toString();
    _isApplyingCapabilities = false;
  }

  /// 标记用户手动编辑了能力
  void _markCapabilitiesEdited() {
    if (_isApplyingCapabilities) return;
    _capabilitiesManuallyEdited = true;
  }

  /// 使验证状态失效
  void _invalidateValidation() {
    if (_validationStatus == ModelValidationStatus.pending &&
        _validationErrorMessage == null &&
        _lastValidatedAt == null) {
      return;
    }
    setState(() {
      _validationStatus = ModelValidationStatus.pending;
      _validationErrorMessage = null;
      _lastValidatedAt = null;
    });
  }

  /// 验证模型配置
  Future<void> _validateModelConfig() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final config = _buildConfig();

    // 快速验证
    final (isQuickValid, quickMessage) = ModelValidator.quickValidate(config);
    if (!isQuickValid) {
      if (quickMessage != null && mounted) {
        AppSnackBar.show(context, quickMessage);
      }
      return;
    }

    setState(() {
      _isValidatingConfig = true;
      _validationStatus = ModelValidationStatus.validating;
      _validationErrorMessage = null;
    });

    final result = await ModelValidator.validate(config);

    if (!mounted) return;

    setState(() {
      _isValidatingConfig = false;
      if (result.isValid) {
        _validationStatus = ModelValidationStatus.valid;
        _lastValidatedAt = DateTime.now();
        _validationErrorMessage = null;
        // 验证成功后自动更新检测到的能力
        if (result.detectedCapabilities != null) {
          _applyCapabilities(result.detectedCapabilities!);
          _capabilitiesManuallyEdited = false;
        }
      } else {
        _validationStatus = ModelValidationStatus.invalid;
        _lastValidatedAt = DateTime.now();
        _validationErrorMessage = result.errorMessage ?? '验证失败';
      }
    });
  }

  /// 构建验证状态显示
  Widget _buildValidationStatus() {
    if (_validationStatus == ModelValidationStatus.pending &&
        _validationErrorMessage == null &&
        _lastValidatedAt == null) {
      return const SizedBox.shrink();
    }

    late final Color color;
    late final IconData icon;
    var message = '';

    switch (_validationStatus) {
      case ModelValidationStatus.valid:
        color = AppColors.success;
        icon = Icons.verified_outlined;
        message = '验证成功';
        break;
      case ModelValidationStatus.invalid:
        color = AppColors.error;
        icon = Icons.error_outline;
        message = _validationErrorMessage ?? '验证失败';
        break;
      case ModelValidationStatus.validating:
        color = AppColors.primary;
        icon = Icons.hourglass_top;
        message = '正在验证...';
        break;
      case ModelValidationStatus.pending:
        color = AppColors.textSecondary;
        icon = Icons.info_outline;
        message = _validationErrorMessage ?? '尚未验证';
        break;
    }

    // 添加验证时间
    if (_lastValidatedAt != null &&
        (_validationStatus == ModelValidationStatus.valid ||
            _validationStatus == ModelValidationStatus.invalid)) {
      message = '$message · ${_formatTimestamp(_lastValidatedAt!)}';
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  /// 格式化时间戳
  String _formatTimestamp(DateTime time) {
    final local = time.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $clock';
  }
}

/// 获取服务商显示名称
String _providerLabel(AIProvider provider) {
  switch (provider) {
    case AIProvider.claude:
      return 'Claude';
    case AIProvider.openai:
      return 'OpenAI';
    case AIProvider.deepseek:
      return 'DeepSeek';
  }
}

/// 获取服务商默认 API URL
String _defaultApiUrl(
  AIProvider provider, [
  AIAPIFormat format = AIAPIFormat.auto,
]) {
  if (provider == AIProvider.deepseek) {
    if (format == AIAPIFormat.responses) {
      return 'https://api.deepseek.com';
    }
    if (format == AIAPIFormat.anthropicMessages) {
      return 'https://api.deepseek.com/anthropic';
    }
  }
  switch (provider) {
    case AIProvider.claude:
      return 'https://api.anthropic.com/v1';
    case AIProvider.openai:
      return 'https://api.openai.com/v1';
    case AIProvider.deepseek:
      return 'https://api.deepseek.com/v1';
  }
}

String _apiFormatLabel(AIAPIFormat format) {
  switch (format) {
    case AIAPIFormat.auto:
      return '自动（推荐）';
    case AIAPIFormat.chatCompletions:
      return 'Chat Completions';
    case AIAPIFormat.responses:
      return 'Responses';
    case AIAPIFormat.anthropicMessages:
      return 'Anthropic Messages';
  }
}

String _apiFormatHint(AIProvider provider, AIAPIFormat format) {
  if (format == AIAPIFormat.auto) {
    return '按服务商和 API URL 自动选择；已有模型会继续使用原来的兼容格式。';
  }
  if (provider == AIProvider.deepseek && format == AIAPIFormat.responses) {
    return 'DeepSeek 官方 Responses 当前仅支持 deepseek-v4-flash。';
  }
  if (provider == AIProvider.deepseek &&
      format == AIAPIFormat.anthropicMessages) {
    return '使用 DeepSeek 的 Anthropic 兼容接口（/anthropic/messages）。';
  }
  return '请求体、流式事件和工具调用都将按此协议解析。';
}

List<AIAPIFormat> _availableAPIFormats(AIProvider provider) {
  switch (provider) {
    case AIProvider.claude:
      return const [AIAPIFormat.auto, AIAPIFormat.anthropicMessages];
    case AIProvider.openai:
      return const [
        AIAPIFormat.auto,
        AIAPIFormat.chatCompletions,
        AIAPIFormat.responses,
      ];
    case AIProvider.deepseek:
      return AIAPIFormat.values;
  }
}

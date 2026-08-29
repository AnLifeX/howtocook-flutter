import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../domain/entities/recipe.dart';
import '../../application/providers/recipe_providers.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/cached_recipe_image.dart';
import '../../../../core/services/cover_manifest_service.dart';
import '../../../../core/services/recipe_image_policy.dart';

/// 菜谱编辑页面
///
/// 支持编辑现有菜谱的所有字段
class RecipeEditScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const RecipeEditScreen({super.key, required this.recipeId});

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();

  // 表单控制器
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _caloriesController;

  // 数据
  Recipe? _originalRecipe;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  // 编辑状态
  String _selectedCategory = '';
  int _selectedDifficulty = 1;
  List<String> _requirementTexts = [];
  List<String> _ingredientTexts = []; // 简化存储，保存时转换
  List<String> _calculationNotes = [];
  List<String> _stepDescriptions = []; // 简化存储，保存时转换
  List<String> _tools = [];
  String? _tips;
  List<String> _warnings = [];
  String? _coverImage;
  List<String> _images = [];

  // 保存原始数据副本，用于重置
  String _originalName = '';
  String _originalCategory = '';
  int _originalDifficulty = 1;
  String _originalDescription = '';
  String _originalCalories = '';
  List<String> _originalRequirementTexts = [];
  List<String> _originalIngredientTexts = [];
  List<String> _originalCalculationNotes = [];
  List<String> _originalStepDescriptions = [];
  List<String> _originalTools = [];
  String? _originalTips;
  List<String> _originalWarnings = [];
  String? _originalCoverImage;
  List<String> _originalImages = [];
  Future<String?>? _aiCoverFuture;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _caloriesController = TextEditingController();
    _loadRecipe();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  /// 加载菜谱数据
  Future<void> _loadRecipe() async {
    try {
      final recipe = await ref.read(recipeByIdProvider(widget.recipeId).future);
      if (recipe != null && mounted) {
        setState(() {
          _originalRecipe = recipe;
          _nameController.text = recipe.name;
          _descriptionController.text = recipe.description ?? '';
          _caloriesController.text =
              recipe.estimatedCaloriesKcal?.toString() ?? '';
          _selectedCategory = recipe.category;
          _selectedDifficulty = recipe.difficulty;
          _requirementTexts = recipe.requirements
              .where((item) => item.kind != 'tool')
              .map((item) => item.text)
              .toList();
          _ingredientTexts = recipe.ingredients.map((i) => i.text).toList();
          _calculationNotes = List.from(recipe.calculationNotes);
          _stepDescriptions = recipe.steps.map((s) => s.description).toList();
          _tools = {
            ...recipe.tools,
            ...recipe.requirements
                .where((item) => item.kind == 'tool')
                .map((item) => item.text),
          }.toList();
          _tips = recipe.tips;
          _warnings = List.from(recipe.warnings);
          final imageParts = splitRecipeImages(recipe);
          _coverImage = imageParts.customCover;
          _images = List.from(imageParts.details);
          _aiCoverFuture = CoverManifestService().resolveAiCoverPath(
            recipeId: recipe.id,
            legacyIds: recipe.legacyIds,
            recipeName: recipe.name,
            category: recipe.category,
          );

          // 保存原始数据副本，用于重置
          _originalName = recipe.name;
          _originalDescription = recipe.description ?? '';
          _originalCalories = recipe.estimatedCaloriesKcal?.toString() ?? '';
          _originalCategory = recipe.category;
          _originalDifficulty = recipe.difficulty;
          _originalRequirementTexts = List.from(_requirementTexts);
          _originalIngredientTexts = recipe.ingredients
              .map((i) => i.text)
              .toList();
          _originalCalculationNotes = List.from(recipe.calculationNotes);
          _originalStepDescriptions = recipe.steps
              .map((s) => s.description)
              .toList();
          _originalTools = List.from(recipe.tools);
          _originalTips = recipe.tips;
          _originalWarnings = List.from(recipe.warnings);
          _originalCoverImage = _coverImage;
          _originalImages = List.from(_images);

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackBar.show(context, '加载失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑菜谱')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_originalRecipe == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑菜谱')),
        body: const Center(child: Text('菜谱不存在')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑菜谱'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _resetToOriginal,
            icon: const Icon(Icons.restart_alt),
            tooltip: '重置',
          ),
          IconButton(
            onPressed: _isSaving ? null : _saveRecipe,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: '保存',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBasicInfoSection(),
            const SizedBox(height: 24),
            _buildRequirementsSection(),
            const SizedBox(height: 24),
            _buildToolsSection(),
            const SizedBox(height: 24),
            _buildIngredientsSection(),
            const SizedBox(height: 24),
            _buildCalculationNotesSection(),
            const SizedBox(height: 24),
            _buildStepsSection(),
            const SizedBox(height: 24),
            _buildTipsSection(),
            const SizedBox(height: 24),
            _buildWarningsSection(),
            const SizedBox(height: 24),
            _buildCoverImageSection(),
            const SizedBox(height: 24),
            _buildDetailImagesSection(),
            const SizedBox(height: 80), // 底部留白
          ],
        ),
      ),
    );
  }

  /// 基本信息部分
  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基本信息', style: AppTextStyles.h3),
            const SizedBox(height: 16),

            // 菜谱名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '菜谱名称',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入菜谱名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '菜谱简介（可选）',
                hintText: '简要介绍风味、营养、难度和预计耗时',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '估算总热量（kcal，可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            ref
                .watch(categoryNameMapProvider)
                .when(
                  data: (categoryMap) => DropdownButtonFormField<String>(
                    initialValue: categoryMap.containsKey(_selectedCategory)
                        ? _selectedCategory
                        : null,
                    decoration: const InputDecoration(
                      labelText: '分类',
                      border: OutlineInputBorder(),
                    ),
                    items: categoryMap.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedCategory = value);
                      }
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('分类加载失败'),
                ),
            const SizedBox(height: 16),

            // 难度选择 - 五颗星
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('难度', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedDifficulty = starValue);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          starValue <= _selectedDifficulty
                              ? Icons.star
                              : Icons.star_border,
                          color: starValue <= _selectedDifficulty
                              ? AppColors.warning
                              : AppColors.textDisabled,
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementsSection() {
    return _buildListSection(
      title: '必备原料',
      items: _requirementTexts,
      onAdd: () => _addListItem(_requirementTexts, '新必备原料'),
      onEdit: (index) => _editListItem(_requirementTexts, index, '编辑必备原料'),
      onDelete: (index) => _deleteListItem(_requirementTexts, index),
      onClear: () => _confirmAndClearList(_requirementTexts, '必备原料'),
    );
  }

  /// 食材部分
  Widget _buildIngredientsSection() {
    return _buildListSection(
      title: '用量与计算（食材用量）',
      items: _ingredientTexts,
      onAdd: () => _addListItem(_ingredientTexts, '新食材'),
      onEdit: (index) => _editListItem(_ingredientTexts, index, '编辑食材'),
      onDelete: (index) => _deleteListItem(_ingredientTexts, index),
      onClear: () => _confirmAndClearList(_ingredientTexts, '食材'),
      validator: (value) => value.trim().isEmpty ? '食材不能为空' : null,
    );
  }

  Widget _buildCalculationNotesSection() {
    return _buildListSection(
      title: '用量计算说明（可选）',
      items: _calculationNotes,
      onAdd: () => _addListItem(_calculationNotes, '例如：每人每顿 200 g'),
      onEdit: (index) => _editListItem(_calculationNotes, index, '编辑计算说明'),
      onDelete: (index) => _deleteListItem(_calculationNotes, index),
      onClear: () => _confirmAndClearList(_calculationNotes, '用量计算说明'),
    );
  }

  /// 步骤部分 - 支持拖拽排序
  Widget _buildStepsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('操作', style: AppTextStyles.h3),
                const Spacer(),
                if (_stepDescriptions.isNotEmpty)
                  IconButton(
                    onPressed: () =>
                        _confirmAndClearList(_stepDescriptions, '操作'),
                    icon: const Icon(Icons.clear_all, size: 20),
                    color: AppColors.error,
                    tooltip: '清空',
                  ),
                IconButton(
                  onPressed: () => _addListItem(_stepDescriptions, '新步骤'),
                  icon: const Icon(Icons.add),
                  tooltip: '添加步骤',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_stepDescriptions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无操作内容',
                    style: TextStyle(color: AppColors.textDisabled),
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                buildDefaultDragHandles: false, // 禁用默认的拖拽手柄
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _stepDescriptions.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = _stepDescriptions.removeAt(oldIndex);
                    _stepDescriptions.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final step = _stepDescriptions[index];
                  return Stack(
                    key: ValueKey('step_$index'),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 12, 72, 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(
                                Icons.drag_handle,
                                color: AppColors.textDisabled,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(step)),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () => _editListItem(
                                _stepDescriptions,
                                index,
                                '编辑步骤',
                              ),
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              color: AppColors.error,
                              onPressed: () =>
                                  _deleteListItem(_stepDescriptions, index),
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 工具部分
  Widget _buildToolsSection() {
    return _buildListSection(
      title: '必备工具（可选）',
      items: _tools,
      onAdd: () => _addListItem(_tools, '新工具'),
      onEdit: (index) => _editListItem(_tools, index, '编辑工具'),
      onDelete: (index) => _deleteListItem(_tools, index),
      onClear: () => _confirmAndClearList(_tools, '工具'),
    );
  }

  /// 小贴士部分
  Widget _buildTipsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('小贴士（可选）', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _tips,
              decoration: const InputDecoration(
                hintText: '输入烹饪小贴士',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (value) => _tips = value,
            ),
          ],
        ),
      ),
    );
  }

  /// 注意事项部分
  Widget _buildWarningsSection() {
    return _buildListSection(
      title: '注意事项（可选）',
      items: _warnings,
      onAdd: () => _addListItem(_warnings, '新注意事项'),
      onEdit: (index) => _editListItem(_warnings, index, '编辑注意事项'),
      onDelete: (index) => _deleteListItem(_warnings, index),
      onClear: () => _confirmAndClearList(_warnings, '注意事项'),
    );
  }

  /// 构建图片预览组件
  Widget _buildImagePreview(
    String imagePath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    final isBase64 = imagePath.startsWith('data:image/');
    final isUrl = imagePath.startsWith('http');
    final isAsset = imagePath.startsWith('assets/');
    final isLocalFile = !isUrl && !isAsset && !isBase64;

    if (isBase64) {
      try {
        final base64String = imagePath.split(',')[1];
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) =>
              const RecipePlaceholderImage.loadFailed(compact: true),
        );
      } catch (_) {
        return const RecipePlaceholderImage.loadFailed(compact: true);
      }
    } else if (isLocalFile && !kIsWeb && File(imagePath).existsSync()) {
      return Image.file(
        File(imagePath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            const RecipePlaceholderImage.loadFailed(compact: true),
      );
    } else if (isUrl) {
      return Image.network(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            const RecipePlaceholderImage.loadFailed(compact: true),
      );
    } else if (isAsset) {
      return Image.asset(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            const RecipePlaceholderImage.loadFailed(compact: true),
      );
    }
    return const RecipePlaceholderImage.loadFailed(compact: true);
  }

  /// 封面图片部分
  Widget _buildCoverImageSection() {
    return FutureBuilder<String?>(
      future: _aiCoverFuture,
      builder: (context, snapshot) {
        final aiCover = snapshot.data;
        final coverImage = _coverImage ?? aiCover;
        final isAiCover = _coverImage == null && aiCover != null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('封面图片', style: AppTextStyles.h3),
                    if (isAiCover) ...[
                      const SizedBox(width: 8),
                      const Chip(
                        avatar: Icon(Icons.auto_awesome, size: 16),
                        label: Text('AI 封面'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (coverImage != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 200,
                          child: _buildImagePreview(coverImage, height: 200),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _imageActionButton(
                              icon: Icons.photo_library,
                              tooltip: '从相册替换',
                              onPressed: () => _pickLocalImage(isCover: true),
                            ),
                            const SizedBox(width: 8),
                            _imageActionButton(
                              icon: Icons.link,
                              tooltip: '用URL替换',
                              onPressed: () => _addImageUrl(isCover: true),
                            ),
                            const SizedBox(width: 8),
                            if (!isAiCover)
                              _imageActionButton(
                                icon: Icons.delete,
                                tooltip: '移除封面',
                                onPressed: () =>
                                    setState(() => _coverImage = null),
                                color: AppColors.error,
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  InkWell(
                    onTap: () => _showCoverImageSourceDialog(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.textDisabled.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 48,
                            color: AppColors.textDisabled,
                          ),
                          SizedBox(height: 8),
                          Text(
                            '点击添加封面图片',
                            style: TextStyle(color: AppColors.textDisabled),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imageActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Material(
      color: (color ?? AppColors.primary).withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  /// 显示封面图片来源选择
  void _showCoverImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickLocalImage(isCover: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('输入图片URL'),
              onTap: () {
                Navigator.pop(context);
                _addImageUrl(isCover: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 详情图片部分
  Widget _buildDetailImagesSection() {
    final detailImages = _images;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('详情图片', style: AppTextStyles.h3),
                const SizedBox(width: 8),
                Text(
                  '(${detailImages.length})',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _addImageUrl(isCover: false),
                  icon: const Icon(Icons.link),
                  tooltip: '添加URL',
                ),
                IconButton(
                  onPressed: () => _pickLocalImage(isCover: false),
                  icon: const Icon(Icons.photo_library),
                  tooltip: '选择本地图片',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (detailImages.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无详情图片',
                    style: TextStyle(color: AppColors.textDisabled),
                  ),
                ),
              )
            else
              ...detailImages.asMap().entries.map((entry) {
                final displayIndex = entry.key;
                final realIndex = displayIndex;
                final imagePath = entry.value;
                final isUrl = imagePath.startsWith('http');
                final isBase64 = imagePath.startsWith('data:image/');
                final isAsset = imagePath.startsWith('assets/');
                final isLocalFile = !isUrl && !isAsset && !isBase64;

                String displayText;
                String? subtitle;
                if (isBase64) {
                  displayText = 'WebP 图片';
                  subtitle = '已压缩';
                } else if (isLocalFile) {
                  displayText = kIsWeb ? '本地图片' : path.basename(imagePath);
                  subtitle = '本地文件';
                } else {
                  displayText = imagePath;
                  subtitle = null;
                }

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: _buildDetailImagePreview(imagePath, realIndex),
                    ),
                  ),
                  title: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: subtitle != null
                      ? Text(subtitle, style: const TextStyle(fontSize: 12))
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUrl)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editImageUrl(realIndex),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _deleteListItem(_images, realIndex),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailImagePreview(String imagePath, int index) {
    final recipe = _originalRecipe;
    if (recipe != null && isManagedRecipeDetailPath(imagePath)) {
      return CachedRecipeImage.detail(
        category: recipe.category,
        recipeId: cachedDetailRecipeId(recipe),
        imageIndex: index,
        width: 40,
        height: 40,
        errorWidget: const RecipePlaceholderImage.notDownloaded(compact: true),
      );
    }
    return _buildImagePreview(imagePath, width: 40, height: 40);
  }

  /// 通用列表部分构建
  Widget _buildListSection({
    required String title,
    required List<String> items,
    required VoidCallback onAdd,
    required Function(int) onEdit,
    required Function(int) onDelete,
    required VoidCallback onClear,
    bool numbered = false,
    String? Function(String)? validator,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.h3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (items.isNotEmpty)
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_all, size: 20),
                    color: AppColors.error,
                    tooltip: '清空',
                  ),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  tooltip: '添加',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无$title',
                    style: const TextStyle(color: AppColors.textDisabled),
                  ),
                ),
              )
            else
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (numbered)
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.surface,
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.circle,
                          size: 8,
                          color: AppColors.textSecondary,
                        ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => onEdit(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.error,
                        onPressed: () => onDelete(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// 添加列表项
  void _addListItem(List<String> list, String hint) {
    _editListItemDialog(list, -1, hint);
  }

  /// 编辑列表项
  void _editListItem(List<String> list, int index, String hint) {
    _editListItemDialog(list, index, hint);
  }

  /// 列表项编辑对话框
  void _editListItemDialog(List<String> list, int index, String hint) {
    final controller = TextEditingController(
      text: index >= 0 ? list[index] : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index >= 0 ? hint : '添加'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (index >= 0) {
                    list[index] = text;
                  } else {
                    list.add(text);
                  }
                });
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 删除列表项
  void _deleteListItem(List<String> list, int index) {
    setState(() => list.removeAt(index));
  }

  /// 添加图片URL
  void _addImageUrl({bool isCover = false}) {
    _editImageUrlDialog(-1, isCover: isCover);
  }

  /// 编辑图片URL
  void _editImageUrl(int index) {
    _editImageUrlDialog(index);
  }

  /// 图片URL编辑对话框
  void _editImageUrlDialog(int index, {bool isCover = false}) {
    final controller = TextEditingController(
      text: index >= 0 ? _images[index] : (isCover ? _coverImage ?? '' : ''),
    );

    final isEditing = index >= 0;
    final title = isEditing ? '编辑图片URL' : (isCover ? '设置封面图片URL' : '添加详情图片URL');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入图片URL地址',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  if (isEditing) {
                    _images[index] = url;
                  } else if (isCover) {
                    _coverImage = url;
                  } else {
                    _images.add(url);
                  }
                });
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 选择本地图片
  Future<void> _pickLocalImage({bool isCover = false}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      // 显示加载对话框
      if (mounted) {
        setState(() => _isUploadingImage = true);
        _showImageProcessingDialog();
      }

      // 读取图片字节
      final bytes = await image.readAsBytes();

      if (!mounted) return;
      _updateImageProcessingDialog('正在压缩图片...');

      // 压缩并转换为webp格式
      final compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: 85,
      );

      final originalSizeKB = (bytes.length / 1024).toStringAsFixed(1);
      final compressedSizeKB = (compressedBytes.length / 1024).toStringAsFixed(
        1,
      );

      String imagePath;

      if (kIsWeb) {
        if (!mounted) return;
        _updateImageProcessingDialog('正在转换格式...');

        // Web端：转换为base64字符串存储
        final base64String = base64Encode(compressedBytes);
        imagePath = 'data:image/webp;base64,$base64String';
      } else {
        if (!mounted) return;
        _updateImageProcessingDialog('正在保存文件...');

        // 移动端：保存到本地文件
        final appDir = await getApplicationDocumentsDirectory();
        final recipesImagesDir = Directory('${appDir.path}/recipe_images');

        // 确保目录存在
        if (!await recipesImagesDir.exists()) {
          await recipesImagesDir.create(recursive: true);
        }

        // 生成唯一文件名（使用webp扩展名）
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'recipe_${widget.recipeId}_$timestamp.webp';
        final targetPath = '${recipesImagesDir.path}/$fileName';

        // 写入压缩后的webp文件
        await File(targetPath).writeAsBytes(compressedBytes);
        imagePath = targetPath;
      }

      if (mounted) {
        setState(() {
          if (isCover) {
            _coverImage = imagePath;
          } else {
            _images.add(imagePath);
          }
          _isUploadingImage = false;
        });
        Navigator.of(context).pop();

        final label = isCover ? '封面图片' : '详情图片';
        AppSnackBar.show(
          context,
          '$label已更新 ($originalSizeKB KB → $compressedSizeKB KB)',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(); // 关闭加载对话框
        }
        AppSnackBar.show(context, '选择图片失败: $e');
      }
    }
  }

  /// 显示图片处理对话框
  void _showImageProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在处理图片...',
                key: const ValueKey('processing_text'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 更新图片处理对话框的文本
  void _updateImageProcessingDialog(String message) {
    // 通过查找 dialog context 来更新文本
    // 注意：这是一个简化的实现，生产环境可能需要使用 StatefulBuilder
    if (mounted && _isUploadingImage) {
      // 关闭旧对话框并显示新对话框
      Navigator.of(context).pop();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// 保存菜谱
  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_ingredientTexts.isEmpty) {
      AppSnackBar.show(context, '请至少添加一个食材');
      return;
    }

    if (_stepDescriptions.isEmpty) {
      AppSnackBar.show(context, '请至少添加一条操作');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 转换食材文本为Ingredient对象
      final ingredients = _ingredientTexts.asMap().entries.map((entry) {
        final index = entry.key;
        final text = entry.value;
        final name = text.split(RegExp(r'\s+')).first;
        if (index < _originalRecipe!.ingredients.length) {
          return _originalRecipe!.ingredients[index].copyWith(
            name: name,
            text: text,
          );
        }
        return Ingredient(name: name, text: text, source: 'manual');
      }).toList();

      // 转换步骤描述为CookingStep对象
      final steps = _stepDescriptions.asMap().entries.map((entry) {
        if (entry.key < _originalRecipe!.steps.length) {
          return _originalRecipe!.steps[entry.key].copyWith(
            description: entry.value,
          );
        }
        return CookingStep(description: entry.value);
      }).toList();

      final requirements = <RecipeRequirement>[
        ..._requirementTexts.map(
          (text) =>
              RecipeRequirement(text: text, markdown: text, kind: 'ingredient'),
        ),
        ..._tools.map(
          (text) => RecipeRequirement(text: text, markdown: text, kind: 'tool'),
        ),
      ];
      final requirementsMarkdown = requirements.isEmpty
          ? null
          : requirements.map((item) => '* ${item.text}').join('\n');
      final calculationMarkdown = <String>[
        ..._calculationNotes,
        ..._ingredientTexts.map((text) => '* $text'),
      ].join('\n');
      final categoryMap = await ref.read(categoryNameMapProvider.future);

      final updatedRecipe = _originalRecipe!.copyWith(
        schemaVersion: 2,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        category: _selectedCategory,
        categoryName:
            categoryMap[_selectedCategory] ?? _originalRecipe!.categoryName,
        difficulty: _selectedDifficulty,
        estimatedCaloriesKcal: int.tryParse(_caloriesController.text.trim()),
        requirements: requirements,
        requirementsMarkdown: requirementsMarkdown,
        ingredients: ingredients,
        calculationMarkdown: calculationMarkdown.isEmpty
            ? null
            : calculationMarkdown,
        calculationNotes: _calculationNotes,
        steps: steps,
        operationMarkdown: _stepDescriptions.join('\n'),
        tools: _tools,
        tips: _tips?.trim().isEmpty == true ? null : _tips?.trim(),
        warnings: _warnings,
        images: [if (_coverImage != null) _coverImage!, ..._images],
        source: switch (_originalRecipe!.source) {
          RecipeSource.bundled ||
          RecipeSource.cloud => RecipeSource.userModified,
          final source => source,
        },
      );

      final repository = ref.read(recipeRepositoryProvider);
      await repository.saveRecipe(updatedRecipe);

      // 刷新相关provider
      ref.invalidate(recipeByIdProvider(widget.recipeId));
      ref.invalidate(allRecipesProvider);

      if (mounted) {
        AppSnackBar.show(context, '保存成功');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 重置到原始状态
  Future<void> _resetToOriginal() async {
    final confirmed = await _showResetConfirmDialog();
    if (confirmed != true) {
      return;
    }

    setState(() {
      _nameController.text = _originalName;
      _descriptionController.text = _originalDescription;
      _caloriesController.text = _originalCalories;
      _selectedCategory = _originalCategory;
      _selectedDifficulty = _originalDifficulty;
      _requirementTexts = List.from(_originalRequirementTexts);
      _ingredientTexts = List.from(_originalIngredientTexts);
      _calculationNotes = List.from(_originalCalculationNotes);
      _stepDescriptions = List.from(_originalStepDescriptions);
      _tools = List.from(_originalTools);
      _tips = _originalTips;
      _warnings = List.from(_originalWarnings);
      _coverImage = _originalCoverImage;
      _images = List.from(_originalImages);
    });

    if (mounted) {
      AppSnackBar.show(context, '已重置到原始内容');
    }
  }

  /// 显示重置确认对话框
  Future<bool?> _showResetConfirmDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            Text(
              '确认重置？',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          '确定要重置所有修改吗？\n\n所有当前修改将被丢弃，恢复为原始内容。此操作不可撤销。',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  /// 确认并清空列表
  Future<void> _confirmAndClearList(List<String> list, String listName) async {
    final confirmed = await _showClearConfirmDialog(listName, list.length);
    if (confirmed == true) {
      setState(() => list.clear());
      if (mounted) {
        AppSnackBar.show(context, '已清空所有$listName');
      }
    }
  }

  /// 显示清空确认对话框
  Future<bool?> _showClearConfirmDialog(String listName, int count) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            Text(
              '确认清空？',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          '确定要清空所有$listName吗？\n\n当前有 $count 项内容将被删除，此操作不可撤销。',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

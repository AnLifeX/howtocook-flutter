enum RecipeDataMode { local, cloud }

extension RecipeDataModeX on RecipeDataMode {
  String get storageValue => name;

  String get label => switch (this) {
    RecipeDataMode.local => '本地数据',
    RecipeDataMode.cloud => '云端数据',
  };

  String get description => switch (this) {
    RecipeDataMode.local => '读取内置菜谱、用户保存和 AI 生成后保存的本地菜谱',
    RecipeDataMode.cloud => '读取云端 HowToCook 菜谱服务，不读取本地收藏和自建菜谱',
  };

  static RecipeDataMode fromStorage(dynamic value) {
    return RecipeDataMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => RecipeDataMode.local,
    );
  }
}

import 'ai_usage_metrics.dart';
import 'recipe_data_mode.dart';

class ConversationContextState {
  const ConversationContextState({
    this.summary,
    this.summarizedMessageCount = 0,
    this.lastInputTokens = 0,
    this.lastOutputTokens = 0,
    this.totalCacheReadTokens = 0,
    this.totalCacheMissTokens = 0,
    this.compressionApproved = false,
    this.recipeDataMode = RecipeDataMode.local,
  });

  final String? summary;
  final int summarizedMessageCount;
  final int lastInputTokens;
  final int lastOutputTokens;
  final int totalCacheReadTokens;
  final int totalCacheMissTokens;
  final bool compressionApproved;
  final RecipeDataMode recipeDataMode;

  bool get hasSummary => summary != null && summary!.trim().isNotEmpty;

  double? get cacheHitRate {
    final total = totalCacheReadTokens + totalCacheMissTokens;
    if (total <= 0) return null;
    return totalCacheReadTokens / total;
  }

  ConversationContextState copyWith({
    String? summary,
    bool clearSummary = false,
    int? summarizedMessageCount,
    int? lastInputTokens,
    int? lastOutputTokens,
    int? totalCacheReadTokens,
    int? totalCacheMissTokens,
    bool? compressionApproved,
    RecipeDataMode? recipeDataMode,
  }) {
    return ConversationContextState(
      summary: clearSummary ? null : (summary ?? this.summary),
      summarizedMessageCount:
          summarizedMessageCount ?? this.summarizedMessageCount,
      lastInputTokens: lastInputTokens ?? this.lastInputTokens,
      lastOutputTokens: lastOutputTokens ?? this.lastOutputTokens,
      totalCacheReadTokens: totalCacheReadTokens ?? this.totalCacheReadTokens,
      totalCacheMissTokens: totalCacheMissTokens ?? this.totalCacheMissTokens,
      compressionApproved: compressionApproved ?? this.compressionApproved,
      recipeDataMode: recipeDataMode ?? this.recipeDataMode,
    );
  }

  ConversationContextState recordUsage(AIUsageMetrics usage) {
    return copyWith(
      lastInputTokens: usage.inputTokens,
      lastOutputTokens: usage.outputTokens,
      totalCacheReadTokens: totalCacheReadTokens + usage.cacheReadTokens,
      totalCacheMissTokens:
          totalCacheMissTokens + usage.effectiveCacheMissTokens,
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'summarizedMessageCount': summarizedMessageCount,
    'lastInputTokens': lastInputTokens,
    'lastOutputTokens': lastOutputTokens,
    'totalCacheReadTokens': totalCacheReadTokens,
    'totalCacheMissTokens': totalCacheMissTokens,
    'compressionApproved': compressionApproved,
    'recipeDataMode': recipeDataMode.storageValue,
  };

  factory ConversationContextState.fromJson(Map<String, dynamic> json) {
    int readInt(String key) => (json[key] as num?)?.toInt() ?? 0;

    return ConversationContextState(
      summary: json['summary'] as String?,
      summarizedMessageCount: readInt('summarizedMessageCount'),
      lastInputTokens: readInt('lastInputTokens'),
      lastOutputTokens: readInt('lastOutputTokens'),
      totalCacheReadTokens: readInt('totalCacheReadTokens'),
      totalCacheMissTokens: readInt('totalCacheMissTokens'),
      compressionApproved: json['compressionApproved'] == true,
      recipeDataMode: RecipeDataModeX.fromStorage(json['recipeDataMode']),
    );
  }
}

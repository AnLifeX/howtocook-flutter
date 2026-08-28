class AIUsageMetrics {
  const AIUsageMetrics({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.cacheMissTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int? cacheMissTokens;

  int get effectiveCacheMissTokens =>
      cacheMissTokens ?? (inputTokens - cacheReadTokens).clamp(0, inputTokens);

  double? get cacheHitRate {
    final total = cacheReadTokens + effectiveCacheMissTokens;
    if (total <= 0) return null;
    return cacheReadTokens / total;
  }
}

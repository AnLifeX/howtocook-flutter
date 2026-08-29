import 'dart:math' as math;

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

  /// 本次请求实际送入模型窗口的完整输入。
  ///
  /// 标准 OpenAI/DeepSeek 用量中的 input/prompt tokens 已包含缓存命中；
  /// 少数兼容网关却把 inputTokens 当成未缓存输入单独返回。若缓存命中数
  /// 大于 inputTokens，可确定是后一种情况，需要把两部分合并。
  int get effectiveInputTokens {
    if (cacheMissTokens != null) {
      return math.max(inputTokens, cacheReadTokens + cacheMissTokens!);
    }
    if (cacheReadTokens > inputTokens) {
      return inputTokens + cacheReadTokens;
    }
    return inputTokens;
  }

  int get effectiveCacheMissTokens {
    if (cacheMissTokens != null) return cacheMissTokens!;
    if (cacheReadTokens > inputTokens) return inputTokens;
    return (inputTokens - cacheReadTokens).clamp(0, inputTokens);
  }

  double? get cacheHitRate {
    final total = cacheReadTokens + effectiveCacheMissTokens;
    if (total <= 0) return null;
    return cacheReadTokens / total;
  }
}

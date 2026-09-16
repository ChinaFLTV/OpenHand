import 'dart:math' as math;

import 'text_clip.dart';

/// 按需展开历史消息；已展开区间始终包含最新尾部，组件由列表懒构建。
abstract final class TranscriptListWindowing {
  static const int defaultInitialWindowSize = 4;
  static const int defaultWindowIncrement = 6;
  static const int defaultWindowingThreshold = 8;

  /// 首帧只构建尾部，避免同时解析多张富文本卡片。
  static const int defaultInitialPaintRows = 2;

  /// 计算最近消息窗口的起始索引。
  static int initialWindowStartIndex(
    int messageCount, {
    int initialWindowSize = defaultInitialWindowSize,
    int windowingThreshold = defaultWindowingThreshold,
  }) {
    final count = messageCount < 0 ? 0 : messageCount;
    final windowSize = math.max(1, initialWindowSize);
    final threshold = math.max(windowSize, windowingThreshold);
    if (count <= threshold) {
      return 0;
    }
    return math.max(0, count - windowSize);
  }

  static int clampWindowStart(int windowStart, int messageCount) {
    final count = messageCount < 0 ? 0 : messageCount;
    if (windowStart <= 0) {
      return 0;
    }
    if (windowStart >= count) {
      return count;
    }
    return windowStart;
  }

  /// 前插历史消息后移动窗口，保持原可见尾部稳定并展示一段更早内容。
  static int windowStartAfterHistoryPrepend({
    required int previousWindowStart,
    required int addedDisplayCount,
    int windowIncrement = defaultWindowIncrement,
  }) {
    final added = math.max(0, addedDisplayCount);
    final increment = math.max(1, windowIncrement);
    return math.max(0, previousWindowStart + added - increment);
  }

  /// 向前展示一段历史消息，结果不小于零。
  static int revealOlderWindowStart(
    int windowStart, {
    int windowIncrement = defaultWindowIncrement,
  }) {
    final increment = math.max(1, windowIncrement);
    return math.max(0, windowStart - increment);
  }

  /// 逻辑范围保留整个尾部，不用消息数量截断可滚动内容。
  static ({int start, int end}) visibleRange({
    required int preferredStart,
    required int messageCount,
  }) {
    final count = math.max(0, messageCount);
    return (start: clampWindowStart(preferredStart, count), end: count);
  }

  /// 追加消息不能收回用户已展开的历史。
  static int windowStartAfterAppend({
    required int previousWindowStart,
    required int messageCount,
  }) => clampWindowStart(previousWindowStart, messageCount);

  /// 首帧只挂最新尾部，其余窗口消息按帧补齐。
  static List<T> initialPaintSlice<T>(
    List<T> messages, {
    int paintRows = defaultInitialPaintRows,
  }) {
    final count = messages.length;
    if (count <= 0) return messages;
    final rows = math.max(1, paintRows);
    if (count <= rows) return messages;
    return messages.sublist(count - rows);
  }

  /// 截取固定开销的正文预览，并避免切断 UTF-16 代理对。
  static String boundedContentPreview(
    String value, {
    required int maxCharacters,
  }) {
    final requestedEnd = math.min(value.length, math.max(0, maxCharacters));
    final end = safeUtf16PrefixCodeUnits(value, requestedEnd);
    if (end == value.length) return value;
    return value.substring(0, end);
  }
}

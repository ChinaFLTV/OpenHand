import 'dart:math' as math;

import 'text_clip.dart';

/// 长会话列表窗口算法，限制首帧和滚动路径的物化规模。
abstract final class TranscriptListWindowing {
  static const int defaultInitialWindowSize = 6;
  static const int defaultWindowIncrement = 6;
  static const int defaultWindowingThreshold = 8;

  /// UI 同时物化的消息软上限，超出部分仍保留在数据层。
  /// 48 张 HTML/Markdown 卡会在首屏布局阶段同步拖垮 UI 线程（ANR）。
  static const int defaultMaxMaterializedWindow = 16;
  static const int defaultOpenFirstPaintCap = 3;
  static const int defaultExpandPerFrame = 2;
  static const int defaultWarmupMaxMessages = 6;
  static const int defaultHtmlWarmupMaxPerPass = 1;

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

  /// 限制重复加载历史消息后的物化窗口规模。
  static int cappedWindowStart({
    required int preferredWindowStart,
    required int messageCount,
    int maxMaterialized = defaultMaxMaterializedWindow,
  }) {
    final count = messageCount < 0 ? 0 : messageCount;
    final preferred = clampWindowStart(preferredWindowStart, count);
    final maxRows = math.max(1, maxMaterialized);
    if (count <= maxRows) {
      return preferred;
    }
    final minStartForCap = count - maxRows;
    return math.max(preferred, minStartForCap);
  }

  /// 从 [preferredStart] 计算有界物化区间。
  static ({int start, int end}) boundedRange({
    required int preferredStart,
    required int messageCount,
    int maxMaterialized = defaultMaxMaterializedWindow,
  }) {
    final count = messageCount < 0 ? 0 : messageCount;
    if (count == 0) return (start: 0, end: 0);
    final start = clampWindowStart(preferredStart, count);
    final maxRows = math.max(1, maxMaterialized);
    return (start: start, end: math.min(count, start + maxRows));
  }

  static int latestWindowStart(
    int messageCount, {
    int maxMaterialized = defaultMaxMaterializedWindow,
  }) {
    final count = math.max(0, messageCount);
    return math.max(0, count - math.max(1, maxMaterialized));
  }

  static int windowStartAfterAppend({
    required int previousWindowStart,
    required int previousMessageCount,
    required int messageCount,
    int maxMaterialized = defaultMaxMaterializedWindow,
  }) {
    final previousCount = math.max(0, previousMessageCount);
    final nextCount = math.max(0, messageCount);
    final maxRows = math.max(1, maxMaterialized);
    final shortWindowLimit = math.min(defaultWindowingThreshold, maxRows);
    if (nextCount <= shortWindowLimit) {
      return 0;
    }
    if (previousWindowStart <= 0 && previousCount <= maxRows) {
      return math.max(0, nextCount - maxRows);
    }
    final previousRange = boundedRange(
      preferredStart: previousWindowStart,
      messageCount: previousCount,
      maxMaterialized: maxRows,
    );
    if (nextCount > previousCount && previousRange.end >= previousCount) {
      final previousWindowLength = math.max(
        1,
        previousRange.end - previousRange.start,
      );
      return math.max(0, nextCount - previousWindowLength);
    }
    return clampWindowStart(previousWindowStart, nextCount);
  }

  /// 计算首帧窗口尾部，保持贴底定位稳定。
  static int openFirstPaintStartIndex(
    int visibleCount, {
    int firstPaintCap = defaultOpenFirstPaintCap,
  }) {
    final count = visibleCount < 0 ? 0 : visibleCount;
    final cap = openFirstPaintCount(count, firstPaintCap: firstPaintCap);
    if (count <= cap) {
      return 0;
    }
    return count - cap;
  }

  static int openFirstPaintCount(
    int visibleCount, {
    int firstPaintCap = defaultOpenFirstPaintCap,
  }) {
    final count = visibleCount < 0 ? 0 : visibleCount;
    return math.min(count, math.max(1, firstPaintCap));
  }

  /// 揭示后按帧补齐物化窗口，避免一次挂载剩余全部富文本卡。
  static int progressiveRenderCount({
    required int currentCount,
    required int targetCount,
    int expandPerFrame = defaultExpandPerFrame,
  }) {
    final current = math.max(0, currentCount);
    final target = math.max(0, targetCount);
    if (current >= target) return target;
    return math.min(target, current + math.max(1, expandPerFrame));
  }

  static List<T> tailSlice<T>(List<T> items, int count) {
    if (items.isEmpty || count >= items.length) return items;
    if (count <= 0) return items.sublist(items.length);
    return items.sublist(items.length - count);
  }

  static int warmupMessageBudget({
    int initialWindowSize = defaultInitialWindowSize,
    int windowIncrement = defaultWindowIncrement,
    int maxWarmup = defaultWarmupMaxMessages,
  }) {
    final desired = math.max(initialWindowSize, windowIncrement);
    return math.max(1, math.min(desired, maxWarmup));
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

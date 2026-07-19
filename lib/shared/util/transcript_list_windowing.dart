import 'dart:math' as math;

/// Pure list-window math for long transcript open / scroll paths.
///
/// Keeps the first paint bound to a recent window so large histories
/// (hundreds–thousands of messages) never force a full materialize on open.
abstract final class TranscriptListWindowing {
  static const int defaultInitialWindowSize = 8;
  static const int defaultWindowIncrement = 6;
  static const int defaultWindowingThreshold = 12;

  /// Soft upper bound for UI-materialized rows after repeated reveal-older.
  /// Beyond this, older rows stay in the data model but leave the active
  /// render window until the user reveals them again (via load-earlier).
  static const int defaultMaxMaterializedWindow = 48;
  static const int defaultOpenFirstPaintCap = 4;
  static const int defaultWarmupMaxMessages = 8;
  static const int defaultHtmlWarmupMaxPerPass = 1;

  /// Start index of the latest window for [messageCount] display messages.
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

  /// After prepending [addedDisplayCount] older messages at the front of the
  /// display list, shift the UI window so the previously visible tail stays
  /// on screen while revealing [windowIncrement] older items.
  static int windowStartAfterHistoryPrepend({
    required int previousWindowStart,
    required int addedDisplayCount,
    int windowIncrement = defaultWindowIncrement,
  }) {
    final added = math.max(0, addedDisplayCount);
    final increment = math.max(1, windowIncrement);
    return math.max(0, previousWindowStart + added - increment);
  }

  /// Reveal one older slice without going below zero.
  static int revealOlderWindowStart(
    int windowStart, {
    int windowIncrement = defaultWindowIncrement,
  }) {
    final increment = math.max(1, windowIncrement);
    return math.max(0, windowStart - increment);
  }

  /// Cap a growing UI window so repeated reveal-older cannot materialize an
  /// unbounded number of rows on the open/scroll path.
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

  /// Calculate a bounded materialized range beginning at [preferredStart].
  ///
  /// The range slides toward history instead of growing an ever-larger suffix.
  /// This keeps widget construction, rich-render warmup, and keyed-child lookup
  /// independent of the total number of loaded transcript messages.
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

  /// First-paint subset of a visible window: always keep the latest tail so
  /// jump-to-bottom remains stable while older rows mount on later frames.
  static int openFirstPaintStartIndex(
    int visibleCount, {
    int firstPaintCap = defaultOpenFirstPaintCap,
  }) {
    final count = visibleCount < 0 ? 0 : visibleCount;
    final cap = math.max(1, firstPaintCap);
    if (count <= cap) {
      return 0;
    }
    return count - cap;
  }

  static int warmupMessageBudget({
    int initialWindowSize = defaultInitialWindowSize,
    int windowIncrement = defaultWindowIncrement,
    int maxWarmup = defaultWarmupMaxMessages,
  }) {
    final desired = math.max(initialWindowSize, windowIncrement);
    return math.max(1, math.min(desired, maxWarmup));
  }
}

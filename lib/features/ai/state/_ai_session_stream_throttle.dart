/// AiSessionController 的流式输出背压辅助逻辑。
///
/// 两个轻量令牌桶限速器，用于在流式追加层做背压：
///
///   * [_StreamCharThrottle] —— 限制每秒向当前流式卡片 *显示* 的
///     grapheme cluster（用户感知字符）数。
///   * [_StreamCardThrottle] —— 限制每秒向当前会话新创建的消息卡片数。
///
/// 两个限速器都支持「关闭」（rate <= 0）。设计目标：
///   - 单 Timer，复杂度 O(1)；
///   - 不阻塞 isolate；
///   - dispose 时不会泄漏待执行回调。
part of '../ai_session_controller.dart';

final Stopwatch _streamThroughputStopwatch = Stopwatch()..start();

int _streamThroughputSecond() =>
    _streamThroughputStopwatch.elapsedMicroseconds ~/
    Duration.microsecondsPerSecond;

bool _runStreamThrottleCallback(void Function() callback, String where) {
  try {
    callback();
    return true;
  } catch (error, stack) {
    silentLog('ai_stream_throttle', where, error, stack);
    return false;
  }
}

/// 滑动窗口吞吐采样器，每秒一个桶，桶 0 = 当前秒。
///
/// 用于两条口径：
///   * AI 原始流入侧：stream event 一到就记录，供弹窗实时显示模型侧速率；
///   * UI 放出侧：节流器真正放出 grapheme 时记录，供内部诊断保留。
class _StreamThroughputSampler {
  static const int defaultWindowSeconds = 30;
  static const int retentionSeconds = 60 * 60;
  static const int maxPersistedPoints = 300;
  static const int _maxBucketValue = 0xFFFFFFFF;

  final Uint32List _buckets = Uint32List(retentionSeconds);
  int? _bucketSecond;
  int? _firstRecordedSecond;
  int _currentBucketIndex = 0;
  int _totalGraphemes = 0;

  int get totalGraphemes => _totalGraphemes;

  void recordText(String value) {
    if (value.isEmpty) return;
    recordGraphemes(value.characters.length);
  }

  void recordGraphemes(int graphemes) {
    final nowSec = _streamThroughputSecond();
    recordGraphemesAt(graphemes, nowSec);
  }

  void recordGraphemesAt(int graphemes, int second) {
    if (graphemes <= 0) return;
    _firstRecordedSecond ??= second;
    _totalGraphemes += graphemes;
    final bucketSecond = _bucketSecond;
    if (bucketSecond == null) {
      _bucketSecond = second;
      _addToCurrentBucket(graphemes);
      return;
    }
    final delta = second - bucketSecond;
    if (delta <= 0) {
      _addToCurrentBucket(graphemes);
      return;
    }
    _advanceBy(delta);
    _bucketSecond = second;
    _addToCurrentBucket(graphemes);
  }

  List<int> snapshot({int windowSeconds = defaultWindowSeconds, int? second}) {
    _advanceTo(second ?? _streamThroughputSecond());
    final window = windowSeconds.clamp(1, retentionSeconds).toInt();
    return List<int>.unmodifiable(
      Iterable<int>.generate(
        window,
        (offset) =>
            _buckets[(_currentBucketIndex - offset + retentionSeconds) %
                retentionSeconds],
      ),
    );
  }

  ({List<int> samples, int intervalMs}) persistentSeries({
    int maxPoints = maxPersistedPoints,
    int? second,
  }) {
    final firstSecond = _firstRecordedSecond;
    final lastRecordedSecond = _bucketSecond;
    if (firstSecond == null || lastRecordedSecond == null || maxPoints <= 0) {
      return (samples: const <int>[], intervalMs: 1000);
    }
    final endSecond = math.max(
      lastRecordedSecond,
      second ?? _streamThroughputSecond(),
    );
    final retainedStart = math.max(
      firstSecond,
      endSecond - retentionSeconds + 1,
    );
    final windowSeconds = endSecond - retainedStart + 1;
    final chronological = snapshot(
      windowSeconds: windowSeconds,
      second: endSecond,
    ).reversed.toList(growable: false);
    if (chronological.length <= maxPoints) {
      return (samples: chronological, intervalMs: 1000);
    }
    final groupSize = (chronological.length / maxPoints).ceil();
    final compacted = <int>[];
    for (var start = 0; start < chronological.length; start += groupSize) {
      final end = math.min(start + groupSize, chronological.length);
      var total = 0;
      for (var index = start; index < end; index++) {
        total += chronological[index];
      }
      compacted.add((total / (end - start)).round());
    }
    return (
      samples: List<int>.unmodifiable(compacted),
      intervalMs: groupSize * 1000,
    );
  }

  void _advanceTo(int second) {
    final bucketSecond = _bucketSecond;
    if (bucketSecond == null) return;
    final delta = second - bucketSecond;
    if (delta <= 0) return;
    _advanceBy(delta);
    _bucketSecond = second;
  }

  void _advanceBy(int delta) {
    if (delta >= retentionSeconds) {
      _buckets.fillRange(0, retentionSeconds, 0);
      _currentBucketIndex = 0;
      return;
    }
    for (var i = 0; i < delta; i++) {
      _currentBucketIndex = (_currentBucketIndex + 1) % retentionSeconds;
      _buckets[_currentBucketIndex] = 0;
    }
  }

  void _addToCurrentBucket(int graphemes) {
    final current = _buckets[_currentBucketIndex];
    _buckets[_currentBucketIndex] = graphemes >= _maxBucketValue - current
        ? _maxBucketValue
        : current + graphemes;
  }
}

/// 会话级字符显示预算。
///
/// assistant 与 reasoning 两条流共享同一个实例，确保「字符 / 秒」配置约束
/// 的是本会话总展示吞吐，而不是每张卡各自拿一份额度。令牌桶仍保留平滑
/// 补给，但每个自然秒再加一道硬上限，避免初始预算或双流叠加把弹窗峰值
/// 冲到用户配置之上。
class _StreamCharThrottleBudget {
  _StreamCharThrottleBudget({required int maxCharsPerSecond})
    : _maxCharsPerSecond = maxCharsPerSecond,
      _budget = maxCharsPerSecond > 0 ? maxCharsPerSecond.toDouble() : 0.0,
      _clock = Stopwatch()..start();

  int _maxCharsPerSecond;
  double _budget;
  final Stopwatch _clock;
  int _lastTickMicroseconds = 0;
  int _bucketSecond = 0;
  int _emittedThisSecond = 0;

  int get maxCharsPerSecond => _maxCharsPerSecond;

  set maxCharsPerSecond(int next) {
    if (next == _maxCharsPerSecond) return;
    _maxCharsPerSecond = next;
    if (next <= 0) {
      _budget = 0;
      _emittedThisSecond = 0;
      return;
    }
    if (_budget > next) _budget = next.toDouble();
    if (_emittedThisSecond > next) _emittedThisSecond = next;
  }

  ({int count, int bucketSecond}) grant(int pendingGraphemes) {
    if (pendingGraphemes <= 0 || _maxCharsPerSecond <= 0) {
      return (count: 0, bucketSecond: _bucketSecond);
    }
    _refill();
    final remainingThisSecond = _maxCharsPerSecond - _emittedThisSecond;
    if (remainingThisSecond <= 0) {
      return (count: 0, bucketSecond: _bucketSecond);
    }
    final allowance = math.min(_budget.floor(), remainingThisSecond);
    if (allowance <= 0) return (count: 0, bucketSecond: _bucketSecond);
    final granted = math.min(allowance, pendingGraphemes);
    _budget -= granted;
    _emittedThisSecond += granted;
    return (count: granted, bucketSecond: _bucketSecond);
  }

  double get partialCharProgress {
    if (_maxCharsPerSecond <= 0) return 1;
    return clampUnitInterval(_budget);
  }

  void _refill() {
    final nowSec = _streamThroughputSecond();
    if (_bucketSecond != nowSec) {
      _bucketSecond = nowSec;
      _emittedThisSecond = 0;
    }
    final nowMicroseconds = _clock.elapsedMicroseconds;
    final elapsedMicros = nowMicroseconds - _lastTickMicroseconds;
    if (elapsedMicros <= 0) {
      return;
    }
    _budget += elapsedMicros * _maxCharsPerSecond / 1000000.0;
    if (_budget > _maxCharsPerSecond) {
      _budget = _maxCharsPerSecond.toDouble();
    }
    _lastTickMicroseconds = nowMicroseconds;
  }
}

/// 显示侧 grapheme 级令牌桶限速器。
///
/// 调用方在拿到完整 sanitized 文本后通过 [renderableGraphemeCount] 询问当前
/// 时刻最多可对外渲染多少个 grapheme cluster；剩余 grapheme 会随着时间推
/// 进自动放开。限速器内部维护一个 ~16ms 节奏的周期 Timer，在余量未释放
/// 时持续触发调用方的 [_onTick] 回调，驱动 UI 把后续 grapheme 滚动出来。
/// 流结束且显示队列已自然排空后调用 [release] 清理计时器。
///
/// [throttleDuration] 启用「节流时长」：从 throttle 创建时刻起经过该时长后，
/// [isDurationExpired] 会变为 true 供 UI 表示持续时长已耗尽；显示侧仍继续
/// 遵守 [maxCharsPerSecond]，避免已积压的正式响应内容突然一次性倾泻。
/// null = 不显示时长耗尽态。
///
/// 命名约定：所有 `*Chars` / `*chars` 计数均按 grapheme 语义解释；
/// 字段名保留 `Chars` 是为了兼容既有设置与持久化结构。
class _StreamCharThrottle {
  _StreamCharThrottle({
    required int maxCharsPerSecond,
    required void Function() onTick,
    Duration? throttleDuration,
    _StreamCharThrottleBudget? sharedBudget,
  }) : _budget =
           sharedBudget ??
           _StreamCharThrottleBudget(maxCharsPerSecond: maxCharsPerSecond),
       _onTick = onTick,
       _throttleDuration =
           (throttleDuration != null && throttleDuration.inMilliseconds > 0)
           ? throttleDuration
           : null,
       _durationClock = Stopwatch()..start() {
    // 持续节流模式下 `_throttleDuration` 必须保持 null，避免正式响应在流期内
    // 意外穿透限速。
    assert(
      !(maxCharsPerSecond > 0 && throttleDuration == null) ||
          _throttleDuration == null,
      '正速率持续节流必须在整个流式阶段保持未过期。',
    );
    assert(
      !(maxCharsPerSecond > 0 && throttleDuration == null) || !_isExpired,
      '正速率持续节流在创建时不能处于过期状态。',
    );
  }

  /// 每秒允许被「展示」的 grapheme 数；<=0 视为关闭限速。
  /// 会话级节流弹窗 Apply 后可立即更新当前活跃 throttle。
  /// 写入新值时同步把 [_budget] 钳到新上限内，防止旧时钟下累积出超额令牌。
  int get maxCharsPerSecond => _budget.maxCharsPerSecond;
  set maxCharsPerSecond(int next) => _budget.maxCharsPerSecond = next;

  /// 会话级运行时开关：`false` 立即从限速桶切换到 pass-through。
  /// `null` = 沿用 maxCharsPerSecond 推断的 enable 状态；显式 `false`
  /// 时即便 maxCharsPerSecond > 0 也会绕过节流；`true` 等同于默认。
  bool? _enabledOverride;
  set enabledOverride(bool? next) {
    if (next == _enabledOverride) return;
    _enabledOverride = next;
    // 关闭节流后立刻补一次 onTick，让等待中的 grapheme 一次性兑现，
    // 不必等下一个 textDelta 才看见输出。
    if (next == false && !_disposed) {
      _runStreamThrottleCallback(_onTick, '字符节流开关回调');
    }
  }

  final void Function() _onTick;
  Timer? _drainTimer;
  bool _disposed = false;
  final _StreamCharThrottleBudget _budget;
  // 已被允许显示的 grapheme 数。
  int _emittedGraphemes = 0;
  // 最近一次 [renderableGraphemeCount] 的总 grapheme 数；用于
  // [hasPending] / [drainGracefully] 判定。
  int _lastKnownTotalGraphemes = 0;
  final Duration? _throttleDuration;
  final Stopwatch _durationClock;

  bool get isEnabled => (_enabledOverride ?? true) && maxCharsPerSecond > 0;

  bool get _isExpired {
    final duration = _throttleDuration;
    return duration != null && _durationClock.elapsed >= duration;
  }

  /// 节流时长是否已耗尽。仅在传入 throttleDuration 时为 true；用于 UI
  /// 把"剩余流式响应正以真实速率追加"的状态向用户透出。
  bool get isDurationExpired => _isExpired;

  /// 推进时钟并补充令牌，返回当前允许「显示」的最大 grapheme 数。
  ///
  /// 调用方应当传入 `text.characters.length`（grapheme 总数）。返回值
  /// 同样是 grapheme 数，调用方可用 `text.characters.take(visible)` 来
  /// 取出可见前缀，保证切片永远落在 grapheme cluster 边界。
  int renderableGraphemeCount(int totalSanitizedGraphemeCount) {
    _lastKnownTotalGraphemes = totalSanitizedGraphemeCount;
    if (!isEnabled || _disposed) {
      // 正速率 pass-through 只允许发生在主动 release 或用户显式关闭节流后。
      assert(
        !(maxCharsPerSecond > 0) || _disposed || _enabledOverride == false,
        'positive-rate _StreamCharThrottle short-circuited to pass-through '
        'while still active — this would dump the whole assistant_final '
        'response in one frame. rate=$maxCharsPerSecond '
        '_disposed=$_disposed _isExpired=$_isExpired '
        '_enabledOverride=$_enabledOverride.',
      );
      final granted = totalSanitizedGraphemeCount - _emittedGraphemes;
      _emittedGraphemes = totalSanitizedGraphemeCount;
      if (granted > 0) _recordEmission(granted);
      return totalSanitizedGraphemeCount;
    }
    if (totalSanitizedGraphemeCount <= _emittedGraphemes) {
      return _emittedGraphemes;
    }
    final pending = totalSanitizedGraphemeCount - _emittedGraphemes;
    final grant = _budget.grant(pending);
    if (grant.count > 0) {
      _emittedGraphemes += grant.count;
      _recordEmission(grant.count, second: grant.bucketSecond);
    }
    if (_emittedGraphemes < totalSanitizedGraphemeCount) {
      _scheduleDrain();
    }
    return _emittedGraphemes;
  }

  // ── 显示侧吞吐采样：最长保留一小时，默认读取最近 30 秒。
  final _displayThroughput = _StreamThroughputSampler();

  void _recordEmission(int graphemes, {int? second}) {
    if (second == null) {
      _displayThroughput.recordGraphemes(graphemes);
      return;
    }
    _displayThroughput.recordGraphemesAt(graphemes, second);
  }

  /// 每秒 grapheme 放出快照，默认最近 30 秒，桶 0 = 当前秒，越往后越旧。
  /// 返回不可变副本，UI 可直接喂给 painter。
  List<int> throughputSnapshot({int windowSeconds = 30, int? second}) {
    return _displayThroughput.snapshot(
      windowSeconds: windowSeconds,
      second: second,
    );
  }

  void _scheduleDrain() {
    if (_drainTimer != null || _disposed) {
      return;
    }
    // 60fps 节奏：16ms 一次 tick，让 grapheme 在低速率（默认 3
    // grapheme/秒）下也能感受到稳定的"打字机"节奏，而不是间歇性蹦出
    // 整块。在高速率下也不会因为 tick 太密把主线程拖累——onTick 回调
    // 本身只做轻量切片。
    _drainTimer = startSafeTimer(kOpenHandFramePeriodicTimerInterval, () {
      _drainTimer = null;
      if (_disposed) {
        return;
      }
      _runStreamThrottleCallback(_onTick, '字符节流排空回调');
      if (_emittedGraphemes < _lastKnownTotalGraphemes) {
        _scheduleDrain();
      }
    });
  }

  /// 当前距离释放下一个 grapheme 还差多少（[0, 1] 区间，1 = 即将释放）。
  /// 用于给 UI 渲染半透明的"待出场字符"，让低速率下的渲染拥有连续动画。
  double get partialCharProgress {
    if (!isEnabled) return 1;
    return _budget.partialCharProgress;
  }

  /// 直通（关闭）期间调用方以码元数近似计量，与 grapheme 预算口径脱钩；
  /// 重新开启节流时用真实 grapheme 总数校准已放出计数：已展示内容不回缩，
  /// 新增内容从当前位置按预算铺开。
  void syncEmittedGraphemes(int totalGraphemes) {
    if (totalGraphemes < 0 || _disposed) return;
    _emittedGraphemes = totalGraphemes;
  }

  /// 立刻释放剩余预算，供流结束 / 取消时把全部内容一次性显式刷出。
  void release() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    _emittedGraphemes = 1 << 30;
  }

  /// 当前是否还有 pending grapheme 未被释放给 UI（仅在 isEnabled=true 时
  /// 有意义）。
  bool get hasPending =>
      isEnabled && !_disposed && _emittedGraphemes < _lastKnownTotalGraphemes;

  /// 软排空：异步等待直到 _emittedGraphemes 追上 _lastKnownTotalGraphemes
  /// 或超过 [maxWait]。流结束后调用，让残余 grapheme 仍按节流速率均匀放
  /// 出，避免「最后一刻一次性 burst 出全部内容」的糟糕观感。
  ///
  /// 返回 true 表示自然排空，false 表示因超时被外部强制 release。
  Future<bool> drainGracefully({Duration? maxWait}) async {
    if (!hasPending) return true;
    final waitStopwatch = maxWait == null ? null : (Stopwatch()..start());
    while (hasPending) {
      if (maxWait != null && waitStopwatch!.elapsed >= maxWait) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
    return true;
  }
}

/// 卡片级令牌桶限速器。
///
/// 调用方在每次想要 *新增* 一张消息卡片前调用 [tryAcquire]；若返回 true
/// 直接执行回调，否则入队并在下一可用令牌到达时由内部 Timer 异步回放。
/// 排队回调按入队顺序顺序执行，不会乱序追加消息。
class _StreamCardThrottle {
  _StreamCardThrottle({
    required int maxCardsPerSecond,
    required void Function() onCardEmitted,
  }) : _maxCardsPerSecond = math.max(0, maxCardsPerSecond),
       _onCardEmitted = onCardEmitted,
       _budget = math.max(0, maxCardsPerSecond).toDouble(),
       _clock = Stopwatch()..start();

  /// 每秒允许被「展示」的新卡片数；<=0 视为关闭限速。
  /// 会话级节流弹窗 Apply 后可立即更新当前活跃 throttle。
  int _maxCardsPerSecond;
  int get maxCardsPerSecond => _maxCardsPerSecond;
  set maxCardsPerSecond(int next) {
    final safeNext = math.max(0, next);
    if (safeNext == _maxCardsPerSecond) return;
    _maxCardsPerSecond = safeNext;
    if (safeNext <= 0) {
      _budget = 0;
      _drainTimer?.cancel();
      _drainTimer = null;
      _flushPending();
      return;
    }
    if (_budget > safeNext) _budget = safeNext.toDouble();
    if (_pending.isNotEmpty) {
      _scheduleDrain();
    }
  }

  /// 会话级运行时开关：关闭时下次 [tryAcquire] 直接通过并排空积压。
  bool? _enabledOverride;
  set enabledOverride(bool? next) {
    if (next == _enabledOverride) return;
    _enabledOverride = next;
    if (next == false && _pending.isNotEmpty && !_disposed) {
      _flushPending();
    }
  }

  final void Function() _onCardEmitted;
  static const int _maxPendingCards = 2048;
  final Queue<VoidCallback> _pending = Queue<VoidCallback>();
  Timer? _drainTimer;
  bool _disposed = false;
  double _budget;
  final Stopwatch _clock;
  int _lastTickMicroseconds = 0;

  bool get isEnabled => (_enabledOverride ?? true) && maxCardsPerSecond > 0;

  /// 当前积压的待发卡片数（仅在 isEnabled=true 时有意义）。供 TopBar
  /// 节流胶囊把"等几张"实时反馈给用户。
  int get pendingCount => _pending.length;

  bool tryAcquire(VoidCallback create) {
    if (_disposed || !isEnabled) {
      return true;
    }
    _refill();
    if (_budget >= 1) {
      _budget -= 1;
      return true;
    }
    if (_pending.length >= _maxPendingCards) {
      _flushPending();
      return true;
    }
    _pending.addLast(create);
    _scheduleDrain();
    return false;
  }

  void _refill() {
    if (maxCardsPerSecond <= 0) {
      _budget = 0;
      _lastTickMicroseconds = _clock.elapsedMicroseconds;
      return;
    }
    final nowMicroseconds = _clock.elapsedMicroseconds;
    final elapsedMicros = nowMicroseconds - _lastTickMicroseconds;
    if (elapsedMicros <= 0) {
      return;
    }
    _budget += elapsedMicros * maxCardsPerSecond / 1000000.0;
    if (_budget > maxCardsPerSecond) {
      _budget = maxCardsPerSecond.toDouble();
    }
    _lastTickMicroseconds = nowMicroseconds;
  }

  void _scheduleDrain() {
    if (_drainTimer != null || _disposed) {
      return;
    }
    if (!isEnabled || maxCardsPerSecond <= 0) {
      _flushPending();
      return;
    }
    final tokensNeeded = clampUnitInterval(1 - _budget);
    final waitSeconds = tokensNeeded <= 0
        ? 0.0
        : tokensNeeded / maxCardsPerSecond;
    final waitMs = (waitSeconds * 1000).ceil().clamp(8, 1000);
    _drainTimer = startSafeTimer(Duration(milliseconds: waitMs), _drainOnce);
  }

  void _drainOnce() {
    _drainTimer = null;
    if (_disposed) {
      return;
    }
    _refill();
    var emitted = 0;
    while (_pending.isNotEmpty && _budget >= 1) {
      final cb = _pending.removeFirst();
      _budget -= 1;
      if (_runStreamThrottleCallback(cb, '卡片节流排空回调')) {
        emitted++;
      }
    }
    if (emitted > 0) {
      _runStreamThrottleCallback(_onCardEmitted, '卡片已放出');
    }
    if (_pending.isNotEmpty) {
      _scheduleDrain();
    }
  }

  void _flushPending() {
    if (_pending.isEmpty || _disposed) {
      return;
    }
    final pending = List<VoidCallback>.from(_pending);
    _pending.clear();
    for (final cb in pending) {
      _runStreamThrottleCallback(cb, '卡片节流立即排空回调');
    }
    _runStreamThrottleCallback(_onCardEmitted, '卡片积压已排空');
  }

  /// 立即释放：把所有积压回调一次性追加，然后置位 disposed 防止 Timer
  /// 再触发。流结束 / 取消时调用。
  void releaseAll() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    final pending = List<VoidCallback>.from(_pending);
    _pending.clear();
    for (final cb in pending) {
      _runStreamThrottleCallback(cb, '卡片节流释放回调');
    }
    if (pending.isNotEmpty) {
      _runStreamThrottleCallback(_onCardEmitted, '卡片积压已释放');
    }
  }

  void cancelPending() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    _pending.clear();
  }
}

/// 流式缓冲的 sanitize / grapheme 结果备忘录。
///
/// raw buffer 只会追加，长度即内容版本：长度未变时 16ms 节流 tick 与
/// 72ms 预览 flush 直接复用上次结果，把重复的 O(N) 全量清洗降为 O(1)；
/// 长度变化才重新 sanitize。grapheme 统计与 [Characters] 视图按需惰性
/// 计算，并随内容版本一起失效。
class _StreamSanitizedBufferMemo {
  int _rawLength = -1;
  String _sanitized = '';
  Characters? _characters;
  int _graphemeCount = -1;

  String sanitizedFor(StringBuffer buffer) {
    if (buffer.length != _rawLength) {
      _rawLength = buffer.length;
      _sanitized = _sanitizeVisibleModelContent(buffer.toString());
      _characters = null;
      _graphemeCount = -1;
    }
    return _sanitized;
  }

  int graphemeCountFor(StringBuffer buffer) {
    final sanitized = sanitizedFor(buffer);
    if (_graphemeCount < 0) {
      final characters = sanitized.characters;
      _characters = characters;
      _graphemeCount = characters.length;
    }
    return _graphemeCount;
  }

  Characters charactersFor(StringBuffer buffer) {
    graphemeCountFor(buffer);
    return _characters!;
  }
}

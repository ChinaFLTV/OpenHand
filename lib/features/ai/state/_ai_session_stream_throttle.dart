/// Stream output back-pressure helpers for AiSessionController.
///
/// 2026-05-17 — 用户反馈：AI 在短时间内回吐大量字符或连续追加多张消息卡
/// 片时，会触发 UI 端布局抖动 / 主线程卡顿 / 列表上下弹跳等糟糕体验。
/// 本文件提供两个轻量的令牌桶限速器，用于在流式追加层做背压：
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

/// 滑动窗口吞吐采样器，每秒一个桶，桶 0 = 当前秒。
///
/// 用于两条口径：
///   * AI 原始流入侧：stream event 一到就记录，供弹窗实时显示模型侧速率；
///   * UI 放出侧：节流器真正放出 grapheme 时记录，供内部诊断保留。
class _StreamThroughputSampler {
  static const int defaultWindowSeconds = 30;
  static const int retentionSeconds = 6 * 60 * 60;

  final List<int> _buckets = List<int>.filled(retentionSeconds, 0);
  int _bucketSecond = 0;

  void recordText(String value) {
    if (value.isEmpty) return;
    recordGraphemes(value.characters.length);
  }

  void recordGraphemes(int graphemes) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    recordGraphemesAt(graphemes, nowSec);
  }

  void recordGraphemesAt(int graphemes, int epochSecond) {
    if (graphemes <= 0) return;
    if (_bucketSecond == 0) {
      _bucketSecond = epochSecond;
      _buckets[0] = graphemes;
      return;
    }
    final delta = epochSecond - _bucketSecond;
    if (delta <= 0) {
      _buckets[0] += graphemes;
      return;
    }
    _advanceBy(delta);
    _bucketSecond = epochSecond;
    _buckets[0] = graphemes;
  }

  List<int> snapshot({int windowSeconds = defaultWindowSeconds}) {
    _advanceByWallClock();
    final window = windowSeconds.clamp(1, retentionSeconds).toInt();
    return List<int>.unmodifiable(_buckets.take(window));
  }

  int get currentSecondValue => _buckets[0];

  void _advanceByWallClock() {
    if (_bucketSecond == 0) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final delta = nowSec - _bucketSecond;
    if (delta <= 0) return;
    _advanceBy(delta);
    _bucketSecond = nowSec;
  }

  void _advanceBy(int delta) {
    if (delta >= retentionSeconds) {
      for (var i = 0; i < retentionSeconds; i++) {
        _buckets[i] = 0;
      }
      return;
    }
    for (var i = retentionSeconds - 1; i >= delta; i--) {
      _buckets[i] = _buckets[i - delta];
    }
    for (var i = 0; i < delta; i++) {
      _buckets[i] = 0;
    }
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
      _lastTickAt = DateTime.now();

  int _maxCharsPerSecond;
  double _budget;
  DateTime _lastTickAt;
  int _wallSecond = 0;
  int _emittedThisWallSecond = 0;

  int get maxCharsPerSecond => _maxCharsPerSecond;

  set maxCharsPerSecond(int next) {
    if (next == _maxCharsPerSecond) return;
    _maxCharsPerSecond = next;
    if (next <= 0) {
      _budget = 0;
      _emittedThisWallSecond = 0;
      return;
    }
    if (_budget > next) _budget = next.toDouble();
    if (_emittedThisWallSecond > next) _emittedThisWallSecond = next;
  }

  ({int count, int wallSecond}) grant(int pendingGraphemes) {
    if (pendingGraphemes <= 0 || _maxCharsPerSecond <= 0) {
      return (count: 0, wallSecond: _wallSecond);
    }
    _refill();
    final remainingThisSecond = _maxCharsPerSecond - _emittedThisWallSecond;
    if (remainingThisSecond <= 0) return (count: 0, wallSecond: _wallSecond);
    final allowance = math.min(_budget.floor(), remainingThisSecond);
    if (allowance <= 0) return (count: 0, wallSecond: _wallSecond);
    final granted = math.min(allowance, pendingGraphemes);
    _budget -= granted;
    _emittedThisWallSecond += granted;
    return (count: granted, wallSecond: _wallSecond);
  }

  double get partialCharProgress {
    if (_maxCharsPerSecond <= 0) return 1;
    return _budget.clamp(0.0, 1.0).toDouble();
  }

  void _refill() {
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    if (_wallSecond != nowSec) {
      _wallSecond = nowSec;
      _emittedThisWallSecond = 0;
    }
    final elapsedMicros = now.difference(_lastTickAt).inMicroseconds;
    if (elapsedMicros <= 0) {
      return;
    }
    _budget += elapsedMicros * _maxCharsPerSecond / 1000000.0;
    if (_budget > _maxCharsPerSecond) {
      _budget = _maxCharsPerSecond.toDouble();
    }
    _lastTickAt = now;
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
/// 命名约定：所有 `*Chars` / `*chars` 计数（包括对外 [maxCharsPerSecond]
/// 字段名以及内部 [_budget] / 节流桶）均按 grapheme 语义解释；
/// 字段名保留 `Chars` 是为了避免破坏 SettingsController 等远端调用方
/// 的字段命名（task 3.2 会把整条调用链一起切到 grapheme 命名）。
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
       _expireAt =
           (throttleDuration != null && throttleDuration.inMilliseconds > 0)
           ? DateTime.now().add(throttleDuration)
           : null {
    // 2026-05-22 — Bug 1 修复（task 3.3）：守住「正式响应卡片必走节流」的
    // 不变量。
    //
    // 持续节流模式（[throttleDuration] == null 或非正）下：
    //   * `_expireAt` 必须保持 null —— [_isExpired] 因此恒为 false，
    //     [isEnabled] 仅在 [maxCharsPerSecond] <= 0 时关闭；
    //   * `[_isExpired]` 既然不会被翻转，整个生命周期内 [renderableGraphemeCount]
    //     的「!isEnabled 且 maxCharsPerSecond > 0」短路只可能因为
    //     [release] 标记 [_disposed] 才发生。
    //
    // 写时检查：[_expireAt] 是 final，构造完成之后没有路径能再次赋值，
    // 所以这里一次断言即可锁住整条不变量；不引入额外状态机。
    assert(
      !(maxCharsPerSecond > 0 && throttleDuration == null) || _expireAt == null,
      'positive-rate continuous throttle (assistant_final path) MUST keep '
      '_expireAt == null so _isExpired stays false for the whole stream — '
      'rate=$maxCharsPerSecond throttleDuration=$throttleDuration.',
    );
    assert(
      !(maxCharsPerSecond > 0 && throttleDuration == null) || !_isExpired,
      'positive-rate continuous throttle MUST NOT be _isExpired at '
      'construction time — rate=$maxCharsPerSecond.',
    );
  }

  /// 每秒允许被「展示」的 grapheme 数；<=0 视为关闭限速。
  /// 会话级节流弹窗 Apply 后可立即更新当前活跃 throttle。
  /// 写入新值时同步把 [_budget] 钳到新上限内，防止旧时钟下累积出超额令牌。
  int get maxCharsPerSecond => _budget.maxCharsPerSecond;
  set maxCharsPerSecond(int next) => _budget.maxCharsPerSecond = next;

  /// 2026-05-19 — 会话级运行时开关：用户在节流弹窗中关闭节流时，控制
  /// 器把 `false` 推到当前活跃 throttle，立即从限速桶切换到 pass-through。
  /// `null` = 沿用 maxCharsPerSecond 推断的 enable 状态；显式 `false`
  /// 时即便 maxCharsPerSecond > 0 也会绕过节流；`true` 等同于默认。
  bool? _enabledOverride;
  set enabledOverride(bool? next) {
    if (next == _enabledOverride) return;
    _enabledOverride = next;
    // 关闭节流后立刻补一次 onTick，让等待中的 grapheme 一次性兑现，
    // 不必等下一个 textDelta 才看见输出。
    if (next == false && !_disposed) {
      try {
        _onTick();
      } catch (_) {
        // ignore
      }
    }
  }

  final void Function() _onTick;
  Timer? _drainTimer;
  bool _disposed = false;
  final _StreamCharThrottleBudget _budget;
  // 已被允许显示的 grapheme 数。命名从 `_emittedChars` 切换为
  // `_emittedGraphemes`，对外通过 [renderableGraphemeCount] 暴露。
  int _emittedGraphemes = 0;
  // 最近一次 [renderableGraphemeCount] 的总 grapheme 数；用于
  // [hasPending] / [drainGracefully] 判定。
  int _lastKnownTotalGraphemes = 0;
  final DateTime? _expireAt;

  bool get isEnabled => (_enabledOverride ?? true) && maxCharsPerSecond > 0;

  bool get _isExpired {
    final exp = _expireAt;
    return exp != null && !DateTime.now().isBefore(exp);
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
      // 2026-05-22 — Bug 1 修复（task 3.3）：守住正式响应卡片的节流
      // 不变量。当 maxCharsPerSecond > 0 时，进入 pass-through 短路
      // 只允许两种合法原因：
      //   ① [_disposed] == true   —— 调用方主动 release（错误/取消/
      //                                  流末尾兜底）；
      //   ② [_enabledOverride] == false —— 用户显式关闭节流。
      // 在持续节流（throttleDuration == null）+ 仍在流期（未 release）
      // 的路径里命中本短路就是真 bug —— 字符会被一次性 dump。
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
      _recordEmission(grant.count, epochSecond: grant.wallSecond);
    }
    if (_emittedGraphemes < totalSanitizedGraphemeCount) {
      _scheduleDrain();
    }
    return _emittedGraphemes;
  }

  // ── 显示侧吞吐采样：保留最近 30 秒 grapheme 放出量，O(1) 更新。
  final _displayThroughput = _StreamThroughputSampler();

  void _recordEmission(int graphemes, {int? epochSecond}) {
    if (epochSecond == null) {
      _displayThroughput.recordGraphemes(graphemes);
      return;
    }
    _displayThroughput.recordGraphemesAt(graphemes, epochSecond);
  }

  /// 最近 30 秒的每秒 grapheme 放出快照，桶 0 =
  /// 当前秒，越往后越旧。返回不可变副本，UI 可直接喂给 painter。
  List<int> throughputSnapshot({int windowSeconds = 30}) {
    return _displayThroughput.snapshot(windowSeconds: windowSeconds);
  }

  /// 当前秒（桶 0）累计已放出的 grapheme 数。
  int get currentSecondEmitted => _displayThroughput.currentSecondValue;

  void _scheduleDrain() {
    if (_drainTimer != null || _disposed) {
      return;
    }
    // 60fps 节奏：16ms 一次 tick，让 grapheme 在低速率（默认 3
    // grapheme/秒）下也能感受到稳定的"打字机"节奏，而不是间歇性蹦出
    // 整块。在高速率下也不会因为 tick 太密把主线程拖累——onTick 回调
    // 本身只做轻量切片。
    _drainTimer = Timer(const Duration(milliseconds: 16), () {
      _drainTimer = null;
      if (_disposed) {
        return;
      }
      // 由调用方通过 renderableGraphemeCount + sanitized 文本切片驱动新一
      // 轮显示。
      try {
        _onTick();
      } catch (_) {
        // ignore
      }
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
    final deadline = maxWait == null ? null : DateTime.now().add(maxWait);
    while (hasPending) {
      if (deadline != null && DateTime.now().isAfter(deadline)) {
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
  }) : _maxCardsPerSecond = maxCardsPerSecond,
       _onCardEmitted = onCardEmitted,
       _budget = maxCardsPerSecond.toDouble(),
       _lastTickAt = DateTime.now();

  /// 每秒允许被「展示」的新卡片数；<=0 视为关闭限速。
  /// 会话级节流弹窗 Apply 后可立即更新当前活跃 throttle。
  int _maxCardsPerSecond;
  int get maxCardsPerSecond => _maxCardsPerSecond;
  set maxCardsPerSecond(int next) {
    if (next == _maxCardsPerSecond) return;
    _maxCardsPerSecond = next;
    if (_budget > next) _budget = next.toDouble();
  }

  /// 2026-05-19 — 会话级运行时开关：会话弹窗 Apply 关闭节流时，控制器
  /// 把 `false` 推下来；下次 [tryAcquire] 直接通过 + 排空积压。
  bool? _enabledOverride;
  set enabledOverride(bool? next) {
    if (next == _enabledOverride) return;
    _enabledOverride = next;
    if (next == false && _pending.isNotEmpty && !_disposed) {
      // 立刻放行所有积压回调。
      final pending = List<VoidCallback>.from(_pending);
      _pending.clear();
      for (final cb in pending) {
        try {
          cb();
        } catch (_) {
          // ignore
        }
      }
      try {
        _onCardEmitted();
      } catch (_) {
        // ignore
      }
    }
  }

  final void Function() _onCardEmitted;
  final List<VoidCallback> _pending = <VoidCallback>[];
  Timer? _drainTimer;
  bool _disposed = false;
  double _budget;
  DateTime _lastTickAt;

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
    _pending.add(create);
    _scheduleDrain();
    return false;
  }

  void _refill() {
    final now = DateTime.now();
    final elapsedMicros = now.difference(_lastTickAt).inMicroseconds;
    if (elapsedMicros <= 0) {
      return;
    }
    _budget += elapsedMicros * maxCardsPerSecond / 1000000.0;
    if (_budget > maxCardsPerSecond) {
      _budget = maxCardsPerSecond.toDouble();
    }
    _lastTickAt = now;
  }

  void _scheduleDrain() {
    if (_drainTimer != null || _disposed) {
      return;
    }
    final tokensNeeded = (1 - _budget).clamp(0, 1).toDouble();
    final waitSeconds = tokensNeeded <= 0
        ? 0.0
        : tokensNeeded / maxCardsPerSecond;
    final waitMs = (waitSeconds * 1000).ceil().clamp(8, 1000);
    _drainTimer = Timer(Duration(milliseconds: waitMs), _drainOnce);
  }

  void _drainOnce() {
    _drainTimer = null;
    if (_disposed) {
      return;
    }
    _refill();
    var emitted = 0;
    while (_pending.isNotEmpty && _budget >= 1) {
      final cb = _pending.removeAt(0);
      _budget -= 1;
      try {
        cb();
        emitted++;
      } catch (_) {
        // ignore individual callback failures; queue remains intact.
      }
    }
    if (emitted > 0) {
      try {
        _onCardEmitted();
      } catch (_) {
        // ignore
      }
    }
    if (_pending.isNotEmpty) {
      _scheduleDrain();
    }
  }

  /// 立即释放：把所有积压回调一次性追加，然后置位 disposed 防止 Timer
  /// 再触发。流结束 / 取消时调用。
  void releaseAll() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    if (_pending.isEmpty) {
      return;
    }
    final pending = List<VoidCallback>.from(_pending);
    _pending.clear();
    for (final cb in pending) {
      try {
        cb();
      } catch (_) {
        // ignore
      }
    }
    try {
      _onCardEmitted();
    } catch (_) {
      // ignore
    }
  }

  void cancelPending() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    _pending.clear();
  }
}

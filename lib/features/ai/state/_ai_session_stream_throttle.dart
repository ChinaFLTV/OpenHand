/// Stream output back-pressure helpers for AiSessionController.
///
/// 2026-05-17 — 用户反馈：AI 在短时间内回吐大量字符或连续追加多张消息卡
/// 片时，会触发 UI 端布局抖动 / 主线程卡顿 / 列表上下弹跳等糟糕体验。
/// 本文件提供两个轻量的令牌桶限速器，用于在流式追加层做背压：
///
///   * [_StreamCharThrottle] —— 限制每秒向当前流式卡片 *显示* 的字符数。
///   * [_StreamCardThrottle] —— 限制每秒向当前会话新创建的消息卡片数。
///
/// 两个限速器都支持「关闭」（rate <= 0）。设计目标：
///   - 单 Timer，复杂度 O(1)；
///   - 不阻塞 isolate；
///   - dispose 时不会泄漏待执行回调。
part of '../ai_session_controller.dart';

/// 显示侧字符级令牌桶限速器。
///
/// 调用方在拿到完整 sanitized 文本后通过 [renderableLength] 询问当前
/// 时刻最多可对外渲染多少字符；剩余字符会随着时间推进自动放开。
/// 限速器内部维护一个 ~33ms 节奏的周期 Timer，在余量未释放时持续触发
/// 调用方的 [_onTick] 回调，驱动 UI 把后续字符滚动出来。
/// 流结束时调用 [release] 即可立刻放开全部预算。
class _StreamCharThrottle {
  _StreamCharThrottle({
    required this.maxCharsPerSecond,
    required void Function() onTick,
  }) : _onTick = onTick,
       _budget = maxCharsPerSecond.toDouble(),
       _lastTickAt = DateTime.now();

  /// 每秒允许被「展示」的字符数；<=0 视为关闭限速。
  final int maxCharsPerSecond;

  final void Function() _onTick;
  Timer? _drainTimer;
  bool _disposed = false;
  double _budget;
  int _emittedChars = 0;
  int _lastKnownTotal = 0;
  DateTime _lastTickAt;

  bool get isEnabled => maxCharsPerSecond > 0;

  /// 推进时钟并补充令牌，返回当前允许「显示」的最大字符数。
  int renderableLength(int totalSanitizedLength) {
    _lastKnownTotal = totalSanitizedLength;
    if (!isEnabled || _disposed) {
      final granted = totalSanitizedLength - _emittedChars;
      _emittedChars = totalSanitizedLength;
      if (granted > 0) _recordEmission(granted);
      return totalSanitizedLength;
    }
    if (totalSanitizedLength <= _emittedChars) {
      return _emittedChars;
    }
    _refill();
    final allowance = _budget.floor();
    if (allowance > 0) {
      final pending = totalSanitizedLength - _emittedChars;
      final granted = allowance >= pending ? pending : allowance;
      _emittedChars += granted;
      _budget -= granted;
      _recordEmission(granted);
    }
    if (_emittedChars < totalSanitizedLength) {
      _scheduleDrain();
    }
    return _emittedChars;
  }

  // ── 吞吐采样：保留最近 [_kThroughputBuckets] 秒的字符放出量，给
  // TopBar 仪表盘画曲线。每秒一个桶，O(1) 更新。
  static const int _kThroughputBuckets = 30;
  final List<int> _throughputBuckets = List<int>.filled(_kThroughputBuckets, 0);
  int _throughputBucketSecond = 0;

  void _recordEmission(int chars) {
    if (chars <= 0) return;
    final nowSec =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_throughputBucketSecond == 0) {
      _throughputBucketSecond = nowSec;
      _throughputBuckets[0] = chars;
      return;
    }
    final delta = nowSec - _throughputBucketSecond;
    if (delta <= 0) {
      _throughputBuckets[0] += chars;
      return;
    }
    if (delta >= _kThroughputBuckets) {
      for (var i = 0; i < _kThroughputBuckets; i++) {
        _throughputBuckets[i] = 0;
      }
    } else {
      // 把现有桶向后挪 delta 位，老的丢失，新桶清零。
      for (var i = _kThroughputBuckets - 1; i >= delta; i--) {
        _throughputBuckets[i] = _throughputBuckets[i - delta];
      }
      for (var i = 0; i < delta; i++) {
        _throughputBuckets[i] = 0;
      }
    }
    _throughputBucketSecond = nowSec;
    _throughputBuckets[0] = chars;
  }

  /// 最近 [_kThroughputBuckets] 秒的每秒字符吞吐快照，桶 0 = 当前秒，
  /// 越往后越旧。返回不可变副本，UI 可直接喂给 painter。
  List<int> throughputSnapshot() =>
      List<int>.unmodifiable(_throughputBuckets);

  /// 当前秒（桶 0）累计已放出的字符数。
  int get currentSecondEmitted => _throughputBuckets[0];

  void _refill() {
    final now = DateTime.now();
    final elapsedMicros = now.difference(_lastTickAt).inMicroseconds;
    if (elapsedMicros <= 0) {
      return;
    }
    _budget += elapsedMicros * maxCharsPerSecond / 1000000.0;
    if (_budget > maxCharsPerSecond) {
      _budget = maxCharsPerSecond.toDouble();
    }
    _lastTickAt = now;
  }

  void _scheduleDrain() {
    if (_drainTimer != null || _disposed) {
      return;
    }
    // 60fps 节奏：16ms 一次 tick，让字符在低速率（默认 3 字符/秒）下也
    // 能感受到稳定的"打字机"节奏，而不是间歇性蹦出整块。在高速率下也
    // 不会因为 tick 太密把主线程拖累——onTick 回调本身只做轻量切片。
    _drainTimer = Timer(const Duration(milliseconds: 16), () {
      _drainTimer = null;
      if (_disposed) {
        return;
      }
      // 由调用方通过 renderableLength + sanitized 文本切片驱动新一轮显示。
      try {
        _onTick();
      } catch (_) {
        // ignore
      }
      if (_emittedChars < _lastKnownTotal) {
        _scheduleDrain();
      }
    });
  }

  /// 当前距离释放下一个字符还差多少（[0, 1] 区间，1 = 即将释放）。
  /// 用于给 UI 渲染半透明的"待出场字符"，让低速率下的渲染拥有连续动画。
  double get partialCharProgress {
    if (!isEnabled) return 1;
    final clamped = _budget.clamp(0.0, 1.0);
    return clamped;
  }

  /// 立刻释放剩余预算，供流结束 / 取消时把全部内容一次性显式刷出。
  void release() {
    _disposed = true;
    _drainTimer?.cancel();
    _drainTimer = null;
    _emittedChars = 1 << 30;
    _budget = (1 << 30).toDouble();
  }

  /// 当前是否还有 pending 字符未被释放给 UI（仅在 isEnabled=true 时有意义）。
  bool get hasPending => isEnabled && !_disposed && _emittedChars < _lastKnownTotal;

  /// 软排空：异步等待直到 _emittedChars 追上 _lastKnownTotal 或超过
  /// [maxWait]。流结束后调用，让残余字符仍按节流速率均匀放出，避免
  /// 「最后一刻一次性 burst 出全部内容」的糟糕观感。
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
    required this.maxCardsPerSecond,
    required void Function() onCardEmitted,
  }) : _onCardEmitted = onCardEmitted,
       _budget = maxCardsPerSecond.toDouble(),
       _lastTickAt = DateTime.now();

  /// 每秒允许被「展示」的新卡片数；<=0 视为关闭限速。
  final int maxCardsPerSecond;

  final void Function() _onCardEmitted;
  final List<VoidCallback> _pending = <VoidCallback>[];
  Timer? _drainTimer;
  bool _disposed = false;
  double _budget;
  DateTime _lastTickAt;

  bool get isEnabled => maxCardsPerSecond > 0;

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
}

import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A refined bouncing scroll physics that preserves the premium elastic feel
/// while preventing the visible "messages bounce up then snap back" jitter on
/// thread-template sessions.
///
/// Key differences from stock [BouncingScrollPhysics]:
/// - **Tighter friction** (0.52 → 0.32) so the content cannot travel as
///   far past the edges.
/// - **Custom monotonic overscroll return** via
///   [_OpenHandRubberBandSimulation]. The framework's
///   [BouncingScrollSimulation] uses a heavy-damping
///   [ScrollSpringSimulation] that still overshoots by 20-50 px whenever
///   the user releases with non-zero velocity into overscroll (e.g. a
///   trackpad fling that crosses the edge), and additionally gets rebuilt
///   via repeated `goBallistic(0)` calls while `position.outOfRange`,
///   producing non-monotonic intermediate values (the data showed
///   px=-1.07 → -7.57 → -4.36 inside the top overscroll zone — a
///   drift that the user perceived as the "messages rapidly bouncing").
///   Our override returns a [Simulation] that always approaches the
///   edge monotonically (single exponential decay) so the content can
///   never drift back into overscroll on its own.
///
/// Usage:
/// ```dart
/// ListView(
///   physics: const OpenHandBouncingScrollPhysics(
///     parent: AlwaysScrollableScrollPhysics(),
///   ),
/// )
/// ```
class OpenHandBouncingScrollPhysics extends BouncingScrollPhysics {
  const OpenHandBouncingScrollPhysics({super.parent});

  @override
  OpenHandBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return OpenHandBouncingScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 0.5, stiffness: 180.0, damping: 24.0);

  /// More aggressive friction than the default (0.52 → 0.32).
  ///
  /// [overscrollFraction] is how far we've overscrolled relative to the
  /// viewport size (0.0 = at edge, 1.0 = overscrolled by a full viewport).
  /// Returning a *smaller* value means each gesture pixel moves the content
  /// *less* in the overscroll zone, so the maximum practical overscroll
  /// distance is naturally limited without any hard boundary clamping.
  @override
  double frictionFactor(double overscrollFraction) =>
      0.32 * math.pow(1 - overscrollFraction, 2);

  /// 2026-06-06（线程模板抽搐 bug 真凶）：替换 framework 的
  /// [BouncingScrollSimulation]（内部串联 FrictionSimulation +
  /// [ScrollSpringSimulation]，在 outOfRange 区间会被反复 `goBallistic(0)`
  /// 重建，重建时把当前 px 当作新 simulation 的 position、velocity 锁 0，
  /// 导致橡皮筋阶段在 px ≈ 0 附近出现非单调的"先往反方向滑再回弹"——即用户
  /// 看到的"消息快速上下小幅弹跳"。这里直接返回一个纯指数衰减的
  /// [_OpenHandRubberBandSimulation]，position 严格单调逼近 leadingExtent /
  /// trailingExtent，没有过冲、没有重建、没有第二次振荡。
  ///
  /// 仍保留 BouncingScrollPhysics 的 friction 行为（拖拽期间 `frictionFactor`
  /// 起作用，把手指输入减弱），所以 iOS 风格的"出 overscroll 区能跟手"
  /// 手感不变；回弹阶段被替换。
  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    // DEBUG 2026-06-06：每次 createBallisticSimulation 都打点，定位是否被反复重建
    debugPrint(
      '[OHPhysics#createBS] px=${position.pixels.toStringAsFixed(2)} '
      'min=${position.minScrollExtent.toStringAsFixed(2)} '
      'max=${position.maxScrollExtent.toStringAsFixed(2)} '
      'v=${velocity.toStringAsFixed(2)} '
      'outOfRange=${position.outOfRange}',
    );
    if (velocity.abs() < tolerance.velocity && !position.outOfRange) {
      return null;
    }
    final double leading = position.minScrollExtent;
    final double trailing = position.maxScrollExtent;
    final double px = position.pixels;
    if (px < leading) {
      return _OpenHandRubberBandSimulation(
        position: px,
        target: leading,
        velocity: velocity,
        kind: _OpenHandRubberBandKind.underscroll,
      );
    }
    if (px > trailing) {
      return _OpenHandRubberBandSimulation(
        position: px,
        target: trailing,
        velocity: velocity,
        kind: _OpenHandRubberBandKind.overscroll,
      );
    }
    // In-range with high velocity：先用 framework 自带的 friction 模型把它
    // 衰减到边界附近，再让 [_OpenHandRubberBandSimulation] 单调接管回弹。
    // 保留 fling 的"惯性"手感但消除 spring 重建造成的二次振荡。
    final FrictionSimulation friction = FrictionSimulation(
      0.135 * (velocity.isNegative ? 1.0 : 1.0),
      px,
      velocity,
    );
    final double finalX = friction.finalX;
    if (finalX < leading) {
      final double tAtEdge = friction.timeAtX(leading);
      return _OpenHandFrictionToRubberBand(
        friction: friction,
        rubber: _OpenHandRubberBandSimulation(
          position: leading,
          target: leading,
          velocity: friction.dx(tAtEdge).clamp(-5000.0, 5000.0),
          kind: _OpenHandRubberBandKind.underscroll,
        ),
        switchTime: tAtEdge,
      );
    }
    if (finalX > trailing) {
      final double tAtEdge = friction.timeAtX(trailing);
      return _OpenHandFrictionToRubberBand(
        friction: friction,
        rubber: _OpenHandRubberBandSimulation(
          position: trailing,
          target: trailing,
          velocity: friction.dx(tAtEdge).clamp(-5000.0, 5000.0),
          kind: _OpenHandRubberBandKind.overscroll,
        ),
        switchTime: tAtEdge,
      );
    }
    return friction;
  }
}

enum _OpenHandRubberBandKind { underscroll, overscroll }

/// 单调指数衰减的橡皮筋 Simulation。
///
/// x(t) = target + (position - target) * exp(-t / tau) * cos(0)
///
/// 严格单调向 [target] 逼近（无过冲、无振荡），回弹时间常数 [tau] 选
/// 280 ms —— 与项目内 [kCardMotionDurationExpand] 保持同一档 Q 弹节奏。
class _OpenHandRubberBandSimulation extends Simulation {
  _OpenHandRubberBandSimulation({
    required this.position,
    required this.target,
    required double velocity,
    required this.kind,
    this.tau = 0.28,
  })  : assert(tau > 0.0),
        _initialDeviation = position - target {
    // DEBUG 2026-06-06：每次 simulation 实例化打点
    debugPrint(
      '[OHPhysics#sim-new] kind=$kind '
      'pos=${position.toStringAsFixed(2)} '
      'target=${target.toStringAsFixed(2)} '
      'v_in=${velocity.toStringAsFixed(2)} '
      'deviation=${_initialDeviation.toStringAsFixed(2)}',
    );
  }

  final double position;
  final double target;
  // 仅用于调试 / 日志扩展位，不影响 x(t)。
  final _OpenHandRubberBandKind kind;
  final double tau;
  final double _initialDeviation;

  @override
  double x(double time) =>
      target + _initialDeviation * math.exp(-time / tau);

  @override
  double dx(double time) =>
      -_initialDeviation / tau * math.exp(-time / tau);

  @override
  bool isDone(double time) =>
      (x(time) - target).abs() < 0.5 && dx(time).abs() < 0.5;
}

/// 串联 FrictionSimulation（fling 惯性阶段）+ 指数衰减橡胶筋（回弹阶段）。
/// 严格遵守 [_OpenHandRubberBandSimulation] 的单调性质，回弹阶段零过冲。
class _OpenHandFrictionToRubberBand extends Simulation {
  _OpenHandFrictionToRubberBand({
    required this.friction,
    required this.rubber,
    required this.switchTime,
  })  : assert(switchTime >= 0.0);

  final FrictionSimulation friction;
  final _OpenHandRubberBandSimulation rubber;
  final double switchTime;

  @override
  double x(double time) =>
      time < switchTime ? friction.x(time) : rubber.x(time - switchTime);

  @override
  double dx(double time) =>
      time < switchTime ? friction.dx(time) : rubber.dx(time - switchTime);

  @override
  bool isDone(double time) =>
      time < switchTime ? friction.isDone(time) : rubber.isDone(time - switchTime);
}

/// 稳定 maxScrollExtent 收缩的 ScrollPosition。
///
/// 问题背景（消息列表抽搐 bug）：用户超用力下滑过冲到 overscroll 区后，
/// BouncingScrollPhysics 缓慢把 pixels 回拉到 maxScrollExtent；同时
/// cacheExtent 边界扫过靠上的 bubble，触发 dispose + rebuild，重新解析
/// markdown 得到与原值略小的几何（几像素差），SliverList 调用
/// applyContentDimensions 收缩 maxScrollExtent。每 ~50 ms 缩 7~8 px，
/// 弹簧看到的 overscroll 距离 d2b 持续变小并触发反向修正，形成视觉抽搐。
///
/// 修复思路：当 pixels 处于 overscroll 区（pixels > 旧 maxScrollExtent）
/// 且新 maxScrollExtent 变化时，把 pixels 同步加上同样的 delta。等价于：
/// 把 SliverList 的内容增高/缩水透明地反映到滚动偏移上，保持 overscroll
/// 距离恒定。视觉效果是：已显示的 bubble 在屏幕上的位置完全不变，
/// 弹簧也不会看到「目标突然变近/变远」的扰动。
class _StableMaxExtentScrollPosition extends ScrollPositionWithSingleContext {
  _StableMaxExtentScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  /// 连续拒绝瞬态近零 extent 更新的次数，防止无限拒绝。
  int _transientRejectCount = 0;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasPixels &&
        hasContentDimensions &&
        maxScrollExtent != this.maxScrollExtent) {
      final double delta = maxScrollExtent - this.maxScrollExtent;
      final double oldMax = this.maxScrollExtent;
      // DEBUG 2026-06-06：只有当 maxScrollExtent 变化 > 1 px 时打点（忽略浮点抖动）
      if (delta.abs() > 1.0) {
        debugPrint(
          '[OHPhysics#applyCD] oldMax=$oldMax newMax=$maxScrollExtent '
          'd=${delta.toStringAsFixed(2)} '
          'px=${pixels.toStringAsFixed(2)} '
          'act=${activity.runtimeType} '
          'dir=$userScrollDirection',
        );
      }
      // 2026-06-06（线程模板抽搐 bug）：drag 守卫只覆盖 overscroll 跟随
      // 分支（pixels > oldMax），让用户的 drag 意图不被 correctPixels 抢走；
      // 收缩分支（delta < -0.5 && pixels > maxScrollExtent）**必须无条件
      // 执行**，否则 pixels 会留在 > newMax 状态，super 内部的
      // applyNewDimensions → IdleScrollActivity.goBallistic(0) 看到
      // outOfRange=true 就反复启动 BouncingScrollSimulation 拉回 pixels，
      // 与用户慢速上滑形成 ~50ms 正反馈，肉眼呈"快速小幅上下弹跳"。
      final bool userDragging = activity is DragScrollActivity ||
          userScrollDirection != ScrollDirection.idle;
      if (pixels > oldMax) {
        // 处于 overscroll 区：保持 overscroll 距离不变，避免弹簧看到
        // "目标突然移动" 而产生抽搐。drag 期间不干扰用户 overscroll 手势。
        if (!userDragging) {
          correctPixels(pixels + delta);
        }
      } else if (delta < -0.5 && pixels > maxScrollExtent) {
        // maxScrollExtent 收缩到当前 pixels 之下（例如 HTML 气泡高度
        // 测量值变小）：按比例缩放 pixels，维持用户的相对阅读位置，
        // 避免被 Flutter 框架 clamp 到底部造成"突然滑回最新消息"。
        //
        // 瞬态近零 extent（如 576→8）是布局中间态产物，不是真实内容
        // 收缩。放行会导致 pixels 被 clamp 到 ~0，扩展回 576 后用户
        // 位置已丢失，被迫重新滚到底 → 再次 overscroll → 循环振荡。
        // 连续拒绝超过 3 帧则放行，防止真实清空内容时死循环。
        if (maxScrollExtent < 50.0 && oldMax > 100.0) {
          _transientRejectCount++;
          if (_transientRejectCount <= 3) {
            return false;
          }
        }
        _transientRejectCount = 0;
        if (oldMax > 0) {
          final double ratio = (pixels / oldMax).clamp(0.0, 1.0);
          final double newPixels =
              (ratio * maxScrollExtent).clamp(0.0, maxScrollExtent);
          correctPixels(newPixels);
        }
      } else {
        _transientRejectCount = 0;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// 与 [OpenHandBouncingScrollPhysics] 搭配的 ScrollController，
/// 通过自定义 [_StableMaxExtentScrollPosition] 防止 overscroll 期间
/// `maxScrollExtent` 收缩引发的视觉抽搐。
class OpenHandStableScrollController extends ScrollController {
  OpenHandStableScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _StableMaxExtentScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

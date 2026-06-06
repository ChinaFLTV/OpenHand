import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A refined bouncing scroll physics that preserves the premium elastic feel
/// while preventing the content from overscrolling too far.
///
/// Key differences from stock [BouncingScrollPhysics]:
/// - **Higher friction**: Overscroll resistance is ~40 % stronger so the
///   content cannot travel as far past the edges, even on fast flings.
/// - **Stiffer spring**: Settles 40-60 % faster than the default iOS spring,
///   giving a snappy, premium feel with minimal secondary oscillation.
///
/// These two tweaks together keep the "Q-bounce" alive while preventing the
/// large displacement that triggers repaint-boundary ghosting on macOS.
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

  /// A stiffer, more damped spring than the stock iOS default
  /// (mass 0.5, stiffness 100, damping ≈14).
  ///
  /// Higher stiffness → snappier return.
  /// Higher damping  → less oscillation / fewer secondary bounces.
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
      // 2026-06-06（线程模板抽搐 bug）：用户主动 drag 期间绝对不能让
      // correctPixels 干扰视口位置 —— contentDimensions 变化是异步回流
      // 产物（HTML 气泡 re-measure / markdown 高亮 / cacheExtent 扫过
      // 新条目），而 drag 时 ScrollController 的 overscroll 弹簧正按
      // 用户意图驱动 pixels；此刻 correctPixels 会让 drag 看到"目标
      // 突然移动"，与 drag 形成 ~50ms 周期正反馈，肉眼呈"小幅上下弹跳"。
      // 守卫同时覆盖两个纠偏分支（overscroll 跟随 + 读顶部 content 收缩
      // 比例缩放）。drag 结束后下一帧守卫自动放行，super 仍走，行为完全保持。
      final bool userDragging = activity is DragScrollActivity ||
          userScrollDirection != ScrollDirection.idle;
      if (!userDragging) {
        if (pixels > oldMax) {
          // 处于 overscroll 区：保持 overscroll 距离不变，避免弹簧看到
          // "目标突然移动" 而产生抽搐。
          correctPixels(pixels + delta);
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

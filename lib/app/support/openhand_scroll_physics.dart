import 'dart:math' as math;

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

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasPixels &&
        hasContentDimensions &&
        maxScrollExtent != this.maxScrollExtent) {
      final double delta = maxScrollExtent - this.maxScrollExtent;
      if (pixels > this.maxScrollExtent) {
        // 处于 overscroll 区：保持 overscroll 距离不变，避免弹簧看到
        // "目标突然移动" 而产生抽搐。
        correctPixels(pixels + delta);
      } else if (delta < -0.5 && pixels > maxScrollExtent) {
        // maxScrollExtent 收缩到当前 pixels 之下（例如 HTML 气泡高度
        // 测量值变小）：按比例缩放 pixels，维持用户的相对阅读位置，
        // 避免被 Flutter 框架 clamp 到底部造成"突然滑回最新消息"。
        final double oldMax = this.maxScrollExtent;
        if (oldMax > 0) {
          final double ratio = (pixels / oldMax).clamp(0.0, 1.0);
          final double newPixels = (ratio * maxScrollExtent).clamp(0.0, maxScrollExtent);
          debugPrint('[SCROLL-PHYSICS] maxExt shrunk $oldMax→$maxScrollExtent, px $pixels→$newPixels (ratio=${ratio.toStringAsFixed(3)})');
          correctPixels(newPixels);
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

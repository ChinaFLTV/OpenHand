import 'package:flutter/widgets.dart';

/// 线程会话窗口专用的稳定 maxScrollExtent ScrollPosition。
///
/// 2026-06-06（线程模板抽搐 bug 推倒重做）：线程会话窗口的所有过渡动画
/// 已全部下线（_home_transcript 内的 entrance / stagger / settlePrependedHeight
/// 多帧循环、`_HtmlBubbleWebView` 的 AnimatedSize Q 弹、home page 的
/// `animateTo` 全部换 jumpTo）。本类继续保留的唯一职责是：
/// 缓存区边界扫过上方 bubble 时，SliverList 调用 `applyContentDimensions`
/// 把 `maxScrollExtent` 收缩几像素时，**不让**用户的视口位置被框架 clamp
/// 到底部造成"突然滑回最新消息"。
///
/// 线程会话窗口的物理改用 [ClampingScrollPhysics]（无 overscroll、无
/// rubber-band、无 Q 弹），用户与代码再不需要为 overshoot / 反复
/// `goBallistic(0)` 重建 BouncingScrollSimulation 兜底。
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
          // "目标突然移动" 而产生抽搐。drag 期间不干扰用户 overscroll 手势。
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

/// 与 [ClampingScrollPhysics] 搭配的 ScrollController，
/// 通过自定义 [_StableMaxExtentScrollPosition] 防止 `maxScrollExtent`
/// 收缩时用户的相对阅读位置被 clamp 掉。
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

/// 线程会话窗口专用的滚动物理：ClampingScrollPhysics（无 overscroll /
/// 无 rubber-band / 无 Q 弹），始终可滚。搭配
/// [OpenHandStableScrollController] 使用可获得 [ScrollPosition] 层
/// 的 maxScrollExtent 收缩保护。
const ClampingScrollPhysics kOpenHandClampingPhysics =
    ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

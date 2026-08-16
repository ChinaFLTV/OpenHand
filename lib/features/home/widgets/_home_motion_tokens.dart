part of '../openhand_home_page.dart';

/// 卡片折叠/展开动画 motion token —— 仓库唯一来源。
///
/// 所有 transcript 内消息卡片（`_MessageBubble`、`_ReasoningMetaRow`、
/// `_ToolCallMetaRow`、`_SelfLearningCard`、`_CompressionCheckpointBody` 等）
/// 的 `AnimatedSize` / `AnimatedRotation` / `AnimatedDefaultTextStyle` 时长
/// 与曲线全部从这里读取，禁止再在调用点写裸 `Duration(milliseconds: …)` /
/// `kOpenHandSwitchInCurve`。
///
/// 设计依据：design.md Bug 5 / requirements.md 6.1—6.3。
///   * 时长 ∈ [220ms, 320ms]，按 expand / collapse 方向各自固定。
///   * 曲线统一为 `Cubic(0.22, 1.22, 0.36, 1)`（轻微 overshoot 的 Q 弹回弹）。
///   * 阴影、边框等装饰插值使用同曲线的有界版本，避免超调产生非法数值。
///   * 全局禁动或当前 [TickerMode] 暂停时降为 `Duration.zero`。

const Duration kCardMotionDurationExpand = Duration(milliseconds: 280);
const Duration kCardMotionDurationCollapse = Duration(milliseconds: 220);
const Curve kCardMotionCurve = Cubic(0.22, 1.22, 0.36, 1);
const Curve kCardDecorationMotionCurve = OpenHandBoundedCurve(kCardMotionCurve);

/// 单一来源：根据展开方向返回卡片折叠/展开动画时长。
///
/// 当用户在系统层启用「减少动画」或当前 [TickerMode] 暂停时直接返回
/// `Duration.zero`，与共享动效偏好保持一致。
Duration cardMotionDurationFor(
  BuildContext context, {
  required bool expanding,
}) {
  return openHandMotionDuration(
    context,
    expanding ? kCardMotionDurationExpand : kCardMotionDurationCollapse,
  );
}

Widget maybeAnimatedSize({
  Key? key,
  required Duration duration,
  required Curve curve,
  required AlignmentGeometry alignment,
  required Widget child,
}) {
  // RenderAnimatedSize may synchronously restart a zero-duration animation
  // during layout and trip "mutated in performLayout"; skip the render object.
  if (duration <= Duration.zero) {
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }
  return AnimatedSize(
    key: key,
    duration: duration,
    curve: curve,
    alignment: alignment,
    child: child,
  );
}

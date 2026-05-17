part of '../openhand_home_page.dart';

/// 卡片折叠/展开动画 motion token —— 仓库唯一来源。
///
/// 所有 transcript 内消息卡片（`_MessageBubble`、`_ReasoningMetaRow`、
/// `_ToolCallMetaRow`、`_SelfLearningCard`、`_CompressionCheckpointBody` 等）
/// 的 `AnimatedSize` / `AnimatedRotation` / `AnimatedDefaultTextStyle` 时长
/// 与曲线全部从这里读取，禁止再在调用点写裸 `Duration(milliseconds: …)` /
/// `Curves.easeOutCubic`。
///
/// 设计依据：design.md Bug 5 / requirements.md 6.1—6.3。
///   * 时长 ∈ [220ms, 320ms]，按 expand / collapse 方向各自固定。
///   * 曲线统一为 `Cubic(0.22, 1.22, 0.36, 1)`（轻微 overshoot 的 Q 弹回弹）。
///   * `MediaQuery.disableAnimationsOf(context) == true` 时降为
///     `Duration.zero`（与现有「减少动画」语义保持一致）。

const Duration kCardMotionDurationExpand = Duration(milliseconds: 280);
const Duration kCardMotionDurationCollapse = Duration(milliseconds: 220);
const Curve kCardMotionCurve = Cubic(0.22, 1.22, 0.36, 1);

/// 单一来源：根据展开方向返回卡片折叠/展开动画时长。
///
/// 当用户在系统层启用「减少动画」（`MediaQuery.disableAnimationsOf`）时
/// 直接返回 `Duration.zero`，与原有 `_reasoningBodyAnimDuration` 语义
/// 保持一致。
Duration cardMotionDurationFor(
  BuildContext context, {
  required bool expanding,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return Duration.zero;
  }
  return expanding ? kCardMotionDurationExpand : kCardMotionDurationCollapse;
}

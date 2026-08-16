import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

/// 全局共享的切换曲线 —— 进场用 easeOutCubic，退场用 easeInCubic。
///
/// 此前 30+ 弹窗文件各自定义 `_kSwitchInCurve = Curves.easeOutCubic` /
/// `_kSwitchOutCurve = Curves.easeInCubic`，改一档要翻遍全库。这里收敛为
/// 单一来源，与 [DialogAnimationCurve.easeOutCubic] 的 curve/reverseCurve
/// 保持一致。
const Curve kOpenHandSwitchInCurve = Curves.easeOutCubic;
const Curve kOpenHandSwitchOutCurve = Curves.easeInCubic;

/// 全局共享的过渡曲线 —— 用于 AnimatedSwitcher / AnimatedDefaultTextStyle
/// 等需要单一曲线（非进出分离）的场景。
const Curve kOpenHandTransitionCurve = Curves.easeOutCubic;
const Curve kOpenHandEmphasizedTransitionCurve = Curves.easeInOutCubic;

/// 全局共享的进场曲线 —— 带自然回弹的 overshoot，用于弹窗进场、列表项入场、
/// 胶囊切换等需要 Q 弹出场感的场景。
const Curve kOpenHandEntranceCurve = Curves.easeOutBack;

enum OpenHandMotionSettingsScope { dialog, menu, page, panel, chip, listItem }

bool openHandReduceMotionOf(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) == true;
}

bool openHandTickerMotionEnabled(BuildContext context) {
  return !openHandReduceMotionOf(context) &&
      TickerMode.valuesOf(context).enabled;
}

Duration openHandMotionDuration(BuildContext context, Duration duration) {
  if (duration <= Duration.zero || !openHandTickerMotionEnabled(context)) {
    return Duration.zero;
  }
  return duration;
}

Duration openHandMotionDurationMs(BuildContext context, int milliseconds) {
  if (milliseconds <= 0 || !openHandTickerMotionEnabled(context)) {
    return Duration.zero;
  }
  return Duration(milliseconds: milliseconds);
}

bool openHandMotionDisabled(DialogAnimationSettings settings) {
  return settings.disablesAnimation;
}

DialogAnimationSettings openHandMotionSettingsOf(
  BuildContext context,
  OpenHandMotionSettingsScope scope, {
  DialogAnimationSettings? override,
  bool respectReduceMotion = true,
  bool respectTickerMode = true,
}) {
  if ((respectReduceMotion && openHandReduceMotionOf(context)) ||
      (respectTickerMode && !TickerMode.valuesOf(context).enabled)) {
    return OpenHandMotionDefaults.disabled;
  }
  return (override ?? openHandMotionSettingsFallbackOf(context, scope))
      .normalized();
}

DialogAnimationSettings openHandMotionSettingsFallbackOf(
  BuildContext context,
  OpenHandMotionSettingsScope scope,
) {
  try {
    final controller = context.read<SettingsController>();
    return switch (scope) {
      OpenHandMotionSettingsScope.dialog => controller.dialogAnimationSettings,
      OpenHandMotionSettingsScope.menu => controller.menuAnimationSettings,
      OpenHandMotionSettingsScope.page => controller.pageAnimationSettings,
      OpenHandMotionSettingsScope.panel => controller.panelAnimationSettings,
      OpenHandMotionSettingsScope.chip => controller.chipAnimationSettings,
      OpenHandMotionSettingsScope.listItem =>
        controller.listItemAnimationSettings,
    };
  } on ProviderNotFoundException {
    return openHandDefaultMotionSettings(scope);
  }
}

DialogAnimationSettings openHandDefaultMotionSettings(
  OpenHandMotionSettingsScope scope,
) {
  return switch (scope) {
    OpenHandMotionSettingsScope.dialog => OpenHandMotionDefaults.dialog,
    OpenHandMotionSettingsScope.menu => OpenHandMotionDefaults.menu,
    OpenHandMotionSettingsScope.page => OpenHandMotionDefaults.page,
    OpenHandMotionSettingsScope.panel => OpenHandMotionDefaults.panel,
    OpenHandMotionSettingsScope.chip => OpenHandMotionDefaults.chip,
    OpenHandMotionSettingsScope.listItem => OpenHandMotionDefaults.listItem,
  };
}

AnimationStyle openHandAnimationStyle(DialogAnimationSettings settings) {
  if (openHandMotionDisabled(settings)) {
    return AnimationStyle.noAnimation;
  }
  return AnimationStyle(
    duration: settings.entranceDuration,
    reverseDuration: settings.exitDuration,
    curve: settings.curve.curve,
    reverseCurve: settings.curve.reverseCurve,
  );
}

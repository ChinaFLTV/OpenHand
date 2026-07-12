import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

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
  } catch (_) {
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

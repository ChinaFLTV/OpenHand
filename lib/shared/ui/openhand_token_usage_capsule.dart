import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../util/input_value_parsing.dart';
import 'animated_dialog.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'rolling_text.dart';

class OpenHandTokenUsageCapsule extends StatelessWidget {
  const OpenHandTokenUsageCapsule({
    super.key,
    required this.showCacheHitRate,
    required this.cacheHitRatio,
    required this.contextWindowRatio,
    required this.contextWindowTooltip,
    this.anchorKey,
  });

  final bool showCacheHitRate;
  final double cacheHitRatio;
  final double contextWindowRatio;
  final String contextWindowTooltip;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.menu,
    );
    final duration = showCacheHitRate
        ? motionSettings.entranceDuration
        : motionSettings.exitDuration;
    final curve = showCacheHitRate
        ? motionSettings.curve.curve
        : motionSettings.curve.reverseCurve;
    return AnimatedContainer(
      key: anchorKey,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      duration: duration,
      curve: curve,
      decoration: BoxDecoration(
        color: showCacheHitRate
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(
          color: showCacheHitRate
              ? colorScheme.primary.withValues(alpha: 0.38)
              : colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: AnimatedSize(
              alignment: Alignment.centerLeft,
              duration: motionSettings.entranceDuration,
              reverseDuration: motionSettings.exitDuration,
              curve: curve,
              child: AnimatedSwitcher(
                duration: motionSettings.entranceDuration,
                reverseDuration: motionSettings.exitDuration,
                transitionBuilder: (child, animation) =>
                    buildAnimationStyleTransition(
                      animation: animation,
                      settings: motionSettings,
                      child: child,
                    ),
                layoutBuilder: (currentChild, previousChildren) =>
                    buildCollisionSafeAnimatedSwitcherLayout(
                      currentChild,
                      previousChildren,
                      alignment: Alignment.centerLeft,
                      sizeToCurrentChild: true,
                    ),
                child: showCacheHitRate
                    ? Row(
                        key: const ValueKey<bool>(true),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          _OpenHandCacheHitRateBadge(ratio: cacheHitRatio),
                          Container(
                            width: 1,
                            height: 12,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: colorScheme.outlineVariant,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey<bool>(false)),
              ),
            ),
          ),
          Tooltip(
            message: contextWindowTooltip,
            child: OpenHandAnimatedContextUsageRing(
              ratio: contextWindowRatio,
              size: 18,
              strokeWidth: 2.6,
              settings: motionSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class OpenHandAnimatedContextUsageRing extends StatelessWidget {
  const OpenHandAnimatedContextUsageRing({
    super.key,
    required this.ratio,
    required this.size,
    required this.strokeWidth,
    this.settings,
  });

  final double ratio;
  final double size;
  final double strokeWidth;
  final DialogAnimationSettings? settings;

  @override
  Widget build(BuildContext context) {
    final normalizedRatio = finiteUnitInterval(ratio);
    final colorScheme = Theme.of(context).colorScheme;
    final motionSettings =
        settings ??
        openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.menu);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: normalizedRatio),
      duration: motionSettings.entranceDuration,
      curve: motionSettings.curve.curve,
      builder: (context, value, _) => SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          value: value.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.round,
          color: openHandContextWindowUsageColor(colorScheme, normalizedRatio),
          backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}

Color openHandContextWindowUsageColor(ColorScheme colorScheme, double ratio) {
  if (ratio >= 0.90) return colorScheme.error;
  if (ratio >= 0.70) return colorScheme.tertiary;
  return colorScheme.primary;
}

class _OpenHandCacheHitRateBadge extends StatelessWidget {
  const _OpenHandCacheHitRateBadge({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final normalizedRatio = finiteUnitInterval(ratio);
    final intensity = (0.5 + normalizedRatio * 0.5).clamp(0.5, 1.0);
    final foreground = colorScheme.primary;
    final background = colorScheme.primary.withValues(
      alpha: 0.08 + normalizedRatio * 0.12,
    );
    final percent = (normalizedRatio * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_rounded, size: 11, color: foreground),
          const SizedBox(width: 3),
          RollingText(
            text: '$percent',
            style: theme.textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w800,
              color: foreground.withValues(alpha: intensity),
            ),
          ),
          Text(
            '%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: foreground.withValues(alpha: intensity),
            ),
          ),
        ],
      ),
    );
  }
}

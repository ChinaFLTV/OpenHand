import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/util/input_value_parsing.dart';

/// 弹窗进场与退场动画样式。
enum DialogAnimationStyle {
  /// 不播放动画。
  none('none'),

  /// 仅透明度过渡。
  fade('fade'),

  /// 从中心淡入并缩放。
  fadeScale('fade_scale'),

  /// 从下方滑入并淡入。
  slideUp('slide_up'),

  /// 从上方滑入并淡入。
  slideDown('slide_down'),

  /// 从左侧滑入并淡入。
  slideLeft('slide_left'),

  /// 从右侧滑入并淡入。
  slideRight('slide_right'),

  /// 从中心展开并淡入。
  expand('expand'),

  /// 旋转、缩放并淡入。
  rotateScale('rotate_scale'),

  /// 弹性缩放。
  elastic('elastic'),

  /// 带自然回弹的弹簧缩放。
  springScale('spring_scale'),

  /// 绕 X 轴翻转并淡入。
  flipX('flip_x');

  const DialogAnimationStyle(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) {
    return switch (this) {
      DialogAnimationStyle.none => l10n.dialogAnimationStyleNone,
      DialogAnimationStyle.fade => l10n.dialogAnimationStyleFade,
      DialogAnimationStyle.fadeScale => l10n.dialogAnimationStyleFadeScale,
      DialogAnimationStyle.slideUp => l10n.dialogAnimationStyleSlideUp,
      DialogAnimationStyle.slideDown => l10n.dialogAnimationStyleSlideDown,
      DialogAnimationStyle.slideLeft => l10n.dialogAnimationStyleSlideLeft,
      DialogAnimationStyle.slideRight => l10n.dialogAnimationStyleSlideRight,
      DialogAnimationStyle.expand => l10n.dialogAnimationStyleExpand,
      DialogAnimationStyle.rotateScale => l10n.dialogAnimationStyleRotateScale,
      DialogAnimationStyle.elastic => l10n.dialogAnimationStyleElastic,
      DialogAnimationStyle.springScale => l10n.dialogAnimationStyleSpringScale,
      DialogAnimationStyle.flipX => l10n.dialogAnimationStyleFlipX,
    };
  }

  static DialogAnimationStyle fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (style) => style.storageValue,
      fallback: fadeScale,
    );
  }
}

/// 弹窗动画缓动曲线。
enum DialogAnimationCurve {
  easeInOut('ease_in_out'),
  easeOut('ease_out'),
  easeOutCubic('ease_out_cubic'),
  easeInOutCubicEmphasized('ease_in_out_cubic_emphasized'),
  elasticOut('elastic_out'),
  bounceOut('bounce_out'),
  decelerate('decelerate');

  const DialogAnimationCurve(this.storageValue);

  final String storageValue;

  String label(AppLocalizations l10n) {
    return switch (this) {
      DialogAnimationCurve.easeInOut => l10n.dialogAnimationCurveEaseInOut,
      DialogAnimationCurve.easeOut => l10n.dialogAnimationCurveEaseOut,
      DialogAnimationCurve.easeOutCubic =>
        l10n.dialogAnimationCurveEaseOutCubic,
      DialogAnimationCurve.easeInOutCubicEmphasized =>
        l10n.dialogAnimationCurveEaseInOutCubicEmphasized,
      DialogAnimationCurve.elasticOut => l10n.dialogAnimationCurveElasticOut,
      DialogAnimationCurve.bounceOut => l10n.dialogAnimationCurveBounceOut,
      DialogAnimationCurve.decelerate => l10n.dialogAnimationCurveDecelerate,
    };
  }

  Curve get curve => switch (this) {
    DialogAnimationCurve.easeInOut => Curves.easeInOut,
    DialogAnimationCurve.easeOut => Curves.easeOut,
    DialogAnimationCurve.easeOutCubic => Curves.easeOutCubic,
    DialogAnimationCurve.easeInOutCubicEmphasized =>
      Curves.easeInOutCubicEmphasized,
    DialogAnimationCurve.elasticOut => Curves.elasticOut,
    DialogAnimationCurve.bounceOut => Curves.bounceOut,
    DialogAnimationCurve.decelerate => Curves.decelerate,
  };

  Curve get reverseCurve => switch (this) {
    DialogAnimationCurve.easeInOut => Curves.easeInOut,
    DialogAnimationCurve.easeOut => Curves.easeIn,
    DialogAnimationCurve.easeOutCubic => Curves.easeInCubic,
    DialogAnimationCurve.easeInOutCubicEmphasized =>
      Curves.easeInOutCubicEmphasized,
    DialogAnimationCurve.elasticOut => Curves.easeIn,
    DialogAnimationCurve.bounceOut => Curves.easeIn,
    DialogAnimationCurve.decelerate => Curves.decelerate,
  };

  static DialogAnimationCurve fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (curve) => curve.storageValue,
      fallback: easeOutCubic,
    );
  }
}

/// 弹窗动画组合设置。
class DialogAnimationSettings {
  const DialogAnimationSettings({
    this.entranceStyle = DialogAnimationStyle.fadeScale,
    this.exitStyle = DialogAnimationStyle.fadeScale,
    this.durationMs = defaultDurationMs,
    this.curve = DialogAnimationCurve.easeOutCubic,
  });

  factory DialogAnimationSettings.fromJson(
    Map<String, dynamic>? json, {
    int fallbackDurationMs = defaultDurationMs,
  }) {
    if (json == null) return defaults;
    final entranceStyle = DialogAnimationStyle.fromStorage(
      nullIfBlank('${json['entrance_style'] ?? ''}'),
    );
    final exitStyle = DialogAnimationStyle.fromStorage(
      nullIfBlank('${json['exit_style'] ?? ''}'),
    );
    return DialogAnimationSettings(
      entranceStyle: entranceStyle,
      exitStyle: exitStyle,
      durationMs: durationMsFromValue(
        json['duration_ms'],
        fallbackDurationMs: fallbackDurationMs,
      ),
      curve: DialogAnimationCurve.fromStorage(
        nullIfBlank('${json['curve'] ?? ''}'),
      ),
    );
  }

  static const int defaultDurationMs = 360;
  static const int minAnimatedDurationMs = 80;
  static const int maxDurationMs = 1200;
  static const IntValueRange _animatedDurationMsRange = IntValueRange(
    fallback: defaultDurationMs,
    min: minAnimatedDurationMs,
    max: maxDurationMs,
  );
  static const DialogAnimationSettings legacyFadeScale =
      DialogAnimationSettings();
  static const DialogAnimationSettings defaults = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    exitStyle: DialogAnimationStyle.springScale,
  );

  static int durationMsFromValue(
    Object? value, {
    int fallbackDurationMs = defaultDurationMs,
  }) {
    final parsed = optionalIntegralIntFromValue(value);
    final candidate = parsed == null || parsed <= 0
        ? fallbackDurationMs
        : parsed;
    return _animatedDurationMsRange.normalize(candidate);
  }

  static int normalizeDurationMs(int durationMs) =>
      _animatedDurationMsRange.normalize(durationMs);

  final DialogAnimationStyle entranceStyle;
  final DialogAnimationStyle exitStyle;
  final int durationMs;
  final DialogAnimationCurve curve;

  bool get entranceDisabled => entranceStyle == DialogAnimationStyle.none;

  bool get exitDisabled => exitStyle == DialogAnimationStyle.none;

  bool get disablesAnimation => entranceDisabled && exitDisabled;

  /// 持久化的动画时长不受单向禁用影响，重新启用动画时可恢复原时长。
  int get configuredDurationMs => normalizeDurationMs(durationMs);

  int get effectiveDurationMs => disablesAnimation ? 0 : configuredDurationMs;

  int get effectiveEntranceDurationMs =>
      entranceDisabled ? 0 : configuredDurationMs;

  int get effectiveExitDurationMs => exitDisabled ? 0 : configuredDurationMs;

  Duration get duration => Duration(milliseconds: effectiveDurationMs);

  Duration get entranceDuration =>
      Duration(milliseconds: effectiveEntranceDurationMs);

  Duration get exitDuration => Duration(milliseconds: effectiveExitDurationMs);

  DialogAnimationSettings normalized() {
    final normalizedDurationMs = configuredDurationMs;
    if (durationMs == normalizedDurationMs) {
      return this;
    }
    return DialogAnimationSettings(
      entranceStyle: entranceStyle,
      exitStyle: exitStyle,
      durationMs: normalizedDurationMs,
      curve: curve,
    );
  }

  DialogAnimationSettings copyWith({
    DialogAnimationStyle? entranceStyle,
    DialogAnimationStyle? exitStyle,
    int? durationMs,
    DialogAnimationCurve? curve,
  }) {
    return DialogAnimationSettings(
      entranceStyle: entranceStyle ?? this.entranceStyle,
      exitStyle: exitStyle ?? this.exitStyle,
      durationMs: durationMs ?? configuredDurationMs,
      curve: curve ?? this.curve,
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    final normalized = this.normalized();
    return {
      'entrance_style': normalized.entranceStyle.storageValue,
      'exit_style': normalized.exitStyle.storageValue,
      'duration_ms': normalized.durationMs,
      'curve': normalized.curve.storageValue,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DialogAnimationSettings &&
          entranceStyle == other.entranceStyle &&
          exitStyle == other.exitStyle &&
          durationMs == other.durationMs &&
          curve == other.curve;

  @override
  int get hashCode => Object.hash(entranceStyle, exitStyle, durationMs, curve);
}

/// 设置默认值与运行时回退共用的动画预设。
class OpenHandMotionDefaults {
  const OpenHandMotionDefaults._();

  static const DialogAnimationSettings disabled = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.none,
    exitStyle: DialogAnimationStyle.none,
    durationMs: 0,
  );

  static const DialogAnimationSettings dialog = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    exitStyle: DialogAnimationStyle.springScale,
  );

  static const DialogAnimationSettings menu = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    exitStyle: DialogAnimationStyle.springScale,
    durationMs: 260,
  );

  static const DialogAnimationSettings page = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.fade,
    exitStyle: DialogAnimationStyle.fade,
    durationMs: 800,
    curve: DialogAnimationCurve.easeInOutCubicEmphasized,
  );

  static const DialogAnimationSettings panel = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.fade,
    exitStyle: DialogAnimationStyle.fade,
    durationMs: 600,
    curve: DialogAnimationCurve.easeInOutCubicEmphasized,
  );

  static const DialogAnimationSettings chip = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    curve: DialogAnimationCurve.easeInOutCubicEmphasized,
  );

  static const DialogAnimationSettings listItem = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.slideUp,
    exitStyle: DialogAnimationStyle.fade,
    curve: DialogAnimationCurve.easeInOutCubicEmphasized,
  );
}

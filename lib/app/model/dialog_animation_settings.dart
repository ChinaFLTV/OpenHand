import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/util/input_value_parsing.dart';

/// Available dialog entrance / exit animation styles.
enum DialogAnimationStyle {
  /// No animation — dialogs appear and disappear instantly.
  none('none'),

  /// Plain opacity-only transition.
  fade('fade'),

  /// Classic Material fade + scale from center.
  fadeScale('fade_scale'),

  /// Slide up from the bottom with fade.
  slideUp('slide_up'),

  /// Slide down from the top with fade.
  slideDown('slide_down'),

  /// Slide in from the left with fade — perfect for in-row chips.
  slideLeft('slide_left'),

  /// Slide in from the right with fade — perfect for in-row chips.
  slideRight('slide_right'),

  /// Expands from center outward (scale + fade).
  expand('expand'),

  /// Rotates in with scale (3D feel).
  rotateScale('rotate_scale'),

  /// Elastic / bouncy scale entrance.
  elastic('elastic'),

  /// Spring scale — Q-bouncy overshoot scale entrance with fade.
  springScale('spring_scale'),

  /// 3D X-axis flip with fade — cinematic card flip.
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

/// Available easing curves for dialog transitions.
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

/// Bundled dialog animation settings.
class DialogAnimationSettings {
  const DialogAnimationSettings({
    this.entranceStyle = DialogAnimationStyle.fadeScale,
    this.exitStyle = DialogAnimationStyle.fadeScale,
    this.durationMs = defaultDurationMs,
    this.curve = DialogAnimationCurve.easeOutCubic,
  });

  factory DialogAnimationSettings.fromJson(Map<String, dynamic>? json) {
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
        entranceStyle: entranceStyle,
        exitStyle: exitStyle,
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
    required DialogAnimationStyle entranceStyle,
    required DialogAnimationStyle exitStyle,
  }) {
    return normalizeDurationMs(
      _animatedDurationMsRange.fromValue(value),
      entranceStyle: entranceStyle,
      exitStyle: exitStyle,
    );
  }

  static int normalizeDurationMs(
    int durationMs, {
    required DialogAnimationStyle entranceStyle,
    required DialogAnimationStyle exitStyle,
  }) {
    return _normalizedDurationMs(
      entranceStyle: entranceStyle,
      exitStyle: exitStyle,
      durationMs: durationMs,
    );
  }

  final DialogAnimationStyle entranceStyle;
  final DialogAnimationStyle exitStyle;
  final int durationMs;
  final DialogAnimationCurve curve;

  bool get disablesAnimation =>
      entranceStyle == DialogAnimationStyle.none &&
      exitStyle == DialogAnimationStyle.none;

  int get effectiveDurationMs => _normalizedDurationMs(
    entranceStyle: entranceStyle,
    exitStyle: exitStyle,
    durationMs: durationMs,
  );

  Duration get duration => Duration(milliseconds: effectiveDurationMs);

  DialogAnimationSettings normalized() {
    final normalizedDurationMs = effectiveDurationMs;
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
      durationMs: durationMs ?? this.durationMs,
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

  static int _normalizedDurationMs({
    required DialogAnimationStyle entranceStyle,
    required DialogAnimationStyle exitStyle,
    required int durationMs,
  }) {
    final disabled =
        entranceStyle == DialogAnimationStyle.none &&
        exitStyle == DialogAnimationStyle.none;
    if (disabled) {
      return 0;
    }
    return _animatedDurationMsRange.normalize(durationMs);
  }
}

/// Centralized motion presets used by settings defaults and runtime fallbacks.
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

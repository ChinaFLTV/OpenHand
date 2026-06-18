import 'package:flutter/material.dart';

import '../../shared/util/input_value_parsing.dart';

/// Available dialog entrance / exit animation styles.
enum DialogAnimationStyle {
  /// No animation — dialogs appear and disappear instantly.
  none('none', 'None', '无动画'),

  /// Plain opacity-only transition.
  fade('fade', 'Fade', '淡入淡出'),

  /// Classic Material fade + scale from center.
  fadeScale('fade_scale', 'Fade & Scale', '渐显缩放'),

  /// Slide up from the bottom with fade.
  slideUp('slide_up', 'Slide Up', '底部上滑'),

  /// Slide down from the top with fade.
  slideDown('slide_down', 'Slide Down', '顶部下滑'),

  /// Slide in from the left with fade — perfect for in-row chips.
  slideLeft('slide_left', 'Slide Left', '左侧滑入'),

  /// Slide in from the right with fade — perfect for in-row chips.
  slideRight('slide_right', 'Slide Right', '右侧滑入'),

  /// Expands from center outward (scale + fade).
  expand('expand', 'Expand', '中心展开'),

  /// Rotates in with scale (3D feel).
  rotateScale('rotate_scale', 'Rotate & Scale', '旋转缩放'),

  /// Elastic / bouncy scale entrance.
  elastic('elastic', 'Elastic', '弹性动画'),

  /// Spring scale — Q-bouncy overshoot scale entrance with fade.
  springScale('spring_scale', 'Spring Scale', '弹簧缩放'),

  /// 3D X-axis flip with fade — cinematic card flip.
  flipX('flip_x', 'Flip X', 'X 轴翻转');

  const DialogAnimationStyle(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

  static DialogAnimationStyle fromStorage(String? value) {
    for (final style in values) {
      if (style.storageValue == value) return style;
    }
    return fadeScale;
  }
}

/// Available easing curves for dialog transitions.
enum DialogAnimationCurve {
  easeInOut('ease_in_out', 'Ease In-Out', '缓入缓出'),
  easeOut('ease_out', 'Ease Out', '缓出'),
  easeOutCubic('ease_out_cubic', 'Ease Out Cubic', '缓出三次'),
  easeInOutCubicEmphasized(
    'ease_in_out_cubic_emphasized',
    'Cubic Emphasized',
    '三次加强',
  ),
  elasticOut('elastic_out', 'Elastic Out', '弹性缓出'),
  bounceOut('bounce_out', 'Bounce Out', '弹跳'),
  decelerate('decelerate', 'Decelerate', '减速');

  const DialogAnimationCurve(this.storageValue, this.labelEn, this.labelZh);

  final String storageValue;
  final String labelEn;
  final String labelZh;

  String label(bool isZh) => isZh ? labelZh : labelEn;

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
    for (final curve in values) {
      if (curve.storageValue == value) return curve;
    }
    return easeOutCubic;
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
    return DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fromStorage(
        nullIfBlank('${json['entrance_style'] ?? ''}'),
      ),
      exitStyle: DialogAnimationStyle.fromStorage(
        nullIfBlank('${json['exit_style'] ?? ''}'),
      ),
      durationMs: intFromValue(
        json['duration_ms'],
        fallback: defaultDurationMs,
      ),
      curve: DialogAnimationCurve.fromStorage(
        nullIfBlank('${json['curve'] ?? ''}'),
      ),
    ).normalized();
  }

  static const int defaultDurationMs = 360;
  static const int minAnimatedDurationMs = 80;
  static const int maxDurationMs = 1200;
  static const DialogAnimationSettings legacyFadeScale =
      DialogAnimationSettings();
  static const DialogAnimationSettings defaults = DialogAnimationSettings(
    entranceStyle: DialogAnimationStyle.springScale,
    exitStyle: DialogAnimationStyle.springScale,
  );

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
    return durationMs.clamp(minAnimatedDurationMs, maxDurationMs).toInt();
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

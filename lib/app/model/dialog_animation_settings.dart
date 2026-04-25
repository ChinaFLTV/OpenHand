import 'package:flutter/material.dart';

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

  /// Expands from center outward (scale + fade).
  expand('expand', 'Expand', '中心展开'),

  /// Rotates in with scale (3D feel).
  rotateScale('rotate_scale', 'Rotate & Scale', '旋转缩放'),

  /// Elastic / bouncy scale entrance.
  elastic('elastic', 'Elastic', '弹性动画');

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
    this.durationMs = 320,
    this.curve = DialogAnimationCurve.easeOutCubic,
  });

  factory DialogAnimationSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fromStorage(
        json['entrance_style'] as String?,
      ),
      exitStyle: DialogAnimationStyle.fromStorage(
        json['exit_style'] as String?,
      ),
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 320,
      curve: DialogAnimationCurve.fromStorage(json['curve'] as String?),
    );
  }

  static const DialogAnimationSettings defaults = DialogAnimationSettings();

  final DialogAnimationStyle entranceStyle;
  final DialogAnimationStyle exitStyle;
  final int durationMs;
  final DialogAnimationCurve curve;

  Duration get duration => Duration(milliseconds: durationMs);

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
    );
  }

  Map<String, dynamic> toJson() => {
    'entrance_style': entranceStyle.storageValue,
    'exit_style': exitStyle.storageValue,
    'duration_ms': durationMs,
    'curve': curve.storageValue,
  };

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

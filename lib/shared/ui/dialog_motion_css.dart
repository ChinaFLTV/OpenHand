import '../../app/model/dialog_animation_settings.dart';

const String kOpenHandDefaultDialogMotionCssTimingFunction =
    'cubic-bezier(0.215, 0.61, 0.355, 1)';

String openHandDialogAnimationCurveCss(DialogAnimationCurve curve) {
  return switch (curve) {
    DialogAnimationCurve.easeInOut => 'ease-in-out',
    DialogAnimationCurve.easeOut => 'ease-out',
    DialogAnimationCurve.easeOutCubic =>
      kOpenHandDefaultDialogMotionCssTimingFunction,
    DialogAnimationCurve.easeInOutCubicEmphasized =>
      'cubic-bezier(0.2, 0, 0, 1)',
    DialogAnimationCurve.elasticOut => 'cubic-bezier(0.34, 1.56, 0.64, 1)',
    DialogAnimationCurve.bounceOut => 'cubic-bezier(0.22, 1.45, 0.36, 1)',
    DialogAnimationCurve.decelerate => 'cubic-bezier(0, 0, 0.2, 1)',
  };
}

String openHandCssTimingFunctionOrDefault(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty
      ? kOpenHandDefaultDialogMotionCssTimingFunction
      : trimmed;
}

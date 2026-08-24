import '../../app/model/dialog_animation_settings.dart';

const String kOpenHandDefaultDialogMotionCssTimingFunction =
    'cubic-bezier(0.215, 0.61, 0.355, 1)';

const String kOpenHandDefaultDialogMotionCssReverseTimingFunction =
    'cubic-bezier(0.55, 0.055, 0.675, 0.19)';

/// 交互回弹曲线：按钮、展开、条带悬停等非弹窗变换共用。
const String kOpenHandUiSpringCssTimingFunction =
    'cubic-bezier(0.22, 1.45, 0.36, 1)';

const int kOpenHandUiHoverDurationMs = 220;

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

String openHandDialogAnimationCurveReverseCss(DialogAnimationCurve curve) {
  return switch (curve) {
    DialogAnimationCurve.easeInOut => 'ease-in-out',
    DialogAnimationCurve.easeOut => 'ease-in',
    DialogAnimationCurve.easeOutCubic =>
      kOpenHandDefaultDialogMotionCssReverseTimingFunction,
    DialogAnimationCurve.easeInOutCubicEmphasized =>
      'cubic-bezier(0.2, 0, 0, 1)',
    DialogAnimationCurve.elasticOut => 'ease-in',
    DialogAnimationCurve.bounceOut => 'ease-in',
    DialogAnimationCurve.decelerate => 'cubic-bezier(0.2, 0, 1, 1)',
  };
}

String openHandCssTimingFunctionOrDefault(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty
      ? kOpenHandDefaultDialogMotionCssTimingFunction
      : trimmed;
}

/// 写入 `:root` 的弹窗时长 / 曲线变量，供独立 HTML 页与 App 弹窗设置对齐。
String openHandDialogMotionCssCustomProperties(
  DialogAnimationSettings settings, {
  bool reduceMotion = false,
}) {
  final enterMs = reduceMotion ? 0 : settings.effectiveEntranceDurationMs;
  final exitMs = reduceMotion ? 0 : settings.effectiveExitDurationMs;
  final durationMs = enterMs == 0 && exitMs == 0
      ? 0
      : (enterMs > exitMs ? enterMs : exitMs);
  final hoverMs = durationMs == 0 ? 0 : kOpenHandUiHoverDurationMs;
  final curve = openHandDialogAnimationCurveCss(settings.curve);
  final reverse = openHandDialogAnimationCurveReverseCss(settings.curve);
  return '''
  --oh-dialog-duration: ${durationMs}ms;
  --oh-dialog-enter-duration: ${enterMs}ms;
  --oh-dialog-exit-duration: ${exitMs}ms;
  --oh-dialog-curve: $curve;
  --oh-dialog-exit-curve: $reverse;
  --oh-spring: $kOpenHandUiSpringCssTimingFunction;
  --oh-hover-duration: ${hoverMs}ms;''';
}

String openHandDialogMotionHtmlRootAttributes(
  DialogAnimationSettings settings, {
  bool reduceMotion = false,
}) {
  if (reduceMotion) {
    return 'data-dialog-enter="none" data-dialog-exit="none" data-motion="reduced"';
  }
  return 'data-dialog-enter="${settings.entranceStyle.storageValue}" '
      'data-dialog-exit="${settings.exitStyle.storageValue}"';
}

/// 独立 HTML 页复用的弹窗进退场关键帧与选择器，与 Web 端 `data-dialog-enter` 对齐。
const String kOpenHandDialogMotionStandaloneCss = r'''
@keyframes oh-dialog-fade-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes oh-dialog-fade-out { from { opacity: 1; } to { opacity: 0; } }
@keyframes oh-dialog-card-fade-in { from { opacity: 0; } to { opacity: 1; } }
@keyframes oh-dialog-card-fade-out { from { opacity: 1; } to { opacity: 0; } }
@keyframes oh-dialog-fade-scale-in {
  from { opacity: 0; transform: scale(0.85); }
  to { opacity: 1; transform: scale(1); }
}
@keyframes oh-dialog-fade-scale-out {
  from { opacity: 1; transform: scale(1); }
  to { opacity: 0; transform: scale(0.85); }
}
@keyframes oh-dialog-slide-up-in {
  from { opacity: 0; transform: translate3d(0, 16%, 0); }
  to { opacity: 1; transform: none; }
}
@keyframes oh-dialog-slide-up-out {
  from { opacity: 1; transform: none; }
  to { opacity: 0; transform: translate3d(0, 16%, 0); }
}
@keyframes oh-dialog-slide-down-in {
  from { opacity: 0; transform: translate3d(0, -16%, 0); }
  to { opacity: 1; transform: none; }
}
@keyframes oh-dialog-slide-down-out {
  from { opacity: 1; transform: none; }
  to { opacity: 0; transform: translate3d(0, -16%, 0); }
}
@keyframes oh-dialog-slide-left-in {
  from { opacity: 0; transform: translate3d(-22%, 0, 0); }
  to { opacity: 1; transform: none; }
}
@keyframes oh-dialog-slide-left-out {
  from { opacity: 1; transform: none; }
  to { opacity: 0; transform: translate3d(-22%, 0, 0); }
}
@keyframes oh-dialog-slide-right-in {
  from { opacity: 0; transform: translate3d(22%, 0, 0); }
  to { opacity: 1; transform: none; }
}
@keyframes oh-dialog-slide-right-out {
  from { opacity: 1; transform: none; }
  to { opacity: 0; transform: translate3d(22%, 0, 0); }
}
@keyframes oh-dialog-expand-in {
  from { opacity: 0; transform: scale(0.12); }
  to { opacity: 1; transform: scale(1); }
}
@keyframes oh-dialog-expand-out {
  from { opacity: 1; transform: scale(1); }
  to { opacity: 0; transform: scale(0.12); }
}
@keyframes oh-dialog-rotate-scale-in {
  from { opacity: 0; transform: rotate(-18deg) scale(0.7); }
  to { opacity: 1; transform: none; }
}
@keyframes oh-dialog-rotate-scale-out {
  from { opacity: 1; transform: none; }
  to { opacity: 0; transform: rotate(-10deg) scale(0.72); }
}
@keyframes oh-dialog-elastic-in {
  0% { opacity: 0; transform: scale(0.9); }
  55% { opacity: 1; transform: scale(1.04); }
  100% { opacity: 1; transform: scale(1); }
}
@keyframes oh-dialog-elastic-out {
  0% { opacity: 1; transform: scale(1); }
  40% { opacity: 0.96; transform: scale(1.02); }
  100% { opacity: 0; transform: scale(0.94); }
}
@keyframes oh-dialog-spring-scale-in {
  0% { opacity: 0; transform: scale(0.6); }
  54% { opacity: 1; transform: scale(1.055); }
  100% { opacity: 1; transform: scale(1); }
}
@keyframes oh-dialog-spring-scale-out {
  from { opacity: 1; transform: scale(1); }
  to { opacity: 0; transform: scale(0.97) translate3d(0, 10px, 0); }
}
@keyframes oh-dialog-flip-x-in {
  from { opacity: 0; transform: perspective(900px) rotateX(90deg); }
  to { opacity: 1; transform: perspective(900px) rotateX(0); }
}
@keyframes oh-dialog-flip-x-out {
  from { opacity: 1; transform: perspective(900px) rotateX(0); }
  to { opacity: 0; transform: perspective(900px) rotateX(70deg); }
}
.oh-dialog-pop-in {
  animation: oh-dialog-fade-scale-in var(--oh-dialog-enter-duration) var(--oh-dialog-curve) both;
  transform-origin: center;
}
.oh-dialog-pop-out {
  animation: oh-dialog-fade-scale-out var(--oh-dialog-exit-duration) var(--oh-dialog-exit-curve) both;
  transform-origin: center;
}
[data-dialog-enter='none'] .oh-dialog-pop-in,
[data-dialog-exit='none'] .oh-dialog-pop-out { animation: none; }
[data-dialog-enter='fade'] .oh-dialog-pop-in { animation-name: oh-dialog-card-fade-in; }
[data-dialog-enter='fade_scale'] .oh-dialog-pop-in { animation-name: oh-dialog-fade-scale-in; }
[data-dialog-enter='slide_up'] .oh-dialog-pop-in { animation-name: oh-dialog-slide-up-in; }
[data-dialog-enter='slide_down'] .oh-dialog-pop-in { animation-name: oh-dialog-slide-down-in; }
[data-dialog-enter='slide_left'] .oh-dialog-pop-in { animation-name: oh-dialog-slide-left-in; }
[data-dialog-enter='slide_right'] .oh-dialog-pop-in { animation-name: oh-dialog-slide-right-in; }
[data-dialog-enter='expand'] .oh-dialog-pop-in { animation-name: oh-dialog-expand-in; }
[data-dialog-enter='rotate_scale'] .oh-dialog-pop-in { animation-name: oh-dialog-rotate-scale-in; }
[data-dialog-enter='elastic'] .oh-dialog-pop-in { animation-name: oh-dialog-elastic-in; }
[data-dialog-enter='spring_scale'] .oh-dialog-pop-in { animation-name: oh-dialog-spring-scale-in; }
[data-dialog-enter='flip_x'] .oh-dialog-pop-in { animation-name: oh-dialog-flip-x-in; }
[data-dialog-exit='fade'] .oh-dialog-pop-out { animation-name: oh-dialog-card-fade-out; }
[data-dialog-exit='fade_scale'] .oh-dialog-pop-out { animation-name: oh-dialog-fade-scale-out; }
[data-dialog-exit='slide_up'] .oh-dialog-pop-out { animation-name: oh-dialog-slide-up-out; }
[data-dialog-exit='slide_down'] .oh-dialog-pop-out { animation-name: oh-dialog-slide-down-out; }
[data-dialog-exit='slide_left'] .oh-dialog-pop-out { animation-name: oh-dialog-slide-left-out; }
[data-dialog-exit='slide_right'] .oh-dialog-pop-out { animation-name: oh-dialog-slide-right-out; }
[data-dialog-exit='expand'] .oh-dialog-pop-out { animation-name: oh-dialog-expand-out; }
[data-dialog-exit='rotate_scale'] .oh-dialog-pop-out { animation-name: oh-dialog-rotate-scale-out; }
[data-dialog-exit='elastic'] .oh-dialog-pop-out { animation-name: oh-dialog-elastic-out; }
[data-dialog-exit='spring_scale'] .oh-dialog-pop-out { animation-name: oh-dialog-spring-scale-out; }
[data-dialog-exit='flip_x'] .oh-dialog-pop-out { animation-name: oh-dialog-flip-x-out; }
''';

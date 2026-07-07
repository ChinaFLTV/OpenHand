import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/localized_text.dart';

const OpenHandAnimationTransitionProfile kAndroidReverseDialogMotionProfile =
    OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.88,
      expandScaleBegin: 0.80,
      rotateScaleBegin: 0.86,
      elasticScaleBegin: 0.86,
      springScaleBegin: 0.84,
      slideUpOffset: Offset(0, 0.20),
      slideDownOffset: Offset(0, -0.16),
      slideLeftOffset: Offset(-0.20, 0),
      slideRightOffset: Offset(0.20, 0),
    );

Future<T?> showAndroidReverseToolDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
  bool surfaceMotion = false,
}) {
  return showOpenHandProfiledDialog<T>(
    context: context,
    settings: settings,
    transitionProfile: kAndroidReverseDialogMotionProfile,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    alignment: alignment,
    surfaceMotion: surfaceMotion,
    builder: builder,
  );
}

void showAndroidReverseSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarSuccessDuration,
  SnackBarAction? action,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showSuccess(
    context,
    message,
    duration: duration,
    action: action,
  );
}

void showAndroidReverseErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarErrorDuration,
  SnackBarAction? action,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showError(
    context,
    message,
    duration: duration,
    action: action,
  );
}

void showAndroidReverseInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarInfoDuration,
  SnackBarAction? action,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showInfo(
    context,
    message,
    duration: duration,
    action: action,
  );
}

Future<bool> copyAndroidReverseTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String logTag = 'android_reverse',
  String logAction = 'copy',
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (error, stack) {
    silentLog(logTag, logAction, error, stack);
    if (!context.mounted) return false;
    showAndroidReverseErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '复制失败：$error',
        zhHant: '複製失敗：$error',
        en: 'Copy failed: $error',
        fr: 'Échec de la copie : $error',
        de: 'Kopieren fehlgeschlagen: $error',
        ja: 'コピーに失敗しました: $error',
      ),
      duration: errorDuration,
    );
    return false;
  }
  if (!context.mounted) return false;
  showAndroidReverseSuccessSnack(
    context,
    successMessage ??
        openHandLocalizedText(
          context,
          zh: '已复制',
          zhHant: '已複製',
          en: 'Copied',
          fr: 'Copié',
          de: 'Kopiert',
          ja: 'コピーしました',
        ),
    duration: successDuration,
  );
  return true;
}

import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_clipboard.dart';
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
    builder: builder,
  );
}

void showAndroidReverseInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarInfoDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandInfoSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
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
}) {
  return copyOpenHandTextToClipboard(
    context: context,
    text: text,
    logTag: logTag,
    logAction: logAction,
    successMessage:
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
    successDuration: successDuration,
    errorDuration: errorDuration,
  );
}

import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void showHomeSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarSuccessDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandSuccessSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showHomeInfoSnack(
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

void showHomeErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarErrorDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandErrorSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void flashHomeSnack(
  BuildContext context,
  String message, {
  OpenHandSnackKind kind = OpenHandSnackKind.info,
  Duration? duration,
  SnackBarAction? action,
  int? maxLines,
  bool postFrame = false,
}) {
  OpenHandSnackBar.flash(
    context,
    message,
    kind: kind,
    duration: duration,
    action: action,
    maxLines: maxLines,
    postFrame: postFrame,
  );
}

Future<bool> copyHomeTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String? errorMessage,
  String logAction = 'copy',
  bool showSuccess = true,
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
  Duration timeout = kOpenHandClipboardCopyTimeout,
}) {
  return copyOpenHandFeatureTextToClipboard(
    context: context,
    text: text,
    logTag: 'home',
    logAction: logAction,
    successMessage: successMessage,
    errorMessage: errorMessage,
    showSuccess: showSuccess,
    timeout: timeout,
    successDuration: successDuration,
    errorDuration: errorDuration,
  );
}

import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void showHarnessSuccessSnack(
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

void showHarnessErrorSnack(
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

void showHarnessInfoSnack(
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

Future<bool> copyHarnessTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String logAction = 'copy',
  bool showSuccess = true,
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
}) {
  return copyOpenHandTextToClipboard(
    context: context,
    text: text,
    logTag: 'harness',
    logAction: logAction,
    successMessage: successMessage,
    showSuccess: showSuccess,
    successDuration: successDuration,
    errorDuration: errorDuration,
    showSuccessSnack: (context, message, {required duration}) =>
        showHarnessSuccessSnack(context, message, duration: duration),
    showErrorSnack: (context, message, {required duration}) =>
        showHarnessErrorSnack(context, message, duration: duration),
  );
}

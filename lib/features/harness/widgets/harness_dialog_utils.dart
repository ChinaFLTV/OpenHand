import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void showHarnessSuccessSnack(
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

void showHarnessErrorSnack(
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

void showHarnessInfoSnack(
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

Future<bool> copyHarnessTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String logAction = 'copy',
  bool showSuccess = true,
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
}) {
  return copyOpenHandFeatureTextToClipboard(
    context: context,
    text: text,
    logTag: 'harness',
    logAction: logAction,
    successMessage: successMessage,
    showSuccess: showSuccess,
    successDuration: successDuration,
    errorDuration: errorDuration,
  );
}

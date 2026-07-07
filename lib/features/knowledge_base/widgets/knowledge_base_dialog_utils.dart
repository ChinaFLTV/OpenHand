import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void showKnowledgeBaseSuccessSnack(
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

void showKnowledgeBaseErrorSnack(
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

void showKnowledgeBaseInfoSnack(
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

Future<bool> copyKnowledgeBaseTextToClipboard({
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
    logTag: 'knowledge_base',
    logAction: logAction,
    successMessage: successMessage,
    showSuccess: showSuccess,
    successDuration: successDuration,
    errorDuration: errorDuration,
    showSuccessSnack: (context, message, {required duration}) =>
        showKnowledgeBaseSuccessSnack(context, message, duration: duration),
    showErrorSnack: (context, message, {required duration}) =>
        showKnowledgeBaseErrorSnack(context, message, duration: duration),
  );
}

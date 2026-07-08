import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void showKnowledgeBaseSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarSuccessDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showKind(
    context,
    message,
    kind: OpenHandSnackKind.success,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showKnowledgeBaseErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarErrorDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showKind(
    context,
    message,
    kind: OpenHandSnackKind.error,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showKnowledgeBaseInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarInfoDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  if (!context.mounted) return;
  OpenHandSnackBar.showKind(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
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

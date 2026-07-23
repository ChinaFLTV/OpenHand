import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';

void flashHomeSnack(
  BuildContext context,
  String message, {
  OpenHandSnackKind kind = OpenHandSnackKind.info,
  Duration? duration,
  SnackBarAction? action,
  int? maxLines,
  bool postFrame = false,
}) {
  flashOpenHandSnack(
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
  String logAction = '复制',
  bool showSuccess = true,
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
  Duration timeout = kOpenHandClipboardCopyTimeout,
}) {
  return copyOpenHandTextToClipboard(
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

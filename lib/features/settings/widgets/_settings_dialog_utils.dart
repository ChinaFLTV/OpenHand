part of 'settings_view.dart';

void _showSettingsSuccessSnack(
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

void _showSettingsErrorSnack(
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

void _showSettingsInfoSnack(
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

Future<bool> _copySettingsTextToClipboard({
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
    logTag: 'settings',
    logAction: logAction,
    successMessage: successMessage,
    showSuccess: showSuccess,
    successDuration: successDuration,
    errorDuration: errorDuration,
    showSuccessSnack: (context, message, {required duration}) =>
        _showSettingsSuccessSnack(context, message, duration: duration),
    showErrorSnack: (context, message, {required duration}) =>
        _showSettingsErrorSnack(context, message, duration: duration),
  );
}

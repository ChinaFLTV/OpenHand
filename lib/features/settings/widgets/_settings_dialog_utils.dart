part of 'settings_view.dart';

void _showSettingsSuccessSnack(
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

void _showSettingsErrorSnack(
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

void _showSettingsInfoSnack(
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

Future<bool> _copySettingsTextToClipboard({
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
    logTag: 'settings',
    logAction: logAction,
    successMessage: successMessage,
    showSuccess: showSuccess,
    successDuration: successDuration,
    errorDuration: errorDuration,
  );
}

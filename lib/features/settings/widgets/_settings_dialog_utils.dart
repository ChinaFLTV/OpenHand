part of 'settings_view.dart';

Future<bool> _copySettingsTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String logAction = '复制',
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
  );
}

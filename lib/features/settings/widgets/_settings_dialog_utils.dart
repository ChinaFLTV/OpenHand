part of 'settings_view.dart';

const Duration _settingsClipboardCopyTimeout = Duration(seconds: 10);

void _showSettingsSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarSuccessDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  if (!context.mounted) return;
  if (maxLines != null) {
    OpenHandSnackBar.showInContext(
      context,
      OpenHandSnackBar.success(
        context,
        message,
        duration: duration,
        action: action,
        maxLines: maxLines,
      ),
    );
    return;
  }
  OpenHandSnackBar.showSuccess(
    context,
    message,
    duration: duration,
    action: action,
  );
}

void _showSettingsErrorSnack(
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

void _showSettingsInfoSnack(
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

Future<bool> _copySettingsTextToClipboard({
  required BuildContext context,
  required String text,
  String? successMessage,
  String logAction = 'copy',
  bool showSuccess = true,
  Duration successDuration = kOpenHandSnackBarSuccessDuration,
  Duration errorDuration = kOpenHandSnackBarErrorDuration,
}) async {
  try {
    await Clipboard.setData(
      ClipboardData(text: text),
    ).timeout(_settingsClipboardCopyTimeout);
  } catch (error, stack) {
    silentLog('settings', logAction, error, stack);
    if (!context.mounted) return false;
    _showSettingsErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '复制失败：$error',
        zhHant: '複製失敗：$error',
        en: 'Copy failed: $error',
        fr: 'Échec de la copie : $error',
        de: 'Kopieren fehlgeschlagen: $error',
        ja: 'コピーに失敗しました: $error',
      ),
      duration: errorDuration,
    );
    return false;
  }
  if (!context.mounted) return false;
  if (showSuccess) {
    _showSettingsSuccessSnack(
      context,
      successMessage ??
          openHandLocalizedText(
            context,
            zh: '已复制到剪贴板',
            zhHant: '已複製到剪貼簿',
            en: 'Copied to clipboard',
            fr: 'Copié dans le presse-papiers',
            de: 'In die Zwischenablage kopiert',
            ja: 'クリップボードにコピーしました',
          ),
      duration: successDuration,
    );
  }
  return true;
}

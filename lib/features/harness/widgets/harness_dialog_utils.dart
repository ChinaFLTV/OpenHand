import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';

const Duration _harnessClipboardCopyTimeout = Duration(seconds: 10);

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
}) async {
  try {
    await Clipboard.setData(
      ClipboardData(text: text),
    ).timeout(_harnessClipboardCopyTimeout);
  } catch (error, stack) {
    silentLog('harness', logAction, error, stack);
    if (!context.mounted) return false;
    showHarnessErrorSnack(
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
    showHarnessSuccessSnack(
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/support/silent_log.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';

const Duration _knowledgeBaseClipboardCopyTimeout = Duration(seconds: 10);

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
}) async {
  try {
    await Clipboard.setData(
      ClipboardData(text: text),
    ).timeout(_knowledgeBaseClipboardCopyTimeout);
  } catch (error, stack) {
    silentLog('knowledge_base', logAction, error, stack);
    if (!context.mounted) return false;
    showKnowledgeBaseErrorSnack(
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
    showKnowledgeBaseSuccessSnack(
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

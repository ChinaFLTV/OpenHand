import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../util/localized_text.dart';
import '../util/user_failure_message.dart';
import 'openhand_snack_bar.dart';

const Duration kOpenHandClipboardCopyTimeout = Duration(seconds: 10);
const Duration _kOpenHandClipboardMaxCopyTimeout = Duration(seconds: 60);

typedef OpenHandClipboardSnackPresenter =
    void Function(
      BuildContext context,
      String message, {
      required Duration duration,
    });

/// 将剪贴板操作超时限制在安全范围内。
Duration clampOpenHandClipboardTimeout(Duration timeout) {
  if (timeout <= Duration.zero) return kOpenHandClipboardCopyTimeout;
  if (timeout > _kOpenHandClipboardMaxCopyTimeout) {
    return _kOpenHandClipboardMaxCopyTimeout;
  }
  return timeout;
}

Future<void> setOpenHandClipboardText(
  String text, {
  Duration timeout = kOpenHandClipboardCopyTimeout,
}) {
  return Clipboard.setData(
    ClipboardData(text: text),
  ).timeout(clampOpenHandClipboardTimeout(timeout));
}

/// 限时读取剪贴板文本；内容为空或读取失败时返回 `null`。
Future<String?> getOpenHandClipboardText({
  Duration timeout = kOpenHandClipboardCopyTimeout,
}) async {
  try {
    final data = await Clipboard.getData(
      Clipboard.kTextPlain,
    ).timeout(clampOpenHandClipboardTimeout(timeout));
    final text = data?.text;
    if (text == null) return null;
    return text;
  } catch (_) {
    return null;
  }
}

Future<bool> copyOpenHandTextToClipboard({
  required BuildContext context,
  required String text,
  required String logTag,
  String logAction = '复制',
  String? successMessage,
  String? errorMessage,
  bool showSuccess = true,
  Duration timeout = kOpenHandClipboardCopyTimeout,
  Duration successDuration = kOpenHandSnackBarBriefDuration,
  Duration errorDuration = kOpenHandSnackBarDetailedDuration,
  OpenHandClipboardSnackPresenter? showSuccessSnack,
  OpenHandClipboardSnackPresenter? showErrorSnack,
}) async {
  try {
    await setOpenHandClipboardText(text, timeout: timeout);
  } catch (error, stack) {
    silentLog(logTag, logAction, error, stack);
    if (!context.mounted) return false;
    (showErrorSnack ?? _showDefaultClipboardErrorSnack)(
      context,
      errorMessage ?? openHandClipboardCopyErrorMessage(context, error),
      duration: errorDuration,
    );
    return false;
  }

  if (!context.mounted) return false;
  if (showSuccess) {
    (showSuccessSnack ?? _showDefaultClipboardSuccessSnack)(
      context,
      successMessage ?? openHandClipboardCopySuccessMessage(context),
      duration: successDuration,
    );
  }
  return true;
}

String openHandClipboardCopySuccessMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已复制到剪贴板',
    zhHant: '已複製到剪貼簿',
    en: 'Copied to clipboard',
    fr: 'Copié dans le presse-papiers',
    de: 'In die Zwischenablage kopiert',
    ja: 'クリップボードにコピーしました',
  );
}

String openHandClipboardCopyErrorMessage(BuildContext context, Object error) {
  final detail = userFailureMessage(
    error,
    fallback: openHandLocalizedText(
      context,
      zh: '剪贴板暂不可用，请稍后重试。',
      zhHant: '剪貼簿暫時無法使用，請稍後重試。',
      en: 'The clipboard is unavailable. Please try again later.',
      fr: 'Le presse-papiers est indisponible. Réessayez plus tard.',
      de: 'Die Zwischenablage ist nicht verfügbar. Bitte später erneut versuchen.',
      ja: 'クリップボードを利用できません。しばらくしてから再試行してください。',
    ),
  );
  return openHandLocalizedText(
    context,
    zh: '复制失败：$detail',
    zhHant: '複製失敗：$detail',
    en: 'Copy failed: $detail',
    fr: 'Échec de la copie : $detail',
    de: 'Kopieren fehlgeschlagen: $detail',
    ja: 'コピーに失敗しました: $detail',
  );
}

void _showDefaultClipboardSuccessSnack(
  BuildContext context,
  String message, {
  required Duration duration,
}) {
  showOpenHandSuccessSnack(context, message, duration: duration);
}

void _showDefaultClipboardErrorSnack(
  BuildContext context,
  String message, {
  required Duration duration,
}) {
  showOpenHandErrorSnack(context, message, duration: duration);
}

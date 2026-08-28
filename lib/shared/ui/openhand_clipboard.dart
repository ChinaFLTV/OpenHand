import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../app/support/silent_log.dart';
import '../util/localized_text.dart';
import '../util/user_failure_message.dart';
import 'openhand_snack_bar.dart';

const Duration kOpenHandClipboardCopyTimeout = Duration(seconds: 10);
const Duration _kOpenHandClipboardMaxCopyTimeout = Duration(seconds: 60);

/// 复制失败提示带一段原因后缀，限两行避免长文案糊住半屏。
const int _kClipboardErrorSnackMaxLines = 2;

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
  bool replaceCurrentSnack = false,
  OpenHandClipboardSnackPresenter? showSuccessSnack,
  OpenHandClipboardSnackPresenter? showErrorSnack,
}) async {
  try {
    await setOpenHandClipboardText(text, timeout: timeout);
  } catch (error, stack) {
    silentLog(logTag, logAction, error, stack);
    if (!context.mounted) return false;
    (showErrorSnack ??
        (replaceCurrentSnack
            ? _replaceClipboardErrorSnack
            : _showDefaultClipboardErrorSnack))(
      context,
      errorMessage ?? openHandClipboardCopyErrorMessage(context, error),
      duration: errorDuration,
    );
    return false;
  }

  if (!context.mounted) return false;
  if (showSuccess) {
    (showSuccessSnack ??
        (replaceCurrentSnack
            ? _replaceClipboardSuccessSnack
            : _showDefaultClipboardSuccessSnack))(
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
  showOpenHandErrorSnack(
    context,
    message,
    duration: duration,
    maxLines: _kClipboardErrorSnackMaxLines,
  );
}

void _replaceClipboardSuccessSnack(
  BuildContext context,
  String message, {
  required Duration duration,
}) {
  replaceOpenHandSnack(
    context,
    message,
    kind: OpenHandSnackKind.success,
    duration: duration,
  );
}

void _replaceClipboardErrorSnack(
  BuildContext context,
  String message, {
  required Duration duration,
}) {
  replaceOpenHandSnack(
    context,
    message,
    kind: OpenHandSnackKind.error,
    duration: duration,
    maxLines: _kClipboardErrorSnackMaxLines,
  );
}

const Duration kOpenHandClipboardImageReadTimeout = Duration(seconds: 10);
const Duration kOpenHandClipboardWriteTimeout = Duration(seconds: 15);

/// 限时读取剪贴板文件路径列表；失败或超时返回空列表。
Future<List<String>> getOpenHandClipboardFiles({
  Duration timeout = kOpenHandClipboardImageReadTimeout,
}) async {
  try {
    return await Pasteboard.files().timeout(
      clampOpenHandClipboardTimeout(timeout),
    );
  } catch (_) {
    return const <String>[];
  }
}

/// 限时读取剪贴板图片字节；失败、超时或无图片时返回 `null`。
Future<Uint8List?> getOpenHandClipboardImage({
  Duration timeout = kOpenHandClipboardImageReadTimeout,
}) async {
  try {
    final bytes = await Pasteboard.image.timeout(
      clampOpenHandClipboardTimeout(timeout),
    );
    if (bytes == null || bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// 限时写入图片到剪贴板；失败时返回 false。
Future<bool> writeOpenHandClipboardImage(
  Uint8List bytes, {
  Duration timeout = kOpenHandClipboardWriteTimeout,
}) async {
  try {
    await Pasteboard.writeImage(
      bytes,
    ).timeout(clampOpenHandClipboardTimeout(timeout));
    return true;
  } catch (_) {
    return false;
  }
}

/// 限时写入文件路径到剪贴板；失败时返回 false。
Future<bool> writeOpenHandClipboardFiles(
  List<String> paths, {
  Duration timeout = kOpenHandClipboardWriteTimeout,
}) async {
  try {
    await Pasteboard.writeFiles(
      paths,
    ).timeout(clampOpenHandClipboardTimeout(timeout));
    return true;
  } catch (_) {
    return false;
  }
}

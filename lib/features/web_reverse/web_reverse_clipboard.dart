import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/openhand_clipboard.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/text_clip.dart';

const int kWebReverseClipboardMaxChars = 1000000;
const String _webReverseClipboardTinyClipMarker = '[已截断]';

class WebReverseClipboardCopyResult {
  const WebReverseClipboardCopyResult({
    required this.originalChars,
    required this.copiedChars,
    required this.clipped,
  });

  final int originalChars;
  final int copiedChars;
  final bool clipped;
}

Future<WebReverseClipboardCopyResult> setWebReverseClipboardText(
  String text, {
  int maxChars = kWebReverseClipboardMaxChars,
  Duration timeout = kOpenHandClipboardCopyTimeout,
}) async {
  final prepared = prepareWebReverseClipboardText(text, maxChars: maxChars);
  await setOpenHandClipboardText(prepared.text, timeout: timeout);
  return WebReverseClipboardCopyResult(
    originalChars: text.length,
    copiedChars: prepared.text.length,
    clipped: prepared.clipped,
  );
}

Future<WebReverseClipboardCopyResult?> copyWebReverseTextToClipboard({
  required BuildContext context,
  required String text,
  String? successBase,
  required String logTag,
  String logAction = '复制',
  int maxChars = kWebReverseClipboardMaxChars,
  Duration successDuration = kOpenHandSnackBarBriefDuration,
  Duration errorDuration = kOpenHandSnackBarDetailedDuration,
  Duration timeout = kOpenHandClipboardCopyTimeout,
  bool showSuccess = true,
}) async {
  late final WebReverseClipboardCopyResult copied;
  try {
    copied = await setWebReverseClipboardText(
      text,
      maxChars: maxChars,
      timeout: timeout,
    );
  } catch (error, stack) {
    silentLog(logTag, logAction, error, stack);
    if (!context.mounted) return null;
    showWebReverseClipboardErrorSnack(
      context: context,
      error: error,
      duration: errorDuration,
    );
    return null;
  }
  if (!context.mounted) return null;
  if (showSuccess) {
    showWebReverseClipboardSuccessSnack(
      context: context,
      base: successBase ?? openHandCopiedLabel(context),
      result: copied,
      duration: successDuration,
    );
  }
  return copied;
}

String webReverseClipboardSnackMessage({
  BuildContext? context,
  bool isZh = false,
  required String base,
  required WebReverseClipboardCopyResult result,
}) {
  if (!result.clipped) return base;
  if (context != null) {
    return openHandLocalizedText(
      context,
      zh: '$base（已按上限复制 ${result.copiedChars}/${result.originalChars} 字符）',
      zhHant: '$base（已依上限複製 ${result.copiedChars}/${result.originalChars} 字元）',
      en: '$base (copied ${result.copiedChars}/${result.originalChars} chars, capped)',
      fr: '$base (${result.copiedChars}/${result.originalChars} caractères copiés, limite atteinte)',
      de: '$base (${result.copiedChars}/${result.originalChars} Zeichen kopiert, begrenzt)',
      ja: '$base（上限により ${result.copiedChars}/${result.originalChars} 文字をコピー）',
    );
  }
  return isZh
      ? '$base（已按上限复制 ${result.copiedChars}/${result.originalChars} 字符）'
      : '$base (copied ${result.copiedChars}/${result.originalChars} chars, capped)';
}

void showWebReverseClipboardSuccessSnack({
  required BuildContext context,
  required String base,
  required WebReverseClipboardCopyResult result,
  Duration duration = kOpenHandSnackBarBriefDuration,
}) {
  showOpenHandSuccessSnack(
    context,
    webReverseClipboardSnackMessage(
      context: context,
      base: base,
      result: result,
    ),
    duration: duration,
  );
}

void showWebReverseClipboardErrorSnack({
  required BuildContext context,
  Object? error,
  Duration duration = kOpenHandSnackBarDetailedDuration,
}) {
  final detail = error == null ? '' : ': $error';
  showOpenHandErrorSnack(
    context,
    openHandLocalizedText(
      context,
      zh: '复制失败$detail',
      zhHant: '複製失敗$detail',
      en: 'Copy failed$detail',
      fr: 'Échec de la copie$detail',
      de: 'Kopieren fehlgeschlagen$detail',
      ja: 'コピーに失敗しました$detail',
    ),
    duration: duration,
  );
}

({String text, bool clipped}) prepareWebReverseClipboardText(
  String text, {
  required int maxChars,
}) {
  final limit = nonNegativeIntFromValue(maxChars, fallback: 0);
  if (text.length <= limit) return (text: text, clipped: false);
  if (limit <= 0) return (text: '', clipped: text.isNotEmpty);
  const suffix = '\n\n[OpenHand 已截断剪贴板内容]';
  if (suffix.length >= limit) {
    final marker = clipTextByCodeUnits(
      _webReverseClipboardTinyClipMarker,
      limit,
      suffix: '',
    );
    return (text: marker, clipped: true);
  }
  return (
    text: clipTextByCodeUnits(text, limit, suffix: suffix),
    clipped: true,
  );
}

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../shared/util/localized_text.dart';

const int kWebReverseClipboardMaxChars = 1000000;

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
}) async {
  final prepared = _prepareClipboardText(text, maxChars: maxChars);
  await Clipboard.setData(ClipboardData(text: prepared.text));
  return WebReverseClipboardCopyResult(
    originalChars: text.length,
    copiedChars: prepared.text.length,
    clipped: prepared.clipped,
  );
}

String webReverseClipboardSnackMessage({
  BuildContext? context,
  required bool isZh,
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

({String text, bool clipped}) _prepareClipboardText(
  String text, {
  required int maxChars,
}) {
  if (text.length <= maxChars) return (text: text, clipped: false);
  final suffix =
      '\n\n[OpenHand clipped clipboard text: ${text.length - maxChars} chars omitted]';
  final keep = math.max(0, maxChars - suffix.length);
  return (text: '${text.substring(0, keep)}$suffix', clipped: true);
}

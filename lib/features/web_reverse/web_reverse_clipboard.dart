import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';

const int kWebReverseClipboardMaxChars = 1000000;
const String _webReverseClipboardTinyClipMarker = '[clipped]';

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
  final prepared = prepareWebReverseClipboardText(text, maxChars: maxChars);
  await Clipboard.setData(ClipboardData(text: prepared.text));
  return WebReverseClipboardCopyResult(
    originalChars: text.length,
    copiedChars: prepared.text.length,
    clipped: prepared.clipped,
  );
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
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  OpenHandSnackBar.showSuccessOn(
    context,
    messenger,
    webReverseClipboardSnackMessage(
      context: context,
      base: base,
      result: result,
    ),
  );
}

({String text, bool clipped}) prepareWebReverseClipboardText(
  String text, {
  required int maxChars,
}) {
  final limit = nonNegativeIntFromValue(maxChars, fallback: 0);
  if (text.length <= limit) return (text: text, clipped: false);
  if (limit <= 0) return (text: '', clipped: text.isNotEmpty);
  final suffix =
      '\n\n[OpenHand clipped clipboard text: ${text.length - limit} chars omitted]';
  if (suffix.length >= limit) {
    final marker = _webReverseClipboardTinyClipMarker.length >= limit
        ? _webReverseClipboardTinyClipMarker.substring(0, limit)
        : _webReverseClipboardTinyClipMarker;
    return (text: marker, clipped: true);
  }
  final keep = nonNegativeRemaining(limit, suffix.length);
  return (text: '${text.substring(0, keep)}$suffix', clipped: true);
}

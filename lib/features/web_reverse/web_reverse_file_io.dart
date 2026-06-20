import 'dart:convert';

import 'package:file_selector/file_selector.dart';

import '../../shared/util/byte_size_format.dart';

const int kWebReverseJsonFileMaxBytes = 32 * kBytesPerMiB;

class WebReverseTextFileReadResult {
  const WebReverseTextFileReadResult._({
    required this.text,
    required this.tooLargeBytes,
  });

  const WebReverseTextFileReadResult.ok(String text)
    : this._(text: text, tooLargeBytes: null);

  const WebReverseTextFileReadResult.tooLarge(int bytes)
    : this._(text: null, tooLargeBytes: bytes);

  final String? text;
  final int? tooLargeBytes;

  bool get isTooLarge => tooLargeBytes != null;
}

Future<WebReverseTextFileReadResult> readWebReverseTextFile(
  XFile file, {
  int maxBytes = kWebReverseJsonFileMaxBytes,
}) async {
  final knownLength = await _safeLength(file);
  if (knownLength != null && knownLength > maxBytes) {
    return WebReverseTextFileReadResult.tooLarge(knownLength);
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > maxBytes) {
    return WebReverseTextFileReadResult.tooLarge(bytes.length);
  }
  return WebReverseTextFileReadResult.ok(utf8.decode(bytes));
}

String webReverseTextFileTooLargeMessage(
  int bytes, {
  required bool isZh,
  int maxBytes = kWebReverseJsonFileMaxBytes,
}) {
  final size = formatByteSize(bytes);
  final max = formatByteSize(maxBytes);
  return isZh
      ? 'JSON 文件过大：$size，上限 $max'
      : 'JSON file is too large: $size (limit $max)';
}

Future<int?> _safeLength(XFile file) async {
  try {
    return await file.length();
  } catch (_) {
    return null;
  }
}

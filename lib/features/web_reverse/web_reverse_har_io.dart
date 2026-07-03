import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../shared/util/byte_size_format.dart';
import '../../shared/util/localized_text.dart';

const int kWebReverseHarFileMaxBytes = 32 * kBytesPerMiB;
const int kWebReverseHarDiffEntryLimit = 1000;
const int kWebReverseHarDiffBodyPreviewChars = 4096;

class WebReverseHarReadResult {
  const WebReverseHarReadResult._({
    required this.bytes,
    required this.tooLargeBytes,
  });

  const WebReverseHarReadResult.ok(List<int> bytes)
    : this._(bytes: bytes, tooLargeBytes: null);

  const WebReverseHarReadResult.tooLarge(int bytes)
    : this._(bytes: null, tooLargeBytes: bytes);

  final List<int>? bytes;
  final int? tooLargeBytes;

  bool get isTooLarge => tooLargeBytes != null;
}

Future<WebReverseHarReadResult> readWebReverseHarFile(XFile file) async {
  final knownLength = await _safeLength(file);
  if (knownLength != null && knownLength > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(knownLength);
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(bytes.length);
  }
  return WebReverseHarReadResult.ok(bytes);
}

Future<WebReverseHarReadResult> readWebReverseHarPath(String path) async {
  final file = File(path);
  final knownLength = await _safeFileLength(file);
  if (knownLength != null && knownLength > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(knownLength);
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(bytes.length);
  }
  return WebReverseHarReadResult.ok(bytes);
}

String webReverseHarTooLargeMessage(
  int bytes, {
  BuildContext? context,
  required bool isZh,
}) {
  final size = formatByteSize(bytes);
  final max = formatByteSize(kWebReverseHarFileMaxBytes);
  if (context != null) {
    return openHandLocalizedText(
      context,
      zh: 'HAR 文件过大：$size，上限 $max',
      zhHant: 'HAR 檔案過大：$size，上限 $max',
      en: 'HAR file is too large: $size (limit $max)',
      fr: 'Fichier HAR trop volumineux : $size (limite $max)',
      de: 'HAR-Datei ist zu groß: $size (Limit $max)',
      ja: 'HAR ファイルが大きすぎます: $size（上限 $max）',
    );
  }
  return isZh
      ? 'HAR 文件过大：$size，上限 $max'
      : 'HAR file is too large: $size (limit $max)';
}

String webReverseHarDiffCappedMessage(
  int shown,
  int total, {
  BuildContext? context,
  required bool isZh,
}) {
  if (context != null) {
    return openHandLocalizedText(
      context,
      zh: '已按上限解析 $shown / $total 条 HAR 记录',
      zhHant: '已依上限解析 $shown / $total 條 HAR 記錄',
      en: 'Parsed $shown of $total HAR entries (capped)',
      fr: '$shown entrées HAR analysées sur $total (limite atteinte)',
      de: '$shown von $total HAR-Einträgen geparst (begrenzt)',
      ja: '$total 件中 $shown 件の HAR エントリを解析（上限）',
    );
  }
  return isZh
      ? '已按上限解析 $shown / $total 条 HAR 记录'
      : 'Parsed $shown of $total HAR entries (capped)';
}

Future<int?> _safeLength(XFile file) async {
  try {
    return await file.length();
  } catch (_) {
    return null;
  }
}

Future<int?> _safeFileLength(File file) async {
  try {
    return await file.length();
  } catch (_) {
    return null;
  }
}

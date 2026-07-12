import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../shared/net/http_response_utils.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/localized_text.dart';

const int kWebReverseHarFileMaxBytes = 32 * kBytesPerMiB;
const int kWebReverseHarDiffEntryLimit = 1000;
const int kWebReverseHarDiffBodyPreviewChars = 4096;
const Duration _harReadIdleTimeout = Duration(seconds: 30);
const Duration _harReadTotalTimeout = Duration(minutes: 2);
const Duration _harMetadataTimeout = Duration(seconds: 5);

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
  if (!kIsWeb && file.path.trim().isNotEmpty) {
    return readWebReverseHarPath(file.path);
  }
  final knownLength = await _safeLength(file);
  if (knownLength != null && knownLength > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(knownLength);
  }
  try {
    final bytes = await readBoundedByteStream(
      file.openRead(),
      maxBytes: kWebReverseHarFileMaxBytes,
      idleTimeout: _harReadIdleTimeout,
      totalTimeout: _harReadTotalTimeout,
    );
    return WebReverseHarReadResult.ok(bytes);
  } on ByteStreamSizeLimitException {
    return WebReverseHarReadResult.tooLarge(
      knownLength != null && knownLength > kWebReverseHarFileMaxBytes
          ? knownLength
          : kWebReverseHarFileMaxBytes + 1,
    );
  }
}

Future<WebReverseHarReadResult> readWebReverseHarPath(String path) async {
  final file = File(path);
  final stat = await file.stat().timeout(_harMetadataTimeout);
  if (!isRegularFileStat(stat)) {
    throw FileSystemException('HAR path is not a regular file.', file.path);
  }
  if (stat.size > kWebReverseHarFileMaxBytes) {
    return WebReverseHarReadResult.tooLarge(stat.size);
  }
  try {
    final bytes = await readBoundedFileBytes(
      file,
      maxBytes: kWebReverseHarFileMaxBytes,
      idleTimeout: _harReadIdleTimeout,
      totalTimeout: _harReadTotalTimeout,
    );
    return WebReverseHarReadResult.ok(bytes);
  } on BoundedFileReadException catch (error) {
    if (error.failure != BoundedFileReadFailure.tooLarge) rethrow;
    return WebReverseHarReadResult.tooLarge(
      stat.size > kWebReverseHarFileMaxBytes
          ? stat.size
          : kWebReverseHarFileMaxBytes + 1,
    );
  }
}

String webReverseHarTooLargeMessage(
  int bytes, {
  BuildContext? context,
  bool isZh = false,
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
  bool isZh = false,
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
    return await file.length().timeout(_harMetadataTimeout);
  } catch (_) {
    return null;
  }
}

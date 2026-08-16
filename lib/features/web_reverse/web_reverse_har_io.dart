import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../shared/util/bounded_xfile_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/localized_text.dart';

const int kWebReverseHarFileMaxBytes = 32 * kBytesPerMiB;
const int kWebReverseHarDiffEntryLimit = 1000;
const int kWebReverseHarDiffBodyPreviewChars = 4 * kBytesPerKiB;

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
  try {
    final bytes = await readBoundedXFileBytes(
      file,
      maxBytes: kWebReverseHarFileMaxBytes,
    );
    return WebReverseHarReadResult.ok(bytes);
  } on BoundedXFileSizeException catch (error) {
    return WebReverseHarReadResult.tooLarge(
      error.actualBytes ?? kWebReverseHarFileMaxBytes + 1,
    );
  }
}

Future<WebReverseHarReadResult> readWebReverseHarPath(String path) async {
  return readWebReverseHarFile(XFile(path));
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

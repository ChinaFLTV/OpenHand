import 'package:file_selector/file_selector.dart';

import '../../shared/util/byte_size_format.dart';

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

String webReverseHarTooLargeMessage(int bytes, {required bool isZh}) {
  final size = formatByteSize(bytes);
  final max = formatByteSize(kWebReverseHarFileMaxBytes);
  return isZh
      ? 'HAR 文件过大：$size，上限 $max'
      : 'HAR file is too large: $size (limit $max)';
}

String webReverseHarDiffCappedMessage(
  int shown,
  int total, {
  required bool isZh,
}) {
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

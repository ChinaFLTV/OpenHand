import 'input_value_parsing.dart';

const int kBytesPerKiB = 1024;
const int kBytesPerMiB = kBytesPerKiB * 1024;
const int kBytesPerGiB = kBytesPerMiB * 1024;
const List<String> _byteSizeUnits = <String>['KB', 'MB', 'GB', 'TB', 'PB'];

final RegExp _trailingFractionZerosPattern = RegExp(r'0+$');
final RegExp _trailingDecimalPointPattern = RegExp(r'\.$');

String formatByteSize(num bytes) {
  if (!bytes.isFinite || bytes <= 0) return '0 B';
  if (bytes < kBytesPerKiB) return '${bytes.round()} B';

  double size = bytes / kBytesPerKiB;
  var unitIndex = 0;
  while (size >= kBytesPerKiB && unitIndex < _byteSizeUnits.length - 1) {
    size /= kBytesPerKiB;
    unitIndex++;
  }

  final fractionDigits = size >= 100 ? 0 : (size >= 10 ? 1 : 2);
  return '${_trimFractionZeros(size.toStringAsFixed(fractionDigits))} '
      '${_byteSizeUnits[unitIndex]}';
}

String formatSignedByteSize(num bytes) {
  if (!bytes.isFinite || bytes == 0) return '0 B';
  final prefix = bytes < 0 ? '-' : '+';
  return '$prefix${formatByteSize(bytes.abs())}';
}

String formatNullableByteSize(int? bytes, {String pendingLabel = '...'}) {
  return bytes == null ? pendingLabel : formatByteSize(bytes);
}

String formatMegabytesInput(int bytes) {
  if (bytes <= 0) return '0';
  final mb = bytes / kBytesPerMiB;
  final fixed = mb >= 100
      ? mb.toStringAsFixed(0)
      : (mb >= 10 ? mb.toStringAsFixed(1) : mb.toStringAsFixed(2));
  return _trimFractionZeros(fixed);
}

int megabytesTextToBytes(
  String value, {
  required int fallbackBytes,
  required int minBytes,
  required int maxBytes,
}) {
  final lower = minBytes <= maxBytes ? minBytes : maxBytes;
  final upper = minBytes <= maxBytes ? maxBytes : minBytes;
  final fallbackMb = fallbackBytes / kBytesPerMiB;
  final parsedMb = doubleFromValue(value, fallback: fallbackMb);
  if (parsedMb <= 0) {
    return lower <= 0 ? 0 : lower;
  }
  if (upper <= 0) {
    return upper;
  }
  final upperMb = upper / kBytesPerMiB;
  if (parsedMb >= upperMb) {
    return upper;
  }
  final bytes = (parsedMb * kBytesPerMiB).round();
  return bytes.clamp(lower, upper);
}

String _trimFractionZeros(String value) {
  if (!value.contains('.')) return value;
  final trimmed = value
      .replaceFirst(_trailingFractionZerosPattern, '')
      .replaceFirst(_trailingDecimalPointPattern, '');
  return trimmed.isEmpty ? '0' : trimmed;
}

import 'input_value_parsing.dart';

const int kBytesPerKiB = 1024;
const int kBytesPerMiB = kBytesPerKiB * 1024;
const int kBytesPerGiB = kBytesPerMiB * 1024;

const List<String> _byteSizeSiUnits = <String>['KB', 'MB', 'GB', 'TB', 'PB'];
const List<String> _byteSizeFrenchUnits = <String>[
  'Ko',
  'Mo',
  'Go',
  'To',
  'Po',
];

final RegExp _trailingFractionZerosPattern = RegExp(r'0+$');
final RegExp _trailingDecimalPointPattern = RegExp(r'\.$');

/// 格式化体积。默认英文单位，供工具回执和纯 Dart 检查使用。
/// 界面请走 [formatLocalizedByteSize]。
String formatByteSize(
  num bytes, {
  String languageCode = 'en',
  String? scriptCode,
  String? countryCode,
}) {
  final language = languageCode.toLowerCase();
  final byteUnit = _byteUnitLabel(
    language,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
  final scaledUnits = language == 'fr'
      ? _byteSizeFrenchUnits
      : _byteSizeSiUnits;
  if (!bytes.isFinite || bytes <= 0) return '0 $byteUnit';
  if (bytes < kBytesPerKiB) return '${bytes.round()} $byteUnit';

  double size = bytes / kBytesPerKiB;
  var unitIndex = 0;
  while (size >= kBytesPerKiB && unitIndex < scaledUnits.length - 1) {
    size /= kBytesPerKiB;
    unitIndex++;
  }

  final fractionDigits = size >= 100 ? 0 : (size >= 10 ? 1 : 2);
  return '${_trimFractionZeros(size.toStringAsFixed(fractionDigits))} '
      '${scaledUnits[unitIndex]}';
}

String formatSignedByteSize(
  num bytes, {
  String languageCode = 'en',
  String? scriptCode,
  String? countryCode,
}) {
  if (!bytes.isFinite || bytes == 0) {
    return formatByteSize(
      0,
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }
  final prefix = bytes < 0 ? '-' : '+';
  return '$prefix${formatByteSize(bytes.abs(), languageCode: languageCode, scriptCode: scriptCode, countryCode: countryCode)}';
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

String _byteUnitLabel(
  String language, {
  String? scriptCode,
  String? countryCode,
}) {
  switch (language) {
    case 'zh':
      return _isTraditionalChinese(
            scriptCode: scriptCode,
            countryCode: countryCode,
          )
          ? '位元組'
          : '字节';
    case 'ja':
      return 'バイト';
    case 'fr':
      return 'o';
    default:
      return 'B';
  }
}

bool _isTraditionalChinese({String? scriptCode, String? countryCode}) {
  final script = scriptCode?.toLowerCase();
  if (script == 'hant') return true;
  if (script == 'hans') return false;
  final country = countryCode?.toLowerCase();
  return country == 'tw' || country == 'hk' || country == 'mo';
}

String _trimFractionZeros(String value) {
  if (!value.contains('.')) return value;
  final trimmed = value
      .replaceFirst(_trailingFractionZerosPattern, '')
      .replaceFirst(_trailingDecimalPointPattern, '');
  return trimmed.isEmpty ? '0' : trimmed;
}

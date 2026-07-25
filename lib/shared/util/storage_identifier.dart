import 'path_safety.dart';

const int _maxSafeStorageIdentifierCodeUnits = 128;

bool isSafeStorageIdentifier(String value) {
  final normalizedValue = value.trim();
  return isPortableFileNamePart(
    normalizedValue,
    maxCodeUnits: _maxSafeStorageIdentifierCodeUnits,
  );
}

/// 去除首尾空白并校验文件系统存储标识符。
String requireSafeStorageIdentifier(
  String value, {
  required String label,
  Object Function(String message)? errorFactory,
}) {
  final normalizedValue = value.trim();
  if (isSafeStorageIdentifier(normalizedValue)) return normalizedValue;
  final message = '$label 无效。';
  throw (errorFactory?.call(message) ?? FormatException(message));
}

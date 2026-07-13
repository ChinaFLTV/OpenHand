import 'dart:convert';
import 'dart:io';

import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';

const int webEngineMaxJsonFileBytes = 16 * kBytesPerMiB;
const int webEngineMaxPayloadFileBytes = 64 * kBytesPerMiB;

final RegExp _webEngineCacheKeyPattern = RegExp(r'^[0-9a-f]{64}$');

bool isValidWebEngineCacheKey(String key) {
  return _webEngineCacheKeyPattern.hasMatch(key);
}

String? webEngineCachePayloadFileName(String key) {
  return isValidWebEngineCacheKey(key) ? '$key.txt' : null;
}

Future<Object?> readWebEngineJsonFile(
  File file, {
  int maxBytes = webEngineMaxJsonFileBytes,
}) async {
  final raw = await readBoundedFileString(file, maxBytes: maxBytes);
  return jsonDecode(raw);
}

Future<String> readWebEnginePayloadFile(File file) {
  return readBoundedFileString(file, maxBytes: webEngineMaxPayloadFileBytes);
}

Future<void> writeWebEngineJsonFile(File file, Object? value) async {
  final content = jsonEncode(value);
  if (utf8.encode(content).length > webEngineMaxJsonFileBytes) {
    throw const FileSystemException(
      'Web engine JSON exceeds the 16 MiB persistence limit.',
    );
  }
  await writeFileAtomically(file, content);
}

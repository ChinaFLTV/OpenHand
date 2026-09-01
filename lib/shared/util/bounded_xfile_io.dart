import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../net/http_response_utils.dart';
import 'argument_guards.dart';
import 'bounded_file_io.dart';

const Duration kBoundedXFileMetadataTimeout = Duration(seconds: 5);
const Duration kBoundedXFileIdleTimeout = Duration(seconds: 30);
const Duration kBoundedXFileTotalTimeout = Duration(minutes: 2);

/// 读取跨平台 [XFile] 时的大小超限异常。
final class BoundedXFileSizeException implements IOException {
  const BoundedXFileSizeException({required this.maxBytes, this.actualBytes});

  final int maxBytes;
  final int? actualBytes;

  @override
  String toString() {
    final actual = actualBytes;
    return actual == null
        ? '所选文件超过 $maxBytes 字节上限。'
        : '所选文件大小为 $actual 字节，超过 $maxBytes 字节上限。';
  }
}

/// 在内存和时间预算内读取 [XFile]，未知元数据或持续增长的来源不能绕过限制。
///
/// 原生路径文件使用单句柄实现；内存文件和 Web 文件使用有界、可取消的字节流。
Future<Uint8List> readBoundedXFileBytes(
  XFile file, {
  required int maxBytes,
  Duration idleTimeout = kBoundedXFileIdleTimeout,
  Duration totalTimeout = kBoundedXFileTotalTimeout,
  Duration metadataTimeout = kBoundedXFileMetadataTimeout,
}) async {
  requirePositiveInt(maxBytes, 'maxBytes');
  requirePositiveDuration(idleTimeout, 'idleTimeout');
  requirePositiveDuration(totalTimeout, 'totalTimeout');
  requirePositiveDuration(metadataTimeout, 'metadataTimeout');

  final knownLength = await _tryReadLength(file, metadataTimeout);
  if (knownLength != null && knownLength > maxBytes) {
    throw BoundedXFileSizeException(
      maxBytes: maxBytes,
      actualBytes: knownLength,
    );
  }

  try {
    final path = file.path.trim();
    if (!kIsWeb && path.isNotEmpty) {
      return await readBoundedFileBytes(
        File(path),
        maxBytes: maxBytes,
        idleTimeout: idleTimeout,
        totalTimeout: totalTimeout,
      );
    }
    return await readBoundedByteStream(
      file.openRead(),
      maxBytes: maxBytes,
      idleTimeout: idleTimeout,
      totalTimeout: totalTimeout,
    );
  } on BoundedFileReadException catch (error) {
    if (error.failure != BoundedFileReadFailure.tooLarge) rethrow;
    throw BoundedXFileSizeException(
      maxBytes: maxBytes,
      actualBytes: knownLength,
    );
  } on ByteStreamSizeLimitException {
    throw BoundedXFileSizeException(
      maxBytes: maxBytes,
      actualBytes: knownLength,
    );
  }
}

Future<int?> _tryReadLength(XFile file, Duration timeout) async {
  try {
    return await file.length().timeout(timeout);
  } catch (_) {
    return null;
  }
}

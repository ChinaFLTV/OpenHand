import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../net/http_response_utils.dart';
import 'bounded_file_io.dart';

const Duration kBoundedXFileMetadataTimeout = Duration(seconds: 5);
const Duration kBoundedXFileIdleTimeout = Duration(seconds: 30);
const Duration kBoundedXFileTotalTimeout = Duration(minutes: 2);

/// A size-limit failure while reading a platform-neutral [XFile].
final class BoundedXFileSizeException implements IOException {
  const BoundedXFileSizeException({required this.maxBytes, this.actualBytes});

  final int maxBytes;
  final int? actualBytes;

  @override
  String toString() {
    final actual = actualBytes;
    return actual == null
        ? 'Selected file exceeds the $maxBytes byte limit.'
        : 'Selected file is $actual bytes and exceeds the $maxBytes byte limit.';
  }
}

/// Reads an [XFile] without allowing unknown metadata or a growing source to
/// bypass the memory and time budgets.
///
/// Native path-backed files use the stricter single-handle implementation;
/// in-memory and web files fall back to a bounded, cancellable byte stream.
Future<Uint8List> readBoundedXFileBytes(
  XFile file, {
  required int maxBytes,
  Duration idleTimeout = kBoundedXFileIdleTimeout,
  Duration totalTimeout = kBoundedXFileTotalTimeout,
  Duration metadataTimeout = kBoundedXFileMetadataTimeout,
}) async {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero ||
      totalTimeout <= Duration.zero ||
      metadataTimeout <= Duration.zero) {
    throw ArgumentError('File read timeouts must be positive.');
  }

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

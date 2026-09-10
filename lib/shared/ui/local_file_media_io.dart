import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

Widget buildLocalSvgPicture(
  String path, {
  required BoxFit fit,
  required Widget fallback,
}) {
  return SvgPicture.file(
    io.File(path),
    fit: fit,
    placeholderBuilder: (context) => fallback,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

Widget buildLocalRasterImage(
  String path, {
  required BoxFit fit,
  required Widget fallback,
}) {
  final file = io.File(path);
  var version = 0;
  try {
    final stat = file.statSync();
    if (stat.type == io.FileSystemEntityType.file) {
      version = Object.hash(stat.modified.millisecondsSinceEpoch, stat.size);
    }
  } catch (_) {}
  return Image(
    image: _VersionedFileImage(file, version: version),
    fit: fit,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

/// 同路径覆盖写入后，用修改时间与大小区分缓存，避免卡片仍显示旧图。
class _VersionedFileImage extends FileImage {
  const _VersionedFileImage(super.file, {required this.version});

  final int version;

  @override
  bool operator ==(Object other) {
    return other is _VersionedFileImage &&
        other.file.path == file.path &&
        other.scale == scale &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(file.path, scale, version);
}

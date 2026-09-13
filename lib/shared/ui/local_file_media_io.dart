import 'dart:io' as io;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

typedef _LocalFileVersion = ({int changedMicros, int modifiedMicros, int size});

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
  _LocalFileVersion? version;
  try {
    final stat = file.statSync();
    if (stat.type == io.FileSystemEntityType.file) {
      version = (
        changedMicros: stat.changed.microsecondsSinceEpoch,
        modifiedMicros: stat.modified.microsecondsSinceEpoch,
        size: stat.size,
      );
    }
  } catch (_) {}
  return Image(
    image: _VersionedFileImage(file, version: version),
    fit: fit,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

/// 同路径覆盖写入后，用精确文件版本区分缓存，避免卡片仍显示旧图。
class _VersionedFileImage extends FileImage {
  const _VersionedFileImage(super.file, {required this.version});

  final _LocalFileVersion? version;

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

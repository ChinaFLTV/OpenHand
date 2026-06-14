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
  return Image.file(
    io.File(path),
    fit: fit,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

bool localFileExists(String path) {
  try {
    return io.File(path).existsSync();
  } on io.FileSystemException {
    return false;
  } on ArgumentError {
    return false;
  }
}

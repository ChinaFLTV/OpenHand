import 'package:flutter/widgets.dart';

bool openHandIsSafeInsetValue(double value) {
  return value.isFinite && value >= 0;
}

EdgeInsets openHandNonNegativeInsets(EdgeInsets value) {
  return EdgeInsets.fromLTRB(
    openHandIsSafeInsetValue(value.left) ? value.left : 0,
    openHandIsSafeInsetValue(value.top) ? value.top : 0,
    openHandIsSafeInsetValue(value.right) ? value.right : 0,
    openHandIsSafeInsetValue(value.bottom) ? value.bottom : 0,
  );
}

EdgeInsets openHandResolvedNonNegativeInsets(
  BuildContext context,
  EdgeInsetsGeometry value,
) {
  return openHandNonNegativeInsets(value.resolve(Directionality.of(context)));
}

EdgeInsets openHandResolvedInsetsOrFallback(
  BuildContext context,
  EdgeInsetsGeometry? value,
  EdgeInsets fallback,
) {
  final resolved = value?.resolve(Directionality.of(context)) ?? fallback;
  if (!openHandIsSafeInsetValue(resolved.left) ||
      !openHandIsSafeInsetValue(resolved.top) ||
      !openHandIsSafeInsetValue(resolved.right) ||
      !openHandIsSafeInsetValue(resolved.bottom)) {
    return fallback;
  }
  return resolved;
}

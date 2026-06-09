import 'package:flutter/material.dart';

bool openHandReduceMotionOf(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) == true;
}

bool openHandTickerMotionEnabled(BuildContext context) {
  return !openHandReduceMotionOf(context) &&
      TickerMode.valuesOf(context).enabled;
}

Duration openHandMotionDuration(BuildContext context, Duration duration) {
  if (duration <= Duration.zero || openHandReduceMotionOf(context)) {
    return Duration.zero;
  }
  return duration;
}

Duration openHandMotionDurationMs(BuildContext context, int milliseconds) {
  if (milliseconds <= 0 || openHandReduceMotionOf(context)) {
    return Duration.zero;
  }
  return Duration(milliseconds: milliseconds);
}

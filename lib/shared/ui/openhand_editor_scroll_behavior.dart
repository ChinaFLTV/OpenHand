import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Editor/code panes own their scrollbars and should not inherit Material's
/// default overscroll indicator. Keeping this behavior shared prevents the
/// gray edge glow/stretch from reappearing in source viewers.
class OpenHandEditorScrollBehavior extends MaterialScrollBehavior {
  const OpenHandEditorScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  // Work around a Flutter framework bug on macOS where trackpad events can
  // arrive with non-monotonic timestamps, causing an assertion failure in
  // IOSScrollViewFlingVelocityTracker.
  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return (PointerEvent event) => VelocityTracker.withKind(event.kind);
  }
}

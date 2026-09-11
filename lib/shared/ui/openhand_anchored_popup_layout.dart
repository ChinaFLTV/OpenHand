import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OpenHandPopupHorizontalAlignment { left, center, right }

/// 将锚点浮层限制在安全区域内，统一尺寸约束与上下翻转定位。
class OpenHandAnchoredPopupLayoutDelegate extends SingleChildLayoutDelegate {
  const OpenHandAnchoredPopupLayoutDelegate({
    required this.safeRect,
    required this.anchorRect,
    required this.placedAbove,
    required this.anchorGap,
    required this.minWidth,
    required this.maxWidth,
    required this.maxHeight,
    this.horizontalAlignment = OpenHandPopupHorizontalAlignment.center,
  });

  final Rect safeRect;
  final Rect anchorRect;
  final bool placedAbove;
  final double anchorGap;
  final double minWidth;
  final double maxWidth;
  final double maxHeight;
  final OpenHandPopupHorizontalAlignment horizontalAlignment;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final resolvedMaxWidth = _boundedDimension(maxWidth, constraints.maxWidth);
    final resolvedMinWidth = _boundedDimension(minWidth, resolvedMaxWidth);
    final resolvedMaxHeight = _boundedDimension(
      maxHeight,
      constraints.maxHeight,
    );
    return BoxConstraints(
      minWidth: resolvedMinWidth,
      maxWidth: resolvedMaxWidth,
      maxHeight: resolvedMaxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rawLeft = switch (horizontalAlignment) {
      OpenHandPopupHorizontalAlignment.left => anchorRect.left,
      OpenHandPopupHorizontalAlignment.center =>
        anchorRect.center.dx - childSize.width / 2,
      OpenHandPopupHorizontalAlignment.right =>
        anchorRect.right - childSize.width,
    };
    final rawTop = placedAbove
        ? anchorRect.top - childSize.height - anchorGap
        : anchorRect.bottom + anchorGap;
    return Offset(
      _clampCoordinate(
        rawLeft,
        lower: safeRect.left,
        upper: safeRect.right - childSize.width,
      ),
      _clampCoordinate(
        rawTop,
        lower: safeRect.top,
        upper: safeRect.bottom - childSize.height,
      ),
    );
  }

  @override
  bool shouldRelayout(
    covariant OpenHandAnchoredPopupLayoutDelegate oldDelegate,
  ) {
    return oldDelegate.safeRect != safeRect ||
        oldDelegate.anchorRect != anchorRect ||
        oldDelegate.placedAbove != placedAbove ||
        oldDelegate.anchorGap != anchorGap ||
        oldDelegate.minWidth != minWidth ||
        oldDelegate.maxWidth != maxWidth ||
        oldDelegate.maxHeight != maxHeight ||
        oldDelegate.horizontalAlignment != horizontalAlignment;
  }
}

Rect openHandOverlaySafeRect({
  required Size overlaySize,
  required EdgeInsets safePadding,
  required double viewportPadding,
}) {
  final width = _finiteNonNegative(overlaySize.width);
  final height = _finiteNonNegative(overlaySize.height);
  final margin = _finiteNonNegative(viewportPadding);
  final left = (_finiteNonNegative(safePadding.left) + margin).clamp(
    0.0,
    width,
  );
  final top = (_finiteNonNegative(safePadding.top) + margin).clamp(0.0, height);
  final right = math.max(
    left,
    width - _finiteNonNegative(safePadding.right) - margin,
  );
  final bottom = math.max(
    top,
    height - _finiteNonNegative(safePadding.bottom) - margin,
  );
  return Rect.fromLTRB(left, top, right, bottom);
}

Rect? openHandAnchorRectInOverlay({
  required GlobalKey anchorKey,
  required BuildContext overlayContext,
}) {
  final anchorObject = anchorKey.currentContext?.findRenderObject();
  final overlayObject = Overlay.maybeOf(
    overlayContext,
  )?.context.findRenderObject();
  if (anchorObject is! RenderBox ||
      overlayObject is! RenderBox ||
      !anchorObject.attached ||
      !overlayObject.attached ||
      !anchorObject.hasSize ||
      !overlayObject.hasSize ||
      anchorObject.size.isEmpty) {
    return null;
  }
  return anchorObject.localToGlobal(Offset.zero, ancestor: overlayObject) &
      anchorObject.size;
}

Rect openHandGlobalRectInOverlay(BuildContext context, Rect globalRect) {
  final overlayObject = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlayObject is! RenderBox || !overlayObject.attached) {
    return globalRect;
  }
  final origin = overlayObject.localToGlobal(Offset.zero);
  return globalRect.translate(-origin.dx, -origin.dy);
}

double _boundedDimension(double value, double upper) {
  final safeUpper = upper.isFinite ? math.max(0.0, upper) : double.infinity;
  return _finiteNonNegative(value).clamp(0.0, safeUpper);
}

double _finiteNonNegative(double value) {
  return value.isFinite && value > 0 ? value : 0;
}

double _clampCoordinate(
  double value, {
  required double lower,
  required double upper,
}) {
  if (!value.isFinite || !lower.isFinite) return 0;
  if (!upper.isFinite || upper <= lower) return lower;
  return value.clamp(lower, upper);
}

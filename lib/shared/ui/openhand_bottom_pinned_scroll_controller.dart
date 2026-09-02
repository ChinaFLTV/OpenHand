import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const double _scrollCorrectionEpsilon = 0.5;

/// 用户主动滚动到底部后，在列表内容高度变化时继续保持底部锚点。
class OpenHandBottomPinnedScrollController extends ScrollController {
  OpenHandBottomPinnedScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.pinThreshold = 2,
  });

  final double pinThreshold;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _OpenHandBottomPinnedScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      pinThreshold: pinThreshold,
    );
  }
}

class _OpenHandBottomPinnedScrollPosition
    extends ScrollPositionWithSingleContext {
  _OpenHandBottomPinnedScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.keepScrollOffset,
    required super.oldPosition,
    required super.debugLabel,
    required this.pinThreshold,
  });

  final double pinThreshold;
  bool _receivedUserScroll = false;

  @override
  void updateUserScrollDirection(ScrollDirection value) {
    if (value != ScrollDirection.idle) _receivedUserScroll = true;
    super.updateUserScrollDirection(value);
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final keepBottomPinned =
        _receivedUserScroll &&
        userScrollDirection != ScrollDirection.forward &&
        oldPosition.extentAfter <= pinThreshold;
    if (!keepBottomPinned) {
      return super.correctForNewDimensions(oldPosition, newPosition);
    }
    final target = newPosition.maxScrollExtent;
    if ((target - pixels).abs() <= _scrollCorrectionEpsilon) return true;
    correctPixels(target);
    return false;
  }
}

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

const Duration kAutoFollowProgrammaticSettleDuration = Duration(
  milliseconds: 260,
);
const Duration kAutoFollowPointerSignalActivityWindow = Duration(
  milliseconds: 900,
);

class AutoFollowProgrammaticScrollWindow {
  AutoFollowProgrammaticScrollWindow({
    this.settleDuration = kAutoFollowProgrammaticSettleDuration,
  });

  final Duration settleDuration;
  int _depth = 0;
  DateTime? _quietUntil;

  bool get busy => _depth > 0;

  bool get active {
    if (_depth > 0) return true;
    final quietUntil = _quietUntil;
    if (quietUntil == null) return false;
    if (DateTime.now().isBefore(quietUntil)) return true;
    _quietUntil = null;
    return false;
  }

  void begin() {
    _depth += 1;
    _extendQuietWindow();
  }

  void end() {
    if (_depth > 0) {
      _depth -= 1;
    }
    _extendQuietWindow();
  }

  void markSettling() => _extendQuietWindow();

  void cancel() {
    _depth = 0;
    _quietUntil = null;
  }

  void _extendQuietWindow() {
    _quietUntil = DateTime.now().add(settleDuration);
  }
}

/// Lightweight helper for log-style auto-follow lists where new content
/// continuously appends and the view should pin to the bottom — UNLESS the
/// user is actively dragging.
///
/// Drop-in usage: wrap the scroll view in `AutoFollowScrollGuard`. From the
/// owning state, replace any direct `controller.jumpTo(maxScrollExtent)` /
/// `animateTo(maxScrollExtent)` with `guard.followToBottom(controller, ...)`.
/// The guard records gestures via a `NotificationListener<ScrollNotification>`
/// and short-circuits programmatic scroll requests for as long as the user
/// is dragging, eliminating the "tractor pull" / 抽搐 / 鬼畜 feel that surfaces
/// when streaming-driven `jumpTo` fights touch / wheel events on the same
/// `ScrollPosition`.
class AutoFollowScrollGuard {
  AutoFollowScrollGuard();

  bool _userScrolling = false;
  final AutoFollowProgrammaticScrollWindow _programmaticScroll =
      AutoFollowProgrammaticScrollWindow();

  /// True while the user holds an active scroll gesture.
  bool get isUserScrolling => _userScrolling;

  /// Wire this into a `NotificationListener<ScrollNotification>.onNotification`.
  /// Returns `false` so other listeners can still process the notification.
  bool handleNotification(ScrollNotification notification) {
    final explicitUserScroll =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle);
    final userScrollEnded =
        notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);
    if (_programmaticScroll.active && !explicitUserScroll) {
      return false;
    }
    if (explicitUserScroll) {
      _programmaticScroll.cancel();
    }
    if (explicitUserScroll) {
      _userScrolling = true;
    } else if (userScrollEnded) {
      _userScrolling = false;
    }
    return false;
  }

  /// Best-effort jump / animate to the bottom of [controller]. Skipped when
  /// the user is currently dragging — once the drag ends, the next streaming
  /// append (or any caller-driven follow request) will succeed normally.
  ///
  /// When [animated] is `true`, an animated easeOutCubic glide is used; the
  /// short default duration keeps log lists "ticking" without feeling
  /// sluggish. When `false` (typical for huge log dumps), `jumpTo` is used
  /// for zero-cost catch-up.
  void followToBottom(
    ScrollController controller, {
    bool animated = false,
    Duration animationDuration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
  }) {
    if (_userScrolling) return;
    if (!controller.hasClients) return;
    final position = controller.position;
    final target = position.maxScrollExtent;
    if ((target - position.pixels).abs() < 0.5) return;
    if (!animated) {
      _programmaticScroll.begin();
      try {
        position.jumpTo(target);
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _programmaticScroll.end();
        });
      }
      return;
    }
    _programmaticScroll.begin();
    position
        .animateTo(target, duration: animationDuration, curve: curve)
        .whenComplete(_programmaticScroll.end);
  }
}

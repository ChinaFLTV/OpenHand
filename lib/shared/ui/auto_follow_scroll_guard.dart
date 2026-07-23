import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

const Duration kAutoFollowProgrammaticSettleDuration = Duration(
  milliseconds: 260,
);
const Duration kAutoFollowPointerSignalActivityWindow = Duration(
  milliseconds: 900,
);

bool isExplicitUserScrollNotification(
  ScrollNotification notification, {
  required bool programmaticScroll,
}) {
  return notification is ScrollStartNotification &&
          notification.dragDetails != null ||
      notification is ScrollUpdateNotification &&
          notification.dragDetails != null ||
      notification is OverscrollNotification &&
          notification.dragDetails != null ||
      notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle &&
          !programmaticScroll;
}

bool isUserScrollEndNotification(ScrollNotification notification) {
  return notification is ScrollEndNotification ||
      notification is UserScrollNotification &&
          notification.direction == ScrollDirection.idle;
}

class AutoFollowProgrammaticScrollWindow {
  AutoFollowProgrammaticScrollWindow({
    this.settleDuration = kAutoFollowProgrammaticSettleDuration,
  });

  final Duration settleDuration;
  int _depth = 0;
  final Stopwatch _settleStopwatch = Stopwatch();

  bool get busy => _depth > 0;

  bool get active {
    if (_depth > 0) return true;
    if (!_settleStopwatch.isRunning) return false;
    if (_settleStopwatch.elapsed < settleDuration) return true;
    _settleStopwatch
      ..stop()
      ..reset();
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
    _settleStopwatch
      ..stop()
      ..reset();
  }

  void _extendQuietWindow() {
    _settleStopwatch
      ..reset()
      ..start();
  }
}

/// 管理持续追加内容列表的自动贴底，用户主动滚动期间暂停跟随。
///
/// 通过 [handleNotification] 记录用户手势，并由 [followToBottom] 统一执行
/// 跳转或动画，避免流式更新与用户滚动争抢同一 ScrollPosition。
class AutoFollowScrollGuard {
  AutoFollowScrollGuard();

  bool _userScrolling = false;
  final AutoFollowProgrammaticScrollWindow _programmaticScroll =
      AutoFollowProgrammaticScrollWindow();

  /// 用户滚动手势是否仍在进行。
  bool get isUserScrolling => _userScrolling;

  /// 接入 NotificationListener.onNotification；固定返回 false 以继续冒泡。
  bool handleNotification(ScrollNotification notification) {
    final programmaticScroll = _programmaticScroll.active;
    final explicitUserScroll = isExplicitUserScrollNotification(
      notification,
      programmaticScroll: programmaticScroll,
    );
    final userScrollEnded = isUserScrollEndNotification(notification);
    if (programmaticScroll && !explicitUserScroll) {
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

  /// 尝试把 [controller] 移到底部；用户滚动期间直接跳过。
  ///
  /// [animated] 为 true 时使用短动画，否则直接 jumpTo。
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

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import 'motion_preference.dart';

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

/// 无 dragDetails 的 start / update / overscroll 是否应归类为滚轮或触控板输入。
///
/// 只有 Listener 真实捕获到 PointerScrollEvent（[recentPointerSignalScroll]）
/// 之后才成立：流式内容增高、Sliver 几何修正同样会产生无 dragDetails 的
/// notification，一概当作用户输入会把贴底跟随误判为「用户正在滚动」，
/// 导致增量输出不再追到最新内容。
bool isImplicitPointerSignalScrollNotification(
  ScrollNotification notification, {
  required bool programmaticScroll,
  required bool recentPointerSignalScroll,
}) {
  return !programmaticScroll &&
      recentPointerSignalScroll &&
      (notification is ScrollStartNotification ||
          notification is ScrollUpdateNotification ||
          notification is OverscrollNotification);
}

bool isUserScrollEndNotification(ScrollNotification notification) {
  return notification is ScrollEndNotification ||
      notification is UserScrollNotification &&
          notification.direction == ScrollDirection.idle;
}

/// 自动跟随列表关心的标准化滚动活动。
class AutoFollowScrollActivity {
  const AutoFollowScrollActivity({
    required this.explicitUserScroll,
    required this.implicitPointerSignalScroll,
    required this.userScrollEnded,
  });

  final bool explicitUserScroll;
  final bool implicitPointerSignalScroll;
  final bool userScrollEnded;

  bool get userScrollActive =>
      explicitUserScroll || implicitPointerSignalScroll;
}

AutoFollowScrollActivity classifyAutoFollowScrollActivity(
  ScrollNotification notification, {
  required bool programmaticScroll,
  bool recentPointerSignalScroll = false,
}) {
  return AutoFollowScrollActivity(
    explicitUserScroll: isExplicitUserScrollNotification(
      notification,
      programmaticScroll: programmaticScroll,
    ),
    implicitPointerSignalScroll: isImplicitPointerSignalScrollNotification(
      notification,
      programmaticScroll: programmaticScroll,
      recentPointerSignalScroll: recentPointerSignalScroll,
    ),
    userScrollEnded: isUserScrollEndNotification(notification),
  );
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
  bool _userScrolling = false;
  bool _followScheduled = false;
  final AutoFollowProgrammaticScrollWindow _programmaticScroll =
      AutoFollowProgrammaticScrollWindow();

  /// 用户滚动手势是否仍在进行。
  bool get isUserScrolling => _userScrolling;

  /// 接入 NotificationListener.onNotification；固定返回 false 以继续冒泡。
  bool handleNotification(ScrollNotification notification) {
    final programmaticScroll = _programmaticScroll.active;
    final activity = classifyAutoFollowScrollActivity(
      notification,
      programmaticScroll: programmaticScroll,
    );
    if (programmaticScroll && !activity.explicitUserScroll) {
      return false;
    }
    if (activity.explicitUserScroll) {
      _programmaticScroll.cancel();
      _userScrolling = true;
    } else if (activity.userScrollEnded) {
      _userScrolling = false;
    }
    return false;
  }

  /// 合并同一帧内的多次贴底请求，避免流式日志为每一行重复注册回调。
  void scheduleFollowToBottom(
    ScrollController controller, {
    bool animated = false,
    Duration animationDuration = const Duration(milliseconds: 180),
    Curve curve = kOpenHandSwitchInCurve,
  }) {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      followToBottom(
        controller,
        animated: animated,
        animationDuration: animationDuration,
        curve: curve,
      );
    });
  }

  /// 尝试把 [controller] 移到底部；用户滚动期间直接跳过。
  ///
  /// [animated] 为 true 时使用短动画，否则直接 jumpTo。
  void followToBottom(
    ScrollController controller, {
    bool animated = false,
    Duration animationDuration = const Duration(milliseconds: 180),
    Curve curve = kOpenHandSwitchInCurve,
  }) {
    _followToEdge(
      controller,
      target: (position) => position.maxScrollExtent,
      animated: animated,
      animationDuration: animationDuration,
      curve: curve,
    );
  }

  /// 尝试把反向列表移到最新内容所在的起点。
  ///
  /// 日志等持续追加的倒序列表把最新一行放在 [minScrollExtent]，
  /// 这样新增内容不会触发跨越整段历史的滚动动画。
  void followToStart(
    ScrollController controller, {
    bool animated = false,
    Duration animationDuration = const Duration(milliseconds: 180),
    Curve curve = kOpenHandSwitchInCurve,
  }) {
    _followToEdge(
      controller,
      target: (position) => position.minScrollExtent,
      animated: animated,
      animationDuration: animationDuration,
      curve: curve,
    );
  }

  void _followToEdge(
    ScrollController controller, {
    required double Function(ScrollPosition position) target,
    required bool animated,
    required Duration animationDuration,
    required Curve curve,
  }) {
    if (_userScrolling) return;
    if (!controller.hasClients) return;
    final position = controller.position;
    final targetOffset = target(
      position,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((targetOffset - position.pixels).abs() < 0.5) return;
    if (!animated) {
      _programmaticScroll.begin();
      try {
        position.jumpTo(targetOffset);
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _programmaticScroll.end();
        });
      }
      return;
    }
    _programmaticScroll.begin();
    position
        .animateTo(targetOffset, duration: animationDuration, curve: curve)
        .whenComplete(_programmaticScroll.end);
  }
}

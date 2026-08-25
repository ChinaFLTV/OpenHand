import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'openhand_safe_scrollbar.dart';

/// 应用内滚动行为的公共基类。
///
/// 统一两件事：
/// * 屏蔽 Material 默认的边缘辉光 / 拉伸——应用自己画滚动条与边界反馈；
/// * 绕开 Flutter 在 macOS 上的一个缺陷：触控板事件可能带非单调时间戳，
///   进入 IOSScrollViewFlingVelocityTracker 后触发断言失败。
///
/// 编辑器与弹窗共用这两项行为，避免滚动策略漂移。
abstract class OpenHandScrollBehaviorBase extends MaterialScrollBehavior {
  const OpenHandScrollBehaviorBase();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return (PointerEvent event) => VelocityTracker.withKind(event.kind);
  }
}

/// 桌面端为滚动域套全局隐式安全滚动条。
class OpenHandImplicitScrollbarBehavior extends OpenHandScrollBehaviorBase {
  const OpenHandImplicitScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return buildOpenHandImplicitScrollbar(
      platform: getPlatform(context),
      child: child,
      details: details,
    );
  }
}

/// 编辑器 / 代码面板自带滚动条，不再套一层 Material 默认滚动条。
class OpenHandEditorScrollBehavior extends OpenHandScrollBehaviorBase {
  const OpenHandEditorScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

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
/// 编辑器与弹窗此前各自重复了这两个覆写，其中弹窗那份还漏抄了绕行说明，
/// 后来者很容易当成可以删掉的冗余代码。
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

/// 桌面端为滚动域套全局隐式安全滚动条；App 根滚动配置与弹窗滚动域共用，
/// 此前两处各自维护一份相同的 [buildScrollbar] 覆写。
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

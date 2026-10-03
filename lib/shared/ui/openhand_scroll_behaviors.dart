import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'openhand_safe_scrollbar.dart';

/// 应用内默认滚动物理：始终可滚、到达两端即夹紧。
///
/// iOS/macOS 默认回弹会与贴底修正、测高补偿互相拉扯，造成两端快速抽搐。
const ClampingScrollPhysics kOpenHandClampingPhysics = ClampingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// 应用内滚动行为的公共基类。
///
/// 统一滚动体验：
/// * 嵌套滚动到边界后将剩余位移交给外层，保留双轴输入；
/// * 屏蔽 Material 默认的边缘辉光 / 拉伸——应用自己画滚动条与边界反馈；
/// * 两端使用夹紧物理，避免回弹与布局补偿互抢；
/// * 绕开 Flutter 在 macOS 上的一个缺陷：触控板事件可能带非单调时间戳，
///   进入 IOSScrollViewFlingVelocityTracker 后触发断言失败。
///
/// 编辑器与弹窗共用这些行为，避免滚动策略漂移。
abstract class OpenHandScrollBehaviorBase extends MaterialScrollBehavior {
  const OpenHandScrollBehaviorBase();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return kOpenHandClampingPhysics;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        final velocity = notification.dragDetails?.primaryVelocity;
        if (notification.depth == 0 && velocity != null && velocity != 0) {
          final metrics = notification.metrics;
          final offsetVelocity =
              -velocity * (axisDirectionIsReversed(details.direction) ? -1 : 1);
          if ((offsetVelocity > 0 && metrics.extentAfter == 0) ||
              (offsetVelocity < 0 && metrics.extentBefore == 0)) {
            _forwardMomentum(context, details.direction, offsetVelocity);
          }
        }
        return false;
      },
      child: NotificationListener<OverscrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              (notification.dragDetails == null &&
                  notification.velocity == 0)) {
            return false;
          }
          var remaining =
              notification.overscroll *
              (axisDirectionIsReversed(details.direction) ? -1 : 1);
          final axis = axisDirectionToAxis(details.direction);
          var ancestor = Scrollable.maybeOf(context);
          while (ancestor != null && remaining.abs() > 0.001) {
            final position = ancestor.position;
            if (axisDirectionToAxis(position.axisDirection) == axis &&
                position.hasContentDimensions &&
                position.physics.shouldAcceptUserOffset(position)) {
              final sign = axisDirectionIsReversed(position.axisDirection)
                  ? -1.0
                  : 1.0;
              final before = position.pixels;
              if (notification.dragDetails == null &&
                  position.isScrollingNotifier.value) {
                return false;
              }
              final target = (before + remaining * sign).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              );
              if (target != before) {
                position.pointerScroll(target - before);
                remaining -= (position.pixels - before) * sign;
                if (notification.dragDetails == null) {
                  _forwardMomentum(
                    context,
                    details.direction,
                    notification.velocity,
                  );
                  break;
                }
              }
            }
            ancestor = Scrollable.maybeOf(ancestor.context);
          }
          return false;
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            final controller = details.controller;
            if (controller == null || controller.positions.length != 1) return;
            final position = controller.position;
            if (!position.hasContentDimensions ||
                !position.physics.shouldAcceptUserOffset(position)) {
              return;
            }
            final state = position.context;
            if (state is! ScrollableState) return;
            final original = event.original ?? event;
            final chain = _scrollChains[original] ??= _OpenHandScrollChain(
              event,
            );
            chain.add(state, position, pointerAxisModifiers);
          },
          child: child,
        ),
      ),
    );
  }

  void _forwardMomentum(
    BuildContext context,
    AxisDirection direction,
    double velocity,
  ) {
    final axis = axisDirectionToAxis(direction);
    final physicalVelocity =
        velocity * (axisDirectionIsReversed(direction) ? -1 : 1);
    var ancestor = Scrollable.maybeOf(context);
    while (ancestor != null) {
      final position = ancestor.position;
      // 旧的内部惯性不能抢占外层已经开始的滚动。
      if (position.isScrollingNotifier.value) return;
      final offsetVelocity =
          physicalVelocity *
          (axisDirectionIsReversed(position.axisDirection) ? -1 : 1);
      if (position is ScrollPositionWithSingleContext &&
          axisDirectionToAxis(position.axisDirection) == axis &&
          position.hasContentDimensions &&
          position.physics.shouldAcceptUserOffset(position) &&
          ((offsetVelocity > 0 && position.extentAfter > 0) ||
              (offsetVelocity < 0 && position.extentBefore > 0))) {
        // 子滚动区触边后延续原速度，由外层物理模型自然减速。
        position.goBallistic(offsetVelocity);
        return;
      }
      ancestor = Scrollable.maybeOf(ancestor.context);
    }
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

final _scrollChains = Expando<_OpenHandScrollChain>();

/// 框架先处理命中的滚动域，仅将未消费的滚动量交给同一路径的外层。
class _OpenHandScrollChain {
  _OpenHandScrollChain(this.event) {
    scheduleMicrotask(_finish);
  }

  final PointerScrollEvent event;
  final _positions =
      <
        ({
          ScrollableState state,
          ScrollPosition position,
          double before,
          Axis axis,
          double sign,
        })
      >[];

  void add(
    ScrollableState state,
    ScrollPosition position,
    Set<LogicalKeyboardKey> modifiers,
  ) {
    if (_positions.any((entry) => identical(entry.position, position))) return;
    final flip =
        event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed.any(modifiers.contains);
    final axis = axisDirectionToAxis(position.axisDirection);
    _positions.add((
      state: state,
      position: position,
      before: position.pixels,
      axis: flip ? flipAxis(axis) : axis,
      sign: axisDirectionIsReversed(position.axisDirection) ? -1 : 1,
    ));
  }

  void _finish() {
    if (_positions.length < 2) return;
    for (final axis in Axis.values) {
      var remaining = axis == Axis.vertical
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      if (remaining == 0) continue;
      final entries = _positions
          .where(
            (entry) =>
                entry.axis == axis &&
                entry.state.mounted &&
                identical(entry.state.position, entry.position),
          )
          .toList();
      // 已发生的位移由框架处理，不能再重复应用。
      for (final entry in entries) {
        remaining -= (entry.position.pixels - entry.before) * entry.sign;
      }
      final original = axis == Axis.vertical
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      if (remaining * original <= 0) continue;
      for (final entry in entries) {
        final position = entry.position;
        final before = position.pixels;
        final target = (before + remaining * entry.sign).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (target == before) continue;
        position.pointerScroll(target - before);
        remaining -= (position.pixels - before) * entry.sign;
        event.respond(allowPlatformDefault: false);
        if (remaining.abs() < 0.001) break;
      }
    }
  }
}

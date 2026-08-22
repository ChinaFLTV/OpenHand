import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 拖拽副本的放大幅度与投影参数。
const double _kReorderProxyScaleGain = 0.018;
const double _kReorderProxyShadowAlpha = 0.12;
const double _kReorderProxyShadowBlur = 18;
const double _kReorderProxyShadowOffsetY = 8;

/// 标记当前子树正在渲染拖拽副本。
class OpenHandReorderProxyContext extends InheritedWidget {
  const OpenHandReorderProxyContext({super.key, required super.child});

  static bool isProxy(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OpenHandReorderProxyContext>() !=
      null;

  @override
  bool updateShouldNotify(OpenHandReorderProxyContext oldWidget) => false;
}

/// ReorderableListView 的拖拽副本装饰。
///
/// 默认副本会把行套进一个方形 Material，边界越过卡片自身的圆角，拖动时留下
/// 一圈难看的直角光晕。这里换成透明 Material，只保留卡片自己的形状，再补一层
/// 随拖起进度增强的投影与轻微放大，让"拿起来"这件事看得出来。
///
/// 时长与曲线跟随全局动效设置：关闭动效时直接停在终态，不做插值。
Widget buildOpenHandReorderProxy(
  BuildContext context,
  Widget child,
  Animation<double> animation,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final motionEnabled = openHandTickerMotionEnabled(context);
  return AnimatedBuilder(
    animation: animation,
    child: Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: OpenHandReorderProxyContext(child: child),
    ),
    builder: (context, proxyChild) {
      final raw = animation.value.clamp(0.0, 1.0);
      final t = motionEnabled ? kOpenHandEntranceCurve.transform(raw) : 1.0;
      return Transform.scale(
        scale: 1 + _kReorderProxyScaleGain * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: _kReorderProxyShadowAlpha * t,
                ),
                blurRadius: _kReorderProxyShadowBlur * t,
                offset: Offset(0, _kReorderProxyShadowOffsetY * t),
              ),
            ],
          ),
          child: proxyChild,
        ),
      );
    },
  );
}

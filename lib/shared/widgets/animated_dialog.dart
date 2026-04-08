import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

/// Shows a dialog with configurable entrance and exit animations.
///
/// When [settings] is null, the animation configuration is automatically
/// read from the nearest [SettingsController] in the widget tree.
/// Falls back to default animation settings if no controller is found.
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final effectiveSettings = settings ??
      context.read<SettingsController>().dialogAnimationSettings;
  if (effectiveSettings.entranceStyle == DialogAnimationStyle.none &&
      effectiveSettings.exitStyle == DialogAnimationStyle.none) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor ?? Colors.black54,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    transitionDuration: effectiveSettings.duration,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return _buildTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        settings: effectiveSettings,
        child: child,
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

Widget _buildTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required DialogAnimationSettings settings,
  required Widget child,
}) {
  final forward = animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.completed;
  final style = forward ? settings.entranceStyle : settings.exitStyle;
  final curveData = settings.curve;
  final curved = CurvedAnimation(
    parent: animation,
    curve: curveData.curve,
    reverseCurve: curveData.reverseCurve,
  );

  return switch (style) {
    DialogAnimationStyle.none => FadeTransition(
        opacity: animation,
        child: child,
      ),
    DialogAnimationStyle.fadeScale => _FadeScaleTransition(
        animation: curved,
        child: child,
      ),
    DialogAnimationStyle.slideUp => _SlideTransition(
        animation: curved,
        beginOffset: const Offset(0, 0.15),
        child: child,
      ),
    DialogAnimationStyle.slideDown => _SlideTransition(
        animation: curved,
        beginOffset: const Offset(0, -0.15),
        child: child,
      ),
    DialogAnimationStyle.expand => _ExpandTransition(
        animation: curved,
        child: child,
      ),
    DialogAnimationStyle.rotateScale => _RotateScaleTransition(
        animation: curved,
        child: child,
      ),
    DialogAnimationStyle.elastic => _ElasticTransition(
        animation: curved,
        child: child,
      ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual transition widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FadeScaleTransition extends StatelessWidget {
  const _FadeScaleTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
        child: child,
      ),
    );
  }
}

class _SlideTransition extends StatelessWidget {
  const _SlideTransition({
    required this.animation,
    required this.beginOffset,
    required this.child,
  });
  final Animation<double> animation;
  final Offset beginOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }
}

class _ExpandTransition extends StatelessWidget {
  const _ExpandTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _RotateScaleTransition extends StatelessWidget {
  const _RotateScaleTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 0.7, end: 1.0).animate(animation);
    final rotation = Tween<double>(begin: -0.05, end: 0.0).animate(animation);
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: scale,
        child: RotationTransition(turns: rotation, child: child),
      ),
    );
  }
}

class _ElasticTransition extends StatelessWidget {
  const _ElasticTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
        child: child,
      ),
    );
  }
}

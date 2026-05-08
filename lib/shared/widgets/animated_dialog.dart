import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

Color resolveAnimatedDialogBarrierColor(
  BuildContext context, {
  Color? override,
}) {
  if (override != null) {
    return override;
  }
  return Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54);
}

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
  final themedBuilder = _wrapDialogBuilderWithTheme(
    builder,
    dismissOnEscape: barrierDismissible,
  );
  final effectiveSettings =
      settings ?? _resolveDialogAnimationSettings(context);
  if (effectiveSettings.entranceStyle == DialogAnimationStyle.none &&
      effectiveSettings.exitStyle == DialogAnimationStyle.none) {
    return showDialog<T>(
      context: context,
      builder: themedBuilder,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: resolveAnimatedDialogBarrierColor(
        context,
        override: barrierColor,
      ),
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: resolveAnimatedDialogBarrierColor(
      context,
      override: barrierColor,
    ),
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
    pageBuilder: (context, animation, secondaryAnimation) =>
        themedBuilder(context),
  );
}

DialogAnimationSettings _resolveDialogAnimationSettings(BuildContext context) {
  try {
    return context.read<SettingsController>().dialogAnimationSettings;
  } catch (_) {
    return const DialogAnimationSettings();
  }
}

/// Shows an animated dialog with a themed shell so teams can keep dialog
/// visuals consistent (Material 3 / Material You expressive) while still
/// customizing body content.
Future<T?> showAnimatedThemedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  return showAnimatedDialog<T>(
    context: context,
    settings: settings,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    builder: builder,
  );
}

WidgetBuilder _wrapDialogBuilderWithTheme(
  WidgetBuilder builder, {
  required bool dismissOnEscape,
}) {
  return (dialogContext) {
    final theme = Theme.of(dialogContext);
    final colorScheme = theme.colorScheme;
    final themed = Theme(
      data: theme.copyWith(
        dialogTheme: theme.dialogTheme.copyWith(
          backgroundColor: colorScheme.surfaceContainerHigh,
          surfaceTintColor: colorScheme.surfaceTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      child: builder(dialogContext),
    );
    if (!dismissOnEscape) return themed;
    return _EscapeDismissDialogScope(child: themed);
  };
}

/// Adds Escape-to-dismiss to a dialog without stealing focus from descendant
/// inputs. Earlier revision wrapped the body in `Focus(autofocus: true, ...)`
/// + `Shortcuts/Actions`，那会抢走对话框内 `TextField` 的 autofocus，并让
/// macOS / Web 端的输入法上下文与剪贴板快捷键失效（无法输入/复制/粘贴）。
/// 改用 [CallbackShortcuts]：它只为子树注册键盘绑定、自身不申请焦点、不与
/// `DefaultTextEditingShortcuts` 抢同名 Intent。Esc 会从对话框内当前焦点节点
/// (按钮 / TextField) 沿 `Shortcuts` 链冒泡命中此处，触发 `maybePop`。
class _EscapeDismissDialogScope extends StatelessWidget {
  const _EscapeDismissDialogScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          unawaited(Navigator.of(context).maybePop());
        },
      },
      child: child,
    );
  }
}

Widget _buildTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required DialogAnimationSettings settings,
  required Widget child,
}) {
  return buildAnimationStyleTransition(
    animation: animation,
    settings: settings,
    child: child,
  );
}

/// Public, shared transition builder so non-dialog surfaces (chips,
/// list-item entrances/exits, tooltips, ...) can reuse the same library
/// of styles as the dialog system. The forward/reverse style is picked
/// based on the controller's status: while running forward (or already
/// completed) we use [DialogAnimationSettings.entranceStyle], otherwise
/// the [DialogAnimationSettings.exitStyle].
Widget buildAnimationStyleTransition({
  required Animation<double> animation,
  required DialogAnimationSettings settings,
  required Widget child,
}) {
  final forward =
      animation.status == AnimationStatus.forward ||
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
    DialogAnimationStyle.fade => FadeTransition(opacity: curved, child: child),
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
    DialogAnimationStyle.slideLeft => _SlideTransition(
      animation: curved,
      beginOffset: const Offset(-0.25, 0),
      child: child,
    ),
    DialogAnimationStyle.slideRight => _SlideTransition(
      animation: curved,
      beginOffset: const Offset(0.25, 0),
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
      animation: animation,
      curve: curveData,
      child: child,
    ),
    DialogAnimationStyle.springScale => _SpringScaleTransition(
      animation: animation,
      child: child,
    ),
    DialogAnimationStyle.flipX => _FlipXTransition(
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
        position: Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(animation),
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
  const _ElasticTransition({
    required this.animation,
    required this.curve,
    required this.child,
  });
  final Animation<double> animation;
  final DialogAnimationCurve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
    );
    final scale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: curve.curve,
        reverseCurve: curve.reverseCurve,
      ),
    );
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}

/// Q-bouncy spring scale: easeOutBack overshoot on entrance + slight
/// fade window. Reverse uses easeInBack so exit also feels springy.
class _SpringScaleTransition extends StatelessWidget {
  const _SpringScaleTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
    );
    final scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack,
      ),
    );
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}

/// 3D card-flip on the X axis with fade — useful for chip / list-item
/// "appear" feels when something switches in/out of place.
class _FlipXTransition extends StatelessWidget {
  const _FlipXTransition({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = animation.value;
        // -pi/2 → 0 ; clamp opacity so the back-face moment isn't visible.
        final angle = (1.0 - t) * 1.5708;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateX(angle);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

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
///
/// [dismissOnEscape] is decoupled from [barrierDismissible]: by default ESC
/// always closes the dialog, even when outside-tap is blocked. Long-running
/// task dialogs (export progress / image processing) opt out via
/// `dismissOnEscape: false`.
Future<T?> showAnimatedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  final themedBuilder = _wrapDialogBuilderWithTheme(
    builder,
    dismissOnEscape: dismissOnEscape,
    alignment: alignment,
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
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  return showAnimatedDialog<T>(
    context: context,
    settings: settings,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    alignment: alignment,
    builder: builder,
  );
}

Future<T?> showAnimatedModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool showDragHandle = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(8, 0, 8, 8),
}) {
  return showAnimatedDialog<T>(
    context: context,
    settings: settings,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    alignment: Alignment.bottomCenter,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colorScheme = theme.colorScheme;
      final size = MediaQuery.sizeOf(sheetContext);
      final viewportWidth = size.width * 0.95;
      final sheetWidth = viewportWidth > 980 ? 980.0 : viewportWidth;
      final sheetShape =
          shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
      final content = builder(sheetContext);
      final body = showDragHandle
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _ModalSheetDragHandle(),
                Flexible(child: content),
              ],
            )
          : content;

      return SafeArea(
        top: false,
        child: Padding(
          padding: margin,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: sheetWidth),
            child: Material(
              type: MaterialType.card,
              elevation: 8,
              color: backgroundColor ?? colorScheme.surfaceContainerHigh,
              surfaceTintColor: colorScheme.surfaceTint,
              shape: sheetShape,
              clipBehavior: Clip.antiAlias,
              child: body,
            ),
          ),
        ),
      );
    },
  );
}

WidgetBuilder _wrapDialogBuilderWithTheme(
  WidgetBuilder builder, {
  required bool dismissOnEscape,
  required AlignmentGeometry alignment,
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
    // 视口收缩：保证任何子弹窗的最大尺寸不超过当前屏幕的 95%，
    // 在窄屏 / 浮动小窗模式下不会贴边或溢出。
    // 只设置上限，不强行撑满，原本小弹窗（install_guide 等）不受影响。
    final clamped = _ViewportClamp(alignment: alignment, child: themed);
    if (!dismissOnEscape) return clamped;
    return _EscapeDismissDialogScope(child: clamped);
  };
}

/// 在弹窗外层套一个 MediaQuery 感知的 ConstrainedBox，把最大宽 / 高限制为
/// 视口的 95%。子弹窗自身的 maxWidth/maxHeight 仍生效——两个约束取最小值。
class _ViewportClamp extends StatelessWidget {
  const _ViewportClamp({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width * 0.95;
    final maxH = size.height * 0.95;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: child,
      ),
    );
  }
}

class _ModalSheetDragHandle extends StatelessWidget {
  const _ModalSheetDragHandle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const SizedBox(width: 36, height: 4),
      ),
    );
  }
}

/// Adds Escape-to-dismiss to a dialog without stealing focus from descendant
/// inputs. Uses ONLY [CallbackShortcuts] — `Focus(autofocus: true)` and
/// `FocusScope(autofocus: true)` both regress macOS IMK and leave every
/// `TextField` (in this dialog and globally afterwards) unable to receive
/// input / copy / paste. The dialog's `ModalRoute` already installs a focus
/// scope that traps key events to the dialog subtree, so ESC keystrokes will
/// bubble up through this [CallbackShortcuts] whether a `TextField` /
/// `Button` has focus or the modal route's own focus node owns it.
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

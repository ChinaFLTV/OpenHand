import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/bounded_animation.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/openhand_snack_bar.dart';

const EdgeInsets kWebReverseStatusBarPadding = EdgeInsets.fromLTRB(
  16,
  8,
  16,
  8,
);

const OpenHandAnimationTransitionProfile kWebReverseDialogMotionProfile =
    OpenHandAnimationTransitionProfile(
      fadeScaleBegin: 0.925,
      expandScaleBegin: 0.86,
      rotateScaleBegin: 0.88,
      elasticScaleBegin: 0.90,
      springScaleBegin: 0.90,
      slideUpOffset: Offset(0, 0.16),
      slideDownOffset: Offset(0, -0.14),
      slideLeftOffset: Offset(-0.18, 0),
      slideRightOffset: Offset(0.18, 0),
    );

/// Shows a Web Reverse tool dialog with one feature-level motion profile.
///
/// The route still reads the global dialog animation settings through
/// [showAnimatedDialog]; this helper only centralizes the Web Reverse
/// transition geometry so all tool dialogs can be tuned in one place.
Future<T?> showWebReverseToolDialog<T>({
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
  return showOpenHandProfiledDialog<T>(
    context: context,
    settings: settings,
    transitionProfile: kWebReverseDialogMotionProfile,
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

void showWebReverseSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarSuccessDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandSuccessSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showWebReverseErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarErrorDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandErrorSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showWebReverseInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarInfoDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  showOpenHandInfoSnack(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

Widget buildWebReverseStatusBar(
  BuildContext context, {
  required String status,
  EdgeInsetsGeometry padding = kWebReverseStatusBarPadding,
}) {
  final text = status.trim();
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final duration = openHandMotionDurationMs(context, 180);
  final child = text.isEmpty
      ? const SizedBox.shrink(key: ValueKey<String>('empty'))
      : Container(
          key: ValueKey<String>(text),
          width: double.infinity,
          color: colorScheme.surfaceContainerHigh,
          padding: padding,
          child: Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        );
  return AnimatedSwitcher(
    duration: duration,
    reverseDuration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (currentChild, previousChildren) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      );
    },
    transitionBuilder: (child, animation) {
      final curved = openHandBoundedCurveAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SizeTransition(
          sizeFactor: curved,
          axisAlignment: -1,
          child: child,
        ),
      );
    },
    child: child,
  );
}

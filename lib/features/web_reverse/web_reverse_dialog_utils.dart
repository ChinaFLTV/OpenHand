import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../l10n/app_localizations.dart';
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

/// 使用 Web 逆向模块统一的动效参数显示工具弹窗。
///
/// 路由仍通过 [showAnimatedDialog] 读取全局弹窗设置；这里只统一模块内的
/// 过渡几何参数。
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

Future<void> confirmWebReverseDiscardChanges({
  required BuildContext context,
  required FutureOr<void> Function() onConfirmed,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showOpenHandConfirmDialog(
    context: context,
    title: l10n?.webReverseHooksDiscardTitle ?? 'Discard unsaved changes?',
    cancelLabel: l10n?.webReverseHooksKeepEditing ?? 'Keep editing',
    confirmLabel: l10n?.webReverseHooksDiscardConfirm ?? 'Discard',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await onConfirmed();
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

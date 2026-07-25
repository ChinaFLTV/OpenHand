import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../util/localized_text.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_tooltip_dismissal.dart';
import 'safe_edge_insets.dart';

const double kOpenHandDialogViewportFraction = 0.95;
const double kOpenHandDialogDefaultMaxWidth = 520;
const double kOpenHandDialogDefaultRadius = 28;
const double kOpenHandDialogFormRadius = 16;
const double kOpenHandDialogActionSpacing = 8;
const double kOpenHandApprovalDialogMaxWidth = 860;
const double kOpenHandToolDialogRadius = 20;
const double kOpenHandToolDialogDefaultMaxWidth = 900;
const double kOpenHandToolDialogDefaultMaxHeight = 720;
const double kOpenHandToolDialogHeaderCompactBreakpoint = 520;
const double kOpenHandModalSheetMaxWidth = 980;
const double kOpenHandModalSheetDragHandleWidth = 36;
const double kOpenHandModalSheetDragHandleHeight = 4;
const EdgeInsets kOpenHandDialogDefaultInsetPadding = EdgeInsets.symmetric(
  horizontal: 40,
  vertical: 24,
);
const EdgeInsets kOpenHandToolDialogInsetPadding = EdgeInsets.all(20);
const EdgeInsets kOpenHandToolDialogHeaderPadding = EdgeInsets.fromLTRB(
  20,
  14,
  12,
  10,
);
const EdgeInsets kOpenHandResponsiveDialogSafeArea = EdgeInsets.all(18);

double resolveOpenHandResponsiveDialogExtent({
  required double viewportExtent,
  required double maxExtent,
  double minAvailableExtent = 0,
  double viewportMargin = 0,
  double? viewportFraction,
}) {
  final safeMax = _validDialogDimension(maxExtent);
  final safeMin = _validDialogDimension(minAvailableExtent) ?? 0;
  final safeMargin = viewportMargin.isFinite ? math.max(0, viewportMargin) : 0;
  final safeFraction = _validDialogViewportFraction(viewportFraction);
  final marginBoundedExtent = viewportExtent.isFinite
      ? math.max(safeMin, viewportExtent - safeMargin)
      : (safeMax ?? safeMin);
  final available = viewportExtent.isFinite && safeFraction != null
      ? math.min(
          marginBoundedExtent,
          math.max(safeMin, viewportExtent * safeFraction),
        )
      : marginBoundedExtent;
  return safeMax == null ? available : math.min(safeMax, available);
}

Color resolveAnimatedDialogBarrierColor(
  BuildContext context, {
  Color? override,
}) {
  if (override != null) {
    return override;
  }
  return Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54);
}

Widget? _constrainDialogContent(Widget? content, double? maxWidth) {
  return buildOpenHandDialogConstrainedContent(
    child: content,
    maxWidth: maxWidth,
  );
}

double? _validDialogMaxWidth(double? maxWidth) {
  if (maxWidth == null || !maxWidth.isFinite || maxWidth <= 0) return null;
  return maxWidth;
}

double? _validDialogDimension(double? value) {
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

double? _validDialogViewportFraction(double? value) {
  if (value == null || !value.isFinite || value <= 0) return null;
  return value.clamp(0.05, 1.0).toDouble();
}

double _safeDialogMaxDimension(double? maxValue, double minValue) {
  final validMax = _validDialogDimension(maxValue);
  if (validMax == null) return double.infinity;
  return validMax < minValue ? minValue : validMax;
}

DialogAnimationSettings _resolveDialogMotionSettings(
  BuildContext context, {
  DialogAnimationSettings? override,
}) {
  return openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.dialog,
    override: override,
  );
}

const ScrollPhysics kOpenHandDialogScrollPhysics = ClampingScrollPhysics();

class OpenHandDialogScrollBehavior extends MaterialScrollBehavior {
  const OpenHandDialogScrollBehavior();

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

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return kOpenHandDialogScrollPhysics;
  }

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

class _OpenHandDialogScrollScope extends InheritedWidget {
  const _OpenHandDialogScrollScope({required super.child});

  static bool isActive(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_OpenHandDialogScrollScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(_OpenHandDialogScrollScope oldWidget) => false;
}

bool openHandDialogScrollScopeOf(BuildContext context) {
  return _OpenHandDialogScrollScope.isActive(context);
}

ScrollPhysics openHandDialogAwareScrollPhysics(
  BuildContext context, {
  ScrollPhysics fallback = const BouncingScrollPhysics(),
}) {
  return openHandDialogScrollScopeOf(context)
      ? kOpenHandDialogScrollPhysics
      : fallback;
}

Widget buildOpenHandDialogScrollConfiguration({required Widget child}) {
  return _OpenHandDialogScrollScope(
    child: ScrollConfiguration(
      behavior: const OpenHandDialogScrollBehavior(),
      child: child,
    ),
  );
}

Widget? buildOpenHandDialogConstrainedContent({
  required Widget? child,
  double? width,
  double? height,
  double? minWidth,
  double? maxWidth,
  double? minHeight,
  double? maxHeight,
}) {
  if (child == null) return null;

  final effectiveWidth = _validDialogDimension(width);
  final effectiveHeight = _validDialogDimension(height);
  final effectiveMinWidth = _validDialogDimension(minWidth) ?? 0;
  final effectiveMinHeight = _validDialogDimension(minHeight) ?? 0;
  final effectiveMaxWidth = _safeDialogMaxDimension(
    maxWidth,
    effectiveMinWidth,
  );
  final effectiveMaxHeight = _safeDialogMaxDimension(
    maxHeight,
    effectiveMinHeight,
  );
  final hasFixedSize = effectiveWidth != null || effectiveHeight != null;
  final hasConstraints =
      minWidth != null ||
      maxWidth != null ||
      minHeight != null ||
      maxHeight != null;

  var current = child;
  if (hasFixedSize) {
    current = SizedBox(
      width: effectiveWidth,
      height: effectiveHeight,
      child: current,
    );
  }
  if (!hasConstraints) return current;
  return ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: effectiveMinWidth,
      maxWidth: effectiveMaxWidth,
      minHeight: effectiveMinHeight,
      maxHeight: effectiveMaxHeight,
    ),
    child: current,
  );
}

AlertDialog buildOpenHandAlertDialog({
  Widget? icon,
  Widget? title,
  Widget? content,
  List<Widget>? actions,
  Color? backgroundColor,
  Color? surfaceTintColor,
  ShapeBorder? shape,
  EdgeInsetsGeometry? titlePadding,
  MainAxisAlignment actionsAlignment = MainAxisAlignment.center,
  OverflowBarAlignment actionsOverflowAlignment = OverflowBarAlignment.center,
  double? actionsOverflowButtonSpacing,
  EdgeInsetsGeometry? actionsPadding,
  EdgeInsetsGeometry? contentPadding,
}) {
  return AlertDialog(
    backgroundColor: backgroundColor,
    surfaceTintColor: surfaceTintColor,
    shape: shape,
    titlePadding: titlePadding,
    actionsAlignment: actionsAlignment,
    actionsOverflowAlignment: actionsOverflowAlignment,
    actionsOverflowButtonSpacing: actionsOverflowButtonSpacing,
    actionsPadding: actionsPadding,
    contentPadding: contentPadding,
    icon: icon,
    title: title,
    content: content == null
        ? null
        : buildOpenHandDialogScrollConfiguration(child: content),
    actions: actions,
  );
}

Dialog buildOpenHandDialog({
  required Widget child,
  Color? backgroundColor,
  Color? surfaceTintColor,
  double? elevation,
  ShapeBorder? shape,
  Clip clipBehavior = Clip.antiAlias,
  EdgeInsets? insetPadding,
  AlignmentGeometry? alignment,
  double? width,
  double? height,
  double? minWidth,
  double? maxWidth,
  double? minHeight,
  double? maxHeight,
}) {
  return Dialog(
    backgroundColor: backgroundColor,
    surfaceTintColor: surfaceTintColor,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    insetPadding: openHandNonNegativeInsets(
      insetPadding ?? kOpenHandDialogDefaultInsetPadding,
    ),
    alignment: alignment,
    child: buildOpenHandDialogConstrainedContent(
      child: buildOpenHandDialogScrollConfiguration(child: child),
      width: width,
      height: height,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    ),
  );
}

Future<bool> showOpenHandConfirmDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String? cancelLabel,
  String? message,
  Widget? content,
  Widget? icon,
  double? maxWidth,
  bool destructive = false,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
}) async {
  final dialogContent = content ?? (message == null ? null : Text(message));
  final confirmed = await showAnimatedDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    builder: (dialogContext) => buildOpenHandAlertDialog(
      icon: icon,
      title: Text(title),
      content: _constrainDialogContent(dialogContent, maxWidth),
      actions: <Widget>[
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label:
              cancelLabel ??
              MaterialLocalizations.of(context).cancelButtonLabel,
        ),
        destructive
            ? OpenHandDialogActionButton.destructive(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: confirmLabel,
              )
            : OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: confirmLabel,
              ),
      ],
    ),
  );
  return confirmed == true;
}

Future<bool> showOpenHandFullAccessConfirmationDialog({
  required BuildContext context,
}) {
  return showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '启用完全访问权限？',
      en: 'Enable Full Access?',
    ),
    message: openHandLocalizedText(
      context,
      zh: '在完全访问权限模式下，OpenHand 可无需审批直接编辑计算机上的任意文件并运行网络命令。\n\n启用完全访问权限前请谨慎评估。此操作将显著增加数据丢失、泄露或异常行为的风险。',
      en: 'With Full Access enabled, OpenHand can edit any file and run commands without requiring your explicit approval.\n\nPlease evaluate carefully before enabling. This action significantly increases the risk of data loss, leakage, or unexpected behavior.',
    ),
    cancelLabel: openHandCancelLabel(context),
    confirmLabel: openHandLocalizedText(
      context,
      zh: '是，仍然继续',
      en: 'Yes, Continue',
    ),
    destructive: true,
  );
}

Future<String?> showOpenHandTextInputDialog({
  required BuildContext context,
  required String title,
  String? initialValue,
  String? hintText,
  String? confirmLabel,
  String? cancelLabel,
  InputDecoration? decoration,
  Widget? icon,
  TextInputType? keyboardType,
  double? maxWidth,
  bool trimResult = true,
  bool autofocus = true,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  int minLines = 1,
  int? maxLines,
}) async {
  final textController = TextEditingController(text: initialValue ?? '');
  final resolvedMinLines = minLines < 1 ? 1 : minLines;
  final resolvedMaxLines = maxLines == null || maxLines < resolvedMinLines
      ? resolvedMinLines
      : maxLines;
  final resolvedMaxWidth = _validDialogMaxWidth(maxWidth);
  String normalize(String value) => trimResult ? value.trim() : value;

  try {
    final submitted = await showAnimatedDialog<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      dismissOnEscape: dismissOnEscape,
      builder: (dialogContext) {
        final field = TextField(
          controller: textController,
          autofocus: autofocus,
          minLines: resolvedMinLines,
          maxLines: resolvedMaxLines,
          keyboardType:
              keyboardType ??
              (resolvedMaxLines == 1
                  ? TextInputType.text
                  : TextInputType.multiline),
          textInputAction: resolvedMaxLines == 1
              ? TextInputAction.done
              : TextInputAction.newline,
          decoration: decoration ?? InputDecoration(hintText: hintText),
          onSubmitted: resolvedMaxLines == 1
              ? (value) => Navigator.of(dialogContext).pop(normalize(value))
              : null,
        );
        return buildOpenHandAlertDialog(
          icon: icon,
          title: Text(title),
          content: resolvedMaxWidth == null
              ? field
              : buildOpenHandDialogConstrainedContent(
                  child: field,
                  maxWidth: resolvedMaxWidth,
                ),
          actions: <Widget>[
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label:
                  cancelLabel ??
                  MaterialLocalizations.of(context).cancelButtonLabel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(normalize(textController.text)),
              label:
                  confirmLabel ??
                  MaterialLocalizations.of(context).okButtonLabel,
            ),
          ],
        );
      },
    );
    return submitted == null ? null : normalize(submitted);
  } finally {
    textController.dispose();
  }
}

typedef OpenHandDialogFormContentBuilder =
    Widget Function(BuildContext dialogContext);
typedef OpenHandDialogFormSubmit<T> = T Function(BuildContext dialogContext);

Future<T?> showOpenHandStatefulDialog<T>({
  required BuildContext context,
  required StatefulWidgetBuilder builder,
  DialogAnimationSettings? settings,
  OpenHandAnimationTransitionProfile transitionProfile =
      const OpenHandAnimationTransitionProfile(),
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
    transitionProfile: transitionProfile,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    alignment: alignment,
    builder: (dialogContext) => StatefulBuilder(builder: builder),
  );
}

Future<T?> showOpenHandFormDialog<T>({
  required BuildContext context,
  required String title,
  required OpenHandDialogFormContentBuilder contentBuilder,
  required OpenHandDialogFormSubmit<T> onSubmit,
  required String submitLabel,
  String? cancelLabel,
  double? maxWidth,
  bool destructive = false,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
}) {
  return showAnimatedDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    builder: (dialogContext) => buildOpenHandDialogFormShell(
      context: dialogContext,
      title: title,
      maxWidth: maxWidth,
      content: contentBuilder(dialogContext),
      actions: <Widget>[
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label:
              cancelLabel ??
              MaterialLocalizations.of(context).cancelButtonLabel,
        ),
        destructive
            ? OpenHandDialogActionButton.destructive(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(onSubmit(dialogContext)),
                label: submitLabel,
              )
            : OpenHandDialogActionButton.primary(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(onSubmit(dialogContext)),
                label: submitLabel,
              ),
      ],
    ),
  );
}

/// Max wait for the dialog builder to attach its [Route] before [dismiss]
/// gives up. Keeps a fast-finishing async op from racing past first paint
/// and leaving a stuck progress shell, without unbounded waiting.
const Duration kOpenHandDialogRouteAttachTimeout = Duration(seconds: 2);

/// Tracks one [showAnimatedDialog] presentation so it can be dismissed later
/// without risking a bare [Navigator.maybePop] on the host page route.
///
/// When the dialog is already gone (ESC / barrier / external pop), [dismiss]
/// is a no-op. Dismissal targets the captured [Route] only:
/// - if it is current → [Navigator.pop] so the global exit transition runs;
/// - else if still active → defer the pop until it becomes current, preserving
///   both the route above it and the configured dialog exit transition.
class OpenHandDialogSession<T extends Object?> {
  OpenHandDialogSession._(this._result) {
    _result.then<void>(
      (_) => _completeClosed(),
      onError: (Object _, StackTrace _) => _completeClosed(),
    );
  }

  final Future<T?> _result;
  final Completer<void> _closedSignal = Completer<void>();
  final Completer<void> _routeAttached = Completer<void>();
  Route<T>? _route;
  bool _closed = false;
  bool _dismissRequested = false;
  T? _dismissResult;
  Future<bool>? _dismissInFlight;
  String _dismissLogTag = 'dialog';
  String _dismissLogAction = '关闭跟踪弹窗';
  Animation<double>? _deferredDismissAnimation;
  VoidCallback? _deferredDismissListener;
  bool _deferredDismissPopScheduled = false;

  /// Whether the reverse transition finished and the route overlay is gone.
  bool get isClosed => _closed;

  bool get isDismissRequested => _dismissRequested;

  Future<T?> get result => _result;

  Future<void> get closed => _closedSignal.future;

  void _completeClosed() {
    _closed = true;
    _clearDeferredDismissListener();
    _signalRouteAttached();
    if (!_closedSignal.isCompleted) _closedSignal.complete();
  }

  void _signalRouteAttached() {
    if (!_routeAttached.isCompleted) {
      _routeAttached.complete();
    }
  }

  void _attachRoute(Route<T> route) {
    if (_closed) return;
    _route = route;
    _signalRouteAttached();
  }

  void _clearDeferredDismissListener() {
    final animation = _deferredDismissAnimation;
    final listener = _deferredDismissListener;
    if (animation != null && listener != null) {
      animation.removeListener(listener);
    }
    _deferredDismissAnimation = null;
    _deferredDismissListener = null;
  }

  bool _deferAnimatedDismiss(Route<T> route) {
    if (route is! TransitionRoute<T>) return false;
    if (_deferredDismissListener != null) return true;
    final secondaryAnimation = route.secondaryAnimation;
    if (secondaryAnimation == null) return false;
    void listener() => _tryDeferredAnimatedDismiss(route);
    _deferredDismissAnimation = secondaryAnimation;
    _deferredDismissListener = listener;
    secondaryAnimation.addListener(listener);
    scheduleMicrotask(listener);
    return true;
  }

  void _tryDeferredAnimatedDismiss(Route<T> route) {
    if (_closed || !route.isActive) {
      _clearDeferredDismissListener();
      return;
    }
    final navigator = route.navigator;
    if (!route.isCurrent || navigator == null || _deferredDismissPopScheduled) {
      return;
    }
    _deferredDismissPopScheduled = true;
    _clearDeferredDismissListener();
    scheduleMicrotask(() {
      _deferredDismissPopScheduled = false;
      if (!_closed && route.isActive && route.isCurrent) {
        try {
          navigator.pop<T>(_dismissResult);
        } catch (error, stack) {
          _dismissRequested = false;
          _dismissResult = null;
          silentLog(_dismissLogTag, _dismissLogAction, error, stack);
        }
      }
    });
  }

  Future<Route<T>?> _awaitRoute({
    Duration timeout = kOpenHandDialogRouteAttachTimeout,
  }) async {
    if (_closed) return null;
    if (_route != null) return _route;
    try {
      await _routeAttached.future.timeout(timeout);
    } on TimeoutException {
      // Fall through and return whatever is attached (may still be null).
    }
    if (_closed) return null;
    return _route;
  }

  /// Dismisses this session's dialog if it is still active.
  ///
  /// Waits briefly for the route to attach so a task that finishes before the
  /// first dialog frame does not leave a stuck progress shell. Prefer
  /// [Navigator.pop] when this route is current so exit motion runs.
  ///
  /// Returns `true` only when this session successfully requested close of
  /// its own route.
  Future<bool> dismiss({
    T? result,
    String logTag = 'dialog',
    String logAction = '关闭跟踪弹窗',
    Duration attachTimeout = kOpenHandDialogRouteAttachTimeout,
  }) {
    if (attachTimeout <= Duration.zero) {
      throw ArgumentError.value(attachTimeout, 'attachTimeout', '必须大于零。');
    }
    if (_closed) return Future<bool>.value(false);
    final activeDismiss = _dismissInFlight;
    if (activeDismiss != null) return activeDismiss;
    if (_dismissRequested) return Future<bool>.value(true);
    _dismissRequested = true;
    _dismissResult = result;
    _dismissLogTag = logTag;
    _dismissLogAction = logAction;
    late final Future<bool> dismissFuture;
    dismissFuture =
        _dismiss(
          logTag: logTag,
          logAction: logAction,
          attachTimeout: attachTimeout,
        ).whenComplete(() {
          if (identical(_dismissInFlight, dismissFuture)) {
            _dismissInFlight = null;
          }
        });
    _dismissInFlight = dismissFuture;
    return dismissFuture;
  }

  Future<bool> _dismiss({
    required String logTag,
    required String logAction,
    required Duration attachTimeout,
  }) async {
    final route = await _awaitRoute(timeout: attachTimeout);
    if (_closed) return false;
    if (route == null || !route.isActive || route.navigator == null) {
      _dismissRequested = false;
      _dismissResult = null;
      return false;
    }
    final navigator = route.navigator!;
    try {
      if (route.isCurrent) {
        // Runs the reverse transition (global dialog exit / Q-bounce when set).
        navigator.pop<T>(_dismissResult);
      } else if (route.isActive) {
        // Never hard-remove a covered dialog: that bypasses its exit motion.
        // Listen to the secondary route animation and pop this route normally
        // once it becomes current. Return immediately so callers never wait
        // indefinitely for the covering route to close.
        final deferred = _deferAnimatedDismiss(route);
        if (!deferred) {
          _dismissRequested = false;
          _dismissResult = null;
        }
        return deferred;
      } else {
        _dismissRequested = false;
        _dismissResult = null;
        return false;
      }
      try {
        await _result;
        await closed;
      } catch (error, stack) {
        silentLog(logTag, logAction, error, stack);
      }
      return true;
    } catch (error, stack) {
      _dismissRequested = false;
      _dismissResult = null;
      silentLog(logTag, logAction, error, stack);
      return false;
    }
  }
}

/// Presents an animated dialog and returns a [OpenHandDialogSession] that can
/// dismiss only that dialog later (safe after async work).
OpenHandDialogSession<T> showTrackedAnimatedDialog<T extends Object?>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  OpenHandAnimationTransitionProfile transitionProfile =
      const OpenHandAnimationTransitionProfile(),
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  return _trackAnimatedDialogPresentation<T>(
    builder: builder,
    present: (trackedBuilder) => showAnimatedDialog<T>(
      context: context,
      settings: settings,
      transitionProfile: transitionProfile,
      barrierDismissible: barrierDismissible,
      dismissOnEscape: dismissOnEscape,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      alignment: alignment,
      builder: trackedBuilder,
    ),
  );
}

/// Navigator-resolved counterpart to [showTrackedAnimatedDialog].
///
/// App-level hosts can use this without deriving a navigator from a context
/// above [MaterialApp], while retaining precise, route-owned dismissal.
OpenHandDialogSession<T>
showTrackedAnimatedDialogOnNavigator<T extends Object?>({
  required NavigatorState navigator,
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  OpenHandAnimationTransitionProfile transitionProfile =
      const OpenHandAnimationTransitionProfile(),
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  return _trackAnimatedDialogPresentation<T>(
    builder: builder,
    present: (trackedBuilder) => showAnimatedDialogOnNavigator<T>(
      navigator: navigator,
      context: context,
      settings: settings,
      transitionProfile: transitionProfile,
      barrierDismissible: barrierDismissible,
      dismissOnEscape: dismissOnEscape,
      barrierLabel: barrierLabel,
      barrierColor: barrierColor,
      routeSettings: routeSettings,
      alignment: alignment,
      builder: trackedBuilder,
    ),
  );
}

OpenHandDialogSession<T> _trackAnimatedDialogPresentation<T extends Object?>({
  required WidgetBuilder builder,
  required Future<T?> Function(WidgetBuilder trackedBuilder) present,
}) {
  // Holder so the route builder can attach even if it runs after this returns
  // (normal for showGeneralDialog) or, rarely, before session assignment.
  final sessionHolder = <OpenHandDialogSession<T>?>[null];
  final future = present((dialogContext) {
    final route = ModalRoute.of<T>(dialogContext);
    void attach(Route<T> r) {
      final session = sessionHolder[0];
      if (session != null && !session.isClosed) {
        session._attachRoute(r);
      }
    }

    if (route != null) {
      attach(route);
      if (sessionHolder[0] == null) {
        scheduleMicrotask(() => attach(route));
      }
    }
    return builder(dialogContext);
  });
  final session = OpenHandDialogSession<T>._(future);
  sessionHolder[0] = session;
  return session;
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
  OpenHandAnimationTransitionProfile transitionProfile =
      const OpenHandAnimationTransitionProfile(),
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  if (!context.mounted) return Future<T?>.value();
  dismissOpenHandTooltipsSafely(debugLabel: '显示弹窗前收起工具提示');
  final themedBuilder = _wrapDialogBuilderWithTheme(
    builder,
    dismissOnEscape: dismissOnEscape,
    alignment: alignment,
  );
  final effectiveSettings = _resolveDialogMotionSettings(
    context,
    override: settings,
  );
  return _pushOpenHandDialogRoute<T>(
    navigator: Navigator.of(context, rootNavigator: useRootNavigator),
    sourceContext: context,
    builder: themedBuilder,
    settings: effectiveSettings,
    transitionProfile: transitionProfile,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    routeSettings: routeSettings,
  );
}

/// Shows an animated dialog by pushing directly through an already resolved
/// [NavigatorState]. Use this for app-level hosts that live above the
/// Navigator and therefore cannot safely call [showGeneralDialog] with their
/// own [BuildContext].
Future<T?> showAnimatedDialogOnNavigator<T>({
  required NavigatorState navigator,
  required BuildContext context,
  required WidgetBuilder builder,
  DialogAnimationSettings? settings,
  OpenHandAnimationTransitionProfile transitionProfile =
      const OpenHandAnimationTransitionProfile(),
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
  String? barrierLabel,
  Color? barrierColor,
  RouteSettings? routeSettings,
  AlignmentGeometry alignment = Alignment.center,
}) {
  if (!navigator.mounted || !context.mounted) {
    return Future<T?>.value();
  }
  dismissOpenHandTooltipsSafely(debugLabel: '通过导航器显示弹窗前收起工具提示');
  final themedBuilder = _wrapDialogBuilderWithTheme(
    builder,
    dismissOnEscape: dismissOnEscape,
    alignment: alignment,
  );
  final effectiveSettings = _resolveDialogMotionSettings(
    context,
    override: settings,
  );
  return _pushOpenHandDialogRoute<T>(
    navigator: navigator,
    sourceContext: context,
    builder: themedBuilder,
    settings: effectiveSettings,
    transitionProfile: transitionProfile,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor,
    routeSettings: routeSettings,
  );
}

Future<T?> _pushOpenHandDialogRoute<T>({
  required NavigatorState navigator,
  required BuildContext sourceContext,
  required WidgetBuilder builder,
  required DialogAnimationSettings settings,
  required OpenHandAnimationTransitionProfile transitionProfile,
  required bool barrierDismissible,
  required String? barrierLabel,
  required Color? barrierColor,
  required RouteSettings? routeSettings,
}) {
  final capturedThemes = InheritedTheme.capture(
    from: sourceContext,
    to: navigator.context,
  );
  final resolvedBarrierLabel =
      barrierLabel ??
      Localizations.of<MaterialLocalizations>(
        sourceContext,
        MaterialLocalizations,
      )?.modalBarrierDismissLabel ??
      '关闭弹窗';
  final route = _OpenHandRawDialogRoute<T>(
    pageBuilder: (routeContext, animation, secondaryAnimation) =>
        capturedThemes.wrap(builder(routeContext)),
    transitionBuilder: (routeContext, animation, secondaryAnimation, child) {
      if (openHandMotionDisabled(settings)) return child;
      return buildAnimationStyleTransition(
        animation: animation,
        settings: settings,
        profile: transitionProfile,
        child: child,
      );
    },
    entranceDuration: settings.entranceDuration,
    exitDuration: settings.exitDuration,
    entranceBarrierCurve: settings.curve.curve,
    exitBarrierCurve: settings.curve.reverseCurve,
    barrierDismissible: barrierDismissible,
    barrierLabel: resolvedBarrierLabel,
    barrierColor: resolveAnimatedDialogBarrierColor(
      sourceContext,
      override: barrierColor,
    ),
    settings: routeSettings,
  );
  return pushOpenHandTransitionRoute(
    navigator,
    route,
    sourceContext: sourceContext,
  );
}

final Expando<List<TransitionRoute<dynamic>>> _openHandRoutesByNavigator =
    Expando<List<TransitionRoute<dynamic>>>('openHandRoutesByNavigator');

/// Pushes an animated route and resolves only after its reverse transition
/// finishes and all overlay entries are removed.
Future<T?> pushOpenHandTransitionRoute<T>(
  NavigatorState navigator,
  TransitionRoute<T> route, {
  BuildContext? sourceContext,
}) async {
  if (!navigator.mounted || sourceContext?.mounted == false) return null;
  final routes = _openHandRoutesByNavigator[navigator] ??=
      <TransitionRoute<dynamic>>[];
  if (routes.isNotEmpty) {
    final previous = routes.last;
    final status = previous.animation?.status;
    if (!previous.isCurrent &&
        (status == AnimationStatus.reverse ||
            status == AnimationStatus.dismissed)) {
      await previous.completed;
    }
  }
  if (!navigator.mounted || sourceContext?.mounted == false) return null;
  final popped = navigator.push<T>(route);
  routes.add(route);
  try {
    return await popped;
  } finally {
    await route.completed;
    routes.remove(route);
  }
}

class _OpenHandRawDialogRoute<T> extends RawDialogRoute<T> {
  _OpenHandRawDialogRoute({
    required super.pageBuilder,
    required RouteTransitionsBuilder transitionBuilder,
    required Duration entranceDuration,
    required Duration exitDuration,
    required Curve entranceBarrierCurve,
    required Curve exitBarrierCurve,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.settings,
  }) : _exitDuration = exitDuration,
       _entranceBarrierCurve = entranceBarrierCurve,
       _exitBarrierCurve = exitBarrierCurve,
       super(
         transitionBuilder: transitionBuilder,
         transitionDuration: entranceDuration,
         requestFocus: true,
       );

  final Duration _exitDuration;
  final Curve _entranceBarrierCurve;
  final Curve _exitBarrierCurve;

  @override
  Duration get reverseTransitionDuration => _exitDuration;

  @override
  Widget buildModalBarrier() {
    final color = barrierColor;
    if (color == null || color.a == 0 || offstage) {
      return ModalBarrier(
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
      );
    }
    final curvedAnimation = CurvedAnimation(
      parent: animation!,
      curve: _entranceBarrierCurve,
      reverseCurve: _exitBarrierCurve,
    );
    return AnimatedModalBarrier(
      color: curvedAnimation.drive(
        ColorTween(begin: color.withValues(alpha: 0), end: color),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
  }
}

/// Shows a dialog with a caller-provided motion profile.
///
/// Feature modules use this when a family of dialogs needs one tuned geometry
/// while still inheriting global duration, curve, reduce-motion, and exit
/// behavior from [showAnimatedDialog].
Future<T?> showOpenHandProfiledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required OpenHandAnimationTransitionProfile transitionProfile,
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
    transitionProfile: transitionProfile,
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

Future<void> showOpenHandInfoDialog({
  required BuildContext context,
  required String title,
  String? closeLabel,
  String? message,
  Widget? content,
  Widget? icon,
  double? maxWidth,
  bool barrierDismissible = true,
  bool dismissOnEscape = true,
}) {
  final dialogContent = content ?? (message == null ? null : Text(message));
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    builder: (dialogContext) => buildOpenHandAlertDialog(
      icon: icon,
      title: Text(title),
      content: _constrainDialogContent(dialogContent, maxWidth),
      actions: <Widget>[
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label:
              closeLabel ?? MaterialLocalizations.of(context).closeButtonLabel,
        ),
      ],
    ),
  );
}

OpenHandDialogSession<void> showOpenHandTrackedLoadingDialog({
  required BuildContext context,
  String? message,
  Widget? content,
  bool barrierDismissible = false,
  bool dismissOnEscape = false,
}) {
  return showTrackedAnimatedDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    dismissOnEscape: dismissOnEscape,
    builder: (_) =>
        buildOpenHandLoadingDialog(message: message, content: content),
  );
}

AlertDialog buildOpenHandLoadingDialog({String? message, Widget? content}) {
  return buildOpenHandAlertDialog(
    content: content ?? buildOpenHandLoadingDialogContent(message: message),
  );
}

Widget buildOpenHandLoadingDialogContent({String? message}) {
  return SizedBox(
    height: 56,
    child: Center(
      child: message == null
          ? const CircularProgressIndicator()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Flexible(child: Text(message)),
              ],
            ),
    ),
  );
}

Widget buildOpenHandDialogFooter({
  required String primaryLabel,
  required VoidCallback? onPrimaryPressed,
  Widget? leading,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
}) {
  final action = OpenHandDialogActionButton.primary(
    label: primaryLabel,
    onPressed: onPrimaryPressed,
  );
  if (leading == null) {
    return Padding(
      padding: padding,
      child: SizedBox(width: double.infinity, child: action),
    );
  }
  return Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: leading),
        const SizedBox(width: kOpenHandDialogActionSpacing),
        action,
      ],
    ),
  );
}

Widget buildOpenHandDialogActionsBar({
  required List<Widget> actions,
  Widget? leading,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  double spacing = kOpenHandDialogActionSpacing,
}) {
  final actionsRow = Wrap(
    alignment: WrapAlignment.center,
    spacing: spacing,
    runSpacing: spacing,
    children: actions,
  );
  if (leading == null) {
    return Padding(padding: padding, child: actionsRow);
  }
  return Padding(
    padding: padding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite && constraints.maxWidth < 420;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              SizedBox(height: spacing),
              Align(alignment: Alignment.centerRight, child: actionsRow),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: leading),
            SizedBox(width: spacing),
            Flexible(
              flex: 0,
              child: Align(alignment: Alignment.centerRight, child: actionsRow),
            ),
          ],
        );
      },
    ),
  );
}

Widget buildOpenHandDialogFormShell({
  required BuildContext context,
  required String title,
  required Widget content,
  required List<Widget> actions,
  double? maxWidth,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  ShapeBorder? shape,
  Color? backgroundColor,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return buildOpenHandDialog(
    backgroundColor: backgroundColor ?? colorScheme.surfaceContainer,
    shape:
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandDialogFormRadius),
        ),
    maxWidth: _validDialogMaxWidth(maxWidth) ?? kOpenHandDialogDefaultMaxWidth,
    child: IntrinsicWidth(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Flexible(child: content),
            const SizedBox(height: 12),
            buildOpenHandDialogActionsBar(
              actions: actions,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildOpenHandToolDialogShell({
  required BuildContext context,
  required Widget child,
  double maxWidth = kOpenHandToolDialogDefaultMaxWidth,
  double maxHeight = kOpenHandToolDialogDefaultMaxHeight,
  EdgeInsets insetPadding = kOpenHandToolDialogInsetPadding,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip clipBehavior = Clip.antiAlias,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final effectiveMaxWidth =
      _validDialogDimension(maxWidth) ?? kOpenHandToolDialogDefaultMaxWidth;
  final effectiveMaxHeight =
      _validDialogDimension(maxHeight) ?? kOpenHandToolDialogDefaultMaxHeight;
  return buildOpenHandDialog(
    backgroundColor: backgroundColor ?? colorScheme.surfaceContainer,
    shape:
        shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandToolDialogRadius),
        ),
    clipBehavior: clipBehavior,
    insetPadding: insetPadding,
    maxWidth: effectiveMaxWidth,
    maxHeight: effectiveMaxHeight,
    child: child,
  );
}

Widget buildOpenHandResponsiveDialogShell({
  required BuildContext context,
  required Widget child,
  double maxWidth = kOpenHandToolDialogDefaultMaxWidth,
  double maxHeight = kOpenHandToolDialogDefaultMaxHeight,
  double? maxWidthFraction,
  double? maxHeightFraction,
  double minAvailableWidth = 280,
  double minAvailableHeight = 360,
  double minWidth = 0,
  double minHeight = 0,
  double horizontalMargin = 36,
  double verticalMargin = 120,
  EdgeInsets safeAreaMinimum = kOpenHandResponsiveDialogSafeArea,
  EdgeInsets insetPadding = EdgeInsets.zero,
  Color? backgroundColor,
  Color? surfaceTintColor,
  ShapeBorder? shape,
  Clip clipBehavior = Clip.antiAlias,
  bool expandToMax = false,
}) {
  final mediaSize = MediaQuery.sizeOf(context);
  final effectiveMaxWidth = resolveOpenHandResponsiveDialogExtent(
    viewportExtent: mediaSize.width,
    maxExtent: maxWidth,
    minAvailableExtent: minAvailableWidth,
    viewportMargin: horizontalMargin,
    viewportFraction: maxWidthFraction,
  );
  final effectiveMaxHeight = resolveOpenHandResponsiveDialogExtent(
    viewportExtent: mediaSize.height,
    maxExtent: maxHeight,
    minAvailableExtent: minAvailableHeight,
    viewportMargin: verticalMargin,
    viewportFraction: maxHeightFraction,
  );
  final effectiveMinWidth = math.min(
    effectiveMaxWidth,
    _validDialogDimension(minWidth) ?? 0,
  );
  final effectiveMinHeight = math.min(
    effectiveMaxHeight,
    _validDialogDimension(minHeight) ?? 0,
  );

  return SafeArea(
    minimum: openHandNonNegativeInsets(safeAreaMinimum),
    child: buildOpenHandDialog(
      backgroundColor: backgroundColor,
      surfaceTintColor: surfaceTintColor,
      shape: shape,
      clipBehavior: clipBehavior,
      insetPadding: insetPadding,
      width: expandToMax ? effectiveMaxWidth : null,
      height: expandToMax ? effectiveMaxHeight : null,
      minWidth: effectiveMinWidth,
      maxWidth: effectiveMaxWidth,
      minHeight: effectiveMinHeight,
      maxHeight: effectiveMaxHeight,
      child: child,
    ),
  );
}

Widget buildOpenHandToolDialogHeader({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? subtitle,
  List<Widget> actions = const <Widget>[],
  Widget? iconWidget,
  Color? iconColor,
  double iconSize = 20,
  VoidCallback? onClose,
  String? closeTooltip,
  EdgeInsetsGeometry padding = kOpenHandToolDialogHeaderPadding,
  bool showCloseButton = true,
  bool closeEnabled = true,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final effectiveSubtitle = subtitle?.trim();
  final closeButton = showCloseButton
      ? IconButton(
          tooltip:
              closeTooltip ??
              MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: closeEnabled
              ? (onClose ?? () => Navigator.of(context).maybePop())
              : null,
          icon: const Icon(Icons.close_rounded),
        )
      : null;
  final actionWidgets = <Widget>[
    ...actions,
    if (closeButton != null) closeButton,
  ];
  final titleBlock = Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (effectiveSubtitle != null && effectiveSubtitle.isNotEmpty)
          Text(
            effectiveSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
  final leading = <Widget>[
    iconWidget ??
        Icon(icon, size: iconSize, color: iconColor ?? colorScheme.primary),
    const SizedBox(width: 10),
    titleBlock,
  ];
  return Padding(
    padding: padding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth &&
            constraints.maxWidth < kOpenHandToolDialogHeaderCompactBreakpoint &&
            actionWidgets.length > 1;
        if (compact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: leading),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  runSpacing: 4,
                  children: actionWidgets,
                ),
              ),
            ],
          );
        }
        return Row(children: [...leading, ...actionWidgets]);
      },
    ),
  );
}

BoxConstraints openHandDialogViewportConstraints(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return BoxConstraints(
    maxWidth: size.width * kOpenHandDialogViewportFraction,
    maxHeight: size.height * kOpenHandDialogViewportFraction,
  );
}

double openHandModalSheetWidth(BuildContext context) {
  final viewportWidth =
      MediaQuery.sizeOf(context).width * kOpenHandDialogViewportFraction;
  return viewportWidth > kOpenHandModalSheetMaxWidth
      ? kOpenHandModalSheetMaxWidth
      : viewportWidth;
}

Widget buildOpenHandDialogValidationMessage(
  BuildContext context, {
  required String? message,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final duration = openHandMotionDurationMs(context, 180);
  final content = message == null
      ? const SizedBox.shrink(key: ValueKey<String>('empty'))
      : DecoratedBox(
          key: ValueKey<String>(message),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.error.withValues(alpha: 0.25),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  return AnimatedSwitcher(
    duration: duration,
    reverseDuration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
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
    child: content,
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
  double elevation = 8,
  Color? backgroundColor,
  ShapeBorder? shape,
  EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(8, 0, 8, 8),
}) {
  assert(elevation >= 0, '底部弹窗阴影高度不能为负数。');
  return showAnimatedDialog<T>(
    context: context,
    settings: settings,
    transitionProfile: const OpenHandAnimationTransitionProfile(
      alignment: Alignment.bottomCenter,
    ),
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
      final sheetWidth = openHandModalSheetWidth(sheetContext);
      final sheetMargin = openHandResolvedNonNegativeInsets(
        sheetContext,
        margin,
      );
      final sheetShape =
          shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
          );
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
          padding: sheetMargin,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: sheetWidth),
            child: Material(
              type: MaterialType.card,
              elevation: elevation,
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
            borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
          ),
        ),
      ),
      child: buildOpenHandDialogScrollConfiguration(
        child: builder(dialogContext),
      ),
    );
    // 视口收缩：保证任何子弹窗的最大尺寸不超过当前屏幕的 95%，
    // 在窄屏 / 浮动小窗模式下不会贴边或溢出。
    // 只设置上限，不强行撑满，原本小弹窗（install_guide 等）不受影响。
    final clamped = _ViewportClamp(alignment: alignment, child: themed);
    final stableHitTest = _DialogInitialHitTestShield(child: clamped);
    if (!dismissOnEscape) return stableHitTest;
    return _EscapeDismissDialogScope(child: stableHitTest);
  };
}

class _DialogInitialHitTestShield extends StatefulWidget {
  const _DialogInitialHitTestShield({required this.child});

  final Widget child;

  @override
  State<_DialogInitialHitTestShield> createState() =>
      _DialogInitialHitTestShieldState();
}

class _DialogInitialHitTestShieldState
    extends State<_DialogInitialHitTestShield> {
  bool _absorbing = true;

  @override
  void initState() {
    super.initState();
    unawaited(_releaseAfterStableFrames());
  }

  Future<void> _releaseAfterStableFrames() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    await binding.endOfFrame;
    if (mounted) {
      setState(() => _absorbing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogInitialHitTestGate(
      absorbing: _absorbing,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
            return SizedBox.expand(child: widget.child);
          }
          return widget.child;
        },
      ),
    );
  }
}

class _DialogInitialHitTestGate extends SingleChildRenderObjectWidget {
  const _DialogInitialHitTestGate({
    required this.absorbing,
    required super.child,
  });

  final bool absorbing;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDialogInitialHitTestGate(absorbing: absorbing);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDialogInitialHitTestGate renderObject,
  ) {
    renderObject.absorbing = absorbing;
  }
}

class _RenderDialogInitialHitTestGate extends RenderProxyBox {
  _RenderDialogInitialHitTestGate({required bool absorbing})
    : _absorbing = absorbing;

  bool _absorbing;

  set absorbing(bool value) {
    if (_absorbing == value) return;
    _absorbing = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!hasSize || !size.contains(position)) {
      return false;
    }
    if (!_absorbing) {
      return super.hitTest(result, position: position);
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// 在弹窗外层套一个 MediaQuery 感知的 ConstrainedBox，把最大宽 / 高限制为
/// 视口的 95%。子弹窗自身的 maxWidth/maxHeight 仍生效——两个约束取最小值。
class _ViewportClamp extends StatelessWidget {
  const _ViewportClamp({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: openHandDialogViewportConstraints(context),
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
        child: const SizedBox(
          width: kOpenHandModalSheetDragHandleWidth,
          height: kOpenHandModalSheetDragHandleHeight,
        ),
      ),
    );
  }
}

/// 为弹窗提供 ESC 关闭能力，且不抢占子输入控件焦点。
///
/// 主路径使用 [HardwareKeyboard] 监听；`Focus(autofocus: true)` 与
/// `FocusScope(autofocus: true)` 会破坏 macOS IMK，导致 `TextField`
/// 无法输入、复制或粘贴。硬件键盘监听不请求焦点，并通过
/// `ModalRoute.isCurrent` 防止嵌套弹窗重复出栈。[Shortcuts] 与 [Actions]
/// 作为焦点控件主动分发 [DismissIntent] 时的备用路径。
class _EscapeDismissDialogScope extends StatefulWidget {
  const _EscapeDismissDialogScope({required this.child});

  final Widget child;

  @override
  State<_EscapeDismissDialogScope> createState() =>
      _EscapeDismissDialogScopeState();
}

class _EscapeDismissDialogScopeState extends State<_EscapeDismissDialogScope> {
  ModalRoute<Object?>? _route;
  bool _dismissRequested = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    return _dismiss();
  }

  bool _dismiss() {
    final route = _route;
    if (route == null || !route.isCurrent) return false;
    if (_dismissRequested) return true;
    final navigator = route.navigator ?? Navigator.maybeOf(context);
    if (navigator == null) return false;
    _dismissRequested = true;
    unawaited(
      navigator
          .maybePop()
          .then((handled) {
            if (!handled || route.isCurrent) {
              _dismissRequested = false;
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            _dismissRequested = false;
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'OpenHand 弹窗',
                context: ErrorDescription('关闭弹窗时'),
              ),
            );
          }),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _dismiss();
              return null;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }
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
  OpenHandAnimationTransitionProfile profile =
      const OpenHandAnimationTransitionProfile(),
  Curve? curveOverride,
  Curve? reverseCurveOverride,
  required Widget child,
}) {
  final safeAnimation = OpenHandBoundedDoubleAnimation(animation);
  final forward =
      animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.completed;
  final style = forward ? settings.entranceStyle : settings.exitStyle;
  final curveData = settings.curve;
  final curve = curveOverride ?? curveData.curve;
  final reverseCurve = reverseCurveOverride ?? curveData.reverseCurve;
  final motion = openHandCurveAnimation(
    parent: safeAnimation,
    curve: curve,
    reverseCurve: reverseCurve,
  );
  final boundedMotion = OpenHandBoundedDoubleAnimation(motion);

  return switch (style) {
    DialogAnimationStyle.none => child,
    DialogAnimationStyle.fade => FadeTransition(
      opacity: boundedMotion,
      child: child,
    ),
    DialogAnimationStyle.fadeScale => _FadeScaleTransition(
      opacity: boundedMotion,
      motion: motion,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.slideUp => _SlideTransition(
      opacity: boundedMotion,
      motion: motion,
      beginOffset: profile.slideUpOffset,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.slideDown => _SlideTransition(
      opacity: boundedMotion,
      motion: motion,
      beginOffset: profile.slideDownOffset,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.slideLeft => _SlideTransition(
      opacity: boundedMotion,
      motion: motion,
      beginOffset: profile.slideLeftOffset,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.slideRight => _SlideTransition(
      opacity: boundedMotion,
      motion: motion,
      beginOffset: profile.slideRightOffset,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.expand => _ExpandTransition(
      parentAnimation: safeAnimation,
      motion: motion,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.rotateScale => _RotateScaleTransition(
      opacity: boundedMotion,
      motion: motion,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.elastic => _ElasticTransition(
      animation: safeAnimation,
      curve: curve,
      reverseCurve: reverseCurve,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.springScale => _SpringScaleTransition(
      animation: safeAnimation,
      curve: curve,
      reverseCurve: reverseCurve,
      profile: profile,
      child: child,
    ),
    DialogAnimationStyle.flipX => _FlipXTransition(
      opacity: boundedMotion,
      motion: motion,
      profile: profile,
      child: child,
    ),
  };
}

enum OpenHandSlideTransitionMode { fractional, paintOffset }

@immutable
class OpenHandAnimationTransitionProfile {
  const OpenHandAnimationTransitionProfile({
    this.alignment = Alignment.center,
    this.fadeScaleBegin = 0.94,
    this.expandScaleBegin = 0.88,
    this.rotateScaleBegin = 0.9,
    this.rotateTurnsBegin = -0.05,
    this.elasticScaleBegin = 0.94,
    this.springScaleBegin = 0.94,
    this.flipMaxAngle = 1.5708,
    this.flipMaxTilt = 0.0,
    this.flipPerspective = 0.0015,
    this.slideMode = OpenHandSlideTransitionMode.fractional,
    this.slideUpOffset = const Offset(0, 0.15),
    this.slideDownOffset = const Offset(0, -0.15),
    this.slideLeftOffset = const Offset(-0.25, 0),
    this.slideRightOffset = const Offset(0.25, 0),
  });

  final Alignment alignment;
  final double fadeScaleBegin;
  final double expandScaleBegin;
  final double rotateScaleBegin;
  final double rotateTurnsBegin;
  final double elasticScaleBegin;
  final double springScaleBegin;
  final double flipMaxAngle;
  final double flipMaxTilt;
  final double flipPerspective;
  final OpenHandSlideTransitionMode slideMode;
  final Offset slideUpOffset;
  final Offset slideDownOffset;
  final Offset slideLeftOffset;
  final Offset slideRightOffset;
}

/// 列表和 Sliver 动态布局使用像素级绘制位移，避免尺寸动画期间命中测试
/// 访问仍待布局的 RenderFractionalTranslation。
const OpenHandAnimationTransitionProfile kOpenHandLayoutSafeTransitionProfile =
    OpenHandAnimationTransitionProfile(
      slideMode: OpenHandSlideTransitionMode.paintOffset,
      slideUpOffset: Offset(0, 12),
      slideDownOffset: Offset(0, -12),
      slideLeftOffset: Offset(-12, 0),
      slideRightOffset: Offset(12, 0),
    );

double _finiteDouble(double value, double fallback) {
  return value.isFinite ? value : fallback;
}

double _positiveFiniteDouble(double value, double fallback) {
  if (!value.isFinite || value <= 0) return fallback;
  return value;
}

Offset _finiteOffset(Offset value, Offset fallback) {
  if (value.dx.isFinite && value.dy.isFinite) return value;
  return fallback;
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual transition widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FadeScaleTransition extends StatelessWidget {
  const _FadeScaleTransition({
    required this.opacity,
    required this.motion,
    required this.profile,
    required this.child,
  });
  final Animation<double> opacity;
  final Animation<double> motion;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: _positiveFiniteDouble(profile.fadeScaleBegin, 0.94),
          end: 1.0,
        ).animate(motion),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

class _SlideTransition extends StatelessWidget {
  const _SlideTransition({
    required this.opacity,
    required this.motion,
    required this.beginOffset,
    required this.profile,
    required this.child,
  });
  final Animation<double> opacity;
  final Animation<double> motion;
  final Offset beginOffset;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveOffset = _finiteOffset(beginOffset, Offset.zero);
    final slidingChild =
        profile.slideMode == OpenHandSlideTransitionMode.paintOffset
        ? _PaintOffsetTransition(
            animation: motion,
            maxXOffset: effectiveOffset.dx,
            maxYOffset: effectiveOffset.dy,
            child: child,
          )
        : SlideTransition(
            position: Tween<Offset>(
              begin: effectiveOffset,
              end: Offset.zero,
            ).animate(motion),
            child: child,
          );
    return FadeTransition(opacity: opacity, child: slidingChild);
  }
}

class _ExpandTransition extends StatelessWidget {
  const _ExpandTransition({
    required this.parentAnimation,
    required this.motion,
    required this.profile,
    required this.child,
  });
  final Animation<double> parentAnimation;
  final Animation<double> motion;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: openHandBoundedCurveAnimation(
        parent: parentAnimation,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(
          begin: _positiveFiniteDouble(profile.expandScaleBegin, 0.88),
          end: 1.0,
        ).animate(motion),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

class _RotateScaleTransition extends StatelessWidget {
  const _RotateScaleTransition({
    required this.opacity,
    required this.motion,
    required this.profile,
    required this.child,
  });
  final Animation<double> opacity;
  final Animation<double> motion;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(
      begin: _positiveFiniteDouble(profile.rotateScaleBegin, 0.9),
      end: 1.0,
    ).animate(motion);
    final rotation = Tween<double>(
      begin: _finiteDouble(profile.rotateTurnsBegin, -0.05),
      end: 0.0,
    ).animate(motion);
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(
        scale: scale,
        alignment: profile.alignment,
        child: RotationTransition(
          turns: rotation,
          alignment: profile.alignment,
          child: child,
        ),
      ),
    );
  }
}

class _ElasticTransition extends StatelessWidget {
  const _ElasticTransition({
    required this.animation,
    required this.curve,
    required this.reverseCurve,
    required this.profile,
    required this.child,
  });
  final Animation<double> animation;
  final Curve curve;
  final Curve reverseCurve;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = openHandBoundedCurveAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.38, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
    );
    final scaleMotion = openHandCurveAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: _positiveFiniteDouble(profile.elasticScaleBegin, 0.94),
          end: 1.0,
        ).animate(scaleMotion),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

/// Q-bouncy spring scale: easeOutBack overshoot on entrance + slight
/// fade window. Reverse uses easeInBack so exit also feels springy.
class _SpringScaleTransition extends StatelessWidget {
  const _SpringScaleTransition({
    required this.animation,
    required this.curve,
    required this.reverseCurve,
    required this.profile,
    required this.child,
  });
  final Animation<double> animation;
  final Curve curve;
  final Curve reverseCurve;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = openHandBoundedCurveAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );
    final scaleMotion = openHandCurveAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );
    return FadeTransition(
      opacity: opacity,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: _positiveFiniteDouble(profile.springScaleBegin, 0.94),
          end: 1.0,
        ).animate(scaleMotion),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

/// 3D card-flip on the X axis with fade — useful for chip / list-item
/// "appear" feels when something switches in/out of place.
class _FlipXTransition extends StatelessWidget {
  const _FlipXTransition({
    required this.opacity,
    required this.motion,
    required this.profile,
    required this.child,
  });
  final Animation<double> opacity;
  final Animation<double> motion;
  final OpenHandAnimationTransitionProfile profile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: AnimatedBuilder(
        animation: motion,
        builder: (context, c) {
          final t = openHandBoundedProgress(motion.value);
          final angle = (1.0 - t) * _finiteDouble(profile.flipMaxAngle, 1.5708);
          final tilt = (1.0 - t) * _finiteDouble(profile.flipMaxTilt, 0.0);
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, _finiteDouble(profile.flipPerspective, 0.0015))
            ..rotateX(angle)
            ..rotateZ(tilt);
          return Transform(
            transform: matrix,
            alignment: profile.alignment,
            child: c,
          );
        },
        child: child,
      ),
    );
  }
}

class _PaintOffsetTransition extends SingleChildRenderObjectWidget {
  const _PaintOffsetTransition({
    required this.animation,
    required this.maxYOffset,
    this.maxXOffset = 0,
    required Widget super.child,
  });

  final Animation<double> animation;
  final double maxYOffset;
  final double maxXOffset;

  @override
  _PaintOffsetRenderObject createRenderObject(BuildContext context) {
    final disable = !openHandTickerMotionEnabled(context);
    return _PaintOffsetRenderObject(
      animation: animation,
      maxYOffset: disable ? 0.0 : maxYOffset,
      maxXOffset: disable ? 0.0 : maxXOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _PaintOffsetRenderObject renderObject,
  ) {
    final disable = !openHandTickerMotionEnabled(context);
    renderObject
      ..animation = animation
      ..maxYOffset = disable ? 0.0 : maxYOffset
      ..maxXOffset = disable ? 0.0 : maxXOffset;
  }
}

/// Layout-safe paint-time translation driven by an [Animation].
///
/// The render object only shifts the paint offset via [markNeedsPaint], so
/// pixel-based slide transitions can be reused without changing layout size.
class _PaintOffsetRenderObject extends RenderProxyBox {
  _PaintOffsetRenderObject({
    required Animation<double> animation,
    required double maxYOffset,
    double maxXOffset = 0,
  }) : _animation = animation,
       _maxYOffset = maxYOffset,
       _maxXOffset = maxXOffset;

  Animation<double> _animation;
  double _maxYOffset;
  double _maxXOffset;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(_handleAnimationTick);
      value.addListener(_handleAnimationTick);
    }
    _animation = value;
    _handleAnimationTick();
  }

  set maxYOffset(double value) {
    if (_maxYOffset == value) return;
    _maxYOffset = value;
    markNeedsPaint();
  }

  set maxXOffset(double value) {
    if (_maxXOffset == value) return;
    _maxXOffset = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_handleAnimationTick);
  }

  @override
  void detach() {
    _animation.removeListener(_handleAnimationTick);
    super.detach();
  }

  void _handleAnimationTick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Offset get _paintOffset {
    final value = _finiteDouble(_animation.value, 1.0);
    return Offset(
      (1 - value) * _finiteDouble(_maxXOffset, 0.0),
      (1 - value) * _finiteDouble(_maxYOffset, 0.0),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    super.paint(context, offset + _paintOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final currentChild = child;
    if (currentChild == null) return false;
    return result.addWithPaintOffset(
      offset: _paintOffset,
      position: position,
      hitTest: (result, transformed) {
        return currentChild.hitTest(result, position: transformed);
      },
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final offset = _paintOffset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}

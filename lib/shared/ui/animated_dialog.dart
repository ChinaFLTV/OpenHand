import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/support/silent_log.dart';
import '../util/argument_guards.dart';
import '../util/localized_text.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_reveal_switcher.dart';
import 'openhand_scroll_behaviors.dart';
import 'openhand_tooltip_dismissal.dart';
import 'safe_edge_insets.dart';

const double kOpenHandDialogViewportFraction = 0.95;
const double kOpenHandDialogDefaultMaxWidth = 520;
const double kOpenHandDialogDefaultRadius = 28;
const double kOpenHandDialogFormRadius = 16;
const double kOpenHandDialogActionSpacing = 8;

/// 弹窗宽度档位，均为内容约束上限。
const double kOpenHandDialogWidthCompact = 560;
const double kOpenHandDialogWidthStandard = 720;
const double kOpenHandDialogWidthWide = 880;
const double kOpenHandDialogWidthExtraWide = 1000;
const double kOpenHandDialogWidthPanel = 1120;
const double kOpenHandDialogWidthFull = 1280;

/// 弹窗高度档位，均为内容约束上限。
const double kOpenHandDialogHeightCompact = 560;
const double kOpenHandDialogHeightStandard = 680;
const double kOpenHandDialogHeightTall = 800;
const double kOpenHandDialogHeightFull = 920;

const double kOpenHandApprovalDialogMaxWidth = 860;

/// 审批弹窗标题左侧图标徽章的边长。
const double kOpenHandApprovalHeaderBadgeSize = 48;
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

Future<DateTimeRange?> showAnimatedDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
  String? cancelText,
  String? confirmText,
  String? saveText,
}) => showAnimatedDialog<DateTimeRange>(
  context: context,
  builder: (_) => DateRangePickerDialog(
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: helpText,
    cancelText: cancelText,
    confirmText: confirmText,
    saveText: saveText,
  ),
);

class OpenHandDialogScrollBehavior extends OpenHandImplicitScrollbarBehavior {
  const OpenHandDialogScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return kOpenHandDialogScrollPhysics;
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

/// [dismiss] 等待弹窗构建器绑定 [Route] 的最长时间，避免快速任务越过首帧后
/// 遗留加载壳，同时杜绝无限等待。
const Duration kOpenHandDialogRouteAttachTimeout = Duration(seconds: 2);

/// 跟踪一次 [showAnimatedDialog] 展示，使后续关闭只作用于对应弹窗路由。
///
/// 弹窗已被 ESC、遮罩或外部操作关闭时，[dismiss] 不执行任何操作。若目标路由
/// 位于栈顶则正常弹出以播放全局退场动画；若仍活动但被覆盖，则等它回到栈顶再弹出。
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

  /// 退场动画及路由遮罩是否已完全结束。
  bool get isClosed => _closed;

  bool get isDismissRequested => _dismissRequested;

  Future<T?> get result => _result;

  Future<void> get closed => _closedSignal.future;

  void _completeClosed() {
    _closed = true;
    _clearDeferredDismissListener();
    _route = null;
    _dismissResult = null;
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
      // 超时后返回当前绑定结果，可能仍为空。
    }
    if (_closed) return null;
    return _route;
  }

  /// 关闭本会话仍处于活动状态的弹窗。
  ///
  /// 短暂等待路由绑定，避免首帧前完成的任务遗留加载壳。路由位于栈顶时通过
  /// [Navigator.pop] 关闭，以完整播放退场动画。
  ///
  /// 仅在成功请求关闭本会话路由时返回 `true`。
  Future<bool> dismiss({
    T? result,
    String logTag = 'dialog',
    String logAction = '关闭跟踪弹窗',
    Duration attachTimeout = kOpenHandDialogRouteAttachTimeout,
  }) {
    requirePositiveDuration(attachTimeout, 'attachTimeout');
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
        // 正常弹出路由，播放全局配置的退场或 Q 弹动画。
        navigator.pop<T>(_dismissResult);
      } else if (route.isActive) {
        // 被覆盖的弹窗不能强制移除；监听上层路由，回到栈顶后再正常弹出。
        // 此处立即返回，避免调用方无限等待上层路由关闭。
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

/// 展示动画弹窗并返回仅能关闭该弹窗的 [OpenHandDialogSession]。
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

/// 已解析导航器版本的 [showTrackedAnimatedDialog]。
///
/// 应用级宿主无需从 [MaterialApp] 上层上下文推导导航器，也能精确关闭所属路由。
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
  // 路由构建器可能在本方法返回后执行，也可能极少数地早于会话赋值，故用容器衔接。
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
  unawaited(
    session.closed.whenComplete(() {
      if (identical(sessionHolder[0], session)) {
        sessionHolder[0] = null;
      }
    }),
  );
  return session;
}

/// 展示可配置进场与退场动画的弹窗。
///
/// [settings] 为空时从组件树最近的 [SettingsController] 读取动画配置；找不到时
/// 使用默认配置。
///
/// [dismissOnEscape] 与 [barrierDismissible] 独立：默认即使禁止点击外部，ESC
/// 仍可关闭弹窗；仅显式审批类弹窗应通过 `dismissOnEscape: false` 禁用。
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

/// 通过已解析的 [NavigatorState] 直接推入动画弹窗，适用于位于 Navigator 上层、
/// 无法用自身 [BuildContext] 安全展示弹窗的应用级宿主。
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
// 自定义动画最长 1.2 秒；额外预留路由遮罩清理时间，异常路由也不能长期阻塞后续弹窗。
const Duration kOpenHandTransitionCompletionTimeout = Duration(seconds: 4);

Future<void> _awaitOpenHandTransitionCompletion(
  TransitionRoute<dynamic> route,
) async {
  try {
    await route.completed.timeout(kOpenHandTransitionCompletionTimeout);
  } catch (error, stack) {
    silentLog('dialog', '等待弹窗退场动画完成', error, stack);
  }
}

/// 推入动画路由，并在退场完成且全部遮罩条目移除后结束。
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
      await _awaitOpenHandTransitionCompletion(previous);
    }
  }
  if (!navigator.mounted || sourceContext?.mounted == false) return null;
  final popped = navigator.push<T>(route);
  routes.add(route);
  try {
    return await popped;
  } finally {
    await _awaitOpenHandTransitionCompletion(route);
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
    final curvedAnimation = OpenHandBoundedDoubleAnimation(
      CurvedAnimation(
        parent: animation!,
        curve: _entranceBarrierCurve,
        reverseCurve: _exitBarrierCurve,
      ),
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

/// 使用调用方提供的动效配置展示弹窗。
///
/// 同族弹窗需要专属几何参数时使用；时长、曲线、减少动态效果与退场行为仍继承
/// [showAnimatedDialog] 的全局配置。
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

/// 绑定了固定过渡几何参数的弹窗入口。
///
/// 各功能模块只需声明自己的 [OpenHandAnimationTransitionProfile] 常量并建一个
/// presenter，不必再各自抄一遍 11 个参数的转发壳。路由与全局弹窗动画设置仍由
/// [showOpenHandProfiledDialog] 统一处理，模块只覆盖过渡几何。
class OpenHandProfiledDialogPresenter {
  const OpenHandProfiledDialogPresenter(this.transitionProfile);

  final OpenHandAnimationTransitionProfile transitionProfile;

  Future<T?> show<T>({
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
  bool dismissOnEscape = true,
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
                kOpenHandHGap16,
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
  return buildOpenHandDialogActionsBar(
    padding: padding,
    leading: leading,
    actions: [
      OpenHandDialogActionButton.primary(
        label: primaryLabel,
        onPressed: onPrimaryPressed,
      ),
    ],
  );
}

Widget buildOpenHandDialogActionsBar({
  required List<Widget> actions,
  Widget? leading,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  double spacing = kOpenHandDialogActionSpacing,
}) {
  final actionsRow = Center(
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: spacing,
      runSpacing: spacing,
      children: actions,
    ),
  );
  if (leading == null) {
    return Padding(padding: padding, child: actionsRow);
  }
  return Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        SizedBox(height: spacing),
        actionsRow,
      ],
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
            kOpenHandGap12,
            Flexible(child: content),
            kOpenHandGap12,
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
    kOpenHandHGap10,
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
              kOpenHandGap8,
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

/// 审批类弹窗的键盘处理：Esc 吞掉，回车即确认。
///
/// 审批必须是显式动作，所以 Esc 只消费不关闭——否则误触一下就等于默默放弃。
/// 两个审批弹窗此前各写了一份同样的判断，[onConfirm] 是唯一的差异。
KeyEventResult handleOpenHandApprovalDialogKey(
  KeyEvent event, {
  required VoidCallback onConfirm,
}) {
  if (event.logicalKey == LogicalKeyboardKey.escape) {
    return KeyEventResult.handled;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  if (event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
    onConfirm();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// 审批类弹窗顶部的「图标徽章 + 标题 + 说明」。
///
/// 写命令确认与 MCP 写调用确认此前各内联了一份完全相同的布局，只有图标与
/// 文案不同。
Widget buildOpenHandApprovalDialogHeader(
  BuildContext context, {
  required IconData icon,
  required Color accent,
  required String title,
  required String description,
}) {
  final theme = Theme.of(context);
  return Row(
    children: [
      Container(
        width: kOpenHandApprovalHeaderBadgeSize,
        height: kOpenHandApprovalHeaderBadgeSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(kOpenHandRadius16),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Icon(icon, color: accent),
      ),
      kOpenHandHGap14,
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            kOpenHandGap4,
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// 校验提示展开 / 收起的时长。
const Duration kOpenHandDialogValidationRevealDuration = Duration(
  milliseconds: 180,
);

Widget buildOpenHandDialogValidationMessage(
  BuildContext context, {
  required String? message,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final content = message == null
      ? null
      : DecoratedBox(
          key: ValueKey<String>(message),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(kOpenHandRadius14),
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
                kOpenHandHGap8,
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
  return OpenHandVerticalRevealSwitcher(
    duration: kOpenHandDialogValidationRevealDuration,
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
  if (!elevation.isFinite || elevation < 0) {
    throw ArgumentError.value(elevation, 'elevation', '必须为有限非负数。');
  }
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
    return OpenHandEscapeDismissScope(child: stableHitTest);
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
          borderRadius: kOpenHandPillBorderRadius,
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
/// 为当前 ModalRoute 接上 Escape 关闭。
///
/// 直接监听硬件按键而不是只挂 Shortcuts：弹窗里的输入框、WebView 会先吃掉
/// 按键，只靠焦点树上的快捷键在这些场景下按 Esc 是没反应的。同时用
/// `_dismissRequested` 挡住连按，避免退场动画期间重复触发导致一次弹掉两层。
///
/// MCP 运维弹窗此前另写了一份完全相同的实现，只多一个 [enabled] 开关；
/// 那个开关现在并入这里。
class OpenHandEscapeDismissScope extends StatefulWidget {
  const OpenHandEscapeDismissScope({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// 为 false 时不响应 Escape（例如弹窗内已有更内层的可关闭浮层）。
  final bool enabled;

  @override
  State<OpenHandEscapeDismissScope> createState() =>
      _OpenHandEscapeDismissScopeState();
}

class _OpenHandEscapeDismissScopeState
    extends State<OpenHandEscapeDismissScope> {
  ModalRoute<Object?>? _route;
  bool _dismissRequested = false;

  @override
  void didUpdateWidget(covariant OpenHandEscapeDismissScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _dismissRequested = false;
  }

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
    if (!widget.enabled) return false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dismissRequested) return;
      if (!route.isActive || !route.isCurrent) {
        _dismissRequested = false;
        return;
      }
      _popAfterFrame(navigator, route);
    });
    return true;
  }

  void _popAfterFrame(NavigatorState navigator, ModalRoute<Object?> route) {
    try {
      if (!route.isActive || !route.isCurrent || route.navigator != navigator) {
        _dismissRequested = false;
        return;
      }
      // 直接弹出当前路由，绕过弹窗内部的 PopScope.canPop 限制；ESC 关闭仍
      // 只作用于当前弹窗，不影响审批弹窗（审批弹窗不会挂载本作用域）。
      navigator.pop();
    } catch (error, stackTrace) {
      _dismissRequested = false;
      silentLog('dialog', '关闭弹窗时导航器状态异常', error, stackTrace);
    }
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
              if (widget.enabled) _dismiss();
              return null;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }
}

/// 公共过渡构建器，使胶囊、列表项和工具提示等非弹窗界面复用弹窗动效库。
/// 正向或已完成时使用 [DialogAnimationSettings.entranceStyle]，其余状态使用
/// [DialogAnimationSettings.exitStyle]。
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
// 各类过渡组件
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
    final begin = _positiveFiniteDouble(profile.fadeScaleBegin, 0.94);
    return FadeTransition(
      opacity: opacity,
      child: _PaintMatrixTransition(
        animation: motion,
        transformBuilder: (value) => _scaleMatrix(begin, value),
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
    final begin = _positiveFiniteDouble(profile.expandScaleBegin, 0.88);
    return FadeTransition(
      opacity: openHandBoundedCurveAnimation(
        parent: parentAnimation,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
      child: _PaintMatrixTransition(
        animation: motion,
        transformBuilder: (value) => _scaleMatrix(begin, value),
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
    final scaleBegin = _positiveFiniteDouble(profile.rotateScaleBegin, 0.9);
    final turnsBegin = _finiteDouble(profile.rotateTurnsBegin, -0.05);
    return FadeTransition(
      opacity: opacity,
      child: _PaintMatrixTransition(
        animation: motion,
        transformBuilder: (value) {
          final progress = _safeTransformProgress(value);
          final scale = _interpolate(scaleBegin, 1.0, progress);
          final turns = _interpolate(turnsBegin, 0.0, progress);
          return Matrix4.identity()
            ..scaleByDouble(scale, scale, 1.0, 1.0)
            ..rotateZ(turns * math.pi * 2);
        },
        alignment: profile.alignment,
        child: child,
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
      curve: const Interval(0.0, 0.38, curve: kOpenHandSwitchInCurve),
      reverseCurve: const Interval(0.0, 1.0, curve: kOpenHandSwitchOutCurve),
    );
    final scaleMotion = openHandCurveAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );
    final begin = _positiveFiniteDouble(profile.elasticScaleBegin, 0.94);
    return FadeTransition(
      opacity: opacity,
      child: _PaintMatrixTransition(
        animation: scaleMotion,
        transformBuilder: (value) => _scaleMatrix(begin, value),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

/// Q 弹缩放：透明度遵循全局曲线，缩放保留样式自身的轻微过冲与反向收束。
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
      curve: kOpenHandEntranceCurve,
      reverseCurve: kOpenHandSpringExitCurve,
    );
    final begin = _positiveFiniteDouble(profile.springScaleBegin, 0.94);
    return FadeTransition(
      opacity: opacity,
      child: _PaintMatrixTransition(
        animation: scaleMotion,
        transformBuilder: (value) => _scaleMatrix(begin, value),
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

/// 绕 X 轴翻转并渐显，适用于胶囊或列表项切换。
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
      child: _PaintMatrixTransition(
        animation: motion,
        transformBuilder: (value) {
          final t = openHandBoundedProgress(value);
          final angle = (1.0 - t) * _finiteDouble(profile.flipMaxAngle, 1.5708);
          final tilt = (1.0 - t) * _finiteDouble(profile.flipMaxTilt, 0.0);
          return Matrix4.identity()
            ..setEntry(3, 2, _finiteDouble(profile.flipPerspective, 0.0015))
            ..rotateX(angle)
            ..rotateZ(tilt);
        },
        alignment: profile.alignment,
        child: child,
      ),
    );
  }
}

typedef _PaintTransformBuilder = Matrix4 Function(double value);
const double _kMaxTransformProgressMagnitude = 4.0;

Matrix4 _scaleMatrix(double begin, double value) {
  final scale = _interpolate(begin, 1.0, _safeTransformProgress(value));
  return Matrix4.diagonal3Values(scale, scale, 1.0);
}

double _interpolate(double begin, double end, double progress) {
  final value = begin + (end - begin) * progress;
  return value.isFinite ? value : end;
}

double _safeTransformProgress(double value) {
  if (value.isNaN) return 0.0;
  if (!value.isFinite) {
    return value.isNegative
        ? -_kMaxTransformProgressMagnitude
        : _kMaxTransformProgressMagnitude;
  }
  return value
      .clamp(-_kMaxTransformProgressMagnitude, _kMaxTransformProgressMagnitude)
      .toDouble();
}

class _PaintMatrixTransition extends SingleChildRenderObjectWidget {
  const _PaintMatrixTransition({
    required this.animation,
    required this.transformBuilder,
    required this.alignment,
    required Widget super.child,
  });

  final Animation<double> animation;
  final _PaintTransformBuilder transformBuilder;
  final Alignment alignment;

  @override
  _PaintMatrixRenderObject createRenderObject(BuildContext context) {
    return _PaintMatrixRenderObject(
      animation: animation,
      transformBuilder: transformBuilder,
      alignment: alignment,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _PaintMatrixRenderObject renderObject,
  ) {
    renderObject
      ..animation = animation
      ..transformBuilder = transformBuilder
      ..alignment = alignment;
  }
}

/// 仅在绘制阶段更新矩阵，避免动画帧在 LayoutBuilder 布局回调中请求重建。
class _PaintMatrixRenderObject extends RenderTransform {
  _PaintMatrixRenderObject({
    required Animation<double> animation,
    required _PaintTransformBuilder transformBuilder,
    required Alignment alignment,
  }) : _animation = animation,
       _transformBuilder = transformBuilder,
       super(
         transform: transformBuilder(animation.value),
         alignment: alignment,
       );

  Animation<double> _animation;
  _PaintTransformBuilder _transformBuilder;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(_updateTransform);
      value.addListener(_updateTransform);
    }
    _animation = value;
    _updateTransform();
  }

  set transformBuilder(_PaintTransformBuilder value) {
    if (identical(_transformBuilder, value)) return;
    _transformBuilder = value;
    _updateTransform();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_updateTransform);
  }

  @override
  void detach() {
    _animation.removeListener(_updateTransform);
    super.detach();
  }

  void _updateTransform() => transform = _transformBuilder(_animation.value);
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

/// 由 [Animation] 驱动、不会影响布局的绘制阶段位移。
///
/// 渲染对象仅通过 [markNeedsPaint] 改变绘制偏移，可复用像素位移动画而不改变布局尺寸。
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

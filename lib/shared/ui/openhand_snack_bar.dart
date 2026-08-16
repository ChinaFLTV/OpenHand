import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/theme/openhand_status_colors.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';
import 'openhand_tap_region.dart';
import 'safe_edge_insets.dart';

const EdgeInsets _kDefaultSnackBarFloatingMargin = EdgeInsets.symmetric(
  horizontal: 20,
  vertical: 14,
);
const EdgeInsets _kDefaultSnackBarContentPadding = EdgeInsets.symmetric(
  horizontal: 16,
  vertical: 14,
);

/// 提示条停留时长按「这条文案读完要多久」分四档，调用方只在这四档里选。
///
/// 此前上百处调用各自内联 `Duration(seconds: N)`，N 取遍 1..8，且同一类提示
/// 的取值互相矛盾——光是错误提示就出现过 2/3/4/5/6 五种。分档后取值集中在
/// 这里，想整体调快调慢只改一处。
const Duration kOpenHandSnackBarBriefDuration = Duration(seconds: 2);
const Duration kOpenHandSnackBarNormalDuration = Duration(seconds: 3);
const Duration kOpenHandSnackBarDetailedDuration = Duration(seconds: 4);
const Duration kOpenHandSnackBarLongReadDuration = Duration(seconds: 6);

enum OpenHandSnackKind { info, success, error }

void showOpenHandSuccessSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarBriefDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  OpenHandSnackBar.flash(
    context,
    message,
    kind: OpenHandSnackKind.success,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showOpenHandInfoSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarNormalDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  OpenHandSnackBar.flash(
    context,
    message,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

void showOpenHandErrorSnack(
  BuildContext context,
  String message, {
  Duration duration = kOpenHandSnackBarDetailedDuration,
  SnackBarAction? action,
  int? maxLines,
}) {
  OpenHandSnackBar.flash(
    context,
    message,
    kind: OpenHandSnackKind.error,
    duration: duration,
    action: action,
    maxLines: maxLines,
  );
}

/// Convenience flash for feature views after async/setState/dialog pop.
///
/// Defaults [postFrame] to `true` so callers avoid showing a snack during
/// an active frame transition. Prefer this over ad-hoc local `_showSnackBar`
/// wrappers that only forward to [OpenHandSnackBar.flash].
void flashOpenHandSnack(
  BuildContext context,
  String message, {
  OpenHandSnackKind kind = OpenHandSnackKind.info,
  Duration? duration,
  SnackBarAction? action,
  int? maxLines,
  bool postFrame = true,
}) {
  OpenHandSnackBar.flash(
    context,
    message,
    kind: kind,
    duration: duration,
    action: action,
    maxLines: maxLines,
  postFrame: postFrame,
  );
}

void showOpenHandSnackBarOn(
  BuildContext context,
  ScaffoldMessengerState? messenger,
  SnackBar snackBar,
) {
  OpenHandSnackBar.show(context, messenger, snackBar);
}

 /// 在 catch 块中安全地展示错误提示条。
 ///
 /// 收敛全库重复的 `catch (e) { if (!context.mounted) return; flashOpenHandSnack(...) }` 样板。
 void flashOpenHandErrorOnCatch(
   BuildContext context,
   String message,
 ) {
   if (!context.mounted) return;
   OpenHandSnackBar.flash(
     context,
     message,
     kind: OpenHandSnackKind.error,
   );
 }

/// 用新提示条顶替当前正在显示的一条：先收起再展示。
///
/// 同一操作的连续反馈（「已复制」紧随「正在复制」、失败提示覆盖成功提示）
/// 必须立刻可见，若直接 show 会排到队尾等前一条自然消失。调用方无需再各自
/// 内联 `ScaffoldMessenger` 查找 + [OpenHandSnackBar.hideCurrentOn] 样板。
void replaceOpenHandSnack(
  BuildContext context,
  String message, {
  OpenHandSnackKind kind = OpenHandSnackKind.info,
  Duration? duration,
  SnackBarAction? action,
  int? maxLines,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  OpenHandSnackBar.hideCurrentOn(messenger);
  OpenHandSnackBar.show(
    context,
    messenger,
    OpenHandSnackBar.ofKind(
      context,
      kind,
      message,
      duration: duration,
      action: action,
      maxLines: maxLines,
    ),
  );
}

class OpenHandGlobalSnackBarHost extends StatefulWidget {
  const OpenHandGlobalSnackBarHost({super.key});

  static const Key hostKey = ValueKey<String>('openhand-global-snack-bar-host');
  static const int maxQueuedSnackBars = 24;

  static final Queue<SnackBar> _pendingSnackBars = Queue<SnackBar>();
  static _OpenHandGlobalSnackBarHostState? _state;

  static bool get isMounted => _state != null;

  static void showSnackBar(SnackBar snackBar) {
    final state = _state;
    if (state == null) {
      _enqueueBounded(_pendingSnackBars, snackBar);
      return;
    }
    state._enqueue(snackBar);
  }

  static void hideCurrent() {
    _state?._dismissCurrent();
  }

  static void _enqueueBounded(Queue<SnackBar> queue, SnackBar snackBar) {
    while (queue.length >= maxQueuedSnackBars) {
      queue.removeFirst();
    }
    queue.addLast(snackBar);
  }

  @override
  State<OpenHandGlobalSnackBarHost> createState() =>
      _OpenHandGlobalSnackBarHostState();
}

class _OpenHandGlobalSnackBarHostState extends State<OpenHandGlobalSnackBarHost>
    with SingleTickerProviderStateMixin {
  final Queue<SnackBar> _queue = Queue<SnackBar>();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration.zero,
    reverseDuration: Duration.zero,
  )..addStatusListener(_handleAnimationStatus);

  SnackBar? _currentSnackBar;
  Timer? _dismissTimer;
  bool _isDismissing = false;
  bool _visibleNotified = false;

  @override
  void initState() {
    super.initState();
    OpenHandGlobalSnackBarHost._state = this;
    while (OpenHandGlobalSnackBarHost._pendingSnackBars.isNotEmpty) {
      _queue.addLast(
        OpenHandGlobalSnackBarHost._pendingSnackBars.removeFirst(),
      );
    }
    _showNextIfIdle();
  }

  @override
  void dispose() {
    if (identical(OpenHandGlobalSnackBarHost._state, this)) {
      OpenHandGlobalSnackBarHost._state = null;
    }
    _dismissTimer?.cancel();
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _enqueue(SnackBar snackBar) {
    OpenHandGlobalSnackBarHost._enqueueBounded(_queue, snackBar);
    _showNextIfIdle();
  }

  DialogAnimationSettings _resolveMotionSettings() {
    return OpenHandSnackBar._resolveMotionSettings(context);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_visibleNotified) {
      _visibleNotified = true;
      _currentSnackBar?.onVisible?.call();
      _armDismissTimer();
      return;
    }
    if (status == AnimationStatus.dismissed && _isDismissing) {
      _removeCurrentAndContinue();
    }
  }

  void _showNextIfIdle() {
    if (!mounted || _currentSnackBar != null || _queue.isEmpty) return;
    final next = _queue.removeFirst();
    final settings = _resolveMotionSettings();
    final tickerEnabled = openHandTickerMotionEnabled(context);
    final entranceMotionEnabled = tickerEnabled && !settings.entranceDisabled;
    _dismissTimer?.cancel();
    _isDismissing = false;
    _visibleNotified = false;
    _controller.duration = tickerEnabled
        ? settings.entranceDuration
        : Duration.zero;
    _controller.reverseDuration = tickerEnabled
        ? settings.exitDuration
        : Duration.zero;
    setState(() => _currentSnackBar = next);
    if (!entranceMotionEnabled) {
      _visibleNotified = true;
      _controller.value = 1;
      next.onVisible?.call();
      _armDismissTimer();
      return;
    }
    _controller.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_currentSnackBar, next)) return;
      _controller.forward();
    });
  }

  void _armDismissTimer() {
    final current = _currentSnackBar;
    if (current == null) return;
    _dismissTimer?.cancel();
    final duration = OpenHandSnackBar._boundedDuration(current.duration);
    if (duration <= Duration.zero) {
      _dismissCurrent();
      return;
    }
    _dismissTimer = startSafeTimer(duration, _dismissCurrent);
  }

  void _dismissCurrent() {
    final current = _currentSnackBar;
    if (current == null || _isDismissing) return;
    _dismissTimer?.cancel();
    final settings = _resolveMotionSettings();
    final exitMotionEnabled =
        openHandTickerMotionEnabled(context) && !settings.exitDisabled;
    _controller.reverseDuration = exitMotionEnabled
        ? settings.exitDuration
        : Duration.zero;
    if (!exitMotionEnabled || _controller.value <= 0) {
      _removeCurrentAndContinue();
      return;
    }
    _isDismissing = true;
    _controller.reverse();
  }

  void _removeCurrentAndContinue() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _isDismissing = false;
    _visibleNotified = false;
    _controller.value = 0;
    setState(() => _currentSnackBar = null);
    _showNextIfIdle();
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentSnackBar;
    final settings = _resolveMotionSettings();
    return Align(
      key: OpenHandGlobalSnackBarHost.hostKey,
      alignment: Alignment.bottomCenter,
      child: current == null
          ? const SizedBox.shrink()
          : _OpenHandGlobalSnackBarEntry(
              snackBar: current,
              animation: _controller,
              settings: settings,
              onDismiss: _dismissCurrent,
              onRemove: _removeCurrentAndContinue,
            ),
    );
  }
}

class OpenHandSnackBar {
  OpenHandSnackBar._();

  static final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static const Duration _minimumDisplayDuration = Duration(milliseconds: 900);
  static const Duration _maximumDisplayDuration = Duration(seconds: 8);
  static const double _actionMaxWidth = 220;

  static DialogAnimationSettings _resolveMotionSettings(BuildContext context) {
    return openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
  }

  static Widget _modernizeLegacyTextContent(
    BuildContext context,
    Widget content,
  ) {
    if (content is _OpenHandSnackBarMotion) return content.child;
    if (content is! Text) return content;
    final cs = Theme.of(context).colorScheme;
    return _OpenHandSnackBarMessage(
      icon: Icons.info_rounded,
      tint: cs.inversePrimary,
      child: content,
    );
  }

  static Duration _boundedDuration(Duration duration) {
    if (duration <= Duration.zero) return Duration.zero;
    if (duration < _minimumDisplayDuration) return _minimumDisplayDuration;
    if (duration > _maximumDisplayDuration) return _maximumDisplayDuration;
    return duration;
  }

  static void hideGlobal({
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) {
    OpenHandGlobalSnackBarHost.hideCurrent();
  }

  static void hideCurrentOn(
    ScaffoldMessengerState? messenger, {
    SnackBarClosedReason reason = SnackBarClosedReason.hide,
  }) {
    if (messenger == null) {
      OpenHandGlobalSnackBarHost.hideCurrent();
      return;
    }
    if (OpenHandGlobalSnackBarHost.isMounted ||
        identical(messenger, rootMessengerKey.currentState)) {
      OpenHandGlobalSnackBarHost.hideCurrent();
    }
    messenger.hideCurrentSnackBar(reason: reason);
  }

  static Widget _messageContent({
    required IconData icon,
    required Color tint,
    required Widget child,
  }) {
    return _OpenHandSnackBarMessage(icon: icon, tint: tint, child: child);
  }

  static TextStyle? _foregroundTextStyle(Color? foregroundColor) {
    return foregroundColor == null ? null : TextStyle(color: foregroundColor);
  }

  static void show(
    BuildContext context,
    ScaffoldMessengerState? messenger,
    SnackBar snackBar,
  ) {
    if (messenger == null || !context.mounted) {
      OpenHandGlobalSnackBarHost.showSnackBar(snackBar);
      return;
    }
    if (OpenHandGlobalSnackBarHost.isMounted ||
        identical(messenger, rootMessengerKey.currentState)) {
      OpenHandGlobalSnackBarHost.showSnackBar(snackBar);
      return;
    }
    _showOn(context, messenger, snackBar);
  }

  static void showInContext(BuildContext context, SnackBar snackBar) {
    if (!context.mounted) {
      OpenHandGlobalSnackBarHost.showSnackBar(snackBar);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      show(context, messenger, snackBar);
      return;
    }
    OpenHandGlobalSnackBarHost.showSnackBar(snackBar);
  }

  static void _showOn(
    BuildContext context,
    ScaffoldMessengerState messenger,
    SnackBar snackBar,
  ) {
    final motionSettings = openHandTickerMotionEnabled(context)
        ? _resolveMotionSettings(context)
        : OpenHandMotionDefaults.disabled;
    final wrapped = _ensureMotionWrapped(context, snackBar, motionSettings);
    messenger.showSnackBar(
      wrapped,
      snackBarAnimationStyle: openHandAnimationStyle(motionSettings),
    );
  }

  static SnackBar _ensureMotionWrapped(
    BuildContext context,
    SnackBar snackBar,
    DialogAnimationSettings motionSettings,
  ) {
    final content = snackBar.content;
    if (content is _OpenHandSnackBarMotion) return snackBar;
    final modernContent = _modernizeLegacyTextContent(context, content);
    final wrappedContent = _OpenHandSnackBarContent(
      message: modernContent,
      action: snackBar.action,
    );
    return SnackBar(
      key: snackBar.key,
      content: _OpenHandSnackBarMotion(
        settings: motionSettings,
        child: wrappedContent,
      ),
      duration: _boundedDuration(snackBar.duration),
      persist: false,
      backgroundColor: snackBar.backgroundColor,
      behavior: snackBar.behavior,
      dismissDirection: snackBar.dismissDirection,
      elevation: snackBar.elevation,
      margin: snackBar.margin,
      padding: snackBar.padding,
      width: snackBar.width,
      shape: snackBar.shape,
      showCloseIcon: false,
      onVisible: snackBar.onVisible,
      hitTestBehavior: snackBar.hitTestBehavior,
      clipBehavior: snackBar.clipBehavior,
      actionOverflowThreshold: snackBar.actionOverflowThreshold,
    );
  }

  static SnackBar success(
    BuildContext context,
    String message, {
    Duration duration = kOpenHandSnackBarBriefDuration,
    SnackBarAction? action,
    int? maxLines,
  }) {
    return _build(
      context,
      message,
      icon: Icons.check_circle_rounded,
      tint: OpenHandStatusColors.success,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  static SnackBar error(
    BuildContext context,
    String message, {
    Duration duration = kOpenHandSnackBarDetailedDuration,
    SnackBarAction? action,
    int? maxLines,
  }) {
    return _build(
      context,
      message,
      icon: Icons.error_rounded,
      tint: OpenHandStatusColors.error,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  static SnackBar info(
    BuildContext context,
    String message, {
    Duration duration = kOpenHandSnackBarNormalDuration,
    SnackBarAction? action,
    int? maxLines,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _build(
      context,
      message,
      icon: Icons.info_rounded,
      tint: cs.inversePrimary,
      duration: duration,
      action: action,
      maxLines: maxLines,
    );
  }

  static Duration defaultDurationForKind(OpenHandSnackKind kind) {
    return switch (kind) {
      OpenHandSnackKind.success => kOpenHandSnackBarBriefDuration,
      OpenHandSnackKind.error => kOpenHandSnackBarDetailedDuration,
      OpenHandSnackKind.info => kOpenHandSnackBarNormalDuration,
    };
  }

  static SnackBar ofKind(
    BuildContext context,
    OpenHandSnackKind kind,
    String message, {
    Duration? duration,
    SnackBarAction? action,
    int? maxLines,
  }) {
    final effectiveDuration = duration ?? defaultDurationForKind(kind);
    return switch (kind) {
      OpenHandSnackKind.success => success(
        context,
        message,
        duration: effectiveDuration,
        action: action,
        maxLines: maxLines,
      ),
      OpenHandSnackKind.error => error(
        context,
        message,
        duration: effectiveDuration,
        action: action,
        maxLines: maxLines,
      ),
      OpenHandSnackKind.info => info(
        context,
        message,
        duration: effectiveDuration,
        action: action,
        maxLines: maxLines,
      ),
    };
  }

  static void showKind(
    BuildContext context,
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
    Duration? duration,
    SnackBarAction? action,
    int? maxLines,
  }) {
    showInContext(
      context,
      ofKind(
        context,
        kind,
        message,
        duration: duration,
        action: action,
        maxLines: maxLines,
      ),
    );
  }

  static void flash(
    BuildContext context,
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
    Duration? duration,
    SnackBarAction? action,
    int? maxLines,
    bool postFrame = false,
  }) {
    void dispatch() {
      if (!context.mounted) return;
      showKind(
        context,
        message,
        kind: kind,
        duration: duration,
        action: action,
        maxLines: maxLines,
      );
    }

    if (postFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dispatch());
    } else {
      dispatch();
    }
  }

  static SnackBar notification(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color tint,
    required Color backgroundColor,
    required Color foregroundColor,
    Duration duration = kOpenHandSnackBarDetailedDuration,
  }) {
    return _build(
      context,
      message,
      icon: icon,
      tint: tint,
      duration: duration,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      maxLines: 3,
    );
  }

  static SnackBar _build(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color tint,
    required Duration duration,
    SnackBarAction? action,
    Color? backgroundColor,
    Color? foregroundColor,
    int? maxLines,
  }) {
    final textStyle = _foregroundTextStyle(foregroundColor);
    return SnackBar(
      duration: _boundedDuration(duration),
      action: action,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
      content: _messageContent(
        icon: icon,
        tint: tint,
        child: Text(
          message,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: textStyle,
        ),
      ),
    );
  }
}

class _OpenHandGlobalSnackBarEntry extends StatelessWidget {
  const _OpenHandGlobalSnackBarEntry({
    required this.snackBar,
    required this.animation,
    required this.settings,
    required this.onDismiss,
    required this.onRemove,
  });

  final SnackBar snackBar;
  final Animation<double> animation;
  final DialogAnimationSettings settings;
  final VoidCallback onDismiss;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final snackBarTheme = SnackBarTheme.of(context);
    final behavior =
        snackBar.behavior ?? snackBarTheme.behavior ?? SnackBarBehavior.fixed;
    final margin = behavior == SnackBarBehavior.floating
        ? openHandResolvedInsetsOrFallback(
            context,
            snackBar.margin ?? snackBarTheme.insetPadding,
            _kDefaultSnackBarFloatingMargin,
          )
        : EdgeInsets.zero;
    final padding = openHandResolvedInsetsOrFallback(
      context,
      snackBar.padding,
      _kDefaultSnackBarContentPadding,
    );
    final width =
        _safeSnackBarWidth(snackBar.width ?? snackBarTheme.width) ??
        double.infinity;
    final shape =
        snackBar.shape ??
        snackBarTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius14));
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor =
        snackBar.backgroundColor ??
        snackBarTheme.backgroundColor ??
        (isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.inverseSurface);
    final elevation =
        snackBar.elevation ?? snackBarTheme.elevation ?? (isDark ? 6 : 4);
    final foregroundColor = isDark
        ? colorScheme.onSurface
        : colorScheme.onInverseSurface;
    final textStyle =
        snackBarTheme.contentTextStyle ??
        theme.textTheme.bodyMedium?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w500,
        ) ??
        TextStyle(color: foregroundColor, fontWeight: FontWeight.w500);
    final body = DefaultTextStyle(
      style: textStyle,
      child: _OpenHandSnackBarContent(
        message: OpenHandSnackBar._modernizeLegacyTextContent(
          context,
          snackBar.content,
        ),
        action: snackBar.action,
        onActionPressed: snackBar.action == null
            ? null
            : () {
                snackBar.action!.onPressed();
                onDismiss();
              },
        onDismiss: onDismiss,
      ),
    );

    Widget child = Material(
      shape: shape,
      elevation: elevation,
      color: backgroundColor,
      clipBehavior: snackBar.clipBehavior,
      child: Padding(padding: padding, child: body),
    );

    child = Semantics(
      container: true,
      liveRegion: true,
      onDismiss: onDismiss,
      child: Dismissible(
        key: ObjectKey(snackBar),
        direction:
            snackBar.dismissDirection ??
            snackBarTheme.dismissDirection ??
            DismissDirection.down,
        resizeDuration: null,
        behavior: snackBar.hitTestBehavior ?? HitTestBehavior.deferToChild,
        onDismissed: (_) => onRemove(),
        child: child,
      ),
    );

    if (!openHandMotionDisabled(settings) &&
        openHandTickerMotionEnabled(context) &&
        animation.value >= 0) {
      child = AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, builtChild) {
          return buildAnimationStyleTransition(
            animation: animation,
            settings: settings,
            child: builtChild!,
          );
        },
      );
    }

    if (behavior == SnackBarBehavior.floating) {
      child = SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: margin,
          child: SizedBox(width: width, child: child),
        ),
      );
    } else {
      child = SafeArea(
        top: false,
        child: SizedBox(width: double.infinity, child: child),
      );
    }

    return child;
  }
}

double? _safeSnackBarWidth(double? width) {
  if (width == null || !width.isFinite || width <= 0) return null;
  return width;
}

class _OpenHandSnackBarMessage extends StatelessWidget {
  const _OpenHandSnackBarMessage({
    required this.icon,
    required this.tint,
    required this.child,
  });

  final IconData icon;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: tint, size: 20),
        kOpenHandHGap12,
        Flexible(child: child),
      ],
    );
  }
}

class _OpenHandSnackBarContent extends StatelessWidget {
  const _OpenHandSnackBarContent({
    required this.message,
    required this.action,
    this.onDismiss,
    this.onActionPressed,
  });

  final Widget message;
  final SnackBarAction? action;
  final VoidCallback? onDismiss;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final onActionPressed = this.onActionPressed;
    return Row(
      children: [
        Expanded(child: message),
        if (action != null) ...[
          kOpenHandHGap10,
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OpenHandSnackBar._actionMaxWidth,
            ),
            child: onActionPressed == null
                ? action
                : _OpenHandGlobalSnackBarActionButton(
                    action: action,
                    onPressed: onActionPressed,
                  ),
          ),
        ],
        kOpenHandHGap6,
        onDismiss == null
            ? const _SnackBarCloseButton()
            : _OpenHandGlobalSnackBarCloseButton(onTap: onDismiss!),
      ],
    );
  }
}

class _OpenHandGlobalSnackBarActionButton extends StatelessWidget {
  const _OpenHandGlobalSnackBarActionButton({
    required this.action,
    required this.onPressed,
  });

  final SnackBarAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snackBarTheme = SnackBarTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foreground =
        action.textColor ??
        snackBarTheme.actionTextColor ??
        (isDark ? theme.colorScheme.primary : theme.colorScheme.inversePrimary);
    final background =
        action.backgroundColor ?? snackBarTheme.actionBackgroundColor;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: onPressed,
      child: Text(action.label),
    );
  }
}

class _OpenHandSnackBarMotion extends StatelessWidget {
  const _OpenHandSnackBarMotion({required this.settings, required this.child});

  final DialogAnimationSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!openHandTickerMotionEnabled(context) ||
        openHandMotionDisabled(settings)) {
      return child;
    }
    final animation = context
        .findAncestorWidgetOfExactType<SnackBar>()
        ?.animation;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, builtChild) {
        return buildAnimationStyleTransition(
          animation: animation,
          settings: settings,
          child: builtChild!,
        );
      },
    );
  }
}

class _SnackBarCloseButton extends StatelessWidget {
  const _SnackBarCloseButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color =
        (isDark
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onInverseSurface)
            .withValues(alpha: 0.7);
    final tooltip = MaterialLocalizations.of(context).closeButtonTooltip;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _OpenHandGlobalSnackBarCloseButton extends StatelessWidget {
  const _OpenHandGlobalSnackBarCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color =
        (isDark
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onInverseSurface)
            .withValues(alpha: 0.7);
    final tooltip = MaterialLocalizations.of(context).closeButtonTooltip;
    return Semantics(
      button: true,
      label: tooltip,
      child: OpenHandTapRegion(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.close_rounded, size: 18, color: color),
        ),
      ),
    );
  }
}

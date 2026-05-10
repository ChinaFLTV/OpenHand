import 'package:flutter/material.dart';

/// Lightweight helpers for building consistent, icon-prefixed
/// [SnackBar]s on top of the global [SnackBarThemeData].
///
/// Use whenever a transient outcome notice would benefit from a
/// success/error/info affordance. The plain string-only
/// `OpenHandSnackBar.show(context, messenger, snackBar)` also applies
/// the app-wide presentation animation so legacy and custom snackbars
/// can opt into the same motion language.
class OpenHandSnackBar {
  OpenHandSnackBar._();

  static const AnimationStyle _motionStyle = AnimationStyle(
    duration: Duration(milliseconds: 360),
    reverseDuration: Duration(milliseconds: 230),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    ScaffoldMessengerState messenger,
    SnackBar snackBar,
  ) {
    final wrapped = _ensureMotionWrapped(snackBar);
    return messenger.showSnackBar(
      wrapped,
      snackBarAnimationStyle:
          MediaQuery.maybeDisableAnimationsOf(context) == true
          ? AnimationStyle.noAnimation
          : _motionStyle,
    );
  }

  /// Re-emits a [SnackBar] with its content wrapped in [_OpenHandSnackBarMotion]
  /// (idempotent — already-wrapped content is left untouched), preserving every
  /// caller-supplied field. Ensures every snackbar that flows through
  /// [OpenHandSnackBar.show] receives the same Q-bouncy entry / decay-out
  /// motion regardless of where it was constructed.
  /// 同时注入无背景的自定义关闭按钮，替代框架内置的有白色背景的 close icon。
  static SnackBar _ensureMotionWrapped(SnackBar snackBar) {
    final content = snackBar.content;
    if (content is _OpenHandSnackBarMotion) return snackBar;
    // 当 SnackBar 有 action 时不注入关闭按钮（action 本身提供了交互入口，
    // 且 Flutter 会在 action 右侧自动布局，再加关闭按钮会导致底部拥挤）。
    final hasAction = snackBar.action != null;
    final wrappedContent = hasAction
        ? content
        : Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 8),
              const _SnackBarCloseButton(),
            ],
          );
    return SnackBar(
      key: snackBar.key,
      content: _OpenHandSnackBarMotion(
        duration: snackBar.duration,
        child: wrappedContent,
      ),
      action: snackBar.action,
      duration: snackBar.duration,
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

  /// Green-leaning tick variant. Primary use: confirming a save /
  /// commit / restore action when a `HighlightPulse` is not
  /// reachable from the current widget.
  static SnackBar success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    return _build(
      context,
      message,
      icon: Icons.check_circle_rounded,
      tint: const Color(0xFF22C55E),
      duration: duration,
      action: action,
    );
  }

  /// Red-leaning warning. Primary use: surfacing a failure that the
  /// user should notice but that doesn't require a modal.
  static SnackBar error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    return _build(
      context,
      message,
      icon: Icons.error_rounded,
      tint: const Color(0xFFEF4444),
      duration: duration,
      action: action,
    );
  }

  /// Neutral info variant — picks the inverse-primary color from
  /// the active theme so it follows light/dark mode correctly.
  static SnackBar info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _build(
      context,
      message,
      icon: Icons.info_rounded,
      tint: cs.inversePrimary,
      duration: duration,
      action: action,
    );
  }

  static SnackBar notification(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color tint,
    required Color backgroundColor,
    required Color foregroundColor,
    Duration duration = const Duration(seconds: 4),
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
    final textStyle = foregroundColor == null
        ? null
        : TextStyle(color: foregroundColor);
    return SnackBar(
      duration: duration,
      action: action,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.down,
      // Material's built-in close icon is enabled globally via SnackBarThemeData
      // (see openhand_theme.dart). We deliberately do NOT pass `showCloseIcon`
      // here so the theme default wins, and snackbars that have an action still
      // get a close affordance — fixing the long-stuck "auth-failed" bar that
      // previously could only be dismissed by waiting out the duration.
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: tint, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenHandSnackBarMotion extends StatefulWidget {
  const _OpenHandSnackBarMotion({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  State<_OpenHandSnackBarMotion> createState() =>
      _OpenHandSnackBarMotionState();
}

class _OpenHandSnackBarMotionState extends State<_OpenHandSnackBarMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _offset;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    final entry = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(entry);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(entry);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _offset,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

/// 无背景的 SnackBar 关闭按钮。
/// 替代 Flutter 框架内置的 IconButton（M3 下有不可控的白色圆形背景），
/// 使用纯透明背景 + 半透明前景色，视觉上更干净。
class _SnackBarCloseButton extends StatelessWidget {
  const _SnackBarCloseButton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onInverseSurface
        .withValues(alpha: 0.7);
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).hideCurrentSnackBar(
          reason: SnackBarClosedReason.dismiss,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.close_rounded, size: 18, color: color),
      ),
    );
  }
}

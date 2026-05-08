import 'dart:async';

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
    return messenger.showSnackBar(
      snackBar,
      snackBarAnimationStyle:
          MediaQuery.maybeDisableAnimationsOf(context) == true
          ? AnimationStyle.noAnimation
          : _motionStyle,
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
      showCloseIcon: false,
      content: _OpenHandSnackBarMotion(
        duration: duration,
        child: Row(
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
            if (action == null) ...[
              const SizedBox(width: 10),
              _OpenHandSnackBarCloseButton(foregroundColor: foregroundColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _OpenHandSnackBarCloseButton extends StatelessWidget {
  const _OpenHandSnackBarCloseButton({this.foregroundColor});

  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foregroundColor ?? theme.colorScheme.onInverseSurface;
    return Tooltip(
      message: MaterialLocalizations.of(context).closeButtonTooltip,
      child: IconButton(
        onPressed: () {
          ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        },
        icon: Icon(Icons.close_rounded, size: 18, color: color),
        style: IconButton.styleFrom(
          foregroundColor: color,
          hoverColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.12),
          minimumSize: const Size(30, 30),
          maximumSize: const Size(30, 30),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
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
  Timer? _reverseTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curve);
    _scale = Tween<double>(begin: 0.965, end: 1).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
      _armReverseTimer();
    }
  }

  void _armReverseTimer() {
    _reverseTimer?.cancel();
    final visibleDuration = widget.duration - const Duration(milliseconds: 230);
    if (visibleDuration <= Duration.zero) return;
    _reverseTimer = Timer(visibleDuration, () {
      if (!mounted || _controller.status != AnimationStatus.completed) return;
      unawaited(_controller.reverse());
    });
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
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

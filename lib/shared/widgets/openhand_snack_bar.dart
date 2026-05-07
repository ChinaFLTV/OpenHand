import 'package:flutter/material.dart';

/// Lightweight helpers for building consistent, icon-prefixed
/// [SnackBar]s on top of the global [SnackBarThemeData].
///
/// Use whenever a transient outcome notice would benefit from a
/// success/error/info affordance. The plain string-only
/// `ScaffoldMessenger.showSnackBar(SnackBar(content: Text(...)))`
/// pattern remains valid for legacy call sites and continues to
/// pick up the global theme styling.
class OpenHandSnackBar {
  OpenHandSnackBar._();

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
      content: _OpenHandSnackBarMotion(
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
          ],
        ),
      ),
    );
  }
}

class _OpenHandSnackBarMotion extends StatefulWidget {
  const _OpenHandSnackBarMotion({required this.child});

  final Widget child;

  @override
  State<_OpenHandSnackBarMotion> createState() => _OpenHandSnackBarMotionState();
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
      duration: const Duration(milliseconds: 340),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
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
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

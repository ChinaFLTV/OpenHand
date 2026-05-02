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

  static SnackBar _build(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color tint,
    required Duration duration,
    SnackBarAction? action,
  }) {
    return SnackBar(
      duration: duration,
      action: action,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: tint, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(message)),
        ],
      ),
    );
  }
}

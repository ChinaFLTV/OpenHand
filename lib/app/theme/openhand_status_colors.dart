import 'package:flutter/material.dart';

/// Canonical status color palette shared across SnackBars, dialogs and
/// inline indicators (badges, dots, severity icons).
///
/// These values intentionally live outside [OpenHandPalette] (which is a
/// `ThemeExtension` keyed to canvas / surface tones): a "danger" red has
/// to stay red in both light and dark themes so users perceive risk
/// consistently. Tailwind's 500-shade values are used so we stay aligned
/// with the editor / docs visual language.
@immutable
class OpenHandStatusColors {
  const OpenHandStatusColors._();

  /// Green-500 — success / saved / online.
  static const Color success = Color(0xFF22C55E);

  /// Red-500 — error / failure / destructive action.
  static const Color error = Color(0xFFEF4444);

  /// Amber-500 — pending / partial / attention but not destructive.
  static const Color warning = Color(0xFFF59E0B);

  /// Blue-500 — informational / neutral notice (only when a colored
  /// affordance is preferred over the theme's `inversePrimary`).
  static const Color info = Color(0xFF3B82F6);
}

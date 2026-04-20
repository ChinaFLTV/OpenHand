import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A refined bouncing scroll physics that preserves the premium elastic feel
/// while preventing the content from overscrolling too far.
///
/// Key differences from stock [BouncingScrollPhysics]:
/// - **Higher friction**: Overscroll resistance is ~40 % stronger so the
///   content cannot travel as far past the edges, even on fast flings.
/// - **Stiffer spring**: Settles 40-60 % faster than the default iOS spring,
///   giving a snappy, premium feel with minimal secondary oscillation.
///
/// These two tweaks together keep the "Q-bounce" alive while preventing the
/// large displacement that triggers repaint-boundary ghosting on macOS.
///
/// Usage:
/// ```dart
/// ListView(
///   physics: const OpenHandBouncingScrollPhysics(
///     parent: AlwaysScrollableScrollPhysics(),
///   ),
/// )
/// ```
class OpenHandBouncingScrollPhysics extends BouncingScrollPhysics {
  const OpenHandBouncingScrollPhysics({super.parent});

  @override
  OpenHandBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return OpenHandBouncingScrollPhysics(parent: buildParent(ancestor));
  }

  /// A stiffer, more damped spring than the stock iOS default
  /// (mass 0.5, stiffness 100, damping ≈14).
  ///
  /// Higher stiffness → snappier return.
  /// Higher damping  → less oscillation / fewer secondary bounces.
  @override
  SpringDescription get spring => const SpringDescription(
    mass: 0.5,
    stiffness: 180.0,
    damping: 24.0,
  );

  /// More aggressive friction than the default (0.52 → 0.32).
  ///
  /// [overscrollFraction] is how far we've overscrolled relative to the
  /// viewport size (0.0 = at edge, 1.0 = overscrolled by a full viewport).
  /// Returning a *smaller* value means each gesture pixel moves the content
  /// *less* in the overscroll zone, so the maximum practical overscroll
  /// distance is naturally limited without any hard boundary clamping.
  @override
  double frictionFactor(double overscrollFraction) =>
      0.32 * math.pow(1 - overscrollFraction, 2);
}

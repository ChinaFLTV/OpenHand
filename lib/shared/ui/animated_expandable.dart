import 'package:flutter/material.dart';

/// Reusable expand/collapse container with the same Q-elastic feel as
/// `_ExpandableToolSection` in the tool-call card:
/// - chevron rotates 0° → 90° on expand (`AnimatedRotation`, 240ms);
/// - body cross-fades + slides down 4 px (`AnimatedSwitcher`, 240ms);
/// - height changes ride a single `AnimatedSize` curve (240ms easeOutCubic).
///
/// Adopt this widget anywhere a boolean drives a "show extra detail"
/// panel — replaces the typical:
/// ```
/// Column(children: [
///   Row(/* header with conditional chevron */),
///   if (expanded) detail,
/// ])
/// ```
/// with smooth animation, no allocation in the steady-state path.
class AnimatedExpandable extends StatelessWidget {
  const AnimatedExpandable({
    super.key,
    required this.expanded,
    required this.header,
    required this.body,
    this.duration = const Duration(milliseconds: 240),
    this.alignment = Alignment.topLeft,
    this.bodyTopPadding = 12.0,
  });

  final bool expanded;

  /// Header row drawn above the body. Should typically include a tap
  /// target wired to your toggle callback. The chevron is *not* added
  /// automatically — callers wishing to use one should compose their
  /// own `AnimatedRotation(turns: expanded ? 0.25 : 0, ...)` before the
  /// label so they keep full control of icon, color, and size.
  final Widget header;

  /// Detail body shown only when `expanded` is true. Built lazily inside
  /// an `AnimatedSwitcher` so callers don't pay for it while collapsed.
  final WidgetBuilder body;

  final Duration duration;
  final AlignmentGeometry alignment;
  final double bodyTopPadding;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration;
    return AnimatedSize(
      duration: effectiveDuration,
      curve: Curves.easeOutCubic,
      alignment: alignment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          AnimatedSwitcher(
            duration: effectiveDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            ),
            child: expanded
                ? Padding(
                    key: const ValueKey<String>('expanded'),
                    padding: EdgeInsets.only(top: bodyTopPadding),
                    child: Builder(builder: body),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('collapsed'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A small chevron that rotates 0 → 90° as `expanded` flips, matching
/// the rest of the app's expand/collapse motion language. Drop into a
/// header row alongside a label.
class AnimatedExpandChevron extends StatelessWidget {
  const AnimatedExpandChevron({
    super.key,
    required this.expanded,
    this.size = 18,
    this.color,
    this.duration = const Duration(milliseconds: 240),
  });

  final bool expanded;
  final double size;
  final Color? color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.25 : 0.0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      curve: Curves.easeOutCubic,
      child: Icon(
        Icons.keyboard_arrow_right_rounded,
        size: size,
        color: color,
      ),
    );
  }
}

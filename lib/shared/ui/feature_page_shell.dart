import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'highlight_pulse.dart';
import 'motion_preference.dart';

class FeaturePageShell extends StatelessWidget {
  const FeaturePageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.body,
    this.successSignal,
    this.notices = const <Widget>[],
    this.animateBody = true,
    this.breakpoint = 980,
    this.headerSpacing = 20,
    this.noticeSpacing = 16,
  });

  final String title;
  final String subtitle;
  final Widget actions;
  final Widget body;
  final ValueListenable<int>? successSignal;
  final List<Widget> notices;
  final bool animateBody;
  final double breakpoint;
  final double headerSpacing;
  final double noticeSpacing;

  @override
  Widget build(BuildContext context) {
    final bodyWidget = Expanded(
      child: animateBody
          ? AnimatedSwitcher(
              duration: openHandMotionDuration(
                context,
                const Duration(milliseconds: 220),
              ),
              child: body,
            )
          : body,
    );

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < breakpoint;
                final header = FeaturePageHeader(
                  title: title,
                  subtitle: subtitle,
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      SizedBox(height: headerSpacing),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 20),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: actions,
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: headerSpacing),
            AnimatedSwitcher(
              duration: openHandMotionDuration(
                context,
                const Duration(milliseconds: 300),
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                );
              },
              child: notices.isEmpty
                  ? const SizedBox.shrink(key: ValueKey('feature-notices-empty'))
                  : Column(
                      key: const ValueKey('feature-notices-list'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final notice in notices) ...<Widget>[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: notice,
                            ),
                          ),
                          SizedBox(height: noticeSpacing),
                        ],
                      ],
                    ),
            ),
            bodyWidget,
          ],
        ),
        if (successSignal != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(child: HighlightPulse(signal: successSignal!)),
          ),
      ],
    );
  }
}

class FeaturePageHeader extends StatelessWidget {
  const FeaturePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'highlight_pulse.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_reveal_switcher.dart';

const Duration _bodyRevealDuration = kOpenHandMotion220;
const Duration _noticesRevealDuration = Duration(milliseconds: 300);

class FeaturePageShell extends StatelessWidget {
  const FeaturePageShell({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
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
  final Widget? actions;
  final Widget body;
  final ValueListenable<int>? successSignal;
  final List<Widget> notices;
  final bool animateBody;
  final double breakpoint;
  final double headerSpacing;
  final double noticeSpacing;

  @override
  Widget build(BuildContext context) {
    final motionEnabled = openHandTickerMotionEnabled(context);
    final bodyWidget = Expanded(
      child: animateBody && motionEnabled
          ? AnimatedSwitcher(
              duration: openHandMotionDuration(context, _bodyRevealDuration),
              child: body,
            )
          : body,
    );
    final noticesWidget = OpenHandVerticalRevealSwitcher(
      duration: _noticesRevealDuration,
      slideBeginOffsetY: -0.08,
      child: _buildNoticeContent(),
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
                final actions = this.actions;
                if (actions == null) return header;
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
                    kOpenHandHGap20,
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
            noticesWidget,
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

  Widget _buildNoticeContent() {
    if (notices.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('feature-notices-empty'));
    }
    return Column(
      key: const ValueKey('feature-notices-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final notice in notices) ...<Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
              child: notice,
            ),
          ),
          SizedBox(height: noticeSpacing),
        ],
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
        kOpenHandGap8,
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

class FeaturePageToolbar extends StatelessWidget {
  const FeaturePageToolbar({
    super.key,
    required this.primaryActions,
    this.secondaryActions = const <Widget>[],
    this.spacing = 8,
  });

  final List<Widget> primaryActions;
  final List<Widget> secondaryActions;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _FeaturePageToolbarRow(actions: primaryActions, spacing: spacing),
        if (secondaryActions.isNotEmpty) ...[
          SizedBox(height: spacing),
          _FeaturePageToolbarRow(actions: secondaryActions, spacing: spacing),
        ],
      ],
    );
  }
}

class FeaturePageToolbarIconButton extends StatelessWidget {
  const FeaturePageToolbarIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 40,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ),
    );
  }
}

class _FeaturePageToolbarRow extends StatelessWidget {
  const _FeaturePageToolbarRow({required this.actions, required this.spacing});

  final List<Widget> actions;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) SizedBox(width: spacing),
            actions[index],
          ],
        ],
      ),
    );
  }
}

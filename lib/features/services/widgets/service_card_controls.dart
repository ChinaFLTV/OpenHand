import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';

const double _serviceCardIconExtent = 64;

class ServiceCardIdentity extends StatelessWidget {
  const ServiceCardIdentity({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.running,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _serviceCardIconExtent,
              height: _serviceCardIconExtent,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: kOpenHandBorderRadius18,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 31, color: colors.onPrimaryContainer),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.circle,
                  color: running
                      ? OpenHandStatusColors.success
                      : colors.outline,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        kOpenHandHGap16,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              kOpenHandGap8,
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ServiceCardToggleButton extends StatelessWidget {
  const ServiceCardToggleButton({
    super.key,
    required this.running,
    required this.busy,
    required this.onToggle,
    required this.startTooltip,
    required this.stopTooltip,
  });

  final bool running;
  final bool busy;
  final VoidCallback onToggle;
  final String startTooltip;
  final String stopTooltip;

  @override
  Widget build(BuildContext context) {
    const shape = WidgetStatePropertyAll<OutlinedBorder>(CircleBorder());
    return Tooltip(
      message: running ? stopTooltip : startTooltip,
      child: IconButton.filledTonal(
        onPressed: busy ? null : onToggle,
        style: running
            ? OpenHandStatusColors.runningStopButtonStyle().copyWith(
                shape: shape,
              )
            : IconButton.styleFrom(shape: const CircleBorder()),
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}

class ServiceCardActions extends StatelessWidget {
  const ServiceCardActions({
    super.key,
    required this.running,
    required this.busy,
    required this.onToggle,
    required this.actions,
  });

  final bool running;
  final bool busy;
  final VoidCallback onToggle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        ServiceCardToggleButton(
          running: running,
          busy: busy,
          onToggle: onToggle,
          startTooltip: text(zh: '启动服务', en: 'Start service'),
          stopTooltip: text(zh: '停止服务', en: 'Stop service'),
        ),
        ...actions,
      ],
    );
  }
}

class ServiceCardIconAction extends StatelessWidget {
  const ServiceCardIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(shape: const CircleBorder()),
    ),
  );
}

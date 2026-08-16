part of '../openhand_home_page.dart';

const Color _kHomeSidebarAmber = Color(0xFFE6A817);

const Duration _kHomeSidebarTileMotionDuration = kOpenHandMotion220;
const Duration _kHomeSidebarPulseDuration = Duration(milliseconds: 1200);
const Curve _kHomeSidebarTileMotionCurve = Curves.easeOutCubic;

Future<void> _showSidebarThreadContextMenu(
  BuildContext context,
  TapDownDetails details, {
  required VoidCallback onRename,
  required VoidCallback onDelete,
  required VoidCallback onExport,
  VoidCallback? onGenerateTitle,
  VoidCallback? onTrajectory,
}) async {
  final selected = await showAnimatedMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      details.globalPosition.dx,
      details.globalPosition.dy,
      details.globalPosition.dx,
      details.globalPosition.dy,
    ),
    items: [
      PopupMenuItem<String>(
        value: 'rename',
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, size: 18),
            kOpenHandHGap8,
            Text(_homeRenameThreadLabel(context)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        child: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, size: 18),
            kOpenHandHGap8,
            Text(AppLocalizations.of(context)!.commonDelete),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'export',
        child: Row(
          children: [
            const Icon(Icons.file_download_outlined, size: 18),
            kOpenHandHGap8,
            Text(_homeExportSessionDataLabel(context)),
          ],
        ),
      ),
      if (onGenerateTitle != null)
        PopupMenuItem<String>(
          value: 'generate_title',
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 18),
              kOpenHandHGap8,
              Text(openHandGenerateAiTitleLabel(context)),
            ],
          ),
        ),
      if (onTrajectory != null)
        PopupMenuItem<String>(
          value: 'trajectory',
          child: Row(
            children: [
              const Icon(Icons.route_outlined, size: 18),
              kOpenHandHGap8,
              Text(openHandTrajectoryLabel(context)),
            ],
          ),
        ),
    ],
  );
  if (!context.mounted) return;
  final action = switch (selected) {
    'rename' => onRename,
    'delete' => onDelete,
    'export' => onExport,
    'generate_title' => onGenerateTitle,
    'trajectory' => onTrajectory,
    _ => null,
  };
  action?.call();
}

class _HarnessSessionTile extends StatelessWidget {
  const _HarnessSessionTile({
    required this.title,
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onExport,
  });

  final String title;
  final HarnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final iconColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final showBadge =
        awaitingApproval ||
        (status != HarnessOrchestratorStatus.idle &&
            status != HarnessOrchestratorStatus.completed);
    final tileMotionDuration = openHandMotionDuration(
      context,
      _kHomeSidebarTileMotionDuration,
    );

    return GestureDetector(
      onSecondaryTapDown: (details) async {
        await _showSidebarThreadContextMenu(
          context,
          details,
          onRename: onRename,
          onDelete: onDelete,
          onExport: onExport,
        );
      },
      child: AnimatedContainer(
        duration: tileMotionDuration,
        curve: _kHomeSidebarTileMotionCurve,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: kOpenHandPillBorderRadius,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: kOpenHandPillBorderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: kOpenHandPillBorderRadius,
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
            splashColor: colorScheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: _kSidebarTileContentPadding,
              child: Row(
                children: [
                  Icon(
                    Icons.precision_manufacturing_outlined,
                    size: _kSidebarTileIconSize,
                    color: iconColor,
                  ),
                  const SizedBox(width: _kSidebarTileIconGap),
                  Expanded(
                    child: OpenHandAnimatedTitleText(
                      text: title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: titleColor,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (showBadge) ...[
                    kOpenHandHGap10,
                    _HarnessStatusCapsule(
                      status: status,
                      awaitingApproval: awaitingApproval,
                      isSelected: isSelected,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status badge for Harness Engineering sessions.
/// Uses the same [_SweepBadge] animation for the running state and a static
/// rounded capsule for terminal states — matching the [_ActiveThreadBadge]
/// pattern used for AI thread sessions.
class _HarnessStatusCapsule extends StatelessWidget {
  const _HarnessStatusCapsule({
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
  });

  final HarnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (awaitingApproval) {
      const foregroundColor = _kHomeSidebarAmber;
      final backgroundColor = foregroundColor.withValues(alpha: 0.14);
      final borderColor = foregroundColor.withValues(alpha: 0.22);
      return _SweepBadge(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        sweepColor: foregroundColor.withValues(alpha: 0.18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulsingDot(color: foregroundColor, size: 8),
            kOpenHandHGap8,
            Text(
              openHandAwaitingApprovalLabel(context),
              style: theme.textTheme.labelMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final (Color fg, String label) = switch (status) {
      HarnessOrchestratorStatus.running => (
        isSelected ? colorScheme.onPrimaryContainer : colorScheme.primary,
        openHandRunningLabel(context),
      ),
      HarnessOrchestratorStatus.completed => (
        const Color(0xFF5F7C53),
        openHandDoneLabel(context),
      ),
      HarnessOrchestratorStatus.failed => (
        const Color(0xFFC84B4B),
        openHandFailedLabel(context),
      ),
      HarnessOrchestratorStatus.cancelled => (
        const Color(0xFFD97A33),
        openHandLocalizedText(
          context,
          zh: '已中止',
          zhHant: '已中止',
          en: 'Cancelled',
          fr: 'Annulé',
          de: 'Abgebrochen',
          ja: 'キャンセル済み',
        ),
      ),
      HarnessOrchestratorStatus.idle => (colorScheme.outline, ''),
    };

    if (status == HarnessOrchestratorStatus.idle ||
        status == HarnessOrchestratorStatus.completed) {
      return const SizedBox.shrink();
    }

    final bg = fg.withValues(alpha: 0.12);
    final border = fg.withValues(alpha: 0.22);
    final labelWidget = Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: fg,
        fontWeight: FontWeight.w700,
      ),
    );

    if (status == HarnessOrchestratorStatus.running) {
      return _SweepBadge(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: bg,
        borderColor: border,
        sweepColor: fg.withValues(alpha: 0.18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            kOpenHandHGap8,
            labelWidget,
          ],
        ),
      );
    }

    // Static capsule for terminal states.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: border),
      ),
      child: labelWidget,
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.session,
    required this.sendPhase,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onExport,
    this.onGenerateTitle,
    this.onTrajectory,
  });

  final AiSession session;
  final AiSendPhase sendPhase;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback? onGenerateTitle;
  final VoidCallback? onTrajectory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 与上方系统导航胶囊统一：未选透明、选中 primaryContainer 全圆角，告别灰底卡片堆。
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final iconColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final templateIcon = AiThreadTemplateIcons.resolve(
      session.templateIconName,
    );
    final isActive = sendPhase != AiSendPhase.idle;
    final tileMotionDuration = openHandMotionDuration(
      context,
      _kHomeSidebarTileMotionDuration,
    );
    return GestureDetector(
      onSecondaryTapDown: (details) async {
        await _showSidebarThreadContextMenu(
          context,
          details,
          onRename: onRename,
          onDelete: onDelete,
          onExport: onExport,
          onGenerateTitle: onGenerateTitle,
          onTrajectory: onTrajectory,
        );
      },
      child: AnimatedContainer(
        duration: tileMotionDuration,
        curve: _kHomeSidebarTileMotionCurve,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: kOpenHandPillBorderRadius,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: kOpenHandPillBorderRadius,
          child: InkWell(
            borderRadius: kOpenHandPillBorderRadius,
            onTap: onTap,
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.04),
            splashColor: colorScheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: _kSidebarTileContentPadding,
              child: Row(
                children: [
                  Icon(
                    templateIcon,
                    size: _kSidebarTileIconSize,
                    color: iconColor,
                  ),
                  const SizedBox(width: _kSidebarTileIconGap),
                  Expanded(
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: titleColor),
                      duration: tileMotionDuration,
                      curve: _kHomeSidebarTileMotionCurve,
                      builder: (context, animatedColor, _) {
                        return OpenHandAnimatedTitleText(
                          text: session.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: animatedColor ?? titleColor,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            height: 1.25,
                          ),
                        );
                      },
                    ),
                  ),
                  if (isActive) ...[
                    kOpenHandHGap10,
                    _ActiveThreadBadge(
                      key: ValueKey<String>('thread-active-${session.id}'),
                      sendPhase: sendPhase,
                      isSelected: isSelected,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveThreadBadge extends StatelessWidget {
  const _ActiveThreadBadge({
    super.key,
    required this.sendPhase,
    required this.isSelected,
  });

  final AiSendPhase sendPhase;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isApprovalPhase = sendPhase == AiSendPhase.awaitingApproval;
    // Use an amber/warning palette for the approval state so it stands out
    // from the regular "active" badge and draws the user's attention.
    final foregroundColor = isApprovalPhase
        ? _kHomeSidebarAmber
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final backgroundColor = isApprovalPhase
        ? _kHomeSidebarAmber.withValues(alpha: 0.14)
        : isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.14)
        : colorScheme.primary.withValues(alpha: 0.12);
    final label = switch (sendPhase) {
      AiSendPhase.compressing => openHandLocalizedText(
        context,
        zh: '压缩中',
        en: 'Compressing',
      ),
      AiSendPhase.sendingMessage => openHandSendingLabel(context),
      AiSendPhase.responding => openHandActiveLabel(context),
      AiSendPhase.awaitingApproval => _homeAwaitingApprovalLabel(context),
      AiSendPhase.idle => '',
    };
    return _SweepBadge(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      backgroundColor: backgroundColor,
      borderColor: foregroundColor.withValues(alpha: 0.22),
      sweepColor: foregroundColor.withValues(alpha: 0.18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isApprovalPhase)
            _PulsingDot(color: foregroundColor, size: 8)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: foregroundColor,
                shape: BoxShape.circle,
              ),
            ),
          kOpenHandHGap8,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circle that pulses (fades in and out) to draw attention.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kHomeSidebarPulseDuration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled = openHandTickerMotionEnabled(context);
    if (!animationsEnabled) {
      _controller.stop();
      return _buildDot(1);
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
    // Bake the pulsing opacity into the BoxDecoration color. Wrapping the dot
    // in `Opacity` allocates a saveLayer, which is wasted overhead for a small
    // circle with no child to composite.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = (0.35 + _controller.value * 0.65).clamp(0.0, 1.0);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: opacity),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildDot(double opacity) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

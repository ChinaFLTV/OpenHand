part of '../openhand_home_page.dart';

class _HardnessSessionTile extends StatelessWidget {
  const _HardnessSessionTile({
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
  final HardnessOrchestratorStatus status;
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
        : colorScheme.surfaceContainerLow;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final showBadge =
        awaitingApproval ||
        (status != HardnessOrchestratorStatus.idle &&
            status != HardnessOrchestratorStatus.completed);

    return GestureDetector(
      onSecondaryTapDown: (details) async {
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
                  const SizedBox(width: 8),
                  Text(
                    _localizedText(context, zh: '重命名线程', en: 'Rename Thread'),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonDelete),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'export',
              child: Row(
                children: [
                  const Icon(Icons.file_download_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _localizedText(
                      context,
                      zh: '导出会话数据',
                      en: 'Export Session Data',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        if (!context.mounted || selected == null) {
          return;
        }
        final VoidCallback? action = switch (selected) {
          'rename' => onRename,
          'delete' => onDelete,
          'export' => onExport,
          _ => null,
        };
        if (action == null) {
          return;
        }
        _scheduleOverlayActionAfterMenuDismissal(context, action);
      },
      child: Material(
        color: backgroundColor,
        borderRadius: _borderRadius18,
        child: InkWell(
          onTap: onTap,
          borderRadius: _borderRadius18,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _AnimatedSessionTitleText(
                    text: title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                    ),
                  ),
                ),
                if (showBadge) ...[
                  const SizedBox(width: 12),
                  _HardnessStatusCapsule(
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
    );
  }
}

/// Status badge for Harness Engineering sessions.
/// Uses the same [_SweepBadge] animation for the running state and a static
/// rounded capsule for terminal states — matching the [_ActiveThreadBadge]
/// pattern used for AI thread sessions.
class _HardnessStatusCapsule extends StatelessWidget {
  const _HardnessStatusCapsule({
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
  });

  final HardnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (awaitingApproval) {
      const foregroundColor = Color(0xFFE6A817);
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
            const SizedBox(width: 8),
            Text(
              openHandLocalizedText(
                context,
                zh: '等待批准',
                zhHant: '等待批准',
                en: 'Awaiting Approval',
                fr: 'En attente',
                de: 'Wartet auf Freigabe',
                ja: '承認待ち',
              ),
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
      HardnessOrchestratorStatus.running => (
        isSelected ? colorScheme.onPrimaryContainer : colorScheme.primary,
        openHandLocalizedText(
          context,
          zh: '运行中',
          zhHant: '執行中',
          en: 'Running',
          fr: 'En cours',
          de: 'Läuft',
          ja: '実行中',
        ),
      ),
      HardnessOrchestratorStatus.completed => (
        const Color(0xFF5F7C53),
        openHandLocalizedText(
          context,
          zh: '已完成',
          zhHant: '已完成',
          en: 'Done',
          fr: 'Terminé',
          de: 'Fertig',
          ja: '完了',
        ),
      ),
      HardnessOrchestratorStatus.failed => (
        const Color(0xFFC84B4B),
        openHandLocalizedText(
          context,
          zh: '失败',
          zhHant: '失敗',
          en: 'Failed',
          fr: 'Échec',
          de: 'Fehlgeschlagen',
          ja: '失敗',
        ),
      ),
      HardnessOrchestratorStatus.cancelled => (
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
      HardnessOrchestratorStatus.idle => (colorScheme.outline, ''),
    };

    if (status == HardnessOrchestratorStatus.idle ||
        status == HardnessOrchestratorStatus.completed) {
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

    if (status == HardnessOrchestratorStatus.running) {
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
            const SizedBox(width: 8),
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
        borderRadius: _borderRadius999,
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
  });

  final AiSession session;
  final AiSendPhase sendPhase;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback? onGenerateTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final isActive = sendPhase != AiSendPhase.idle;
    return GestureDetector(
      onSecondaryTapDown: (details) async {
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
                  const SizedBox(width: 8),
                  Text(
                    _localizedText(context, zh: '重命名线程', en: 'Rename Thread'),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonDelete),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'export',
              child: Row(
                children: [
                  const Icon(Icons.file_download_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _localizedText(
                      context,
                      zh: '导出会话数据',
                      en: 'Export Session Data',
                    ),
                  ),
                ],
              ),
            ),
            if (onGenerateTitle != null)
              PopupMenuItem<String>(
                value: 'generate_title',
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _localizedText(
                        context,
                        zh: '获取 AI 摘要标题',
                        en: 'Generate AI Title',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
        if (!context.mounted || selected == null) {
          return;
        }
        final VoidCallback? action = switch (selected) {
          'rename' => onRename,
          'delete' => onDelete,
          'export' => onExport,
          'generate_title' => onGenerateTitle,
          _ => null,
        };
        if (action == null) {
          return;
        }
        _scheduleOverlayActionAfterMenuDismissal(context, action);
      },
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: _borderRadius18,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: _borderRadius18,
          child: InkWell(
            borderRadius: _borderRadius18,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: titleColor),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedColor, _) {
                        return _AnimatedSessionTitleText(
                          text: session.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: animatedColor ?? titleColor,
                          ),
                        );
                      },
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 12),
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
        ? const Color(0xFFE6A817)
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final backgroundColor = isApprovalPhase
        ? const Color(0xFFE6A817).withValues(alpha: 0.14)
        : isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.14)
        : colorScheme.primary.withValues(alpha: 0.12);
    final label = switch (sendPhase) {
      AiSendPhase.compressing => _localizedText(
        context,
        zh: '压缩中',
        en: 'Compressing',
      ),
      AiSendPhase.sendingMessage => _localizedText(
        context,
        zh: '发送中',
        en: 'Sending',
      ),
      AiSendPhase.responding => _localizedText(
        context,
        zh: '进行中',
        en: 'Active',
      ),
      AiSendPhase.awaitingApproval => _localizedText(
        context,
        zh: '等待批准',
        en: 'Awaiting Approval',
      ),
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
          const SizedBox(width: 8),
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
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
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

part of 'hardness_session_dashboard.dart';

class _HePhaseCardEntrance extends StatefulWidget {
  const _HePhaseCardEntrance({required this.child});

  final Widget child;

  @override
  State<_HePhaseCardEntrance> createState() => _HePhaseCardEntranceState();
}

class _HePhaseCardEntranceState extends State<_HePhaseCardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    // Opacity: linear 0→1 in the first 60 % of the animation.
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOut),
      ),
    );
    // Scale: 0.94→1.0 with an elastic overshoot — the Q弹 feel.
    _scale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    // Slide: starts 18 px below its final position and rises to 0.
    _slide = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.topCenter,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

// =============================================================================
// Phase card — mirrors an AI tool-call execution card (_MessageBubble w/
// isToolCall = true):
//   • secondaryContainer bg + secondary border  → running
//   • errorContainer bg + error border          → failed
//   • surfaceContainerHighest + light border    → completed
//   • surfaceContainerLow + light border        → pending / skipped
// =============================================================================

class _HePhaseCard extends StatefulWidget {
  const _HePhaseCard({
    super.key,
    required this.log,
    required this.config,
    required this.isZh,
    required this.expanded,
    required this.onToggleExpand,
    required this.onCopyLog,
    this.onRoleConfigChanged,
    this.filePathRoots = const [],
  });

  final HardnessPhaseLog log;
  final HardnessSessionConfig config;
  final bool isZh;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCopyLog;

  /// If non-null, the phase is pending and the user can change its CLI/model.
  final ValueChanged<HardnessRoleConfig>? onRoleConfigChanged;

  /// Root directories for file path resolution.
  final List<String> filePathRoots;

  @override
  State<_HePhaseCard> createState() => _HePhaseCardState();
}

class _HePhaseCardState extends State<_HePhaseCard> {
  static const _expandSwitchDuration = Duration(milliseconds: 280);

  @override
  void didUpdateWidget(covariant _HePhaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  String _collapsedPreviewLine(List<String> lines) {
    return lines.lastWhere((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      if (trimmed.startsWith('✓ ') ||
          trimmed.startsWith('✗ ') ||
          trimmed.startsWith('▶ ') ||
          trimmed.startsWith('⚠ ') ||
          trimmed.startsWith('ℹ ')) {
        return false;
      }
      if (trimmed.startsWith('【') && trimmed.endsWith('】')) {
        return false;
      }
      return true;
    }, orElse: () => '');
  }

  /// Returns the HardnessRoleConfig that drives this phase.
  /// Mirrors HardnessOrchestrator._roleConfigForPhase.
  HardnessRoleConfig _roleConfig() {
    final c = widget.config;
    return switch (widget.log.phase) {
      HardnessPhase.metaCollection => c.profilerConfig,
      HardnessPhase.reading => c.readerConfig,
      HardnessPhase.planning => c.plannerConfig,
      HardnessPhase.implementing => c.implementerConfig,
      HardnessPhase.reviewing => c.reviewerConfig,
    };
  }

  static const Map<HardnessPhase, IconData> _phaseIcons = {
    HardnessPhase.metaCollection: Icons.manage_search_rounded,
    HardnessPhase.reading: Icons.menu_book_rounded,
    HardnessPhase.planning: Icons.route_rounded,
    HardnessPhase.implementing: Icons.code_rounded,
    HardnessPhase.reviewing: Icons.fact_check_rounded,
  };

  IconData get _statusIcon {
    // Completed reviewing phases with FAIL verdict use a warning icon.
    if (widget.log.status == HardnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return Icons.unpublished_rounded;
    }
    return switch (widget.log.status) {
      HardnessPhaseStatus.pending => Icons.radio_button_unchecked_rounded,
      HardnessPhaseStatus.paused => Icons.pause_circle_filled_rounded,
      HardnessPhaseStatus.running => Icons.play_circle_outline_rounded,
      HardnessPhaseStatus.completed => Icons.check_circle_rounded,
      HardnessPhaseStatus.failed => Icons.error_rounded,
      HardnessPhaseStatus.cancelled => Icons.cancel_rounded,
      HardnessPhaseStatus.skipped => Icons.remove_circle_outline_rounded,
    };
  }

  String _statusText() {
    final isZh = widget.isZh;
    // Completed reviewing phases with FAIL verdict show distinct text.
    if (widget.log.status == HardnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return isZh ? '验收未通过' : 'Review Failed';
    }
    return switch (widget.log.status) {
      HardnessPhaseStatus.pending => isZh ? '等待中' : 'Pending',
      HardnessPhaseStatus.paused => isZh ? '暂停中' : 'Paused',
      HardnessPhaseStatus.running => isZh ? '运行中' : 'Running',
      HardnessPhaseStatus.completed => isZh ? '执行完成' : 'Completed',
      HardnessPhaseStatus.failed => isZh ? '执行失败' : 'Failed',
      HardnessPhaseStatus.cancelled => isZh ? '执行中止' : 'Cancelled',
      HardnessPhaseStatus.skipped => isZh ? '已跳过' : 'Skipped',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final log = widget.log;
    final isZh = widget.isZh;
    // `context.select` so this card only rebuilds when the cached `aiModels`
    // reference actually changes, not on every unrelated SettingsController
    // notification (theme tweaks, animation settings, hardness toggles…).
    final aiModels = context.select<SettingsController?, List<AiModelConfig>>(
      (controller) => controller?.aiModels ?? const <AiModelConfig>[],
    );

    final isRunning = log.status == HardnessPhaseStatus.running;
    final isPaused = log.status == HardnessPhaseStatus.paused;
    final isFailed = log.status == HardnessPhaseStatus.failed;
    final isCancelled = log.status == HardnessPhaseStatus.cancelled;
    final palette = _hePhasePalette(
      theme,
      colorScheme,
      log.status,
      reviewVerdictFail: log.reviewVerdictFail,
    );
    final backgroundColor = palette.background;
    final borderColor = palette.border;
    final textColor = palette.text;

    final phaseIcon = _phaseIcons[log.phase] ?? Icons.timelapse_rounded;
    final phaseName = isZh ? log.phase.displayNameZh : log.phase.displayNameEn;
    final roleConfig = _roleConfig();
    final collapsedPreviewLine = _collapsedPreviewLine(log.lines);

    // Animate color & border transitions when status changes (e.g. pending →
    // running → completed). AnimatedContainer handles backgroundColor and
    // borderColor interpolation automatically.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: _br26,
        border: Border.all(
          color: borderColor,
          width: (isRunning || isFailed || isPaused || isCancelled) ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header pill (mirrors _ToolCallMetaRow) ───────────────
            _HePhaseMetaRow(
              log: log,
              phaseName: phaseName,
              phaseIcon: phaseIcon,
              statusText: _statusText(),
              statusIcon: _statusIcon,
              textColor: textColor,
              expanded: widget.expanded,
              onToggle: widget.onToggleExpand,
            ),

            // ── Info chips (mirrors _ToolCallBody chip Wrap) ──────────────
            if (roleConfig.isUrlMode ||
                roleConfig.cliName.isNotEmpty ||
                roleConfig.modelId.isNotEmpty ||
                log.exitCode != null ||
                log.savedLogPath != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (roleConfig.isUrlMode)
                    const _HeChip(icon: Icons.cloud_rounded, label: 'URL/API'),
                  if (!roleConfig.isUrlMode && roleConfig.cliName.isNotEmpty)
                    _HeChip(
                      icon: Icons.terminal_rounded,
                      label: roleConfig.cliName,
                    ),
                  if (roleConfig.isUrlMode &&
                      (roleConfig.aiModelConfigId?.trim().isNotEmpty ?? false))
                    _HeChip(
                      icon: Icons.layers_rounded,
                      label: _heDescribeAiModelConfig(
                        aiModels,
                        roleConfig.aiModelConfigId,
                        isZh: isZh,
                        urlModeModelId: roleConfig.urlModeModelId,
                      ),
                    ),
                  if (!roleConfig.isUrlMode && roleConfig.modelId.isNotEmpty)
                    _HeChip(
                      icon: Icons.layers_rounded,
                      label: describeHardnessCliModel(
                        findHardnessCliByName(roleConfig.cliName),
                        roleConfig.modelId,
                        isZh: isZh,
                      ),
                    ),
                  if (log.exitCode != null)
                    _HeChip(
                      icon: log.exitCode == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.flag_outlined,
                      label: '${isZh ? '退出码' : 'Exit'}: ${log.exitCode}',
                    ),
                  if (log.savedLogPath != null)
                    _HeChip(
                      icon: Icons.save_outlined,
                      label: isZh ? '已保存日志' : 'Log saved',
                    ),
                  if (log.changedFiles.isNotEmpty)
                    _HeChip(
                      icon: Icons.difference_rounded,
                      label:
                          '${log.changedFiles.length} ${isZh ? '个文件变动' : 'files changed'}',
                    ),
                ],
              ),
            ],

            // ── Edit CLI/model for retryable and not-yet-executed phases ───
            if (widget.onRoleConfigChanged != null) ...[
              const SizedBox(height: 10),
              _HePendingPhaseEditor(
                roleConfig: roleConfig,
                isZh: isZh,
                onChanged: widget.onRoleConfigChanged!,
              ),
            ],

            AnimatedSwitcher(
              duration: _expandSwitchDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final fade = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                final slide = Tween<Offset>(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(fade);
                final scale = Tween<double>(begin: 0.985, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                );
                return ClipRect(
                  child: FadeTransition(
                    opacity: fade,
                    child: SizeTransition(
                      sizeFactor: fade,
                      axisAlignment: -1,
                      child: SlideTransition(
                        position: slide,
                        child: ScaleTransition(
                          scale: scale,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: widget.expanded
                  ? KeyedSubtree(
                      key: ValueKey<String>(
                        'he-phase-expanded-${log.phase.name}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _HePhaseExpandedBody(
                          log: log,
                          isZh: isZh,
                          onCopyLog: widget.onCopyLog,
                          filePathRoots: widget.filePathRoots,
                        ),
                      ),
                    )
                  : collapsedPreviewLine.isNotEmpty
                  ? KeyedSubtree(
                      key: ValueKey<String>(
                        'he-phase-collapsed-${log.phase.name}',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          collapsedPreviewLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: textColor.withValues(alpha: 0.60),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey<String>('he-phase-collapsed-empty'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HePhaseExpandedBody extends StatelessWidget {
  const _HePhaseExpandedBody({
    required this.log,
    required this.isZh,
    required this.onCopyLog,
    this.filePathRoots = const [],
  });

  final HardnessPhaseLog log;
  final bool isZh;
  final VoidCallback onCopyLog;
  final List<String> filePathRoots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFailed = log.status == HardnessPhaseStatus.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeLogSection(
          log: log,
          isZh: isZh,
          onCopy: onCopyLog,
          filePathRoots: filePathRoots,
        ),
        if (log.changedFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          _HeChangedFilesList(files: log.changedFiles, isZh: isZh),
        ],
        if (isFailed) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isZh
                      ? '本阶段执行失败，请检查上方日志以了解详情。'
                      : 'This phase failed. Review the log above for details.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// _HePhaseActionBar — action buttons shown below a selected phase card,
// matching the _MessageActionButton pattern from AI thread messages.
// =============================================================================

class _HePhaseActionBar extends StatelessWidget {
  const _HePhaseActionBar({
    required this.isZh,
    required this.onCopyLog,
    required this.onReExecute,
    required this.onDelete,
  });

  final bool isZh;
  final VoidCallback onCopyLog;
  final VoidCallback onReExecute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onCopyLog,
          style: buttonStyle,
          icon: const Icon(Icons.content_copy_outlined, size: 16),
          label: Text(isZh ? '复制' : 'Copy'),
        ),
        OutlinedButton.icon(
          onPressed: onReExecute,
          style: buttonStyle,
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: Text(isZh ? '重新执行' : 'Re-execute'),
        ),
        OutlinedButton.icon(
          onPressed: onDelete,
          style: buttonStyle,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: Text(isZh ? '删除' : 'Delete'),
        ),
      ],
    );
  }
}

// =============================================================================
// Sweep-shimmer pill — replicates _SweepBadge from openhand_home_page for use
// inside the hardness dashboard without introducing a cross-feature import.
// Plays a left-to-right grey shimmer on loop while a phase is running.
// =============================================================================

class _HeSweepPill extends StatefulWidget {
  const _HeSweepPill({
    required this.child,
    required this.backgroundColor,
    required this.sweepColor,
  });

  final Widget child;
  final Color backgroundColor;
  final Color sweepColor;

  @override
  State<_HeSweepPill> createState() => _HeSweepPillState();
}

class _HeSweepPillState extends State<_HeSweepPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const br = BorderRadius.all(Radius.circular(999));
    return ClipRRect(
      borderRadius: br,
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          final start = -1.8 + (_ctrl.value * 2.8);
          final end = start + 0.9;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: br,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(start, 0),
                        end: Alignment(end, 0),
                        colors: [
                          Colors.transparent,
                          widget.sweepColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Phase card header pill — mirrors _ToolCallMetaRow
// =============================================================================

class _HePhaseMetaRow extends StatelessWidget {
  const _HePhaseMetaRow({
    required this.log,
    required this.phaseName,
    required this.phaseIcon,
    required this.statusText,
    required this.statusIcon,
    required this.textColor,
    required this.expanded,
    required this.onToggle,
  });

  final HardnessPhaseLog log;
  final String phaseName;
  final IconData phaseIcon;
  final String statusText;
  final IconData statusIcon;
  final Color textColor;
  final bool expanded;
  final VoidCallback onToggle;

  bool get _isRunning => log.status == HardnessPhaseStatus.running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Status-icon indicator with AnimatedSwitcher — transitions smoothly when
    // the phase status changes (pending → running → completed).
    // While running the icon position is kept empty; the sweep animation on
    // the pill itself already signals activity.
    final statusIndicator = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        key: ValueKey<HardnessPhaseStatus>(log.status),
        width: 16,
        height: 16,
        // Running state: no spinner — the pill sweep conveys activity.
        child: _isRunning
            ? null
            : Icon(
                statusIcon,
                size: 16,
                color: textColor.withValues(alpha: 0.88),
              ),
      ),
    );

    final pillInnerContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusIndicator,
          // Add spacing only when the icon slot is occupied (non-running).
          if (!_isRunning) const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$phaseName · $statusText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: textColor.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: textColor.withValues(alpha: 0.72),
              size: 18,
            ),
          ),
        ],
      ),
    );

    // When running: wrap the pill in the sweep-shimmer overlay.
    // When idle/done: use a plain container (no animation overhead).
    final pillBackground = Colors.black.withValues(alpha: 0.08);
    final pillDecoratedChild = _isRunning
        ? _HeSweepPill(
            backgroundColor: pillBackground,
            sweepColor: textColor.withValues(alpha: 0.14),
            child: pillInnerContent,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: pillBackground,
              borderRadius: _br999,
            ),
            child: pillInnerContent,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: _br999,
        overlayColor: WidgetStatePropertyAll<Color>(
          textColor.withValues(alpha: 0.06),
        ),
        child: pillDecoratedChild,
      ),
    );
  }
}

// =============================================================================
// _HeLogSection — smart log panel
//
// • Running phase  → live monospace tail (last 50 lines, auto-scroll)
// • Done phase     → "Smart" view (default): extracted command chip +
//                    full Markdown-rendered content
//                    "Raw" toggle: classic coloured monospace
// =============================================================================


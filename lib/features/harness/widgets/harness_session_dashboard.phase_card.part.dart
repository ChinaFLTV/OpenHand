part of 'harness_session_dashboard.dart';

class _HePhaseCardEntrance extends StatelessWidget {
  const _HePhaseCardEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OpenHandSpringEntrance(
      duration: kOpenHandMotion520,
      opacityIntervalEnd: 0.60,
      slideBegin: const Offset(0.0, 0.06),
      child: child,
    );
  }
}

// 阶段卡片沿用工具调用卡片的运行、失败、完成和等待状态色。
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

  final HarnessPhaseLog log;
  final HarnessSessionConfig config;
  final bool isZh;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCopyLog;

  /// 非空时允许用户修改等待阶段的 CLI 和模型。
  final ValueChanged<HarnessRoleConfig>? onRoleConfigChanged;

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

  /// Returns the HarnessRoleConfig that drives this phase.
  /// Mirrors HarnessOrchestrator._roleConfigForPhase.
  HarnessRoleConfig _roleConfig() {
    final c = widget.config;
    return switch (widget.log.phase) {
      HarnessPhase.metaCollection => c.profilerConfig,
      HarnessPhase.reading => c.readerConfig,
      HarnessPhase.planning => c.plannerConfig,
      HarnessPhase.implementing => c.implementerConfig,
      HarnessPhase.reviewing => c.reviewerConfig,
    };
  }

  static const Map<HarnessPhase, IconData> _phaseIcons = {
    HarnessPhase.metaCollection: Icons.manage_search_rounded,
    HarnessPhase.reading: Icons.menu_book_rounded,
    HarnessPhase.planning: Icons.route_rounded,
    HarnessPhase.implementing: Icons.code_rounded,
    HarnessPhase.reviewing: Icons.fact_check_rounded,
  };

  IconData get _statusIcon {
    // Completed reviewing phases with FAIL verdict use a warning icon.
    if (widget.log.status == HarnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return Icons.unpublished_rounded;
    }
    return switch (widget.log.status) {
      HarnessPhaseStatus.pending => Icons.radio_button_unchecked_rounded,
      HarnessPhaseStatus.paused => Icons.pause_circle_filled_rounded,
      HarnessPhaseStatus.running => Icons.play_circle_outline_rounded,
      HarnessPhaseStatus.completed => Icons.check_circle_rounded,
      HarnessPhaseStatus.failed => Icons.error_rounded,
      HarnessPhaseStatus.cancelled => Icons.cancel_rounded,
      HarnessPhaseStatus.skipped => Icons.remove_circle_outline_rounded,
    };
  }

  String _statusText(BuildContext context) {
    // Completed reviewing phases with FAIL verdict show distinct text.
    if (widget.log.status == HarnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return openHandLocalizedText(
        context,
        zh: '验收未通过',
        zhHant: '驗收未通過',
        en: 'Review Failed',
        fr: 'Revue échouée',
        de: 'Prüfung fehlgeschlagen',
        ja: 'レビュー不合格',
      );
    }
    return harnessPhaseStatusLabel(context, widget.log.status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final log = widget.log;
    final isZh = widget.isZh;
    // `context.select` so this card only rebuilds when the cached `aiModels`
    // reference actually changes, not on every unrelated SettingsController
    // notification (theme tweaks, animation settings, harness toggles…).
    final aiModels = context.select<SettingsController?, List<AiModelConfig>>(
      (controller) => controller?.aiModels ?? const <AiModelConfig>[],
    );

    final isRunning = log.status == HarnessPhaseStatus.running;
    final isPaused = log.status == HarnessPhaseStatus.paused;
    final isFailed = log.status == HarnessPhaseStatus.failed;
    final isCancelled = log.status == HarnessPhaseStatus.cancelled;
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
    final phaseName = _heHarnessPhaseLabel(context, log.phase);
    final roleConfig = _roleConfig();
    final collapsedPreviewLine = _collapsedPreviewLine(log.lines);
    final exitCodeLabel = openHandLocalizedText(
      context,
      zh: '退出码',
      zhHant: '結束碼',
      en: 'Exit',
      fr: 'Code de sortie',
      de: 'Exit-Code',
      ja: '終了コード',
    );

    // Animate color & border transitions when status changes (e.g. pending →
    // running → completed). AnimatedContainer handles backgroundColor and
    // borderColor interpolation automatically.
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion380),
      curve: kOpenHandSwitchInCurve,
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
              statusText: _statusText(context),
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
              kOpenHandGap10,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (roleConfig.isUrlMode)
                    const OpenHandToolChip(
                      icon: Icons.cloud_rounded,
                      label: 'URL/API',
                    ),
                  if (!roleConfig.isUrlMode && roleConfig.cliName.isNotEmpty)
                    OpenHandToolChip(
                      icon: Icons.terminal_rounded,
                      label: roleConfig.cliName,
                    ),
                  if (roleConfig.isUrlMode &&
                      (roleConfig.aiModelConfigId?.trim().isNotEmpty ?? false))
                    OpenHandToolChip(
                      icon: Icons.layers_rounded,
                      label: _heDescribeAiModelConfig(
                        context,
                        aiModels,
                        roleConfig.aiModelConfigId,
                        urlModeModelId: roleConfig.urlModeModelId,
                      ),
                    ),
                  if (!roleConfig.isUrlMode && roleConfig.modelId.isNotEmpty)
                    OpenHandToolChip(
                      icon: Icons.layers_rounded,
                      label: describeHarnessCliModel(
                        roleConfig.modelId,
                        locale: Localizations.localeOf(context),
                      ),
                    ),
                  if (log.exitCode != null)
                    OpenHandToolChip(
                      icon: log.exitCode == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.flag_outlined,
                      label: '$exitCodeLabel: ${log.exitCode}',
                    ),
                  if (log.savedLogPath != null)
                    OpenHandToolChip(
                      icon: Icons.save_outlined,
                      label: openHandLocalizedText(
                        context,
                        zh: '已保存日志',
                        zhHant: '已儲存日誌',
                        en: 'Log saved',
                        fr: 'Journal enregistré',
                        de: 'Log gespeichert',
                        ja: 'ログ保存済み',
                      ),
                    ),
                  if (log.changedFiles.isNotEmpty)
                    OpenHandToolChip(
                      icon: Icons.difference_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '${log.changedFiles.length} 个文件变动',
                        zhHant: '${log.changedFiles.length} 個檔案變更',
                        en: '${log.changedFiles.length} files changed',
                        fr: '${log.changedFiles.length} fichiers modifiés',
                        de: '${log.changedFiles.length} Dateien geändert',
                        ja: '${log.changedFiles.length} 件のファイル変更',
                      ),
                    ),
                ],
              ),
            ],

            // ── Edit CLI/model for retryable and not-yet-executed phases ───
            if (widget.onRoleConfigChanged != null) ...[
              kOpenHandGap10,
              _HePendingPhaseEditor(
                roleConfig: roleConfig,
                onChanged: widget.onRoleConfigChanged!,
              ),
            ],

            AnimatedSwitcher(
              duration: openHandMotionDuration(context, _expandSwitchDuration),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
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
                  curve: kOpenHandSwitchInCurve,
                  reverseCurve: kOpenHandSwitchOutCurve,
                );
                final slide = Tween<Offset>(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(fade);
                final scale = Tween<double>(begin: 0.985, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: kOpenHandSwitchInCurve,
                    reverseCurve: kOpenHandSwitchOutCurve,
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
                            fontFamily: kOpenHandMonospaceFontFamily,
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

  final HarnessPhaseLog log;
  final bool isZh;
  final VoidCallback onCopyLog;
  final List<String> filePathRoots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFailed = log.status == HarnessPhaseStatus.failed;

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
          kOpenHandGap12,
          _HeChangedFilesList(files: log.changedFiles, isZh: isZh),
        ],
        if (isFailed) ...[
          kOpenHandGap12,
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: colorScheme.error,
              ),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '本阶段执行失败，请检查上方日志以了解详情。',
                    zhHant: '本階段執行失敗，請檢查上方日誌了解詳情。',
                    en: 'This phase failed. Review the log above for details.',
                    fr: 'Cette phase a échoué. Consultez le journal ci-dessus pour plus de détails.',
                    de: 'Diese Phase ist fehlgeschlagen. Details stehen im obigen Log.',
                    ja: 'このフェーズは失敗しました。詳細は上のログを確認してください。',
                  ),
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

// _HePhaseActionBar — action buttons shown below a selected phase card,
// matching the _MessageActionButton pattern from AI thread messages.
class _HePhaseActionBar extends StatelessWidget {
  const _HePhaseActionBar({
    required this.onCopyLog,
    required this.onReExecute,
    required this.onDelete,
  });

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
          label: Text(openHandCopyLabel(context)),
        ),
        OutlinedButton.icon(
          onPressed: onReExecute,
          style: buttonStyle,
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: Text(
            openHandLocalizedText(
              context,
              zh: '重新执行',
              zhHant: '重新執行',
              en: 'Re-execute',
              fr: 'Relancer',
              de: 'Erneut ausführen',
              ja: '再実行',
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onDelete,
          style: buttonStyle,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: Text(openHandDeleteLabel(context)),
        ),
      ],
    );
  }
}

class _HeSweepPill extends StatelessWidget {
  const _HeSweepPill({
    required this.child,
    required this.backgroundColor,
    required this.sweepColor,
  });

  final Widget child;
  final Color backgroundColor;
  final Color sweepColor;

  @override
  Widget build(BuildContext context) {
    const br = kOpenHandPillBorderRadius;
    return ClipRRect(
      borderRadius: br,
      child: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor, borderRadius: br),
        child: OpenHandSweepShimmer(sweepColor: sweepColor, child: child),
      ),
    );
  }
}

// Phase card header pill — mirrors _ToolCallMetaRow
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

  final HarnessPhaseLog log;
  final String phaseName;
  final IconData phaseIcon;
  final String statusText;
  final IconData statusIcon;
  final Color textColor;
  final bool expanded;
  final VoidCallback onToggle;

  bool get _isRunning => log.status == HarnessPhaseStatus.running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Status-icon indicator with AnimatedSwitcher — transitions smoothly when
    // the phase status changes (pending → running → completed).
    // While running the icon position is kept empty; the sweep animation on
    // the pill itself already signals activity.
    final statusIndicator = AnimatedSwitcher(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: kOpenHandEntranceCurve),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        key: ValueKey<HarnessPhaseStatus>(log.status),
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
          if (!_isRunning) kOpenHandHGap8,
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
          kOpenHandHGap6,
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
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
              borderRadius: kOpenHandPillBorderRadius,
            ),
            child: pillInnerContent,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: kOpenHandPillBorderRadius,
        overlayColor: WidgetStatePropertyAll<Color>(
          textColor.withValues(alpha: 0.06),
        ),
        child: pillDecoratedChild,
      ),
    );
  }
}

// _HeLogSection — smart log panel
// • Running phase  → live monospace tail (last 50 lines, auto-scroll)
// • Done phase     → "Smart" view (default): extracted command chip +
//                    full Markdown-rendered content
//                    "Raw" toggle: classic coloured monospace

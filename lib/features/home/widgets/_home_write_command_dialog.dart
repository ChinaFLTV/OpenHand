part of '../openhand_home_page.dart';

/// 写命令确认弹窗。返回值：
/// * [BashCommandApprovalDecision.approved] —— 用户点击「允许执行」或敲回车
/// * [BashCommandApprovalDecision.rejected] —— 用户点击「取消」按钮
/// * [BashCommandApprovalDecision.timedOut] —— 审批倒计时结束自动拒绝
/// * `null` —— 调用方通过 Session 外部关闭，视为 dismissed 由调用方解释
///
/// 弹窗显式禁用 barrierDismissible + dismissOnEscape：点击外部空白处与
/// 按 Esc 均不会关闭，必须用户显式点击「允许执行」或「取消」按钮才能
/// 关闭，避免误触引发「已隐式同意」或「意外丢弃」的歧义。
Future<BashCommandApprovalDecision?> showWriteCommandConfirmationDialog(
  BuildContext context, {
  required BashCommandApprovalRequest request,
}) {
  return showWriteCommandConfirmationDialogSession(
    context,
    request: request,
  ).result;
}

OpenHandDialogSession<BashCommandApprovalDecision>
showWriteCommandConfirmationDialogSession(
  BuildContext context, {
  required BashCommandApprovalRequest request,
}) {
  final sessionHolder = <OpenHandDialogSession<BashCommandApprovalDecision>?>[
    null,
  ];
  final session = showTrackedAnimatedDialog<BashCommandApprovalDecision>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false, // 内部 Focus 消费 Esc，避免继续传播至上层快捷键
    builder: (_) => _WriteCommandConfirmationDialog(
      request: request,
      onDecision: (decision) {
        final activeSession = sessionHolder[0];
        if (activeSession == null) return;
        unawaited(
          activeSession.dismiss(
            result: decision,
            logTag: 'home',
            logAction: '处理写入命令审批对话框',
          ),
        );
      },
    ),
  );
  sessionHolder[0] = session;
  return session;
}

class _WriteCommandConfirmationDialog extends StatefulWidget {
  const _WriteCommandConfirmationDialog({
    required this.request,
    required this.onDecision,
  });

  final BashCommandApprovalRequest request;
  final ValueChanged<BashCommandApprovalDecision> onDecision;

  @override
  State<_WriteCommandConfirmationDialog> createState() =>
      _WriteCommandConfirmationDialogState();
}

class _WriteCommandConfirmationDialogState
    extends State<_WriteCommandConfirmationDialog> {
  static const Duration _tick = Duration(seconds: 1);

  final ScrollController _bodyScrollController = ScrollController();
  final FocusNode _shortcutFocusNode = FocusNode();
  Timer? _timer;
  bool _isExpanded = false;
  bool _decisionRequested = false;
  DateTime _now = DateTime.now().toUtc();

  DateTime? get _requestedAt => widget.request.requestedAt?.toUtc();

  DateTime? get _expiresAt => widget.request.expiresAt?.toUtc();

  Duration? get _remaining {
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      return null;
    }
    return nonNegativeDuration(expiresAt.difference(_now));
  }

  double? get _remainingProgress {
    final requestedAt = _requestedAt;
    final expiresAt = _expiresAt;
    if (requestedAt == null || expiresAt == null) {
      return null;
    }
    final total = expiresAt.difference(requestedAt).inMilliseconds;
    if (total <= 0) return 0;
    final remaining = _remaining?.inMilliseconds ?? 0;
    return (remaining / total).clamp(0.0, 1.0);
  }

  bool get _isLongCommand =>
      widget.request.command.length > 150 ||
      widget.request.command.contains('\n');

  String get _shortenedCommand {
    if (!_isLongCommand) {
      return widget.request.command;
    }
    final command = widget.request.command.trim();
    final firstLine = command.split('\n').first;
    if (firstLine.length > 120) {
      return '${firstLine.substring(0, 120)}... [omitted ${command.length - 120} chars]';
    }
    return '$firstLine\n... [omitted ${command.length - firstLine.length} chars]';
  }

  void _closeWith(BashCommandApprovalDecision decision) {
    if (!mounted || _decisionRequested) return;
    _decisionRequested = true;
    _timer?.cancel();
    widget.onDecision(decision);
  }

  void _updateCountdown() {
    if (!mounted) {
      return;
    }
    final nextNow = DateTime.now().toUtc();
    final expiresAt = _expiresAt;
    setState(() => _now = nextNow);
    if (expiresAt != null && !nextNow.isBefore(expiresAt)) {
      _closeWith(BashCommandApprovalDecision.timedOut);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _shortcutFocusNode.requestFocus();
      if (_expiresAt != null) {
        _updateCountdown();
      }
    });
    if (_expiresAt != null) {
      _timer = startSafePeriodicTimer(_tick, (_) => _updateCountdown());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shortcutFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final remaining = _remaining;
    final progress = _remainingProgress;
    final dialog = Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        // Esc 已在上方消费：必须明确允许或取消，避免误触意外丢弃。
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _closeWith(BashCommandApprovalDecision.approved);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandApprovalDialogMaxWidth,
        maxHeight: double.infinity,
        maxHeightFraction: 0.78,
        safeAreaMinimum: const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 24,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildOpenHandApprovalDialogHeader(
                context,
                icon: Icons.terminal_rounded,
                accent: accent,
                title: openHandLocalizedText(
                  context,
                  zh: '确认执行写命令',
                  en: 'Confirm Write Command',
                ),
                description: openHandLocalizedText(
                  context,
                  zh: '该 bash 命令可能修改文件或系统状态，需要你确认后才会真正执行。',
                  en: 'This bash command may modify files or system state. '
                      'OpenHand needs your approval before running it.',
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 16),
                OpenHandCountdownProgressBar(
                  value: progress,
                  color: accent,
                  semanticLabel: openHandLocalizedText(
                    context,
                    zh: '写命令确认剩余时间',
                    en: 'Write-command confirmation time remaining',
                  ),
                ),
              ],
              if (remaining != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OpenHandApprovalChip(
                      icon: Icons.hourglass_top_rounded,
                      label: formatOpenHandAutoRejectCountdown(
                        context,
                        remaining,
                      ),
                      color: accent,
                    ),
                    OpenHandApprovalChip(
                      icon: Icons.folder_open_rounded,
                      label: widget.request.workingDirectory,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: OpenHandSafeScrollbar(
                  controller: _bodyScrollController,
                  thumbVisibility: false,
                  child: SingleChildScrollView(
                    controller: _bodyScrollController,
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isExpanded)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SelectableText(
                                widget.request.command,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      height: 1.45,
                                    ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: SelectableText(
                              _shortenedCommand,
                              maxLines: 3,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                            ),
                          ),
                        if (_isLongCommand)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isExpanded = !_isExpanded;
                                });
                              },
                              icon: Icon(
                                _isExpanded
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _isExpanded
                                    ? openHandLocalizedText(
                                        context,
                                        zh: '收起命令',
                                        en: 'Collapse',
                                      )
                                    : openHandLocalizedText(
                                        context,
                                        zh: '查看完整命令',
                                        en: 'View Full Command',
                                      ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        _WriteCommandDirectoryPanel(
                          workingDirectory: widget.request.workingDirectory,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '快捷键：Enter 确认 · Esc 不关闭，请明确选择允许或取消',
                  en: 'Shortcuts: Enter approves · Esc is ignored; choose Run or Cancel explicitly',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () =>
                        _closeWith(BashCommandApprovalDecision.rejected),
                    label: AppLocalizations.of(context)!.commonCancel,
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: () =>
                        _closeWith(BashCommandApprovalDecision.approved),
                    label: openHandLocalizedText(
                      context,
                      zh: '允许执行',
                      en: 'Run Command',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope<BashCommandApprovalDecision>(canPop: false, child: dialog);
  }
}

class _WriteCommandDirectoryPanel extends StatelessWidget {
  const _WriteCommandDirectoryPanel({required this.workingDirectory});

  final String workingDirectory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _homeWorkingDirectoryLabel(context),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  nonBlankStringOr(workingDirectory, '-'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

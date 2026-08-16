part of '../openhand_home_page.dart';

const Duration _kToolCompletionGlowDuration = Duration(milliseconds: 620);
const Duration _kToolSettleBounceDuration = Duration(milliseconds: 480);
const Duration _kToolPreExecutionMotionDuration = Duration(milliseconds: 360);
const Duration _kToolStructureSwitchDuration = kOpenHandMotion320;
const Duration _kToolPhaseSwitchDuration = kOpenHandMotion280;
const Duration _kToolCompactMotionDuration = kOpenHandMotion220;
const Duration _kToolConstructingPulseDuration = Duration(milliseconds: 1100);
const Curve _kToolCardMotionCurve = kOpenHandSwitchInCurve;

/// 工具卡片阶段切换时新内容自下方滑入的相对幅度。
const double _kToolStructureSlideOffsetY = 0.06;
const int _kToolFullContentMaxBytes = 32 * kBytesPerMiB;

class _ToolCallBody extends _ElapsedMessageWidget {
  const _ToolCallBody({
    required super.message,
    required this.sessionId,
    required this.selectable,
  });

  final String sessionId;
  final bool selectable;

  @override
  bool get shouldTickElapsed => _shouldTickToolExecutionElapsed(message);

  @override
  bool elapsedTimingChanged(covariant _ToolCallBody oldWidget) {
    return _toolExecutionTimingChanged(oldWidget.message, message);
  }

  @override
  State<_ToolCallBody> createState() => _ToolCallBodyState();
}

class _ToolCallBodyState extends State<_ToolCallBody>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        _ForegroundElapsedTicker<_ToolCallBody> {
  bool? _argumentsExpandedOverride;
  bool? _resultExpandedOverride;
  _ToolCallViewData? _cachedViewData;
  int? _cachedViewDataSignature;

  late final AnimationController _completionGlowCtrl;
  late final AnimationController _settleBounceCtrl;
  late final Listenable _mergedAnimations = Listenable.merge(<Listenable>[
    _completionGlowCtrl,
    _settleBounceCtrl,
  ]);
  String? _lastTerminalStatus; // success / error / failure once it lands
  bool? _wasPreExecution;

  @override
  void initState() {
    super.initState();
    _completionGlowCtrl = AnimationController(
      vsync: this,
      duration: _kToolCompletionGlowDuration,
    );
    // 工具加固 v4.5：从「参数构造中」过渡到正式卡片时的 Q 弹回弹动画。
    // 480ms easeOutBack 让边框/背景/尺寸的同步收束带 ~6% 过冲，避免直
    // 接生硬切换。受全局 reduceMotion / TickerMode 偏好控制。
    _settleBounceCtrl = AnimationController(
      vsync: this,
      duration: _kToolSettleBounceDuration,
      value: 1.0,
    );
    final initialStatus = _toolExecutionStatus(widget.message);
    if (_isTerminalStatus(initialStatus)) {
      // 历史工具消息已处于终态，切换会话时不重复播放完成动画。
      _lastTerminalStatus = initialStatus;
      _completionGlowCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _completionGlowCtrl.dispose();
    _settleBounceCtrl.dispose();
    super.dispose();
  }

  void _maybeKickCompletionGlow(String status) {
    if (!_isTerminalStatus(status)) return;
    if (_lastTerminalStatus == status) return;
    final wasFresh = _lastTerminalStatus == null;
    _lastTerminalStatus = status;
    if (!wasFresh) {
      return; // 终态变化（如成功转失败）不重复播放动画。
    }
    if (!openHandTickerMotionEnabled(context)) {
      // 用户减少动态效果或子树暂停时直接进入完成态。
      _completionGlowCtrl.value = 1.0;
      return;
    }
    _completionGlowCtrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _ToolCallBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _argumentsExpandedOverride = null;
      _resultExpandedOverride = null;
      _cachedViewData = null;
      _cachedViewDataSignature = null;
      _lastTerminalStatus = null;
      _completionGlowCtrl.value = 0;
      final initialStatus = _toolExecutionStatus(widget.message);
      if (_isTerminalStatus(initialStatus)) {
        _lastTerminalStatus = initialStatus;
        _completionGlowCtrl.value = 1.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final defaultExpanded = _shouldDefaultExpandToolStatus(
      _toolExecutionStatus(message),
    );
    final argumentsExpanded = _argumentsExpandedOverride ?? defaultExpanded;
    final resultExpanded = _resultExpandedOverride ?? defaultExpanded;
    final toolCall = _resolveToolCallViewData(
      context,
      message,
      argumentsExpanded: argumentsExpanded,
      resultExpanded: resultExpanded,
    );
    // Construction state machine: tool call has been created from stream
    // deltas but the executor has not yet picked it up. Three sub-phases
    // crossfade through a single AnimatedContainer (320ms easeOutCubic):
    //   preparing/constructing → submitting → running.
    // - constructing: arguments still streaming (gray);
    // - submitting:   arguments fully captured, awaiting hand-off
    //                 (soft tertiary tint, brief but visible);
    // - running/done: handled by the regular two-section layout.
    final isStreamingArgs =
        message.metadata['tool_arguments_streaming'] == true ||
        message.metadata['tool_preparing'] == true;
    final isAwaitingExecutor =
        toolCall.status.isEmpty && !toolCall.hasResultContent;
    final isConstructing = isAwaitingExecutor && isStreamingArgs;
    final isSubmitting = isAwaitingExecutor && !isStreamingArgs;
    final isPreExecution = isConstructing || isSubmitting;
    // Detect the pre-execution → executed transition once per state change
    // and schedule the Q-bounce settle. Idempotent: only fires when the
    // boolean flips from true → false, never on internal pre-exec churn.
    final motionEnabled = openHandTickerMotionEnabled(context);
    final preExecutionMotionDuration = openHandMotionDuration(
      context,
      _kToolPreExecutionMotionDuration,
    );
    if (_wasPreExecution == true && !isPreExecution) {
      if (!motionEnabled) {
        _settleBounceCtrl.value = 1.0;
      } else {
        _settleBounceCtrl.forward(from: 0.0);
      }
    } else if (_wasPreExecution == null && !isPreExecution) {
      // First mount on an already-executed message — skip ceremony.
      _settleBounceCtrl.value = 1.0;
    } else if (isPreExecution) {
      // Hold the bounce reset so the next exit replays cleanly.
      _settleBounceCtrl.value = 1.0;
    }
    _wasPreExecution = isPreExecution;
    // Schedule a one-shot completion glow when status first lands on a
    // terminal value. Idempotent — relies on _lastTerminalStatus.
    _maybeKickCompletionGlow(toolCall.status);
    final cs = theme.colorScheme;
    final borderColor = isSubmitting
        ? cs.tertiary.withValues(alpha: 0.45)
        : isConstructing
        ? cs.outline.withValues(alpha: 0.35)
        : Colors.transparent;
    final tintColor = isSubmitting
        ? cs.tertiaryContainer.withValues(alpha: 0.35)
        : isConstructing
        ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
        : Colors.transparent;
    return ClipRect(
      child: AnimatedSize(
        duration: preExecutionMotionDuration,
        curve: _kToolCardMotionCurve,
        alignment: Alignment.topLeft,
        child: AnimatedBuilder(
          animation: _mergedAnimations,
          builder: (context, child) {
            // Compose completion glow on top of the steady-state tint.
            // Curve: ease-out from 1 → 0 (alpha decays). The glow fully
            // fades within ~620ms so the card settles into its neutral
            // post-execution look without lingering color.
            final glowProgress = _completionGlowCtrl.value;
            final glowActive = glowProgress > 0 && glowProgress < 1;
            Color glowFill = Colors.transparent;
            Color glowBorder = Colors.transparent;
            if (glowActive) {
              final fade = (1.0 - glowProgress).clamp(0.0, 1.0);
              final eased = kOpenHandSwitchInCurve.transform(fade);
              final isFail = _isFailureStatus(_lastTerminalStatus ?? '');
              final tone = isFail ? cs.error : cs.primary;
              final container = isFail
                  ? cs.errorContainer
                  : cs.primaryContainer;
              glowFill = container.withValues(alpha: 0.32 * eased);
              glowBorder = tone.withValues(alpha: 0.55 * eased);
            }
            final composedFill = glowActive ? glowFill : tintColor;
            final composedBorder = glowActive ? glowBorder : borderColor;
            // Q 弹回弹：settle 进度走 easeOutBack 曲线（~6% 过冲），
            // 用同一进度同时驱动 radius 由 14→10、scale 由 0.97→1.0
            // 与一次轻微的 padding 保留过渡，让颜色/形状/尺寸同步收
            // 束为正式卡片。pre-execution 阶段保持稳定 radius=14。
            final settleRaw = _settleBounceCtrl.value;
            final settleEased = !motionEnabled
                ? 1.0
                : kOpenHandEntranceCurve.transform(settleRaw);
            final radius = isPreExecution
                ? 14.0
                : 14.0 + (10.0 - 14.0) * settleEased.clamp(0.0, 1.0);
            final settleScale = isPreExecution
                ? 1.0
                : (0.97 + 0.03 * settleEased).clamp(0.96, 1.04);
            final container = AnimatedContainer(
              duration: preExecutionMotionDuration,
              curve: _kToolCardMotionCurve,
              padding: isPreExecution || glowActive
                  ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: composedFill,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: composedBorder),
              ),
              child: child,
            );
            if (!motionEnabled || isPreExecution) {
              return container;
            }
            // 始终用 Transform.scale 包裹（settled 时 scale=1）以保持
            // widget tree 结构稳定，避免 conditional wrap 导致的
            // Element 重建/AnimatedSize ticker 重建。
            return Transform.scale(
              scale: settleScale,
              alignment: Alignment.topLeft,
              child: container,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OpenHandToolChip(
                    icon: toolCall.presentation.icon,
                    label: toolCall.primaryChipLabel,
                  ),
                  // 构造与提交阶段平滑切换；执行后移除子项，避免空组件产生双倍间距。
                  if (isPreExecution)
                    AnimatedSwitcher(
                      duration: openHandMotionDuration(
                        context,
                        _kToolPhaseSwitchDuration,
                      ),
                      switchInCurve: _kToolCardMotionCurve,
                      switchOutCurve: kOpenHandSwitchOutCurve,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.92,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _ToolConstructingBadge(
                        key: ValueKey<String>(
                          isSubmitting ? 'submitting' : 'constructing',
                        ),
                        label: isSubmitting
                            ? AppLocalizations.of(context)!.tlCallSubmitting
                            : AppLocalizations.of(
                                context,
                              )!.tlCallArgumentsConstructing,
                        hint: isSubmitting
                            ? AppLocalizations.of(context)!.tlCallSubmittingHint
                            : AppLocalizations.of(
                                context,
                              )!.tlCallArgumentsConstructingHint,
                        tone: isSubmitting
                            ? _ToolConstructingTone.submitting
                            : _ToolConstructingTone.constructing,
                      ),
                    ),
                  if (toolCall.workingDirectory.isNotEmpty)
                    OpenHandToolChip(
                      icon: Icons.folder_outlined,
                      label:
                          '${AppLocalizations.of(context)!.tlCallDir}: ${toolCall.workingDirectory}',
                    ),
                  if (toolCall.status.isNotEmpty)
                    OpenHandToolChip(
                      icon: toolCall.statusIcon,
                      label: toolCall.outcomeLabel,
                    ),
                  if (message.metadata['sandbox_applied'] == true ||
                      message.metadata['sandbox_blocked'] == true ||
                      '${message.metadata['sandbox_unavailable_reason'] ?? ''}'
                          .trim()
                          .isNotEmpty)
                    Tooltip(
                      message:
                          '${message.metadata['sandbox_unavailable_reason'] ?? message.metadata['sandbox_backend'] ?? ''}',
                      child: OpenHandToolChip(
                        icon: message.metadata['sandbox_blocked'] == true
                            ? Icons.lock_outline_rounded
                            : Icons.security_rounded,
                        label: message.metadata['sandbox_blocked'] == true
                            ? openHandLocalizedText(
                                context,
                                zh: '沙盒拦截',
                                en: 'Sandbox blocked',
                              )
                            : '${openHandSandboxLabel(context)}${'${message.metadata['sandbox_backend'] ?? ''}'.trim().isEmpty ? '' : ' · ${message.metadata['sandbox_backend']}'}',
                      ),
                    ),
                  if (message.metadata['sandbox_proxy_enabled'] == true)
                    Tooltip(
                      message:
                          'HTTP ${message.metadata['sandbox_proxy_http_port'] ?? '-'}${message.metadata['sandbox_proxy_socks_port'] == null ? '' : ' · SOCKS ${message.metadata['sandbox_proxy_socks_port']}'}',
                      child: OpenHandToolChip(
                        icon: Icons.hub_outlined,
                        label: openHandLocalizedText(
                          context,
                          zh: '沙盒代理',
                          en: 'Sandbox proxy',
                        ),
                      ),
                    ),
                  if (message.metadata['websearch_cache'] is String)
                    _ToolCacheChip(
                      status: message.metadata['websearch_cache'] as String,
                      cachedAt:
                          message.metadata['websearch_cache_cached_at']
                              as String?,
                      expiresAt:
                          message.metadata['websearch_cache_expires_at']
                              as String?,
                      hitLabel: '缓存命中',
                      unknownLabelPrefix: '缓存',
                    ),
                  if (message.metadata['webfetch_cache'] is String)
                    _ToolCacheChip(
                      status: message.metadata['webfetch_cache'] as String,
                      cachedAt:
                          message.metadata['webfetch_cache_cached_at']
                              as String?,
                      expiresAt:
                          message.metadata['webfetch_cache_expires_at']
                              as String?,
                      hitLabel: '抓取缓存命中',
                      unknownLabelPrefix: '抓取缓存',
                    ),
                  if (toolCall.durationMs > 0 || toolCall.status == 'running')
                    OpenHandToolChip(
                      icon: Icons.timer_outlined,
                      label:
                          '${AppLocalizations.of(context)!.tlCallElapsed}: ${formatCompactDurationMs(toolCall.durationMs)}',
                    ),
                  if (toolCall.exitCode != null)
                    OpenHandToolChip(
                      icon: Icons.flag_outlined,
                      label:
                          '${AppLocalizations.of(context)!.tlCallExit}: ${toolCall.exitCode}',
                    ),
                  // 停滞 chip：runtime 通过 metadata 上报 stall warning 时显现，
                  // 命令重新有输出后会被清空（仅在 running 状态保留）。
                  if (message.metadata['tool_execution_stall_warning']
                          is String &&
                      (message.metadata['tool_execution_stall_warning']
                              as String)
                          .trim()
                          .isNotEmpty &&
                      toolCall.status == 'running')
                    Tooltip(
                      message:
                          message.metadata['tool_execution_stall_warning']
                              as String,
                      child: OpenHandToolChip(
                        icon: Icons.warning_amber_outlined,
                        label: openHandLocalizedText(
                          context,
                          zh: '可能停滞',
                          zhHant: '可能停滯',
                          en: 'Possibly stalled',
                          fr: 'Possiblement bloqué',
                          de: 'Möglicherweise blockiert',
                          ja: '停止している可能性',
                        ),
                      ),
                    ),
                  // 当工具调用仍登记在执行中心时，提供独立 Stop 按钮：
                  // 单击只杀本调用（区别于全局"停止响应"，不影响并行的兄弟工具）。
                  _ToolCancelButton(
                    sessionId: widget.sessionId,
                    toolCallId: '${message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}',
                  ),
                ],
              ),
              // Phase swap: keys-row (pre-execution) ⇄ expandable-sections
              // (executed). Single AnimatedSwitcher keyed on the binary phase
              // so toggling expand/collapse INSIDE the executed phase does NOT
              // re-trigger the cross-fade; only the structural transition
              // does. Slide+fade gives the swap a soft, slick feel; the outer
              // AnimatedSize already handles overall height.
              kOpenHandGap10,
              OpenHandCrossFadeSwitcher(
                duration: _kToolStructureSwitchDuration,
                slideBeginOffsetY: _kToolStructureSlideOffsetY,
                child: isPreExecution
                    ? KeyedSubtree(
                        key: const ValueKey<String>('phase-pre'),
                        child: _ConstructingArgumentKeysRow(
                          keys: toolCall.argumentKeys,
                          collectedLabel: AppLocalizations.of(
                            context,
                          )!.tlCallCollectedParameters,
                          emptyLabel: AppLocalizations.of(
                            context,
                          )!.tlCallNoParametersYet,
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('phase-done'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ExpandableToolSection(
                              title: AppLocalizations.of(
                                context,
                              )!.tlCallToolInput,
                              preview: toolCall.argumentsPreview,
                              expanded: argumentsExpanded,
                              onToggle: () {
                                setState(() {
                                  _argumentsExpandedOverride =
                                      !argumentsExpanded;
                                });
                              },
                              expandedBuilder: (context) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (toolCall.command.isNotEmpty)
                                    _ToolOutputPanel(
                                      label: AppLocalizations.of(
                                        context,
                                      )!.tlCallCommand,
                                      content: toolCall.formattedCommand,
                                      theme: theme,
                                      selectable: widget.selectable,
                                    ),
                                  if (toolCall.command.isNotEmpty)
                                    kOpenHandGap10,
                                  _ToolOutputPanel(
                                    label: AppLocalizations.of(
                                      context,
                                    )!.tlCallArguments,
                                    content: toolCall.formattedArguments,
                                    theme: theme,
                                    selectable: widget.selectable,
                                  ),
                                ],
                              ),
                            ),
                            kOpenHandGap10,
                            _ExpandableToolSection(
                              title: AppLocalizations.of(
                                context,
                              )!.tlCallToolOutput,
                              preview: toolCall.hasResultContent
                                  ? toolCall.resultPreview
                                  : AppLocalizations.of(
                                      context,
                                    )!.tlCallNoOutputYet,
                              expanded: resultExpanded,
                              onToggle: () {
                                setState(() {
                                  _resultExpandedOverride = !resultExpanded;
                                });
                              },
                              expandedBuilder: (context) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (toolCall.stdout.isNotEmpty)
                                    _ToolOutputPanel(
                                      label: AppLocalizations.of(
                                        context,
                                      )!.tlCallStdout,
                                      content: toolCall.formattedStdout,
                                      theme: theme,
                                      selectable: widget.selectable,
                                      fullContentFile: toolCall.stdoutFile,
                                    ),
                                  if (toolCall.stderr.isNotEmpty) ...[
                                    if (toolCall.stdout.isNotEmpty)
                                      kOpenHandGap10,
                                    _ToolOutputPanel(
                                      label: AppLocalizations.of(
                                        context,
                                      )!.tlCallStderr,
                                      content: toolCall.formattedStderr,
                                      theme: theme,
                                      isError: true,
                                      selectable: widget.selectable,
                                      fullContentFile: toolCall.stderrFile,
                                    ),
                                  ],
                                  if (toolCall.showResultText) ...[
                                    if (toolCall.stdout.isNotEmpty ||
                                        toolCall.stderr.isNotEmpty)
                                      kOpenHandGap10,
                                    _ToolOutputPanel(
                                      label: AppLocalizations.of(
                                        context,
                                      )!.tlCallResult,
                                      content: toolCall.formattedResult,
                                      theme: theme,
                                      selectable: widget.selectable,
                                    ),
                                  ],
                                  if (toolCall.stdout.isEmpty &&
                                      toolCall.stderr.isEmpty &&
                                      !toolCall.showResultText)
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.tlCallThereIsNoToolOutputYet,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // ── File mutation card (Codex-style multi-file list + ledger undo/redo) ──
              if (_fileMutationPaths(message).isNotEmpty &&
                  _toolExecutionStatus(message) == 'success') ...[
                kOpenHandGap10,
                _FileMutationCard(
                  key: ValueKey<String>(
                    'file-mutation-${message.id}-${message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}',
                  ),
                  message: message,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _ToolCallViewData _resolveToolCallViewData(
    BuildContext context,
    AiSessionMessage message, {
    required bool argumentsExpanded,
    required bool resultExpanded,
  }) {
    final signature = Object.hash(
      Localizations.localeOf(context).toLanguageTag(),
      message.id,
      message.metadata['tool_name'],
      message.metadata['tool_source'],
      message.metadata['mcp_server_name'],
      message.metadata['mcp_tool_name'],
      message.metadata['mcp_tool_id'],
      message.metadata['skill_name'],
      message.metadata['tool_execution_status'],
      message.metadata['tool_execution_command'],
      message.metadata['tool_execution_working_directory'],
      message.metadata['tool_execution_stdout'],
      message.metadata['tool_execution_stderr'],
      message.metadata['tool_execution_result'],
      message.metadata['tool_arguments'],
      message.metadata['tool_execution_exit_code'],
      message.metadata['tool_execution_elapsed_ms'] ??
          message.metadata['tool_execution_duration_ms'],
      _shouldTickToolExecutionElapsed(message)
          ? DateTime.now().millisecondsSinceEpoch ~/ 1000
          : '',
      argumentsExpanded,
      resultExpanded,
    );
    if (_cachedViewData != null && _cachedViewDataSignature == signature) {
      return _cachedViewData!;
    }
    final viewData = _ToolCallViewData.from(
      context,
      message,
      includeArgumentsContent: argumentsExpanded,
      includeResultContent: resultExpanded,
    );
    _cachedViewData = viewData;
    _cachedViewDataSignature = signature;
    return viewData;
  }
}

void _markToolCardInteractiveTap(BuildContext context) {
  _BubbleHtmlInteractiveScope.maybeOf(context)?.markInteractiveTap();
}

class _ExpandableToolSection extends StatelessWidget {
  const _ExpandableToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.expandedBuilder,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final WidgetBuilder expandedBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPreview = preview.trim().isNotEmpty;
    final motionDuration = cardMotionDurationFor(context, expanding: expanded);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: kOpenHandBorderRadius16,
      child: InkWell(
        onTap: () {
          _markToolCardInteractiveTap(context);
          onToggle();
        },
        borderRadius: kOpenHandBorderRadius16,
        // AnimatedSize wraps the *entire* card so the chevron rotation
        // and content cross-fade ride a single height curve — feels
        // like the card itself is breathing.
        child: AnimatedSize(
          duration: motionDuration,
          curve: kCardMotionCurve,
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0.0,
                      duration: motionDuration,
                      curve: kCardMotionCurve,
                      child: const Icon(
                        Icons.keyboard_arrow_right_rounded,
                        size: 18,
                      ),
                    ),
                    kOpenHandHGap8,
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                // Cross-fade between collapsed preview and expanded body.
                // Keys lock so toggling the same section animates; the
                // outer AnimatedSize handles height. SizedBox.shrink covers
                // the empty-preview / not-expanded fallback so transitions
                // never see a null child.
                AnimatedSwitcher(
                  duration: motionDuration,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topLeft,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: openHandBoundedCurveAnimation(
                      parent: animation,
                      curve: kOpenHandSwitchInCurve,
                      reverseCurve: kOpenHandSwitchOutCurve,
                    ),
                    child: child,
                  ),
                  child: expanded
                      ? Padding(
                          key: const ValueKey<String>('expanded'),
                          padding: const EdgeInsets.only(top: 12),
                          child: Builder(builder: expandedBuilder),
                        )
                      : hasPreview
                      ? Padding(
                          key: const ValueKey<String>('preview'),
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              height: 1.35,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('empty')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolOutputPanel extends StatefulWidget {
  const _ToolOutputPanel({
    required this.label,
    required this.content,
    required this.theme,
    required this.selectable,
    this.isError = false,
    this.fullContentFile,
  });

  final String label;
  final _FormattedToolContent content;
  final ThemeData theme;
  final bool selectable;
  final bool isError;

  /// Optional file path containing full (non-truncated) content.
  final String? fullContentFile;

  @override
  State<_ToolOutputPanel> createState() => _ToolOutputPanelState();
}

class _ToolOutputPanelState extends State<_ToolOutputPanel> {
  bool _isExpanded = false;
  bool _isWrapped = false;
  _ToolOutputPreview? _cachedPreview;
  String? _cachedPreviewKey;

  void _toggleExpanded() {
    _markToolCardInteractiveTap(context);
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _toggleWrapped() {
    _markToolCardInteractiveTap(context);
    setState(() {
      _isWrapped = !_isWrapped;
    });
  }

  void _showFullContentDialog(BuildContext context) {
    _markToolCardInteractiveTap(context);
    // Defer dialog insertion to avoid triggering MouseTracker re-entrancy
    // when the button is pressed during pointer event processing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAnimatedDialog(
        context: context,
        builder: (_) => _ToolContentFullDialog(
          label: widget.label,
          content: widget.content,
          isError: widget.isError,
          fullContentFile: widget.fullContentFile,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedPreviewKey != widget.content.text) {
      _cachedPreviewKey = widget.content.text;
      _cachedPreview = _buildToolOutputPreview(widget.content.text);
    }
    final preview = _cachedPreview!;
    final bool isLong = preview.isLong;

    final displayContent = isLong && !_isExpanded
        ? preview.collapsedText
        : widget.content.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: widget.theme.textTheme.labelLarge?.copyWith(
                  color: widget.isError
                      ? widget.theme.colorScheme.error
                      : widget.theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _toggleWrapped,
                  icon: Icon(
                    _isWrapped
                        ? Icons.wrap_text_rounded
                        : Icons.segment_rounded,
                    size: 14,
                  ),
                  label: Text(
                    _isWrapped
                        ? AppLocalizations.of(context)!.tlCallUnwrap
                        : AppLocalizations.of(context)!.tlCallWrapLines,
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 28),
                    foregroundColor: widget.theme.colorScheme.primary,
                    textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLong) ...[
                  kOpenHandHGap8,
                  TextButton.icon(
                    onPressed: _toggleExpanded,
                    icon: Icon(
                      _isExpanded
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      size: 14,
                    ),
                    label: Text(
                      _isExpanded
                          ? AppLocalizations.of(
                              context,
                            )!.tlCallViewCompressedContent
                          : AppLocalizations.of(context)!.tlCallViewFullContent,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      foregroundColor: widget.theme.colorScheme.primary,
                      textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isExpanded) ...[
                    kOpenHandHGap8,
                    TextButton.icon(
                      onPressed: () => _showFullContentDialog(context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: Text(
                        AppLocalizations.of(context)!.tlCallViewInDialog,
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 28),
                        foregroundColor: widget.theme.colorScheme.tertiary,
                        textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
        kOpenHandGap8,
        _HighlightedCodePanel(
          content: displayContent,
          theme: widget.theme,
          language: widget.content.language,
          selectable: widget.selectable,
          baseColor: widget.isError
              ? widget.theme.colorScheme.onErrorContainer
              : widget.theme.colorScheme.onSurface,
          accentColor: widget.isError ? widget.theme.colorScheme.error : null,
          wrapLines: _isWrapped,
        ),
      ],
    );
  }
}

const int _toolOutputPreviewMaxLines = 15;
const int _toolOutputPreviewMaxChars = 800;
const String _toolOutputPreviewCollapsedNotice =
    '\n\n... [已折叠以优化显示体验，请点击“查看完整内容”]';

class _ToolOutputPreview {
  const _ToolOutputPreview({required this.isLong, required this.collapsedText});

  final bool isLong;
  final String collapsedText;
}

_ToolOutputPreview _buildToolOutputPreview(String content) {
  if (content.isEmpty) {
    return const _ToolOutputPreview(isLong: false, collapsedText: '');
  }
  final buffer = StringBuffer();
  var index = 0;
  var lineCount = 0;
  var writtenChars = 0;
  var truncatedByChars = false;
  while (index < content.length &&
      lineCount < _toolOutputPreviewMaxLines &&
      writtenChars < _toolOutputPreviewMaxChars) {
    final lineStart = index;
    var lineEnd = index;
    while (lineEnd < content.length) {
      final unit = content.codeUnitAt(lineEnd);
      if (unit == 0x0A || unit == 0x0D) {
        break;
      }
      lineEnd += 1;
    }
    if (lineCount > 0) {
      if (writtenChars + 1 > _toolOutputPreviewMaxChars) {
        truncatedByChars = true;
        break;
      }
      buffer.write('\n');
      writtenChars += 1;
    }
    final remainingChars = _toolOutputPreviewMaxChars - writtenChars;
    final lineLength = lineEnd - lineStart;
    if (lineLength > remainingChars) {
      final safeEnd = safeUtf16PrefixCodeUnits(
        content,
        lineStart + remainingChars,
      );
      buffer.write(content.substring(lineStart, safeEnd));
      writtenChars += safeEnd - lineStart;
      truncatedByChars = true;
      break;
    }
    buffer.write(content.substring(lineStart, lineEnd));
    writtenChars += lineLength;
    lineCount += 1;
    if (lineEnd >= content.length) {
      index = lineEnd;
      break;
    }
    final newlineUnit = content.codeUnitAt(lineEnd);
    if (newlineUnit == 0x0D &&
        lineEnd + 1 < content.length &&
        content.codeUnitAt(lineEnd + 1) == 0x0A) {
      index = lineEnd + 2;
    } else {
      index = lineEnd + 1;
    }
  }
  final hasMore = index < content.length || truncatedByChars;
  if (!hasMore && content.length <= _toolOutputPreviewMaxChars) {
    return _ToolOutputPreview(isLong: false, collapsedText: content);
  }
  return _ToolOutputPreview(
    isLong: true,
    collapsedText: '$buffer$_toolOutputPreviewCollapsedNotice',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToolContentFullDialog — full-screen dialog showing complete tool output
// ─────────────────────────────────────────────────────────────────────────────

const double _kToolContentDialogMaxWidth = 1180;
const double _kToolContentDialogRadius = 26;
const double _kToolContentDialogActionSize = 40;
const double _kToolContentDialogCompactBreakpoint = 720;
const Duration _kToolContentDialogActionResetDelay = Duration(
  milliseconds: 1400,
);
const EdgeInsets _kToolContentDialogHeaderPadding = EdgeInsets.fromLTRB(
  22,
  18,
  14,
  14,
);
const EdgeInsets _kToolContentDialogMetaPadding = EdgeInsets.fromLTRB(
  22,
  10,
  22,
  12,
);
const EdgeInsets _kToolContentDialogBodyPadding = EdgeInsets.all(18);

class _ToolContentFullDialog extends StatefulWidget {
  const _ToolContentFullDialog({
    required this.label,
    required this.content,
    this.isError = false,
    this.fullContentFile,
  });

  final String label;
  final _FormattedToolContent content;
  final bool isError;

  /// Optional file path containing the full (non-truncated) output.
  final String? fullContentFile;

  @override
  State<_ToolContentFullDialog> createState() => _ToolContentFullDialogState();
}

class _ToolContentFullDialogState extends State<_ToolContentFullDialog> {
  bool _wrapLines = true;
  bool _loadingFile = false;
  bool _fileLoadAttempted = false;
  bool _copied = false;
  bool _downloaded = false;
  _FormattedToolContent? _fileContent;
  String? _cachedStatsText;
  _ToolContentDialogStats? _cachedStats;
  Timer? _copiedResetTimer;
  Timer? _downloadedResetTimer;

  _FormattedToolContent get _effectiveContent => _fileContent ?? widget.content;

  bool get _hasText => _effectiveContent.text.trim().isNotEmpty;

  bool get _usingLoadedFile => _fileContent != null;

  @override
  void initState() {
    super.initState();
    _tryLoadFullContent();
  }

  @override
  void didUpdateWidget(covariant _ToolContentFullDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullContentFile != widget.fullContentFile) {
      _fileLoadAttempted = false;
      _fileContent = null;
      _cachedStatsText = null;
      _cachedStats = null;
      _tryLoadFullContent();
    }
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    _downloadedResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryLoadFullContent() async {
    final filePath = widget.fullContentFile?.trim();
    if (filePath == null || filePath.isEmpty || _fileLoadAttempted) return;
    _fileLoadAttempted = true;
    setState(() => _loadingFile = true);
    try {
      final file = File(filePath);
      if (!await isRegularFilePath(file.path, followLinks: true)) {
        if (!mounted) return;
        setState(() => _loadingFile = false);
        return;
      }
      final raw = await readBoundedFileString(
        file,
        maxBytes: _kToolFullContentMaxBytes,
      );
      if (!mounted) return;
      setState(() {
        _fileContent = _formatToolContent(raw);
        _cachedStatsText = null;
        _cachedStats = null;
        _loadingFile = false;
      });
    } catch (error, stack) {
      silentLog('home_tool_call', '加载完整工具内容', error, stack);
      if (!mounted) return;
      setState(() => _loadingFile = false);
    }
  }

  void _toggleWrap() {
    setState(() => _wrapLines = !_wrapLines);
  }

  Future<void> _copyContent() async {
    final text = _effectiveContent.text;
    if (text.isEmpty || _loadingFile) return;
    final copied = await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: text,
      successMessage: openHandLocalizedText(
        context,
        zh: '完整内容已复制。',
        zhHant: '完整內容已複製。',
        en: 'Full content copied.',
        fr: 'Contenu complet copié.',
        de: 'Vollständiger Inhalt kopiert.',
        ja: '完全な内容をコピーしました。',
      ),
      errorMessage: openHandLocalizedText(
        context,
        zh: '复制完整内容失败。',
        zhHant: '複製完整內容失敗。',
        en: 'Failed to copy full content.',
        fr: 'Échec de la copie du contenu complet.',
        de: 'Vollständiger Inhalt konnte nicht kopiert werden.',
        ja: '完全な内容のコピーに失敗しました。',
      ),
      logAction: '复制完整工具内容',
    );
    if (!mounted || !copied) return;
    _copiedResetTimer?.cancel();
    setState(() => _copied = true);
    _copiedResetTimer = startSafeTimer(_kToolContentDialogActionResetDelay, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _downloadContent() async {
    final content = _effectiveContent;
    final text = content.text;
    if (text.isEmpty || _loadingFile) return;
    try {
      final selectedLocation = await getSaveLocation(
        suggestedName: _toolContentDownloadFileName(
          widget.label,
          content.language,
        ),
      );
      final selectedPath = selectedLocation?.path;
      if (!mounted || selectedPath == null || selectedPath.isEmpty) return;
      await writeFileAtomically(File(selectedPath), text);
      if (!mounted) return;
      _downloadedResetTimer?.cancel();
      setState(() => _downloaded = true);
      _showToolContentSnackBar(
        openHandLocalizedText(
          context,
          zh: '完整内容已下载为 ${p.basename(selectedPath)}',
          zhHant: '完整內容已下載為 ${p.basename(selectedPath)}',
          en: 'Full content downloaded as ${p.basename(selectedPath)}',
          fr: 'Contenu complet téléchargé sous ${p.basename(selectedPath)}',
          de: 'Vollständiger Inhalt als ${p.basename(selectedPath)} gespeichert',
          ja: '完全な内容を ${p.basename(selectedPath)} として保存しました',
        ),
        kind: OpenHandSnackKind.success,
      );
      _downloadedResetTimer = startSafeTimer(
        _kToolContentDialogActionResetDelay,
        () {
          if (mounted) setState(() => _downloaded = false);
        },
      );
    } catch (error, stack) {
      silentLog('home_tool_call', '下载完整工具内容', error, stack);
      if (!mounted) return;
      _showToolContentSnackBar(
        openHandLocalizedText(
          context,
          zh: '下载完整内容失败。',
          zhHant: '下載完整內容失敗。',
          en: 'Failed to download full content.',
          fr: 'Échec du téléchargement du contenu complet.',
          de: 'Vollständiger Inhalt konnte nicht gespeichert werden.',
          ja: '完全な内容の保存に失敗しました。',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }

  void _showToolContentSnackBar(
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
  }) {
    flashOpenHandSnack(context, message, kind: kind);
  }

  _ToolContentDialogStats _statsFor(String text) {
    if (identical(_cachedStatsText, text) && _cachedStats != null) {
      return _cachedStats!;
    }
    final stats = _ToolContentDialogStats(
      lineCount: _countToolContentLines(text),
      charCount: text.length,
    );
    _cachedStatsText = text;
    _cachedStats = stats;
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final content = _effectiveContent;
    final text = content.text;
    final stats = _statsFor(text);
    final normalizedLanguage = _normalizeCodeLanguage(content.language);
    final languageLabel =
        normalizedLanguage ??
        openHandLocalizedText(
          context,
          zh: '纯文本',
          zhHant: '純文字',
          en: 'Plain text',
          fr: 'Texte brut',
          de: 'Klartext',
          ja: 'プレーンテキスト',
        );
    final sourceLabel = _loadingFile
        ? openHandLocalizedText(
            context,
            zh: '加载中',
            zhHant: '載入中',
            en: 'Loading',
            fr: 'Chargement',
            de: 'Wird geladen',
            ja: '読み込み中',
          )
        : _usingLoadedFile
        ? openHandLocalizedText(
            context,
            zh: '完整文件',
            zhHant: '完整檔案',
            en: 'Full file',
            fr: 'Fichier complet',
            de: 'Vollständige Datei',
            ja: '完全なファイル',
          )
        : widget.fullContentFile == null
        ? openHandLocalizedText(
            context,
            zh: '消息内容',
            zhHant: '訊息內容',
            en: 'Message content',
            fr: 'Contenu du message',
            de: 'Nachrichteninhalt',
            ja: 'メッセージ内容',
          )
        : openHandLocalizedText(
            context,
            zh: '已回退',
            zhHant: '已回退',
            en: 'Fallback',
            fr: 'Repli',
            de: 'Fallback',
            ja: 'フォールバック',
          );

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: _kToolContentDialogMaxWidth,
      maxHeight: double.infinity,
      maxWidthFraction: 0.94,
      maxHeightFraction: 0.9,
      minAvailableWidth: 320,
      minAvailableHeight: 420,
      horizontalMargin: 56,
      verticalMargin: 56,
      safeAreaMinimum: const EdgeInsets.all(20),
      expandToMax: true,
      backgroundColor: colorScheme.surfaceContainerLowest,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(_kToolContentDialogRadius),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(_kToolContentDialogRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: _kToolContentDialogHeaderPadding,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.hasBoundedWidth &&
                      constraints.maxWidth <
                          _kToolContentDialogCompactBreakpoint;
                  final title = Row(
                    children: [
                      _ToolContentDialogLeadingIcon(isError: widget.isError),
                      kOpenHandHGap12,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: widget.isError
                                    ? colorScheme.error
                                    : colorScheme.onSurface,
                              ),
                            ),
                            kOpenHandGap2,
                            Text(
                              openHandLocalizedText(
                                context,
                                zh: '工具输出完整内容',
                                zhHant: '工具輸出完整內容',
                                en: 'Complete tool output',
                                fr: 'Sortie complète de l’outil',
                                de: 'Vollständige Tool-Ausgabe',
                                ja: 'ツール出力の完全な内容',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      _ToolContentDialogIconButton(
                        tooltip: _wrapLines
                            ? AppLocalizations.of(context)!.tlCallUnwrap
                            : AppLocalizations.of(context)!.tlCallWrapLines,
                        icon: _wrapLines
                            ? Icons.wrap_text_rounded
                            : Icons.segment_rounded,
                        selected: _wrapLines,
                        onPressed: _toggleWrap,
                      ),
                      _ToolContentDialogIconButton(
                        tooltip: _copied
                            ? openHandCopiedLabel(context)
                            : openHandCopyLabel(context),
                        icon: _copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        selected: _copied,
                        onPressed: _hasText && !_loadingFile
                            ? () => unawaited(_copyContent())
                            : null,
                      ),
                      _ToolContentDialogIconButton(
                        tooltip: _downloaded
                            ? openHandLocalizedText(
                                context,
                                zh: '已下载',
                                zhHant: '已下載',
                                en: 'Downloaded',
                                fr: 'Téléchargé',
                                de: 'Gespeichert',
                                ja: '保存済み',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '下载',
                                zhHant: '下載',
                                en: 'Download',
                                fr: 'Télécharger',
                                de: 'Speichern',
                                ja: '保存',
                              ),
                        icon: _downloaded
                            ? Icons.check_rounded
                            : Icons.download_rounded,
                        selected: _downloaded,
                        onPressed: _hasText && !_loadingFile
                            ? () => unawaited(_downloadContent())
                            : null,
                      ),
                      _ToolContentDialogIconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  );
                  if (compact) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        kOpenHandGap12,
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      kOpenHandHGap16,
                      actions,
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: _kToolContentDialogMetaPadding,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                  ),
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ToolContentDialogChip(
                    icon: Icons.code_rounded,
                    label: languageLabel,
                    emphasized: normalizedLanguage != null,
                  ),
                  _ToolContentDialogChip(
                    icon: Icons.format_list_numbered_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '${_compactToolContentCount(stats.lineCount)} 行',
                      zhHant: '${_compactToolContentCount(stats.lineCount)} 行',
                      en: '${_compactToolContentCount(stats.lineCount)} lines',
                      fr: '${_compactToolContentCount(stats.lineCount)} lignes',
                      de: '${_compactToolContentCount(stats.lineCount)} Zeilen',
                      ja: '${_compactToolContentCount(stats.lineCount)} 行',
                    ),
                  ),
                  _ToolContentDialogChip(
                    icon: Icons.data_object_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '${_compactToolContentCount(stats.charCount)} 字符',
                      zhHant: '${_compactToolContentCount(stats.charCount)} 字元',
                      en: '${_compactToolContentCount(stats.charCount)} chars',
                      fr: '${_compactToolContentCount(stats.charCount)} car.',
                      de: '${_compactToolContentCount(stats.charCount)} Zeichen',
                      ja: '${_compactToolContentCount(stats.charCount)} 文字',
                    ),
                  ),
                  _ToolContentDialogChip(
                    icon: _usingLoadedFile
                        ? Icons.insert_drive_file_rounded
                        : Icons.article_outlined,
                    label: sourceLabel,
                    emphasized: _usingLoadedFile,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ToolContentFullDialogBody(
                content: content,
                isError: widget.isError,
                loading: _loadingFile,
                wrapLines: _wrapLines,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolContentDialogStats {
  const _ToolContentDialogStats({
    required this.lineCount,
    required this.charCount,
  });

  final int lineCount;
  final int charCount;
}

class _ToolContentDialogLeadingIcon extends StatelessWidget {
  const _ToolContentDialogLeadingIcon({required this.isError});

  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isError ? colorScheme.error : colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surfaceContainerHigh,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: SizedBox.square(
        dimension: 42,
        child: Icon(
          isError ? Icons.error_outline_rounded : Icons.terminal_rounded,
          color: color,
          size: 22,
        ),
      ),
    );
  }
}

class _ToolContentDialogIconButton extends StatelessWidget {
  const _ToolContentDialogIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;
    return Tooltip(
      message: tooltip,
      waitDuration: kOpenHandTooltipWait,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(_kToolContentDialogActionSize),
          minimumSize: const Size.square(_kToolContentDialogActionSize),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: enabled
              ? foreground
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
          backgroundColor: enabled
              ? background
              : colorScheme.surfaceContainer.withValues(alpha: 0.62),
          disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
            alpha: 0.44,
          ),
          disabledBackgroundColor: colorScheme.surfaceContainer.withValues(
            alpha: 0.58,
          ),
          shape: const RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius14),
        ),
      ),
    );
  }
}

class _ToolContentDialogChip extends StatelessWidget {
  const _ToolContentDialogChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tint = emphasized
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tint.withValues(alpha: emphasized ? 0.10 : 0.06),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: tint.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint),
            kOpenHandHGap6,
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: emphasized ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolContentFullDialogBody extends StatelessWidget {
  const _ToolContentFullDialogBody({
    required this.content,
    required this.isError,
    required this.loading,
    required this.wrapLines,
  });

  final _FormattedToolContent content;
  final bool isError;
  final bool loading;
  final bool wrapLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = content.text;

    if (loading) {
      return _ToolContentDialogStatePane(
        icon: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            color: colorScheme.primary,
          ),
        ),
        title: openHandLocalizedText(
          context,
          zh: '正在加载完整内容',
          zhHant: '正在載入完整內容',
          en: 'Loading full content',
          fr: 'Chargement du contenu complet',
          de: 'Vollständiger Inhalt wird geladen',
          ja: '完全な内容を読み込み中',
        ),
      );
    }

    if (text.trim().isEmpty) {
      return _ToolContentDialogStatePane(
        icon: Icon(
          Icons.article_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 28,
        ),
        title: AppLocalizations.of(context)!.tlCallEmptyContent,
      );
    }

    return Padding(
      padding: _kToolContentDialogBodyPadding,
      child: SizedBox.expand(
        child: _HighlightedCodePanel(
          content: text,
          theme: theme,
          language: content.language,
          selectable: true,
          baseColor: isError
              ? colorScheme.onErrorContainer
              : colorScheme.onSurface,
          accentColor: isError ? colorScheme.error : null,
          wrapLines: wrapLines,
          showToolbar: false,
          internalVerticalScroll: true,
        ),
      ),
    );
  }
}

class _ToolContentDialogStatePane extends StatelessWidget {
  const _ToolContentDialogStatePane({required this.icon, required this.title});

  final Widget icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              kOpenHandHGap12,
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactToolContentCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final scaled = value / 1000;
    return '${_trimToolContentCount(scaled, value < 10000 ? 1 : 0)}K';
  }
  final scaled = value / 1000000;
  return '${_trimToolContentCount(scaled, value < 10000000 ? 1 : 0)}M';
}

/// 去掉小数末尾的零与孤立小数点。
final RegExp _trailingZeroFractionPattern = RegExp(r'\.?0+$');

String _trimToolContentCount(double value, int fractionDigits) {
  final fixed = value.toStringAsFixed(fractionDigits);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(_trailingZeroFractionPattern, '');
}

int _countToolContentLines(String text) {
  if (text.isEmpty) return 0;
  var count = 1;
  var index = 0;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x0A) {
      count += 1;
    } else if (unit == 0x0D) {
      count += 1;
      if (index + 1 < text.length && text.codeUnitAt(index + 1) == 0x0A) {
        index += 1;
      }
    }
    index += 1;
  }
  return count;
}

String _toolContentDownloadFileName(String label, String? language) {
  final extension = _getFileExtensionForLanguage(language);
  final normalized = label.trim().toLowerCase();
  final baseName = sanitizePortableFileNamePart(
    normalized,
    fallback: 'tool_output',
    collapseReplacement: true,
    trimBoundaryReplacement: true,
  );
  if (baseName.endsWith(extension)) return baseName;
  return '$baseName$extension';
}

class _ToolCacheChip extends StatelessWidget {
  const _ToolCacheChip({
    required this.status,
    required this.cachedAt,
    required this.expiresAt,
    required this.hitLabel,
    required this.unknownLabelPrefix,
  });

  final String status;
  final String? cachedAt;
  final String? expiresAt;
  final String hitLabel;
  final String unknownLabelPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    late final IconData icon;
    late final String label;
    late final Color tint;
    switch (status) {
      case 'hit':
        icon = Icons.flash_on_rounded;
        label = hitLabel;
        tint = cs.primary;
      case 'miss-stored':
        icon = Icons.cloud_download_outlined;
        label = '已落盘';
        tint = cs.tertiary;
      case 'disabled':
        icon = Icons.do_disturb_alt_outlined;
        label = '缓存关闭';
        tint = cs.onSurfaceVariant;
      default:
        icon = Icons.help_outline;
        label = '$unknownLabelPrefix：$status';
        tint = cs.onSurfaceVariant;
    }
    final tooltip = StringBuffer(label);
    if (cachedAt != null && cachedAt!.isNotEmpty) {
      tooltip
        ..write('\n命中时间：')
        ..write(cachedAt);
    }
    if (expiresAt != null && expiresAt!.isNotEmpty) {
      tooltip
        ..write('\n过期时间：')
        ..write(expiresAt);
    }
    return Tooltip(
      message: tooltip.toString(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint),
            kOpenHandHGap6,
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: tint),
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具卡片右侧出现的"独立 Stop"按钮 —— 仅当 [toolCallId] 仍登记在
/// [AiToolExecutionRegistry] 时显现。点击只终止本调用，不影响并行执行的
/// 兄弟工具，区别于全局的"停止响应"。
class _ToolCancelButton extends StatefulWidget {
  const _ToolCancelButton({required this.sessionId, required this.toolCallId});

  final String sessionId;
  final String toolCallId;

  @override
  State<_ToolCancelButton> createState() => _ToolCancelButtonState();
}

class _ToolCancelButtonState extends State<_ToolCancelButton> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AiToolExecutionRegistry.instance.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    AiToolExecutionRegistry.instance.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onTap() async {
    if (_busy) return;
    _markToolCardInteractiveTap(context);
    setState(() => _busy = true);
    try {
      await AiToolExecutionRegistry.instance.cancelToolCall(
        sessionId: widget.sessionId,
        toolCallId: widget.toolCallId,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.toolCallId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    final record = AiToolExecutionRegistry.instance.recordOf(
      sessionId: widget.sessionId,
      toolCallId: id,
    );
    if (record == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: AppLocalizations.of(context)!.tlCallStopRequest,
      child: InkWell(
        onTap: _busy ? null : _onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.55),
            borderRadius: kOpenHandPillBorderRadius,
            border: Border.all(color: cs.error.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _busy ? Icons.hourglass_top : Icons.stop_circle_outlined,
                size: 14,
                color: cs.error,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ToolConstructingTone { constructing, submitting }

/// Pulsing pill shown next to the primary chip during the pre-execution
/// phases. `constructing` = gray (arguments still streaming),
/// `submitting` = soft tertiary tint (arguments captured, awaiting the
/// executor). Both pulse with the same 1.1s breathing rhythm.
class _ToolConstructingBadge extends StatefulWidget {
  const _ToolConstructingBadge({
    super.key,
    required this.label,
    required this.hint,
    this.tone = _ToolConstructingTone.constructing,
  });

  final String label;
  final String hint;
  final _ToolConstructingTone tone;

  @override
  State<_ToolConstructingBadge> createState() => _ToolConstructingBadgeState();
}

class _ToolConstructingBadgeState extends State<_ToolConstructingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kToolConstructingPulseDuration,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSubmitting = widget.tone == _ToolConstructingTone.submitting;
    final baseFill = isSubmitting
        ? cs.tertiaryContainer
        : cs.surfaceContainerHighest;
    final baseBorder = isSubmitting ? cs.tertiary : cs.outline;
    final fg = isSubmitting ? cs.onTertiaryContainer : cs.onSurfaceVariant;
    final animationsEnabled = openHandTickerMotionEnabled(context);
    final badgeMotionDuration = openHandMotionDuration(
      context,
      _kToolPhaseSwitchDuration,
    );
    Widget buildBadge(double t) {
      return AnimatedContainer(
        duration: badgeMotionDuration,
        curve: _kToolCardMotionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: baseFill.withValues(alpha: 0.55 + 0.35 * t),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(
            color: baseBorder.withValues(alpha: 0.3 + 0.25 * t),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                value: animationsEnabled ? null : 1,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            ),
            kOpenHandHGap6,
            Text(
              widget.label,
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
          ],
        ),
      );
    }

    if (!animationsEnabled) {
      _ctrl.stop();
      return Tooltip(message: widget.hint, child: buildBadge(0.5));
    }
    if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
    return Tooltip(
      message: widget.hint,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return buildBadge(_ctrl.value);
        },
      ),
    );
  }
}

/// Inline row used while a tool call is still in its "constructing" phase:
/// shows the parameter keys parsed so far (e.g. `path, query`), or a muted
/// "no parameters yet" placeholder. Each key fades in via [AppearOnce] so
/// new arrivals feel alive without re-laying out neighbours.
class _ConstructingArgumentKeysRow extends StatelessWidget {
  const _ConstructingArgumentKeysRow({
    required this.keys,
    required this.collectedLabel,
    required this.emptyLabel,
  });

  final List<({String key, String? valuePreview})> keys;
  final String collectedLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(emptyLabel, style: mutedStyle),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2, left: 2),
          child: Text(
            '$collectedLabel:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        for (final entry in keys)
          AppearOnce(
            key: ValueKey<String>('arg-key-${entry.key}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
                borderRadius: kOpenHandPillBorderRadius,
                border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
              ),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurface,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                  children: [
                    TextSpan(text: entry.key),
                    if (entry.valuePreview != null) ...[
                      TextSpan(
                        text: ': ',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                      TextSpan(
                        text: entry.valuePreview,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolCallPresentation {
  const _ToolCallPresentation({
    required this.categoryLabel,
    required this.displayName,
    required this.icon,
    this.isCommandLike = false,
  });

  final String categoryLabel;
  final String displayName;
  final IconData icon;
  final bool isCommandLike;
}

class _ToolCallViewData {
  const _ToolCallViewData({
    required this.presentation,
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.durationMs,
    required this.argumentsPreview,
    required this.argumentKeys,
    required this.formattedCommand,
    required this.formattedArguments,
    required this.formattedStdout,
    required this.formattedStderr,
    required this.formattedResult,
    required this.defaultExpanded,
    required this.showResultText,
    required this.hasResultContent,
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.primaryChipLabel,
    required this.statusLabel,
    required this.outcomeLabel,
    required this.resultPreview,
    this.stdoutFile,
    this.stderrFile,
  });

  factory _ToolCallViewData.from(
    BuildContext context,
    AiSessionMessage message, {
    bool includeArgumentsContent = true,
    bool includeResultContent = true,
  }) {
    final presentation = _toolCallPresentation(context, message);
    final isPreparing = message.metadata['tool_preparing'] == true;
    final effectivePresentation = isPreparing
        ? _ToolCallPresentation(
            categoryLabel: AppLocalizations.of(context)!.tlCallTool,
            displayName: AppLocalizations.of(context)!.tlCallPreparing,
            icon: Icons.hourglass_empty_rounded,
          )
        : presentation;
    final status = _toolExecutionStatus(message);
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message).trimRight();
    final stderr = _toolExecutionStderr(message).trimRight();
    final resultText = _toolExecutionResult(message).trimRight();
    final exitCode = _toolExecutionExitCode(message);
    final durationMs = _toolExecutionDurationMs(message);
    final argumentsPreview = _toolArgumentsPreview(message);
    final argumentKeys = _parseArgumentKeys(
      '${message.metadata['tool_arguments'] ?? ''}',
    );
    final formattedCommand = !includeArgumentsContent || command.isEmpty
        ? const _FormattedToolContent(text: '')
        : _FormattedToolContent(text: '\$ $command', language: 'bash');
    final formattedArguments = includeArgumentsContent
        ? _formatToolContent(
            '${message.metadata['tool_arguments'] ?? ''}',
            emptyFallback: '{}',
          )
        : const _FormattedToolContent(text: '{}');
    final formattedStdout = includeResultContent
        ? _formatToolContent(stdout)
        : const _FormattedToolContent(text: '');
    final formattedStderr = includeResultContent
        ? _formatToolContent(stderr)
        : const _FormattedToolContent(text: '');
    final formattedResult = includeResultContent
        ? _formatToolContent(resultText)
        : const _FormattedToolContent(text: '');
    final isStructuredWrapper =
        resultText.startsWith('status: ') &&
        resultText.contains('\ncommand: ') &&
        resultText.contains('\nduration_ms: ');
    final showResultText =
        resultText.isNotEmpty &&
        resultText != stdout.trim() &&
        resultText != stderr.trim() &&
        !isStructuredWrapper;
    final hasResultContent =
        stdout.isNotEmpty ||
        stderr.isNotEmpty ||
        resultText.isNotEmpty ||
        exitCode != null ||
        status.isNotEmpty;
    final stdoutFile = '${message.metadata['tool_execution_stdout_file'] ?? ''}'
        .trim();
    final stderrFile = '${message.metadata['tool_execution_stderr_file'] ?? ''}'
        .trim();
    final viewData = _ToolCallViewData(
      presentation: effectivePresentation,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout,
      stderr: stderr,
      resultText: resultText,
      exitCode: exitCode,
      durationMs: durationMs,
      argumentsPreview: argumentsPreview,
      argumentKeys: argumentKeys,
      formattedCommand: formattedCommand,
      formattedArguments: formattedArguments,
      formattedStdout: formattedStdout,
      formattedStderr: formattedStderr,
      formattedResult: formattedResult,
      defaultExpanded: _shouldDefaultExpandToolStatus(status),
      showResultText: showResultText,
      hasResultContent: hasResultContent,
      stdoutFile: stdoutFile.isNotEmpty ? stdoutFile : null,
      stderrFile: stderrFile.isNotEmpty ? stderrFile : null,
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      primaryChipLabel: _buildPrimaryChipLabel(context, effectivePresentation),
      statusLabel: _toolCallStatusLabelForData(
        context,
        effectivePresentation,
        status,
        durationMs,
      ),
      outcomeLabel: _toolExecutionOutcomeLabel(context, status),
      resultPreview: _toolExecutionPreviewText(
        context,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
    return viewData;
  }

  final _ToolCallPresentation presentation;
  final String status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final int durationMs;
  final String argumentsPreview;

  /// Argument names (top-level keys) that have been parsed so far. Useful
  /// during the streaming "constructing" state to surface a real-time
  /// preview of which parameters the model has already supplied.
  final List<({String key, String? valuePreview})> argumentKeys;
  final _FormattedToolContent formattedCommand;
  final _FormattedToolContent formattedArguments;
  final _FormattedToolContent formattedStdout;
  final _FormattedToolContent formattedStderr;
  final _FormattedToolContent formattedResult;
  final bool defaultExpanded;
  final bool showResultText;
  final bool hasResultContent;
  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String primaryChipLabel;
  final String statusLabel;
  final String outcomeLabel;
  final String resultPreview;

  /// File path containing full stdout when it was truncated at collection time.
  final String? stdoutFile;

  /// File path containing full stderr when it was truncated at collection time.
  final String? stderrFile;
}

String _toolCallName(AiSessionMessage message) =>
    '${message.metadata['tool_name'] ?? ''}'.trim();

String _toolExecutionStatus(AiSessionMessage message) =>
    '${message.metadata['tool_execution_status'] ?? ''}'.trim();

bool _toolExecutionTimingChanged(
  AiSessionMessage previous,
  AiSessionMessage current,
) {
  return previous.id != current.id ||
      _toolExecutionStatus(previous) != _toolExecutionStatus(current) ||
      previous.metadata['tool_execution_started_at'] !=
          current.metadata['tool_execution_started_at'] ||
      previous.metadata['tool_execution_elapsed_ms'] !=
          current.metadata['tool_execution_elapsed_ms'] ||
      previous.metadata['tool_execution_duration_ms'] !=
          current.metadata['tool_execution_duration_ms'];
}

bool _shouldSweepToolStatus(String status) {
  return status.isEmpty || _isLiveToolExecutionStatus(status);
}

bool _isTerminalStatus(String status) {
  final normalized = status.toLowerCase();
  return normalized == 'success' ||
      normalized == 'ok' ||
      normalized == 'completed' ||
      normalized == 'error' ||
      normalized == 'failure' ||
      normalized == 'failed' ||
      normalized == 'denied' ||
      normalized == 'rejected' ||
      normalized == 'timed_out' ||
      normalized == 'invalid_arguments' ||
      normalized == 'cancelled' ||
      normalized == 'canceled' ||
      normalized == 'aborted' ||
      normalized == 'blocked';
}

bool _isFailureStatus(String status) {
  final normalized = status.toLowerCase();
  return normalized == 'error' ||
      normalized == 'failure' ||
      normalized == 'failed' ||
      normalized == 'denied' ||
      normalized == 'rejected' ||
      normalized == 'timed_out' ||
      normalized == 'invalid_arguments' ||
      normalized == 'blocked';
}

bool _isLiveToolExecutionStatus(String status) {
  final normalized = status.toLowerCase();
  return normalized == 'running' ||
      normalized == 'pending' ||
      normalized == 'in_progress';
}

bool _shouldTickToolExecutionElapsed(AiSessionMessage message) {
  return _isLiveToolExecutionStatus(_toolExecutionStatus(message));
}

DateTime? _toolExecutionStartedAt(AiSessionMessage message) {
  return _dateTimeFromMetadata(message.metadata['tool_execution_started_at']);
}

DateTime? _toolExecutionFinishedAt(AiSessionMessage message) {
  return _dateTimeFromMetadata(message.metadata['tool_execution_finished_at']);
}

String _toolExecutionCommand(AiSessionMessage message) {
  final executionCommand = '${message.metadata['tool_execution_command'] ?? ''}'
      .trim();
  if (executionCommand.isNotEmpty) {
    return executionCommand;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolCommandFromArguments(rawArguments);
}

String _toolExecutionWorkingDirectory(AiSessionMessage message) {
  final executionDirectory =
      '${message.metadata['tool_execution_working_directory'] ?? ''}'.trim();
  if (executionDirectory.isNotEmpty) {
    return executionDirectory;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolWorkingDirectoryFromArguments(rawArguments);
}

String _toolExecutionStdout(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stdout'] ?? ''}';

String _toolExecutionStderr(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stderr'] ?? ''}';

String _toolExecutionResult(AiSessionMessage message) =>
    '${message.metadata['tool_execution_result'] ?? ''}';

bool _isStreamingReasoningMessage(AiSessionMessage message) {
  return message.kind == AiSessionMessageKind.reasoning &&
      message.metadata[aiSessionMessageMetadataStreamingKey] == true;
}

bool _shouldTrackMessageLayout({
  required AiSessionMessage message,
  required AiSendPhase sendPhase,
  required bool isLastVisibleMessage,
}) {
  final isRoundFileMutationSummary =
      message.kind == AiSessionMessageKind.fileMutationSummary ||
      (message.kind == AiSessionMessageKind.status &&
          message.metadata['round_file_mutation_summary'] == true);
  if (isLastVisibleMessage && isRoundFileMutationSummary) {
    return true;
  }
  if (_isStreamingReasoningMessage(message)) {
    return true;
  }
  if (message.kind == AiSessionMessageKind.toolCall) {
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      return true;
    }
  }
  if (sendPhase != AiSendPhase.idle && isLastVisibleMessage) {
    return switch (message.kind) {
      AiSessionMessageKind.assistant || AiSessionMessageKind.status => true,
      _ => false,
    };
  }
  return false;
}

bool _shouldDefaultExpandReasoning(AiSessionMessage message) {
  // 超过 5-6 行的思考内容默认折叠，包括流式阶段。这样 pending tool-call
  // 卡片插入时不会被长思考逐 token 增长反复顶动；较短内容继续展开，省一次点击。
  return !_isReasoningContentLong(message.content);
}

/// 思考类型消息「是否算超长」的判定，与 WEB 端 isReasoningLong 对齐：
/// - 硬换行 `\n` 数 ≥ 5（即内容占 6 行及以上） → 超长；
/// - 否则回退到字符数阈值（避免长段无换行文本被误判为短）。
const int _reasoningLongCharThreshold = 260;
const int _reasoningLongLineBreakThreshold = 5;
bool _isReasoningContentLong(String content) {
  if (content.length > _reasoningLongCharThreshold) return true;
  var lineBreaks = 0;
  for (final unit in content.codeUnits) {
    if (unit == 0x0A) {
      lineBreaks += 1;
      if (lineBreaks >= _reasoningLongLineBreakThreshold) return true;
    }
  }
  return false;
}

bool _shouldDefaultExpandToolStatus(String status) {
  return status.isEmpty;
}

int _reasoningElapsedMs(AiSessionMessage message) {
  final fixedElapsedMs = _reasoningFixedElapsedMs(message);
  if (fixedElapsedMs != null) {
    return fixedElapsedMs;
  }
  final startedAt =
      _dateTimeFromMetadata(
        message.metadata[aiSessionMessageReasoningStartedAtKey],
      ) ??
      message.createdAt.toUtc();
  final elapsed = DateTime.now().toUtc().difference(startedAt).inMilliseconds;
  return math.max(0, elapsed);
}

int? _reasoningFixedElapsedMs(AiSessionMessage message) {
  final storedElapsed = _nonNegativeIntFromMetadata(
    message.metadata[aiSessionMessageReasoningElapsedMsKey],
  );
  if (storedElapsed != null) {
    return storedElapsed;
  }
  final endedAt = _dateTimeFromMetadata(
    message.metadata[aiSessionMessageReasoningEndedAtKey],
  );
  if (endedAt == null) {
    return null;
  }
  final startedAt =
      _dateTimeFromMetadata(
        message.metadata[aiSessionMessageReasoningStartedAtKey],
      ) ??
      message.createdAt.toUtc();
  return math.max(0, endedAt.difference(startedAt).inMilliseconds);
}

int? _nonNegativeIntFromMetadata(Object? rawValue) {
  return optionalNonNegativeIntFromValue(rawValue);
}

DateTime? _dateTimeFromMetadata(Object? rawValue) {
  return utcDateTimeFromValue(rawValue);
}

int? _toolExecutionExitCode(AiSessionMessage message) {
  final value = message.metadata['tool_execution_exit_code'];
  return optionalIntegralIntFromValue(value);
}

IconData _toolExecutionStatusIcon(String status) {
  return switch (status.toLowerCase()) {
    'running' ||
    'pending' ||
    'in_progress' => Icons.play_circle_outline_rounded,
    'cancelled' || 'canceled' || 'aborted' => Icons.stop_circle_outlined,
    'success' || 'ok' || 'completed' => Icons.check_circle_outline_rounded,
    'denied' || 'blocked' => Icons.block_rounded,
    'rejected' => Icons.cancel_outlined,
    'timed_out' => Icons.timer_off_outlined,
    'failed' || 'failure' || 'error' => Icons.error_outline_rounded,
    'invalid_arguments' => Icons.warning_amber_rounded,
    _ => Icons.terminal_rounded,
  };
}

/// Builds a compact, non-redundant chip label for a tool call bubble.
///
/// - When [_ToolCallPresentation.categoryLabel] equals [_ToolCallPresentation.displayName]
///   (the common built-in tool case, e.g. both are "Bash"), render the label once
///   to avoid producing noisy strings such as "Bash: Bash".
/// - For the generic "Tool" / "工具" fallback (used when the model emits an
///   unrecognized tool name), drop the generic category prefix and surface only
///   the actual name so the chip does not bleed scaffolding like "Tool: Bash"
///   into the transcript.
/// - Otherwise keep the `Category: DisplayName` form so MCP/Skill/Hook chips
///   remain easy to scan.
String _buildPrimaryChipLabel(
  BuildContext context,
  _ToolCallPresentation presentation,
) {
  final category = presentation.categoryLabel.trim();
  final display = presentation.displayName.trim();
  if (category.isEmpty || category == display) {
    return display.isEmpty ? category : display;
  }
  final genericCategory = AppLocalizations.of(context)!.tlCallTool;
  if (category == genericCategory) {
    return display.isEmpty ? category : display;
  }
  return '$category: $display';
}

_ToolCallPresentation _toolCallPresentation(
  BuildContext context,
  AiSessionMessage message,
) {
  final rawToolName = _toolCallName(message);
  final normalizedToolName = rawToolName.trim().toLowerCase();
  final toolSource = '${message.metadata['tool_source'] ?? ''}'
      .trim()
      .toLowerCase();
  if (toolSource == 'skill' || normalizedToolName.startsWith('skill__')) {
    final skillName = '${message.metadata['skill_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: AppLocalizations.of(context)!.tlCallSkill,
      displayName: skillName.isEmpty ? rawToolName : skillName,
      icon: Icons.extension_rounded,
    );
  }
  if (toolSource == 'hook' || normalizedToolName.startsWith('hook__')) {
    final hookName = '${message.metadata['hook_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: 'Hook',
      displayName: hookName.isEmpty ? rawToolName : hookName,
      icon: Icons.webhook_rounded,
    );
  }
  if (toolSource == 'mcp' || normalizedToolName.startsWith('mcp__')) {
    final serverName = '${message.metadata['mcp_server_name'] ?? ''}'.trim();
    final toolName = '${message.metadata['mcp_tool_name'] ?? ''}'.trim();
    final toolId = '${message.metadata['mcp_tool_id'] ?? ''}'.trim();
    final displayName = <String>[
      if (serverName.isNotEmpty) serverName,
      if (toolName.isNotEmpty) toolName else if (toolId.isNotEmpty) toolId,
    ].join(' / ');
    return _ToolCallPresentation(
      categoryLabel: 'MCP',
      displayName: displayName.isEmpty ? rawToolName : displayName,
      icon: Icons.account_tree_outlined,
    );
  }
  return switch (normalizedToolName) {
    'bash' => const _ToolCallPresentation(
      categoryLabel: 'Bash',
      displayName: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    ),
    'grep' => const _ToolCallPresentation(
      categoryLabel: 'Grep',
      displayName: 'Grep',
      icon: Icons.manage_search_rounded,
    ),
    'ls' => const _ToolCallPresentation(
      categoryLabel: 'LS',
      displayName: 'LS',
      icon: Icons.folder_open_rounded,
    ),
    'read' => const _ToolCallPresentation(
      categoryLabel: 'Read',
      displayName: 'Read',
      icon: Icons.article_outlined,
    ),
    'write' => const _ToolCallPresentation(
      categoryLabel: 'Write',
      displayName: 'Write',
      icon: Icons.edit_note_rounded,
    ),
    'edit' => const _ToolCallPresentation(
      categoryLabel: 'Edit',
      displayName: 'Edit',
      icon: Icons.edit_outlined,
    ),
    'multiedit' => const _ToolCallPresentation(
      categoryLabel: 'MultiEdit',
      displayName: 'MultiEdit',
      icon: Icons.edit_note_outlined,
    ),
    'notebookedit' => const _ToolCallPresentation(
      categoryLabel: 'NotebookEdit',
      displayName: 'NotebookEdit',
      icon: Icons.menu_book_outlined,
    ),
    'webfetch' => const _ToolCallPresentation(
      categoryLabel: 'WebFetch',
      displayName: 'WebFetch',
      icon: Icons.language_rounded,
    ),
    'websearch' => const _ToolCallPresentation(
      categoryLabel: 'WebSearch',
      displayName: 'WebSearch',
      icon: Icons.travel_explore_rounded,
    ),
    'todowrite' => const _ToolCallPresentation(
      categoryLabel: 'TodoWrite',
      displayName: 'TodoWrite',
      icon: Icons.checklist_rounded,
    ),
    'task' => const _ToolCallPresentation(
      categoryLabel: 'Task',
      displayName: 'Task',
      icon: Icons.hub_outlined,
    ),
    'glob' => const _ToolCallPresentation(
      categoryLabel: 'Glob',
      displayName: 'Glob',
      icon: Icons.filter_alt_outlined,
    ),
    'exitplanmode' => const _ToolCallPresentation(
      categoryLabel: 'ExitPlanMode',
      displayName: 'ExitPlanMode',
      icon: Icons.assignment_turned_in_outlined,
    ),
    'askuserchoice' => const _ToolCallPresentation(
      categoryLabel: 'AskUserChoice',
      displayName: 'AskUserChoice',
      icon: Icons.quiz_outlined,
    ),
    'toolsearch' => const _ToolCallPresentation(
      categoryLabel: 'ToolSearch',
      displayName: 'ToolSearch',
      icon: Icons.search_rounded,
    ),
    _ => _ToolCallPresentation(
      categoryLabel: AppLocalizations.of(context)!.tlCallTool,
      displayName: rawToolName.isEmpty
          ? AppLocalizations.of(context)!.tlCallTool
          : rawToolName,
      icon: Icons.build_circle_outlined,
    ),
  };
}

class _FormattedToolContent {
  const _FormattedToolContent({required this.text, this.language});

  final String text;
  final String? language;
}

class _FormattedToolContentCacheEntry {
  const _FormattedToolContentCacheEntry({
    required this.content,
    required this.retainedCharacters,
  });

  final _FormattedToolContent content;
  final int retainedCharacters;
}

// AI 流式响应约每 72ms 重建一次；缓存可避免相同工具输出反复执行
// JSON/XML/YAML/TOML 检测。条目数和总字符数同时受限，防止大输出长期驻留。
const int _formatToolContentCacheCap = 128;
const int _formatToolContentCacheMaxCharacters = 4 * kBytesPerMiB;
final LifecycleLruCache<_FormattedToolContentCacheEntry>
_formatToolContentCache = LifecycleLruCache<_FormattedToolContentCacheEntry>(
  maxEntries: _formatToolContentCacheCap,
  maxCost: _formatToolContentCacheMaxCharacters,
  costOf: (entry) => entry.retainedCharacters,
);

_FormattedToolContent _formatToolContent(
  String rawContent, {
  String emptyFallback = '',
}) {
  // Short-circuit: cheap to recompute for tiny strings, and the cache key
  // overhead would dominate.
  if (rawContent.length < 8 && emptyFallback.isEmpty) {
    return _formatToolContentImpl(rawContent, emptyFallback: emptyFallback);
  }
  final cacheKey = emptyFallback.isEmpty
      ? rawContent
      : '${rawContent.length}|$emptyFallback\u0000$rawContent';
  final cached = _formatToolContentCache.get(cacheKey);
  if (cached != null) {
    return cached.content;
  }
  final computed = _formatToolContentImpl(
    rawContent,
    emptyFallback: emptyFallback,
  );
  _formatToolContentCache.put(
    cacheKey,
    _FormattedToolContentCacheEntry(
      content: computed,
      retainedCharacters:
          cacheKey.length +
          computed.text.length +
          (computed.language?.length ?? 0),
    ),
  );
  return computed;
}

_FormattedToolContent _formatToolContentImpl(
  String rawContent, {
  String emptyFallback = '',
}) {
  final normalized = rawContent
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
  final trimmed = normalized.trim();
  if (trimmed.isEmpty) {
    return _FormattedToolContent(text: emptyFallback);
  }
  final legacyToolSearchContent = _tryFormatLegacyToolSearchContent(trimmed);
  if (legacyToolSearchContent != null) {
    return _FormattedToolContent(
      text: legacyToolSearchContent,
      language: 'json',
    );
  }
  final jsonContent = _tryFormatJsonContent(trimmed);
  if (jsonContent != null) {
    return _FormattedToolContent(text: jsonContent, language: 'json');
  }
  final xmlContent = _tryFormatXmlContent(trimmed);
  if (xmlContent != null) {
    return _FormattedToolContent(text: xmlContent, language: 'xml');
  }
  final yamlContent = _tryFormatYamlContent(trimmed);
  if (yamlContent != null) {
    return _FormattedToolContent(text: yamlContent, language: 'yaml');
  }
  if (_looksLikeTomlContent(trimmed)) {
    return _FormattedToolContent(text: normalized, language: 'toml');
  }
  return _FormattedToolContent(text: normalized);
}

String? _tryFormatLegacyToolSearchContent(String content) {
  final headerMatch = _legacyToolSearchHeaderPattern.firstMatch(content);
  if (headerMatch == null) return null;
  final functions = <Map<String, Object?>>[];
  for (final match in _legacyToolSearchFunctionPattern.allMatches(content)) {
    final rawFunction = match.group(1)?.trim();
    if (rawFunction == null || rawFunction.isEmpty) continue;
    try {
      final decoded = jsonDecode(rawFunction);
      if (decoded is Map) {
        functions.add(Map<String, Object?>.from(decoded));
      }
    } catch (_) {
      return null;
    }
  }
  final loadedTools = functions
      .map((item) => '${item['name'] ?? ''}'.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  final matchedCount = int.tryParse(headerMatch.group(1) ?? '') ?? 0;
  final deferredTotal = int.tryParse(headerMatch.group(2) ?? '') ?? 0;
  if (functions.isEmpty && matchedCount > 0) return null;
  return prettyPrintJson(<String, Object?>{
    'tool': 'ToolSearch',
    'status': 'success',
    'matched_count': matchedCount,
    'deferred_total': deferredTotal,
    'loaded_tools': loadedTools,
    'message': matchedCount == 0
        ? 'No deferred tool matched. Try different keywords or select exact names.'
        : 'Call ToolSearch with an exact matched tool_name and schema-matching arguments.',
    'functions': functions,
  });
}

final RegExp _legacyToolSearchHeaderPattern = RegExp(
  r'^ToolSearch (?:loaded|matched) (\d+) of (\d+) deferred runtime tool\(s\)\.',
);
final RegExp _legacyToolSearchFunctionPattern = RegExp(
  r'<function>([\s\S]*?)</function>',
);

String? _tryFormatJsonContent(String content) {
  if (!_looksLikeJsonContent(content)) {
    return null;
  }
  try {
    return prettyPrintJson(jsonDecode(content));
  } catch (_) {
    return null;
  }
}

bool _looksLikeJsonContent(String content) {
  if (content.length < 2) {
    return false;
  }
  final startsWithObject = content.startsWith('{') && content.endsWith('}');
  final startsWithArray = content.startsWith('[') && content.endsWith(']');
  return startsWithObject || startsWithArray;
}

String? _tryFormatXmlContent(String content) {
  if (!_looksLikeXmlContent(content)) {
    return null;
  }
  try {
    return xml.XmlDocument.parse(
      content,
    ).toXmlString(pretty: true, indent: '  ');
  } catch (_) {
    try {
      return xml.XmlDocumentFragment.parse(
        content,
      ).toXmlString(pretty: true, indent: '  ');
    } catch (_) {
      return null;
    }
  }
}

bool _looksLikeXmlContent(String content) {
  return content.startsWith('<') &&
      content.endsWith('>') &&
      _xmlStartTagProbePattern.hasMatch(content);
}

String? _tryFormatYamlContent(String content) {
  if (!_looksLikeYamlContent(content)) {
    return null;
  }
  try {
    final decoded = loadYamlNode(content);
    final value = decoded.value;
    if (value is! YamlMap &&
        value is! YamlList &&
        !_isYamlMultilineScalar(value)) {
      return null;
    }
    return _renderYamlNode(value, 0);
  } catch (_) {
    return null;
  }
}

bool _looksLikeYamlContent(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trimLeft())
      .where((line) => line.isNotEmpty)
      .take(12)
      .toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  var structuredLineCount = 0;
  for (final line in lines) {
    if (line == '---' || line == '...') {
      structuredLineCount += 1;
      continue;
    }
    if (line.startsWith('- ') || _yamlKeyPrefixPattern.hasMatch(line)) {
      structuredLineCount += 1;
    }
  }
  return structuredLineCount > 0;
}

bool _looksLikeTomlContent(String content) {
  final lines = splitTrimmedNonEmpty(
    content,
    separator: '\n',
  ).where((line) => !line.startsWith('#')).take(12).toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  return lines.every(
    (line) =>
        _tomlSectionPattern.hasMatch(line) ||
        _tomlKeyValuePattern.hasMatch(line),
  );
}

bool _isYamlMultilineScalar(Object? value) {
  return value is String && value.contains('\n');
}

String _renderYamlNode(Object? value, int indent) {
  final padding = ' ' * indent;
  if (value is YamlMap) {
    if (value.isEmpty) {
      return '$padding{}';
    }
    final buffer = StringBuffer();
    var isFirst = true;
    for (final entry in value.entries) {
      if (!isFirst) {
        buffer.writeln();
      }
      final key = _renderYamlKey(entry.key);
      final entryValue = entry.value;
      if (_isYamlInlineValue(entryValue)) {
        buffer.write('$padding$key: ${_renderYamlScalar(entryValue)}');
      } else {
        buffer.write(
          '$padding$key:\n${_renderYamlNode(entryValue, indent + 2)}',
        );
      }
      isFirst = false;
    }
    return buffer.toString();
  }
  if (value is YamlList) {
    if (value.isEmpty) {
      return '$padding[]';
    }
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index += 1) {
      if (index > 0) {
        buffer.writeln();
      }
      final item = value[index];
      if (_isYamlInlineValue(item)) {
        buffer.write('$padding- ${_renderYamlScalar(item)}');
      } else {
        buffer.write('$padding-\n${_renderYamlNode(item, indent + 2)}');
      }
    }
    return buffer.toString();
  }
  if (value is String && value.contains('\n')) {
    final childPadding = ' ' * (indent + 2);
    final lines = value.split('\n');
    return '$padding|\n${lines.map((line) => '$childPadding$line').join('\n')}';
  }
  return '$padding${_renderYamlScalar(value)}';
}

bool _isYamlInlineValue(Object? value) {
  return switch (value) {
    null => true,
    bool() => true,
    num() => true,
    String() => !value.contains('\n'),
    _ => false,
  };
}

String _renderYamlKey(Object? value) {
  final key = '${value ?? ''}';
  if (_tomlBareKeyPattern.hasMatch(key)) {
    return key;
  }
  return jsonEncode(key);
}

String _renderYamlScalar(Object? value) {
  return switch (value) {
    null => 'null',
    bool() => value ? 'true' : 'false',
    num() => '$value',
    String() => jsonEncode(value),
    DateTime() => jsonEncode(value.toIso8601String()),
    _ => jsonEncode('$value'),
  };
}

String _toolArgumentsPreview(AiSessionMessage message) {
  final command = _toolExecutionCommand(message);
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) {
        final entries = stringKeyedMapFromValue(decoded).entries.take(2);
        final summary = entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(', ');
        if (summary.isNotEmpty) {
          return summary;
        }
      }
      if (decoded is List) {
        return '[${decoded.length} items]';
      }
    } catch (_) {
      // Fallback to the prettified text preview below.
    }
  }
  final preview = rawArguments.isEmpty ? '{}' : rawArguments;
  return splitTrimmedNonEmpty(preview, separator: '\n').firstOrNull ?? '{}';
}

/// Best-effort parse of top-level argument key/value previews from a
/// JSON-encoded `tool_arguments` blob. Used to surface a real-time
/// preview of which parameters have been parsed during the streaming
/// "constructing" state. Each value is truncated to ~16 chars and
/// nested maps/lists are summarized as `{…}` / `[…]` so the row stays
/// compact.
List<({String key, String? valuePreview})> _parseArgumentKeys(
  String rawArguments,
) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return const <({String key, String? valuePreview})>[];
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return decoded.entries
          .map(
            (e) => (
              key: '${e.key}',
              valuePreview: _summarizeArgumentValue(e.value),
            ),
          )
          .toList(growable: false);
    }
  } catch (_) {
    // Partial JSON mid-stream — expected; fall through.
  }
  return const <({String key, String? valuePreview})>[];
}

String? _summarizeArgumentValue(Object? value) {
  if (value == null) return null;
  if (value is Map) return '{…}';
  if (value is List) return value.isEmpty ? '[]' : '[${value.length}]';
  final raw = value is String ? value : '$value';
  final flat = collapseInlineWhitespace(raw);
  if (flat.isEmpty) return null;
  const maxLen = 16;
  return clipTextByCodeUnits(flat, maxLen, suffix: '…');
}

String _toolCallStatusLabelForData(
  BuildContext context,
  _ToolCallPresentation presentation,
  String status,
  int durationMs,
) {
  final suffix = durationMs <= 0
      ? ''
      : ' (${formatCompactDurationMs(durationMs)})';
  final toolLabel = presentation.displayName.trim().isEmpty
      ? presentation.categoryLabel
      : presentation.displayName.trim();
  final statusLabel = _toolCallStatusActionLabel(
    context,
    status,
    isCommandLike: presentation.isCommandLike,
  );
  return suffix.isEmpty
      ? '$toolLabel · $statusLabel'
      : '$toolLabel · $statusLabel$suffix';
}

String _toolCallStatusActionLabel(
  BuildContext context,
  String status, {
  required bool isCommandLike,
}) {
  return switch (status.toLowerCase()) {
    '' =>
      (isCommandLike
          ? AppLocalizations.of(context)!.tlCallPreparing
          : AppLocalizations.of(context)!.tlCallPreparingAlt),
    'running' || 'pending' || 'in_progress' =>
      (isCommandLike
          ? AppLocalizations.of(context)!.tlCallRunning
          : AppLocalizations.of(context)!.tlCallRunningAlt),
    'cancelled' ||
    'canceled' ||
    'aborted' => AppLocalizations.of(context)!.tlCallStopped,
    'success' || 'ok' || 'completed' =>
      (isCommandLike
          ? AppLocalizations.of(context)!.tlCallCompleted
          : AppLocalizations.of(context)!.tlCallCompletedAlt),
    'denied' || 'blocked' => AppLocalizations.of(context)!.tlCallBlocked,
    'rejected' => AppLocalizations.of(context)!.tlCallRejected,
    'timed_out' =>
      (isCommandLike
          ? AppLocalizations.of(context)!.tlCallTimedOut
          : AppLocalizations.of(context)!.tlCallTimedOutAlt),
    'failed' || 'failure' || 'error' =>
      (isCommandLike
          ? AppLocalizations.of(context)!.tlCallFailed
          : AppLocalizations.of(context)!.tlCallFailedAlt),
    'invalid_arguments' => AppLocalizations.of(context)!.tlCallInvalid,
    _ => AppLocalizations.of(context)!.tlCallToolCall,
  };
}

String _toolExecutionOutcomeLabel(BuildContext context, String status) {
  return switch (status.toLowerCase()) {
    'running' ||
    'pending' ||
    'in_progress' => AppLocalizations.of(context)!.tlCallRunning,
    'cancelled' ||
    'canceled' ||
    'aborted' => AppLocalizations.of(context)!.tlCallStopped,
    'success' ||
    'ok' ||
    'completed' => AppLocalizations.of(context)!.tlCallSucceeded,
    'denied' || 'blocked' => AppLocalizations.of(context)!.tlCallDenied,
    'rejected' => AppLocalizations.of(context)!.tlCallRejected,
    'timed_out' => AppLocalizations.of(context)!.tlCallTimedOut,
    'failed' ||
    'failure' ||
    'error' => AppLocalizations.of(context)!.tlCallFailed,
    'invalid_arguments' => AppLocalizations.of(context)!.tlCallInvalid,
    _ => status,
  };
}

String _toolExecutionPreviewText(
  BuildContext context, {
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = lastNonEmptyLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = lastNonEmptyLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = lastNonEmptyLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (_shouldSweepToolStatus(status)) {
    return AppLocalizations.of(context)!.tlCallToolIsRunningWaitingForOutput;
  }
  return AppLocalizations.of(context)!.tlCallExpandToInspectToolOutput;
}

String lastNonEmptyLine(String content) {
  var lineEnd = content.length;
  while (lineEnd > 0) {
    var lineStart = lineEnd;
    while (lineStart > 0) {
      final unit = content.codeUnitAt(lineStart - 1);
      if (unit == 0x0A || unit == 0x0D) {
        break;
      }
      lineStart -= 1;
    }
    final line = content.substring(lineStart, lineEnd).trim();
    if (line.isNotEmpty) {
      return line;
    }
    while (lineStart > 0) {
      final unit = content.codeUnitAt(lineStart - 1);
      if (unit != 0x0A && unit != 0x0D) {
        break;
      }
      lineStart -= 1;
    }
    lineEnd = lineStart;
  }
  return '';
}

int _toolExecutionDurationMs(AiSessionMessage message) {
  final rawValue =
      message.metadata['tool_execution_elapsed_ms'] ??
      message.metadata['tool_execution_duration_ms'] ??
      0;
  final storedElapsedMs = math.max(
    0,
    optionalRoundedIntFromValue(rawValue) ?? 0,
  );
  final status = _toolExecutionStatus(message);
  final startedAt =
      _toolExecutionStartedAt(message) ??
      (_isLiveToolExecutionStatus(status) ? message.createdAt.toUtc() : null);
  if (_isLiveToolExecutionStatus(status) && startedAt != null) {
    final liveElapsedMs = DateTime.now()
        .toUtc()
        .difference(startedAt)
        .inMilliseconds;
    return math.max(storedElapsedMs, math.max(0, liveElapsedMs));
  }
  if (storedElapsedMs > 0) {
    return storedElapsedMs;
  }
  final finishedAt = _toolExecutionFinishedAt(message);
  if (startedAt != null && finishedAt != null) {
    return math.max(0, finishedAt.difference(startedAt).inMilliseconds);
  }
  return storedElapsedMs;
}

Future<void> _openResolvedMessagePath(
  BuildContext context,
  MessageResolvedPath resolvedPath,
) async {
  try {
    final launched = resolvedPath.isDirectory
        ? await openLocalPathWithSystemApp(
            resolvedPath.resolvedPath,
            tag: 'tool_call_widgets',
          )
        : await revealLocalPathInSystemFileManager(
            resolvedPath.resolvedPath,
            tag: 'tool_call_widgets',
          );
    if (launched) {
      return;
    }
    throw FileSystemException(
      isDesktopPlatform()
          ? 'Unable to open file location.'
          : 'Unsupported platform.',
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

Future<void> _openMessageLinkUri(BuildContext context, Uri uri) async {
  // Restrict the schemes we will hand to the OS launcher. Without this an
  // adversarial markdown link such as `file:///etc/passwd` or
  // `vbscript:msgbox(...)` could be opened verbatim with the user's
  // default handler. Only the schemes that have a sensible “open this”
  // semantic in this product are allowed.
  const allowedSchemes = <String>{'http', 'https', 'mailto', 'file'};
  final scheme = uri.scheme.toLowerCase();
  if (!allowedSchemes.contains(scheme)) {
    if (context.mounted) {
      _showMessageLinkOpenError(
        context,
        FormatException('Unsupported link scheme: $scheme'),
      );
    }
    return;
  }
  try {
    final launched = await openExternalUriWithSystemApp(
      uri,
      tag: 'home_tool_call_widgets.open_link',
    );
    if (launched) {
      return;
    }
    throw const FileSystemException('Unable to open link.');
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

void _showMessageLinkOpenError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  showOpenHandErrorSnack(
    context,
    AppLocalizations.of(context)!.tlCallFailedToOpenFileLocationError(error),
  );
}

class _FilePathMarkdownBuilder extends MarkdownElementBuilder {
  _FilePathMarkdownBuilder({
    required this.textColor,
    required this.inlineCodeBuilder,
    required this.onOpenPath,
  });

  final Color textColor;
  final OpenHandMarkdownInlineCodeBuilder inlineCodeBuilder;
  final Future<void> Function(
    BuildContext context,
    MessageResolvedPath resolvedPath,
  )
  onOpenPath;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == messageResolvedPathElementTag) {
      final path = messageResolvedPathFromElement(element);
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildChip(
              context,
              displayPath: path.displayPath,
              resolvedPath: path.resolvedPath,
              isDirectory: path.isDirectory,
            ),
          ),
        ),
      );
    }

    final path = messagePendingPathFromElement(element);

    return Text.rich(
      WidgetSpan(
        alignment: path.isCodeSpan
            ? PlaceholderAlignment.baseline
            : PlaceholderAlignment.middle,
        baseline: path.isCodeSpan ? TextBaseline.alphabetic : null,
        style: path.isCodeSpan ? inlineCodeBuilder.textStyle : null,
        child: _AsyncFilePathChip(
          normalizedPath: path.normalizedPath,
          candidateRoots: path.candidateRoots,
          fullMatch: path.fullMatch,
          trailing: path.trailing,
          isCodeSpan: path.isCodeSpan,
          parentStyle: parentStyle,
          builder: this,
        ),
      ),
    );
  }

  Widget _buildCodeSpan(String text) => inlineCodeBuilder.buildChip(text);

  Widget _buildChip(
    BuildContext context, {
    required String displayPath,
    required String resolvedPath,
    required bool isDirectory,
    bool isUnresolved = false,
  }) {
    return OpenHandFilePathChip(
      displayPath: displayPath,
      resolvedPath: resolvedPath,
      isDirectory: isDirectory,
      isUnresolved: isUnresolved,
      textColor: textColor,
      onOpen: () {
        // 打开前先标记一次交互，避免 HTML 气泡把这次点击当成"点空白处收起"。
        _markToolCardInteractiveTap(context);
        onOpenPath(
          context,
          MessageResolvedPath(
            displayPath: displayPath,
            resolvedPath: resolvedPath,
            isDirectory: isDirectory,
          ),
        );
      },
    );
  }
}

class _AsyncFilePathChip extends StatefulWidget {
  const _AsyncFilePathChip({
    required this.normalizedPath,
    required this.candidateRoots,
    required this.fullMatch,
    required this.trailing,
    required this.isCodeSpan,
    required this.parentStyle,
    required this.builder,
  });

  final String normalizedPath;
  final List<String> candidateRoots;
  final String fullMatch;
  final String trailing;
  final bool isCodeSpan;
  final TextStyle? parentStyle;
  final _FilePathMarkdownBuilder builder;

  @override
  State<_AsyncFilePathChip> createState() => _AsyncFilePathChipState();
}

class _AsyncFilePathChipState extends State<_AsyncFilePathChip> {
  Future<MessageResolvedPath?>? _future;
  // When the resolution cache already has the answer for the current
  // `(normalizedPath, candidateRoots)` pair, we skip the FutureBuilder
  // entirely and render synchronously.  This avoids the extra "loading"
  // build frame that FutureBuilder always triggers (even when the future
  // is already completed), and more importantly spares the cascade of
  // 10+ setState pulses during the initial transcript paint when many
  // chips all resolve at once.
  bool _resolvedSync = false;
  MessageResolvedPath? _syncValue;

  void _primeFromCacheOrStartFuture() {
    final probe = lookupResolvedMessagePathFromCache(
      widget.normalizedPath,
      widget.candidateRoots,
    );
    if (probe.hit) {
      _resolvedSync = true;
      _syncValue = probe.value;
      _future = null;
      return;
    }
    _resolvedSync = false;
    _syncValue = null;
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void initState() {
    super.initState();
    _primeFromCacheOrStartFuture();
  }

  @override
  void didUpdateWidget(_AsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _primeFromCacheOrStartFuture();
    }
  }

  Widget _renderResolved(
    BuildContext context,
    MessageResolvedPath? resolvedPath,
  ) {
    if (resolvedPath == null) {
      if (widget.isCodeSpan) {
        return widget.builder._buildCodeSpan(widget.fullMatch);
      }
      final isExplicitPath =
          widget.normalizedPath.startsWith('~/') ||
          widget.normalizedPath.startsWith('./') ||
          widget.normalizedPath.startsWith('../') ||
          looksLikeAbsoluteMessagePath(widget.normalizedPath);
      if (isExplicitPath) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: widget.builder._buildChip(
                  context,
                  displayPath: widget.normalizedPath,
                  resolvedPath: widget.normalizedPath,
                  isDirectory: widget.trailing.contains('/'),
                  isUnresolved: true,
                ),
              ),
            ),
            if (widget.trailing.isNotEmpty)
              Text(widget.trailing, style: widget.parentStyle),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(widget.fullMatch, style: widget.parentStyle),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: widget.builder._buildChip(
              context,
              displayPath: resolvedPath.displayPath,
              resolvedPath: resolvedPath.resolvedPath,
              isDirectory: resolvedPath.isDirectory,
            ),
          ),
        ),
        if (widget.trailing.isNotEmpty)
          Text(widget.trailing, style: widget.parentStyle),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedSync) {
      return _renderResolved(context, _syncValue);
    }
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        return _renderResolved(context, snapshot.data);
      },
    );
  }
}

class _SelfLearningCard extends StatefulWidget {
  const _SelfLearningCard({required this.message});

  final AiSessionMessage message;

  @override
  State<_SelfLearningCard> createState() => _SelfLearningCardState();
}

class _SelfLearningCardState extends State<_SelfLearningCard> {
  bool _profileChangesExpanded = false;
  bool _memoriesExpanded = false;
  bool _skillsExpanded = false;
  bool _profileExpanded = false;
  bool _responseExpanded = false;
  bool _reasoningExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final metadata = widget.message.metadata;
    final memoryItems = _extractChangeItems(metadata['memory_changes']);
    final skillItems = _extractChangeItems(metadata['skill_changes']);
    final profileItems = _extractChangeItems(metadata['profile_changes']);
    final profileDiff = _extractProfileDiff(metadata['profile_diff']);
    final aiResponse = _extractProfileDiff(metadata['ai_response']);
    final aiReasoning = _extractProfileDiff(metadata['ai_reasoning']);
    final status = metadata['status']?.toString() ?? '';
    final isStreaming = metadata['streaming'] == true;
    final elapsedLabel = _formatSelfLearningElapsed(
      context,
      widget.message.createdAt,
    );
    final memoryCountLabel = AppLocalizations.of(
      context,
    )!.tlCallMemoryitemsLengthMemoriesUpdated(memoryItems.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelfLearningHeaderRow(
          icon: Icons.psychology_alt_rounded,
          label: AppLocalizations.of(context)!.tlCallSelfLearning,
          color: colorScheme.tertiary,
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (profileItems.isNotEmpty)
              OpenHandToolChip(
                icon: Icons.account_circle_outlined,
                label: AppLocalizations.of(
                  context,
                )!.tlCallProfileitemsLengthProfileChanges(profileItems.length),
              ),
            OpenHandToolChip(
              icon: Icons.memory_rounded,
              label: memoryCountLabel,
            ),
            if (skillItems.isNotEmpty)
              OpenHandToolChip(
                icon: Icons.extension_rounded,
                label: AppLocalizations.of(
                  context,
                )!.tlCallSkillitemsLengthSkillsUpdated(skillItems.length),
              ),
            OpenHandToolChip(icon: Icons.schedule_rounded, label: elapsedLabel),
            if (metadata['nudge_recovered'] == true)
              OpenHandToolChip(
                icon: Icons.refresh_rounded,
                label: AppLocalizations.of(context)!.tlCallNudgeRecovered,
              ),
          ],
        ),
        kOpenHandGap10,
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallProfileChanges,
          preview: _changeItemsPreview(context, profileItems),
          expanded: _profileChangesExpanded,
          onToggle: () {
            setState(() {
              _profileChangesExpanded = !_profileChangesExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: profileItems),
        ),
        kOpenHandGap10,
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallMemoryChanges,
          preview: _changeItemsPreview(context, memoryItems),
          expanded: _memoriesExpanded,
          onToggle: () {
            setState(() {
              _memoriesExpanded = !_memoriesExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: memoryItems),
        ),
        kOpenHandGap10,
        _ExpandableToolSection(
          title: AppLocalizations.of(context)!.tlCallSkillChanges,
          preview: _changeItemsPreview(context, skillItems),
          expanded: _skillsExpanded,
          onToggle: () {
            setState(() {
              _skillsExpanded = !_skillsExpanded;
            });
          },
          expandedBuilder: (context) =>
              _SelfLearningChangeList(items: skillItems),
        ),
        if (profileDiff.isNotEmpty) ...[
          kOpenHandGap10,
          _ExpandableToolSection(
            title: AppLocalizations.of(context)!.tlCallProfileDiff,
            preview: profileDiff,
            expanded: _profileExpanded,
            onToggle: () {
              setState(() {
                _profileExpanded = !_profileExpanded;
              });
            },
            expandedBuilder: (context) => Text(
              profileDiff,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
        ],
        if (aiReasoning.isNotEmpty) ...[
          kOpenHandGap10,
          _ExpandableToolSection(
            title: (isStreaming
                ? AppLocalizations.of(context)!.tlCallAiThinkingStreaming
                : AppLocalizations.of(context)!.tlCallAiThinking),
            preview: _previewText(aiReasoning),
            expanded: _reasoningExpanded,
            onToggle: () {
              setState(() {
                _reasoningExpanded = !_reasoningExpanded;
              });
            },
            expandedBuilder: (context) => isStreaming
                ? StreamingTextRevealText(
                    text: aiReasoning,
                    streaming: true,
                    animateSize: false,
                    builder: (context, visibleText) => _SelfLearningMarkdown(
                      data: visibleText.isEmpty ? ' ' : visibleText,
                      muted: true,
                    ),
                  )
                : _SelfLearningMarkdown(data: aiReasoning, muted: true),
          ),
        ],
        if (aiResponse.isNotEmpty) ...[
          kOpenHandGap10,
          _ExpandableToolSection(
            title: (isStreaming
                ? AppLocalizations.of(context)!.tlCallAiResponseStreaming
                : AppLocalizations.of(context)!.tlCallAiResponse),
            preview: _previewText(aiResponse),
            expanded: _responseExpanded,
            onToggle: () {
              setState(() {
                _responseExpanded = !_responseExpanded;
              });
            },
            expandedBuilder: (context) => isStreaming
                ? StreamingTextRevealText(
                    text: aiResponse,
                    streaming: true,
                    animateSize: false,
                    builder: (context, visibleText) => _SelfLearningMarkdown(
                      data: visibleText.isEmpty ? ' ' : visibleText,
                      muted: false,
                    ),
                  )
                : _SelfLearningMarkdown(data: aiResponse, muted: false),
          ),
        ],
        if (status == 'error' && aiResponse.isEmpty) ...[
          kOpenHandGap10,
          Text(
            widget.message.content,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              height: 1.45,
            ),
          ),
        ] else if (status != 'error' &&
            !isStreaming &&
            aiResponse.isEmpty &&
            aiReasoning.isEmpty &&
            profileItems.isEmpty &&
            memoryItems.isEmpty &&
            skillItems.isEmpty &&
            widget.message.content.trim().isNotEmpty) ...[
          // 兜底说明：当本轮成功结束（status != 'error'）但模型
          // 既没有调用任何工具，也没有产生 AI 文本/思考输出时，避免卡片只剩
          // "无变更" 三连而让用户误以为是 BUG。把 message.content 作为简要
          // 说明展示出来（通常是 dispatcher 给出的 "模型本轮未调用任何工具…"
          // 这类文案，或后端返回的 finish_reason 提示）。
          kOpenHandGap10,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: kOpenHandBorderRadius10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    widget.message.content,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders self-learning AI 思考 / AI 响应 with Markdown — reuses the same
/// `_SafeMarkdownBody` engine the main message bubble uses, so code fences,
/// lists and emphasis get full syntax-highlighted treatment instead of the
/// previous plain `SelectableText`.
///
/// Wrapped in [AnimatedSize] so as the dispatcher streams token-deltas in
/// (and the parent's metadata grows), the card height eases out with a
/// gentle Q-bouncy easeOutCubicEmphasized curve instead of jumping.
class _SelfLearningMarkdown extends StatelessWidget {
  const _SelfLearningMarkdown({required this.data, required this.muted});

  final String data;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    final styleSheet = muted
        ? base.copyWith(
            p: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : base.copyWith(p: theme.textTheme.bodyMedium?.copyWith(height: 1.5));
    return ClipRect(
      child: AnimatedSize(
        duration: openHandMotionDuration(context, _kToolCompactMotionDuration),
        curve: _kToolCardMotionCurve,
        alignment: Alignment.topLeft,
        child: _SafeMarkdownBody(
          data: data.isEmpty ? ' ' : data,
          styleSheet: styleSheet,
          selectable: true,
        ),
      ),
    );
  }
}

/// 生成折叠卡片标题使用的单行预览，超过 120 个代码单元时截断。
String _previewText(String text) {
  final collapsed = collapseInlineWhitespace(text);
  return clipTextByCodeUnits(collapsed, 120, suffix: '…');
}

/// Header row for the self-learning card. Intentionally matches the visual
/// weight of [_MessageMetaRow] but uses a tinted capsule so the colour slot
/// used by the card (tertiary) is clearly differentiated from tool calls
/// (secondary).
class _SelfLearningHeaderRow extends StatelessWidget {
  const _SelfLearningHeaderRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          kOpenHandHGap8,
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a list of self-learning change entries. Each entry is either a
/// bare id string or a map with `id` / `summary` keys; the summary — when
/// present — is shown in a muted style beneath the id.
class _SelfLearningChangeList extends StatelessWidget {
  const _SelfLearningChangeList({required this.items});

  final List<_SelfLearningChangeItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        AppLocalizations.of(context)!.tlCallNoChanges,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) kOpenHandGap10,
          _SelfLearningChangeTile(item: items[i]),
        ],
      ],
    );
  }
}

class _SelfLearningChangeTile extends StatelessWidget {
  const _SelfLearningChangeTile({required this.item});

  final _SelfLearningChangeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: theme.colorScheme.tertiary,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.id.isEmpty
                    ? AppLocalizations.of(context)!.tlCallUnnamed
                    : item.id,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
              ),
              if (item.summary.isNotEmpty) ...[
                kOpenHandGap2,
                Text(
                  item.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SelfLearningChangeItem {
  const _SelfLearningChangeItem({required this.id, required this.summary});

  final String id;
  final String summary;
}

/// Coerces `memory_changes` / `skill_changes` metadata into a list of
/// [_SelfLearningChangeItem]. Accepts any of the following shapes:
///
///   - `List<String>` → each becomes an id-only item.
///   - `List<Map>`    → reads `id` and `summary` defensively.
///   - `int`          → returns that many placeholder items so the header
///                      count matches the list length (ids unknown).
///   - any other type → empty list.
List<_SelfLearningChangeItem> _extractChangeItems(Object? raw) {
  if (raw is List) {
    final items = <_SelfLearningChangeItem>[];
    for (final entry in raw) {
      if (entry is String) {
        items.add(_SelfLearningChangeItem(id: entry.trim(), summary: ''));
      } else if (entry is Map) {
        final id = '${entry['id'] ?? ''}'.trim();
        final summary = '${entry['summary'] ?? ''}'.trim();
        items.add(_SelfLearningChangeItem(id: id, summary: summary));
      }
    }
    return items;
  }
  if (raw is int && raw > 0) {
    return List<_SelfLearningChangeItem>.generate(
      raw,
      (_) => const _SelfLearningChangeItem(id: '', summary: ''),
    );
  }
  return const <_SelfLearningChangeItem>[];
}

String _extractProfileDiff(Object? raw) {
  if (raw is String) {
    return raw.trim();
  }
  if (raw is Map) {
    final summary = '${raw['summary'] ?? ''}'.trim();
    if (summary.isNotEmpty) return summary;
    // Fallback: render a compact "key: value" preview if the map has
    // primitive entries. Keeps the UI useful when the agent emits a
    // structured diff instead of a pre-written paragraph.
    final parts = <String>[];
    raw.forEach((key, value) {
      if (value is String || value is num || value is bool) {
        parts.add('$key: $value');
      }
    });
    return parts.join(' · ');
  }
  return '';
}

String _changeItemsPreview(
  BuildContext context,
  List<_SelfLearningChangeItem> items,
) {
  if (items.isEmpty) {
    return AppLocalizations.of(context)!.tlCallNoChanges;
  }
  final names = items
      .map((item) => item.id.isEmpty ? '—' : item.id)
      .take(3)
      .join(', ');
  final suffix = items.length > 3
      ? AppLocalizations.of(
          context,
        )!.tlCallAndItemsLength3More(items.length - 3, items.length)
      : '';
  return '$names$suffix';
}

/// Formats the elapsed time since [createdAt] into a short relative label.
/// Mirrors the bilingual convention used elsewhere in the home feature
/// (e.g. the reasoning meta row) instead of the absolute timestamp used in
/// the message footer, because the spec calls for a relative elapsed hint.
String _formatSelfLearningElapsed(BuildContext context, DateTime createdAt) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(createdAt.toUtc());
  if (diff.isNegative || diff.inSeconds < 5) {
    return AppLocalizations.of(context)!.tlCallJustNow;
  }
  if (diff.inMinutes < 1) {
    final seconds = diff.inSeconds;
    return AppLocalizations.of(context)!.tlCallSecondsSAgo(seconds);
  }
  if (diff.inHours < 1) {
    final minutes = diff.inMinutes;
    return AppLocalizations.of(context)!.tlCallMinutesMAgo(minutes);
  }
  if (diff.inDays < 1) {
    final hours = diff.inHours;
    return AppLocalizations.of(context)!.tlCallHoursHAgo(hours);
  }
  final days = diff.inDays;
  return AppLocalizations.of(context)!.tlCallDaysDAgo(days);
}

/// 把文件差异预览加载失败的常见 dart:io 异常翻译成简短用户文案，
/// 替代直接 `e.toString()` 把 `FileSystemException(...)` 暴露给用户。
String _friendlyFileDiffError(BuildContext context, Object error) {
  if (error is BoundedFileReadException) {
    final limit = formatByteSize(error.maxBytes);
    return openHandLocalizedText(
      context,
      zh: '文件超过 $limit，无法安全生成差异预览。',
      zhHant: '檔案超過 $limit，無法安全產生差異預覽。',
      en: 'The file exceeds $limit and cannot be previewed safely.',
      fr: 'Le fichier dépasse $limit et ne peut pas être prévisualisé en toute sécurité.',
      de: 'Die Datei überschreitet $limit und kann nicht sicher angezeigt werden.',
      ja: 'ファイルが $limit を超えているため、安全にプレビューできません。',
    );
  }
  final raw = error.toString();
  if (raw.startsWith('PathNotFoundException') ||
      raw.contains('No such file or directory')) {
    return openHandLocalizedText(
      context,
      zh: '文件已不存在或路径已被移动。\n原始错误：$raw',
      zhHant: '檔案已不存在或路徑已被移動。\n原始錯誤：$raw',
      en: 'File no longer exists or has been moved.\nRaw: $raw',
      fr: 'Le fichier n’existe plus ou a été déplacé.\nBrut : $raw',
      de: 'Die Datei existiert nicht mehr oder wurde verschoben.\nRohdaten: $raw',
      ja: 'ファイルは存在しないか移動されました。\nRaw: $raw',
    );
  }
  if (raw.startsWith('FileSystemException')) {
    return openHandLocalizedText(
      context,
      zh: '文件系统操作失败 (可能是权限不足 / 磁盘已满 / 路径被占用)。\n原始错误：$raw',
      zhHant: '檔案系統操作失敗 (可能是權限不足 / 磁碟已滿 / 路徑被占用)。\n原始錯誤：$raw',
      en: 'Filesystem operation failed (permission, disk space, or lock).\nRaw: $raw',
      fr: 'L’opération du système de fichiers a échoué (droits, espace disque ou verrou).\nBrut : $raw',
      de: 'Dateisystemvorgang fehlgeschlagen (Berechtigung, Speicherplatz oder Sperre).\nRohdaten: $raw',
      ja: 'ファイルシステム操作に失敗しました (権限、空き容量、ロックの可能性)。\nRaw: $raw',
    );
  }
  return raw;
}

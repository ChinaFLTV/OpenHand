part of 'harness_session_dashboard.dart';

/// 工具轨迹展开 / 预览互换的时长与上滑幅度。
const Duration _kToolTraceSwitchDuration = kOpenHandMotion240;
const double _kToolTraceSlideOffsetY = 0.04;

class _HeApiToolCallMeta {
  const _HeApiToolCallMeta({
    required this.argumentsJson,
    required this.status,
    required this.durationMs,
    required this.exitCode,
    required this.command,
    required this.workingDirectory,
  });

  final String argumentsJson;
  final String status;
  final int durationMs;
  final int? exitCode;
  final String command;
  final String workingDirectory;

  /// Scans [lines] for 📥/📤 markers, removes them in-place, and returns
  /// the extracted metadata. Returns `null` if no markers were found.
  static _HeApiToolCallMeta? tryExtract(List<String> lines) {
    String? argsRaw;
    String? statusLine;
    int? argsIndex;
    int? statusIndex;

    for (var i = 0; i < lines.length; i++) {
      if (argsRaw == null) {
        final m = _heApiArgsMarker.firstMatch(lines[i]);
        if (m != null) {
          argsRaw = m.group(1)!.trim();
          argsIndex = i;
          continue;
        }
      }
      if (statusLine == null) {
        final m = _heApiStatusMarker.firstMatch(lines[i]);
        if (m != null) {
          statusLine = m.group(1)!.trim();
          statusIndex = i;
          continue;
        }
      }
      if (argsRaw != null && statusLine != null) break;
    }

    if (argsRaw == null && statusLine == null) return null;

    // Remove marker lines from the list (in reverse order to keep indices
    // stable).
    final indicesToRemove = <int>[
      if (statusIndex != null) statusIndex,
      if (argsIndex != null) argsIndex,
    ]..sort((a, b) => b.compareTo(a));
    for (final idx in indicesToRemove) {
      lines.removeAt(idx);
    }

    // Parse arguments JSON — pretty-print for display.
    var argumentsJson = '';
    if (argsRaw != null && argsRaw.isNotEmpty) {
      argumentsJson = formatStructuredTextForDisplay(argsRaw).text;
    }

    // Parse status line: "status: succeeded | 150ms | exit: 0 | cmd: ... | cwd: ..."
    var status = '';
    var durationMs = 0;
    int? exitCode;
    var command = '';
    var workingDirectory = '';

    if (statusLine != null) {
      final parts = splitTrimmed(statusLine, separator: '|');
      for (final part in parts) {
        if (part.startsWith('status:')) {
          status = _heNormalizeToolStatus(
            part.substring('status:'.length).trim(),
          );
        } else if (part.endsWith('ms')) {
          final digits = part.replaceAll(RegExp(r'[^0-9]'), '');
          durationMs = intFromValue(digits, fallback: 0);
        } else if (part.startsWith('exit:')) {
          exitCode = optionalIntFromValue(part.substring('exit:'.length));
        } else if (part.startsWith('cmd:')) {
          command = part.substring('cmd:'.length).trim();
        } else if (part.startsWith('cwd:')) {
          workingDirectory = part.substring('cwd:'.length).trim();
        }
      }
    }

    return _HeApiToolCallMeta(
      argumentsJson: argumentsJson,
      status: status,
      durationMs: durationMs,
      exitCode: exitCode,
      command: command,
      workingDirectory: workingDirectory,
    );
  }
}

final RegExp _heToolStatusPattern = RegExp(
  r'\b(succeeded|failed|timed out|timed-out|cancelled|canceled|denied|rejected|blocked)(?:\s+in\s+([0-9]+(?:\.[0-9]+)?(?:ms|s|sec|secs|m|min|mins)))?\b',
  caseSensitive: false,
);

final RegExp _heToolExitCodePattern = RegExp(
  r'(?:exit(?:\s+code)?|code)\s*[:=]\s*(-?\d+)',
  caseSensitive: false,
);

class _HeToolPresentation {
  const _HeToolPresentation({
    required this.label,
    required this.icon,
    required this.isCommandLike,
  });

  final String label;
  final IconData icon;
  final bool isCommandLike;
}

class _HeParsedToolHeader {
  const _HeParsedToolHeader({
    required this.command,
    required this.workingDirectory,
    required this.status,
    required this.durationMs,
    required this.inlineResult,
  });

  final String command;
  final String workingDirectory;
  final String status;
  final int durationMs;
  final String inlineResult;

  static _HeParsedToolHeader? tryParse(
    String line, {
    required bool isStreaming,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final statusMatch = _heToolStatusPattern.firstMatch(trimmed);
    var prefix = trimmed;
    var status = '';
    var durationMs = 0;
    var inlineResult = '';

    if (statusMatch != null) {
      status = _heNormalizeToolStatus(statusMatch.group(1) ?? '');
      durationMs = _heParseToolDurationToMs(statusMatch.group(2) ?? '');
      prefix = trimmed.substring(0, statusMatch.start).trimRight();
      var trailing = trimmed.substring(statusMatch.end).trimLeft();
      if (trailing.startsWith(':')) {
        trailing = trailing.substring(1).trimLeft();
      }
      inlineResult = trailing;
    }

    final split = _heSplitToolCommandAndDirectory(prefix);
    final command = split?.command ?? prefix;
    final workingDirectory = split?.workingDirectory ?? '';
    final looksLikeHeader = split != null || _heLooksLikeToolCommand(command);
    if (!looksLikeHeader) {
      return null;
    }

    return _HeParsedToolHeader(
      command: command,
      workingDirectory: workingDirectory,
      status: status.isEmpty && isStreaming ? 'running' : status,
      durationMs: durationMs,
      inlineResult: inlineResult,
    );
  }
}

class _HeStructuredToolTrace {
  const _HeStructuredToolTrace({
    required this.presentation,
    required this.status,
    required this.durationMs,
    required this.command,
    required this.workingDirectory,
    required this.argumentsText,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.statusIcon,
    required this.headerLabel,
    required this.outcomeLabel,
    required this.inputPreview,
    required this.outputPreview,
  });

  factory _HeStructuredToolTrace.fromSegment(
    _HeOutputSegment segment, {
    required BuildContext context,
    required bool isStreaming,
  }) {
    final lines = List<String>.from(segment.lines);

    // ── Try extracting structured markers emitted by HarnessApiPhaseRunner ──
    // Format:  📥 {json}          ← tool arguments
    //          📤 status: ... | duration | exit: N | cmd: ... | cwd: ...
    //          {output lines...}
    final apiMeta = _HeApiToolCallMeta.tryExtract(lines);

    final firstContentIndex = _heIndexOfFirstMeaningfulLine(lines);
    final firstContentLine = firstContentIndex >= 0
        ? lines[firstContentIndex].trim()
        : '';
    final parsedHeader = apiMeta != null
        ? null // Skip CLI header parsing when structured API markers exist.
        : _HeParsedToolHeader.tryParse(
            firstContentLine,
            isStreaming: isStreaming,
          );
    final presentation = _heToolPresentationForSegment(
      segment,
      parsedHeader,
      context: context,
    );

    final outputLines = <String>[];
    if (apiMeta != null) {
      // Structured API path — remaining lines (after marker extraction) are
      // pure tool output.
      outputLines.addAll(lines);
    } else if (parsedHeader != null) {
      if (parsedHeader.inlineResult.isNotEmpty) {
        outputLines.add(parsedHeader.inlineResult);
      }
      if (firstContentIndex >= 0 && firstContentIndex + 1 < lines.length) {
        outputLines.addAll(lines.skip(firstContentIndex + 1));
      }
    } else if (segment.kind == _HeSegmentKind.toolResult) {
      outputLines.addAll(lines);
    } else if (segment.kind == _HeSegmentKind.toolCall && lines.isNotEmpty) {
      outputLines.addAll(lines);
    }

    final outputText = _heNormalizeToolText(outputLines.join('\n'));
    final exitCode = apiMeta?.exitCode ?? _heExtractToolExitCode(outputLines);
    var status = apiMeta?.status ?? parsedHeader?.status ?? '';

    // If no status from header, try to extract from output lines.
    if (status.isEmpty) {
      status = _heExtractStatusFromLines(outputLines);
    }

    if (status.isEmpty && isStreaming) {
      status = 'running';
    }
    if (status.isEmpty && exitCode != null) {
      status = exitCode == 0 ? 'success' : 'failed';
    }
    if (status.isEmpty &&
        segment.kind == _HeSegmentKind.toolResult &&
        outputText.isNotEmpty) {
      status = 'success';
    }

    final useErrorChannel =
        status == 'failed' ||
        status == 'timed_out' ||
        status == 'denied' ||
        status == 'rejected';
    final stdout =
        segment.kind != _HeSegmentKind.toolResult &&
            outputText.isNotEmpty &&
            !useErrorChannel
        ? outputText
        : '';
    final stderr = outputText.isNotEmpty && useErrorChannel ? outputText : '';
    final resultText =
        segment.kind == _HeSegmentKind.toolResult && stderr.isEmpty
        ? outputText
        : '';

    final argumentsText =
        apiMeta?.argumentsJson ??
        _heBuildStructuredToolArguments(segment, parsedHeader);
    final command = apiMeta?.command ?? parsedHeader?.command ?? '';
    final workingDirectory =
        apiMeta?.workingDirectory ?? parsedHeader?.workingDirectory ?? '';
    final durationMs = apiMeta?.durationMs ?? parsedHeader?.durationMs ?? 0;
    final actionLabel = _heToolActionLabel(
      context: context,
      status: status,
      isCommandLike: presentation.isCommandLike,
    );
    final durationSuffix = durationMs > 0
        ? ' (${_heFormatToolDuration(durationMs)})'
        : '';

    return _HeStructuredToolTrace(
      presentation: presentation,
      status: status,
      durationMs: durationMs,
      command: command,
      workingDirectory: workingDirectory,
      argumentsText: argumentsText,
      stdout: _heFormatStructuredToolContent(stdout),
      stderr: _heFormatStructuredToolContent(stderr),
      resultText: _heFormatStructuredToolContent(resultText),
      exitCode: exitCode,
      statusIcon: _heToolStatusIcon(status),
      headerLabel: '${presentation.label} · $actionLabel$durationSuffix',
      outcomeLabel: _heToolOutcomeLabel(context: context, status: status),
      inputPreview: _heBuildStructuredToolInputPreview(
        command: command,
        argumentsText: argumentsText,
      ),
      outputPreview: _heBuildStructuredToolOutputPreview(
        context: context,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
  }

  final _HeToolPresentation presentation;
  final String status;
  final int durationMs;
  final String command;
  final String workingDirectory;
  final String argumentsText;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final IconData statusIcon;
  final String headerLabel;
  final String outcomeLabel;
  final String inputPreview;
  final String outputPreview;

  bool get hasInputSection =>
      command.isNotEmpty || argumentsText.trim().isNotEmpty;

  bool get hasOutputSection =>
      stdout.isNotEmpty ||
      stderr.isNotEmpty ||
      resultText.isNotEmpty ||
      status.isNotEmpty ||
      exitCode != null;
}

class _HeStructuredToolTraceCard extends StatefulWidget {
  const _HeStructuredToolTraceCard({
    required this.segment,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.isStreaming,
  });

  final _HeOutputSegment segment;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool isStreaming;

  @override
  State<_HeStructuredToolTraceCard> createState() =>
      _HeStructuredToolTraceCardState();
}

class _HeStructuredToolTraceCardState
    extends State<_HeStructuredToolTraceCard> {
  bool _inputExpanded = false;
  bool _outputExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final data = _HeStructuredToolTrace.fromSegment(
      widget.segment,
      context: context,
      isStreaming: widget.isStreaming,
    );
    final isToolCall = widget.segment.kind == _HeSegmentKind.toolCall;
    final cardColor = isToolCall
        ? Color.alphaBlend(
            colorScheme.secondary.withValues(alpha: 0.14),
            colorScheme.surfaceContainerHighest,
          )
        : colorScheme.surfaceContainerHigh;
    final borderColor = isToolCall
        ? colorScheme.secondary.withValues(alpha: 0.28)
        : colorScheme.outlineVariant.withValues(alpha: 0.28);
    final textColor = isToolCall
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final subtleSurface = Color.alphaBlend(
      Colors.white.withValues(
        alpha: widget.theme.brightness == Brightness.dark ? 0.05 : 0.55,
      ),
      cardColor,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: _br26,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: widget.theme.brightness == Brightness.dark ? 0.05 : 0.035,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: subtleSurface,
                borderRadius: kOpenHandPillBorderRadius,
                border: Border.all(color: borderColor.withValues(alpha: 0.7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.statusIcon, size: 18, color: textColor),
                  kOpenHandHGap8,
                  Flexible(
                    child: Text(
                      data.headerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.theme.textTheme.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandGap10,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OpenHandToolChip(
                  icon: data.presentation.icon,
                  label: data.presentation.label,
                ),
                if (data.workingDirectory.isNotEmpty)
                  OpenHandToolChip(
                    icon: Icons.folder_outlined,
                    label:
                        '${openHandLocalizedText(context, zh: '目录', zhHant: '目錄', en: 'Dir', fr: 'Dossier', de: 'Verzeichnis', ja: 'ディレクトリ')}: ${data.workingDirectory}',
                  ),
                if (data.outcomeLabel.isNotEmpty)
                  OpenHandToolChip(
                    icon: data.statusIcon,
                    label: data.outcomeLabel,
                  ),
                if (data.durationMs > 0 || data.status == 'running')
                  OpenHandToolChip(
                    icon: Icons.timer_outlined,
                    label:
                        '${openHandLocalizedText(context, zh: '耗时', zhHant: '耗時', en: 'Elapsed', fr: 'Durée', de: 'Dauer', ja: '経過')}: ${_heFormatToolDuration(data.durationMs)}',
                  ),
                if (data.exitCode != null)
                  OpenHandToolChip(
                    icon: Icons.flag_outlined,
                    label:
                        '${openHandLocalizedText(context, zh: '退出码', zhHant: '退出碼', en: 'Exit', fr: 'Code de sortie', de: 'Exitcode', ja: '終了コード')}: ${data.exitCode}',
                  ),
              ],
            ),
            if (data.hasInputSection) ...[
              kOpenHandGap10,
              _HeStructuredToolSection(
                title: openHandLocalizedText(
                  context,
                  zh: '工具入参',
                  zhHant: '工具輸入',
                  en: 'Tool Input',
                  fr: 'Entrée outil',
                  de: 'Tool-Eingabe',
                  ja: 'ツール入力',
                ),
                preview: data.inputPreview,
                expanded: _inputExpanded,
                onToggle: () {
                  setState(() {
                    _inputExpanded = !_inputExpanded;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.command.isNotEmpty)
                      _HeToolTextPanel(
                        label: 'command',
                        content: '\$ ${data.command}',
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    if (data.command.isNotEmpty) kOpenHandGap10,
                    if (data.argumentsText.trim().isNotEmpty)
                      _HeToolTextPanel(
                        label: 'arguments',
                        content: data.argumentsText,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
              ),
            ],
            if (data.hasOutputSection) ...[
              kOpenHandGap10,
              _HeStructuredToolSection(
                title: openHandLocalizedText(
                  context,
                  zh: '结果输出',
                  zhHant: '結果輸出',
                  en: 'Tool Output',
                  fr: 'Sortie outil',
                  de: 'Tool-Ausgabe',
                  ja: 'ツール出力',
                ),
                preview: data.outputPreview,
                expanded: _outputExpanded,
                onToggle: () {
                  setState(() {
                    _outputExpanded = !_outputExpanded;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.stdout.isNotEmpty)
                      _HeToolTextPanel(
                        label: 'stdout',
                        content: data.stdout,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    if (data.stderr.isNotEmpty) ...[
                      if (data.stdout.isNotEmpty) kOpenHandGap10,
                      _HeToolTextPanel(
                        label: 'stderr',
                        content: data.stderr,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                        isError: true,
                      ),
                    ],
                    if (data.resultText.isNotEmpty) ...[
                      if (data.stdout.isNotEmpty || data.stderr.isNotEmpty)
                        kOpenHandGap10,
                      _HeToolTextPanel(
                        label: 'result',
                        content: data.resultText,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    ],
                    if (data.stdout.isEmpty &&
                        data.stderr.isEmpty &&
                        data.resultText.isEmpty)
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '当前还没有工具输出。',
                          zhHant: '目前還沒有工具輸出。',
                          en: 'There is no tool output yet.',
                          fr: 'Aucune sortie outil pour le moment.',
                          de: 'Noch keine Tool-Ausgabe vorhanden.',
                          ja: 'まだツール出力はありません。',
                        ),
                        style: widget.theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeStructuredToolSection extends StatelessWidget {
  const _HeStructuredToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPreview = preview.trim().isNotEmpty;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      borderRadius: kOpenHandBorderRadius16,
      child: InkWell(
        onTap: onToggle,
        borderRadius: kOpenHandBorderRadius16,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion240),
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedExpandChevron(
                      expanded: expanded,
                      color: theme.colorScheme.onSurfaceVariant,
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
                OpenHandCrossFadeSwitcher(
                  duration: _kToolTraceSwitchDuration,
                  slideBeginOffsetY: _kToolTraceSlideOffsetY,
                  child: expanded
                      ? Padding(
                          key: const ValueKey<String>('expanded'),
                          padding: const EdgeInsets.only(top: 12),
                          child: child,
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
                              color: theme.colorScheme.onSurfaceVariant,
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

class _HeToolTextPanel extends StatefulWidget {
  const _HeToolTextPanel({
    required this.label,
    required this.content,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.isError = false,
  });

  final String label;
  final String content;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool isError;

  @override
  State<_HeToolTextPanel> createState() => _HeToolTextPanelState();
}

class _HeToolTextPanelState extends State<_HeToolTextPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final normalized = widget.content.trimRight();
    final lines = const LineSplitter().convert(normalized);
    final isLong = normalized.length > 900 || lines.length > 18;
    final displayText = isLong && !_expanded
        ? '${lines.take(15).join('\n')}\n\n... [${openHandLocalizedText(context, zh: '已折叠，点击右上角展开完整内容', zhHant: '已摺疊，點擊右上角展開完整內容', en: 'collapsed, expand to view the full content', fr: 'replié, développez pour voir le contenu complet', de: 'eingeklappt, zum vollständigen Inhalt erweitern', ja: '折りたたみ済み、右上から全文を展開')}]'
        : normalized;
    final accentColor = widget.isError
        ? widget.colorScheme.error
        : widget.colorScheme.onSurfaceVariant;
    final panelSurface = widget.isError
        ? Color.alphaBlend(
            widget.colorScheme.error.withValues(alpha: 0.08),
            widget.colorScheme.surface,
          )
        : widget.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelSurface,
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: widget.isError
              ? widget.colorScheme.error.withValues(alpha: 0.24)
              : widget.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: widget.theme.textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: normalized.isEmpty
                    ? null
                    : () async {
                        await copyOpenHandTextToClipboard(
                          logTag: 'harness',
                          context: context,
                          text: normalized,
                          successMessage: openHandCopiedLabel(context),
                          logAction: '复制工具追踪值',
                        );
                      },
                tooltip: openHandCopyLabel(context),
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: widget.colorScheme.onSurfaceVariant,
                  minimumSize: const Size(32, 32),
                ),
              ),
              if (isLong)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  tooltip: _expanded
                      ? openHandCollapseLabel(context)
                      : openHandLocalizedText(
                          context,
                          zh: '展开全部',
                          zhHant: '展開全部',
                          en: 'Expand',
                          fr: 'Développer',
                          de: 'Erweitern',
                          ja: '展開',
                        ),
                  icon: Icon(
                    _expanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: widget.colorScheme.primary,
                    minimumSize: const Size(32, 32),
                  ),
                ),
            ],
          ),
          kOpenHandGap8,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.66,
              ),
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: SelectableText(
                      displayText,
                      style: widget.theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        height: 1.45,
                        color: widget.isError
                            ? widget.colorScheme.onErrorContainer
                            : widget.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

({String command, String workingDirectory})? _heSplitToolCommandAndDirectory(
  String raw,
) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final inIndex = trimmed.lastIndexOf(' in ');
  if (inIndex <= 0) {
    return _heLooksLikeToolCommand(trimmed)
        ? (command: trimmed, workingDirectory: '')
        : null;
  }
  final command = trimmed.substring(0, inIndex).trimRight();
  final workingDirectory = trimmed.substring(inIndex + 4).trimLeft();
  if (!_heLooksLikeToolWorkingDirectory(workingDirectory) ||
      !_heLooksLikeToolCommand(command)) {
    return _heLooksLikeToolCommand(trimmed)
        ? (command: trimmed, workingDirectory: '')
        : null;
  }
  return (command: command, workingDirectory: workingDirectory);
}

_HeToolPresentation _heToolPresentationForSegment(
  _HeOutputSegment segment,
  _HeParsedToolHeader? parsedHeader, {
  required BuildContext context,
}) {
  final role = (segment.roleLabel ?? '').trim().toLowerCase();
  final command = (parsedHeader?.command ?? '').toLowerCase();

  // Match roleLabel set by _heParseOutputSegments for
  // tool calls detected via '⚙ 工具调用：{ToolName}' format.
  if (role == 'bash' ||
      role == 'exec' ||
      command.contains('/bin/zsh') ||
      command.contains('/bin/bash') ||
      command.contains(' zsh ') ||
      command.contains(' bash ')) {
    return const _HeToolPresentation(
      label: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    );
  }
  if (role == 'ls' || role == 'listdir' || role == 'list_dir') {
    return const _HeToolPresentation(
      label: 'LS',
      icon: Icons.folder_open_rounded,
      isCommandLike: false,
    );
  }
  if (role == 'read' || role == 'readfile' || role == 'read_file') {
    return const _HeToolPresentation(
      label: 'Read',
      icon: Icons.description_outlined,
      isCommandLike: false,
    );
  }
  if (role == 'write' || role == 'writefile' || role == 'write_file') {
    return _HeToolPresentation(
      label: openHandLocalizedText(
        context,
        zh: '写入',
        zhHant: '寫入',
        en: 'Write',
        fr: 'Écriture',
        de: 'Schreiben',
        ja: '書き込み',
      ),
      icon: Icons.edit_document,
      isCommandLike: false,
    );
  }
  if (role == 'edit' || role == 'editfile' || role == 'edit_file') {
    return _HeToolPresentation(
      label: openHandLocalizedText(
        context,
        zh: '编辑',
        zhHant: '編輯',
        en: 'Edit',
        fr: 'Édition',
        de: 'Bearbeiten',
        ja: '編集',
      ),
      icon: Icons.edit_note_rounded,
      isCommandLike: false,
    );
  }
  if (role == 'grep' || role == 'grepsearch' || role == 'grep_search') {
    return const _HeToolPresentation(
      label: 'Grep',
      icon: Icons.search_rounded,
      isCommandLike: false,
    );
  }
  if (role == 'semantic' ||
      role == 'semanticsearch' ||
      role == 'semantic_search') {
    return _HeToolPresentation(
      label: openHandLocalizedText(
        context,
        zh: '语义搜索',
        zhHant: '語意搜尋',
        en: 'Semantic Search',
        fr: 'Recherche sémantique',
        de: 'Semantische Suche',
        ja: 'セマンティック検索',
      ),
      icon: Icons.travel_explore_rounded,
      isCommandLike: false,
    );
  }
  if (segment.kind == _HeSegmentKind.toolResult || role == 'tool') {
    return _HeToolPresentation(
      label: openHandToolResultLabel(context),
      icon: Icons.output_rounded,
      isCommandLike: false,
    );
  }
  if (role == 'function') {
    return _HeToolPresentation(
      label: _harnessSessionToolLabel(context),
      icon: Icons.build_circle_outlined,
      isCommandLike: false,
    );
  }
  // Use roleLabel as-is if it looks like a tool name.
  if (role.isNotEmpty && role.length <= 20) {
    return _HeToolPresentation(
      label: segment.roleLabel!.trim(),
      icon: Icons.build_circle_outlined,
      isCommandLike: segment.kind == _HeSegmentKind.toolCall,
    );
  }
  return _HeToolPresentation(
    label: _harnessSessionToolLabel(context),
    icon: Icons.build_circle_outlined,
    isCommandLike: segment.kind == _HeSegmentKind.toolCall,
  );
}

String _heBuildStructuredToolArguments(
  _HeOutputSegment segment,
  _HeParsedToolHeader? parsedHeader,
) {
  if (parsedHeader != null) {
    final arguments = <String, Object?>{
      if (parsedHeader.command.isNotEmpty) 'cmd': parsedHeader.command,
      if (parsedHeader.workingDirectory.isNotEmpty)
        'cwd': parsedHeader.workingDirectory,
      if ((segment.roleLabel ?? '').trim().isNotEmpty)
        'channel': segment.roleLabel!.trim().toLowerCase(),
    };
    if (arguments.isNotEmpty) {
      return prettyPrintJson(arguments);
    }
  }
  if (segment.kind == _HeSegmentKind.toolCall) {
    return _heFormatStructuredToolContent(segment.lines.join('\n'));
  }
  return '';
}

String _heBuildStructuredToolInputPreview({
  required String command,
  required String argumentsText,
}) {
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final lines = const LineSplitter()
      .convert(argumentsText)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '{}' : lines.first;
}

String _heBuildStructuredToolOutputPreview({
  required BuildContext context,
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = _heLastNonEmptyToolLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _heLastNonEmptyToolLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = _heLastNonEmptyToolLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (status == 'running' || status.isEmpty) {
    return openHandLocalizedText(
      context,
      zh: '工具运行中，等待新的输出...',
      zhHant: '工具執行中，等待新的輸出...',
      en: 'Tool is running. Waiting for output...',
      fr: 'L’outil est en cours. En attente de sortie...',
      de: 'Tool läuft. Warte auf Ausgabe...',
      ja: 'ツール実行中。出力を待機しています...',
    );
  }
  return openHandLocalizedText(
    context,
    zh: '点击展开查看工具输出',
    zhHant: '點擊展開查看工具輸出',
    en: 'Expand to inspect tool output',
    fr: 'Développez pour inspecter la sortie outil',
    de: 'Erweitern, um die Tool-Ausgabe zu prüfen',
    ja: '展開してツール出力を確認',
  );
}

String _heNormalizeToolStatus(String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case 'succeeded':
    case 'success':
      return 'success';
    case 'failed':
    case 'invalid_arguments':
      return 'failed';
    case 'timed out':
    case 'timed-out':
    case 'timed_out':
      return 'timed_out';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'denied':
      return 'denied';
    case 'rejected':
      return 'rejected';
    case 'blocked':
      return 'denied';
    default:
      return rawStatus.trim().toLowerCase();
  }
}

String _heToolActionLabel({
  required BuildContext context,
  required String status,
  required bool isCommandLike,
}) {
  switch (status) {
    case 'running':
      return isCommandLike
          ? openHandLocalizedText(
              context,
              zh: '执行中',
              zhHant: '執行中',
              en: 'Running',
              fr: 'Exécution',
              de: 'Wird ausgeführt',
              ja: '実行中',
            )
          : openHandLocalizedText(
              context,
              zh: '调用中',
              zhHant: '呼叫中',
              en: 'Running',
              fr: 'Appel en cours',
              de: 'Wird aufgerufen',
              ja: '呼び出し中',
            );
    case 'success':
      return isCommandLike
          ? openHandLocalizedText(
              context,
              zh: '执行完成',
              zhHant: '執行完成',
              en: 'Completed',
              fr: 'Exécution terminée',
              de: 'Ausgeführt',
              ja: '実行完了',
            )
          : openHandLocalizedText(
              context,
              zh: '调用完成',
              zhHant: '呼叫完成',
              en: 'Completed',
              fr: 'Appel terminé',
              de: 'Aufruf abgeschlossen',
              ja: '呼び出し完了',
            );
    case 'cancelled':
      return openHandStoppedLabel(context);
    case 'denied':
      return openHandLocalizedText(
        context,
        zh: '已拦截',
        zhHant: '已攔截',
        en: 'Blocked',
        fr: 'Bloqué',
        de: 'Blockiert',
        ja: 'ブロック済み',
      );
    case 'rejected':
      return openHandLocalizedText(
        context,
        zh: '已拒绝',
        zhHant: '已拒絕',
        en: 'Rejected',
        fr: 'Refusé',
        de: 'Abgelehnt',
        ja: '拒否済み',
      );
    case 'timed_out':
      return isCommandLike
          ? openHandLocalizedText(
              context,
              zh: '执行超时',
              zhHant: '執行逾時',
              en: 'Timed Out',
              fr: 'Délai dépassé',
              de: 'Zeitüberschreitung',
              ja: '実行タイムアウト',
            )
          : openHandLocalizedText(
              context,
              zh: '调用超时',
              zhHant: '呼叫逾時',
              en: 'Timed Out',
              fr: 'Délai d’appel dépassé',
              de: 'Aufruf-Timeout',
              ja: '呼び出しタイムアウト',
            );
    case 'failed':
      return isCommandLike
          ? openHandLocalizedText(
              context,
              zh: '执行失败',
              zhHant: '執行失敗',
              en: 'Failed',
              fr: 'Échec',
              de: 'Fehlgeschlagen',
              ja: '実行失敗',
            )
          : openHandLocalizedText(
              context,
              zh: '调用失败',
              zhHant: '呼叫失敗',
              en: 'Failed',
              fr: 'Échec de l’appel',
              de: 'Aufruf fehlgeschlagen',
              ja: '呼び出し失敗',
            );
    default:
      return isCommandLike
          ? openHandLocalizedText(
              context,
              zh: '准备执行',
              zhHant: '準備執行',
              en: 'Preparing',
              fr: 'Préparation',
              de: 'Vorbereitung',
              ja: '実行準備中',
            )
          : openHandLocalizedText(
              context,
              zh: '工具调用',
              zhHant: '工具呼叫',
              en: 'Tool Call',
              fr: 'Appel outil',
              de: 'Tool-Aufruf',
              ja: 'ツール呼び出し',
            );
  }
}

String _heToolOutcomeLabel({
  required BuildContext context,
  required String status,
}) {
  switch (status) {
    case 'running':
      return openHandRunningLabel(context);
    case 'success':
      return openHandLocalizedText(
        context,
        zh: '执行成功',
        zhHant: '執行成功',
        en: 'Succeeded',
        fr: 'Réussi',
        de: 'Erfolgreich',
        ja: '成功',
      );
    case 'cancelled':
      return openHandStoppedLabel(context);
    case 'denied':
      return openHandLocalizedText(
        context,
        zh: '已被禁止',
        zhHant: '已被禁止',
        en: 'Denied',
        fr: 'Refusé',
        de: 'Verweigert',
        ja: '拒否',
      );
    case 'rejected':
      return openHandLocalizedText(
        context,
        zh: '用户拒绝',
        zhHant: '使用者拒絕',
        en: 'Rejected',
        fr: 'Rejeté',
        de: 'Abgelehnt',
        ja: 'ユーザーが拒否',
      );
    case 'timed_out':
      return openHandLocalizedText(
        context,
        zh: '执行超时',
        zhHant: '執行逾時',
        en: 'Timed Out',
        fr: 'Délai dépassé',
        de: 'Zeitüberschreitung',
        ja: 'タイムアウト',
      );
    case 'failed':
      return openHandLocalizedText(
        context,
        zh: '执行失败',
        zhHant: '執行失敗',
        en: 'Failed',
        fr: 'Échec',
        de: 'Fehlgeschlagen',
        ja: '失敗',
      );
    default:
      return '';
  }
}

IconData _heToolStatusIcon(String status) {
  switch (status) {
    case 'running':
      return Icons.play_circle_outline_rounded;
    case 'success':
      return Icons.check_circle_outline_rounded;
    case 'cancelled':
      return Icons.stop_circle_outlined;
    case 'denied':
      return Icons.block_rounded;
    case 'rejected':
      return Icons.cancel_outlined;
    case 'timed_out':
      return Icons.timer_off_outlined;
    case 'failed':
      return Icons.error_outline_rounded;
    default:
      return Icons.terminal_rounded;
  }
}

int _heParseToolDurationToMs(String rawDuration) {
  final trimmed = rawDuration.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return 0;
  }
  final numeric = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(trimmed);
  final value = double.tryParse(numeric?.group(1) ?? '0') ?? 0;
  if (trimmed.endsWith('ms')) {
    return value.round();
  }
  if (trimmed.endsWith('min') ||
      trimmed.endsWith('mins') ||
      trimmed.endsWith('m')) {
    return (value * 60000).round();
  }
  return (value * 1000).round();
}

String _heFormatToolDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).floor();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds}s';
}

int _heIndexOfFirstMeaningfulLine(List<String> lines) {
  for (var index = 0; index < lines.length; index += 1) {
    if (lines[index].trim().isNotEmpty) {
      return index;
    }
  }
  return -1;
}

bool _heLooksLikeToolCommand(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return trimmed.startsWith('/') ||
      trimmed.startsWith('./') ||
      trimmed.startsWith('../') ||
      trimmed.startsWith('~/') ||
      trimmed.contains(' -') ||
      trimmed.contains("'") ||
      trimmed.contains('"');
}

bool _heLooksLikeToolWorkingDirectory(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return trimmed.startsWith('/') ||
      trimmed.startsWith('./') ||
      trimmed.startsWith('../') ||
      trimmed.startsWith('~/');
}

int? _heExtractToolExitCode(List<String> lines) {
  for (final line in lines) {
    final match = _heToolExitCodePattern.firstMatch(line);
    final code = int.tryParse(match?.group(1) ?? '');
    if (code != null) {
      return code;
    }
  }
  return null;
}

/// Extracts status from tool output lines.
/// Matches patterns like 'status: denied', 'status: success', etc.
final RegExp _heToolOutputStatusPattern = RegExp(
  r'^\s*status\s*:\s*(\w+)',
  caseSensitive: false,
);

String _heExtractStatusFromLines(List<String> lines) {
  for (final line in lines) {
    final match = _heToolOutputStatusPattern.firstMatch(line);
    if (match != null) {
      return _heNormalizeToolStatus(match.group(1) ?? '');
    }
  }
  return '';
}

String _heFormatStructuredToolContent(String rawContent) {
  final normalized = _heNormalizeToolText(rawContent);
  if (normalized.isEmpty) {
    return '';
  }
  return formatStructuredTextForDisplay(normalized).text;
}

String _heNormalizeToolText(String rawContent) {
  return rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
}

String _heLastNonEmptyToolLine(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '' : lines.last;
}

bool _heShouldRenderSegmentAsLogLines(String content) {
  final lines = const LineSplitter().convert(content);
  if (lines.isEmpty || lines.any((line) => line.contains('```'))) {
    return false;
  }

  var matchedLines = 0;
  var markdownishLines = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (_logLevelPattern.hasMatch(trimmed) ||
        trimmed.startsWith('>') ||
        trimmed.startsWith('✓ ') ||
        trimmed.startsWith('✗ ') ||
        trimmed.startsWith('⚠ ') ||
        trimmed.startsWith('▶ ')) {
      matchedLines += 1;
      continue;
    }
    if (trimmed.startsWith('#') ||
        trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('|')) {
      markdownishLines += 1;
    }
  }
  return matchedLines > 0 && markdownishLines == 0;
}

class _HeStructuredLogLines extends StatelessWidget {
  const _HeStructuredLogLines({required this.lines, required this.colorScheme});

  final List<String> lines;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      cacheExtent: 600,
      itemCount: lines.length,
      itemBuilder: (context, index) =>
          _LogLine(line: lines[index], colorScheme: colorScheme),
    );
  }
}

String _harnessSessionToolLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '工具',
    zhHant: '工具',
    en: 'Tool',
    fr: 'Outil',
    de: 'Tool',
    ja: 'ツール',
  );
}

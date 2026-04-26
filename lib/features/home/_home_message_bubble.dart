part of 'openhand_home_page.dart';

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.sessionTitle,
    required this.sessionEnvironment,
    required this.showReasoningSweep,
    required this.trackLayoutChanges,
    required this.onLayoutChanged,
    required this.isSelected,
    required this.onSelect,
    required this.onDeselect,
    required this.onCopy,
    required this.onDelete,
    this.onDeleteFromHere,
    this.onEdit,
    this.onAudit,
  });

  final AiSessionMessage message;
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool trackLayoutChanges;
  final VoidCallback onLayoutChanged;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onDeleteFromHere;
  final Future<void> Function()? onEdit;
  final VoidCallback? onAudit;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _compressionExpanded = false;
  bool? _reasoningExpandedOverride;

  // Cached expensive objects to avoid re-allocation on every build.
  List<md.InlineSyntax>? _cachedInlineSyntaxes;
  Map<String, MarkdownElementBuilder>? _cachedBuilders;
  _MessageMarkdownThemeData? _cachedMarkdownThemeData;
  String? _cachedFilePathParseKey;
  List<String>? _cachedFilePathRoots;
  String? _lastCacheMessageId;
  String? _lastCacheEnvironmentKey;
  int? _lastCacheThemeBrightness;
  bool? _lastCacheIsSelected;
  bool? _lastCacheDarkCodeSurface;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpandedOverride = null;
      _invalidateCache();
    }
  }

  void _invalidateCache() {
    _cachedInlineSyntaxes = null;
    _cachedBuilders = null;
    _cachedMarkdownThemeData = null;
    _cachedFilePathParseKey = null;
    _cachedFilePathRoots = null;
    _lastCacheMessageId = null;
    _lastCacheEnvironmentKey = null;
    _lastCacheThemeBrightness = null;
    _lastCacheIsSelected = null;
    _lastCacheDarkCodeSurface = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = widget.message;
    final isUser = message.kind == AiSessionMessageKind.user;
    final isCompressionPoint =
        message.kind == AiSessionMessageKind.compressionPoint;
    final isReasoning = message.kind == AiSessionMessageKind.reasoning;
    final isStreamingReasoning = _isStreamingReasoningMessage(message);
    final isToolCall =
        message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook;
    final isToolResult =
        message.kind == AiSessionMessageKind.tool ||
        message.kind == AiSessionMessageKind.mcp ||
        message.kind == AiSessionMessageKind.skill;
    final isStatus = message.kind == AiSessionMessageKind.status;
    final isSelfLearning = message.kind == AiSessionMessageKind.selfLearning;
    final attachments = AiMessageAttachment.listFromMetadata(
      message.metadata[aiSessionMessageAttachmentsMetadataKey],
    );
    final reasoningExpanded =
        _reasoningExpandedOverride ?? _shouldDefaultExpandReasoning(message);

    final alignment = isCompressionPoint
        ? Alignment.center
        : isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final borderRadius = BorderRadius.circular(isReasoning ? 18 : 26);
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isUser
        ? colorScheme.primaryContainer
        : isReasoning
        ? const Color(0xFF18181B)
        : isToolCall
        ? colorScheme.secondaryContainer
        : isToolResult
        ? colorScheme.surfaceContainerHighest
        : isSelfLearning
        ? colorScheme.tertiaryContainer
        : isStatus
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh;
    final textColor = isCompressionPoint
        ? colorScheme.onTertiaryContainer
        : isUser
        ? colorScheme.onPrimaryContainer
        : isReasoning
        ? Colors.white
        : isToolCall
        ? colorScheme.onSecondaryContainer
        : isSelfLearning
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurface;
    final useDarkCodeSurface = isReasoning || isToolCall;
    final environmentKey =
        '${widget.sessionEnvironment.applicationDirectory}|${_toolExecutionWorkingDirectory(message)}';
    final themeBrightness = theme.brightness.index;
    final needsCacheRefresh =
        _lastCacheMessageId != message.id ||
        _lastCacheEnvironmentKey != environmentKey ||
        _lastCacheThemeBrightness != themeBrightness ||
        _lastCacheIsSelected != widget.isSelected ||
        _lastCacheDarkCodeSurface != useDarkCodeSurface;
    if (needsCacheRefresh) {
      _lastCacheMessageId = message.id;
      _lastCacheEnvironmentKey = environmentKey;
      _lastCacheThemeBrightness = themeBrightness;
      _lastCacheIsSelected = widget.isSelected;
      _lastCacheDarkCodeSurface = useDarkCodeSurface;
      _cachedMarkdownThemeData = _MessageMarkdownThemeData.fromMessageBubble(
        theme: theme,
        backgroundColor: backgroundColor,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
      _cachedFilePathRoots = messageFilePathRoots(
        widget.sessionEnvironment,
        workingDirectory: _toolExecutionWorkingDirectory(message),
      );
      _cachedFilePathParseKey = _cachedFilePathRoots!.join('|');
      _cachedBuilders = <String, MarkdownElementBuilder>{
        'pre': _HighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: textColor,
          darkSurface: useDarkCodeSurface,
          selectable: widget.isSelected,
        ),
        'openhand-file-resolved': _FilePathMarkdownBuilder(
          textColor: textColor,
          onOpenPath: _openResolvedMessagePath,
        ),
        'openhand-file-pending': _FilePathMarkdownBuilder(
          textColor: textColor,
          onOpenPath: _openResolvedMessagePath,
        ),
        'openhand-generated-media': _GeneratedMediaLinkMarkdownBuilder(
          textColor: textColor,
          backgroundColor: backgroundColor,
          pathRoots: _cachedFilePathRoots!,
        ),
      };
      _cachedInlineSyntaxes = <md.InlineSyntax>[
        _GeneratedMediaLinkSyntax.byExtension(pathRoots: _cachedFilePathRoots!),
        _GeneratedMediaLinkSyntax.byGeneratedLabel(
          pathRoots: _cachedFilePathRoots!,
        ),
        MessagePathCodeSyntax(candidateRoots: _cachedFilePathRoots!),
        MessageFilePathSyntax(candidateRoots: _cachedFilePathRoots!),
      ];
    }
    final markdownStyleSheet = _cachedMarkdownThemeData!;
    final filePathRoots = _cachedFilePathRoots!;
    final filePathParseKey = _cachedFilePathParseKey!;
    final markdownBuilders = _cachedBuilders!;
    final inlineSyntaxes = _cachedInlineSyntaxes!;

    // Parse Hardness Engineering agent/phase annotations from message content.
    // Only assistant-role messages can carry these markers.
    final heAnnotation =
        (!isUser &&
            !isCompressionPoint &&
            !isToolCall &&
            !isToolResult &&
            !isStatus &&
            !isSelfLearning)
        ? _parseHeAnnotation(message.content)
        : null;
    final effectiveContent = heAnnotation?.strippedContent ?? message.content;

    final bubbleBody = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (heAnnotation != null && heAnnotation.hasAnnotations)
          _HardnessAnnotationCapsuleRow(annotation: heAnnotation),
        DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: isToolCall
                ? Border.all(color: colorScheme.secondary, width: 1.2)
                : widget.isSelected
                ? Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.38),
                    width: 1.5,
                  )
                : Border.all(
                    color: colorScheme.outlineVariant.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
                    ),
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
                if (isCompressionPoint)
                  _MessageMetaRow(
                    icon: Icons.summarize_rounded,
                    label: AppLocalizations.of(
                      context,
                    )!.threadCompressionCheckpointLabel,
                    color: textColor,
                  )
                else if (isReasoning)
                  _ReasoningMetaRow(
                    message: message,
                    color: textColor,
                    showSweep: widget.showReasoningSweep,
                    expanded: reasoningExpanded,
                    onTap: () {
                      final nextExpanded = !reasoningExpanded;
                      setState(() {
                        _reasoningExpandedOverride = nextExpanded;
                      });
                    },
                  )
                else if (isToolCall)
                  _ToolCallMetaRow(
                    data: _ToolCallStatusViewData.from(context, message),
                    color: textColor,
                  )
                else if (isToolResult)
                  _MessageMetaRow(
                    icon: Icons.inventory_2_outlined,
                    label: _localizedText(
                      context,
                      zh: '工具结果',
                      en: 'Tool Result',
                    ),
                    color: textColor,
                  )
                else if (!isSelfLearning && message.modelLabel != null)
                  Text(
                    message.modelLabel!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isUser
                          ? textColor.withValues(alpha: 0.86)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (isCompressionPoint ||
                    isReasoning ||
                    isToolCall ||
                    isToolResult ||
                    (!isSelfLearning && message.modelLabel != null))
                  const SizedBox(height: 10),
                if (isCompressionPoint)
                  _CompressionCheckpointBody(
                    content: message.content,
                    expanded: _compressionExpanded,
                    onToggle: () {
                      setState(() {
                        _compressionExpanded = !_compressionExpanded;
                      });
                    },
                    selectable: widget.isSelected,
                    textColor: textColor,
                    fadeColor: backgroundColor,
                    styleSheet: markdownStyleSheet.styleSheet,
                    builders: markdownBuilders,
                    inlineSyntaxes: inlineSyntaxes,
                    pathRoots: filePathRoots,
                    parseKey: filePathParseKey,
                  )
                else if (isReasoning)
                  _ReasoningBody(
                    content: message.content,
                    expanded: reasoningExpanded,
                    streaming: isStreamingReasoning,
                    selectable: widget.isSelected,
                    textColor: textColor,
                    fadeColor: backgroundColor,
                    styleSheet: markdownStyleSheet.styleSheet,
                    builders: markdownBuilders,
                    inlineSyntaxes: inlineSyntaxes,
                    pathRoots: filePathRoots,
                    parseKey: filePathParseKey,
                  )
                else if (isToolCall)
                  _ToolCallBody(message: message, selectable: widget.isSelected)
                else if (isSelfLearning)
                  // Wrap the self-learning card in an AnimatedSize so as the
                  // dispatcher streams in tokens (and metadata grows), the
                  // bubble height eases out with a Q-bouncy curve instead
                  // of jumping. Mirrors the reasoning bubble behaviour.
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: _SelfLearningCard(message: message),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (attachments.isNotEmpty) ...[
                        _MessageAttachmentSummaryBlock(
                          attachments: attachments,
                          textColor: textColor,
                          backgroundColor: backgroundColor,
                          onAttachmentTap: (attachment) =>
                              _openAttachment(context, attachment),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _CollapsibleMessageMarkdownBody(
                        data: effectiveContent.isEmpty ? ' ' : effectiveContent,
                        selectable: widget.isSelected,
                        builders: markdownBuilders,
                        styleSheet: markdownStyleSheet.styleSheet,
                        inlineSyntaxes: inlineSyntaxes,
                        pathRoots: filePathRoots,
                        parseKey: filePathParseKey,
                        fadeColor: backgroundColor,
                        collapseCharThreshold: isToolResult
                            ? _toolResultMarkdownCollapseCharThreshold
                            : _messageMarkdownCollapseCharThreshold,
                        collapseLineThreshold: isToolResult
                            ? _toolResultMarkdownCollapseLineThreshold
                            : _messageMarkdownCollapseLineThreshold,
                        previewMaxHeight: isToolResult ? 176 : 240,
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  _formatDateTime(message.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.78),
                  ),
                ),
                if (isUser)
                  _CreationModeChip(
                    request: AiCreationRequest.fromMetadata(
                      message.metadata[AiCreationRequest.metadataKey],
                    ),
                    textColor: textColor,
                  ),
                if (isUser)
                  _UserSkillSelectionChip(
                    metadata: message.metadata[aiUserSkillSelectionMetadataKey],
                    textColor: textColor,
                  ),
              ],
            ),
          ),
        ),
        if (widget.isSelected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _MessageActionButton(
                  onPressed: widget.onCopy,
                  icon: Icons.content_copy_outlined,
                  label: _localizedText(context, zh: '复制', en: 'Copy'),
                ),
                if (widget.onEdit != null)
                  _MessageActionButton(
                    onPressed: widget.onEdit,
                    icon: Icons.edit_outlined,
                    label: AppLocalizations.of(context)!.commonEdit,
                  ),
                _MessageActionButton(
                  onPressed: widget.onDelete,
                  icon: Icons.delete_outline_rounded,
                  label: AppLocalizations.of(context)!.commonDelete,
                ),
                if (widget.onDeleteFromHere != null)
                  _MessageActionButton(
                    onPressed: widget.onDeleteFromHere,
                    icon: Icons.delete_sweep_outlined,
                    label: _localizedText(
                      context,
                      zh: '删除此条及后续',
                      en: 'Delete From Here',
                    ),
                  ),
                if (widget.onAudit != null)
                  _MessageActionButton(
                    onPressed: () async => widget.onAudit!.call(),
                    icon: Icons.fact_check_outlined,
                    label: _localizedText(context, zh: '审计', en: 'Audit'),
                  ),
              ],
            ),
          ),
      ],
    );
    final messageContent = widget.trackLayoutChanges
        ? NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (notification) {
              widget.onLayoutChanged();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: bubbleBody),
          )
        : bubbleBody;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onSelect,
      child: TapRegion(
        enabled: widget.isSelected,
        onTapOutside: (_) => widget.onDeselect(),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: messageContent,
          ),
        ),
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

class _MessageAttachmentSummaryBlock extends StatelessWidget {
  const _MessageAttachmentSummaryBlock({
    required this.attachments,
    required this.textColor,
    required this.backgroundColor,
    this.onAttachmentTap,
  });

  final List<AiMessageAttachment> attachments;
  final Color textColor;
  final Color backgroundColor;
  final void Function(AiMessageAttachment attachment)? onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onAttachmentTap?.call(attachment),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      textColor.withValues(alpha: 0.08),
                      backgroundColor,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: textColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForAttachmentKind(attachment.kind),
                        size: 16,
                        color: textColor.withValues(alpha: 0.88),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Opens a message attachment: images are shown in an in-app preview dialog;
/// other file types are opened with the system default application.
Future<void> _openAttachment(
  BuildContext context,
  AiMessageAttachment attachment,
) async {
  final storagePath = attachment.storagePath.trim();
  if (storagePath.isEmpty) {
    return;
  }
  final file = File(storagePath);
  if (!file.existsSync()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '附件文件不存在或已被移动。',
            en: 'Attachment file not found or has been moved.',
          ),
        ),
      ),
    );
    return;
  }

  if (attachment.isImage) {
    if (!context.mounted) return;
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _ImagePreviewDialog.file(
        filePath: storagePath,
        title: attachment.name,
      ),
    );
    return;
  }

  // Non-image files: open with system default application.
  await _openLocalPathWithSystemApp(context, storagePath);
}

Future<void> _openLocalPathWithSystemApp(
  BuildContext context,
  String path,
) async {
  if (!context.mounted) {
    return;
  }
  final normalizedPath = path.trim();
  if (normalizedPath.isEmpty) {
    return;
  }
  // Refuse anything that doesn't look like a local file path. Without this
  // a string such as `https://evil.invalid` or a leading `-flag` could be
  // forwarded directly to `open` / `xdg-open`, which both happily treat
  // those inputs as URLs / option flags.
  final looksLikeUri = RegExp(
    r'^[A-Za-z][A-Za-z0-9+.-]*:',
  ).hasMatch(normalizedPath);
  final hasLeadingDash = normalizedPath.startsWith('-');
  if (looksLikeUri || hasLeadingDash) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '拒绝打开不安全的路径：$normalizedPath',
              en: 'Refused unsafe path: $normalizedPath',
            ),
          ),
        ),
      );
    }
    return;
  }
  try {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[normalizedPath]);
    } else if (Platform.isWindows) {
      result = await Process.run('cmd', <String>[
        '/c',
        'start',
        '',
        normalizedPath,
      ]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[normalizedPath]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Failed to open file.' : message,
      normalizedPath,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '打开文件失败：$error',
            en: 'Failed to open file: $error',
          ),
        ),
      ),
    );
  }
}

/// Opens a composer attachment draft: images are shown in an in-app preview
/// dialog; other file types are opened with the system default application.
Future<void> _openComposerAttachment(
  BuildContext context,
  _ComposerAttachmentDraft draft,
) async {
  await _openAttachment(
    context,
    AiMessageAttachment(
      id: draft.filePath,
      storagePath: draft.filePath,
      kind: draft.kind,
      name: draft.name,
      mimeType: '',
      sizeBytes: draft.sizeBytes,
    ),
  );
}

/// Shimmer / skeleton placeholder shown while an image frame is loading.
class _ImageShimmerPlaceholder extends StatefulWidget {
  const _ImageShimmerPlaceholder();

  @override
  State<_ImageShimmerPlaceholder> createState() =>
      _ImageShimmerPlaceholderState();
}

class _ImageShimmerPlaceholderState extends State<_ImageShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surfaceContainerLow;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-1.0 + 2.0 * _ctrl.value + 1.0, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.image_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen image preview dialog with zoom and pan support.
class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog.file({required this.filePath, required this.title})
    : imageUri = null;

  const _ImagePreviewDialog.network({
    required this.imageUri,
    required this.title,
  }) : filePath = null;

  final String? filePath;
  final Uri? imageUri;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _localizedText(
                      context,
                      zh: '使用系统应用打开',
                      en: 'Open with System App',
                    ),
                    onPressed: () => _openInSystemApp(context),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.download_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _localizedText(
                      context,
                      zh: '保存到本地',
                      en: 'Save to disk',
                    ),
                    onPressed: () => _saveImageAs(context),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Image body with zoom/pan.
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildPreviewImage(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewImage(BuildContext context) {
    final sourceFilePath = filePath;
    if (sourceFilePath != null) {
      return Image.file(
        File(sourceFilePath),
        fit: BoxFit.contain,
        frameBuilder: _SafeMarkdownBodyState._fadeInImageFrameBuilder,
        errorBuilder: (context, error, stackTrace) =>
            _buildImageLoadError(context),
      );
    }

    final sourceUri = imageUri;
    if (sourceUri == null) {
      return _buildImageLoadError(context);
    }

    return Image.network(
      sourceUri.toString(),
      fit: BoxFit.contain,
      frameBuilder: _SafeMarkdownBodyState._fadeInImageFrameBuilder,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        final expected = loadingProgress.expectedTotalBytes;
        final progress = expected != null && expected > 0
            ? loadingProgress.cumulativeBytesLoaded / expected
            : null;
        return SizedBox(
          width: 220,
          height: 220,
          child: Center(
            child: CircularProgressIndicator(value: progress, strokeWidth: 2.6),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          _buildImageLoadError(context),
    );
  }

  Widget _buildImageLoadError(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: colorScheme.error),
          const SizedBox(height: 12),
          Text(
            _localizedText(context, zh: '无法加载图片', en: 'Failed to load image'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInSystemApp(BuildContext context) async {
    final sourceFilePath = filePath;
    if (sourceFilePath != null) {
      await _openLocalPathWithSystemApp(context, sourceFilePath);
      return;
    }
    final sourceUri = imageUri;
    if (sourceUri == null) {
      return;
    }
    await _openMessageLinkUri(context, sourceUri);
  }

  Future<void> _saveImageAs(BuildContext context) async {
    final basename = _suggestedSaveName();
    final ext = _normalizeSaveExtension(p.extension(basename).toLowerCase());
    // Map common image extensions to MIME types for the save dialog.
    final mimeType = switch (ext) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      _ => 'image/png',
    };
    final extensionWithoutDot = ext.replaceFirst('.', '');
    try {
      final location = await getSaveLocation(
        suggestedName: basename,
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: 'Images',
            mimeTypes: <String>[mimeType],
            extensions: <String>[extensionWithoutDot],
          ),
        ],
      );
      if (location == null) return;
      final sourceFilePath = filePath;
      if (sourceFilePath != null) {
        final source = File(sourceFilePath);
        if (!source.existsSync()) {
          throw FileSystemException(
            'Image source file is missing.',
            source.path,
          );
        }
        await source.copy(location.path);
        return;
      }

      final sourceUri = imageUri;
      if (sourceUri == null) {
        throw const FileSystemException('Image source is unavailable.');
      }
      await _downloadRemoteImage(sourceUri, location.path);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context, zh: '保存失败：$e', en: 'Save failed: $e'),
          ),
        ),
      );
    }
  }

  String _suggestedSaveName() {
    final sourceFilePath = filePath;
    if (sourceFilePath != null) {
      final basename = p.basename(sourceFilePath).trim();
      if (basename.isNotEmpty) {
        return basename;
      }
    }

    final sourceUri = imageUri;
    if (sourceUri != null) {
      final decodedPath = () {
        try {
          return Uri.decodeFull(sourceUri.path);
        } catch (_) {
          return sourceUri.path;
        }
      }();
      final basename = p.basename(decodedPath).trim();
      if (basename.isNotEmpty && basename != '/' && basename != '.') {
        return basename;
      }
    }
    return 'image-${DateTime.now().millisecondsSinceEpoch}.png';
  }

  String _normalizeSaveExtension(String extension) {
    if (extension.isNotEmpty) {
      return extension;
    }
    final sourceUri = imageUri;
    if (sourceUri != null) {
      final format = sourceUri.queryParameters['format']?.trim().toLowerCase();
      if (format != null &&
          (format == 'png' ||
              format == 'jpg' ||
              format == 'jpeg' ||
              format == 'webp' ||
              format == 'gif' ||
              format == 'bmp')) {
        return '.$format';
      }
    }
    return '.png';
  }

  Future<void> _downloadRemoteImage(Uri sourceUri, String destination) async {
    final scheme = sourceUri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FileSystemException(
        'Unsupported image URI scheme: ${sourceUri.scheme}',
        sourceUri.toString(),
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(sourceUri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading image.',
          uri: sourceUri,
        );
      }
      final contentType = response.headers.contentType;
      if (contentType != null && contentType.primaryType != 'image') {
        throw HttpException(
          'Unexpected content type: ${contentType.mimeType}',
          uri: sourceUri,
        );
      }

      final output = File(destination).openWrite();
      try {
        await output.addStream(response);
        await output.flush();
      } finally {
        await output.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

enum _GeneratedMessageMediaKind { video, audio }

class _GeneratedMediaSource {
  const _GeneratedMediaSource({
    required this.kind,
    required this.uri,
    this.filePath,
  });

  final _GeneratedMessageMediaKind kind;
  final Uri uri;
  final String? filePath;

  bool get isLocalFile => filePath != null;
}

class _GeneratedMediaLinkSyntax extends md.InlineSyntax {
  _GeneratedMediaLinkSyntax.byExtension({required this.pathRoots})
    : super(_byExtensionPattern, caseSensitive: false);

  _GeneratedMediaLinkSyntax.byGeneratedLabel({required this.pathRoots})
    : super(_byGeneratedLabelPattern, caseSensitive: false);

  static const String _mediaExtensionAlternation =
      r'mp4|webm|mov|m4v|mkv|mp3|wav|m4a|aac|ogg|opus|flac';
  static const String _byExtensionPattern =
      r'\[([^\]\n]{0,240})\]\(([^)\s]*\.(?:' +
      _mediaExtensionAlternation +
      r')(?:[?#][^)\s]*)?)\)';
  static const String _byGeneratedLabelPattern =
      r'\[((?:AI\s+Generated\s+(?:Video|Audio)|AI\s+Audio\s+Response)[^\]\n]{0,240})\]\(([^)\s]+)\)';

  final List<String> pathRoots;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final fullMatch = match[0] ?? '';
    final label = (match[1] ?? '').trim();
    final href = (match[2] ?? '').trim();
    final kindHint = _generatedMediaKindForLabel(label);
    final source = _resolveGeneratedMediaSource(
      href,
      pathRoots,
      kindHint: kindHint,
    );
    if (source == null) {
      parser.addNode(
        md.Element.text('a', label.isEmpty ? fullMatch : label)
          ..attributes['href'] = href,
      );
      return true;
    }
    parser.addNode(
      md.Element.text(
          'openhand-generated-media',
          label.isEmpty ? _generatedMediaFallbackTitle(source) : label,
        )
        ..attributes['href'] = href
        ..attributes['media_kind'] = source.kind.name
        ..attributes['file_path'] = source.filePath ?? '',
    );
    return true;
  }
}

class _GeneratedMediaLinkMarkdownBuilder extends MarkdownElementBuilder {
  _GeneratedMediaLinkMarkdownBuilder({
    required this.textColor,
    required this.backgroundColor,
    required this.pathRoots,
  });

  final Color textColor;
  final Color backgroundColor;
  final List<String> pathRoots;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = (element.attributes['href'] ?? '').trim();
    if (href.isEmpty) return null;
    final kindHint = _generatedMediaKindFromStorage(
      element.attributes['media_kind'],
    );
    final filePath = (element.attributes['file_path'] ?? '').trim();
    final source = filePath.isNotEmpty && kindHint != null
        ? _GeneratedMediaSource(
            kind: kindHint,
            uri: Uri.file(filePath),
            filePath: filePath,
          )
        : _resolveGeneratedMediaSource(href, pathRoots, kindHint: kindHint);
    if (source == null) return null;
    final label = element.textContent.trim().isEmpty
        ? _generatedMediaFallbackTitle(source)
        : element.textContent.trim();
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, right: 4, bottom: 4),
          child: _GeneratedMediaLinkCard(
            source: source,
            title: label,
            textColor: textColor,
            backgroundColor: backgroundColor,
          ),
        ),
      ),
    );
  }
}

class _GeneratedMediaLinkCard extends StatefulWidget {
  const _GeneratedMediaLinkCard({
    required this.source,
    required this.title,
    required this.textColor,
    required this.backgroundColor,
  });

  final _GeneratedMediaSource source;
  final String title;
  final Color textColor;
  final Color backgroundColor;

  @override
  State<_GeneratedMediaLinkCard> createState() =>
      _GeneratedMediaLinkCardState();
}

class _GeneratedMediaLinkCardState extends State<_GeneratedMediaLinkCard> {
  // Without this guard, rapid double-clicks on the inline card stacked two
  // identical preview dialogs (each spinning up its own WebView), which
  // pinned the UI thread and leaked event handlers.
  bool _dialogOpen = false;
  // Cached sidecar PNG path for local video previews. `null` while the
  // capture is pending or when the source is remote / not a video.
  String? _videoThumbPath;
  bool _videoCaptureRequested = false;

  @override
  void initState() {
    super.initState();
    _initVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant _GeneratedMediaLinkCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.filePath != widget.source.filePath ||
        oldWidget.source.kind != widget.source.kind) {
      _videoThumbPath = null;
      _videoCaptureRequested = false;
      _initVideoThumbnail();
    }
  }

  Future<void> _initVideoThumbnail() async {
    final source = widget.source;
    if (source.kind != _GeneratedMessageMediaKind.video) return;
    final path = source.filePath;
    if (path == null) return;
    final cached = _VideoThumbnailManager.thumbnailPathFor(path);
    try {
      if (await File(cached).exists()) {
        if (!mounted) return;
        setState(() => _videoThumbPath = cached);
        return;
      }
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'video thumbnail: cache probe failed',
        error,
        stack,
      );
    }
    if (!mounted) return;
    if (_VideoThumbnailManager.isMarkedFailed(path)) return;
    setState(() => _videoCaptureRequested = true);
  }

  Future<void> _openPreview() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _MediaPreviewDialog(source: widget.source, title: widget.title),
      );
    } finally {
      if (mounted) _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final title = widget.title;
    final textColor = widget.textColor;
    final backgroundColor = widget.backgroundColor;
    final isVideo = source.kind == _GeneratedMessageMediaKind.video;
    if (isVideo) {
      return _buildVideoCard(theme, source, title, textColor, backgroundColor);
    }
    const icon = Icons.graphic_eq;
    final label = _localizedText(context, zh: '音频', en: 'Audio');
    final detail = source.isLocalFile
        ? p.basename(source.filePath!)
        : source.uri.host.isEmpty
        ? source.uri.toString()
        : source.uri.host;
    final cardColor = Color.alphaBlend(
      textColor.withValues(alpha: 0.08),
      backgroundColor,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: title,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openPreview,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 240),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 26, color: textColor.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$label · $detail',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.76),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_full_rounded,
                    size: 18,
                    color: textColor.withValues(alpha: 0.78),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(
    ThemeData theme,
    _GeneratedMediaSource source,
    String title,
    Color textColor,
    Color backgroundColor,
  ) {
    final detail = source.isLocalFile
        ? p.basename(source.filePath!)
        : source.uri.host.isEmpty
        ? source.uri.toString()
        : source.uri.host;
    final cardColor = Color.alphaBlend(
      textColor.withValues(alpha: 0.08),
      backgroundColor,
    );
    final thumbPath = _videoThumbPath;
    final showCapture =
        _videoCaptureRequested && thumbPath == null && source.isLocalFile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: title,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openPreview,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 240),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textColor.withValues(alpha: 0.16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbPath != null)
                          Image.file(
                            File(thumbPath),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.black87,
                            ),
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.78),
                                  Colors.black.withValues(alpha: 0.92),
                                ],
                              ),
                            ),
                          ),
                        // Subtle scrim so the play icon stays legible on
                        // bright thumbnails.
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.0),
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.85),
                                width: 1.4,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_outlined,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'VIDEO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showCapture)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: _VideoThumbnailCaptureHost(
                              videoPath: source.filePath!,
                              mimeType: _mimeTypeForGeneratedMedia(source),
                              onResult: (path) {
                                if (!mounted) return;
                                setState(() {
                                  _videoCaptureRequested = false;
                                  _videoThumbPath = path;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: textColor.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 18,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({required this.source, required this.title});

  final _GeneratedMediaSource source;
  final String title;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  static const Duration _mediaLoadTimeout = Duration(seconds: 18);

  late final WebViewController _controller;
  Timer? _loadTimeoutTimer;
  bool _pageLoaded = false;
  bool _mediaReady = false;
  String? _loadError;
  // Reentrancy guards: rapid double-taps on the system-player / save buttons
  // were spawning duplicate downloads to the same destination, corrupting
  // the output file and pinning the WebView event loop.
  bool _isSaving = false;
  bool _isOpeningExternal = false;
  bool _disposed = false;
  // Cancel signal for the in-flight save. Completed when the user dismisses
  // the dialog mid-download so we stop pulling bytes and clean up the
  // partial file instead of writing into a destination the user is no
  // longer watching.
  Completer<void>? _saveCancel;
  // Path to a temp HTML wrapper written next to a local media file so
  // WKWebView can load `file://` resources (it refuses to do so when the
  // page itself was loaded via `loadHtmlString`/`about:blank`).
  String? _tempHtmlPath;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'OpenHandMedia',
        onMessageReceived: _handleMediaMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageLoaded = true);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loadError = error.description;
            });
          },
        ),
      );
    // `setBackgroundColor` on macOS bridges to `WKWebView.setOpaque`, which
    // is unimplemented in the wkwebview plugin and throws
    // `UnimplementedError: opaque is not implemented on macOS`. Skip the
    // call there — the dialog already uses a transparent overlay so the
    // default WKWebView background is acceptable.
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(Colors.transparent);
    }
    _bootstrapMediaPage();
    _loadTimeoutTimer = Timer(_mediaLoadTimeout, () {
      if (!mounted || _mediaReady) return;
      setState(() {
        _loadError = _localizedText(
          context,
          zh: '载入超时，可使用系统播放器打开。',
          en: 'Loading timed out. Open with the system player instead.',
        );
      });
    });
  }

  // For local `file://` media we must write the HTML wrapper next to the
  // video so WKWebView can grant `file://` read access to the parent
  // directory via `loadFileURL:allowingReadAccessToURL:`. Loading the same
  // HTML via `loadHtmlString` works on Android/iOS Safari but WKWebView on
  // macOS silently refuses to fetch the `<source src="file://...">` entry,
  // resulting in the existing 18s timeout fallback.
  Future<void> _bootstrapMediaPage() async {
    final localPath = widget.source.filePath;
    if (localPath != null && File(localPath).existsSync()) {
      try {
        final dir = p.dirname(localPath);
        final tempName =
            '.openhand_media_player_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
        final tempFile = File(p.join(dir, tempName));
        await tempFile.writeAsString(_buildMediaHtml(localOverride: localPath));
        if (!mounted) {
          await tempFile.delete().catchError((_) => tempFile);
          return;
        }
        _tempHtmlPath = tempFile.path;
        await _controller.loadFile(tempFile.path);
        return;
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'media preview: loadFile fallback failed',
          error,
          stack,
        );
        // Fall through to loadHtmlString — worst case the user still sees
        // the timeout fallback and can use the system player button.
      }
    }
    if (!mounted) return;
    await _controller.loadHtmlString(_buildMediaHtml());
  }

  @override
  void dispose() {
    _disposed = true;
    _loadTimeoutTimer?.cancel();
    final pending = _saveCancel;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _saveCancel = null;
    final tempPath = _tempHtmlPath;
    if (tempPath != null) {
      // Best-effort cleanup; ignore failures (file may already be gone).
      Future<void>(() async {
        try {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'media preview: temp html cleanup failed',
            error,
            stack,
          );
        }
      });
    }
    super.dispose();
  }

  void _handleMediaMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final value = message.message.trim();
    if (value == 'ready' || value == 'canplay' || value == 'loadedmetadata') {
      _loadTimeoutTimer?.cancel();
      setState(() {
        _mediaReady = true;
        _loadError = null;
      });
      return;
    }
    if (value.startsWith('error')) {
      setState(() {
        _loadError = value.length > 6 ? value.substring(6) : value;
      });
    }
  }

  String _buildMediaHtml({String? localOverride}) {
    final rawSource = localOverride != null
        ? Uri.file(localOverride).toString()
        : widget.source.uri.toString();
    final source = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(rawSource);
    final isVideo = widget.source.kind == _GeneratedMessageMediaKind.video;
    final mimeType = _mimeTypeForGeneratedMedia(widget.source);
    final escapedMime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(mimeType);
    final mediaTag = isVideo
        ? '<video id="media" controls playsinline preload="metadata"><source src="$source" type="$escapedMime"></video>'
        : '<audio id="media" controls preload="metadata"><source src="$source" type="$escapedMime"></audio>';
    return '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; }
body { display: flex; align-items: center; justify-content: center; overflow: hidden; }
video { width: 100%; height: 100%; max-height: 100vh; background: #000; object-fit: contain; }
audio { width: min(680px, calc(100vw - 24px)); }
</style>
</head>
<body>
$mediaTag
<script>
(function() {
  const media = document.getElementById('media');
  const post = (value) => {
    if (window.OpenHandMedia && window.OpenHandMedia.postMessage) {
      window.OpenHandMedia.postMessage(value);
    }
  };
  ['loadedmetadata', 'canplay', 'playing'].forEach((eventName) => {
    media.addEventListener(eventName, () => post(eventName));
  });
  media.addEventListener('error', () => {
    const err = media.error ? String(media.error.code) : 'unknown';
    post('error:' + err);
  });
  setTimeout(() => {
    if (!media || media.readyState === 0) post('error:timeout');
  }, ${_mediaLoadTimeout.inMilliseconds});
})();
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isVideo = widget.source.kind == _GeneratedMessageMediaKind.video;
    final mediaHeight = isVideo
        ? MediaQuery.sizeOf(context).height * 0.68
        : 126.0;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.92, 960),
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(
                    isVideo ? Icons.videocam_outlined : Icons.audiotrack,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _localizedText(
                      context,
                      zh: '使用系统播放器打开',
                      en: 'Open with System Player',
                    ),
                    onPressed: () => _openInSystemPlayer(context),
                  ),
                  const SizedBox(width: 4),
                  if (isVideo) ...[
                    IconButton(
                      icon: Icon(
                        Icons.fullscreen_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      tooltip: _localizedText(
                        context,
                        zh: '全屏沉浸播放',
                        en: 'Fullscreen playback',
                      ),
                      onPressed: () => _enterFullscreen(context),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    icon: Icon(
                      Icons.download_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _localizedText(
                      context,
                      zh: '保存到本地',
                      en: 'Save to disk',
                    ),
                    onPressed: () => _saveMediaAs(context),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: mediaHeight,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: WebViewWidget(controller: _controller),
                        ),
                        if (!_pageLoaded ||
                            (!_mediaReady && _loadError == null))
                          const Center(
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          ),
                        if (_loadError != null)
                          _MediaLoadFallback(
                            message: _loadError!,
                            onOpenExternal: () => _openInSystemPlayer(context),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInSystemPlayer(BuildContext context) async {
    if (_isOpeningExternal) return;
    _isOpeningExternal = true;
    try {
      final filePath = widget.source.filePath;
      if (filePath != null) {
        await _openLocalPathWithSystemApp(context, filePath);
        return;
      }
      await _openMessageLinkUri(context, widget.source.uri);
    } finally {
      if (!_disposed) _isOpeningExternal = false;
    }
  }

  Future<void> _enterFullscreen(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    // Pop the dialog so the existing WebView is torn down before we mount
    // the fullscreen route. Two simultaneous WKWebView instances pointing
    // at the same `file://` resource can race on the read-access grant.
    navigator.pop();
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            _FullscreenVideoPage(source: widget.source, title: widget.title),
      ),
    );
  }

  Future<void> _saveMediaAs(BuildContext context) async {
    if (_isSaving) return;
    _isSaving = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void showSnack(String zh, String en) {
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(_localizedText(context, zh: zh, en: en))),
      );
    }

    try {
      final basename = _suggestedSaveName();
      final ext = _normalizeMediaSaveExtension(
        p.extension(basename).toLowerCase(),
        widget.source.kind,
      );
      final location = await getSaveLocation(
        suggestedName: _replaceExtensionIfNeeded(basename, ext),
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: widget.source.kind == _GeneratedMessageMediaKind.video
                ? 'Videos'
                : 'Audio',
            mimeTypes: <String>[_mimeTypeForExtension(ext)],
            extensions: <String>[ext.replaceFirst('.', '')],
          ),
        ],
      );
      if (location == null) return;
      showSnack('正在保存…', 'Saving…');
      final filePath = widget.source.filePath;
      if (filePath != null) {
        final source = File(filePath);
        if (!source.existsSync()) {
          throw FileSystemException('Media source file is missing.', filePath);
        }
        await source.copy(location.path);
        showSnack('已保存到：${location.path}', 'Saved to: ${location.path}');
        return;
      }
      final cancel = Completer<void>();
      _saveCancel = cancel;
      try {
        await _downloadRemoteMedia(
          widget.source,
          location.path,
          cancelSignal: cancel.future,
        );
        showSnack('已保存到：${location.path}', 'Saved to: ${location.path}');
      } finally {
        if (identical(_saveCancel, cancel)) _saveCancel = null;
      }
    } on _MediaDownloadCancelled {
      showSnack('已取消保存。', 'Save cancelled.');
    } on TimeoutException catch (error) {
      showSnack('保存超时：${error.message ?? ''}',
          'Save timed out: ${error.message ?? ''}');
    } catch (error) {
      showSnack('保存失败：$error', 'Save failed: $error');
    } finally {
      if (!_disposed) _isSaving = false;
    }
  }

  String _suggestedSaveName() {
    final filePath = widget.source.filePath;
    if (filePath != null) {
      final basename = p.basename(filePath).trim();
      if (basename.isNotEmpty) return basename;
    }
    final decodedPath = () {
      try {
        return Uri.decodeFull(widget.source.uri.path);
      } catch (_) {
        return widget.source.uri.path;
      }
    }();
    final basename = p.basename(decodedPath).trim();
    if (basename.isNotEmpty && basename != '/' && basename != '.') {
      return basename;
    }
    final prefix = widget.source.kind == _GeneratedMessageMediaKind.video
        ? 'video'
        : 'audio';
    final ext = widget.source.kind == _GeneratedMessageMediaKind.video
        ? '.mp4'
        : '.mp3';
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}$ext';
  }
}

class _MediaLoadFallback extends StatelessWidget {
  const _MediaLoadFallback({
    required this.message,
    required this.onOpenExternal,
  });

  final String message;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                _localizedText(context, zh: '系统播放器', en: 'System Player'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_GeneratedMediaSource? _resolveGeneratedMediaSource(
  String href,
  List<String> pathRoots, {
  _GeneratedMessageMediaKind? kindHint,
}) {
  final decodedHref = () {
    try {
      return Uri.decodeFull(href);
    } catch (_) {
      return href;
    }
  }();
  final parsed = Uri.tryParse(href);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    final kind =
        _generatedMediaKindForText(parsed.path.isEmpty ? href : parsed.path) ??
        kindHint;
    if (kind == null) return null;
    return _GeneratedMediaSource(kind: kind, uri: parsed);
  }
  if (parsed != null && parsed.scheme == 'file') {
    try {
      final filePath = parsed.toFilePath();
      final kind = _generatedMediaKindForText(filePath) ?? kindHint;
      if (kind == null || !_cachedMarkdownImageFileExists(filePath)) {
        return null;
      }
      return _GeneratedMediaSource(
        kind: kind,
        uri: Uri.file(filePath),
        filePath: filePath,
      );
    } catch (_) {
      return null;
    }
  }
  if (decodedHref.startsWith('/')) {
    final kind = _generatedMediaKindForText(decodedHref) ?? kindHint;
    if (kind != null && _cachedMarkdownImageFileExists(decodedHref)) {
      return _GeneratedMediaSource(
        kind: kind,
        uri: Uri.file(decodedHref),
        filePath: decodedHref,
      );
    }
  }
  final resolvedPath = resolveMarkdownMessageLinkPath(decodedHref, pathRoots);
  if (resolvedPath == null || resolvedPath.isDirectory) return null;
  final kind =
      _generatedMediaKindForText(resolvedPath.resolvedPath) ?? kindHint;
  if (kind == null ||
      !_cachedMarkdownImageFileExists(resolvedPath.resolvedPath)) {
    return null;
  }
  return _GeneratedMediaSource(
    kind: kind,
    uri: Uri.file(resolvedPath.resolvedPath),
    filePath: resolvedPath.resolvedPath,
  );
}

_GeneratedMessageMediaKind? _generatedMediaKindForText(String value) {
  final extension = p
      .extension(Uri.tryParse(value)?.path ?? value)
      .toLowerCase();
  if (_videoMediaExtensions.contains(extension)) {
    return _GeneratedMessageMediaKind.video;
  }
  if (_audioMediaExtensions.contains(extension)) {
    return _GeneratedMessageMediaKind.audio;
  }
  return null;
}

_GeneratedMessageMediaKind? _generatedMediaKindForLabel(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('video')) {
    return _GeneratedMessageMediaKind.video;
  }
  if (normalized.contains('audio') || normalized.contains('speech')) {
    return _GeneratedMessageMediaKind.audio;
  }
  return null;
}

_GeneratedMessageMediaKind? _generatedMediaKindFromStorage(String? value) {
  return switch (value) {
    'video' => _GeneratedMessageMediaKind.video,
    'audio' => _GeneratedMessageMediaKind.audio,
    _ => null,
  };
}

String _generatedMediaFallbackTitle(_GeneratedMediaSource source) {
  final filePath = source.filePath;
  if (filePath != null) return p.basename(filePath);
  final basename = p.basename(source.uri.path).trim();
  if (basename.isNotEmpty && basename != '/' && basename != '.') {
    return basename;
  }
  return source.kind == _GeneratedMessageMediaKind.video
      ? 'AI Generated Video'
      : 'AI Generated Audio';
}

String _mimeTypeForGeneratedMedia(_GeneratedMediaSource source) {
  return _mimeTypeForExtension(
    p.extension(source.filePath ?? source.uri.path).toLowerCase(),
  );
}

String _mimeTypeForExtension(String extension) {
  return switch (extension) {
    '.mp4' || '.m4v' => 'video/mp4',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.mkv' => 'video/x-matroska',
    '.mp3' => 'audio/mpeg',
    '.wav' => 'audio/wav',
    '.m4a' => 'audio/mp4',
    '.aac' => 'audio/aac',
    '.ogg' || '.opus' => 'audio/ogg',
    '.flac' => 'audio/flac',
    _ => 'application/octet-stream',
  };
}

String _normalizeMediaSaveExtension(
  String extension,
  _GeneratedMessageMediaKind kind,
) {
  if (kind == _GeneratedMessageMediaKind.video &&
      _videoMediaExtensions.contains(extension)) {
    return extension;
  }
  if (kind == _GeneratedMessageMediaKind.audio &&
      _audioMediaExtensions.contains(extension)) {
    return extension;
  }
  return kind == _GeneratedMessageMediaKind.video ? '.mp4' : '.mp3';
}

String _replaceExtensionIfNeeded(String basename, String extension) {
  final current = p.extension(basename);
  if (current.toLowerCase() == extension) return basename;
  if (current.isEmpty) return '$basename$extension';
  return '${basename.substring(0, basename.length - current.length)}$extension';
}

Future<void> _downloadRemoteMedia(
  _GeneratedMediaSource source,
  String destination, {
  Future<void>? cancelSignal,
}) async {
  final scheme = source.uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FileSystemException(
      'Unsupported media URI scheme: ${source.uri.scheme}',
      source.uri.toString(),
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var cancelled = false;
  cancelSignal?.whenComplete(() {
    cancelled = true;
    client.close(force: true);
  });
  try {
    final request = await client
        .getUrl(source.uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} while downloading media.',
        uri: source.uri,
      );
    }
    final contentType = response.headers.contentType;
    final expectedPrimary = source.kind == _GeneratedMessageMediaKind.video
        ? 'video'
        : 'audio';
    if (contentType != null &&
        contentType.primaryType != expectedPrimary &&
        contentType.mimeType != 'application/octet-stream') {
      throw HttpException(
        'Unexpected content type: ${contentType.mimeType}',
        uri: source.uri,
      );
    }
    final maxBytes = source.kind == _GeneratedMessageMediaKind.video
        ? 2 * 1024 * 1024 * 1024
        : 256 * 1024 * 1024;
    final downloadDeadline = DateTime.now().add(
      source.kind == _GeneratedMessageMediaKind.video
          ? const Duration(minutes: 20)
          : const Duration(minutes: 5),
    );
    final outputFile = File(destination);
    final output = outputFile.openWrite();
    var receivedBytes = 0;
    var outputClosed = false;

    Future<void> closeOutput() async {
      if (outputClosed) return;
      outputClosed = true;
      await output.close();
    }

    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (cancelled) {
          throw const _MediaDownloadCancelled();
        }
        if (DateTime.now().isAfter(downloadDeadline)) {
          throw TimeoutException('Media download exceeded time limit.');
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxBytes) {
          throw FileSystemException(
            'Media download exceeded size limit.',
            destination,
          );
        }
        output.add(chunk);
      }
      await output.flush();
    } catch (error, stack) {
      try {
        await closeOutput();
      } catch (closeError, closeStack) {
        silentLog(
          'home_message_bubble',
          'close failed media download stream',
          closeError,
          closeStack,
        );
      }
      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } on FileSystemException catch (cleanupError, cleanupStack) {
        silentLog(
          'home_message_bubble',
          'delete partial media download',
          cleanupError,
          cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (!outputClosed) {
        await output.close();
      }
    }
  } finally {
    client.close(force: true);
  }
}

const Set<String> _videoMediaExtensions = <String>{
  '.mp4',
  '.webm',
  '.mov',
  '.m4v',
  '.mkv',
};

class _MediaDownloadCancelled implements Exception {
  const _MediaDownloadCancelled();
  @override
  String toString() => 'Media download cancelled by caller.';
}

const Set<String> _audioMediaExtensions = <String>{
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.flac',
};

/// Small capsule rendered directly under a user message timestamp when the
/// message was sent with a non-text creation mode (image / video / audio / deep
/// research). Lets the reader tell at a glance what action the message is
/// asking for even after the composer chip is gone.
class _CreationModeChip extends StatelessWidget {
  const _CreationModeChip({required this.request, required this.textColor});

  final AiCreationRequest request;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (!request.isActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (icon, labelZh, labelEn) = switch (request.mode) {
      AiCreationMode.image => (Icons.image_outlined, '图片生成', 'Image'),
      AiCreationMode.video => (Icons.videocam_outlined, '视频生成', 'Video'),
      AiCreationMode.audio => (Icons.audiotrack_outlined, '音频生成', 'Audio'),
      AiCreationMode.deepResearch => (
        Icons.travel_explore_rounded,
        '深度研究',
        'Deep Research',
      ),
      AiCreationMode.none => (Icons.circle_outlined, '', ''),
    };
    final options = request.options;
    final detailParts = <String>[
      if (options.aspectRatio != null) options.aspectRatio!,
      if (options.size != null && options.aspectRatio == null) options.size!,
      if (options.durationSeconds != null) '${options.durationSeconds}s',
      if (options.count != 1) 'x${options.count}',
    ];
    final label = _localizedText(context, zh: labelZh, en: labelEn);
    final detail = detailParts.isEmpty ? '' : ' · ${detailParts.join(' · ')}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: textColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: textColor.withValues(alpha: 0.9)),
            const SizedBox(width: 4),
            Text(
              '$label$detail',
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Capsule rendered under a user message timestamp when the message was
/// submitted with an explicit local-skill selection (e.g. `/caveman`).
/// Mirrors [_CreationModeChip] so the transcript conveys at a glance which
/// skill was activated for the turn.
class _UserSkillSelectionChip extends StatelessWidget {
  const _UserSkillSelectionChip({
    required this.metadata,
    required this.textColor,
  });

  final Object? metadata;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (metadata is! Map) return const SizedBox.shrink();
    final map = Map<String, Object?>.from(metadata as Map);
    final name = (map['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return const SizedBox.shrink();
    final emoji = (map['emoji'] as String?)?.trim();
    final iconPath = (map['icon_path'] as String?)?.trim();
    final iconKind = (map['icon_kind'] as String?)?.trim();
    final theme = Theme.of(context);
    final leading = _buildLeading(emoji, iconPath, iconKind);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: textColor.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 4),
            ] else ...[
              Icon(
                Icons.extension_rounded,
                size: 12,
                color: textColor.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildLeading(String? emoji, String? iconPath, String? iconKind) {
    if (emoji != null && emoji.isNotEmpty) {
      return Text(emoji, style: const TextStyle(fontSize: 12, height: 1.0));
    }
    if (iconPath != null && iconPath.isNotEmpty && iconKind == 'raster') {
      return SizedBox(
        width: 14,
        height: 14,
        child: Image.file(
          File(iconPath),
          width: 14,
          height: 14,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    return null;
  }
}

/// Coordinates one-shot first-frame capture for local video files.
///
/// We render the existing `webview_flutter` stack (no new deps) inside an
/// `Offstage` host, ask the page to seek to ~0.1s, draw the first frame to
/// a 480px-wide canvas, and post the dataURL back through a JS channel.
/// The PNG is persisted next to the source video as `<video>.thumb.png` so
/// future card mounts simply read the cached file via `Image.file`.
///
/// Concurrency is intentionally capped at one capture in flight so the
/// UI never spawns multiple WKWebView platform views simultaneously,
/// which has historically caused jank/ANR on macOS. Subsequent requesters
/// queue and inherit the slot when the previous capture finishes.
class _VideoThumbnailManager {
  static final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  static int _active = 0;
  static const int _maxActive = 1;
  // Per-process retry guard: if a capture failed once we don't keep
  // re-creating WebViews for the same file in the same session.
  static final Set<String> _failed = <String>{};

  static String thumbnailPathFor(String videoPath) => '$videoPath.thumb.png';

  static bool isMarkedFailed(String videoPath) => _failed.contains(videoPath);
  static void _markFailed(String videoPath) => _failed.add(videoPath);

  static Future<void> _acquireSlot() {
    if (_active < _maxActive) {
      _active += 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  static void _releaseSlot() {
    if (_active > 0) _active -= 1;
    if (_active < _maxActive && _waiters.isNotEmpty) {
      _active += 1;
      _waiters.removeFirst().complete();
    }
  }
}

/// Offstage WebView that captures a single first-frame PNG for a local
/// video file. Removes itself by calling `onResult` (which the parent
/// uses to swap the card to `Image.file`).
class _VideoThumbnailCaptureHost extends StatefulWidget {
  const _VideoThumbnailCaptureHost({
    required this.videoPath,
    required this.mimeType,
    required this.onResult,
  });

  final String videoPath;
  final String mimeType;
  final void Function(String? thumbPath) onResult;

  @override
  State<_VideoThumbnailCaptureHost> createState() =>
      _VideoThumbnailCaptureHostState();
}

class _VideoThumbnailCaptureHostState
    extends State<_VideoThumbnailCaptureHost> {
  WebViewController? _controller;
  String? _tempHtmlPath;
  bool _slotHeld = false;
  bool _done = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _VideoThumbnailManager._acquireSlot();
    _slotHeld = true;
    if (!mounted) {
      _finish(null);
      return;
    }
    try {
      final dir = p.dirname(widget.videoPath);
      final tempName =
          '.openhand_thumb_capture_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
      final tempFile = File(p.join(dir, tempName));
      await tempFile.writeAsString(_buildCaptureHtml());
      _tempHtmlPath = tempFile.path;
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'OpenHandThumb',
          onMessageReceived: _onMessage,
        );
      if (!Platform.isMacOS) {
        controller.setBackgroundColor(Colors.transparent);
      }
      _controller = controller;
      await controller.loadFile(tempFile.path);
      if (!mounted) {
        _finish(null);
        return;
      }
      // Watchdog: if no message arrives within the budget, bail out so
      // the slot is released and the card stops trying for this session.
      _watchdog = Timer(const Duration(seconds: 14), () {
        if (!_done) _finish(null);
      });
      setState(() {});
    } catch (error, stack) {
      silentLog(
        'home_message_bubble',
        'video thumbnail: setup failed',
        error,
        stack,
      );
      _finish(null);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    if (_done) return;
    final value = message.message;
    if (value.startsWith('error')) {
      _finish(null);
      return;
    }
    const marker = 'base64,';
    final idx = value.indexOf(marker);
    if (idx < 0) {
      _finish(null);
      return;
    }
    final b64 = value.substring(idx + marker.length);
    Future<void>(() async {
      try {
        final bytes = base64.decode(b64);
        final outPath = _VideoThumbnailManager.thumbnailPathFor(
          widget.videoPath,
        );
        await File(outPath).writeAsBytes(bytes, flush: true);
        _finish(outPath);
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'video thumbnail: write failed',
          error,
          stack,
        );
        _finish(null);
      }
    });
  }

  void _finish(String? path) {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    if (path == null) _VideoThumbnailManager._markFailed(widget.videoPath);
    final temp = _tempHtmlPath;
    if (temp != null) {
      Future<void>(() async {
        try {
          final f = File(temp);
          if (await f.exists()) await f.delete();
        } catch (_) {
          // best effort
        }
      });
    }
    if (_slotHeld) {
      _slotHeld = false;
      _VideoThumbnailManager._releaseSlot();
    }
    widget.onResult(path);
  }

  @override
  void dispose() {
    if (!_done) {
      _done = true;
      _watchdog?.cancel();
      final temp = _tempHtmlPath;
      if (temp != null) {
        Future<void>(() async {
          try {
            final f = File(temp);
            if (await f.exists()) await f.delete();
          } catch (_) {
            // best effort
          }
        });
      }
      if (_slotHeld) {
        _slotHeld = false;
        _VideoThumbnailManager._releaseSlot();
      }
    }
    super.dispose();
  }

  String _buildCaptureHtml() {
    final src = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(Uri.file(widget.videoPath).toString());
    final mime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(widget.mimeType);
    return '''
<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:#000;width:100%;height:100%}video,canvas{display:none}</style></head><body>
<video id="v" muted playsinline preload="auto" crossorigin="anonymous"><source src="$src" type="$mime"></video>
<canvas id="c"></canvas>
<script>(function(){
var v=document.getElementById('v');var c=document.getElementById('c');
function post(m){if(window.OpenHandThumb&&window.OpenHandThumb.postMessage){window.OpenHandThumb.postMessage(m);}}
var captured=false;
function capture(){
  if(captured)return;captured=true;
  try{
    var w=v.videoWidth, h=v.videoHeight;
    if(!w||!h){post('error:no_video_dim');return;}
    var tw=Math.min(480,w);
    var th=Math.round(h*(tw/w));
    c.width=tw;c.height=th;
    var ctx=c.getContext('2d');
    ctx.drawImage(v,0,0,tw,th);
    post(c.toDataURL('image/png'));
  }catch(e){post('error:'+(e&&e.message||'capture'));}
}
v.addEventListener('loadeddata',function(){
  try{var t=Math.min(0.1,(v.duration||0));v.currentTime=t;}catch(e){capture();}
});
v.addEventListener('seeked',capture);
v.addEventListener('error',function(){post('error:video_load');});
setTimeout(function(){if(!captured)post('error:timeout');},10000);
})();</script>
</body></html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox.shrink();
    // Tiny visible footprint so the platform view actually paints (some
    // platform-view embedders skip 0x0 hosts), but offstage so it never
    // affects layout or hit-testing.
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(opacity: 0, child: WebViewWidget(controller: ctrl)),
    );
  }
}

/// Black-screen fullscreen route for immersive video playback. Reuses the
/// `loadFile` trick from `_MediaPreviewDialog` so WKWebView can grant
/// `file://` read access to the parent directory.
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.source, required this.title});

  final _GeneratedMediaSource source;
  final String title;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late final WebViewController _controller;
  String? _tempHtmlPath;
  bool _ready = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _ready = true);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _loadError = error.description);
          },
        ),
      );
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(Colors.black);
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final localPath = widget.source.filePath;
    if (localPath != null && File(localPath).existsSync()) {
      try {
        final dir = p.dirname(localPath);
        final tempName =
            '.openhand_fullscreen_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}.html';
        final tempFile = File(p.join(dir, tempName));
        await tempFile.writeAsString(_buildHtml(localOverride: localPath));
        if (!mounted) {
          await tempFile.delete().catchError((_) => tempFile);
          return;
        }
        _tempHtmlPath = tempFile.path;
        await _controller.loadFile(tempFile.path);
        return;
      } catch (error, stack) {
        silentLog(
          'home_message_bubble',
          'fullscreen video: loadFile fallback failed',
          error,
          stack,
        );
      }
    }
    if (!mounted) return;
    await _controller.loadHtmlString(_buildHtml());
  }

  String _buildHtml({String? localOverride}) {
    final raw = localOverride != null
        ? Uri.file(localOverride).toString()
        : widget.source.uri.toString();
    final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(raw);
    final mime = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(_mimeTypeForGeneratedMedia(widget.source));
    return '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1.0"><style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}video{width:100vw;height:100vh;background:#000;object-fit:contain}</style></head><body>
<video id="media" controls autoplay playsinline preload="auto"><source src="$src" type="$mime"></video>
</body></html>
''';
  }

  @override
  void dispose() {
    final tmp = _tempHtmlPath;
    if (tmp != null) {
      Future<void>(() async {
        try {
          final f = File(tmp);
          if (await f.exists()) await f.delete();
        } catch (error, stack) {
          silentLog(
            'home_message_bubble',
            'fullscreen video: temp html cleanup failed',
            error,
            stack,
          );
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            if (!_ready && _loadError == null)
              const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white70,
                ),
              ),
            if (_loadError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                  tooltip: _localizedText(
                    context,
                    zh: '返回',
                    en: 'Back',
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            if (widget.title.isNotEmpty)
              Positioned(
                top: 16,
                left: 64,
                right: 16,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

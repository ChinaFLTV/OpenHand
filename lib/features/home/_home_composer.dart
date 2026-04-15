part of 'openhand_home_page.dart';

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    super.key,
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.controller,
    required this.selectedModel,
    required this.availableModels,
    required this.recentModelSelections,
    required this.onModelSelected,
    required this.focusNode,
    required this.composerHeight,
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.pendingAttachments,
    required this.attachmentsEnabled,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onReorderAttachments,
    required this.onSend,
    required this.onStop,
    required this.creationMode,
    required this.onCreationModeChanged,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.queuedMessages,
    required this.onRemoveQueuedMessage,
    required this.onMoveQueuedMessage,
    required this.onEditQueuedMessage,
    this.projectRoot,
  });

  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode focusNode;
  final double composerHeight;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final List<_ComposerAttachmentDraft> pendingAttachments;
  final bool attachmentsEnabled;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(int oldIndex, int newIndex) onReorderAttachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final List<_QueuedMessage> queuedMessages;
  final ValueChanged<int> onRemoveQueuedMessage;
  final void Function(int from, int to) onMoveQueuedMessage;
  final void Function(int index, String newText) onEditQueuedMessage;
  final String? projectRoot;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  final LayerLink _atMentionLayerLink = LayerLink();
  OverlayEntry? _atMentionOverlay;
  List<_AtMentionItem> _atMentionResults = const [];
  int _atMentionSelectedIndex = 0;
  int _atMentionTriggerOffset = -1;
  String _atMentionCurrentDirectory = '';
  // Breadcrumb path segments for directory drilling.
  List<String> _atMentionBreadcrumbs = const [];
  bool _atMentionLoading = false;
  bool _atMentionSuppressListener = false;
  // Offset of a dismissed '@' – prevents re-triggering the popup for the
  // same '@' character after the user explicitly closed it.
  int _atMentionDismissedOffset = -1;
  // Project file/directory references selected via the @ mention overlay.
  List<_AtMentionItem> _projectFileReferences = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChangedForAtMention);
  }

  @override
  void didUpdateWidget(covariant _ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChangedForAtMention);
      widget.controller.addListener(_handleTextChangedForAtMention);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChangedForAtMention);
    _dismissAtMentionOverlay();
    super.dispose();
  }

  // ── @ mention detection ──

  void _handleTextChangedForAtMention() {
    if (_atMentionSuppressListener) return;
    final root = widget.projectRoot;
    if (root == null || root.isEmpty) {
      _dismissAtMentionOverlay();
      return;
    }
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _dismissAtMentionOverlay();
      return;
    }
    final cursor = selection.baseOffset;
    // Scan backwards from cursor to find a '@' anchor.
    int atIndex = -1;
    for (var i = cursor - 1; i >= 0; i--) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x40 /* @ */) {
        atIndex = i;
        break;
      }
      // Stop scanning at any whitespace (space, tab, newline, carriage-return).
      // Once the user types a space after the query, the mention is abandoned.
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D) {
        break;
      }
    }
    if (atIndex < 0) {
      _dismissAtMentionOverlay();
      return;
    }
    // The character before @ must be start-of-text or whitespace.
    if (atIndex > 0) {
      final prev = text.codeUnitAt(atIndex - 1);
      if (prev != 0x20 && prev != 0x0A && prev != 0x0D && prev != 0x09) {
        _dismissAtMentionOverlay();
        return;
      }
    }
    // If the user previously dismissed the popup for this exact '@' offset
    // AND the '@' character at that offset is still the same one (not a newly
    // typed '@'), do not re-trigger.
    if (atIndex == _atMentionDismissedOffset) {
      return;
    }
    _atMentionDismissedOffset = -1;
    final query = text.substring(atIndex + 1, cursor);
    _atMentionTriggerOffset = atIndex;
    _performAtMentionSearch(root, query);
  }

  Future<void> _performAtMentionSearch(String rootPath, String query) async {
    if (!mounted) return;
    setState(() => _atMentionLoading = true);
    final basePath = _atMentionCurrentDirectory.isEmpty
        ? rootPath
        : p.join(rootPath, _atMentionCurrentDirectory);
    final trimmedQuery = query.trim().toLowerCase();
    final results = <_AtMentionItem>[];
    try {
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        setState(() {
          _atMentionResults = const [];
          _atMentionLoading = false;
        });
        _showAtMentionOverlay();
        return;
      }
      final entries = await dir.list().toList();
      entries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(
          p.basename(b.path).toLowerCase(),
        );
      });
      for (final entry in entries) {
        if (results.length >= 50) break;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        const ignored = {
          'node_modules', 'build', '.dart_tool', '__pycache__',
          '.git', '.idea', '.vscode', 'target', 'dist', '.gradle',
        };
        if (ignored.contains(name)) continue;
        if (trimmedQuery.isEmpty || name.toLowerCase().contains(trimmedQuery)) {
          final relativePath = p.relative(entry.path, from: rootPath);
          results.add(_AtMentionItem(
            name: name,
            path: entry.path,
            relativePath: relativePath,
            isDirectory: entry is Directory,
          ));
        }
      }
      // If trimmedQuery is non-empty and we have few results, also search
      // recursively for deeper matches (up to 80 total).
      if (trimmedQuery.isNotEmpty && results.length < 20) {
        await _deepSearchAtMention(
          Directory(rootPath),
          trimmedQuery,
          results,
          rootPath,
          0,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _atMentionResults = results;
      _atMentionSelectedIndex = 0;
      _atMentionLoading = false;
    });
    _showAtMentionOverlay();
  }

  Future<void> _deepSearchAtMention(
    Directory dir,
    String query,
    List<_AtMentionItem> results,
    String rootPath,
    int depth,
  ) async {
    if (depth > 8 || results.length >= 80) return;
    try {
      final entries = await dir.list().toList();
      for (final entry in entries) {
        if (results.length >= 80) return;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        const ignored = {
          'node_modules', 'build', '.dart_tool', '__pycache__',
          '.git', '.idea', '.vscode', 'target', 'dist', '.gradle',
        };
        if (ignored.contains(name)) continue;
        final relativePath = p.relative(entry.path, from: rootPath);
        // Avoid duplicates already in the shallow list.
        if (name.toLowerCase().contains(query) &&
            !results.any((r) => r.path == entry.path)) {
          results.add(_AtMentionItem(
            name: name,
            path: entry.path,
            relativePath: relativePath,
            isDirectory: entry is Directory,
          ));
        }
        if (entry is Directory) {
          await _deepSearchAtMention(entry, query, results, rootPath, depth + 1);
        }
      }
    } catch (_) {}
  }

  void _showAtMentionOverlay() {
    if (_atMentionOverlay != null) {
      _atMentionOverlay!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    _atMentionOverlay = OverlayEntry(
      builder: (ctx) {
        return _AtMentionOverlayPanel(
          link: _atMentionLayerLink,
          items: _atMentionResults,
          selectedIndex: _atMentionSelectedIndex,
          loading: _atMentionLoading,
          breadcrumbs: _atMentionBreadcrumbs,
          onSelect: _handleAtMentionSelect,
          onDrillDown: _handleAtMentionDrillDown,
          onBreadcrumbTap: _handleAtMentionBreadcrumbTap,
          onDismiss: _userDismissAtMentionOverlay,
        );
      },
    );
    overlay.insert(_atMentionOverlay!);
  }

  /// Dismiss triggered by user action (click outside / Escape).
  /// Remembers the '@' offset so the popup won't re-trigger for the same '@'.
  void _userDismissAtMentionOverlay() {
    if (_atMentionTriggerOffset >= 0) {
      _atMentionDismissedOffset = _atMentionTriggerOffset;
    }
    _dismissAtMentionOverlay();
  }

  void _dismissAtMentionOverlay() {
    _atMentionOverlay?.remove();
    _atMentionOverlay = null;
    if (_atMentionTriggerOffset >= 0) {
      _atMentionTriggerOffset = -1;
      _atMentionCurrentDirectory = '';
      _atMentionBreadcrumbs = const [];
      _atMentionResults = const [];
    }
    // Validate the dismissed-offset marker: if the '@' at that position
    // no longer exists in the text, clear it so it won't block a future '@'
    // that happens to land at the same offset.
    if (_atMentionDismissedOffset >= 0) {
      final text = widget.controller.text;
      if (_atMentionDismissedOffset >= text.length ||
          text.codeUnitAt(_atMentionDismissedOffset) != 0x40) {
        _atMentionDismissedOffset = -1;
      }
    }
  }

  void _handleAtMentionSelect(_AtMentionItem item) {
    // Add to project file/directory references as a capsule chip.
    if (_projectFileReferences.any((r) => r.path == item.path)) {
      // Already referenced — just dismiss.
      _dismissAtMentionOverlay();
      widget.focusNode.requestFocus();
      return;
    }
    // Remove the '@query' text from the input.
    if (_atMentionTriggerOffset >= 0 &&
        _atMentionTriggerOffset <= widget.controller.text.length) {
      final cursor = widget.controller.selection.baseOffset
          .clamp(0, widget.controller.text.length);
      _atMentionSuppressListener = true;
      try {
        widget.controller.text = widget.controller.text.replaceRange(
          _atMentionTriggerOffset, cursor, '',
        );
        widget.controller.selection = TextSelection.collapsed(
          offset: _atMentionTriggerOffset,
        );
      } finally {
        _atMentionSuppressListener = false;
      }
    }
    setState(() {
      _projectFileReferences = [..._projectFileReferences, item];
    });
    _dismissAtMentionOverlay();
    widget.focusNode.requestFocus();
  }

  void _handleAtMentionDrillDown(_AtMentionItem item) {
    if (!item.isDirectory) return;
    final root = widget.projectRoot;
    if (root == null) return;
    setState(() {
      _atMentionCurrentDirectory = p.relative(item.path, from: root);
      _atMentionBreadcrumbs = p.split(_atMentionCurrentDirectory)
          .where((s) => s.isNotEmpty)
          .toList();
    });
    // Replace the query text after @ with just @
    final textLen = widget.controller.text.length;
    if (_atMentionTriggerOffset >= 0 && _atMentionTriggerOffset < textLen) {
      final cursor = widget.controller.selection.baseOffset
          .clamp(0, textLen);
      final start = _atMentionTriggerOffset + 1;
      if (start <= cursor) {
        _atMentionSuppressListener = true;
        try {
          widget.controller.text = widget.controller.text.replaceRange(
            start, cursor, '',
          );
          widget.controller.selection = TextSelection.collapsed(
            offset: start,
          );
        } finally {
          _atMentionSuppressListener = false;
        }
      }
    }
    _performAtMentionSearch(root, '');
  }

  void _handleAtMentionBreadcrumbTap(int depth) {
    final root = widget.projectRoot;
    if (root == null) return;
    if (depth < 0) {
      // Go back to project root.
      setState(() {
        _atMentionCurrentDirectory = '';
        _atMentionBreadcrumbs = const [];
      });
    } else {
      final newBreadcrumbs = _atMentionBreadcrumbs.sublist(0, depth + 1);
      setState(() {
        _atMentionCurrentDirectory = p.joinAll(newBreadcrumbs);
        _atMentionBreadcrumbs = newBreadcrumbs;
      });
    }
    _performAtMentionSearch(root, '');
  }

  /// Injects project file/directory references into the controller text and
  /// clears the capsule list. Called both from the send button and from the
  /// parent via [GlobalKey] for keyboard-shortcut sends.
  void _injectReferencesIntoText() {
    if (_projectFileReferences.isEmpty) return;
    final refs = _projectFileReferences.map((r) {
      final suffix = r.isDirectory ? '/' : '';
      return '@${r.relativePath}$suffix';
    }).join(' ');
    _atMentionSuppressListener = true;
    try {
      final currentText = widget.controller.text;
      if (currentText.trim().isEmpty) {
        widget.controller.text = refs;
      } else {
        widget.controller.text = '$refs\n$currentText';
      }
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    } finally {
      _atMentionSuppressListener = false;
    }
    setState(() {
      _projectFileReferences = [];
    });
  }

  /// Injects project file/directory references into the prompt text as
  /// `@path` tokens, clears the capsule list, then delegates to [widget.onSend].
  Future<void> _sendWithReferences() async {
    _injectReferencesIntoText();
    await widget.onSend();
  }

  void _showModelMenu(BuildContext btnContext) {
    showModelSearchSelector(
      context: btnContext,
      models: widget.availableModels,
      recentSelections: widget.recentModelSelections,
      selectedConfigId: widget.selectedModel?.id,
      selectedModelId: widget.selectedModel?.modelId,
    ).then((value) {
      if (!mounted || value == null) return;
      widget.onModelSelected(value.$1, value.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedModelLabel =
        widget.selectedModel?.displayName ?? l10n.chatModelButton;
    final isCompressing = widget.sendPhase == AiSendPhase.compressing;
    final isSendingMessage = widget.sendPhase == AiSendPhase.sendingMessage;
    final isResponding = widget.sendPhase == AiSendPhase.responding;
    final isBusy = widget.sendPhase != AiSendPhase.idle;
    final canStopSending = widget.canStopSending;
    final modeToggleEnabled = widget.sendPhase == AiSendPhase.idle;
    final runtimeStatus = widget.currentSession == null
        ? null
        : _runtimeToolCatalogStatus(
            widget.currentSession!,
            livePreview: widget.liveRuntimeToolPreview,
          );
    final sendButtonLabel = canStopSending
        ? _localizedText(context, zh: '停止回答', en: 'Stop Response')
        : switch (widget.sendPhase) {
            AiSendPhase.compressing => _localizedText(
              context,
              zh: '消息压缩中',
              en: 'Compressing Messages',
            ),
            AiSendPhase.sendingMessage => l10n.chatSending,
            AiSendPhase.responding => _localizedText(
              context,
              zh: '停止回答',
              en: 'Stop Response',
            ),
            AiSendPhase.awaitingApproval => _localizedText(
              context,
              zh: '等待批准',
              en: 'Awaiting Approval',
            ),
            AiSendPhase.idle => l10n.composerSend,
          };

    final expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.editingMessageId != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: _borderRadius999,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  _localizedText(
                    context,
                    zh: '正在编辑历史消息',
                    en: 'Editing Previous Message',
                  ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    widget.onCancelEditing();
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.queuedMessages.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.queuedMessages.length,
            itemBuilder: (context, index) {
              final msg = widget.queuedMessages[index];
              final isFirst = index == 0;
              final isLast = index == widget.queuedMessages.length - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      if (msg.attachments.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${msg.attachments.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isFirst
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index - 1),
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: 14,
                          color: isFirst
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '上移',
                          en: 'Move up',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isLast
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index + 1),
                        icon: Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: isLast
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '下移',
                          en: 'Move down',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () async {
                          final edited = await _showEditQueuedMessageDialog(
                            context,
                            msg.text,
                          );
                          if (edited != null && edited.trim().isNotEmpty) {
                            widget.onEditQueuedMessage(index, edited);
                          }
                        },
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '编辑此等待消息',
                          en: 'Edit this queued message',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => widget.onRemoveQueuedMessage(index),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '删除此等待消息',
                          en: 'Remove this queued message',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        if (_projectFileReferences.isNotEmpty) ...[
          _ReorderableProjectReferenceWrap(
            references: _projectFileReferences,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final list = List<_AtMentionItem>.from(_projectFileReferences);
                final item = list.removeAt(oldIndex);
                list.insert(
                  newIndex > oldIndex ? newIndex - 1 : newIndex,
                  item,
                );
                _projectFileReferences = list;
              });
            },
            onRemove: (path) {
              setState(() {
                _projectFileReferences = _projectFileReferences
                    .where((r) => r.path != path)
                    .toList();
              });
            },
          ),
          const SizedBox(height: 8),
        ],
        if (widget.pendingAttachments.isNotEmpty) ...[
          _ReorderableAttachmentWrap(
            attachments: widget.pendingAttachments,
            onReorder: widget.onReorderAttachments,
            onRemove: (filePath) => widget.onRemoveAttachment(filePath),
            onTap: (draft) => _openComposerAttachment(context, draft),
          ),
          const SizedBox(height: 12),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            height: widget.composerHeight,
            child: CompositedTransformTarget(
              link: _atMentionLayerLink,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                expands: true,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(hintText: l10n.composerHint),
              ),
            ),
          ),
        ),
      ],
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Builder(
                  builder: (btnContext) {
                    return OutlinedButton.icon(
                      onPressed: widget.availableModels.isEmpty
                          ? null
                          : () => _showModelMenu(btnContext),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.hub_outlined),
                      label: Text(
                        selectedModelLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: widget.attachmentsEnabled
                      ? _localizedText(
                          context,
                          zh: '选择附件（最多 $aiMessageAttachmentLimit 个，支持图片、文本、代码、表格和 PDF）',
                          en: 'Choose attachments (up to $aiMessageAttachmentLimit; images, text, code, spreadsheets, and PDF)',
                        )
                      : _localizedText(
                          context,
                          zh: '当前模型不支持附件',
                          en: 'The selected model does not support attachments',
                        ),
                  child: OutlinedButton.icon(
                    onPressed: widget.attachmentsEnabled
                        ? widget.onPickAttachments
                        : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      widget.pendingAttachments.isEmpty
                          ? _localizedText(context, zh: '附件', en: 'Attach')
                          : _localizedText(
                              context,
                              zh: '附件 ${widget.pendingAttachments.length}',
                              en: 'Files ${widget.pendingAttachments.length}',
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ComposerFullAccessModeButton(
                  fullAccess: widget.fullAccessPermission,
                  enabled: true,
                  onChanged: (bool value) {
                    if (value != widget.fullAccessPermission) {
                      widget.onToggleFullAccessPermission(value);
                    }
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: _composerModeTooltip(
                    context,
                    widget.sessionMode,
                    runtimeStatus,
                  ),
                  child: _ComposerModeButton(
                    mode: widget.sessionMode,
                    runtimeStatus: runtimeStatus,
                    enabled: modeToggleEnabled,
                    onPressed: () {
                      widget.onSessionModeChanged(
                        widget.sessionMode == AiSessionMode.plan
                            ? AiSessionMode.chat
                            : AiSessionMode.plan,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.isCollapsed ? '展开输入框' : '折叠输入框',
            en: widget.isCollapsed ? 'Expand Composer' : 'Collapse Composer',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: () => widget.onCollapsedChanged(!widget.isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Icon(
                widget.isCollapsed
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.autoFollowEnabled ? '关闭自动滚动' : '开启自动滚动',
            en: widget.autoFollowEnabled
                ? 'Disable Auto Follow'
                : 'Enable Auto Follow',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.onToggleAutoFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: widget.autoFollowEnabled
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: widget.autoFollowEnabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                side: widget.autoFollowEnabled
                    ? null
                    : BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                widget.autoFollowEnabled
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.vertical_align_bottom_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ComposerCreationModeButton(
          creationMode: widget.creationMode,
          onCreationModeChanged: widget.onCreationModeChanged,
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, textValue, _) {
            final hasUserTextOrAttachments =
                textValue.text.trim().isNotEmpty ||
                widget.pendingAttachments.isNotEmpty ||
                _projectFileReferences.isNotEmpty;
            final isQueueingAction = isBusy && hasUserTextOrAttachments;

            return SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: isQueueingAction
                    ? () => _sendWithReferences()
                    : canStopSending && !hasUserTextOrAttachments
                    ? () => widget.onStop()
                    : isBusy
                    ? null
                    : () => _sendWithReferences(),
                icon: isQueueingAction
                    ? const Icon(Icons.queue_play_next_rounded)
                    : canStopSending && !hasUserTextOrAttachments
                    ? const Icon(Icons.stop_rounded)
                    : isCompressing || isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        isResponding
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                label: Text(
                  isQueueingAction
                      ? _localizedText(context, zh: '提前发送', en: 'Queue Message')
                      : canStopSending && !hasUserTextOrAttachments
                      ? _localizedText(
                          context,
                          zh: '停止回答',
                          en: 'Stop Responding',
                        )
                      : sendButtonLabel,
                ),
              ),
            );
          },
        ),
      ],
    );

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubicEmphasized,
        padding: EdgeInsets.fromLTRB(18, 14, 18, widget.isCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: widget.isCollapsed ? 1 : 0,
                end: widget.isCollapsed ? 0 : 1,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              child: expandedContent,
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: value,
                    child: IgnorePointer(
                      ignoring: value < 0.98,
                      child: Opacity(
                        opacity: value.clamp(0, 1).toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              height: widget.isCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

class _ComposerFullAccessModeButton extends StatefulWidget {
  const _ComposerFullAccessModeButton({
    required this.fullAccess,
    required this.enabled,
    required this.onChanged,
  });

  final bool fullAccess;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_ComposerFullAccessModeButton> createState() =>
      _ComposerFullAccessModeButtonState();
}

class _ComposerFullAccessModeButtonState
    extends State<_ComposerFullAccessModeButton> {
  void _showAccessMenu() {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()!
            as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showAnimatedMenu<bool>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<bool>(
          value: false,
          child: Row(
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '默认权限', en: 'Default Access'),
                ),
              ),
              if (!widget.fullAccess)
                const Icon(Icons.check_rounded, size: 20)
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(
                    context,
                    zh: '完全访问权限',
                    en: 'Full Access',
                  ),
                ),
              ),
              if (widget.fullAccess)
                const Icon(Icons.check_rounded, size: 20)
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeLabel = widget.fullAccess
        ? _localizedText(context, zh: '完全访问权限', en: 'Full Access')
        : _localizedText(context, zh: '默认权限', en: 'Default Access');
    final backgroundColor = !widget.enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : widget.fullAccess
        ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !widget.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : widget.fullAccess
        ? const Color(0xFFF59E0B)
        : colorScheme.onSurfaceVariant;
    final borderColor = !widget.enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : widget.fullAccess
        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
        : colorScheme.outlineVariant;

    return OutlinedButton(
      onPressed: widget.enabled ? _showAccessMenu : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.fullAccess
                ? Icons.gpp_maybe_outlined
                : Icons.admin_panel_settings_outlined,
            size: 18,
            color: foregroundColor,
          ),
          const SizedBox(width: 8),
          Text(
            modeLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: foregroundColor,
          ),
        ],
      ),
    );
  }
}

class _ComposerModeButton extends StatelessWidget {
  const _ComposerModeButton({
    required this.mode,
    required this.runtimeStatus,
    required this.enabled,
    required this.onPressed,
  });

  final AiSessionMode mode;
  final _RuntimeToolCatalogStatus? runtimeStatus;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPlanMode = mode == AiSessionMode.plan;
    final modeIcon = _runtimeModeIcon(runtimeStatus, explicitMode: mode);
    final modeLabel = _runtimeModeLabel(
      context,
      runtimeStatus,
      compact: true,
      explicitMode: mode,
    );
    final backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : isPlanMode
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isPlanMode
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final accentColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.28)
        : colorScheme.primary.withValues(alpha: isPlanMode ? 1 : 0.9);
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : isPlanMode
        ? colorScheme.primary.withValues(alpha: 0.24)
        : colorScheme.outlineVariant;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isPlanMode ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: Icon(
                modeIcon,
                key: ValueKey<String>('${mode.storageValue}-$modeIcon'),
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              modeLabel,
              key: ValueKey<String>('${mode.storageValue}-$modeLabel'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Creation mode types for the composer.
enum _CreationMode { none, image, video, audio, deepResearch }

/// A "+" button that opens a popup for creation modes (image, video, audio, deep research).
/// When a supported mode is selected, the button turns active (primary color + mode icon).
class _ComposerCreationModeButton extends StatefulWidget {
  const _ComposerCreationModeButton({
    required this.creationMode,
    required this.onCreationModeChanged,
  });

  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;

  @override
  State<_ComposerCreationModeButton> createState() =>
      _ComposerCreationModeButtonState();
}

class _ComposerCreationModeButtonState
    extends State<_ComposerCreationModeButton> {
  IconData _iconForMode(_CreationMode mode) => switch (mode) {
    _CreationMode.none => Icons.add_rounded,
    _CreationMode.image => Icons.image_outlined,
    _CreationMode.video => Icons.videocam_outlined,
    _CreationMode.audio => Icons.audiotrack_outlined,
    _CreationMode.deepResearch => Icons.travel_explore_rounded,
  };

  /// Notify the parent of a mode change after the current frame to avoid
  /// mutating the widget tree while the [MouseTracker] is mid-update.
  void _deferModeChange(_CreationMode mode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreationModeChanged(mode);
    });
  }

  void _selectMode(_CreationMode mode) {
    if (mode == widget.creationMode) {
      // Toggle off.
      _deferModeChange(_CreationMode.none);
      return;
    }
    // Only image generation is currently supported.
    if (mode != _CreationMode.image) {
      final label = switch (mode) {
        _CreationMode.video => _localizedText(
          context,
          zh: '视频生成功能暂不支持，敬请期待',
          en: 'Video generation is not yet supported',
        ),
        _CreationMode.audio => _localizedText(
          context,
          zh: '音频生成功能暂不支持，敬请期待',
          en: 'Audio generation is not yet supported',
        ),
        _CreationMode.deepResearch => _localizedText(
          context,
          zh: '深度研究功能暂不支持，敬请期待',
          en: 'Deep Research is not yet supported',
        ),
        _ => '',
      };
      if (label.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _deferModeChange(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.creationMode != _CreationMode.none;
    return Tooltip(
      message: _localizedText(context, zh: '创建', en: 'Create'),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: FilledButton(
            onPressed: () {
              // When active, toggle off instead of opening the menu.
              if (isActive) {
                _deferModeChange(_CreationMode.none);
                return;
              }
              _showCreationMenu();
            },
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              backgroundColor: isActive
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: isActive
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface,
              side: isActive
                  ? null
                  : BorderSide(color: colorScheme.outlineVariant),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                _iconForMode(widget.creationMode),
                key: ValueKey<_CreationMode>(widget.creationMode),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreationMenu() {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()!
            as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final colorScheme = Theme.of(context).colorScheme;
    showAnimatedMenu<_CreationMode>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.image,
          child: Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.image
                    ? colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '创建图片', en: 'Create Image'),
                ),
              ),
              if (widget.creationMode == _CreationMode.image)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.video,
          child: Row(
            children: [
              const Icon(Icons.videocam_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '视频生成', en: 'Generate Video'),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.audio,
          child: Row(
            children: [
              const Icon(Icons.audiotrack_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '音频生成', en: 'Generate Audio'),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.deepResearch,
          child: Row(
            children: [
              const Icon(Icons.travel_explore_rounded, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '深度研究', en: 'Deep Research'),
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      _selectMode(value);
    });
  }
}

/// A wrap layout that allows drag-to-reorder of attachment chips.
class _ReorderableAttachmentWrap extends StatefulWidget {
  const _ReorderableAttachmentWrap({
    required this.attachments,
    required this.onReorder,
    required this.onRemove,
    required this.onTap,
  });

  final List<_ComposerAttachmentDraft> attachments;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;
  final void Function(_ComposerAttachmentDraft draft) onTap;

  @override
  State<_ReorderableAttachmentWrap> createState() =>
      _ReorderableAttachmentWrapState();
}

class _ReorderableAttachmentWrapState
    extends State<_ReorderableAttachmentWrap> {
  int? _dragIndex;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(widget.attachments.length, (index) {
        final attachment = widget.attachments[index];
        final isDragging = _dragIndex == index;
        final isHovering = _hoverIndex == index;
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data != index) {
              setState(() => _hoverIndex = index);
            }
            return details.data != index;
          },
          onLeave: (_) {
            if (_hoverIndex == index) {
              setState(() => _hoverIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _hoverIndex = null);
            widget.onReorder(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Draggable<int>(
              data: index,
              onDragStarted: () => setState(() => _dragIndex = index),
              onDragEnd: (_) => setState(() {
                _dragIndex = null;
                _hoverIndex = null;
              }),
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: Opacity(
                  opacity: 0.85,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () {},
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _ComposerAttachmentChip(
                  attachment: attachment,
                  onRemove: () {},
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: isHovering
                    ? (Matrix4.identity()..scaleByDouble(1.05, 1.05, 1.0, 1.0))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                child: Opacity(
                  opacity: isDragging ? 0.3 : 1.0,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () => widget.onRemove(attachment.filePath),
                    onTap: () => widget.onTap(attachment),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
    this.onTap,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForAttachmentKind(attachment.kind),
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onRemove,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project file/directory reference capsules (reorderable, removable chips)
// ─────────────────────────────────────────────────────────────────────────────

class _ReorderableProjectReferenceWrap extends StatefulWidget {
  const _ReorderableProjectReferenceWrap({
    required this.references,
    required this.onReorder,
    required this.onRemove,
  });

  final List<_AtMentionItem> references;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;

  @override
  State<_ReorderableProjectReferenceWrap> createState() =>
      _ReorderableProjectReferenceWrapState();
}

class _ReorderableProjectReferenceWrapState
    extends State<_ReorderableProjectReferenceWrap> {
  int? _dragIndex;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(widget.references.length, (index) {
        final ref = widget.references[index];
        final isDragging = _dragIndex == index;
        final isHovering = _hoverIndex == index;
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data != index) {
              setState(() => _hoverIndex = index);
            }
            return details.data != index;
          },
          onLeave: (_) {
            if (_hoverIndex == index) {
              setState(() => _hoverIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _hoverIndex = null);
            widget.onReorder(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Draggable<int>(
              data: index,
              onDragStarted: () => setState(() => _dragIndex = index),
              onDragEnd: (_) => setState(() {
                _dragIndex = null;
                _hoverIndex = null;
              }),
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: Opacity(
                  opacity: 0.85,
                  child: _ProjectReferenceChip(
                    item: ref,
                    onRemove: () {},
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _ProjectReferenceChip(
                  item: ref,
                  onRemove: () {},
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: isHovering
                    ? (Matrix4.identity()..scaleByDouble(1.05, 1.05, 1.0, 1.0))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                child: Opacity(
                  opacity: isDragging ? 0.3 : 1.0,
                  child: _ProjectReferenceChip(
                    item: ref,
                    onRemove: () => widget.onRemove(ref.path),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _ProjectReferenceChip extends StatelessWidget {
  const _ProjectReferenceChip({
    required this.item,
    required this.onRemove,
  });

  final _AtMentionItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.isDirectory
                ? Icons.folder_rounded
                : _AtMentionOverlayPanel._atMentionIcon(item),
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              item.isDirectory
                  ? '${item.relativePath}/'
                  : item.relativePath,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// @ mention overlay (Cursor-style file reference autocomplete)
// ─────────────────────────────────────────────────────────────────────────────

class _AtMentionItem {
  const _AtMentionItem({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final String relativePath;
  final bool isDirectory;
}

class _AtMentionOverlayPanel extends StatelessWidget {
  const _AtMentionOverlayPanel({
    required this.link,
    required this.items,
    required this.selectedIndex,
    required this.loading,
    required this.breadcrumbs,
    required this.onSelect,
    required this.onDrillDown,
    required this.onBreadcrumbTap,
    required this.onDismiss,
  });

  final LayerLink link;
  final List<_AtMentionItem> items;
  final int selectedIndex;
  final bool loading;
  final List<String> breadcrumbs;
  final void Function(_AtMentionItem item) onSelect;
  final void Function(_AtMentionItem item) onDrillDown;
  final void Function(int depth) onBreadcrumbTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isZh =
        Localizations.localeOf(context).languageCode.startsWith('zh');

    return Stack(
      children: [
        // Dismiss barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 460,
              maxHeight: 340,
            ),
            child: Material(
              elevation: 8,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? colorScheme.surfaceContainerHigh
                  : colorScheme.surface,
              surfaceTintColor: colorScheme.surfaceTint,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Breadcrumb row.
                  if (breadcrumbs.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AtMentionBreadcrumbChip(
                              label: isZh ? '项目根目录' : 'Project Root',
                              icon: Icons.home_rounded,
                              onTap: () => onBreadcrumbTap(-1),
                            ),
                            for (var i = 0; i < breadcrumbs.length; i++) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              _AtMentionBreadcrumbChip(
                                label: breadcrumbs[i],
                                icon: Icons.folder_rounded,
                                onTap: () => onBreadcrumbTap(i),
                                isLast: i == breadcrumbs.length - 1,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  // Results.
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          isZh ? '未找到匹配文件或目录' : 'No matching files or directories',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (ctx, index) {
                          final item = items[index];
                          final isSelected = index == selectedIndex;
                          return Material(
                            color: isSelected
                                ? colorScheme.primaryContainer
                                    .withValues(alpha: 0.4)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => onSelect(item),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _atMentionIcon(item),
                                      size: 18,
                                      color: item.isDirectory
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            item.relativePath,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.55),
                                                  fontSize: 10,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.isDirectory) ...[
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: isZh ? '进入目录' : 'Open directory',
                                          onPressed: () => onDrillDown(item),
                                          icon: Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static IconData _atMentionIcon(_AtMentionItem item) {
    if (item.isDirectory) return Icons.folder_rounded;
    final ext = p.extension(item.name).toLowerCase();
    return switch (ext) {
      '.dart' => Icons.code_rounded,
      '.py' => Icons.code_rounded,
      '.js' || '.jsx' || '.ts' || '.tsx' => Icons.javascript_rounded,
      '.json' => Icons.data_object_rounded,
      '.yaml' || '.yml' => Icons.settings_rounded,
      '.md' => Icons.article_rounded,
      '.html' || '.htm' => Icons.web_rounded,
      '.css' || '.scss' || '.less' => Icons.palette_rounded,
      '.png' || '.jpg' || '.jpeg' || '.gif' || '.svg' || '.webp' =>
        Icons.image_rounded,
      '.go' || '.rs' || '.java' || '.kt' || '.swift' || '.c' || '.cpp' =>
        Icons.code_rounded,
      '.sql' => Icons.storage_rounded,
      '.sh' || '.bash' || '.zsh' => Icons.terminal_rounded,
      '.vue' => Icons.web_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }
}

class _AtMentionBreadcrumbChip extends StatelessWidget {
  const _AtMentionBreadcrumbChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLast = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isLast
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isLast
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerAttachmentDraft {
  const _ComposerAttachmentDraft({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.sizeBytes,
  });

  final String filePath;
  final String name;
  final AiAttachmentKind kind;
  final int sizeBytes;

  static Future<_ComposerAttachmentDraft> fromPath(String path) async {
    final file = File(path);
    final stat = await file.stat();
    return _ComposerAttachmentDraft(
      filePath: path,
      name: p.basename(path),
      kind: aiAttachmentKindForPath(path),
      sizeBytes: stat.size,
    );
  }
}

IconData _iconForAttachmentKind(AiAttachmentKind kind) {
  return switch (kind) {
    AiAttachmentKind.image => Icons.image_outlined,
    AiAttachmentKind.text => Icons.description_outlined,
    AiAttachmentKind.spreadsheet => Icons.table_chart_outlined,
    AiAttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AiAttachmentKind.binary => Icons.insert_drive_file_outlined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HE session tile shown in the navigation pane threads list.
// Mirrors the visual design of _ThreadTile for consistency.
// ─────────────────────────────────────────────────────────────────────────────


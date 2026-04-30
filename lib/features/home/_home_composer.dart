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
    required this.autoFollowPaused,
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
    this.creationOptions = AiCreationOptions.empty,
    this.onCreationOptionsChanged,
    this.onEditOptionsRequested,
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
  // True when auto-follow mode is ON but the user has scrolled away from
  // the bottom, so following is temporarily paused. In this state the
  // button renders as a muted "resume" affordance; tapping it re-arms the
  // follow and jumps to the latest message instead of disabling the mode.
  final bool autoFollowPaused;
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
  final AiCreationOptions creationOptions;
  final ValueChanged<AiCreationOptions>? onCreationOptionsChanged;
  final Future<void> Function()? onEditOptionsRequested;
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

  // ── Skill picker (leading `/` slash trigger) ──
  //
  // When the text in the composer begins with '/', a picker overlay is
  // presented that lists locally installed skills. Selecting a skill strips
  // the leading '/…' token from the composer and attaches the skill as a
  // removable chip.  When sending, the skill's SKILL.md content is injected
  // as a `<system-reminder>`/`<skill-manifest>` block ahead of the user's
  // prompt so every thread template can honour the explicit selection.
  LocalSkill? _selectedSkill;
  String? _selectedSkillManifest;
  int _slashTriggerOffset = -1;
  int _slashDismissedOffset = -1;
  List<LocalSkill> _skillPickerResults = const <LocalSkill>[];
  int _skillPickerSelectedIndex = 0;
  bool _skillPickerLoading = false;
  OverlayEntry? _skillPickerOverlay;
  // Drives the skill picker overlay's enter/exit transitions.  A single
  // ValueNotifier is shared between the composer state and the overlay
  // widget so the overlay can reverse its animation before being removed
  // from the overlay stack.  `null` means the overlay is not mounted.
  ValueNotifier<bool>? _skillPickerVisible;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChangedForAtMention);
    widget.controller.addListener(_handleTextChangedForSlashSkill);
  }

  @override
  void didUpdateWidget(covariant _ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChangedForAtMention);
      oldWidget.controller.removeListener(_handleTextChangedForSlashSkill);
      widget.controller.addListener(_handleTextChangedForAtMention);
      widget.controller.addListener(_handleTextChangedForSlashSkill);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChangedForAtMention);
    widget.controller.removeListener(_handleTextChangedForSlashSkill);
    _dismissAtMentionOverlay();
    _dismissSkillPickerOverlay(remember: false);
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
      if (ch == 0x40 /* @ */ ) {
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
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      for (final entry in entries) {
        if (results.length >= 50) break;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        const ignored = {
          'node_modules',
          'build',
          '.dart_tool',
          '__pycache__',
          '.git',
          '.idea',
          '.vscode',
          'target',
          'dist',
          '.gradle',
        };
        if (ignored.contains(name)) continue;
        if (trimmedQuery.isEmpty || name.toLowerCase().contains(trimmedQuery)) {
          final relativePath = p.relative(entry.path, from: rootPath);
          results.add(
            _AtMentionItem(
              name: name,
              path: entry.path,
              relativePath: relativePath,
              isDirectory: entry is Directory,
            ),
          );
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
    } catch (error, stack) {
      silentLog('composer', 'at-mention shallow search', error, stack);
    }
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
          'node_modules',
          'build',
          '.dart_tool',
          '__pycache__',
          '.git',
          '.idea',
          '.vscode',
          'target',
          'dist',
          '.gradle',
        };
        if (ignored.contains(name)) continue;
        final relativePath = p.relative(entry.path, from: rootPath);
        // Avoid duplicates already in the shallow list.
        if (name.toLowerCase().contains(query) &&
            !results.any((r) => r.path == entry.path)) {
          results.add(
            _AtMentionItem(
              name: name,
              path: entry.path,
              relativePath: relativePath,
              isDirectory: entry is Directory,
            ),
          );
        }
        if (entry is Directory) {
          await _deepSearchAtMention(
            entry,
            query,
            results,
            rootPath,
            depth + 1,
          );
        }
      }
    } catch (error, stack) {
      silentLog('composer', 'at-mention deep search', error, stack);
    }
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
      final cursor = widget.controller.selection.baseOffset.clamp(
        0,
        widget.controller.text.length,
      );
      _atMentionSuppressListener = true;
      try {
        widget.controller.text = widget.controller.text.replaceRange(
          _atMentionTriggerOffset,
          cursor,
          '',
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
      _atMentionBreadcrumbs = p
          .split(_atMentionCurrentDirectory)
          .where((s) => s.isNotEmpty)
          .toList();
    });
    // Replace the query text after @ with just @
    final textLen = widget.controller.text.length;
    if (_atMentionTriggerOffset >= 0 && _atMentionTriggerOffset < textLen) {
      final cursor = widget.controller.selection.baseOffset.clamp(0, textLen);
      final start = _atMentionTriggerOffset + 1;
      if (start <= cursor) {
        _atMentionSuppressListener = true;
        try {
          widget.controller.text = widget.controller.text.replaceRange(
            start,
            cursor,
            '',
          );
          widget.controller.selection = TextSelection.collapsed(offset: start);
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

  // ── Skill picker (leading `/` slash trigger) helpers ──

  /// Returns the parsed leading `/` trigger, or `null` when the text no
  /// longer matches the shape `"/token<ws?>..."` with the cursor inside the
  /// first token.
  ({int triggerOffset, int tokenEnd, String query})? _computeSlashTrigger() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    if (text.isEmpty || text.codeUnitAt(0) != 0x2F /* '/' */ ) return null;
    var tokenEnd = text.length;
    for (var i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D) {
        tokenEnd = i;
        break;
      }
    }
    final cursor = selection.baseOffset.clamp(0, text.length);
    if (cursor > tokenEnd) return null;
    return (
      triggerOffset: 0,
      tokenEnd: tokenEnd,
      query: text.substring(1, tokenEnd),
    );
  }

  void _handleTextChangedForSlashSkill() {
    if (_atMentionSuppressListener) return;
    if (_selectedSkill != null) return;
    final trigger = _computeSlashTrigger();
    if (trigger == null) {
      _dismissSkillPickerOverlay(remember: false);
      _slashDismissedOffset = -1;
      return;
    }
    if (trigger.triggerOffset == _slashDismissedOffset) return;
    _slashDismissedOffset = -1;
    _slashTriggerOffset = trigger.triggerOffset;
    _performSkillPickerSearch(trigger.query);
  }

  void _performSkillPickerSearch(String query) {
    if (!mounted) return;
    final skills = _readSkillsListSafe();
    final trimmed = query.trim().toLowerCase();
    final matches = trimmed.isEmpty
        ? skills
        : skills.where((skill) {
            final haystack = '${skill.name} ${skill.description}'.toLowerCase();
            return haystack.contains(trimmed);
          }).toList();
    setState(() {
      _skillPickerResults = matches;
      _skillPickerSelectedIndex = 0;
      _skillPickerLoading = false;
    });
    _showSkillPickerOverlay();
  }

  List<LocalSkill> _readSkillsListSafe() {
    try {
      final controller = Provider.of<SkillsController>(context, listen: false);
      return controller.skills;
    } catch (_) {
      return const <LocalSkill>[];
    }
  }

  void _showSkillPickerOverlay() {
    if (_skillPickerOverlay != null) {
      // Already mounted — ensure it is visible (e.g. user re-typed '/' while
      // a reverse animation was in flight) and rebuild with fresh results.
      _skillPickerVisible?.value = true;
      _skillPickerOverlay!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final visible = ValueNotifier<bool>(true);
    _skillPickerVisible = visible;
    // Resolve animation settings from the global SettingsController so the
    // picker respects the user's preferred dialog animation style/curve/
    // duration.  Fallback to defaults if the provider is unreachable.
    DialogAnimationSettings animationSettings;
    try {
      animationSettings = Provider.of<SettingsController>(
        context,
        listen: false,
      ).dialogAnimationSettings;
    } catch (_) {
      animationSettings = const DialogAnimationSettings();
    }
    _skillPickerOverlay = OverlayEntry(
      builder: (_) {
        return _SkillPickerOverlayPanel(
          link: _atMentionLayerLink,
          items: _skillPickerResults,
          selectedIndex: _skillPickerSelectedIndex,
          loading: _skillPickerLoading,
          onSelect: _handleSkillPickerSelect,
          onDismiss: _userDismissSkillPickerOverlay,
          visible: visible,
          animationSettings: animationSettings,
          onExitComplete: _finalizeSkillPickerOverlayRemoval,
        );
      },
    );
    overlay.insert(_skillPickerOverlay!);
  }

  void _userDismissSkillPickerOverlay() {
    _dismissSkillPickerOverlay(remember: true);
  }

  void _dismissSkillPickerOverlay({required bool remember}) {
    if (remember && _slashTriggerOffset >= 0) {
      _slashDismissedOffset = _slashTriggerOffset;
    }
    // Ask the overlay panel to reverse its animation; it will invoke
    // [_finalizeSkillPickerOverlayRemoval] when the exit transition ends.
    // During widget disposal we cannot wait for an animation tick, so fall
    // back to synchronous removal.
    final visible = _skillPickerVisible;
    if (visible == null || _skillPickerOverlay == null || !mounted) {
      _finalizeSkillPickerOverlayRemoval();
    } else {
      visible.value = false;
    }
    _skillPickerResults = const <LocalSkill>[];
    _skillPickerSelectedIndex = 0;
    _skillPickerLoading = false;
    _slashTriggerOffset = -1;
    if (_slashDismissedOffset >= 0) {
      final text = widget.controller.text;
      if (_slashDismissedOffset >= text.length ||
          text.codeUnitAt(_slashDismissedOffset) != 0x2F) {
        _slashDismissedOffset = -1;
      }
    }
  }

  /// Removes the overlay entry from the root overlay and disposes the
  /// visibility notifier.  Safe to call multiple times.
  void _finalizeSkillPickerOverlayRemoval() {
    final entry = _skillPickerOverlay;
    _skillPickerOverlay = null;
    entry?.remove();
    final visible = _skillPickerVisible;
    _skillPickerVisible = null;
    visible?.dispose();
  }

  Future<void> _handleSkillPickerSelect(LocalSkill skill) async {
    final trigger = _computeSlashTrigger();
    if (trigger != null) {
      _atMentionSuppressListener = true;
      try {
        final text = widget.controller.text;
        final remainderStart =
            trigger.tokenEnd < text.length &&
                (text.codeUnitAt(trigger.tokenEnd) == 0x20 ||
                    text.codeUnitAt(trigger.tokenEnd) == 0x09)
            ? trigger.tokenEnd + 1
            : trigger.tokenEnd;
        final newText = text.substring(remainderStart);
        widget.controller.text = newText;
        widget.controller.selection = const TextSelection.collapsed(offset: 0);
      } finally {
        _atMentionSuppressListener = false;
      }
    }
    _dismissSkillPickerOverlay(remember: false);
    _slashDismissedOffset = -1;
    String? manifestContent;
    try {
      final controller = Provider.of<SkillsController>(context, listen: false);
      manifestContent = await controller.readSkillManifest(skill);
    } catch (_) {
      manifestContent = null;
    }
    if (!mounted) return;
    setState(() {
      _selectedSkill = skill;
      _selectedSkillManifest = manifestContent;
    });
    widget.focusNode.requestFocus();
  }

  void _clearSelectedSkill() {
    if (_selectedSkill == null && _selectedSkillManifest == null) return;
    setState(() {
      _selectedSkill = null;
      _selectedSkillManifest = null;
    });
  }

  /// Moves the skill picker's highlight by [delta] rows (wrap-around).
  /// Invoked by the parent focus node key handler when the user presses the
  /// up/down arrow keys while the picker overlay is visible.
  void _moveSkillPickerSelection(int delta) {
    if (_skillPickerOverlay == null) return;
    final total = _skillPickerResults.length;
    if (total == 0) return;
    final next = (_skillPickerSelectedIndex + delta) % total;
    setState(() {
      _skillPickerSelectedIndex = next < 0 ? next + total : next;
    });
    _skillPickerOverlay?.markNeedsBuild();
  }

  /// Commits the currently highlighted skill picker entry.  Returns true
  /// when a selection was made (so the caller can swallow the key event).
  bool _commitSkillPickerSelection() {
    if (_skillPickerOverlay == null) return false;
    if (_skillPickerLoading) return false;
    if (_skillPickerResults.isEmpty) return false;
    final index = _skillPickerSelectedIndex;
    if (index < 0 || index >= _skillPickerResults.length) return false;
    final skill = _skillPickerResults[index];
    // Fire-and-forget: the select handler already manages state updates and
    // SKILL.md loading.  Returning true tells the parent to swallow the key.
    unawaited(_handleSkillPickerSelect(skill));
    return true;
  }

  /// Returns a display-only metadata payload describing the currently
  /// pending skill selection (if any).  Meant to be read **before**
  /// [consumePendingSkillReminder], since consuming clears the selection.
  /// The payload is persisted verbatim onto the user message metadata so
  /// the transcript bubble can render a skill capsule under the timestamp.
  Map<String, Object?>? peekPendingSkillMetadata() {
    final skill = _selectedSkill;
    if (skill == null) return null;
    return <String, Object?>{
      'name': skill.name,
      'path': skill.manifestPath,
      if (skill.hasEmojiIcon) 'emoji': skill.emojiIcon,
      if (skill.hasIcon) 'icon_path': skill.iconPath,
      if (skill.hasIcon && skill.iconKind != null)
        'icon_kind': switch (skill.iconKind!) {
          LocalSkillIconKind.svg => 'svg',
          LocalSkillIconKind.raster => 'raster',
        },
    };
  }

  /// Consumes the currently-selected skill (if any) and returns a single
  /// `<system-reminder>` payload string that should be appended to the
  /// outgoing LLM prompt.  The selection chip is cleared as a side effect so
  /// the skill applies only to the turn being submitted.  The visible
  /// composer text is **never** mutated, ensuring the stored user message
  /// rendered in the transcript bubble stays free of injected manifest XML.
  String? consumePendingSkillReminder() {
    final skill = _selectedSkill;
    if (skill == null) return null;
    final manifest = (_selectedSkillManifest ?? '').trim();
    final fallbackDescription = skill.description.trim();
    final manifestBody = manifest.isNotEmpty
        ? manifest
        : (fallbackDescription.isNotEmpty
              ? fallbackDescription
              : 'No SKILL.md content is available; honour the user intent implied by the skill name.');
    final buffer = StringBuffer()
      ..writeln(
        'The user explicitly selected the local skill "${skill.name}" for this request.',
      )
      ..writeln(
        'Follow the SKILL.md content below with the highest priority, overriding any conflicting default behaviour.',
      )
      ..writeln(
        "Apply the skill's guidance to the user's message for this turn; do not ignore this directive even if the skill seems unrelated.",
      )
      ..writeln()
      ..writeln(
        '<skill-manifest name="${_escapeXmlAttribute(skill.name)}" path="${_escapeXmlAttribute(skill.manifestPath)}">',
      )
      ..writeln(manifestBody)
      ..write('</skill-manifest>');
    _clearSelectedSkill();
    return buffer.toString();
  }

  static String _escapeXmlAttribute(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Injects project file/directory references into the controller text and
  /// clears the capsule list. Called both from the send button and from the
  /// parent via [GlobalKey] for keyboard-shortcut sends.
  void _injectReferencesIntoText() {
    if (_projectFileReferences.isEmpty) return;
    final refs = _projectFileReferences
        .map((r) {
          final suffix = r.isDirectory ? '/' : '';
          return '@${r.relativePath}$suffix';
        })
        .join(' ');
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

  /// Opens the shared AI model editor dialog pre-filled with the currently
  /// selected provider configuration. Mirrors the gear button shown next to
  /// each model capsule in Settings → AI Model Providers.
  Future<void> _openSelectedModelEditor(BuildContext btnContext) async {
    final selected = widget.selectedModel;
    if (selected == null) {
      return;
    }
    await showAiModelEditorDialog(btnContext, initialModel: selected);
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

    final chipAnim = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.chipAnimationSettings,
        );
    final expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedSkill != null) ...[
          AnimatedRemovableChip(
            key: ValueKey('skill:${_selectedSkill!.manifestPath}'),
            settings: chipAnim,
            collapseAxis: Axis.vertical,
            onRemove: _clearSelectedSkill,
            builder: (ctx, requestRemove) => _SelectedSkillChip(
              skill: _selectedSkill!,
              onRemoved: requestRemove,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.editingMessageId != null) ...[
          AnimatedRemovableChip(
            key: ValueKey<String>('editing:${widget.editingMessageId}'),
            settings: chipAnim,
            collapseAxis: Axis.vertical,
            onRemove: () {
              widget.onCancelEditing();
            },
            builder: (ctx, requestRemove) => Container(
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
                    onTap: requestRemove,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
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
              return AnimatedRemovableChip(
                key: ValueKey<String>(
                  'queued:$index:${identityHashCode(msg)}',
                ),
                settings: chipAnim,
                collapseAxis: Axis.vertical,
                onRemove: () => widget.onRemoveQueuedMessage(index),
                builder: (ctx, requestRemove) => Padding(
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
                        onPressed: requestRemove,
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
              // 2026-04-26: Wrap the editable text in a Shortcuts/Actions
              // pair driven by the global SettingsController bindings so
              // that send-message and toggle-composer hotkeys (Ctrl+Enter
              // and Ctrl+P by default) work *inside* the focused TextField.
              //
              // Background: macOS' DefaultTextEditingShortcuts maps Ctrl+P
              // to MoveSelectionUpTextIntent at the WidgetsApp level, which
              // intercepts our HardwareKeyboard handler before it has a
              // chance to fire (the symptom users reported was a brief
              // border flash and nothing else).  Because Shortcuts widgets
              // are walked from the focused node outward, declaring the
              // bindings *here*, just above the EditableText, beats the
              // global text-editing shortcuts and forwards the keystroke
              // to our composer callbacks instead.
              child: _ComposerShortcutsHost(
                bindings: context
                    .watch<SettingsController>()
                    .shortcutBindings,
                onSend: () => unawaited(widget.onSend()),
                onToggleCollapsed: () =>
                    widget.onCollapsedChanged(!widget.isCollapsed),
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
                    final hasSelection = widget.selectedModel != null;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: widget.availableModels.isEmpty
                              ? null
                              : () => _showModelMenu(btnContext),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            padding: const EdgeInsetsDirectional.only(
                              start: 16,
                              end: 12,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadiusDirectional.horizontal(
                                start: Radius.circular(26),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.hub_outlined),
                          label: Text(
                            selectedModelLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Quick-edit gear: opens the same editor dialog used
                        // in Settings → AI Model Providers, pre-filled with
                        // the currently selected model. This shortens the
                        // "tweak temperature mid-chat" flow from 4 taps
                        // (open settings → providers → row → edit) to 1.
                        Tooltip(
                          message: _localizedText(
                            context,
                            zh: '编辑当前模型配置',
                            en: 'Edit selected model configuration',
                          ),
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: hasSelection
                                  ? () => unawaited(
                                      _openSelectedModelEditor(btnContext),
                                    )
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(40, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadiusDirectional.horizontal(
                                        end: Radius.circular(26),
                                      ),
                                ),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
        // Compact "+" button for picking attachments. Lives just left of the
        // expand/collapse toggle so the affordance mirrors the right-side
        // creation-mode button (which carries the mode-semantic icon below).
        Tooltip(
          message: widget.attachmentsEnabled
              ? _localizedText(
                  context,
                  zh:
                      '添加附件（最多 $aiMessageAttachmentLimit 个，单文件 ≤10MB；支持图片、文本、代码、表格和 PDF）',
                  en:
                      'Add attachments (up to $aiMessageAttachmentLimit, ≤10MB each; images, text, code, spreadsheets, PDF)',
                )
              : _localizedText(
                  context,
                  zh: '当前模型不支持附件',
                  en: 'The selected model does not support attachments',
                ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.attachmentsEnabled
                  ? () => unawaited(widget.onPickAttachments())
                  : null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: widget.attachmentsEnabled
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerHigh,
                foregroundColor: widget.attachmentsEnabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        const SizedBox(width: 10),
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
            zh: !widget.autoFollowEnabled
                ? '开启自动滚动'
                : (widget.autoFollowPaused
                      ? '自动滚动已暂停（已上滑）· 点击恢复并跳至最新'
                      : '关闭自动滚动'),
            en: !widget.autoFollowEnabled
                ? 'Enable Auto Follow'
                : (widget.autoFollowPaused
                      ? 'Auto Follow paused (scrolled up) · tap to resume & jump to latest'
                      : 'Disable Auto Follow'),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.onToggleAutoFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: !widget.autoFollowEnabled
                    ? colorScheme.surfaceContainerHighest
                    : (widget.autoFollowPaused
                          ? colorScheme.primaryContainer
                          : colorScheme.primary),
                foregroundColor: !widget.autoFollowEnabled
                    ? colorScheme.onSurfaceVariant
                    : (widget.autoFollowPaused
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onPrimary),
                side: !widget.autoFollowEnabled
                    ? BorderSide(color: colorScheme.outlineVariant)
                    : (widget.autoFollowPaused
                          ? BorderSide(color: colorScheme.primary)
                          : null),
              ),
              child: Icon(
                !widget.autoFollowEnabled
                    ? Icons.vertical_align_bottom_outlined
                    : (widget.autoFollowPaused
                          ? Icons.arrow_downward_rounded
                          : Icons.vertical_align_bottom_rounded),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ComposerCreationModeButton(
          creationMode: widget.creationMode,
          onCreationModeChanged: widget.onCreationModeChanged,
        ),
        // NOTE: Only FadeTransition is safe inside a LayoutBuilder
        // subtree.  ScaleTransition / SlideTransition / RotationTransition
        // extend AnimatedWidget, whose _AnimatedState calls setState()
        // during animation ticks.  In Flutter 3.11+ LayoutBuilder has its
        // own BuildScope; that setState propagates through
        // _LayoutBuilderElement._scheduleRebuild → scheduleLayoutCallback
        // which asserts debugNeedsLayout — a condition that is false
        // during handleBeginFrame.  FadeTransition is a
        // SingleChildRenderObjectWidget that drives opacity via
        // RenderAnimatedOpacity.markNeedsPaint and never calls setState.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          child:
              widget.creationMode != _CreationMode.none &&
                  widget.onEditOptionsRequested != null
              ? Padding(
                  key: ValueKey<String>(
                    'creation-options-${widget.creationMode.name}',
                  ),
                  padding: const EdgeInsets.only(left: 6),
                  child: _ComposerCreationOptionsChip(
                    mode: widget.creationMode,
                    options: widget.creationOptions,
                    onTap: widget.onEditOptionsRequested!,
                  ),
                )
              : const SizedBox(key: ValueKey<String>('creation-options-off')),
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
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
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
                  _localizedText(context, zh: '完全访问权限', en: 'Full Access'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            // FadeTransition-only: ScaleTransition is unsafe inside
            // LayoutBuilder (see note in _ComposerPanelState.build).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                modeIcon,
                key: ValueKey<String>('${mode.storageValue}-$modeIcon'),
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // FadeTransition-only: SlideTransition is unsafe inside
          // LayoutBuilder (see note in _ComposerPanelState.build).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
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
    _CreationMode.none => Icons.tune_rounded,
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
    if (mode == _CreationMode.deepResearch) {
      final label = switch (mode) {
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
      message: _localizedText(context, zh: '模式', en: 'Mode'),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeInOutCubicEmphasized,
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
            // Same safety constraint as _ComposerCreationOptionsChip: avoid
            // ScaleTransition / RotationTransition (AnimatedWidget subclasses)
            // inside a LayoutBuilder subtree.  Their setState() ticks during
            // handleBeginFrame trigger scheduleLayoutCallback assertions.
            // FadeTransition (SingleChildRenderObjectWidget) is safe.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
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
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
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
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.video,
          child: Row(
            children: [
              Icon(
                Icons.videocam_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.video
                    ? colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '视频生成', en: 'Generate Video'),
                ),
              ),
              if (widget.creationMode == _CreationMode.video)
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.audio,
          child: Row(
            children: [
              Icon(
                Icons.audiotrack_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.audio
                    ? colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedText(context, zh: '音频生成', en: 'Generate Audio'),
                ),
              ),
              if (widget.creationMode == _CreationMode.audio)
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
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
    final chipAnim = context.select<SettingsController, DialogAnimationSettings>(
      (c) => c.chipAnimationSettings,
    );
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
              child: AnimatedRemovableChip(
                key: ValueKey('attachment:${attachment.filePath}'),
                settings: chipAnim,
                collapseAxis: Axis.horizontal,
                onRemove: () => widget.onRemove(attachment.filePath),
                builder: (context, requestRemove) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    transform: isHovering
                        ? (Matrix4.identity()
                          ..scaleByDouble(1.05, 1.05, 1.0, 1.0))
                        : Matrix4.identity(),
                    transformAlignment: Alignment.center,
                    child: Opacity(
                      opacity: isDragging ? 0.3 : 1.0,
                      child: _ComposerAttachmentChip(
                        attachment: attachment,
                        onRemove: requestRemove,
                        onTap: () => widget.onTap(attachment),
                      ),
                    ),
                  );
                },
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
    if (attachment.kind == AiAttachmentKind.image) {
      return _ComposerImageThumbChip(
        attachment: attachment,
        onTap: onTap,
        onRemove: onRemove,
      );
    }
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

/// Square thumbnail chip dedicated to image attachments. Click-to-preview is
/// inherited from `_openComposerAttachment` which routes images through the
/// shared `_ImagePreviewDialog` used by message bubbles.
class _ComposerImageThumbChip extends StatelessWidget {
  const _ComposerImageThumbChip({
    required this.attachment,
    required this.onTap,
    required this.onRemove,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double size = 64;
    return Tooltip(
      message: '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(
                      File(attachment.filePath),
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 24,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: colorScheme.onSurface,
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
    final chipAnim = context.select<SettingsController, DialogAnimationSettings>(
      (c) => c.chipAnimationSettings,
    );
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
                  child: _ProjectReferenceChip(item: ref, onRemove: () {}),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _ProjectReferenceChip(item: ref, onRemove: () {}),
              ),
              child: AnimatedRemovableChip(
                key: ValueKey('projref:${ref.path}'),
                settings: chipAnim,
                collapseAxis: Axis.horizontal,
                onRemove: () => widget.onRemove(ref.path),
                builder: (context, requestRemove) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  transform: isHovering
                      ? (Matrix4.identity()
                        ..scaleByDouble(1.05, 1.05, 1.0, 1.0))
                      : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  child: Opacity(
                    opacity: isDragging ? 0.3 : 1.0,
                    child: _ProjectReferenceChip(
                      item: ref,
                      onRemove: requestRemove,
                    ),
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
  const _ProjectReferenceChip({required this.item, required this.onRemove});

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
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
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
              item.isDirectory ? '${item.relativePath}/' : item.relativePath,
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 340),
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
                          isZh
                              ? '未找到匹配文件或目录'
                              : 'No matching files or directories',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
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
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.4,
                                  )
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
                                          tooltip: isZh
                                              ? '进入目录'
                                              : 'Open directory',
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
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.svg' ||
      '.webp' => Icons.image_rounded,
      '.go' ||
      '.rs' ||
      '.java' ||
      '.kt' ||
      '.swift' ||
      '.c' ||
      '.cpp' => Icons.code_rounded,
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

// ─────────────────────────────────────────────────────────────────────────────
// Skill picker overlay (Codex-style leading '/' slash trigger)
// ─────────────────────────────────────────────────────────────────────────────

class _SkillPickerOverlayPanel extends StatefulWidget {
  const _SkillPickerOverlayPanel({
    required this.link,
    required this.items,
    required this.selectedIndex,
    required this.loading,
    required this.onSelect,
    required this.onDismiss,
    required this.visible,
    required this.animationSettings,
    required this.onExitComplete,
  });

  final LayerLink link;
  final List<LocalSkill> items;
  final int selectedIndex;
  final bool loading;
  final ValueChanged<LocalSkill> onSelect;
  final VoidCallback onDismiss;
  final ValueListenable<bool> visible;
  final DialogAnimationSettings animationSettings;
  final VoidCallback onExitComplete;

  @override
  State<_SkillPickerOverlayPanel> createState() =>
      _SkillPickerOverlayPanelState();
}

class _SkillPickerOverlayPanelState extends State<_SkillPickerOverlayPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  final ScrollController _listController = ScrollController();
  // Approximate pixel height of a single item in the list so keyboard
  // navigation can scroll the highlighted entry into view.  Kept in sync
  // with the `Padding` values used in `itemBuilder` below.
  static const double _estimatedItemExtent = 54.0;

  @override
  void initState() {
    super.initState();
    final settings = widget.animationSettings;
    // Honour the user-configured duration, but clamp to a snappy range so an
    // inline picker never feels laggy (>420ms) nor flashes without affordance
    // (<120ms) for non-zero settings.  Zero preserves instant-show semantics.
    final baseMs = settings.duration.inMilliseconds;
    final durationMs = baseMs == 0 ? 0 : baseMs.clamp(120, 420).toInt();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    _animation = _buildAnimation();
    widget.visible.addListener(_handleVisibilityChanged);
    if (widget.visible.value) {
      _controller.forward();
    } else {
      // Extremely edge-case: the overlay was asked to exit before it rendered.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onExitComplete();
      });
    }
    _controller.addStatusListener(_handleAnimationStatus);
  }

  CurvedAnimation _buildAnimation() {
    final curveData = widget.animationSettings.curve;
    return CurvedAnimation(
      parent: _controller,
      curve: curveData.curve,
      reverseCurve: curveData.reverseCurve,
    );
  }

  void _handleVisibilityChanged() {
    if (!mounted) return;
    if (widget.visible.value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.visible.value) {
      widget.onExitComplete();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_handleVisibilityChanged);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SkillPickerOverlayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollSelectionIntoView();
    }
  }

  void _scrollSelectionIntoView() {
    if (!_listController.hasClients) return;
    final target = widget.selectedIndex * _estimatedItemExtent;
    final viewportStart = _listController.offset;
    final viewportEnd =
        viewportStart + _listController.position.viewportDimension;
    if (target < viewportStart) {
      _listController.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    } else if (target + _estimatedItemExtent > viewportEnd) {
      final next =
          target +
          _estimatedItemExtent -
          _listController.position.viewportDimension;
      _listController.animateTo(
        next.clamp(0.0, _listController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    final panel = Material(
      elevation: 8,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Icon(
                  Icons.extension_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isZh ? '选择一个技能' : 'Select a skill',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
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
          else if (widget.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  isZh ? '未找到匹配技能' : 'No matching skills',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                controller: _listController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (ctx, index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;
                  return Material(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelect(item),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            _SkillPickerLeading(skill: item),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.description.trim().isNotEmpty)
                                    Text(
                                      item.description,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                            fontSize: 10,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
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
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 360),
            child: _SkillPickerTransition(
              animation: _animation,
              settings: widget.animationSettings,
              child: panel,
            ),
          ),
        ),
      ],
    );
  }
}

/// Applies the user-configured dialog entrance/exit transition to the skill
/// picker overlay so its motion feels cohesive with the rest of the app's
/// animated surfaces.  The picker is anchored to the bottom-left of the
/// composer, so directional transitions use a downward origin offset to
/// suggest the panel is emerging from the `/` caret.
class _SkillPickerTransition extends StatelessWidget {
  const _SkillPickerTransition({
    required this.animation,
    required this.settings,
    required this.child,
  });

  final Animation<double> animation;
  final DialogAnimationSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Pick entrance vs exit style based on direction so reverse animations
    // can differ from entrance when the user configured them separately.
    final forward =
        animation.status == AnimationStatus.forward ||
        animation.status == AnimationStatus.completed;
    final style = forward ? settings.entranceStyle : settings.exitStyle;
    switch (style) {
      case DialogAnimationStyle.none:
        return FadeTransition(opacity: animation, child: child);
      case DialogAnimationStyle.fade:
        return FadeTransition(opacity: animation, child: child);
      case DialogAnimationStyle.fadeScale:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomCenter,
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.slideUp:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.slideDown:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.expand:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.rotateScale:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
            child: RotationTransition(
              turns: Tween<double>(begin: -0.02, end: 0.0).animate(animation),
              child: child,
            ),
          ),
        );
      case DialogAnimationStyle.elastic:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.slideLeft:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-0.08, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case DialogAnimationStyle.slideRight:
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
      case DialogAnimationStyle.springScale:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
                reverseCurve: Curves.easeInBack,
              ),
            ),
            child: child,
          ),
        );
      case DialogAnimationStyle.flipX:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            alignment: Alignment.bottomLeft,
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
            child: child,
          ),
        );
    }
  }
}

class _SkillPickerLeading extends StatelessWidget {
  const _SkillPickerLeading({required this.skill});

  final LocalSkill skill;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (skill.hasEmojiIcon) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text(skill.emojiIcon!, style: const TextStyle(fontSize: 18)),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        skill.initials,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Removable chip rendered at the top-left of the composer when the user
/// explicitly selects a skill via the leading-slash picker.  Mirrors the
/// Codex-style pill shown in the input area and exposes a close button to
/// clear the selection.
class _SelectedSkillChip extends StatelessWidget {
  const _SelectedSkillChip({required this.skill, required this.onRemoved});

  final LocalSkill skill;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (skill.hasEmojiIcon)
              Text(skill.emojiIcon!, style: const TextStyle(fontSize: 14))
            else
              Icon(
                Icons.extension_rounded,
                size: 14,
                color: colorScheme.onPrimaryContainer,
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                skill.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: isZh ? '移除此技能' : 'Remove skill',
              child: InkWell(
                onTap: onRemoved,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ],
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

/// Small chip rendered next to the creation-mode button that summarises the
/// currently chosen options. Styled to match the send button and acts as a
/// one-tap escape hatch back to plain text mode.
class _ComposerCreationOptionsChip extends StatelessWidget {
  const _ComposerCreationOptionsChip({
    required this.mode,
    required this.options,
    required this.onTap,
  });

  final _CreationMode mode;
  final AiCreationOptions options;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = options.aspectRatio?.trim();
    final label = switch (mode) {
      _CreationMode.image =>
        ratio != null && ratio.isNotEmpty
            ? ratio
            : _localizedText(context, zh: '图像', en: 'IMG'),
      _CreationMode.video =>
        ratio != null && ratio.isNotEmpty
            ? ratio
            : _localizedText(context, zh: '视频', en: 'VID'),
      _CreationMode.audio =>
        options.durationSeconds != null
            ? '${options.durationSeconds}s'
            : _localizedText(context, zh: '音频', en: 'AUD'),
      _CreationMode.deepResearch => _localizedText(context, zh: '研究', en: 'R'),
      _CreationMode.none => _localizedText(context, zh: '开', en: 'ON'),
    };
    return Tooltip(
      message: _localizedText(
        context,
        zh: '取消创建模式并恢复文本发送',
        en: 'Cancel creation mode and return to text',
      ),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubicEmphasized,
          child: FilledButton(
            onPressed: () => unawaited(onTap()),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            // NOTE: Do NOT wrap the label in AnimatedSwitcher with
            // ScaleTransition/RotationTransition here.  Those widgets extend
            // AnimatedWidget, whose _AnimatedState calls setState() on every
            // animation tick.  Inside a LayoutBuilder subtree, that setState
            // call propagates through BuildScope._scheduleBuildFor →
            // _LayoutBuilderElement._scheduleRebuild →
            // RenderObject.scheduleLayoutCallback, which asserts
            // debugNeedsLayout == true.  During handleBeginFrame the render
            // object has not yet been marked as needing layout, so the
            // assertion fires and produces a red-screen crash.
            // FadeTransition is safe (it is a SingleChildRenderObjectWidget
            // that drives opacity at the render level via markNeedsPaint).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                key: ValueKey<String>('creation-options-label-$label'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Composer shortcut interception ────────────────────────────────────────
//
// Hosts a Shortcuts/Actions pair just above the composer's TextField.  The
// activators are derived from the user's global SettingsController bindings
// (sendMessage / toggleComposer).  Because Shortcuts widgets are walked from
// the focused EditableText outward, this layer intercepts before the global
// DefaultTextEditingShortcuts (which would otherwise consume Ctrl+P as
// MoveSelectionUpTextIntent on macOS).

class _ComposerSendIntent extends Intent {
  const _ComposerSendIntent();
}

class _ComposerToggleCollapsedIntent extends Intent {
  const _ComposerToggleCollapsedIntent();
}

class _ComposerShortcutsHost extends StatelessWidget {
  const _ComposerShortcutsHost({
    required this.bindings,
    required this.onSend,
    required this.onToggleCollapsed,
    required this.child,
  });

  final Map<OpenHandShortcutAction, List<int>> bindings;
  final VoidCallback onSend;
  final VoidCallback onToggleCollapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shortcutMap = <ShortcutActivator, Intent>{};
    final sendActivators = _activatorsForBinding(
      bindings[OpenHandShortcutAction.sendMessage],
    );
    for (final activator in sendActivators) {
      shortcutMap[activator] = const _ComposerSendIntent();
    }
    final toggleActivators = _activatorsForBinding(
      bindings[OpenHandShortcutAction.toggleComposer],
    );
    for (final activator in toggleActivators) {
      shortcutMap[activator] = const _ComposerToggleCollapsedIntent();
    }
    if (shortcutMap.isEmpty) {
      return child;
    }
    return Shortcuts(
      shortcuts: shortcutMap,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ComposerSendIntent: CallbackAction<_ComposerSendIntent>(
            onInvoke: (_) {
              onSend();
              return null;
            },
          ),
          _ComposerToggleCollapsedIntent:
              CallbackAction<_ComposerToggleCollapsedIntent>(
                onInvoke: (_) {
                  onToggleCollapsed();
                  return null;
                },
              ),
        },
        child: child,
      ),
    );
  }

  // Convert the user-configured key binding (a normalised list of logical
  // key ids that already includes any modifiers) to a SingleActivator.
  static List<ShortcutActivator> _activatorsForBinding(List<int>? keyIds) {
    if (keyIds == null || keyIds.isEmpty) {
      return const <ShortcutActivator>[];
    }
    var control = false;
    var shift = false;
    var alt = false;
    var meta = false;
    LogicalKeyboardKey? trigger;
    for (final keyId in keyIds) {
      final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
      if (key == null) continue;
      if (key == LogicalKeyboardKey.control) {
        control = true;
      } else if (key == LogicalKeyboardKey.shift) {
        shift = true;
      } else if (key == LogicalKeyboardKey.alt) {
        alt = true;
      } else if (key == LogicalKeyboardKey.meta) {
        meta = true;
      } else {
        trigger ??= key;
      }
    }
    if (trigger == null) {
      return const <ShortcutActivator>[];
    }
    return <ShortcutActivator>[
      SingleActivator(
        trigger,
        control: control,
        shift: shift,
        alt: alt,
        meta: meta,
      ),
    ];
  }
}

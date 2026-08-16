// 管理并执行持久化的页面脚本片段。

part of 'web_reverse_dashboard_dialog.dart';

class _SnippetsBody extends StatefulWidget {
  const _SnippetsBody({required this.controller, required this.onPersist});
  final WebReverseSessionController controller;
  final VoidCallback onPersist;

  @override
  State<_SnippetsBody> createState() => _SnippetsBodyState();
}

class _SnippetsBodyState extends State<_SnippetsBody>
    with
        FrameCoalescedRebuild<_SnippetsBody>,
        _DashboardScriptEditorLifecycle<_SnippetsBody> {
  bool _running = false;
  String? _lastResultPreview;

  @override
  Listenable get _dashboardScriptController => widget.controller;

  @override
  void _syncSelectionFromController() {
    _syncDashboardScriptSelection(
      items: widget.controller.snippets,
      itemId: (snippet) => snippet.id,
      itemName: (snippet) => snippet.name,
      itemCode: (snippet) => snippet.code,
      syncAdditionalFields: (_) => _lastResultPreview = null,
    );
  }

  @override
  void _markDirty() {
    _updateDashboardScriptDirty(
      items: widget.controller.snippets,
      itemId: (snippet) => snippet.id,
      itemName: (snippet) => snippet.name,
      itemCode: (snippet) => snippet.code,
    );
  }

  void _select(WebReverseSnippet snip) {
    if (_dirty && _selectedId != null && _selectedId != snip.id) {
      unawaited(
        confirmWebReverseDiscardChanges(
          context: context,
          onConfirmed: () => _doSelect(snip),
        ),
      );
      return;
    }
    _doSelect(snip);
  }

  void _doSelect(WebReverseSnippet snip) {
    setState(() {
      _setDashboardScriptSelection(
        id: snip.id,
        name: snip.name,
        code: snip.code,
        syncAdditionalFields: () => _lastResultPreview = null,
      );
    });
  }

  void _newSnippet() {
    if (_dirty) {
      unawaited(
        confirmWebReverseDiscardChanges(context: context, onConfirmed: _doNew),
      );
      return;
    }
    _doNew();
  }

  void _doNew() {
    final ts = DateTime.now();
    final loc = AppLocalizations.of(context);
    final time = formatHourMinuteSecond(ts);
    final name = loc?.webReverseSnippetsNewName(time) ?? 'snippet $time';
    final s = widget.controller.addSnippet(
      name: name,
      code:
          '// ${loc?.webReverseSnippetsDefaultCode ?? 'Write JS here. Runs in page context.'}\n',
    );
    widget.onPersist();
    setState(() {
      _setDashboardScriptSelection(
        id: s.id,
        name: s.name,
        code: s.code,
        syncAdditionalFields: () => _lastResultPreview = null,
      );
    });
  }

  void _save() {
    final id = _selectedId;
    if (id == null) return;
    widget.controller.updateSnippet(
      id: id,
      name: _nameCtrl.text,
      code: _codeCtrl.text,
    );
    widget.onPersist();
    setState(() => _dirty = false);
  }

  Future<void> _run() async {
    final id = _selectedId;
    if (id == null) return;
    if (_dirty) _save(); // 先持久化再执行，避免「执行的不是看到的」。
    setState(() {
      _running = true;
      _lastResultPreview = null;
    });
    try {
      final r = await widget.controller.runSnippet(id);
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      setState(
        () => _lastResultPreview =
            r ?? (loc?.webReverseSnippetsNoResult ?? '(no result)'),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _delete() async {
    final id = _selectedId;
    if (id == null) return;
    final loc = AppLocalizations.of(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: loc?.webReverseSnippetsDeleteTitle ?? 'Delete snippet?',
      message: loc?.webReverseSnippetsDeleteContent ?? 'This cannot be undone.',
      cancelLabel: loc?.commonCancel ?? 'Cancel',
      confirmLabel: loc?.webReverseSnippetsDelete ?? 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    widget.controller.removeSnippet(id);
    widget.onPersist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final list = [...widget.controller.snippets]
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    return _DashboardScriptWorkspace(
      sidebarWidth: 260,
      libraryIcon: Icons.code_rounded,
      libraryTitle: loc?.webReverseSnippetsTitle ?? 'Snippet pad',
      createTooltip: loc?.webReverseSnippetsNew ?? 'New snippet',
      onCreate: _newSnippet,
      emptyLibraryLabel:
          loc?.webReverseSnippetsEmpty ??
          'No snippets yet.\nTap + to create one.',
      itemCount: list.length,
      itemBuilder: (_, index) {
        final snippet = list[index];
        return _SnippetTile(
          snippet: snippet,
          selected: snippet.id == _selectedId,
          onTap: () => _select(snippet),
        );
      },
      emptyEditorLabel:
          loc?.webReverseSnippetsPickPrompt ?? 'Pick a snippet or create one.',
      editor: _selectedId == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DashboardScriptNameField(
                        controller: _nameCtrl,
                        label: loc?.webReverseHooksNameLabel ?? 'Name',
                      ),
                    ),
                    kOpenHandHGap8,
                    FilledButton.icon(
                      onPressed: _running ? null : _run,
                      icon: OpenHandBusyStatusIcon(
                        busy: _running,
                        icon: Icons.play_arrow_rounded,
                      ),
                      label: Text(loc?.webReverseSnippetsRun ?? 'Run (⌘R)'),
                    ),
                    kOpenHandHGap6,
                    FilledButton.tonalIcon(
                      onPressed: _dirty ? _save : null,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _dirty
                            ? (loc?.webReverseSnippetsSaveDirty ?? 'Save *')
                            : (loc?.webReverseHooksSaved ?? 'Saved'),
                      ),
                    ),
                    kOpenHandHGap6,
                    IconButton(
                      tooltip: loc?.webReverseSnippetsDelete ?? 'Delete',
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                      onPressed: _delete,
                    ),
                  ],
                ),
                kOpenHandGap10,
                Expanded(
                  child: _DashboardScriptCodeEditor(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    bindings: _dashboardScriptEditorBindings(
                      onRun: () {
                        if (!_running) _run();
                      },
                      onSave: () {
                        if (_dirty) _save();
                      },
                    ),
                  ),
                ),
                _DashboardScriptResultPreview(text: _lastResultPreview),
              ],
            ),
    );
  }
}

class _SnippetTile extends StatefulWidget {
  const _SnippetTile({
    required this.snippet,
    required this.selected,
    required this.onTap,
  });
  final WebReverseSnippet snippet;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile>
    with OpenHandHoverState<_SnippetTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
    final bg = widget.selected
        ? cs.primary.withValues(alpha: 0.16)
        : (openHandHovered ? cs.surfaceContainerHighest : Colors.transparent);
    final border = widget.selected
        ? cs.primary.withValues(alpha: 0.55)
        : Colors.transparent;
    final ts = widget.snippet.updatedAt;
    final tsText = ts == null ? '' : formatHourMinute(ts);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setOpenHandHovered(true),
      onExit: (_) => setOpenHandHovered(false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : kOpenHandMotion140,
          curve: kOpenHandSwitchInCurve,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.javascript_rounded,
                size: 16,
                color: widget.selected ? cs.primary : cs.onSurfaceVariant,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  widget.snippet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
              if (tsText.isNotEmpty)
                Text(
                  tsText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

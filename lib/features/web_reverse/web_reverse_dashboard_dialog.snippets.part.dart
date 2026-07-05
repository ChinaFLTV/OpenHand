// 「脚本注入库 (Snippet Pad)」面板。
// 左侧列表 = 已保存的 snippet（按更新时间倒排）；右侧 = 名称 + 多行代码
// 编辑器 + Run/Save/Delete 工具栏。Run 走 [WebReverseSessionController
// .runSnippet]，结果写到 Console 面板（已有的 _appendConsole）。Save 触发
// dashboard 持久化到 session metadata，刷新/重连后自动恢复。
// 风格保持与其它面板一致：圆角胶囊按钮、220ms easeOutCubic 切换、Q弹
// AnimatedSwitcher / AnimatedSize；遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _SnippetsBody extends StatefulWidget {
  const _SnippetsBody({required this.controller, required this.onPersist});
  final WebReverseSessionController controller;
  final VoidCallback onPersist;

  @override
  State<_SnippetsBody> createState() => _SnippetsBodyState();
}

class _SnippetsBodyState extends State<_SnippetsBody> {
  String? _selectedId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  bool _dirty = false;
  bool _running = false;
  String? _lastResultPreview;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncSelectionFromController();
    _nameCtrl.addListener(_markDirty);
    _codeCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // 仅在 snippets 列表本身变化时刷新；其它 controller 通知不打扰编辑器。
    setState(() {});
    _syncSelectionFromController();
  }

  void _syncSelectionFromController() {
    final list = widget.controller.snippets;
    if (list.isEmpty) {
      _selectedId = null;
      if (_nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty) {
        _nameCtrl.text = '';
        _codeCtrl.text = '';
      }
      _dirty = false;
      return;
    }
    // 找当前选中；若已被删除，回退到第一项。
    final found = list.firstWhere(
      (e) => e.id == _selectedId,
      orElse: () => list.first,
    );
    if (_selectedId != found.id) {
      _selectedId = found.id;
      _nameCtrl.text = found.name;
      _codeCtrl.text = found.code;
      _dirty = false;
    }
  }

  void _markDirty() {
    if (_selectedId == null) {
      _dirty = _nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty;
    } else {
      final cur = widget.controller.snippets.firstWhere(
        (e) => e.id == _selectedId,
        orElse: () => const WebReverseSnippet(
          id: '',
          name: '',
          code: '',
          updatedAt: null,
        ),
      );
      _dirty = cur.name != _nameCtrl.text || cur.code != _codeCtrl.text;
    }
    if (mounted) setState(() {});
  }

  void _select(WebReverseSnippet snip) {
    if (_dirty && _selectedId != null && _selectedId != snip.id) {
      _confirmDiscard(() => _doSelect(snip));
      return;
    }
    _doSelect(snip);
  }

  void _doSelect(WebReverseSnippet snip) {
    setState(() {
      _selectedId = snip.id;
      _nameCtrl.text = snip.name;
      _codeCtrl.text = snip.code;
      _dirty = false;
      _lastResultPreview = null;
    });
  }

  void _newSnippet() {
    if (_dirty) {
      _confirmDiscard(_doNew);
      return;
    }
    _doNew();
  }

  void _doNew() {
    final ts = DateTime.now();
    final loc = AppLocalizations.of(context);
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    final name = loc?.webReverseSnippetsNewName(time) ?? 'snippet $time';
    final s = widget.controller.addSnippet(
      name: name,
      code:
          '// ${loc?.webReverseSnippetsDefaultCode ?? 'Write JS here. Runs in page context.'}\n',
    );
    widget.onPersist();
    setState(() {
      _selectedId = s.id;
      _nameCtrl.text = s.name;
      _codeCtrl.text = s.code;
      _dirty = false;
      _lastResultPreview = null;
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

  Future<void> _confirmDiscard(VoidCallback onConfirm) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: loc?.webReverseHooksDiscardTitle ?? 'Discard unsaved changes?',
      cancelLabel: loc?.webReverseHooksKeepEditing ?? 'Keep editing',
      confirmLabel: loc?.webReverseHooksDiscardConfirm ?? 'Discard',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final reduceMotion = !_wrMotionEnabled(context);
    final list = [...widget.controller.snippets]
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：列表 + 新建按钮
          SizedBox(
            width: 260,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Row(
                      children: [
                        Icon(Icons.code_rounded, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc?.webReverseSnippetsTitle ?? 'Snippet pad',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: loc?.webReverseSnippetsNew ?? 'New snippet',
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: _newSnippet,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                loc?.webReverseSnippetsEmpty ??
                                    'No snippets yet.\nTap + to create one.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 2),
                            itemBuilder: (_, i) {
                              final s = list[i];
                              final selected = s.id == _selectedId;
                              return _SnippetTile(
                                snippet: s,
                                selected: selected,
                                onTap: () => _select(s),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 右侧：编辑器
          Expanded(
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: _kSwitchInCurve,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: _selectedId == null
                  ? Center(
                      child: Text(
                        loc?.webReverseSnippetsPickPrompt ??
                            'Pick a snippet or create one.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nameCtrl,
                                maxLength: WebReverseSessionController
                                    .maxSavedScriptNameChars,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                buildCounter: _hideTextFieldCounter,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  labelText:
                                      loc?.webReverseHooksNameLabel ?? 'Name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _running ? null : _run,
                              icon: _running
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                loc?.webReverseSnippetsRun ?? 'Run (⌘R)',
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.tonalIcon(
                              onPressed: _dirty ? _save : null,
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: Text(
                                _dirty
                                    ? (loc?.webReverseSnippetsSaveDirty ??
                                          'Save *')
                                    : (loc?.webReverseHooksSaved ?? 'Saved'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip:
                                  loc?.webReverseSnippetsDelete ?? 'Delete',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: cs.error,
                              ),
                              onPressed: _delete,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.keyR,
                                meta: true,
                              ): () {
                                if (!_running) _run();
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.keyR,
                                control: true,
                              ): () {
                                if (!_running) _run();
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.keyS,
                                meta: true,
                              ): () {
                                if (_dirty) _save();
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.keyS,
                                control: true,
                              ): () {
                                if (_dirty) _save();
                              },
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: TextField(
                                controller: _codeCtrl,
                                focusNode: _codeFocus,
                                maxLines: null,
                                expands: true,
                                maxLength: WebReverseSessionController
                                    .maxSavedScriptCodeChars,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                buildCounter: _hideTextFieldCounter,
                                textAlignVertical: TextAlignVertical.top,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: reduceMotion
                              ? Duration.zero
                              : _kSwitchDuration,
                          curve: _kSwitchInCurve,
                          child: _lastResultPreview == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: cs.primary.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 14,
                                          color: cs.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: SelectableText(
                                            _lastResultPreview!,
                                            maxLines: 6,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
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

class _SnippetTileState extends State<_SnippetTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
    final bg = widget.selected
        ? cs.primary.withValues(alpha: 0.16)
        : (_hover ? cs.surfaceContainerHighest : Colors.transparent);
    final border = widget.selected
        ? cs.primary.withValues(alpha: 0.55)
        : Colors.transparent;
    final ts = widget.snippet.updatedAt;
    final tsText = ts == null
        ? ''
        : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (_hover) return;
        _hover = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hover) return;
        _hover = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.javascript_rounded,
                size: 16,
                color: widget.selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
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

// 「JS Hook 库」面板。
//
// 左侧：已保存的 hook 列表，每条带启用/禁用开关；右侧：名称 + 多行编辑器
// + 装载状态。Hook 通过 Page.addScriptToEvaluateOnNewDocument 在每个文档
// 加载前注入，可用于 patch window.fetch / 装载调试钩子 / 旁路反爬。
//
// 切换 target / 重新连接时由 controller 自动重装。enabled 切换 = 即时
// 装/卸；编辑保存 = 重装；删除 = 卸载并移除。
//
// 风格与 Snippet Pad 完全一致：圆角胶囊、220ms easeOutCubic 切换、Q弹
// AnimatedSwitcher / AnimatedSize；遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _HooksBody extends StatefulWidget {
  const _HooksBody({
    required this.controller,
    required this.onPersist,
  });
  final WebReverseSessionController controller;
  final VoidCallback onPersist;

  @override
  State<_HooksBody> createState() => _HooksBodyState();
}

class _HooksBodyState extends State<_HooksBody> {
  String? _selectedId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  bool _dirty = false;

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
    setState(() {});
    _syncSelectionFromController();
  }

  void _syncSelectionFromController() {
    final list = widget.controller.hooks;
    if (list.isEmpty) {
      _selectedId = null;
      if (_nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty) {
        _nameCtrl.text = '';
        _codeCtrl.text = '';
      }
      _dirty = false;
      return;
    }
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
    final id = _selectedId;
    if (id == null) {
      _dirty = _nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty;
    } else {
      final cur = widget.controller.hooks.firstWhere(
        (e) => e.id == id,
        orElse: () => const WebReverseHook(
          id: '',
          name: '',
          code: '',
          enabled: false,
          updatedAt: null,
        ),
      );
      _dirty = cur.name != _nameCtrl.text || cur.code != _codeCtrl.text;
    }
    if (mounted) setState(() {});
  }

  void _select(WebReverseHook h) {
    if (_dirty && _selectedId != null && _selectedId != h.id) {
      _confirmDiscard(() => _doSelect(h));
      return;
    }
    _doSelect(h);
  }

  void _doSelect(WebReverseHook h) {
    setState(() {
      _selectedId = h.id;
      _nameCtrl.text = h.name;
      _codeCtrl.text = h.code;
      _dirty = false;
    });
  }

  Future<void> _newHook() async {
    if (_dirty) {
      _confirmDiscard(_doNew);
      return;
    }
    await _doNew();
  }

  Future<void> _doNew() async {
    final ts = DateTime.now();
    final loc = AppLocalizations.of(context);
    final time =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    final name = loc?.webReverseHooksNewName(time) ?? 'hook $time';
    final h = await widget.controller.addHook(
      name: name,
      code:
          '// ${loc?.webReverseHooksDefaultCode ?? 'Runs before every document load; patch window/fetch etc.'}\n'
          '(() => {\n  // hook here\n})();\n',
    );
    widget.onPersist();
    if (!mounted) return;
    setState(() {
      _selectedId = h.id;
      _nameCtrl.text = h.name;
      _codeCtrl.text = h.code;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final id = _selectedId;
    if (id == null) return;
    await widget.controller.updateHook(
      id: id,
      name: _nameCtrl.text,
      code: _codeCtrl.text,
    );
    widget.onPersist();
    if (mounted) {
      setState(() => _dirty = false);
      final loc = AppLocalizations.of(context);
      OpenHandSnackBar.showSuccess(
        context,
        loc?.webReverseHooksSavedToast ?? 'Saved and reloaded',
      );
    }
  }

  Future<void> _toggle(WebReverseHook h, bool v) async {
    await widget.controller.setHookEnabled(h.id, v);
    widget.onPersist();
  }

  void _delete() {
    final id = _selectedId;
    if (id == null) return;
    final loc = AppLocalizations.of(context);
    showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(loc?.webReverseHooksDeleteTitle ?? 'Delete hook?'),
        content: Text(
          loc?.webReverseHooksDeleteContent ??
              'Will be uninstalled immediately.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(),
            label: loc?.commonCancel ?? 'Cancel',
          ),
          OpenHandDialogActionButton.destructive(
            onPressed: () async {
              await widget.controller.removeHook(id);
              widget.onPersist();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            label: loc?.webReverseHooksDelete ?? 'Delete',
          ),
        ],
      ),
    );
  }

  void _confirmDiscard(VoidCallback onConfirm) {
    final loc = AppLocalizations.of(context);
    showAnimatedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          loc?.webReverseHooksDiscardTitle ?? 'Discard unsaved changes?',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(),
            label: loc?.webReverseHooksKeepEditing ?? 'Keep editing',
          ),
          OpenHandDialogActionButton.destructive(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            label: loc?.webReverseHooksDiscardConfirm ?? 'Discard',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final list = [...widget.controller.hooks]
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
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
                        Icon(
                          Icons.fingerprint_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc?.webReverseHooksLibrary ?? 'Hook library',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: loc?.webReverseHooksNew ?? 'New hook',
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: _newHook,
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
                                loc?.webReverseHooksEmpty ??
                                    'No hooks yet.\nTap + to create one.',
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
                              final h = list[i];
                              final selected = h.id == _selectedId;
                              return _HookTile(
                                hook: h,
                                selected: selected,
                                onTap: () => _select(h),
                                onToggle: (v) => _toggle(h, v),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                        loc?.webReverseHooksPickPrompt ??
                            'Pick a hook or create one.',
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
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  labelText:
                                      loc?.webReverseHooksNameLabel ?? 'Name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: _dirty ? _save : null,
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: Text(
                                _dirty
                                    ? (loc?.webReverseHooksSave ?? 'Save (⌘S)')
                                    : (loc?.webReverseHooksSaved ?? 'Saved'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: loc?.webReverseHooksDelete ?? 'Delete',
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
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  loc?.webReverseHooksInfo ??
                                      'Save reloads instantly. Runs before each document loads; survives tab switch and reload.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
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

class _HookTile extends StatefulWidget {
  const _HookTile({
    required this.hook,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });
  final WebReverseHook hook;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  State<_HookTile> createState() => _HookTileState();
}

class _HookTileState extends State<_HookTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bg = widget.selected
        ? cs.primary.withValues(alpha: 0.12)
        : (_hover ? cs.surfaceContainerHighest : Colors.transparent);
    final border = widget.selected
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0.0);
    return MouseRegion(
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
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.hook.enabled
                      ? Colors.green.shade400
                      : cs.outlineVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.hook.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.hook.enabled
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: widget.hook.enabled,
                  onChanged: widget.onToggle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

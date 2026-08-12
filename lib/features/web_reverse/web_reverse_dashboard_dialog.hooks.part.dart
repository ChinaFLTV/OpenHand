// 管理在文档加载前注入的 JS Hook。

part of 'web_reverse_dashboard_dialog.dart';

class _HooksBody extends StatefulWidget {
  const _HooksBody({required this.controller, required this.onPersist});
  final WebReverseSessionController controller;
  final VoidCallback onPersist;

  @override
  State<_HooksBody> createState() => _HooksBodyState();
}

class _HooksBodyState extends State<_HooksBody>
    with
        FrameCoalescedRebuild<_HooksBody>,
        _DashboardScriptEditorLifecycle<_HooksBody> {
  @override
  Listenable get _dashboardScriptController => widget.controller;

  @override
  void _syncSelectionFromController() {
    _syncDashboardScriptSelection(
      items: widget.controller.hooks,
      itemId: (hook) => hook.id,
      itemName: (hook) => hook.name,
      itemCode: (hook) => hook.code,
    );
  }

  @override
  void _markDirty() {
    _updateDashboardScriptDirty(
      items: widget.controller.hooks,
      itemId: (hook) => hook.id,
      itemName: (hook) => hook.name,
      itemCode: (hook) => hook.code,
    );
  }

  void _select(WebReverseHook h) {
    if (_dirty && _selectedId != null && _selectedId != h.id) {
      unawaited(
        confirmWebReverseDiscardChanges(
          context: context,
          onConfirmed: () => _doSelect(h),
        ),
      );
      return;
    }
    _doSelect(h);
  }

  void _doSelect(WebReverseHook h) {
    setState(() {
      _setDashboardScriptSelection(id: h.id, name: h.name, code: h.code);
    });
  }

  Future<void> _newHook() async {
    if (_dirty) {
      await confirmWebReverseDiscardChanges(
        context: context,
        onConfirmed: _doNew,
      );
      return;
    }
    await _doNew();
  }

  Future<void> _doNew() async {
    final ts = DateTime.now();
    final loc = AppLocalizations.of(context);
    final time = formatHourMinuteSecond(ts);
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
      _setDashboardScriptSelection(id: h.id, name: h.name, code: h.code);
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
      showOpenHandSuccessSnack(
        context,
        loc?.webReverseHooksSavedToast ?? 'Saved and reloaded',
      );
    }
  }

  Future<void> _toggle(WebReverseHook h, bool v) async {
    await widget.controller.setHookEnabled(h.id, v);
    widget.onPersist();
  }

  Future<void> _delete() async {
    final id = _selectedId;
    if (id == null) return;
    final loc = AppLocalizations.of(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: loc?.webReverseHooksDeleteTitle ?? 'Delete hook?',
      message:
          loc?.webReverseHooksDeleteContent ??
          'Will be uninstalled immediately.',
      cancelLabel: loc?.commonCancel ?? 'Cancel',
      confirmLabel: loc?.webReverseHooksDelete ?? 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.controller.removeHook(id);
    if (!mounted) return;
    widget.onPersist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final list = [...widget.controller.hooks]
      ..sort(
        (a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
      );
    return _DashboardScriptWorkspace(
      sidebarWidth: 280,
      libraryIcon: Icons.fingerprint_rounded,
      libraryTitle: loc?.webReverseHooksLibrary ?? 'Hook library',
      createTooltip: loc?.webReverseHooksNew ?? 'New hook',
      onCreate: _newHook,
      emptyLibraryLabel:
          loc?.webReverseHooksEmpty ?? 'No hooks yet.\nTap + to create one.',
      itemCount: list.length,
      itemBuilder: (_, index) {
        final hook = list[index];
        return _DashboardToggleTile(
          title: hook.name,
          enabled: hook.enabled,
          selected: hook.id == _selectedId,
          onTap: () => _select(hook),
          onToggle: (value) => _toggle(hook, value),
        );
      },
      emptyEditorLabel:
          loc?.webReverseHooksPickPrompt ?? 'Pick a hook or create one.',
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
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                      onPressed: _delete,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _DashboardScriptCodeEditor(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    bindings: _dashboardScriptEditorBindings(
                      onSave: () {
                        if (_dirty) _save();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.04),
                    borderRadius: kWebReverseRadiusLarge,
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
    );
  }
}

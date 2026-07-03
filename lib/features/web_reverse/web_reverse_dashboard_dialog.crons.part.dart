// 「定时任务 Crons」面板。
//
// 左侧：cron 列表（开关 + 名称 + 周期 + 上次执行）；右侧：名称 + 周期秒数
// + 多行编辑器 + Save / Run-now / Delete。每条 cron 通过控制器内部安全周期定时器
// 持续运行；切换 dashboard tab 不停。删除 / 关闭 = cancel Timer。
//
// 风格：与 Snippets / Hooks 保持一致 — 圆角胶囊、220ms easeOutCubic Q弹动画、
// 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _CronsBody extends StatefulWidget {
  const _CronsBody({
    required this.controller,
    required this.isZh,
    required this.onPersist,
  });
  final WebReverseSessionController controller;
  final bool isZh;
  final VoidCallback onPersist;

  @override
  State<_CronsBody> createState() => _CronsBodyState();
}

class _CronsBodyState extends State<_CronsBody> {
  String? _selectedId;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _intervalCtrl = TextEditingController(text: '60');
  final FocusNode _codeFocus = FocusNode();
  bool _dirty = false;
  bool _runningNow = false;
  String? _lastResultPreview;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncSelectionFromController();
    _nameCtrl.addListener(_markDirty);
    _codeCtrl.addListener(_markDirty);
    _intervalCtrl.addListener(_markDirty);
    // 每秒刷一次「上次执行 X 秒前」标签。
    _tickTimer = startSafePeriodicTimer(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _intervalCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _syncSelectionFromController();
  }

  void _syncSelectionFromController() {
    final list = widget.controller.crons;
    if (list.isEmpty) {
      _selectedId = null;
      if (_nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty) {
        _nameCtrl.text = '';
        _codeCtrl.text = '';
        _intervalCtrl.text = '60';
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
      _intervalCtrl.text = found.intervalSeconds.toString();
      _dirty = false;
      _lastResultPreview = null;
    }
  }

  void _markDirty() {
    final id = _selectedId;
    if (id == null) {
      _dirty = _nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty;
    } else {
      final cur = widget.controller.crons.firstWhere(
        (e) => e.id == id,
        orElse: () => const WebReverseCron(
          id: '',
          name: '',
          code: '',
          intervalSeconds: 0,
          enabled: false,
          updatedAt: null,
        ),
      );
      final iv =
          optionalIntFromValue(_intervalCtrl.text) ?? cur.intervalSeconds;
      _dirty =
          cur.name != _nameCtrl.text ||
          cur.code != _codeCtrl.text ||
          cur.intervalSeconds != iv;
    }
    if (mounted) setState(() {});
  }

  void _select(WebReverseCron c) {
    if (_dirty && _selectedId != null && _selectedId != c.id) {
      _confirmDiscard(() => _doSelect(c));
      return;
    }
    _doSelect(c);
  }

  void _doSelect(WebReverseCron c) {
    setState(() {
      _selectedId = c.id;
      _nameCtrl.text = c.name;
      _codeCtrl.text = c.code;
      _intervalCtrl.text = c.intervalSeconds.toString();
      _dirty = false;
      _lastResultPreview = null;
    });
  }

  Future<void> _newCron() async {
    if (_dirty) {
      _confirmDiscard(_doNew);
      return;
    }
    await _doNew();
  }

  Future<void> _doNew() async {
    final ts = DateTime.now();
    final isZh = widget.isZh;
    final name =
        '${isZh ? "任务" : "cron"} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
    final c = await widget.controller.addCron(
      name: name,
      code:
          '// ${isZh ? "周期性 JS。例：刷新登录态、轮询接口、自动点续期" : "Periodic JS. Heartbeat / polling / auto-renew."}\n'
          '// ${isZh ? "在这里写入需要定时执行的安静脚本。" : "Add quiet scheduled script logic here."}\n',
      intervalSeconds: 60,
    );
    widget.onPersist();
    if (!mounted) return;
    setState(() {
      _selectedId = c.id;
      _nameCtrl.text = c.name;
      _codeCtrl.text = c.code;
      _intervalCtrl.text = c.intervalSeconds.toString();
      _dirty = false;
      _lastResultPreview = null;
    });
  }

  Future<bool> _save() async {
    final id = _selectedId;
    if (id == null) return false;
    final iv = optionalIntFromValue(_intervalCtrl.text);
    if (iv == null ||
        iv < WebReverseSessionController.minCronIntervalSeconds ||
        iv > WebReverseSessionController.maxCronIntervalSeconds) {
      OpenHandSnackBar.showError(
        context,
        widget.isZh
            ? '周期需为 ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} 秒'
            : 'Interval must be ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} seconds',
      );
      return false;
    }
    await widget.controller.updateCron(
      id: id,
      name: _nameCtrl.text,
      code: _codeCtrl.text,
      intervalSeconds: iv,
    );
    widget.onPersist();
    if (mounted) {
      setState(() => _dirty = false);
      OpenHandSnackBar.showSuccess(context, widget.isZh ? '已保存' : 'Saved');
    }
    return true;
  }

  Future<void> _runNow() async {
    final id = _selectedId;
    if (id == null) return;
    if (_dirty && !await _save()) return;
    setState(() {
      _runningNow = true;
      _lastResultPreview = null;
    });
    try {
      final r = await widget.controller.runCronNow(id);
      if (!mounted) return;
      setState(
        () =>
            _lastResultPreview = r ?? (widget.isZh ? '(无返回值)' : '(no result)'),
      );
    } finally {
      if (mounted) setState(() => _runningNow = false);
    }
  }

  Future<void> _toggle(WebReverseCron c, bool v) async {
    await widget.controller.setCronEnabled(c.id, v);
    widget.onPersist();
  }

  Future<void> _delete() async {
    final id = _selectedId;
    if (id == null) return;
    final isZh = widget.isZh;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除任务？' : 'Delete cron?',
      message: isZh ? '将立即取消定时并不可撤销。' : 'Timer will be cancelled.',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '删除' : 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.controller.removeCron(id);
    if (!mounted) return;
    widget.onPersist();
  }

  Future<void> _confirmDiscard(VoidCallback onConfirm) async {
    final isZh = widget.isZh;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '丢弃未保存改动？' : 'Discard unsaved changes?',
      cancelLabel: isZh ? '继续编辑' : 'Keep editing',
      confirmLabel: isZh ? '丢弃' : 'Discard',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    onConfirm();
  }

  String _formatAgo(DateTime? t, bool isZh) {
    if (t == null) return isZh ? '从未' : 'never';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 5) return isZh ? '刚刚' : 'just now';
    if (s < 60) return isZh ? '${s}s 前' : '${s}s ago';
    final m = s ~/ 60;
    if (m < 60) return isZh ? '${m}m 前' : '${m}m ago';
    final h = m ~/ 60;
    return isZh ? '${h}h 前' : '${h}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final list = [...widget.controller.crons]
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
            width: 300,
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
                          Icons.schedule_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isZh ? '定时任务' : 'Crons',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: isZh ? '新建任务' : 'New cron',
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: _newCron,
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
                                isZh
                                    ? '暂无任务。\n点 + 新建第一个。'
                                    : 'No crons yet.\nTap + to create one.',
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
                              final c = list[i];
                              final selected = c.id == _selectedId;
                              return _CronTile(
                                cron: c,
                                selected: selected,
                                lastRunLabel: _formatAgo(
                                  widget.controller.cronLastRunAt(c.id),
                                  isZh,
                                ),
                                onTap: () => _select(c),
                                onToggle: (v) => _toggle(c, v),
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
                        isZh ? '从左侧选一个任务，或新建一个。' : 'Pick a cron or create one.',
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
                              flex: 3,
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
                                  labelText: isZh ? '名称' : 'Name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: _intervalCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 5,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                buildCounter: _hideTextFieldCounter,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  labelText: isZh ? '周期(秒)' : 'Every (s)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _runningNow ? null : _runNow,
                              icon: _runningNow
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
                              label: Text(isZh ? '立即跑' : 'Run now'),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.tonalIcon(
                              onPressed: _dirty ? _save : null,
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: Text(
                                _dirty
                                    ? (isZh ? '保存 (⌘S)' : 'Save (⌘S)')
                                    : (isZh ? '已保存' : 'Saved'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: isZh ? '删除' : 'Delete',
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
                              const SingleActivator(
                                LogicalKeyboardKey.keyR,
                                meta: true,
                              ): () {
                                if (!_runningNow) _runNow();
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.keyR,
                                control: true,
                              ): () {
                                if (!_runningNow) _runNow();
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

class _CronTile extends StatefulWidget {
  const _CronTile({
    required this.cron,
    required this.selected,
    required this.lastRunLabel,
    required this.onTap,
    required this.onToggle,
  });
  final WebReverseCron cron;
  final bool selected;
  final String lastRunLabel;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  State<_CronTile> createState() => _CronTileState();
}

class _CronTileState extends State<_CronTile> {
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
                  color: widget.cron.enabled
                      ? Colors.green.shade400
                      : cs.outlineVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cron.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.cron.enabled
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'every ${widget.cron.intervalSeconds}s · ${widget.lastRunLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: widget.cron.enabled,
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

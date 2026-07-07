// 「定时任务 Crons」面板。
// 左侧：cron 列表（开关 + 名称 + 周期 + 上次执行）；右侧：名称 + 周期秒数
// + 多行编辑器 + Save / Run-now / Delete。每条 cron 通过控制器内部安全周期定时器
// 持续运行；切换 dashboard tab 不停。删除 / 关闭 = cancel Timer。
// 风格：与 Snippets / Hooks 保持一致 — 圆角胶囊、220ms easeOutCubic Q弹动画、
// 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _CronsBody extends StatefulWidget {
  const _CronsBody({required this.controller, required this.onPersist});
  final WebReverseSessionController controller;
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
    final name =
        '${_text(zh: "任务", zhHant: "任務", en: "cron", fr: "tâche", de: "Cron", ja: "タスク")} '
        '${formatHourMinuteSecond(ts)}';
    final c = await widget.controller.addCron(
      name: name,
      code: _defaultCronCode(),
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
      showWebReverseErrorSnack(
        context,
        _text(
          zh: '周期需为 ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} 秒',
          zhHant:
              '週期需為 ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} 秒',
          en: 'Interval must be ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} seconds',
          fr: "L'intervalle doit être de ${WebReverseSessionController.minCronIntervalSeconds} à ${WebReverseSessionController.maxCronIntervalSeconds} s",
          de: 'Intervall muss ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} s betragen',
          ja: '間隔は ${WebReverseSessionController.minCronIntervalSeconds}-${WebReverseSessionController.maxCronIntervalSeconds} 秒にしてください',
        ),
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
      showWebReverseSuccessSnack(
        context,
        _text(
          zh: '已保存',
          zhHant: '已儲存',
          en: 'Saved',
          fr: 'Enregistré',
          de: 'Gespeichert',
          ja: '保存しました',
        ),
      );
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
        () => _lastResultPreview =
            r ??
            _text(
              zh: '(无返回值)',
              zhHant: '(無返回值)',
              en: '(no result)',
              fr: '(aucun résultat)',
              de: '(kein Ergebnis)',
              ja: '(戻り値なし)',
            ),
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
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _text(
        zh: '删除任务？',
        zhHant: '刪除任務？',
        en: 'Delete cron?',
        fr: 'Supprimer la tâche ?',
        de: 'Cron löschen?',
        ja: 'タスクを削除しますか？',
      ),
      message: _text(
        zh: '将立即取消定时并不可撤销。',
        zhHant: '將立即取消定時且無法復原。',
        en: 'Timer will be cancelled.',
        fr: 'Le minuteur sera annulé.',
        de: 'Der Timer wird beendet.',
        ja: 'タイマーは直ちに解除されます。',
      ),
      cancelLabel: _text(
        zh: '取消',
        zhHant: '取消',
        en: 'Cancel',
        fr: 'Annuler',
        de: 'Abbrechen',
        ja: 'キャンセル',
      ),
      confirmLabel: _text(
        zh: '删除',
        zhHant: '刪除',
        en: 'Delete',
        fr: 'Supprimer',
        de: 'Löschen',
        ja: '削除',
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.controller.removeCron(id);
    if (!mounted) return;
    widget.onPersist();
  }

  Future<void> _confirmDiscard(VoidCallback onConfirm) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _text(
        zh: '丢弃未保存改动？',
        zhHant: '捨棄未儲存變更？',
        en: 'Discard unsaved changes?',
        fr: 'Ignorer les modifications ?',
        de: 'Ungespeicherte Änderungen verwerfen?',
        ja: '未保存の変更を破棄しますか？',
      ),
      cancelLabel: _text(
        zh: '继续编辑',
        zhHant: '繼續編輯',
        en: 'Keep editing',
        fr: 'Continuer',
        de: 'Weiter bearbeiten',
        ja: '編集を続ける',
      ),
      confirmLabel: _text(
        zh: '丢弃',
        zhHant: '捨棄',
        en: 'Discard',
        fr: 'Ignorer',
        de: 'Verwerfen',
        ja: '破棄',
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    onConfirm();
  }

  String _formatAgo(DateTime? t) {
    if (t == null) {
      return _text(
        zh: '从未',
        zhHant: '從未',
        en: 'never',
        fr: 'jamais',
        de: 'nie',
        ja: '未実行',
      );
    }
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 5) {
      return _text(
        zh: '刚刚',
        zhHant: '剛剛',
        en: 'just now',
        fr: "à l'instant",
        de: 'gerade eben',
        ja: 'たった今',
      );
    }
    if (s < 60) {
      return _text(
        zh: '${s}s 前',
        zhHant: '${s}s 前',
        en: '${s}s ago',
        fr: 'il y a ${s}s',
        de: 'vor ${s}s',
        ja: '$s秒前',
      );
    }
    final m = s ~/ 60;
    if (m < 60) {
      return _text(
        zh: '${m}m 前',
        zhHant: '${m}m 前',
        en: '${m}m ago',
        fr: 'il y a $m min',
        de: 'vor $m Min.',
        ja: '$m分前',
      );
    }
    final h = m ~/ 60;
    return _text(
      zh: '${h}h 前',
      zhHant: '${h}h 前',
      en: '${h}h ago',
      fr: 'il y a $h h',
      de: 'vor $h Std.',
      ja: '$h時間前',
    );
  }

  String _cronStatusLabel(WebReverseCron cron) {
    final ago = _formatAgo(widget.controller.cronLastRunAt(cron.id));
    return _text(
      zh: '每 ${cron.intervalSeconds}s · $ago',
      zhHant: '每 ${cron.intervalSeconds}s · $ago',
      en: 'every ${cron.intervalSeconds}s · $ago',
      fr: 'toutes les ${cron.intervalSeconds}s · $ago',
      de: 'alle ${cron.intervalSeconds}s · $ago',
      ja: '${cron.intervalSeconds}秒ごと · $ago',
    );
  }

  String _defaultCronCode() {
    final purpose = _text(
      zh: '// 周期性 JS：心跳、轮询、自动续期。',
      zhHant: '// 週期性 JS：心跳、輪詢、自動續期。',
      en: '// Periodic JS: heartbeat, polling, auto-renew.',
      fr: '// JS périodique : heartbeat, polling, renouvellement.',
      de: '// Periodisches JS: Heartbeat, Polling, Auto-Renew.',
      ja: '// 定期 JS: ハートビート、ポーリング、自動更新。',
    );
    final guidance = _text(
      zh: '// 在这里写入安静、可重复执行的逻辑。',
      zhHant: '// 在此寫入安靜、可重複執行的邏輯。',
      en: '// Add quiet, repeatable logic here.',
      fr: '// Ajoutez ici une logique discrète et répétable.',
      de: '// Ruhige, wiederholbare Logik hier einfügen.',
      ja: '// 静かに繰り返せる処理をここに書きます。',
    );
    return '$purpose\n$guidance\n';
  }

  String _text({
    required String zh,
    required String en,
    String? zhHant,
    String? fr,
    String? de,
    String? ja,
  }) {
    return openHandLocalizedText(
      context,
      zh: zh,
      zhHant: zhHant,
      en: en,
      fr: fr,
      de: de,
      ja: ja,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
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
                            _text(
                              zh: '定时任务',
                              zhHant: '定時任務',
                              en: 'Crons',
                              fr: 'Tâches',
                              de: 'Cronjobs',
                              ja: '定期タスク',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _text(
                            zh: '新建任务',
                            zhHant: '新增任務',
                            en: 'New cron',
                            fr: 'Nouvelle tâche',
                            de: 'Neuer Cron',
                            ja: '新規タスク',
                          ),
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
                                _text(
                                  zh: '暂无任务。\n点 + 新建第一个。',
                                  zhHant: '暫無任務。\n點 + 新增第一個。',
                                  en: 'No crons yet.\nTap + to create one.',
                                  fr: 'Aucune tâche.\nTouchez + pour en créer une.',
                                  de: 'Noch keine Crons.\nMit + den ersten erstellen.',
                                  ja: 'タスクはまだありません。\n+ で作成します。',
                                ),
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
                                statusLabel: _cronStatusLabel(c),
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
                        _text(
                          zh: '从左侧选一个任务，或新建一个。',
                          zhHant: '從左側選一個任務，或新增一個。',
                          en: 'Pick a cron or create one.',
                          fr: 'Choisissez une tâche ou créez-en une.',
                          de: 'Cron auswählen oder erstellen.',
                          ja: 'タスクを選択するか新規作成してください。',
                        ),
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
                                  labelText: _text(
                                    zh: '名称',
                                    zhHant: '名稱',
                                    en: 'Name',
                                    fr: 'Nom',
                                    de: 'Name',
                                    ja: '名前',
                                  ),
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
                                  labelText: _text(
                                    zh: '周期(秒)',
                                    zhHant: '週期(秒)',
                                    en: 'Every (s)',
                                    fr: 'Toutes les (s)',
                                    de: 'Alle (s)',
                                    ja: '間隔(秒)',
                                  ),
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
                              label: Text(
                                _text(
                                  zh: '立即跑',
                                  zhHant: '立即執行',
                                  en: 'Run now',
                                  fr: 'Exécuter',
                                  de: 'Jetzt ausführen',
                                  ja: '今すぐ実行',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.tonalIcon(
                              onPressed: _dirty ? _save : null,
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: Text(
                                _dirty
                                    ? _text(
                                        zh: '保存 (⌘S)',
                                        zhHant: '儲存 (⌘S)',
                                        en: 'Save (⌘S)',
                                        fr: 'Enregistrer (⌘S)',
                                        de: 'Speichern (⌘S)',
                                        ja: '保存 (⌘S)',
                                      )
                                    : _text(
                                        zh: '已保存',
                                        zhHant: '已儲存',
                                        en: 'Saved',
                                        fr: 'Enregistré',
                                        de: 'Gespeichert',
                                        ja: '保存済み',
                                      ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: _text(
                                zh: '删除',
                                zhHant: '刪除',
                                en: 'Delete',
                                fr: 'Supprimer',
                                de: 'Löschen',
                                ja: '削除',
                              ),
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
    required this.statusLabel,
    required this.onTap,
    required this.onToggle,
  });
  final WebReverseCron cron;
  final bool selected;
  final String statusLabel;
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
    final reduceMotion = !_wrMotionEnabled(context);
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
                      widget.statusLabel,
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

// 管理由控制器安全调度的周期脚本任务。

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
      unawaited(
        confirmWebReverseDiscardChanges(
          context: context,
          onConfirmed: () => _doSelect(c),
        ),
      );
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
      showOpenHandErrorSnack(
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
      showOpenHandSuccessSnack(
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
      cancelLabel: openHandCancelLabel(context),
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
                              return _DashboardToggleTile(
                                title: c.name,
                                subtitle: _cronStatusLabel(c),
                                enabled: c.enabled,
                                selected: selected,
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
                          child: _DashboardScriptCodeEditor(
                            controller: _codeCtrl,
                            focusNode: _codeFocus,
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
                          ),
                        ),
                        _DashboardScriptResultPreview(text: _lastResultPreview),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

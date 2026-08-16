// 「断点」独立面板：
// 三段式：
//   1) Source breakpoints —— controller.userBreakpoints 列出，每条带「跳到 Sources」+ 删除。
//   2) Pause on exceptions —— 三态 SegmentedButton: 关 / 仅未捕获 / 全部抛出。
//   3) XHR / fetch breakpoints —— 子串匹配的 URL 列表 + 新增输入框 + 删除按钮。
// 风格：圆角胶囊 + 220ms easeOutCubic 切换 + Q弹 AnimatedSize/Switcher，
// 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _BreakpointsBody extends StatefulWidget {
  const _BreakpointsBody({
    required this.controller,
    required this.onPersist,
    required this.onJumpToSource,
  });
  final WebReverseSessionController controller;
  final VoidCallback onPersist;
  final void Function(String url, int line) onJumpToSource;

  @override
  State<_BreakpointsBody> createState() => _BreakpointsBodyState();
}

class _BreakpointsBodyState extends State<_BreakpointsBody>
    with FrameCoalescedRebuild<_BreakpointsBody> {
  final TextEditingController _xhrCtrl = TextEditingController();
  final TextEditingController _domSelectorCtrl = TextEditingController();
  String _domType = 'subtree-modified';
  // Event Listener 断点支持的事件按类目分组（与 Chrome DevTools 命名一致）。
  // 用户在 UI 上勾选 chip 后调用 setEventListenerBreakpoint。
  static const Map<String, List<String>> _kEventCategories = {
    'Mouse': [
      'click',
      'auxclick',
      'dblclick',
      'mousedown',
      'mouseup',
      'mouseenter',
      'mouseleave',
      'mousemove',
      'mouseover',
      'mouseout',
      'contextmenu',
      'wheel',
    ],
    'Keyboard': ['keydown', 'keypress', 'keyup'],
    'Touch': ['touchstart', 'touchmove', 'touchend', 'touchcancel'],
    'Pointer': [
      'pointerdown',
      'pointerup',
      'pointermove',
      'pointerover',
      'pointerout',
      'pointerenter',
      'pointerleave',
      'pointercancel',
    ],
    'Control': [
      'focus',
      'blur',
      'change',
      'input',
      'submit',
      'reset',
      'select',
      'invalid',
    ],
    'Clipboard': ['copy', 'cut', 'paste'],
    'DOM Mutation': [
      'DOMNodeInserted',
      'DOMNodeRemoved',
      'DOMAttrModified',
      'DOMCharacterDataModified',
    ],
    'Timer': ['timer:setTimeout', 'timer:setInterval'],
    'Animation': [
      'animationstart',
      'animationend',
      'animationiteration',
      'transitionstart',
      'transitionend',
    ],
    'Load': ['load', 'beforeunload', 'unload', 'DOMContentLoaded'],
    'Worker': ['message', 'messageerror'],
    'XHR': ['xhrSend', 'xhrReadyStateChange'],
    'Drag/Drop': [
      'drag',
      'dragstart',
      'dragend',
      'dragenter',
      'dragleave',
      'dragover',
      'drop',
    ],
  };

  bool _gListLoading = false;
  List<Map<String, Object?>>? _globalListeners;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _xhrCtrl.dispose();
    _domSelectorCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() => scheduleCoalescedRebuild();

  Future<void> _removeSourceBp(({String url, int line}) b) async {
    final ok = await widget.controller.removeBreakpointAt(
      url: b.url,
      line: b.line,
    );
    if (!mounted) return;
    if (ok) {
      widget.onPersist();
    } else {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '取消断点失败',
          zhHant: '取消斷點失敗',
          en: 'Failed to remove breakpoint',
          fr: 'Échec de suppression du point d’arrêt',
          de: 'Breakpoint konnte nicht entfernt werden',
          ja: 'ブレークポイントを解除できませんでした',
        ),
      );
    }
  }

  // 条件断点编辑器：从行号右侧 ✎ 图标进入。Esc/取消保留原值；保存后调
  // controller.setBreakpointCondition（内部走 remove + setBreakpointByUrl
  // 重建），结果通过 _safeNotify → addListener → setState 刷新 UI。
  Future<void> _editSourceBpCondition(({String url, int line}) b) async {
    final existing = widget.controller.breakpointCondition(
      url: b.url,
      line: b.line,
    );
    final ctrl = TextEditingController(text: existing);
    String? value;
    try {
      value = await webReverseToolDialogs.show<String>(
        context: context,
        builder: (dialogContext) {
          return buildOpenHandAlertDialog(
            title: Text(
              _text(
                zh: '编辑条件断点',
                zhHant: '編輯條件斷點',
                en: 'Edit conditional breakpoint',
                fr: 'Modifier le point d’arrêt conditionnel',
                de: 'Bedingten Breakpoint bearbeiten',
                ja: '条件付きブレークポイントを編集',
              ),
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(
                      zh: '当表达式求值为真时才暂停。留空则改回普通断点。\n表达式在断点所在栈帧的作用域内求值。',
                      zhHant: '當表達式求值為真時才暫停。留空則改回普通斷點。\n表達式會在斷點所在棧幀的作用域內求值。',
                      en: 'Pause only when the expression is truthy. Leave empty to revert to a plain breakpoint.\nEvaluated in the frame scope where the breakpoint fires.',
                      fr: 'Suspend uniquement si l’expression est vraie. Laissez vide pour revenir à un point d’arrêt simple.\nÉvalué dans la portée de la frame concernée.',
                      de: 'Nur pausieren, wenn der Ausdruck wahr ist. Leer lassen für einen normalen Breakpoint.\nAuswertung im Scope des auslösenden Frames.',
                      ja: '式が true のときだけ停止します。空にすると通常のブレークポイントに戻ります。\n停止したフレームのスコープで評価されます。',
                    ),
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  kOpenHandGap12,
                  Text(
                    '${b.url}  ${_lineLabel(b.line)}',
                    style: Theme.of(dialogContext).textTheme.labelSmall
                        ?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  kOpenHandGap10,
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: _text(
                        zh: '例如：count > 100 && user.id === 42',
                        zhHant: '例如：count > 100 && user.id === 42',
                        en: 'e.g. count > 100 && user.id === 42',
                        fr: 'ex. count > 100 && user.id === 42',
                        de: 'z. B. count > 100 && user.id === 42',
                        ja: '例: count > 100 && user.id === 42',
                      ),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                label: openHandCancelLabel(dialogContext),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              OpenHandDialogActionButton.primary(
                label: _text(
                  zh: '保存',
                  zhHant: '儲存',
                  en: 'Save',
                  fr: 'Enregistrer',
                  de: 'Speichern',
                  ja: '保存',
                ),
                onPressed: () => Navigator.of(dialogContext).pop(ctrl.text),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
    if (!mounted || value == null) return;
    final newId = await widget.controller.setBreakpointCondition(
      url: b.url,
      line: b.line,
      condition: value,
    );
    if (!mounted) return;
    if (newId == null) {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '更新条件断点失败',
          zhHant: '更新條件斷點失敗',
          en: 'Failed to update conditional breakpoint',
          fr: 'Échec de mise à jour du point d’arrêt conditionnel',
          de: 'Bedingter Breakpoint konnte nicht aktualisiert werden',
          ja: '条件付きブレークポイントを更新できませんでした',
        ),
      );
    } else {
      widget.onPersist();
      showOpenHandSuccessSnack(
        context,
        value.trim().isEmpty
            ? _text(
                zh: '已转为普通断点',
                zhHant: '已轉為普通斷點',
                en: 'Reverted to plain breakpoint',
                fr: 'Revenu à un point d’arrêt simple',
                de: 'In normalen Breakpoint umgewandelt',
                ja: '通常のブレークポイントに戻しました',
              )
            : _text(
                zh: '条件断点已生效',
                zhHant: '條件斷點已生效',
                en: 'Conditional breakpoint applied',
                fr: 'Point d’arrêt conditionnel appliqué',
                de: 'Bedingter Breakpoint aktiv',
                ja: '条件付きブレークポイントを適用しました',
              ),
      );
    }
  }

  Future<void> _addXhr() async {
    final v = _xhrCtrl.text.trim();
    final ok = await widget.controller.addXhrBreakpoint(v);
    if (!mounted) return;
    if (ok) {
      _xhrCtrl.clear();
      widget.onPersist();
    } else {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '添加 XHR 断点失败',
          zhHant: '新增 XHR 斷點失敗',
          en: 'Failed to add XHR breakpoint',
          fr: 'Échec d’ajout du point d’arrêt XHR',
          de: 'XHR-Breakpoint konnte nicht hinzugefügt werden',
          ja: 'XHR ブレークポイントを追加できませんでした',
        ),
      );
    }
  }

  Future<void> _removeXhr(String s) async {
    final ok = await widget.controller.removeXhrBreakpoint(s);
    if (ok && mounted) widget.onPersist();
  }

  // 把 URL 收成「文件名」级别的短串展示在断点行标题：
  //   https://a.com/foo/bar.js?v=1#L → bar.js
  // 没有路径分量时直接返回原 URL。完整 URL 仍通过 tooltip 展示。
  String _shortUrl(String url) {
    if (url.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      for (var i = segments.length - 1; i >= 0; i--) {
        final s = segments[i];
        if (s.isNotEmpty) return s;
      }
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {
      // 解析失败回落到字符串截断。
    }
    final cleaned = url.split('?').first.split('#').first;
    final slash = cleaned.lastIndexOf('/');
    return slash >= 0 && slash < cleaned.length - 1
        ? cleaned.substring(slash + 1)
        : cleaned;
  }

  Future<void> _setPause(String state) async {
    final ok = await widget.controller.setPauseOnExceptions(state);
    if (!mounted) return;
    if (!ok) {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '设置失败（页面未在调试态）',
          zhHant: '設定失敗（頁面未在偵錯狀態）',
          en: 'Set failed (page not attached)',
          fr: 'Échec du réglage (page non attachée)',
          de: 'Setzen fehlgeschlagen (Seite nicht verbunden)',
          ja: '設定できませんでした（ページ未接続）',
        ),
      );
    } else {
      widget.onPersist();
    }
  }

  Future<void> _toggleEventListener(String evt) async {
    final has = widget.controller.eventListenerBreakpoints.contains(evt);
    final ok = has
        ? await widget.controller.removeEventListenerBreakpoint(evt)
        : await widget.controller.setEventListenerBreakpoint(evt);
    if (!mounted) return;
    if (!ok) {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '操作失败（页面未在调试态）',
          zhHant: '操作失敗（頁面未在偵錯狀態）',
          en: 'Op failed (not attached)',
          fr: 'Échec de l’opération (non attaché)',
          de: 'Aktion fehlgeschlagen (nicht verbunden)',
          ja: '操作できませんでした（未接続）',
        ),
      );
    } else {
      widget.onPersist();
    }
  }

  Future<void> _addDomBp() async {
    final sel = _domSelectorCtrl.text.trim();
    if (sel.isEmpty) return;
    final ok = await widget.controller.addDomBreakpoint(
      selector: sel,
      type: _domType,
    );
    if (!mounted) return;
    if (ok) {
      _domSelectorCtrl.clear();
      widget.onPersist();
    } else {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '添加失败（选择器无匹配或未附加调试器）',
          zhHant: '新增失敗（選擇器無匹配或未附加偵錯器）',
          en: 'Add failed (selector miss / not attached)',
          fr: 'Échec d’ajout (sélecteur absent / non attaché)',
          de: 'Hinzufügen fehlgeschlagen (Selector ohne Treffer / nicht verbunden)',
          ja: '追加できませんでした（セレクタ不一致 / 未接続）',
        ),
      );
    }
  }

  Future<void> _removeDomBp(({String selector, String type}) b) async {
    final ok = await widget.controller.removeDomBreakpoint(
      selector: b.selector,
      type: b.type,
    );
    if (ok && mounted) widget.onPersist();
  }

  Future<void> _toggleCspViolation(String type) async {
    final cur = widget.controller.cspViolationBreakpoints;
    final next = cur.contains(type)
        ? (cur.toSet()..remove(type))
        : (cur.toSet()..add(type));
    final ok = await widget.controller.setCspViolationBreakpoints(next);
    if (!mounted) return;
    if (!ok) {
      showOpenHandErrorSnack(
        context,
        _text(
          zh: '设置失败',
          zhHant: '設定失敗',
          en: 'Set failed',
          fr: 'Échec du réglage',
          de: 'Setzen fehlgeschlagen',
          ja: '設定できませんでした',
        ),
      );
    } else {
      widget.onPersist();
    }
  }

  Future<void> _refreshGlobalListeners() async {
    setState(() => _gListLoading = true);
    final list = await widget.controller.listGlobalEventListeners();
    if (!mounted) return;
    setState(() {
      _gListLoading = false;
      _globalListeners = list;
    });
  }

  Future<void> _stepOver() async {
    await widget.controller.stepOverDebugger();
  }

  Future<void> _stepInto() async {
    await widget.controller.stepIntoDebugger();
  }

  Future<void> _stepOut() async {
    await widget.controller.stepOutDebugger();
  }

  Future<void> _resume() async {
    await widget.controller.resumeDebugger();
  }

  String _eventCategoryLabel(String key) {
    return switch (key) {
      'Mouse' => _text(
        zh: '鼠标',
        zhHant: '滑鼠',
        en: 'Mouse',
        fr: 'Souris',
        de: 'Maus',
        ja: 'マウス',
      ),
      'Keyboard' => _text(
        zh: '键盘',
        zhHant: '鍵盤',
        en: 'Keyboard',
        fr: 'Clavier',
        de: 'Tastatur',
        ja: 'キーボード',
      ),
      'Touch' => _text(
        zh: '触控',
        zhHant: '觸控',
        en: 'Touch',
        fr: 'Tactile',
        de: 'Touch',
        ja: 'タッチ',
      ),
      'Pointer' => _text(
        zh: '指针',
        zhHant: '指標',
        en: 'Pointer',
        fr: 'Pointeur',
        de: 'Pointer',
        ja: 'ポインター',
      ),
      'Control' => _text(
        zh: '控件',
        zhHant: '控制項',
        en: 'Control',
        fr: 'Contrôle',
        de: 'Steuerelemente',
        ja: 'コントロール',
      ),
      'Clipboard' => _text(
        zh: '剪贴板',
        zhHant: '剪貼簿',
        en: 'Clipboard',
        fr: 'Presse-papiers',
        de: 'Zwischenablage',
        ja: 'クリップボード',
      ),
      'DOM Mutation' => _text(
        zh: 'DOM 变更',
        zhHant: 'DOM 變更',
        en: 'DOM Mutation',
        fr: 'Mutation DOM',
        de: 'DOM-Änderung',
        ja: 'DOM 変更',
      ),
      'Timer' => _text(
        zh: '定时器',
        zhHant: '計時器',
        en: 'Timer',
        fr: 'Minuteur',
        de: 'Timer',
        ja: 'タイマー',
      ),
      'Animation' => _text(
        zh: '动画',
        zhHant: '動畫',
        en: 'Animation',
        fr: 'Animation',
        de: 'Animation',
        ja: 'アニメーション',
      ),
      'Load' => _text(
        zh: '加载',
        zhHant: '載入',
        en: 'Load',
        fr: 'Chargement',
        de: 'Laden',
        ja: '読み込み',
      ),
      'Worker' => _text(
        zh: 'Worker',
        zhHant: 'Worker',
        en: 'Worker',
        fr: 'Worker',
        de: 'Worker',
        ja: 'Worker',
      ),
      'XHR' => 'XHR',
      'Drag/Drop' => _text(
        zh: '拖放',
        zhHant: '拖放',
        en: 'Drag/Drop',
        fr: 'Glisser-déposer',
        de: 'Drag-and-drop',
        ja: 'ドラッグ＆ドロップ',
      ),
      _ => key,
    };
  }

  String _lineLabel(int zeroBasedLine) {
    final line = zeroBasedLine + 1;
    return _text(
      zh: '第 $line 行',
      zhHant: '第 $line 行',
      en: 'line $line',
      fr: 'ligne $line',
      de: 'Zeile $line',
      ja: '$line 行目',
    );
  }

  String _addLabel() {
    return _text(
      zh: '添加',
      zhHant: '新增',
      en: 'Add',
      fr: 'Ajouter',
      de: 'Hinzufügen',
      ja: '追加',
    );
  }

  String _noneYetLabel() {
    return _text(
      zh: '尚未添加。',
      zhHant: '尚未新增。',
      en: 'None yet.',
      fr: 'Aucun pour le moment.',
      de: 'Noch keine.',
      ja: 'まだありません。',
    );
  }

  /// 绑定当前语言的行内文本取值；语言切换后随重建自动生效。
  OpenHandLocalizedTextResolver get _text => openHandTextResolver(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
    final sourceBps = widget.controller.userBreakpoints.toList()
      ..sort((a, b) {
        final c = a.url.compareTo(b.url);
        return c != 0 ? c : a.line.compareTo(b.line);
      });
    final xhrBps = widget.controller.xhrBreakpoints.toList()..sort();
    final elBps = widget.controller.eventListenerBreakpoints;
    final domBps = widget.controller.domBreakpoints;
    final cspBps = widget.controller.cspViolationBreakpoints;
    final paused = widget.controller.pausedState;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListView(
        children: [
          // 顶部「执行控制」卡片：暂停/恢复 + Step Over/Into/Out + 状态徽章
          _SectionCard(
            icon: paused == null
                ? Icons.play_circle_outline_rounded
                : Icons.pause_circle_outline_rounded,
            title: paused == null
                ? _text(
                    zh: '执行控制（运行中）',
                    zhHant: '執行控制（執行中）',
                    en: 'Execution (running)',
                    fr: 'Exécution (en cours)',
                    de: 'Ausführung (läuft)',
                    ja: '実行制御（実行中）',
                  )
                : _text(
                    zh: '执行控制（已暂停 · ${paused.reason}）',
                    zhHant: '執行控制（已暫停 · ${paused.reason}）',
                    en: 'Execution (paused · ${paused.reason})',
                    fr: 'Exécution (en pause · ${paused.reason})',
                    de: 'Ausführung (pausiert · ${paused.reason})',
                    ja: '実行制御（一時停止 · ${paused.reason}）',
                  ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: paused == null ? null : _resume,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    _text(
                      zh: '继续',
                      zhHant: '繼續',
                      en: 'Resume',
                      fr: 'Reprendre',
                      de: 'Fortsetzen',
                      ja: '再開',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepOver,
                  icon: const Icon(Icons.redo_rounded, size: 18),
                  label: Text(
                    _text(
                      zh: '单步跳过',
                      zhHant: '單步跳過',
                      en: 'Step over',
                      fr: 'Pas à pas principal',
                      de: 'Step over',
                      ja: 'ステップオーバー',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepInto,
                  icon: const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _text(
                      zh: '单步进入',
                      zhHant: '單步進入',
                      en: 'Step into',
                      fr: 'Entrer',
                      de: 'Step into',
                      ja: 'ステップイン',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepOut,
                  icon: const Icon(
                    Icons.subdirectory_arrow_left_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _text(
                      zh: '单步跳出',
                      zhHant: '單步跳出',
                      en: 'Step out',
                      fr: 'Sortir',
                      de: 'Step out',
                      ja: 'ステップアウト',
                    ),
                  ),
                ),
                if (paused != null && paused.callFrames.isNotEmpty)
                  Tooltip(
                    message:
                        paused.callFrames.first['functionName']?.toString() ??
                        '<anonymous>',
                    child: Chip(
                      avatar: const Icon(Icons.layers_rounded, size: 14),
                      label: Text(
                        '${paused.callFrames.first['functionName'] ?? '<anonymous>'} '
                        '· ${(paused.callFrames.first['location'] as Map?)?['lineNumber'] ?? '?'}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.location_on_rounded,
            title: _text(
              zh: '代码断点',
              zhHant: '程式碼斷點',
              en: 'Source breakpoints',
              fr: 'Points d’arrêt source',
              de: 'Source-Breakpoints',
              ja: 'ソースブレークポイント',
            ),
            child: AnimatedSize(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: kOpenHandSwitchInCurve,
              child: sourceBps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          _text(
                            zh: '到 Sources 面板点击行号下断点。',
                            zhHant: '到 Sources 面板點擊行號設定斷點。',
                            en: 'Toggle breakpoints by clicking line numbers in Sources.',
                            fr: 'Activez les points d’arrêt via les numéros de ligne dans Sources.',
                            de: 'Breakpoints in Sources über Zeilennummern umschalten.',
                            ja: 'Sources で行番号をクリックして切り替えます。',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final b in sourceBps)
                          _BpRow(
                            icon: Icons.circle,
                            iconColor: cs.primary,
                            title: _shortUrl(b.url),
                            subtitle: _lineLabel(b.line),
                            tooltip: b.url,
                            onTap: () => widget.onJumpToSource(b.url, b.line),
                            onDelete: () => _removeSourceBp(b),
                            condition: widget.controller.breakpointCondition(
                              url: b.url,
                              line: b.line,
                            ),
                            onEditCondition: () => _editSourceBpCondition(b),
                          ),
                      ],
                    ),
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.error_outline_rounded,
            title: _text(
              zh: '抛出异常时暂停',
              zhHant: '拋出例外時暫停',
              en: 'Pause on exceptions',
              fr: 'Pause sur exceptions',
              de: 'Bei Ausnahmen pausieren',
              ja: '例外で一時停止',
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'none',
                    label: Text(
                      _text(
                        zh: '关',
                        zhHant: '關',
                        en: 'Off',
                        fr: 'Désactivé',
                        de: 'Aus',
                        ja: 'オフ',
                      ),
                    ),
                    icon: const Icon(Icons.do_disturb_alt_rounded),
                  ),
                  ButtonSegment(
                    value: 'uncaught',
                    label: Text(
                      _text(
                        zh: '仅未捕获',
                        zhHant: '僅未捕獲',
                        en: 'Uncaught only',
                        fr: 'Non interceptées',
                        de: 'Nur ungefangene',
                        ja: '未捕捉のみ',
                      ),
                    ),
                    icon: const Icon(Icons.report_problem_outlined),
                  ),
                  ButtonSegment(
                    value: 'all',
                    label: Text(
                      _text(
                        zh: '全部',
                        zhHant: '全部',
                        en: 'All',
                        fr: 'Toutes',
                        de: 'Alle',
                        ja: 'すべて',
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_rounded),
                  ),
                ],
                selected: {widget.controller.pauseOnExceptions},
                onSelectionChanged: (s) {
                  if (s.isNotEmpty) _setPause(s.first);
                },
              ),
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.cloud_download_outlined,
            title: _text(
              zh: 'XHR / fetch 断点（URL 子串匹配）',
              zhHant: 'XHR / fetch 斷點（URL 子字串匹配）',
              en: 'XHR / fetch breakpoints (URL substring)',
              fr: 'Points XHR / fetch (sous-chaîne URL)',
              de: 'XHR-/fetch-Breakpoints (URL-Teilstring)',
              ja: 'XHR / fetch ブレークポイント（URL 部分一致）',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xhrCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: _text(
                            zh: 'URL 子串（留空 = 拦截全部）',
                            zhHant: 'URL 子字串（留空 = 攔截全部）',
                            en: 'URL substring (empty = all)',
                            fr: 'Sous-chaîne URL (vide = tout)',
                            de: 'URL-Teilstring (leer = alle)',
                            ja: 'URL 部分文字列（空 = すべて）',
                          ),
                        ),
                        onSubmitted: (_) => _addXhr(),
                      ),
                    ),
                    kOpenHandHGap8,
                    FilledButton.icon(
                      onPressed: _addXhr,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(_addLabel()),
                    ),
                  ],
                ),
                kOpenHandGap8,
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: kOpenHandSwitchInCurve,
                  child: xhrBps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _noneYetLabel(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final s in xhrBps)
                              _BpRow(
                                icon: Icons.link_rounded,
                                iconColor: cs.tertiary,
                                title: s.isEmpty
                                    ? _text(
                                        zh: '<全部 XHR>',
                                        zhHant: '<全部 XHR>',
                                        en: '<any XHR>',
                                        fr: '<tout XHR>',
                                        de: '<beliebiger XHR>',
                                        ja: '<すべての XHR>',
                                      )
                                    : s,
                                subtitle: null,
                                tooltip: null,
                                onTap: null,
                                onDelete: () => _removeXhr(s),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.touch_app_outlined,
            title: _text(
              zh: '事件监听断点',
              zhHant: '事件監聽斷點',
              en: 'Event Listener Breakpoints',
              fr: 'Points d’arrêt des écouteurs',
              de: 'Event-Listener-Breakpoints',
              ja: 'イベントリスナーブレークポイント',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in _kEventCategories.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      _eventCategoryLabel(entry.key),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final evt in entry.value)
                        FilterChip(
                          label: Text(
                            evt,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: elBps.contains(evt),
                          onSelected: (_) => _toggleEventListener(evt),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.account_tree_outlined,
            title: _text(
              zh: 'DOM 断点',
              zhHant: 'DOM 斷點',
              en: 'DOM Breakpoints',
              fr: 'Points d’arrêt DOM',
              de: 'DOM-Breakpoints',
              ja: 'DOM ブレークポイント',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _domSelectorCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: _text(
                            zh: 'CSS 选择器（如 #root）',
                            zhHant: 'CSS 選擇器（如 #root）',
                            en: 'CSS selector (e.g. #root)',
                            fr: 'Sélecteur CSS (ex. #root)',
                            de: 'CSS-Selector (z. B. #root)',
                            ja: 'CSS セレクタ（例 #root）',
                          ),
                        ),
                        onSubmitted: (_) => _addDomBp(),
                      ),
                    ),
                    kOpenHandHGap8,
                    WebReverseSelectButton<String>(
                      value: _domType,
                      dense: true,
                      minWidth: 168,
                      tooltip: _text(
                        zh: '选择 DOM 断点类型',
                        zhHant: '選擇 DOM 斷點類型',
                        en: 'Select DOM breakpoint type',
                        fr: 'Choisir le type de point DOM',
                        de: 'DOM-Breakpoint-Typ auswählen',
                        ja: 'DOM ブレークポイント種別を選択',
                      ),
                      options: const [
                        WebReverseSelectOption(
                          value: 'subtree-modified',
                          label: 'subtree-modified',
                        ),
                        WebReverseSelectOption(
                          value: 'attribute-modified',
                          label: 'attribute-modified',
                        ),
                        WebReverseSelectOption(
                          value: 'node-removed',
                          label: 'node-removed',
                        ),
                      ],
                      onChanged: (v) => setState(() => _domType = v),
                    ),
                    kOpenHandHGap8,
                    FilledButton.icon(
                      onPressed: _addDomBp,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(_addLabel()),
                    ),
                  ],
                ),
                kOpenHandGap8,
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: kOpenHandSwitchInCurve,
                  child: domBps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _noneYetLabel(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final b in domBps)
                              _BpRow(
                                icon: Icons.code_rounded,
                                iconColor: cs.secondary,
                                title: b.selector,
                                subtitle: b.type,
                                tooltip: null,
                                onTap: null,
                                onDelete: () => _removeDomBp(b),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.security_outlined,
            title: _text(
              zh: 'CSP 违规断点',
              zhHant: 'CSP 違規斷點',
              en: 'CSP Violation Breakpoints',
              fr: 'Points d’arrêt CSP',
              de: 'CSP-Verstoß-Breakpoints',
              ja: 'CSP 違反ブレークポイント',
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: cspBps.contains('trustedtype-sink-violation'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('trustedtype-sink-violation'),
                  onChanged: (_) =>
                      _toggleCspViolation('trustedtype-sink-violation'),
                ),
                CheckboxListTile(
                  value: cspBps.contains('trustedtype-policy-violation'),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('trustedtype-policy-violation'),
                  onChanged: (_) =>
                      _toggleCspViolation('trustedtype-policy-violation'),
                ),
              ],
            ),
          ),
          kOpenHandGap12,
          _SectionCard(
            icon: Icons.list_alt_rounded,
            title: _text(
              zh: '全局事件监听器（window）',
              zhHant: '全域事件監聽器（window）',
              en: 'Global Listeners (window)',
              fr: 'Écouteurs globaux (window)',
              de: 'Globale Listener (window)',
              ja: 'グローバルリスナー（window）',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _globalListeners == null
                            ? _text(
                                zh: '点击右侧按钮抓取一次。',
                                zhHant: '點擊右側按鈕抓取一次。',
                                en: 'Click to fetch.',
                                fr: 'Cliquez pour récupérer.',
                                de: 'Zum Abrufen klicken.',
                                ja: 'クリックして取得します。',
                              )
                            : _text(
                                zh: '共 ${_globalListeners!.length} 个监听器',
                                zhHant: '共 ${_globalListeners!.length} 個監聽器',
                                en: '${_globalListeners!.length} listeners',
                                fr: '${_globalListeners!.length} écouteurs',
                                de: '${_globalListeners!.length} Listener',
                                ja: '${_globalListeners!.length} 件のリスナー',
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _gListLoading ? null : _refreshGlobalListeners,
                      icon: OpenHandBusyStatusIcon(
                        busy: _gListLoading,
                        icon: Icons.refresh_rounded,
                      ),
                      label: Text(
                        _text(
                          zh: '刷新',
                          zhHant: '重新整理',
                          en: 'Refresh',
                          fr: 'Actualiser',
                          de: 'Aktualisieren',
                          ja: '更新',
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap8,
                if (_globalListeners != null &&
                    _globalListeners!.isNotEmpty) ...[
                  for (final l in _globalListeners!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: cs.tertiary,
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: Text(
                              '${l['type']}'
                              '${l['useCapture'] == true ? ' · capture' : ''}'
                              '${l['passive'] == true ? ' · passive' : ''}'
                              '${l['once'] == true ? ' · once' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            '${l['scriptId'] ?? ''}:${l['lineNumber'] ?? ''}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: webReverseSurfaceCardDecoration(cs, radius: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              kOpenHandHGap8,
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          child,
        ],
      ),
    );
  }
}

class _BpRow extends StatelessWidget {
  const _BpRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onTap,
    required this.onDelete,
    this.onEditCondition,
    this.condition,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  // 条件断点：若提供 onEditCondition 则在删除按钮旁渲染编辑图标，
  // condition 不空时图标用 primary 高亮以提示「该断点已附带条件」。
  final VoidCallback? onEditCondition;
  final String? condition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasCondition = (condition ?? '').isNotEmpty;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 10, color: iconColor),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (hasCondition)
                  // 已设条件：把表达式以小字 + monospace 直接渲染出来，便于
                  // 用户一眼回忆「这个断点为什么只在这个上下文才停」。
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'if (${condition!})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onEditCondition != null)
            IconButton(
              tooltip: hasCondition
                  ? openHandLocalizedText(
                      context,
                      zh: '编辑条件',
                      zhHant: '編輯條件',
                      en: 'Edit condition',
                      fr: 'Modifier la condition',
                      de: 'Bedingung bearbeiten',
                      ja: '条件を編集',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: '添加条件',
                      zhHant: '新增條件',
                      en: 'Add condition',
                      fr: 'Ajouter une condition',
                      de: 'Bedingung hinzufügen',
                      ja: '条件を追加',
                    ),
              icon: Icon(
                hasCondition ? Icons.tune_rounded : Icons.edit_note_rounded,
                size: 16,
                color: hasCondition ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: onEditCondition,
            ),
          IconButton(
            tooltip: openHandDeleteLabel(context),
            icon: Icon(Icons.close_rounded, size: 16, color: cs.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
    Widget content = onTap == null
        ? row
        : InkWell(
            borderRadius: kOpenHandBorderRadius10,
            onTap: onTap,
            child: row,
          );
    if (tooltip != null) {
      content = Tooltip(message: tooltip, child: content);
    }
    return content;
  }
}

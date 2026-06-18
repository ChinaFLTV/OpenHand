// 「断点」独立面板：
//
// 三段式：
//   1) Source breakpoints —— controller.userBreakpoints 列出，每条带「跳到 Sources」+ 删除。
//   2) Pause on exceptions —— 三态 SegmentedButton: 关 / 仅未捕获 / 全部抛出。
//   3) XHR / fetch breakpoints —— 子串匹配的 URL 列表 + 新增输入框 + 删除按钮。
//
// 风格：圆角胶囊 + 220ms easeOutCubic 切换 + Q弹 AnimatedSize/Switcher，
// 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _BreakpointsBody extends StatefulWidget {
  const _BreakpointsBody({
    required this.controller,
    required this.isZh,
    required this.onPersist,
    required this.onJumpToSource,
  });
  final WebReverseSessionController controller;
  final bool isZh;
  final VoidCallback onPersist;
  final void Function(String url, int line) onJumpToSource;

  @override
  State<_BreakpointsBody> createState() => _BreakpointsBodyState();
}

class _BreakpointsBodyState extends State<_BreakpointsBody> {
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

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _removeSourceBp(({String url, int line}) b) async {
    final ok = await widget.controller.removeBreakpointAt(
      url: b.url,
      line: b.line,
    );
    if (!mounted) return;
    if (ok) {
      widget.onPersist();
    } else {
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '取消断点失败' : 'Failed to remove breakpoint',
      );
    }
  }

  // 条件断点编辑器：从行号右侧 ✎ 图标进入。Esc/取消保留原值；保存后调
  // controller.setBreakpointCondition（内部走 remove + setBreakpointByUrl
  // 重建），结果通过 _safeNotify → addListener → setState 刷新 UI。
  Future<void> _editSourceBpCondition(({String url, int line}) b) async {
    final isZh = widget.isZh;
    final existing = widget.controller.breakpointCondition(
      url: b.url,
      line: b.line,
    );
    final ctrl = TextEditingController(text: existing);
    String? value;
    try {
      value = await showAnimatedDialog<String>(
        context: context,
        builder: (dialogContext) {
          return buildOpenHandAlertDialog(
            title: Text(isZh ? '编辑条件断点' : 'Edit conditional breakpoint'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isZh
                        ? '当表达式求值为真时才暂停。留空则改回普通断点。\n'
                              '表达式在断点所在栈帧的作用域内求值。'
                        : 'Pause only when the expression is truthy. Leave empty to revert to a plain breakpoint.\n'
                              'Evaluated in the frame scope where the breakpoint fires.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${b.url}  line ${b.line + 1}',
                    style: Theme.of(dialogContext).textTheme.labelSmall
                        ?.copyWith(
                          fontFamily: 'monospace',
                          color: Theme.of(
                            dialogContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 4,
                    minLines: 2,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: isZh
                          ? '例如：count > 100 && user.id === 42'
                          : 'e.g. count > 100 && user.id === 42',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                label: isZh ? '取消' : 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              OpenHandDialogActionButton.primary(
                label: isZh ? '保存' : 'Save',
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
      OpenHandSnackBar.showError(
        context,
        isZh ? '更新条件断点失败' : 'Failed to update conditional breakpoint',
      );
    } else {
      widget.onPersist();
      OpenHandSnackBar.showSuccess(
        context,
        value.trim().isEmpty
            ? (isZh ? '已转为普通断点' : 'Reverted to plain breakpoint')
            : (isZh ? '条件断点已生效' : 'Conditional breakpoint applied'),
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
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '添加 XHR 断点失败' : 'Failed to add XHR breakpoint',
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
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '设置失败（页面未在调试态）' : 'Set failed (page not attached)',
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
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '操作失败（页面未在调试态）' : 'Op failed (not attached)',
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
      OpenHandSnackBar.showError(
        context,
        widget.isZh
            ? '添加失败（选择器无匹配或未附加调试器）'
            : 'Add failed (selector miss / not attached)',
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
      OpenHandSnackBar.showError(context, widget.isZh ? '设置失败' : 'Set failed');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
                ? (isZh ? '执行控制（运行中）' : 'Execution (running)')
                : (isZh
                      ? '执行控制（已暂停 · ${paused.reason}）'
                      : 'Execution (paused · ${paused.reason})'),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: paused == null ? null : _resume,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(isZh ? '继续' : 'Resume'),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepOver,
                  icon: const Icon(Icons.redo_rounded, size: 18),
                  label: Text(isZh ? '单步跳过' : 'Step over'),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepInto,
                  icon: const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 18,
                  ),
                  label: Text(isZh ? '单步进入' : 'Step into'),
                ),
                OutlinedButton.icon(
                  onPressed: paused == null ? null : _stepOut,
                  icon: const Icon(
                    Icons.subdirectory_arrow_left_rounded,
                    size: 18,
                  ),
                  label: Text(isZh ? '单步跳出' : 'Step out'),
                ),
                if (paused != null && paused.callFrames.isNotEmpty)
                  Tooltip(
                    message:
                        paused.callFrames.first['functionName']?.toString() ??
                        '<anonymous>',
                    child: Chip(
                      avatar: const Icon(Icons.layers_rounded, size: 14),
                      label: Text(
                        '${(paused.callFrames.first['functionName'] ?? '<anonymous>')} '
                        '· ${(paused.callFrames.first['location'] as Map?)?['lineNumber'] ?? '?'}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.location_on_rounded,
            title: isZh ? '代码断点' : 'Source breakpoints',
            child: AnimatedSize(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: _kSwitchInCurve,
              child: sourceBps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          isZh
                              ? '到 Sources 面板点击行号下断点。'
                              : 'Toggle breakpoints by clicking line numbers in Sources.',
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
                            subtitle: 'line ${b.line + 1}',
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.error_outline_rounded,
            title: isZh ? '抛出异常时暂停' : 'Pause on exceptions',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'none',
                    label: Text(isZh ? '关' : 'Off'),
                    icon: const Icon(Icons.do_disturb_alt_rounded),
                  ),
                  ButtonSegment(
                    value: 'uncaught',
                    label: Text(isZh ? '仅未捕获' : 'Uncaught only'),
                    icon: const Icon(Icons.report_problem_outlined),
                  ),
                  ButtonSegment(
                    value: 'all',
                    label: Text(isZh ? '全部' : 'All'),
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.cloud_download_outlined,
            title: isZh
                ? 'XHR / fetch 断点（URL 子串匹配）'
                : 'XHR / fetch breakpoints (URL substring)',
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
                          labelText: isZh
                              ? 'URL 子串（留空 = 拦截全部）'
                              : 'URL substring (empty = all)',
                        ),
                        onSubmitted: (_) => _addXhr(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addXhr,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(isZh ? '添加' : 'Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: _kSwitchInCurve,
                  child: xhrBps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            isZh ? '尚未添加。' : 'None yet.',
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
                                    ? (isZh ? '<全部 XHR>' : '<any XHR>')
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.touch_app_outlined,
            title: isZh ? '事件监听断点' : 'Event Listener Breakpoints',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in _kEventCategories.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      entry.key,
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.account_tree_outlined,
            title: isZh ? 'DOM 断点' : 'DOM Breakpoints',
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
                          labelText: isZh
                              ? 'CSS 选择器（如 #root）'
                              : 'CSS selector (e.g. #root)',
                        ),
                        onSubmitted: (_) => _addDomBp(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _domType,
                      items: const [
                        DropdownMenuItem(
                          value: 'subtree-modified',
                          child: Text('subtree-modified'),
                        ),
                        DropdownMenuItem(
                          value: 'attribute-modified',
                          child: Text('attribute-modified'),
                        ),
                        DropdownMenuItem(
                          value: 'node-removed',
                          child: Text('node-removed'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _domType = v);
                      },
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addDomBp,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(isZh ? '添加' : 'Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: _kSwitchInCurve,
                  child: domBps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            isZh ? '尚未添加。' : 'None yet.',
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.security_outlined,
            title: isZh ? 'CSP 违规断点' : 'CSP Violation Breakpoints',
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
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.list_alt_rounded,
            title: isZh ? '全局事件监听器（window）' : 'Global Listeners (window)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _globalListeners == null
                            ? (isZh ? '点击右侧按钮抓取一次。' : 'Click to fetch.')
                            : (isZh
                                  ? '共 ${_globalListeners!.length} 个监听器'
                                  : '${_globalListeners!.length} listeners'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _gListLoading ? null : _refreshGlobalListeners,
                      icon: _gListLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(isZh ? '刷新' : 'Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                          const SizedBox(width: 8),
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
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(width: 10),
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
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onEditCondition != null)
            IconButton(
              tooltip: hasCondition ? 'Edit condition' : 'Add condition',
              icon: Icon(
                hasCondition ? Icons.tune_rounded : Icons.edit_note_rounded,
                size: 16,
                color: hasCondition ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: onEditCondition,
            ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.close_rounded, size: 16, color: cs.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
    Widget content = onTap == null
        ? row
        : InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: row,
          );
    if (tooltip != null) {
      content = Tooltip(message: tooltip, child: content);
    }
    return content;
  }
}

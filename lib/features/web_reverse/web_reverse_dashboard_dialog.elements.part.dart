// 元素 (Elements / DOM Inspector) 面板
// 左：DOM 树（懒加载子节点，单击选中，双击展开/折叠）
// 右：3 子 tab — Attributes / Computed / Listeners
// 顶部工具栏：刷新根、复制 selector / xpath、在页面里高亮 / 滚动到。
// CDP 调用全部走 [WebReverseSessionController] 上新增的 `dom*` 方法；
// 本面板自己不缓存 DOM 树到 metadata（每次刷新都重读，避免会话不一致）。

part of 'web_reverse_dashboard_dialog.dart';

const Duration _kElementsHighlightDuration = Duration(milliseconds: 1500);

class _ElementsBody extends StatefulWidget {
  const _ElementsBody({required this.controller, required this.reduceMotion});
  final WebReverseSessionController controller;
  final bool reduceMotion;

  @override
  State<_ElementsBody> createState() => _ElementsBodyState();
}

class _ElementsBodyState extends State<_ElementsBody> {
  Map<String, dynamic>? _root;
  bool _loading = false;
  String? _loadError;
  int _documentSerial = 0;
  int _selectionSerial = 0;
  int _highlightSerial = 0;
  Timer? _highlightHideTimer;

  /// nodeId -> 是否已展开。
  final Map<int, bool> _expanded = <int, bool>{};
  final Map<int, int> _expandSerial = <int, int>{};

  /// nodeId -> 节点数据（含 children）。子树懒加载时填充进来。
  final Map<int, Map<String, dynamic>> _byNodeId =
      <int, Map<String, dynamic>>{};

  int? _selectedNodeId;

  // 右侧详情数据
  Map<String, String> _attrs = const <String, String>{};
  List<Map<String, String>> _computed = const <Map<String, String>>[];
  List<Map<String, dynamic>> _listeners = const <Map<String, dynamic>>[];
  bool _loadingDetails = false;
  int _detailsTab = 0; // 0=Attrs 1=Computed 2=Listeners

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocument());
  }

  @override
  void dispose() {
    _documentSerial++;
    _selectionSerial++;
    _clearHighlight();
    super.dispose();
  }

  void _clearHighlight() {
    _highlightSerial++;
    _highlightHideTimer?.cancel();
    _highlightHideTimer = null;
    unawaited(widget.controller.domHideHighlight());
  }

  Future<void> _highlightTemporarily(int nodeId) async {
    final serial = ++_highlightSerial;
    final controller = widget.controller;
    final targetId = controller.currentPageTargetId;
    _highlightHideTimer?.cancel();
    _highlightHideTimer = null;
    await controller.domHighlightNode(nodeId);
    if (!mounted || serial != _highlightSerial) return;
    if (controller.currentPageTargetId != targetId) return;
    _highlightHideTimer = startSafeTimer(_kElementsHighlightDuration, () async {
      _highlightHideTimer = null;
      if (!mounted || serial != _highlightSerial) return;
      if (controller.currentPageTargetId != targetId) return;
      await controller.domHideHighlight();
    });
  }

  Future<void> _loadDocument() async {
    if (!mounted) return;
    final serial = ++_documentSerial;
    _selectionSerial++;
    _clearHighlight();
    final controller = widget.controller;
    final targetId = controller.currentPageTargetId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final root = await controller.domGetDocument();
    if (!mounted || serial != _documentSerial) return;
    if (controller.currentPageTargetId != targetId) {
      setState(() => _loading = false);
      return;
    }
    if (root == null) {
      final loc = AppLocalizations.of(context);
      setState(() {
        _loading = false;
        _loadError =
            loc?.webReverseElementsLoadFailed ??
            'Load failed: browser not running or CDP unavailable';
      });
      return;
    }
    _byNodeId.clear();
    _expanded.clear();
    _expandSerial.clear();
    _indexNode(root);
    setState(() {
      _root = root;
      _loading = false;
    });
  }

  /// 递归把 node 写进 [_byNodeId]，children 一并展开 1 层。
  void _indexNode(Map<String, dynamic> node) {
    final id = node['nodeId'];
    if (id is int) _byNodeId[id] = node;
    final children = node['children'];
    if (children is List) {
      for (final c in children) {
        if (c is Map<String, dynamic>) _indexNode(c);
      }
    }
  }

  Future<void> _toggleExpand(int nodeId) async {
    final isOpen = _expanded[nodeId] ?? false;
    if (isOpen) {
      _expandSerial[nodeId] = (_expandSerial[nodeId] ?? 0) + 1;
      setState(() => _expanded[nodeId] = false);
      return;
    }
    final node = _byNodeId[nodeId];
    final children = node?['children'];
    if (children is! List || children.isEmpty) {
      // 拉一层
      final serial = (_expandSerial[nodeId] ?? 0) + 1;
      _expandSerial[nodeId] = serial;
      final controller = widget.controller;
      final targetId = controller.currentPageTargetId;
      final fresh = await controller.domDescribeNode(nodeId);
      if (!mounted || _expandSerial[nodeId] != serial) return;
      if (controller.currentPageTargetId != targetId) return;
      if (fresh != null) {
        _byNodeId[nodeId] = fresh;
        _indexNode(fresh);
      }
    }
    if (!mounted) return;
    setState(() => _expanded[nodeId] = true);
  }

  Future<void> _select(int nodeId) async {
    final serial = ++_selectionSerial;
    final controller = widget.controller;
    final targetId = controller.currentPageTargetId;
    setState(() {
      _selectedNodeId = nodeId;
      _loadingDetails = true;
    });
    final node = _byNodeId[nodeId];
    final attrs = <String, String>{};
    final attrArr = node?['attributes'];
    if (attrArr is List) {
      for (var i = 0; i + 1 < attrArr.length; i += 2) {
        attrs['${attrArr[i]}'] = '${attrArr[i + 1]}';
      }
    }
    final computed = await controller.domGetComputedStyle(nodeId);
    if (!mounted || serial != _selectionSerial) return;
    if (controller.currentPageTargetId != targetId) {
      setState(() => _loadingDetails = false);
      return;
    }
    final listeners = await controller.domGetEventListeners(nodeId);
    if (!mounted || serial != _selectionSerial) return;
    if (controller.currentPageTargetId != targetId) {
      setState(() => _loadingDetails = false);
      return;
    }
    setState(() {
      _attrs = attrs;
      _computed = computed;
      _listeners = listeners;
      _loadingDetails = false;
    });
    await _highlightTemporarily(nodeId);
  }

  Future<void> _copySelector() async {
    final id = _selectedNodeId;
    if (id == null) return;
    final s = await widget.controller.domCssSelectorForNode(id);
    if (!mounted) return;
    if (s == null) {
      final loc = AppLocalizations.of(context);
      showOpenHandErrorSnack(
        context,
        loc?.webReverseElementsSelectorFailed ?? 'Failed to build selector',
      );
      return;
    }
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: s,
      successBase: loc?.webReverseElementsSelectorCopied ?? 'Selector copied',
      logTag: 'web_reverse_elements_panel',
      logAction: '复制选择器',
      successDuration: const Duration(seconds: 1),
    );
  }

  Future<void> _copyXPath() async {
    final id = _selectedNodeId;
    if (id == null) return;
    final s = await widget.controller.domXPathForNode(id);
    if (!mounted) return;
    if (s == null) {
      final loc = AppLocalizations.of(context);
      showOpenHandErrorSnack(
        context,
        loc?.webReverseElementsXPathFailed ?? 'Failed to build XPath',
      );
      return;
    }
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: s,
      successBase: loc?.webReverseElementsXPathCopied ?? 'XPath copied',
      logTag: 'web_reverse_elements_panel',
      logAction: '复制 XPath',
      successDuration: const Duration(seconds: 1),
    );
  }

  Future<void> _scrollIntoView() async {
    final id = _selectedNodeId;
    if (id == null) return;
    final serial = _selectionSerial;
    await widget.controller.domScrollIntoView(id);
    if (!mounted || serial != _selectionSerial || id != _selectedNodeId) return;
    await _highlightTemporarily(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        _buildToolbar(theme, cs, loc),
        const Divider(height: 1),
        Expanded(
          child: OpenHandContentStateSwitcher(
            // 外层 Expanded 已定高，这里只做淡入淡出。
            animateSize: false,
            stateKey: _loading
                ? 'loading'
                : _loadError != null
                ? 'error'
                : _root == null
                ? 'empty'
                : 'tree',
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.error,
                        ),
                      ),
                    ),
                  )
                : _root == null
                ? const SizedBox()
                : Row(
                    children: [
                      SizedBox(width: 380, child: _buildTree(theme, cs)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildDetails(theme, cs, loc)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final hasSel = _selectedNodeId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Tooltip(
            message: loc?.webReverseElementsReloadDom ?? 'Reload DOM root',
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: _loading ? null : _loadDocument,
            ),
          ),
          kOpenHandHGap4,
          OutlinedButton.icon(
            onPressed: hasSel ? _copySelector : null,
            icon: const Icon(Icons.link_rounded, size: 14),
            label: Text(loc?.webReverseElementsCopySelector ?? 'Copy selector'),
          ),
          kOpenHandHGap6,
          OutlinedButton.icon(
            onPressed: hasSel ? _copyXPath : null,
            icon: const Icon(Icons.alt_route_rounded, size: 14),
            label: Text(loc?.webReverseElementsCopyXPath ?? 'Copy XPath'),
          ),
          kOpenHandHGap6,
          OutlinedButton.icon(
            onPressed: hasSel ? _scrollIntoView : null,
            icon: const Icon(Icons.center_focus_strong_rounded, size: 14),
            label: Text(
              loc?.webReverseElementsScrollIntoView ?? 'Scroll into view',
            ),
          ),
          const Spacer(),
          if (_selectedNodeId != null)
            Text(
              'nodeId=${_selectedNodeId!}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: kOpenHandMonospaceFontFamily,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  // ─── 左：DOM 树 ─────────────────────────────────────────────────────
  Widget _buildTree(ThemeData theme, ColorScheme cs) {
    final root = _root;
    if (root == null) return const SizedBox();
    final rows = <_TreeRow>[];
    _flatten(root, 0, rows);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (_, i) => _buildTreeRow(theme, cs, rows[i]),
    );
  }

  void _flatten(Map<String, dynamic> node, int depth, List<_TreeRow> out) {
    final id = node['nodeId'];
    if (id is! int) return;
    final type = node['nodeType'] as int? ?? 1;
    if (type != 1 && type != 9) {
      // 仅显示 element / document，跳过 text/comment（保留信息但不滚屏）
      // 也跳过 attribute/cdata 之类。
      // text 节点用一行折叠在父节点旁更紧凑——这里简化：直接不显示。
      return;
    }
    out.add(_TreeRow(node: node, depth: depth));
    final open = _expanded[id] ?? false;
    if (!open) return;
    final children = node['children'];
    if (children is List) {
      for (final c in children) {
        if (c is Map<String, dynamic>) _flatten(c, depth + 1, out);
      }
    }
  }

  Widget _buildTreeRow(ThemeData theme, ColorScheme cs, _TreeRow row) {
    final node = row.node;
    final id = node['nodeId'] as int;
    final selected = id == _selectedNodeId;
    final isOpen = _expanded[id] ?? false;
    final childCount = node['childNodeCount'] as int? ?? 0;
    final hasChildren = childCount > 0;
    final localName = (node['localName'] as String?) ?? '';
    final nodeName = (node['nodeName'] as String?) ?? '';
    final tag = localName.isNotEmpty ? localName : nodeName.toLowerCase();
    // 提取 id / class 属性显示
    String idAttr = '';
    String classAttr = '';
    final attrArr = node['attributes'];
    if (attrArr is List) {
      for (var i = 0; i + 1 < attrArr.length; i += 2) {
        final k = '${attrArr[i]}';
        final v = '${attrArr[i + 1]}';
        if (k == 'id') idAttr = v;
        if (k == 'class') classAttr = v;
      }
    }
    return InkWell(
      onTap: () => _select(id),
      child: AnimatedContainer(
        duration: widget.reduceMotion ? Duration.zero : kOpenHandMotion140,
        curve: kOpenHandSwitchInCurve,
        color: selected ? cs.primary.withValues(alpha: 0.12) : null,
        padding: EdgeInsets.fromLTRB(8.0 + row.depth * 14, 2, 8, 2),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: hasChildren
                  ? InkResponse(
                      radius: 12,
                      onTap: () => _toggleExpand(id),
                      child: Icon(
                        isOpen
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : const SizedBox(),
            ),
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                  children: [
                    TextSpan(
                      text: '<$tag',
                      style: TextStyle(color: cs.tertiary),
                    ),
                    if (idAttr.isNotEmpty)
                      TextSpan(
                        text: ' id="$idAttr"',
                        style: TextStyle(color: cs.primary),
                      ),
                    if (classAttr.isNotEmpty)
                      TextSpan(
                        text: ' class="$classAttr"',
                        style: TextStyle(color: cs.secondary),
                      ),
                    TextSpan(
                      text: hasChildren && !isOpen ? '>…</$tag>' : '>',
                      style: TextStyle(color: cs.tertiary),
                    ),
                  ],
                ),
              ),
            ),
            if (hasChildren)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '$childCount',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 右：详情 ───────────────────────────────────────────────────────
  Widget _buildDetails(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    if (_selectedNodeId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            loc?.webReverseElementsPickElement ??
                'Pick an element from the tree',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              kOpenHandHGap10,
              _subTabBtn(
                theme,
                cs,
                0,
                loc?.webReverseElementsAttrsTab(_attrs.length) ??
                    'Attrs (${_attrs.length})',
              ),
              _subTabBtn(
                theme,
                cs,
                1,
                loc?.webReverseElementsComputedTab(_computed.length) ??
                    'Computed (${_computed.length})',
              ),
              _subTabBtn(
                theme,
                cs,
                2,
                loc?.webReverseElementsListenersTab(_listeners.length) ??
                    'Listeners (${_listeners.length})',
              ),
              const Spacer(),
              OpenHandInlineRevealSwitcher(
                presentKey: const ValueKey<String>('elements-loading'),
                child: _loadingDetails
                    ? const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: widget.reduceMotion ? Duration.zero : kOpenHandMotion180,
            switchInCurve: kOpenHandSwitchInCurve,
            child: switch (_detailsTab) {
              0 => _attrsView(theme, cs, loc),
              1 => _computedView(theme, cs, loc),
              _ => _listenersView(theme, cs, loc),
            },
          ),
        ),
      ],
    );
  }

  Widget _subTabBtn(ThemeData theme, ColorScheme cs, int idx, String label) {
    final on = _detailsTab == idx;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        onPressed: () => setState(() => _detailsTab = idx),
        style: TextButton.styleFrom(
          foregroundColor: on ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: on ? cs.primary.withValues(alpha: 0.1) : null,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _attrsView(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    if (_attrs.isEmpty) {
      return OpenHandInlineEmptyState(
        key: const ValueKey('attrs-empty'),
        message: loc?.webReverseElementsNoAttrs ?? 'No attributes',
        dense: true,
      );
    }
    final entries = _attrs.entries.toList();
    return ListView.builder(
      key: const ValueKey('attrs'),
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
              ),
              children: [
                TextSpan(
                  text: e.key,
                  style: TextStyle(color: cs.primary),
                ),
                const TextSpan(text: '="'),
                TextSpan(
                  text: e.value,
                  style: TextStyle(color: cs.onSurface),
                ),
                const TextSpan(text: '"'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _computedView(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    if (_computed.isEmpty) {
      return OpenHandInlineEmptyState(
        key: const ValueKey('comp-empty'),
        message: loc?.webReverseElementsNoComputed ?? 'No computed style',
        dense: true,
      );
    }
    return ListView.builder(
      key: const ValueKey('computed'),
      padding: const EdgeInsets.all(12),
      itemCount: _computed.length,
      itemBuilder: (_, i) {
        final e = _computed[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
              children: [
                TextSpan(
                  text: '${e['name']}: ',
                  style: TextStyle(color: cs.primary),
                ),
                TextSpan(
                  text: '${e['value']};',
                  style: TextStyle(color: cs.onSurface),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listenersView(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    if (_listeners.isEmpty) {
      return OpenHandInlineEmptyState(
        key: const ValueKey('listen-empty'),
        message: loc?.webReverseElementsNoListeners ?? 'No event listeners',
        dense: true,
      );
    }
    return ListView.builder(
      key: const ValueKey('listeners'),
      padding: const EdgeInsets.all(12),
      itemCount: _listeners.length,
      itemBuilder: (_, i) {
        final l = _listeners[i];
        final type = '${l['type'] ?? ''}';
        final useCapture = l['useCapture'] == true;
        final passive = l['passive'] == true;
        final once = l['once'] == true;
        final src =
            '${l['scriptId'] ?? ''}:'
            '${l['lineNumber'] ?? 0}:${l['columnNumber'] ?? 0}';
        final handler = l['handler'];
        final desc = handler is Map ? '${handler['description'] ?? ''}' : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: kOpenHandBorderRadius6,
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                  if (useCapture) _flag('capture', cs),
                  if (passive) _flag('passive', cs),
                  if (once) _flag('once', cs),
                  const Spacer(),
                  SelectableText(
                    src,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SelectableText(
                    desc,
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _flag(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: 0.12),
        borderRadius: kOpenHandBorderRadius4,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.tertiary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _TreeRow {
  const _TreeRow({required this.node, required this.depth});
  final Map<String, dynamic> node;
  final int depth;
}

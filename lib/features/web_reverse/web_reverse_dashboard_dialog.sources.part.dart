part of 'web_reverse_dashboard_dialog.dart';

/// Sources tab：列出 page 已 parse 的所有 JS 脚本（来自 CDP `Debugger.scriptParsed`），
/// 点开任一脚本 → 调 `Debugger.getScriptSource` 拉源码 → 提供"原样 / 美化"切换 +
/// 行号 + 简易行点击下断点（`Debugger.setBreakpointByUrl`）。
///
/// 此版仅做"看 + 下断点"两件事；命中断点后的 Step Over / 作用域回显是更大的工程，
/// 用户可点"打开官方 DevTools"按钮走 Chrome 自带 inspector。
class _SourcesPanel extends StatefulWidget {
  const _SourcesPanel({
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

class _SourcesPanelState extends State<_SourcesPanel> {
  bool _enabling = true;
  String? _selectedId;
  String? _source;
  bool _prettify = false;
  String _filter = '';
  // breakpointId 索引：sourceLine → breakpointId，便于二次点击同行取消。
  final Map<int, String> _bpAtLine = <int, String>{};
  // ── LSP（可选）：用户在「LSP」chip 里手动启用。typescript-language-server
  // 默认按当前选中脚本的 URL 作为 documentUri 喂给 server；hover/goto def
  // 直接复用面板内文本坐标。
  final WebReverseLspClient _lsp = WebReverseLspClient();
  bool _lspEnabled = false;
  String? _lastSentUri;

  // 2026-05-24 — Stage F 深化：自动 hover + 行尾浮窗 + 跳转定义滚动。
  // _hoverDebounce 在用户停留 300ms 后才触发 LSP hover，避免每个鼠标
  // 移动事件都打 server 一次。_hoverLine / _hoverColumn / _hoverMarkdown
  // 联动 _SourceHoverBubble 在行尾贴一张浮窗显示 markdown。
  Timer? _hoverDebounce;
  int? _hoverLine;
  String? _hoverMarkdown;
  bool _hoverLoading = false;
  // 高亮命中行：goto-definition / 全局搜索都会写入；2 秒后自动消逝。
  int? _highlightedLine;
  Timer? _highlightTimer;
  // 滚到目标行需要 ScrollablePositionedList 暴露的精确 jumpTo；这里用
  // 手动布局：每行高度由 _kSourceLineHeight 估算，控制 ScrollController
  // 滚到 lineIndex * 行高即可。
  static const double _kSourceLineHeight = 19.5;
  final ScrollController _sourceScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _hoverDebounce?.cancel();
    _highlightTimer?.cancel();
    _sourceScroll.dispose();
    _lsp.stop();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await widget.controller.enableDebugger();
    if (!mounted) return;
    setState(() => _enabling = false);
  }

  /// 用户在 chip 上点击启用 LSP：拉起子进程，握手成功后把当前选中脚本
  /// 推给 server。失败时 chip 自动回到禁用状态并 SnackBar 提示。
  Future<void> _toggleLsp() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    if (_lspEnabled) {
      await _lsp.stop();
      setState(() => _lspEnabled = false);
      return;
    }
    setState(() => _lspEnabled = true);
    final ok = await _lsp.start();
    if (!mounted) return;
    if (!ok) {
      setState(() => _lspEnabled = false);
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh
            ? 'LSP 启动失败：${_lsp.lastError ?? "请安装 typescript-language-server"}'
            : 'LSP failed: ${_lsp.lastError ?? "install typescript-language-server"}',
      );
      return;
    }
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      isZh ? 'LSP 已就绪' : 'LSP ready',
      duration: const Duration(seconds: 1),
    );
    await _pushCurrentToLsp();
  }

  Future<void> _pushCurrentToLsp() async {
    if (!_lspEnabled || _lsp.status != WebReverseLspStatus.ready) return;
    final src = _source;
    final id = _selectedId;
    if (src == null || id == null) return;
    final url = widget.controller.parsedScripts[id]?.url ?? '';
    final uri = _toLspUri(url);
    final content =
        _prettify ? WebReverseSessionController.prettifyJs(src) : src;
    await _lsp.openOrChange(
      uri: uri,
      languageId: _languageIdFor(url),
      text: content,
    );
    _lastSentUri = uri;
  }

  String _toLspUri(String url) {
    if (url.startsWith('file://')) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // 把远端 URL 映射成虚拟 untitled scheme，供 ts-server 把所有内容当
      // 单文件分析。其实 ts-server 接受 file:// 之外的 scheme，但有些 server
      // 依赖 file:// 才做诊断 —— 这里走 untitled 兜底足够支撑 hover/goto。
      return 'untitled:${Uri.encodeComponent(url)}';
    }
    return 'untitled:${Uri.encodeComponent(url.isEmpty ? 'inline' : url)}';
  }

  String _languageIdFor(String url) {
    final l = url.toLowerCase();
    if (l.endsWith('.ts') || l.endsWith('.tsx')) return 'typescript';
    if (l.endsWith('.jsx')) return 'javascriptreact';
    return 'javascript';
  }

  /// 鼠标在某一行上悬停时调度：300ms 内不触发新 hover，超过则发起 LSP
  /// 请求并把结果写到 _hoverMarkdown 让 _SourceHoverBubble 渲染贴在行尾。
  void _scheduleAutoHover(int line, int column, String text) {
    if (!_lspEnabled || _lsp.status != WebReverseLspStatus.ready) return;
    _hoverDebounce?.cancel();
    _hoverDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || !_lspEnabled) return;
      if (_lastSentUri == null) await _pushCurrentToLsp();
      final uri = _lastSentUri;
      if (uri == null || !mounted) return;
      setState(() {
        _hoverLine = line;
        _hoverLoading = true;
        _hoverMarkdown = null;
      });
      final md = await _lsp.hover(uri, line, column);
      if (!mounted) return;
      // 如果光标已经移开（_hoverLine 不是当前 line），丢弃过期结果。
      if (_hoverLine != line) return;
      setState(() {
        _hoverMarkdown = md;
        _hoverLoading = false;
      });
    });
  }

  void _clearAutoHover() {
    _hoverDebounce?.cancel();
    if (_hoverLine != null || _hoverMarkdown != null || _hoverLoading) {
      setState(() {
        _hoverLine = null;
        _hoverMarkdown = null;
        _hoverLoading = false;
      });
    }
  }

  /// 跳转到目标行：ScrollController.animateTo(lineIndex * 行高)，并把
  /// 高亮带写到 _highlightedLine 让对应行底色亮起 2s 后回收。
  void _scrollToLine(int line) {
    if (!_sourceScroll.hasClients) return;
    final target = (line * _kSourceLineHeight - 80).clamp(
      0.0,
      _sourceScroll.position.maxScrollExtent,
    );
    _sourceScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _highlightTimer?.cancel();
    setState(() => _highlightedLine = line);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _highlightedLine = null);
    });
  }

  /// 估算鼠标 X 坐标对应的列号：用 TextPainter 的 monospace 度量。
  /// 行内文本起点（行号 + 间距）= 36 + 6 + 12 = 54 px。
  int _estimateColumn(double localX, String line) {
    final span = TextSpan(
      text: line,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    if (tp.width <= 0 || line.isEmpty) return 0;
    // 行内偏移 = localX - 行号宽 (54 px 左 padding 含)。负值 clamp 到 0。
    final offset = (localX - 54).clamp(0.0, tp.width);
    final pos = tp.getPositionForOffset(Offset(offset, 5));
    return pos.offset.clamp(0, line.length);
  }

  Future<void> _onLineSecondaryTap(
    TapDownDetails details,
    int line,
    String text,
  ) async {
    final col = _estimateColumn(details.localPosition.dx, text);
    final pos = details.globalPosition;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          value: 'hover',
          child: Text(widget.isZh ? '查看 hover' : 'Hover'),
        ),
        PopupMenuItem(
          value: 'def',
          child: Text(widget.isZh ? '跳转定义' : 'Go to definition'),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Text(widget.isZh ? '重命名…' : 'Rename…'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'hover') await _showHover(line, col);
    if (selected == 'def') await _gotoDefinition(line, col);
    if (selected == 'rename') await _renameAt(line, col);
  }

  Future<void> _onLineLongPress(int line, String text) async {
    // 长按默认中点位置查询 hover。
    await _showHover(line, (text.length / 2).floor());
  }

  Future<void> _showHover(int line, int col) async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    final md = await _lsp.hover(uri, line, col);
    if (!mounted) return;
    if (md == null || md.isEmpty) {
      OpenHandSnackBar.showInfoOn(
        context,
        messenger,
        isZh ? '该位置无 hover 信息' : 'No hover info',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? 'LSP Hover' : 'LSP Hover'),
        content: SizedBox(
          width: 560,
          child: SelectableText(
            md,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isZh ? '关闭' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _gotoDefinition(int line, int col) async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    final r = await _lsp.definition(uri, line, col);
    if (!mounted) return;
    if (r == null) {
      OpenHandSnackBar.showInfoOn(
        context,
        messenger,
        isZh ? '未找到定义' : 'No definition found',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    // 如果定义还在同一份文档（典型场景：当前脚本内的函数 / 变量），
    // 直接 ScrollController.animateTo 滚到目标行 + 高亮 2 秒。否则
    // SnackBar 提示位置（跨文件需要 user 自行打开外部 IDE）。
    if (r.uri == uri) {
      _scrollToLine(r.line);
    } else {
      OpenHandSnackBar.showInfoOn(
        context,
        messenger,
        isZh
            ? '定义位置：${r.uri} 第 ${r.line + 1} 行'
            : 'Defined at ${r.uri} L${r.line + 1}',
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _renameAt(int line, int col) async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '重命名为' : 'Rename to'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: Text(isZh ? '确定' : 'OK'),
          ),
        ],
      ),
    );
    if (!mounted || newName == null || newName.isEmpty) return;
    final edit = await _lsp.rename(uri, line, col, newName);
    if (!mounted) return;
    if (edit == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '重命名失败（LSP 未返回 edit）' : 'Rename failed',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final changes = edit['changes'];
    final docChanges = edit['documentChanges'];
    final summary = changes is Map
        ? '${changes.length} files'
        : (docChanges is List ? '${docChanges.length} changes' : 'edit');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isZh ? '重命名结果（仅查看）' : 'Rename result (read-only)'),
        content: SizedBox(
          width: 600,
          child: SelectableText(
            isZh
                ? '收到 LSP edit：$summary\n\n（当前面板只展示分析结果，未自动改源码；'
                    '如需落盘请走外部 IDE。）\n\n${const JsonEncoder.withIndent('  ').convert(edit)}'
                : 'LSP returned edit: $summary\n\n(Read-only preview.)\n\n${const JsonEncoder.withIndent('  ').convert(edit)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isZh ? '关闭' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectScript(String id) async {
    setState(() {
      _selectedId = id;
      _source = null;
      _bpAtLine.clear();
    });
    final src = await widget.controller.getScriptSource(id);
    if (!mounted) return;
    setState(() => _source = src);
    await _pushCurrentToLsp();
  }

  Future<void> _toggleBreakpoint(int lineIdx) async {
    final id = _selectedId;
    if (id == null) return;
    final url = widget.controller.parsedScripts[id]?.url;
    if (url == null || url.isEmpty) return;
    final existing = _bpAtLine[lineIdx];
    final messenger = ScaffoldMessenger.of(context);
    if (existing != null) {
      final ok = await widget.controller.removeBreakpoint(existing);
      if (!mounted) return;
      if (ok) {
        setState(() => _bpAtLine.remove(lineIdx));
        context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>()
            ?.persistBreakpoints();
      } else {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          widget.isZh ? '取消断点失败' : 'Remove failed',
          duration: const Duration(seconds: 2),
        );
      }
    } else {
      final bp = await widget.controller.setBreakpointByUrl(
        url: url,
        lineNumber: lineIdx,
      );
      if (!mounted) return;
      if (bp != null) {
        setState(() => _bpAtLine[lineIdx] = bp);
        context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>()
            ?.persistBreakpoints();
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          widget.isZh ? '已下断点' : 'Breakpoint set',
          duration: const Duration(seconds: 1),
        );
      } else {
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          widget.isZh ? '下断点失败（可能 url 不可达）' : 'Set failed',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _showGlobalCodeSearch() async {
    final isZh = widget.isZh;
    final result = await showDialog<({String scriptId, int line})>(
      context: context,
      builder: (_) => _SourcesGlobalSearchDialog(
        controller: widget.controller,
        isZh: isZh,
      ),
    );
    if (result == null || !mounted) return;
    await _selectScript(result.scriptId);
    if (!mounted) return;
    // 等列表 build 一帧后再 scroll，确保 ScrollController 已 attach。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToLine(result.line);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final scripts = widget.controller.parsedScripts;
    final filteredIds = scripts.keys
        .where((id) {
          final url = scripts[id]?.url ?? '';
          return _filter.isEmpty ||
              url.toLowerCase().contains(_filter.toLowerCase());
        })
        .toList(growable: false)
      ..sort((a, b) =>
          (scripts[a]?.url ?? '').compareTo(scripts[b]?.url ?? ''));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: isZh ? '搜索脚本 URL…' : 'Search script URL…',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 16),
                          border: const OutlineInputBorder(),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        onChanged: (v) => setState(() => _filter = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: isZh ? '跨脚本搜索代码' : 'Search code across scripts',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      onPressed: _showGlobalCodeSearch,
                      icon: const Icon(Icons.travel_explore_rounded),
                    ),
                  ],
                ),
              ),
              if (_enabling)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_enabling)
                Expanded(
                  child: filteredIds.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              isZh
                                  ? '尚未捕获脚本。\n刷新页面或交互后此处会更新。'
                                  : 'No scripts captured yet.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredIds.length,
                          itemBuilder: (_, idx) {
                            final id = filteredIds[idx];
                            final url = scripts[id]?.url ?? '';
                            final selected = id == _selectedId;
                            return Material(
                              color: selected
                                  ? cs.primaryContainer
                                  : Colors.transparent,
                              child: InkWell(
                                onTap: () => _selectScript(id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    _shortenUrl(url),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: selected
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: _selectedId == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      isZh
                          ? '从左侧选择脚本查看源码 / 下断点。\n\n点击任意行的左侧行号即可下断点；'
                              '命中后浏览器会自动暂停，可在原生 DevTools 中调试。'
                          : 'Pick a script on the left to view its source.\n\n'
                              'Click any line number to toggle a breakpoint.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : _buildSourceView(theme, cs, isZh),
        ),
      ],
    );
  }

  Widget _buildSourceView(ThemeData theme, ColorScheme cs, bool isZh) {
    final raw = _source;
    final url = widget.controller.parsedScripts[_selectedId]?.url ?? '';
    if (raw == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final source =
        _prettify ? WebReverseSessionController.prettifyJs(raw) : raw;
    final lines = source.split('\n');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_prettify
                    ? (isZh ? '已美化' : 'Pretty')
                    : (isZh ? '原样' : 'Raw')),
                selected: _prettify,
                onSelected: (v) {
                  setState(() => _prettify = v);
                  _pushCurrentToLsp();
                },
              ),
              const SizedBox(width: 6),
              FilterChip(
                avatar: Icon(
                  _lsp.status == WebReverseLspStatus.ready
                      ? Icons.bolt_rounded
                      : Icons.bolt_outlined,
                  size: 16,
                  color: _lsp.status == WebReverseLspStatus.ready
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                label: Text(_lspEnabled
                    ? (isZh ? 'LSP 已开' : 'LSP on')
                    : (isZh ? 'LSP' : 'LSP')),
                selected: _lspEnabled,
                onSelected: (_) => _toggleLsp(),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isZh ? '复制源码' : 'Copy source',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: source));
                  if (!mounted) return;
                  OpenHandSnackBar.showSuccess(
                    context,
                    isZh ? '已复制' : 'Copied',
                    duration: const Duration(seconds: 1),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: isZh ? '继续运行（Resume）' : 'Resume',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                onPressed: widget.controller.resumeDebugger,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: Container(
            color: cs.surfaceContainerHigh,
            child: ListView.builder(
              controller: _sourceScroll,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lines.length,
              itemBuilder: (_, idx) {
                final hasBp = _bpAtLine.containsKey(idx);
                final isHighlighted = _highlightedLine == idx;
                final isHovered = _hoverLine == idx && _lspEnabled;
                return MouseRegion(
                  onHover: _lspEnabled
                      ? (event) {
                          // 用 TextPainter 估算列号，传给 LSP hover。
                          final col = _estimateColumn(
                            event.localPosition.dx,
                            lines[idx],
                          );
                          _scheduleAutoHover(idx, col, lines[idx]);
                        }
                      : null,
                  onExit: _lspEnabled ? (_) => _clearAutoHover() : null,
                  child: InkWell(
                    onTap: () => _toggleBreakpoint(idx),
                    onSecondaryTapDown: _lspEnabled
                        ? (d) => _onLineSecondaryTap(d, idx, lines[idx])
                        : null,
                    onLongPress: _lspEnabled
                        ? () => _onLineLongPress(idx, lines[idx])
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      color: isHighlighted
                          ? cs.tertiaryContainer.withValues(alpha: 0.5)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 36,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Text(
                                  '${idx + 1}',
                                  style:
                                      theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: cs.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                                if (hasBp)
                                  Positioned(
                                    right: 4,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: cs.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SelectableText(
                                  lines[idx].isEmpty ? ' ' : lines[idx],
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: cs.onSurface,
                                  ),
                                ),
                                // 行尾自动 hover 浮窗：贴在当前行右侧；
                                // 内容为 LSP 返回的 markdown，超过 240 字
                                // 截断，点击鼠标移走自动消失。
                                if (isHovered &&
                                    (_hoverLoading ||
                                        (_hoverMarkdown != null &&
                                            _hoverMarkdown!.isNotEmpty)))
                                  Positioned(
                                    left: _estimateLineWidth(lines[idx]) + 12,
                                    top: -2,
                                    child: _SourceHoverBubble(
                                      markdown: _hoverMarkdown,
                                      loading: _hoverLoading,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 估算指定行渲染宽度，让 _SourceHoverBubble 紧贴行尾出现。
  double _estimateLineWidth(String line) {
    if (line.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  String _shortenUrl(String url) {
    const maxLen = 64;
    if (url.length <= maxLen) return url;
    final tail = url.length - maxLen + 3;
    return '...${url.substring(tail)}';
  }
}


/// 跨脚本代码搜索对话框：输入关键字 → controller.searchScriptsGlobal
/// 拉取所有 parsedScripts 的源码逐行 grep；命中点列表点击即关闭对话框
/// 把 (scriptId, line) 返回给 _SourcesPanelState 跳转 + 高亮。
class _SourcesGlobalSearchDialog extends StatefulWidget {
  const _SourcesGlobalSearchDialog({
    required this.controller,
    required this.isZh,
  });

  final WebReverseSessionController controller;
  final bool isZh;

  @override
  State<_SourcesGlobalSearchDialog> createState() =>
      _SourcesGlobalSearchDialogState();
}

class _SourcesGlobalSearchDialogState
    extends State<_SourcesGlobalSearchDialog> {
  final TextEditingController _qCtrl = TextEditingController();
  bool _searching = false;
  List<({String scriptId, String url, int line, String preview})> _hits =
      const [];

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _qCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final hits = await widget.controller.searchScriptsGlobal(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _hits = hits;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.travel_explore_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _qCtrl,
                      autofocus: true,
                      onSubmitted: (_) => _run(),
                      decoration: InputDecoration(
                        hintText: isZh
                            ? '在所有已加载脚本里搜索…'
                            : 'Search across loaded scripts…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _searching ? null : _run,
                    icon: Icon(
                      _searching
                          ? Icons.hourglass_top_rounded
                          : Icons.search_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _searching
                          ? (isZh ? '搜索中…' : 'Searching…')
                          : (isZh ? '搜索' : 'Search'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searching
                            ? (isZh ? '搜索中…' : 'Searching…')
                            : (isZh
                                ? '输入关键字后按回车或点击搜索；命中按行展示，点击即跳转。'
                                : 'Type a query and press Enter; click a hit to jump.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _hits.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final h = _hits[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            h.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            'L${h.line + 1}: ${h.preview}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(
                            (scriptId: h.scriptId, line: h.line),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isZh
                        ? '命中 ${_hits.length} 条（上限 200）'
                        : '${_hits.length} hits (cap 200)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(isZh ? '关闭' : 'Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// LSP hover 浮窗：贴在当前悬停行的行尾。鼠标移开 → MouseRegion.onExit
/// 触发 _clearAutoHover 让父组件 setState 把它销毁。Loading 状态下显示
/// 微缩进度圈，避免冷启动时窗口"瞬时空白"。markdown 直接 SelectableText
/// 渲染（不引入 markdown 渲染器以保持轻量）。
class _SourceHoverBubble extends StatelessWidget {
  const _SourceHoverBubble({required this.markdown, required this.loading});

  final String? markdown;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = markdown == null
        ? null
        : (markdown!.length > 360
            ? '${markdown!.substring(0, 360)}…'
            : markdown!);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: loading
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LSP…',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                )
              : SelectableText(
                  preview ?? '',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
        ),
      ),
    );
  }
}

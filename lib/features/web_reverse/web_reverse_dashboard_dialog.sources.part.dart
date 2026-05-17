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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await widget.controller.enableDebugger();
    if (!mounted) return;
    setState(() => _enabling = false);
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
                onSelected: (v) => setState(() => _prettify = v),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isZh ? '复制源码' : 'Copy source',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: source));
                  if (!mounted) return;
                  OpenHandSnackBar.showSuccess(
                    context,
                    isZh ? '已复制' : 'Copied',
                    duration: const Duration(seconds: 1),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
              IconButton(
                tooltip: isZh ? '继续运行（Resume）' : 'Resume',
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lines.length,
              itemBuilder: (_, idx) {
                final hasBp = _bpAtLine.containsKey(idx);
                return InkWell(
                  onTap: () => _toggleBreakpoint(idx),
                  child: Padding(
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
                                style: theme.textTheme.labelSmall?.copyWith(
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
                          child: SelectableText(
                            lines[idx].isEmpty ? ' ' : lines[idx],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.5,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
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

  String _shortenUrl(String url) {
    const maxLen = 64;
    if (url.length <= maxLen) return url;
    final tail = url.length - maxLen + 3;
    return '...${url.substring(tail)}';
  }
}

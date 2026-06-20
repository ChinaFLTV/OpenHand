part of 'web_reverse_dashboard_dialog.dart';

/// Sources tab：列出 page 已 parse 的所有 JS 脚本（来自 CDP `Debugger.scriptParsed`），
/// 点开任一脚本 → 调 `Debugger.getScriptSource` 拉源码 → 提供"原样 / 美化"切换 +
/// 行号 + 简易行点击下断点（`Debugger.setBreakpointByUrl`）。
///
/// 此版仅做"看 + 下断点"两件事；命中断点后的 Step Over / 作用域回显是更大的工程，
/// 用户可点"打开官方 DevTools"按钮走 Chrome 自带 inspector。
class _SourcesPanel extends StatefulWidget {
  const _SourcesPanel({
    super.key,
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
  static const double _kDebuggerSideRailWidth = 300;
  static const double _kDebuggerSideRailStackBreakpoint = 680;
  static const double _kDebuggerSideRailStackHeight = 220;
  final ScrollController _sourceScroll = ScrollController();

  // ── Slice 3: Source Map ──
  // 当前选中脚本的 source map（懒加载，失败/无 map 时为 null）。
  WebReverseSourceMapInfo? _sourceMap;
  // 是否正在抓 map，决定 chip 是否显示进度。
  bool _sourceMapLoading = false;
  // 当前在源码视图里展示的原始源 index；-1 表示还在看压缩源。
  int _originalSourceIndex = -1;
  // 是否优先展示原始源（即使 sourcesContent[index] 为 null 也按 inline
  // 占位写「未内联到 map 的源」）。
  bool get _viewingOriginal => _originalSourceIndex >= 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    widget.controller.addListener(_onCtrlChanged);
    // 2026-05-19 — Cmd+P / Ctrl+P 全局快速打开脚本/跳行（类 VSCode/Chrome
    // DevTools）。挂在 HardwareKeyboard 上避免 TextField 焦点抢键。
    HardwareKeyboard.instance.addHandler(_handleQuickOpenKey);
  }

  void _onCtrlChanged() {
    if (!mounted) return;
    // 暂停状态变更时刷新调试器侧栏 + 把当前栈帧位置滚到视野中央。
    final paused = widget.controller.pausedState;
    if (paused != null && paused.callFrames.isNotEmpty) {
      final loc = paused.callFrames.first['location'] as Map?;
      final url = '${paused.callFrames.first['url'] ?? ''}';
      final line = (loc?['lineNumber'] as num?)?.toInt() ?? -1;
      if (line >= 0 && url.isNotEmpty) {
        // 异步避免在 listener 回调里直接 setState 触发框架告警。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          requestJumpTo(url: url, line: line);
        });
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrlChanged);
    HardwareKeyboard.instance.removeHandler(_handleQuickOpenKey);
    _hoverDebounce?.cancel();
    _highlightTimer?.cancel();
    _sourceScroll.dispose();
    _lsp.stop();
    super.dispose();
  }

  /// HW 键回调：Cmd+P (macOS) / Ctrl+P (其他)。Shift/Alt 修饰键按下时
  /// 不响应（避免与潜在的「全部脚本搜索」冲突，留给现有圆形 chip）。
  bool _handleQuickOpenKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (e.logicalKey != LogicalKeyboardKey.keyP) return false;
    final hw = HardwareKeyboard.instance;
    final modOk = Platform.isMacOS ? hw.isMetaPressed : hw.isControlPressed;
    if (!modOk) return false;
    if (hw.isShiftPressed || hw.isAltPressed) return false;
    if (!mounted) return false;
    // 异步打开，避免在 HW 回调里同步 build dialog。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showQuickOpen());
    });
    return true;
  }

  /// Cmd+P 弹窗：模糊匹配脚本 URL（basename 加权），尾随 `:42` 跳目标行；
  /// 选中后等价于 `_selectScript` + `_scrollToLine`。
  Future<void> _showQuickOpen() async {
    final isZh = widget.isZh;
    final scripts = widget.controller.parsedScripts;
    if (scripts.isEmpty) {
      OpenHandSnackBar.showInfo(
        context,
        isZh ? '尚未捕获脚本' : 'No scripts yet',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final picked = await showAnimatedDialog<({String scriptId, int? line})>(
      context: context,
      builder: (_) => _SourcesQuickOpenDialog(
        controller: widget.controller,
        currentScriptId: _selectedId,
        isZh: isZh,
      ),
    );
    if (picked == null || !mounted) return;
    await _selectScript(picked.scriptId);
    if (!mounted) return;
    final line = picked.line;
    if (line != null && line > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToLine(line);
      });
    }
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
    // 优先使用本会话用户在「LSP 设置」里指定的命令；未配置则回退默认。
    final cfg = context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>()
        ?.readLspConfig();
    final ok = await _lsp.start(
      cmd: cfg?.command,
      cmdArgs: cfg?.args.isEmpty ?? true ? null : cfg!.args,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _lspEnabled = false);
      // exit 127 = "command not found"。识别到这个码就主动给一段安装提示，
      // 让用户不用再回 README 找。
      final raw = _lsp.lastError ?? '';
      final isMissing =
          raw.contains('exit 127') ||
          raw.contains('Cannot run program') ||
          raw.toLowerCase().contains('not found') ||
          raw.toLowerCase().contains('no such file');
      final friendly = isMissing
          ? (isZh
                ? '未检测到 typescript-language-server。请先 `npm i -g typescript typescript-language-server`，或在「LSP 设置」里换成本机已装的 LSP（如 deno-lsp、pyright、vtsls）。'
                : 'typescript-language-server not installed. Run `npm i -g typescript typescript-language-server`, or switch via LSP Settings.')
          : (isZh ? 'LSP 启动失败：$raw' : 'LSP failed: $raw');
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        friendly,
        duration: const Duration(seconds: 6),
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
    final content = _prettify
        ? WebReverseSessionController.prettifyJs(src)
        : src;
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

  /// LSP 设置弹窗：让用户切到本机已装的 LSP（默认 typescript-language-server
  /// --stdio，可换 deno-lsp / pyright / vtsls 等）。保存后立刻把现有
  /// session stop，按新命令重启；命令落进 session metadata 跨会话保留。
  Future<void> _showLspSettings() async {
    final isZh = widget.isZh;
    final dashboardState = context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>();
    final cur = dashboardState?.readLspConfig();
    final cmdCtrl = TextEditingController(
      text: cur?.command ?? 'typescript-language-server',
    );
    final argsCtrl = TextEditingController(
      text: cur?.args.isEmpty ?? true ? '--stdio' : cur!.args.join(' '),
    );
    final preset = ValueNotifier<String?>(null);
    try {
      final result = await showAnimatedDialog<bool>(
        context: context,
        builder: (dialogContext) => buildOpenHandAlertDialog(
          title: Text(isZh ? 'LSP 设置' : 'LSP settings'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh
                      ? '选择 LSP 服务器命令；命令需在本机 PATH 中可执行。常见预设：'
                      : 'Specify LSP server command (must be on PATH). Presets:',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String?>(
                  valueListenable: preset,
                  builder: (_, sel, _) => Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final p in _lspPresets)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: sel == p.label,
                          onSelected: (_) {
                            preset.value = p.label;
                            cmdCtrl.text = p.cmd;
                            argsCtrl.text = p.args.join(' ');
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cmdCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: isZh ? '命令' : 'Command',
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: argsCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: isZh ? '参数（空格分隔）' : 'Args (space separated)',
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  isZh
                      ? '保存后会自动重启当前 LSP 会话。安装方法（按需）：\n'
                            '• typescript-language-server：npm i -g typescript typescript-language-server\n'
                            '• vtsls：npm i -g @vtsls/language-server\n'
                            '• deno lsp：brew install deno  → 命令填 deno，参数 lsp\n'
                            '• pyright：npm i -g pyright  → 命令填 pyright-langserver，参数 --stdio'
                      : 'Restart applies on save. Install hints:\n'
                            '• typescript-language-server: npm i -g typescript typescript-language-server\n'
                            '• vtsls: npm i -g @vtsls/language-server\n'
                            '• deno lsp: brew install deno → cmd=deno args=lsp\n'
                            '• pyright: npm i -g pyright → cmd=pyright-langserver args=--stdio',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              label: isZh ? '取消' : 'Cancel',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            OpenHandDialogActionButton.primary(
              label: isZh ? '保存' : 'Save',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (result != true || !mounted) return;
      final cmd = cmdCtrl.text.trim();
      final args = argsCtrl.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (cmd.isEmpty) return;
      dashboardState?.persistLspConfig(command: cmd, args: args);
      // 重启：先 stop 旧 server（如果运行中），切回 disabled 状态等用户主动开。
      if (_lspEnabled) {
        await _lsp.stop();
        setState(() => _lspEnabled = false);
        // 提示用户需要再次点击 LSP 启用以走新配置。
        if (mounted) {
          OpenHandSnackBar.showInfo(
            context,
            isZh ? '已保存。点击 LSP 胶囊以新命令重启。' : 'Saved. Tap LSP chip to restart.',
          );
        }
      }
    } finally {
      cmdCtrl.dispose();
      argsCtrl.dispose();
      preset.dispose();
    }
  }

  static const _lspPresets = <({String label, String cmd, List<String> args})>[
    (
      label: 'typescript-language-server',
      cmd: 'typescript-language-server',
      args: ['--stdio'],
    ),
    (label: 'vtsls', cmd: 'vtsls', args: ['--stdio']),
    (label: 'deno lsp', cmd: 'deno', args: ['lsp']),
    (label: 'pyright', cmd: 'pyright-langserver', args: ['--stdio']),
    (label: 'rust-analyzer', cmd: 'rust-analyzer', args: <String>[]),
    (label: 'gopls', cmd: 'gopls', args: <String>[]),
  ];

  /// 鼠标在某一行上悬停时调度：300ms 内不触发新 hover，超过则发起 LSP
  /// 请求并把结果写到 _hoverMarkdown 让 _SourceHoverBubble 渲染贴在行尾。
  void _scheduleAutoHover(int line, int column, String text) {
    if (!_lspEnabled || _lsp.status != WebReverseLspStatus.ready) return;
    _hoverDebounce?.cancel();
    _hoverDebounce = startSafeTimer(
      const Duration(milliseconds: 300),
      () async {
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
      },
    );
  }

  void _clearAutoHover() {
    _hoverDebounce?.cancel();
    if (_hoverLine != null || _hoverMarkdown != null || _hoverLoading) {
      _hoverLine = null;
      _hoverMarkdown = null;
      _hoverLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
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
    _highlightTimer = startSafeTimer(const Duration(seconds: 2), () {
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
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
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
    final selected = await showAnimatedMenu<String>(
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
    showOpenHandInfoDialog(
      context: context,
      title: isZh ? 'LSP Hover' : 'LSP Hover',
      closeLabel: isZh ? '关闭' : 'Close',
      content: SizedBox(
        width: 560,
        child: SelectableText(
          md,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
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
    final newName = await showOpenHandTextInputDialog(
      context: context,
      title: isZh ? '重命名为' : 'Rename to',
      cancelLabel: isZh ? '取消' : 'Cancel',
      confirmLabel: isZh ? '确定' : 'OK',
      decoration: const InputDecoration(border: OutlineInputBorder()),
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
    showOpenHandInfoDialog(
      context: context,
      title: isZh ? '重命名结果（仅查看）' : 'Rename result (read-only)',
      closeLabel: isZh ? '关闭' : 'Close',
      content: SizedBox(
        width: 600,
        child: SelectableText(
          isZh
              ? '收到 LSP edit：$summary\n\n（当前面板只展示分析结果，未自动改源码；如需落盘请走外部 IDE。）\n\n${const JsonEncoder.withIndent('  ').convert(edit)}'
              : 'LSP returned edit: $summary\n\n(Read-only preview.)\n\n${const JsonEncoder.withIndent('  ').convert(edit)}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }

  Future<void> _selectScript(String id) async {
    setState(() {
      _selectedId = id;
      _source = null;
      _bpAtLine.clear();
      // 切脚本：source map 状态全部重置；新脚本懒加载。
      _sourceMap = null;
      _sourceMapLoading = false;
      _originalSourceIndex = -1;
    });
    final src = await widget.controller.getScriptSource(id);
    if (!mounted) return;
    setState(() => _source = src);
    await _pushCurrentToLsp();
    // 抓 sourcemap 不阻塞源码渲染；完成后追加显示「Map(N)」chip。
    final url = widget.controller.parsedScripts[id]?.url ?? '';
    if (url.isNotEmpty) {
      setState(() => _sourceMapLoading = true);
      final info = await widget.controller.fetchSourceMapForUrl(url);
      if (!mounted) return;
      setState(() {
        _sourceMap = info;
        _sourceMapLoading = false;
      });
    }
  }

  /// 由 dashboard 调用：根据 (url, line, col) 选中匹配的脚本并滚到目标行。
  /// 匹配策略：优先精确 URL 相等，否则尝试后缀匹配（处理 hash / query 不
  /// 一致的情况），最后退化为 source-map 不可用时仅切到 Sources tab 但
  /// 不强行选择脚本，留给用户手动定位。
  Future<void> requestJumpTo({
    required String url,
    int line = 0,
    int col = 0,
  }) async {
    final scripts = widget.controller.parsedScripts;
    String? matchId;
    for (final e in scripts.entries) {
      if (e.value.url == url) {
        matchId = e.key;
        break;
      }
    }
    matchId ??= () {
      for (final e in scripts.entries) {
        final u = e.value.url;
        if (u.isNotEmpty && (url.endsWith(u) || u.endsWith(url))) {
          return e.key;
        }
      }
      return null;
    }();
    if (matchId == null) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      OpenHandSnackBar.showInfoOn(
        context,
        messenger,
        widget.isZh ? '未找到对应脚本：$url' : 'No parsed script matches: $url',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    if (_selectedId != matchId) {
      await _selectScript(matchId);
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToLine(line);
    });
  }

  Future<void> _toggleBreakpoint(int lineIdx) async {
    final id = _selectedId;
    if (id == null) return;
    // 查看原始源时点行号无法直接转成生成文件行号（需要反向 mapping），
    // 现阶段不支持，直接 SnackBar 提示用户「切回压缩源再下断点」。
    if (_viewingOriginal) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        OpenHandSnackBar.showInfoOn(
          context,
          messenger,
          widget.isZh
              ? '原始源视图暂不支持下断点，请先返回压缩源'
              : 'Breakpoint not supported in original-source view',
          duration: const Duration(seconds: 2),
        );
      }
      return;
    }
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
    final result = await showAnimatedDialog<({String scriptId, int line})>(
      context: context,
      builder: (_) =>
          _SourcesGlobalSearchDialog(controller: widget.controller, isZh: isZh),
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
    final filteredIds =
        scripts.keys
            .where((id) {
              final url = scripts[id]?.url ?? '';
              return _filter.isEmpty ||
                  url.toLowerCase().contains(_filter.toLowerCase());
            })
            .toList(growable: false)
          ..sort(
            (a, b) => (scripts[a]?.url ?? '').compareTo(scripts[b]?.url ?? ''),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: isZh ? '搜索脚本 URL…' : 'Search script URL…',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 16,
                            ),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          onChanged: (v) => setState(() => _filter = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: IconButton(
                          tooltip: isZh
                              ? '跨脚本搜索代码'
                              : 'Search code across scripts',
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          style: IconButton.styleFrom(
                            // 圆形按钮：与右侧脚本列表拉开明显语义，避免与脚本项圈起混淆。
                            shape: CircleBorder(
                              side: BorderSide(color: cs.outlineVariant),
                            ),
                          ),
                          onPressed: _showGlobalCodeSearch,
                          icon: const Icon(Icons.travel_explore_rounded),
                        ),
                      ),
                    ],
                  ),
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

  /// Source Map chip：标题写「Map(N)」，点击弹出原始源列表；选中后
  /// 切到原始源视图。N = sources 数。
  Widget _buildSourceMapChip(ThemeData theme, ColorScheme cs, bool isZh) {
    final sm = _sourceMap!;
    return AnimatedPopupMenuButton<int>(
      tooltip: isZh ? '切到原始源' : 'Pick original source',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 560),
      itemBuilder: (ctx) {
        return <PopupMenuEntry<int>>[
          PopupMenuItem<int>(
            enabled: false,
            child: Text(
              isZh
                  ? '映射来源：${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}'
                  : 'From: ${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const PopupMenuDivider(),
          for (var i = 0; i < sm.sources.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sm.sourcesContent.length > i && sm.sourcesContent[i] != null
                        ? Icons.description_outlined
                        : Icons.cloud_outlined,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      sm.resolveSource(i),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      onSelected: (idx) {
        setState(() => _originalSourceIndex = idx);
      },
      child: Chip(
        avatar: Icon(Icons.alt_route_rounded, size: 14, color: cs.primary),
        label: Text(
          isZh ? 'Map(${sm.sources.length})' : 'Map(${sm.sources.length})',
          style: const TextStyle(fontSize: 12),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }

  Widget _buildSourceView(ThemeData theme, ColorScheme cs, bool isZh) {
    final raw = _source;
    final url = widget.controller.parsedScripts[_selectedId]?.url ?? '';
    if (raw == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // 若选了原始源，优先渲染映射出来的源码；sourcesContent[index] 为
    // null 时显示「未内联到 map」占位。
    String source;
    String? originalLabel;
    if (_viewingOriginal && _sourceMap != null) {
      final idx = _originalSourceIndex;
      final sm = _sourceMap!;
      final body = (idx >= 0 && idx < sm.sourcesContent.length)
          ? sm.sourcesContent[idx]
          : null;
      originalLabel = sm.resolveSource(idx);
      source =
          body ??
          (isZh
              ? '// 该原始源未内联到 sourcesContent 中。\n// 可以在终端单独 fetch ${sm.mapUrl} 下载完整映射，\n// 或在浏览器 DevTools Sources 里手动展开。'
              : '// This original source is not inlined in sourcesContent.\n// Fetch ${sm.mapUrl} manually to inspect.');
    } else {
      source = _prettify ? WebReverseSessionController.prettifyJs(raw) : raw;
    }
    final lines = source.split('\n');
    Widget buildSourceList() {
      return Container(
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
                    horizontal: 12,
                    vertical: 1,
                  ),
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
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SelectableText(
                              lines[idx].isEmpty ? ' ' : lines[idx],
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                height: 1.5,
                                color: cs.onSurface,
                              ),
                            ),
                            // 行尾自动 hover 浮窗：贴在当前行右侧；内容为 LSP
                            // 返回的 markdown，超过 240 字截断，移走自动消失。
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
      );
    }

    Widget buildDebuggerSideRail({required double width}) {
      return _DebuggerSideRail(
        controller: widget.controller,
        isZh: widget.isZh,
        width: width,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _viewingOriginal && originalLabel != null
                      ? '↳ $originalLabel'
                      : url,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _viewingOriginal ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: _viewingOriginal
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── Source Map chip：已抓到 N>0 个原始源时启用；正在
              // 抓取显示菊花；命中后点击弹 PopupMenu 选源切换视图。
              if (_sourceMapLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_sourceMap != null && _sourceMap!.sources.isNotEmpty)
                SizedBox(
                  height: 32,
                  child: _buildSourceMapChip(theme, cs, isZh),
                ),
              if (_viewingOriginal) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _originalSourceIndex = -1);
                    },
                    icon: const Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      size: 16,
                    ),
                    label: Text(isZh ? '返回压缩' : 'Back to gen'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              // “原样” / “LSP” 胶囊外明确限定高 32，与右侧复制源码 /
              // 继续运行等动作胶囊保持同高，避免主侊变得徽高徽矮。
              SizedBox(
                height: 32,
                child: FilterChip(
                  label: Text(
                    _prettify
                        ? (isZh ? '已美化' : 'Pretty')
                        : (isZh ? '原样' : 'Raw'),
                  ),
                  selected: _prettify,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // 查看原始源时美化按钮无意义，置灰。
                  onSelected: _viewingOriginal
                      ? null
                      : (v) {
                          setState(() => _prettify = v);
                          _pushCurrentToLsp();
                        },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 32,
                child: FilterChip(
                  avatar: Icon(
                    _lsp.status == WebReverseLspStatus.ready
                        ? Icons.bolt_rounded
                        : Icons.bolt_outlined,
                    size: 16,
                    color: _lsp.status == WebReverseLspStatus.ready
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  label: Text(
                    _lspEnabled
                        ? (isZh ? 'LSP 已开' : 'LSP on')
                        : (isZh ? 'LSP' : 'LSP'),
                  ),
                  selected: _lspEnabled,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => _toggleLsp(),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: isZh ? 'LSP 设置' : 'LSP settings',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  onPressed: () => _showLspSettings(),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final copied = await setWebReverseClipboardText(source);
                    if (!mounted) return;
                    OpenHandSnackBar.showSuccessOn(
                      context,
                      messenger,
                      webReverseClipboardSnackMessage(
                        isZh: isZh,
                        base: isZh ? '已复制' : 'Copied',
                        result: copied,
                      ),
                      duration: const Duration(seconds: 1),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(isZh ? '复制源码' : 'Copy'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: widget.controller.resumeDebugger,
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(isZh ? '继续运行' : 'Resume'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              if (maxWidth.isFinite &&
                  maxWidth < _kDebuggerSideRailStackBreakpoint) {
                return Column(
                  children: [
                    Expanded(child: buildSourceList()),
                    SizedBox(
                      height: _kDebuggerSideRailStackHeight,
                      child: buildDebuggerSideRail(width: maxWidth),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: buildSourceList()),
                  // 调试器侧栏必须位于 body 的同一条 Row 内。这样它继承
                  // Expanded body 的有限高度，内部 ListView 不会在 tab 动画
                  // / SizeTransition 测量阶段拿到无界高度。
                  buildDebuggerSideRail(width: _kDebuggerSideRailWidth),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

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
                          onTap: () => Navigator.of(
                            context,
                          ).pop((scriptId: h.scriptId, line: h.line)),
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
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '关闭' : 'Close',
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

/// 调试器右侧栏：暂停时显示 Call Stack / Scope / Watch，未暂停时仅显示
/// Watch + 「点页面任何一行可触发暂停」提示。所有项随 controller.notify 自动
/// 刷新；evaluateWatch 内部会按 paused 状态自动切换 evaluateOnCallFrame /
/// Runtime.evaluate。AnimatedSize 控制展开收起。
class _DebuggerSideRail extends StatefulWidget {
  const _DebuggerSideRail({
    required this.controller,
    required this.isZh,
    required this.width,
  });
  final WebReverseSessionController controller;
  final bool isZh;
  final double width;
  @override
  State<_DebuggerSideRail> createState() => _DebuggerSideRailState();
}

class _DebuggerSideRailState extends State<_DebuggerSideRail> {
  final TextEditingController _watchCtrl = TextEditingController();
  final Map<String, String> _watchValues = <String, String>{};
  int _selectedFrame = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _watchCtrl.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (!mounted) return;
    _selectedFrame = 0;
    _evaluateAllWatches();
    setState(() {});
  }

  Future<void> _evaluateAllWatches() async {
    for (final w in widget.controller.watchExpressions) {
      final r = await widget.controller.evaluateWatch(w);
      if (!mounted) return;
      _watchValues[w] = _formatRemote(r);
    }
    if (mounted) setState(() {});
  }

  String _formatRemote(Map<String, Object?>? r) {
    if (r == null) return '<n/a>';
    if (r['type'] == 'error') return 'Error: ${r['description']}';
    final desc = r['description'] ?? r['value'];
    return '$desc';
  }

  Future<void> _addWatch() async {
    final v = _watchCtrl.text.trim();
    if (v.isEmpty) return;
    widget.controller.addWatchExpression(v);
    _watchCtrl.clear();
    final r = await widget.controller.evaluateWatch(v);
    if (!mounted) return;
    setState(() => _watchValues[v] = _formatRemote(r));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final paused = widget.controller.pausedState;
    final frames = paused?.callFrames ?? const <Map<String, Object?>>[];
    final selFrame = frames.isNotEmpty
        ? frames[_selectedFrame.clamp(0, frames.length - 1)]
        : null;
    final scopeChain = (selFrame?['scopeChain'] as List?) ?? const [];

    return SizedBox(
      width: widget.width,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.outlineVariant)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          children: [
            if (paused != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pause_circle_filled_rounded,
                      size: 16,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isZh
                            ? '已暂停 · ${paused.reason}'
                            : 'Paused · ${paused.reason}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isZh ? '继续' : 'Resume',
                      iconSize: 18,
                      onPressed: () => widget.controller.resumeDebugger(),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    IconButton(
                      tooltip: isZh ? '单步跳过' : 'Step over',
                      iconSize: 18,
                      onPressed: () => widget.controller.stepOverDebugger(),
                      icon: const Icon(Icons.redo_rounded),
                    ),
                    IconButton(
                      tooltip: isZh ? '单步进入' : 'Step into',
                      iconSize: 18,
                      onPressed: () => widget.controller.stepIntoDebugger(),
                      icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                    ),
                    IconButton(
                      tooltip: isZh ? '单步跳出' : 'Step out',
                      iconSize: 18,
                      onPressed: () => widget.controller.stepOutDebugger(),
                      icon: const Icon(Icons.subdirectory_arrow_left_rounded),
                    ),
                  ],
                ),
              ),
            if (paused != null) ...[
              const SizedBox(height: 10),
              _RailCard(
                title: isZh ? '调用栈' : 'Call Stack',
                icon: Icons.layers_rounded,
                child: Column(
                  children: [
                    for (var i = 0; i < frames.length; i++)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selectedFrame = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: i == _selectedFrame
                                ? cs.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                i == 0
                                    ? Icons.play_arrow_rounded
                                    : Icons.circle_outlined,
                                size: 12,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (frames[i]['functionName']
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true
                                          ? frames[i]['functionName']
                                          : '<anonymous>')
                                      .toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                ':${(frames[i]['location'] as Map?)?['lineNumber'] ?? '?'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _RailCard(
                title: isZh ? '作用域' : 'Scope',
                icon: Icons.account_tree_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in scopeChain.whereType<Map>())
                      _ScopeSection(
                        controller: widget.controller,
                        scope: s.cast<String, Object?>(),
                        isZh: isZh,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            _RailCard(
              title: isZh ? '观察' : 'Watch',
              icon: Icons.visibility_outlined,
              trailing: IconButton(
                tooltip: isZh ? '全部重算' : 'Re-evaluate',
                iconSize: 16,
                onPressed: _evaluateAllWatches,
                icon: const Icon(Icons.refresh_rounded),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _watchCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            hintText: isZh ? '表达式（回车添加）' : 'expression (Enter)',
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          onSubmitted: (_) => _addWatch(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _addWatch,
                        iconSize: 18,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final w in widget.controller.watchExpressions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  w,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                  ),
                                ),
                                SelectableText(
                                  _watchValues[w] ?? '...',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            icon: Icon(Icons.close_rounded, color: cs.error),
                            onPressed: () {
                              widget.controller.removeWatchExpression(w);
                              _watchValues.remove(w);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isZh
                  ? '更多断点（XHR / EventListener / DOM / CSP / 全局监听器）请打开「Breakpoints」标签页。'
                  : 'More breakpoint types in the Breakpoints tab.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(right: 4), child: child),
        ],
      ),
    );
  }
}

/// Scope 卡片中单个 scope（local / closure / global）的展开行：第一次展开时
/// 通过 `Runtime.getProperties` 拉一次属性列表并缓存到 State。
class _ScopeSection extends StatefulWidget {
  const _ScopeSection({
    required this.controller,
    required this.scope,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final Map<String, Object?> scope;
  final bool isZh;
  @override
  State<_ScopeSection> createState() => _ScopeSectionState();
}

class _ScopeSectionState extends State<_ScopeSection> {
  bool _expanded = false;
  bool _loading = false;
  List<Map<String, Object?>>? _props;

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() => _expanded = true);
    if (_props != null) return;
    final obj = widget.scope['object'] as Map?;
    final objectId = obj?['objectId'] as String?;
    if (objectId == null) return;
    setState(() => _loading = true);
    final list = await widget.controller.runtimeGetProperties(
      objectId: objectId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _props = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = '${widget.scope['type'] ?? 'scope'}';
    final name = widget.scope['name'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    name == null || name.isEmpty ? type : '$type · $name',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in (_props ?? const []).take(120))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: RichText(
                              text: TextSpan(
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: cs.onSurface,
                                ),
                                children: [
                                  TextSpan(
                                    text: '${p['name']}',
                                    style: TextStyle(color: cs.primary),
                                  ),
                                  const TextSpan(text: ': '),
                                  TextSpan(
                                    text:
                                        '${(p['value'] as Map?)?['description'] ?? (p['value'] as Map?)?['value'] ?? ''}',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
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
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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

// ─────────────────────────────────────────────────────────────────────────
// Cmd+P / Ctrl+P 快速打开脚本（类 VSCode/Chrome DevTools）。
// 输入纯文本 → 模糊匹配脚本 URL（basename 命中加权）。结尾 `:42` 跳到指定
// 行。↑↓ 移动高亮项，Enter 选中，Esc 关闭。仅做文件/行跳转；符号检索受限
// 于 CDP（要拉源码现取），暂不放进首屏。
// ─────────────────────────────────────────────────────────────────────────
class _SourcesQuickOpenDialog extends StatefulWidget {
  const _SourcesQuickOpenDialog({
    required this.controller,
    required this.currentScriptId,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final String? currentScriptId;
  final bool isZh;
  @override
  State<_SourcesQuickOpenDialog> createState() =>
      _SourcesQuickOpenDialogState();
}

class _SourcesQuickOpenDialogState extends State<_SourcesQuickOpenDialog> {
  final TextEditingController _qCtrl = TextEditingController();
  final FocusNode _qFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();
  late final List<_QuickEntry> _all;
  List<_QuickEntry> _filtered = const [];
  int? _gotoLine;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    final scripts = widget.controller.parsedScripts;
    _all = scripts.entries
        .map((e) => _QuickEntry(scriptId: e.key, url: e.value.url))
        .toList(growable: false);
    _refilter();
    _qCtrl.addListener(_onText);
  }

  @override
  void dispose() {
    _qCtrl.removeListener(_onText);
    _qCtrl.dispose();
    _qFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _onText() => setState(_refilter);

  void _refilter() {
    var raw = _qCtrl.text;
    int? line;
    final colonIdx = raw.lastIndexOf(':');
    if (colonIdx > 0 && colonIdx < raw.length - 1) {
      final tail = raw.substring(colonIdx + 1).trim();
      final n = int.tryParse(tail);
      if (n != null && n > 0) {
        line = n;
        raw = raw.substring(0, colonIdx);
      }
    }
    _gotoLine = line;
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) {
      // 默认按 URL 排序，把当前文件置顶。
      final sorted = [..._all]..sort((a, b) => a.url.compareTo(b.url));
      final cur = widget.currentScriptId;
      if (cur != null) {
        final idx = sorted.indexWhere((e) => e.scriptId == cur);
        if (idx > 0) {
          final pick = sorted.removeAt(idx);
          sorted.insert(0, pick);
        }
      }
      _filtered = sorted;
    } else {
      // 评分：basename 包含 +3，开头匹配 +2，URL 包含 +1。
      final scored = <(int, _QuickEntry)>[];
      for (final e in _all) {
        final url = e.url.toLowerCase();
        final base = url.split('/').last;
        var s = 0;
        if (base.startsWith(q)) s += 5;
        if (base.contains(q)) s += 3;
        if (url.contains(q)) s += 1;
        if (s > 0) scored.add((s, e));
      }
      scored.sort((a, b) {
        final cmp = b.$1.compareTo(a.$1);
        if (cmp != 0) return cmp;
        return a.$2.url.compareTo(b.$2.url);
      });
      _filtered = scored.map((p) => p.$2).toList(growable: false);
    }
    if (_activeIndex >= _filtered.length) {
      _activeIndex = _filtered.isEmpty ? 0 : _filtered.length - 1;
    }
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _activeIndex = (_activeIndex + delta) % _filtered.length;
      if (_activeIndex < 0) _activeIndex += _filtered.length;
    });
    // 简易滚动：把活跃项滚到中间。
    if (_listScroll.hasClients) {
      const rowH = 36.0;
      final target = (_activeIndex * rowH - 100).clamp(
        0.0,
        _listScroll.position.maxScrollExtent,
      );
      _listScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _commit() {
    if (_filtered.isEmpty) return;
    final pick = _filtered[_activeIndex];
    Navigator.of(context).pop((scriptId: pick.scriptId, line: _gotoLine));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 640,
        height: 480,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.enter): _commit,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): _commit,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: TextField(
                  controller: _qCtrl,
                  focusNode: _qFocus,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isZh
                        ? '快速打开脚本… 末尾加 :42 可跳到指定行'
                        : 'Go to file… (suffix :42 jumps to line)',
                    prefixIcon: const Icon(Icons.flash_on_rounded, size: 16),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              if (_gotoLine != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: Text(
                    isZh ? '将跳到第 $_gotoLine 行' : 'Will jump to line $_gotoLine',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          isZh ? '无匹配脚本' : 'No matches',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _listScroll,
                        itemExtent: 36,
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final e = _filtered[i];
                          final active = i == _activeIndex;
                          final base = e.url.split('/').last;
                          final dir = base.length >= e.url.length
                              ? ''
                              : e.url.substring(
                                  0,
                                  e.url.length - base.length - 1,
                                );
                          return InkWell(
                            onTap: () {
                              setState(() => _activeIndex = i);
                              _commit();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              color: active
                                  ? cs.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 14,
                                    color: active
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    base.isEmpty ? '(anonymous)' : base,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active ? cs.primary : cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      dir,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant,
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Text(
                  isZh
                      ? '↑/↓ 选择 · Enter 打开 · Esc 关闭'
                      : '↑/↓ navigate · Enter open · Esc close',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickEntry {
  const _QuickEntry({required this.scriptId, required this.url});
  final String scriptId;
  final String url;
}

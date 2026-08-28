part of 'web_reverse_dashboard_dialog.dart';

String _sourcesStatusLabel(
  BuildContext context, {
  required int lineCount,
  required bool viewingOriginal,
  required bool prettified,
}) {
  final view = viewingOriginal
      ? openHandLocalizedText(
          context,
          zh: '原始源',
          zhHant: '原始源',
          en: 'original',
          fr: 'original',
          de: 'Original',
          ja: '元ソース',
        )
      : prettified
      ? openHandLocalizedText(
          context,
          zh: '已美化',
          zhHant: '已美化',
          en: 'pretty',
          fr: 'formaté',
          de: 'formatiert',
          ja: '整形済み',
        )
      : openHandLocalizedText(
          context,
          zh: '原样',
          zhHant: '原樣',
          en: 'raw',
          fr: 'brut',
          de: 'roh',
          ja: 'そのまま',
        );
  return openHandLocalizedText(
    context,
    zh: '$lineCount 行 | $view | JavaScript',
    zhHant: '$lineCount 行 | $view | JavaScript',
    en: '$lineCount lines | $view | JavaScript',
    fr: '$lineCount lignes | $view | JavaScript',
    de: '$lineCount Zeilen | $view | JavaScript',
    ja: '$lineCount 行 | $view | JavaScript',
  );
}

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
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
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

  // 自动 hover + 行尾浮窗 + 跳转定义滚动。
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
  static const double _kSourceGutterWidth = 58;
  static const double _kSourceEditorFontSize = 11.5;
  static const double _kSourceEstimatedCharWidth = 7.1;
  static const double _kSourceMaxEstimatedContentWidth = 16000;
  static const double _kSourceStatusBarHeight = 26;
  static const double _kDebuggerSideRailWidth = 300;
  static const double _kDebuggerSideRailStackBreakpoint = 680;
  static const double _kDebuggerSideRailStackHeight = 220;
  static const int _kLspSnackErrorMaxChars = 220;
  final ScrollController _sourceScroll = ScrollController();
  final ScrollController _sourceLineScroll = ScrollController();
  final ScrollController _sourceHorizontalScroll = ScrollController();

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
    _sourceScroll.addListener(_syncSourceLineScroll);
    widget.controller.addListener(_onCtrlChanged);
    // Cmd+P / Ctrl+P 全局快速打开脚本/跳行（类 VSCode/Chrome
    // DevTools）。挂在 HardwareKeyboard 上避免 TextField 焦点抢键。
    HardwareKeyboard.instance.addHandler(_handleQuickOpenKey);
  }

  void _onCtrlChanged() {
    if (!mounted) return;
    final selectedId = _selectedId;
    final selectedScriptRemoved =
        selectedId != null &&
        !widget.controller.parsedScripts.containsKey(selectedId);
    // 暂停状态变更时刷新调试器侧栏 + 把当前栈帧位置滚到视野中央。
    final paused = widget.controller.pausedState;
    if (paused != null && paused.callFrames.isNotEmpty) {
      final loc = stringKeyedMapFromValue(paused.callFrames.first['location']);
      final url = '${paused.callFrames.first['url'] ?? ''}';
      final line = intFromValue(loc['lineNumber'], fallback: -1);
      if (line >= 0 && url.isNotEmpty) {
        // 异步避免在 listener 回调里直接 setState 触发框架告警。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          requestJumpTo(url: url, line: line);
        });
      }
    }
    setState(() {
      if (!selectedScriptRemoved) return;
      _selectedId = null;
      _source = null;
      _sourceMap = null;
      _sourceMapLoading = false;
      _originalSourceIndex = -1;
      _bpAtLine.clear();
      _lastSentUri = null;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrlChanged);
    HardwareKeyboard.instance.removeHandler(_handleQuickOpenKey);
    _hoverDebounce?.cancel();
    _highlightTimer?.cancel();
    _sourceScroll.removeListener(_syncSourceLineScroll);
    _sourceScroll.dispose();
    _sourceLineScroll.dispose();
    _sourceHorizontalScroll.dispose();
    unawaited(_lsp.stop());
    super.dispose();
  }

  void _syncSourceLineScroll() {
    if (!_sourceScroll.hasClients || !_sourceLineScroll.hasClients) return;
    final target = _sourceScroll.offset
        .clamp(0.0, _sourceLineScroll.position.maxScrollExtent)
        .toDouble();
    if ((_sourceLineScroll.offset - target).abs() < 0.5) return;
    _sourceLineScroll.jumpTo(target);
  }

  void _resetSourceScrollPositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_sourceScroll.hasClients) _sourceScroll.jumpTo(0);
      if (_sourceLineScroll.hasClients) _sourceLineScroll.jumpTo(0);
      if (_sourceHorizontalScroll.hasClients) _sourceHorizontalScroll.jumpTo(0);
    });
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
    final scripts = widget.controller.parsedScripts;
    if (scripts.isEmpty) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '尚未捕获脚本',
          zhHant: '尚未捕獲腳本',
          en: 'No scripts yet',
          fr: 'Aucun script pour le moment',
          de: 'Noch keine Skripte erfasst',
          ja: 'スクリプトはまだありません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    final picked = await webReverseToolDialogs
        .show<({String scriptId, int? line})>(
          context: context,
          builder: (_) => _SourcesQuickOpenDialog(
            controller: widget.controller,
            currentScriptId: _selectedId,
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
    if (_lspEnabled) {
      await _lsp.stop();
      if (!mounted) return;
      setState(() => _lspEnabled = false);
      return;
    }
    setState(() => _lspEnabled = true);
    // 优先使用本会话用户在「LSP 设置」里指定的命令；未配置则回退默认。
    final cfg = context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>()
        ?.readLspConfig();
    late final bool ok;
    try {
      ok = await _lsp.start(
        cmd: cfg?.command,
        cmdArgs: cfg?.args.isEmpty ?? true ? null : cfg!.args,
      );
    } catch (error, stack) {
      silentLog('web_reverse_sources_panel', '启动 LSP', error, stack);
      if (!mounted) return;
      setState(() => _lspEnabled = false);
      final detail = userFailureMessage(
        error,
        fallback: openHandLocalizedText(
          context,
          zh: '无法启动 LSP，请检查命令与安装状态。',
          zhHant: '無法啟動 LSP，請檢查命令與安裝狀態。',
          en: 'Unable to start LSP. Check the command and installation.',
          fr: 'Impossible de démarrer le LSP. Vérifiez la commande et l’installation.',
          de: 'LSP konnte nicht gestartet werden. Prüfen Sie Befehl und Installation.',
          ja: 'LSP を起動できません。コマンドとインストール状態を確認してください。',
        ),
        maxCharacters: _kLspSnackErrorMaxChars,
      );
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'LSP 启动失败：$detail',
          zhHant: 'LSP 啟動失敗：$detail',
          en: 'LSP failed: $detail',
          fr: 'Échec LSP : $detail',
          de: 'LSP fehlgeschlagen: $detail',
          ja: 'LSP 起動に失敗しました: $detail',
        ),
        duration: kOpenHandSnackBarLongReadDuration,
      );
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _lspEnabled = false);
      final raw = clipTextWithEllipsis(
        _lsp.lastError ?? '',
        _kLspSnackErrorMaxChars,
      );
      final isMissing = _lsp.status == WebReverseLspStatus.notInstalled;
      final friendly = isMissing
          ? openHandLocalizedText(
              context,
              zh: '未检测到 typescript-language-server。请先 `npm i -g typescript typescript-language-server`，或在「LSP 设置」里换成本机已装的 LSP（如 deno-lsp、pyright、vtsls）。',
              zhHant:
                  '未偵測到 typescript-language-server。請先 `npm i -g typescript typescript-language-server`，或在「LSP 設定」裡換成本機已安裝的 LSP（如 deno-lsp、pyright、vtsls）。',
              en: 'typescript-language-server not installed. Run `npm i -g typescript typescript-language-server`, or switch via LSP Settings.',
              fr: 'typescript-language-server est introuvable. Lancez `npm i -g typescript typescript-language-server` ou changez de LSP.',
              de: 'typescript-language-server nicht gefunden. Führen Sie `npm i -g typescript typescript-language-server` aus oder wählen Sie einen anderen LSP.',
              ja: 'typescript-language-server が見つかりません。`npm i -g typescript typescript-language-server` を実行するか、LSP 設定で別の LSP を選んでください。',
            )
          : openHandLocalizedText(
              context,
              zh: 'LSP 启动失败：$raw',
              zhHant: 'LSP 啟動失敗：$raw',
              en: 'LSP failed: $raw',
              fr: 'Échec LSP : $raw',
              de: 'LSP fehlgeschlagen: $raw',
              ja: 'LSP 起動に失敗しました: $raw',
            );
      showOpenHandErrorSnack(
        context,
        friendly,
        duration: kOpenHandSnackBarLongReadDuration,
      );
      return;
    }
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: 'LSP 已就绪',
        zhHant: 'LSP 已就緒',
        en: 'LSP ready',
        fr: 'LSP prêt',
        de: 'LSP bereit',
        ja: 'LSP 準備完了',
      ),
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
      final result = await webReverseToolDialogs.show<bool>(
        context: context,
        builder: (dialogContext) => buildOpenHandAlertDialog(
          title: Text(
            openHandLocalizedText(
              dialogContext,
              zh: 'LSP 设置',
              zhHant: 'LSP 設定',
              en: 'LSP settings',
              fr: 'Paramètres LSP',
              de: 'LSP-Einstellungen',
              ja: 'LSP 設定',
            ),
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  openHandLocalizedText(
                    dialogContext,
                    zh: '选择 LSP 服务器命令；命令需在本机 PATH 中可执行。常见预设：',
                    zhHant: '選擇 LSP 伺服器命令；命令需在本機 PATH 中可執行。常見預設：',
                    en: 'Specify LSP server command (must be on PATH). Presets:',
                    fr: 'Indiquez la commande LSP (dans PATH). Préréglages :',
                    de: 'LSP-Serverbefehl angeben (im PATH). Voreinstellungen:',
                    ja: 'LSP サーバーコマンドを選択します（PATH 上で実行可能）。プリセット:',
                  ),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                kOpenHandGap8,
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
                kOpenHandGap12,
                TextField(
                  controller: cmdCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: openHandLocalizedText(
                      dialogContext,
                      zh: '命令',
                      zhHant: '命令',
                      en: 'Command',
                      fr: 'Commande',
                      de: 'Befehl',
                      ja: 'コマンド',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                kOpenHandGap8,
                TextField(
                  controller: argsCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: openHandLocalizedText(
                      dialogContext,
                      zh: '参数（空格分隔）',
                      zhHant: '參數（以空格分隔）',
                      en: 'Args (space separated)',
                      fr: 'Arguments (séparés par des espaces)',
                      de: 'Argumente (leerzeichengetrennt)',
                      ja: '引数（スペース区切り）',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                kOpenHandGap8,
                Text(
                  openHandLocalizedText(
                    dialogContext,
                    zh:
                        '保存后会自动重启当前 LSP 会话。安装方法（按需）：\n'
                        '• typescript-language-server：npm i -g typescript typescript-language-server\n'
                        '• vtsls：npm i -g @vtsls/language-server\n'
                        '• deno lsp：brew install deno  → 命令填 deno，参数 lsp\n'
                        '• pyright：npm i -g pyright  → 命令填 pyright-langserver，参数 --stdio',
                    zhHant:
                        '儲存後會自動重啟目前 LSP 會話。安裝方法（按需）：\n'
                        '• typescript-language-server：npm i -g typescript typescript-language-server\n'
                        '• vtsls：npm i -g @vtsls/language-server\n'
                        '• deno lsp：brew install deno  → 命令填 deno，參數 lsp\n'
                        '• pyright：npm i -g pyright  → 命令填 pyright-langserver，參數 --stdio',
                    en:
                        'Restart applies on save. Install hints:\n'
                        '• typescript-language-server: npm i -g typescript typescript-language-server\n'
                        '• vtsls: npm i -g @vtsls/language-server\n'
                        '• deno lsp: brew install deno → cmd=deno args=lsp\n'
                        '• pyright: npm i -g pyright → cmd=pyright-langserver args=--stdio',
                    fr:
                        'Le LSP redémarre à l’enregistrement. Installation :\n'
                        '• typescript-language-server: npm i -g typescript typescript-language-server\n'
                        '• vtsls: npm i -g @vtsls/language-server\n'
                        '• deno lsp: brew install deno → cmd=deno args=lsp\n'
                        '• pyright: npm i -g pyright → cmd=pyright-langserver args=--stdio',
                    de:
                        'Speichern startet die LSP-Sitzung neu. Installation:\n'
                        '• typescript-language-server: npm i -g typescript typescript-language-server\n'
                        '• vtsls: npm i -g @vtsls/language-server\n'
                        '• deno lsp: brew install deno → cmd=deno args=lsp\n'
                        '• pyright: npm i -g pyright → cmd=pyright-langserver args=--stdio',
                    ja:
                        '保存すると現在の LSP セッションを再起動します。インストール例:\n'
                        '• typescript-language-server: npm i -g typescript typescript-language-server\n'
                        '• vtsls: npm i -g @vtsls/language-server\n'
                        '• deno lsp: brew install deno → cmd=deno args=lsp\n'
                        '• pyright: npm i -g pyright → cmd=pyright-langserver args=--stdio',
                  ),
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              label: openHandCancelLabel(dialogContext),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            OpenHandDialogActionButton.primary(
              label: openHandLocalizedText(
                dialogContext,
                zh: '保存',
                zhHant: '儲存',
                en: 'Save',
                fr: 'Enregistrer',
                de: 'Speichern',
                ja: '保存',
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (result != true || !mounted) return;
      final cmd = cmdCtrl.text.trim();
      final args = argsCtrl.text
          .trim()
          .split(kInlineWhitespacePattern)
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (cmd.isEmpty) return;
      dashboardState?.persistLspConfig(command: cmd, args: args);
      // 重启：先 stop 旧 server（如果运行中），切回 disabled 状态等用户主动开。
      if (_lspEnabled) {
        await _lsp.stop();
        if (!mounted) return;
        setState(() => _lspEnabled = false);
        // 提示用户需要再次点击 LSP 启用以走新配置。
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已保存。点击 LSP 胶囊以新命令重启。',
            zhHant: '已儲存。點擊 LSP 膠囊以新命令重啟。',
            en: 'Saved. Tap LSP chip to restart.',
            fr: 'Enregistré. Touchez le badge LSP pour redémarrer.',
            de: 'Gespeichert. LSP-Chip antippen zum Neustart.',
            ja: '保存しました。LSP チップをクリックして新しいコマンドで再起動してください。',
          ),
        );
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
      duration: kOpenHandMotion320,
      curve: kOpenHandSwitchInCurve,
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
      style: const TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: 11.5,
      ),
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
          child: Text(
            openHandLocalizedText(
              context,
              zh: '查看 hover',
              zhHant: '查看 hover',
              en: 'Hover',
              fr: 'Survol',
              de: 'Hover anzeigen',
              ja: 'Hover を表示',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'def',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '跳转定义',
              zhHant: '跳轉定義',
              en: 'Go to definition',
              fr: 'Aller à la définition',
              de: 'Zur Definition',
              ja: '定義へ移動',
            ),
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Text(
            openHandLocalizedText(
              context,
              zh: '重命名…',
              zhHant: '重新命名…',
              en: 'Rename…',
              fr: 'Renommer…',
              de: 'Umbenennen…',
              ja: '名前を変更…',
            ),
          ),
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
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    final md = await _lsp.hover(uri, line, col);
    if (!mounted) return;
    if (md == null || md.isEmpty) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '该位置无 hover 信息',
          zhHant: '該位置沒有 hover 資訊',
          en: 'No hover info',
          fr: 'Aucune info de survol',
          de: 'Keine Hover-Info',
          ja: 'Hover 情報はありません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    showOpenHandInfoDialog(
      context: context,
      title: 'LSP Hover',
      closeLabel: openHandCloseLabel(context),
      content: SizedBox(
        width: 560,
        child: SelectableText(
          md,
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Future<void> _gotoDefinition(int line, int col) async {
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    final r = await _lsp.definition(uri, line, col);
    if (!mounted) return;
    if (r == null) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '未找到定义',
          zhHant: '未找到定義',
          en: 'No definition found',
          fr: 'Aucune définition trouvée',
          de: 'Keine Definition gefunden',
          ja: '定義が見つかりません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    // 如果定义还在同一份文档（典型场景：当前脚本内的函数 / 变量），
    // 直接 ScrollController.animateTo 滚到目标行 + 高亮 2 秒。否则
    // SnackBar 提示位置（跨文件需要 user 自行打开外部 IDE）。
    if (r.uri == uri) {
      _scrollToLine(r.line);
    } else {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '定义位置：${r.uri} 第 ${r.line + 1} 行',
          zhHant: '定義位置：${r.uri} 第 ${r.line + 1} 行',
          en: 'Defined at ${r.uri} L${r.line + 1}',
          fr: 'Défini dans ${r.uri} ligne ${r.line + 1}',
          de: 'Definiert in ${r.uri} Zeile ${r.line + 1}',
          ja: '定義位置: ${r.uri} ${r.line + 1} 行目',
        ),
        duration: kOpenHandSnackBarDetailedDuration,
      );
    }
  }

  Future<void> _renameAt(int line, int col) async {
    if (_lastSentUri == null) await _pushCurrentToLsp();
    final uri = _lastSentUri;
    if (uri == null) return;
    if (!mounted) return;
    final newName = await showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '重命名为',
        zhHant: '重新命名為',
        en: 'Rename to',
        fr: 'Renommer en',
        de: 'Umbenennen in',
        ja: '新しい名前',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandOkLabel(context),
      decoration: const InputDecoration(border: OutlineInputBorder()),
    );
    if (!mounted || newName == null || newName.isEmpty) return;
    final edit = await _lsp.rename(uri, line, col, newName);
    if (!mounted) return;
    if (edit == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '重命名失败（LSP 未返回 edit）',
          zhHant: '重新命名失敗（LSP 未返回 edit）',
          en: 'Rename failed',
          fr: 'Échec du renommage',
          de: 'Umbenennen fehlgeschlagen',
          ja: '名前変更に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
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
      title: openHandLocalizedText(
        context,
        zh: '重命名结果（仅查看）',
        zhHant: '重新命名結果（僅查看）',
        en: 'Rename result (read-only)',
        fr: 'Résultat du renommage (lecture seule)',
        de: 'Umbenennen-Ergebnis (schreibgeschützt)',
        ja: '名前変更結果（読み取り専用）',
      ),
      closeLabel: openHandCloseLabel(context),
      content: SizedBox(
        width: 600,
        child: SelectableText(
          openHandLocalizedText(
            context,
            zh: '收到 LSP edit：$summary\n\n（当前面板只展示分析结果，未自动改源码；如需落盘请走外部 IDE。）\n\n${prettyPrintJson(edit)}',
            zhHant:
                '收到 LSP edit：$summary\n\n（目前面板只展示分析結果，未自動改源碼；如需落盤請使用外部 IDE。）\n\n${prettyPrintJson(edit)}',
            en: 'LSP returned edit: $summary\n\n(Read-only preview.)\n\n${prettyPrintJson(edit)}',
            fr: 'Le LSP a retourné un edit : $summary\n\n(Aperçu en lecture seule.)\n\n${prettyPrintJson(edit)}',
            de: 'LSP gab ein Edit zurück: $summary\n\n(Nur-Lese-Vorschau.)\n\n${prettyPrintJson(edit)}',
            ja: 'LSP edit を受信: $summary\n\n（読み取り専用プレビューです。）\n\n${prettyPrintJson(edit)}',
          ),
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 11,
          ),
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
    if (!mounted || _selectedId != id) return;
    setState(() => _source = src);
    _resetSourceScrollPositions();
    await _pushCurrentToLsp();
    if (!mounted || _selectedId != id) return;
    // 抓 sourcemap 不阻塞源码渲染；完成后追加显示「Map(N)」chip。
    final url = widget.controller.parsedScripts[id]?.url ?? '';
    if (url.isNotEmpty) {
      setState(() => _sourceMapLoading = true);
      final info = await widget.controller.fetchSourceMapForUrl(url);
      if (!mounted || _selectedId != id) return;
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
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '未找到对应脚本：$url',
          zhHant: '未找到對應腳本：$url',
          en: 'No parsed script matches: $url',
          fr: 'Aucun script ne correspond : $url',
          de: 'Kein passendes Skript: $url',
          ja: '対応するスクリプトが見つかりません: $url',
        ),
        duration: kOpenHandSnackBarBriefDuration,
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
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '原始源视图暂不支持下断点，请先返回压缩源',
          zhHant: '原始源視圖暫不支援設定斷點，請先返回壓縮源',
          en: 'Breakpoint not supported in original-source view',
          fr: 'Points d’arrêt non pris en charge dans la source originale',
          de: 'Breakpoints in Originalquellenansicht nicht unterstützt',
          ja: '元ソース表示ではブレークポイントを設定できません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    final url = widget.controller.parsedScripts[id]?.url;
    if (url == null || url.isEmpty) return;
    final existing = _bpAtLine[lineIdx];
    if (existing != null) {
      final ok = await widget.controller.removeBreakpoint(existing);
      if (!mounted) return;
      if (ok) {
        setState(() => _bpAtLine.remove(lineIdx));
        context
            .findAncestorStateOfType<_WebReverseDashboardDialogState>()
            ?.persistBreakpoints();
      } else {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '取消断点失败',
            zhHant: '取消斷點失敗',
            en: 'Remove failed',
            fr: 'Échec de suppression',
            de: 'Entfernen fehlgeschlagen',
            ja: '解除に失敗しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
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
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已下断点',
            zhHant: '已設定斷點',
            en: 'Breakpoint set',
            fr: 'Point d’arrêt défini',
            de: 'Breakpoint gesetzt',
            ja: 'ブレークポイントを設定しました',
          ),
        );
      } else {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '下断点失败（可能 url 不可达）',
            zhHant: '設定斷點失敗（可能 URL 不可達）',
            en: 'Set failed',
            fr: 'Échec de définition',
            de: 'Setzen fehlgeschlagen',
            ja: '設定に失敗しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      }
    }
  }

  Future<void> _showGlobalCodeSearch() async {
    final result = await webReverseToolDialogs
        .show<({String scriptId, int line})>(
          context: context,
          builder: (_) =>
              _SourcesGlobalSearchDialog(controller: widget.controller),
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
                            hintText: openHandLocalizedText(
                              context,
                              zh: '搜索脚本 URL…',
                              zhHant: '搜尋腳本 URL…',
                              en: 'Search script URL…',
                              fr: 'Rechercher une URL de script…',
                              de: 'Skript-URL suchen…',
                              ja: 'スクリプト URL を検索…',
                            ),
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
                            fontFamily: kOpenHandMonospaceFontFamily,
                            fontSize: 12,
                          ),
                          onChanged: (v) => setState(() => _filter = v.trim()),
                        ),
                      ),
                      kOpenHandHGap6,
                      SizedBox(
                        width: 38,
                        height: 38,
                        child: IconButton(
                          tooltip: openHandLocalizedText(
                            context,
                            zh: '跨脚本搜索代码',
                            zhHant: '跨腳本搜尋程式碼',
                            en: 'Search code across scripts',
                            fr: 'Rechercher dans les scripts',
                            de: 'Code über Skripte suchen',
                            ja: 'スクリプト横断検索',
                          ),
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
                              openHandLocalizedText(
                                context,
                                zh: '尚未捕获脚本。\n刷新页面或交互后此处会更新。',
                                zhHant: '尚未捕獲腳本。\n重新整理頁面或互動後此處會更新。',
                                en: 'No scripts captured yet.',
                                fr: 'Aucun script capturé pour le moment.',
                                de: 'Noch keine Skripte erfasst.',
                                ja: 'スクリプトはまだ取得されていません。',
                              ),
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
                                      fontFamily: kOpenHandMonospaceFontFamily,
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
                      openHandLocalizedText(
                        context,
                        zh: '从左侧选择脚本查看源码 / 下断点。\n\n点击任意行的左侧行号即可下断点；命中后浏览器会自动暂停，可在原生 DevTools 中调试。',
                        zhHant:
                            '從左側選擇腳本查看源碼 / 設定斷點。\n\n點擊任意行的左側行號即可設定斷點；命中後瀏覽器會自動暫停，可在原生 DevTools 中偵錯。',
                        en: 'Pick a script on the left to view its source.\n\nClick any line number to toggle a breakpoint.',
                        fr: 'Choisissez un script à gauche pour voir sa source.\n\nCliquez un numéro de ligne pour basculer un point d’arrêt.',
                        de: 'Wählen Sie links ein Skript, um den Quelltext zu sehen.\n\nZeilennummer anklicken, um einen Breakpoint umzuschalten.',
                        ja: '左側のスクリプトを選択してソースを表示します。\n\n行番号をクリックするとブレークポイントを切り替えます。',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : _buildSourceView(theme, cs),
        ),
      ],
    );
  }

  /// Source Map chip：标题写「Map(N)」，点击弹出原始源列表；选中后
  /// 切到原始源视图。N = sources 数。
  Widget _buildSourceMapChip(ThemeData theme, ColorScheme cs) {
    final sm = _sourceMap!;
    return AnimatedPopupMenuButton<int>(
      tooltip: openHandLocalizedText(
        context,
        zh: '切到原始源',
        zhHant: '切到原始源',
        en: 'Pick original source',
        fr: 'Choisir la source originale',
        de: 'Originalquelle wählen',
        ja: '元ソースを選択',
      ),
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 560),
      itemBuilder: (ctx) {
        return <PopupMenuEntry<int>>[
          PopupMenuItem<int>(
            enabled: false,
            child: Text(
              openHandLocalizedText(
                context,
                zh: '映射来源：${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
                zhHant: '映射來源：${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
                en: 'From: ${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
                fr: 'Depuis : ${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
                de: 'Von: ${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
                ja: '参照元: ${sm.mapUrl.isEmpty ? '<unknown>' : sm.mapUrl}',
              ),
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
                  kOpenHandHGap8,
                  Flexible(
                    child: Text(
                      sm.resolveSource(i),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kOpenHandMonospaceFontFamily,
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
        _resetSourceScrollPositions();
      },
      child: Chip(
        avatar: Icon(Icons.alt_route_rounded, size: 14, color: cs.primary),
        label: Text(
          'Map(${sm.sources.length})',
          style: const TextStyle(fontSize: 12),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }

  Widget _buildSourceView(ThemeData theme, ColorScheme cs) {
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
          openHandLocalizedText(
            context,
            zh: '// 该原始源未内联到 sourcesContent 中。\n// 可以在终端单独 fetch ${sm.mapUrl} 下载完整映射，\n// 或在浏览器 DevTools Sources 里手动展开。',
            zhHant:
                '// 該原始源未內嵌到 sourcesContent 中。\n// 可以在終端單獨 fetch ${sm.mapUrl} 下載完整映射，\n// 或在瀏覽器 DevTools Sources 裡手動展開。',
            en: '// This original source is not inlined in sourcesContent.\n// Fetch ${sm.mapUrl} manually to inspect.',
            fr: '// Cette source originale n’est pas intégrée dans sourcesContent.\n// Récupérez ${sm.mapUrl} manuellement pour l’inspecter.',
            de: '// Diese Originalquelle ist nicht in sourcesContent eingebettet.\n// Rufen Sie ${sm.mapUrl} manuell ab.',
            ja: '// この元ソースは sourcesContent に埋め込まれていません。\n// ${sm.mapUrl} を手動で取得して確認してください。',
          );
    } else {
      source = _prettify ? WebReverseSessionController.prettifyJs(raw) : raw;
    }
    final lines = source.split('\n');
    Widget buildSourceList() {
      final longestLine = lines.fold<int>(
        0,
        (value, line) => math.max(value, line.length),
      );
      final sourceTextStyle = theme.textTheme.bodySmall?.copyWith(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: _kSourceEditorFontSize,
        height: 1.5,
        color: cs.onSurface,
      );
      final gutterTextStyle = theme.textTheme.labelSmall?.copyWith(
        fontFamily: kOpenHandMonospaceFontFamily,
        color: cs.onSurfaceVariant.withValues(alpha: 0.72),
      );
      const sourceScrollBehavior = OpenHandEditorScrollBehavior();

      return Container(
        color: cs.surfaceContainerHigh,
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportWidth = math.max(
                      0.0,
                      constraints.maxWidth - _kSourceGutterWidth,
                    );
                    final contentWidth = math.min(
                      _kSourceMaxEstimatedContentWidth,
                      math.max(
                        viewportWidth,
                        longestLine * _kSourceEstimatedCharWidth + 48,
                      ),
                    );

                    Widget buildGutterLine(int idx) {
                      final hasBp = _bpAtLine.containsKey(idx);
                      final isHighlighted = _highlightedLine == idx;
                      return RepaintBoundary(
                        child: InkWell(
                          onTap: () => _toggleBreakpoint(idx),
                          child: AnimatedContainer(
                            duration: openHandMotionDuration(
                              context,
                              kOpenHandMotion240,
                            ),
                            curve: kOpenHandSwitchInCurve,
                            color: isHighlighted
                                ? cs.tertiaryContainer.withValues(alpha: 0.32)
                                : Colors.transparent,
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 10,
                                  child: hasBp
                                      ? Center(
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: cs.error,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: cs.error.withValues(
                                                    alpha: 0.24,
                                                  ),
                                                  blurRadius: 5,
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                kOpenHandHGap6,
                                Expanded(
                                  child: Text(
                                    '${idx + 1}',
                                    maxLines: 1,
                                    textAlign: TextAlign.right,
                                    style: gutterTextStyle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    Widget buildCodeLine(int idx) {
                      final line = lines[idx];
                      final isHighlighted = _highlightedLine == idx;
                      final isHovered = _hoverLine == idx && _lspEnabled;
                      return RepaintBoundary(
                        child: MouseRegion(
                          onHover: _lspEnabled
                              ? (event) {
                                  final col = _estimateColumn(
                                    event.localPosition.dx,
                                    line,
                                  );
                                  _scheduleAutoHover(idx, col, line);
                                }
                              : null,
                          onExit: _lspEnabled ? (_) => _clearAutoHover() : null,
                          child: InkWell(
                            onTap: () => _toggleBreakpoint(idx),
                            onSecondaryTapDown: _lspEnabled
                                ? (d) => _onLineSecondaryTap(d, idx, line)
                                : null,
                            onLongPress: _lspEnabled
                                ? () => _onLineLongPress(idx, line)
                                : null,
                            child: AnimatedContainer(
                              duration: openHandMotionDuration(
                                context,
                                kOpenHandMotion240,
                              ),
                              curve: kOpenHandSwitchInCurve,
                              color: isHighlighted
                                  ? cs.tertiaryContainer.withValues(alpha: 0.5)
                                  : Colors.transparent,
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 16,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SelectableText(
                                    line.isEmpty ? ' ' : line,
                                    maxLines: 1,
                                    style: sourceTextStyle,
                                  ),
                                  if (isHovered &&
                                      (_hoverLoading ||
                                          (_hoverMarkdown != null &&
                                              _hoverMarkdown!.isNotEmpty)))
                                    Positioned(
                                      left: _estimateLineWidth(line) + 12,
                                      top: -2,
                                      child: _SourceHoverBubble(
                                        markdown: _hoverMarkdown,
                                        loading: _hoverLoading,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: _kSourceGutterWidth,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.62,
                            ),
                            border: Border(
                              right: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: ScrollConfiguration(
                            behavior: sourceScrollBehavior,
                            child: ListView.builder(
                              controller: _sourceLineScroll,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: lines.length,
                              itemExtent: _kSourceLineHeight,
                              itemBuilder: (_, idx) => buildGutterLine(idx),
                            ),
                          ),
                        ),
                        Expanded(
                          child: PrimaryScrollController.none(
                            child: OpenHandSafeScrollbar(
                              controller: _sourceScroll,
                              thumbVisibility: true,
                              thickness: 9,
                              radius: kOpenHandPillRadius,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.vertical,
                              child: ScrollConfiguration(
                                behavior: sourceScrollBehavior,
                                child: SingleChildScrollView(
                                  controller: _sourceHorizontalScroll,
                                  scrollDirection: Axis.horizontal,
                                  physics: const ClampingScrollPhysics(),
                                  child: SizedBox(
                                    width: contentWidth,
                                    child: ListView.builder(
                                      controller: _sourceScroll,
                                      physics: const ClampingScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      cacheExtent: _kSourceLineHeight * 80,
                                      itemCount: lines.length,
                                      itemExtent: _kSourceLineHeight,
                                      itemBuilder: (_, idx) =>
                                          buildCodeLine(idx),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Container(
              height: _kSourceStatusBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.data_object_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Text(
                      _sourcesStatusLabel(
                        context,
                        lineCount: lines.length,
                        viewingOriginal: _viewingOriginal,
                        prettified: _prettify,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
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

    Widget buildDebuggerSideRail({required double width}) {
      return _DebuggerSideRail(controller: widget.controller, width: width);
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
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                    color: _viewingOriginal ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: _viewingOriginal
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              kOpenHandHGap8,
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
                SizedBox(height: 32, child: _buildSourceMapChip(theme, cs)),
              if (_viewingOriginal) ...[
                kOpenHandHGap6,
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _originalSourceIndex = -1);
                      _resetSourceScrollPositions();
                    },
                    icon: const Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      size: 16,
                    ),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '返回压缩',
                        zhHant: '返回壓縮',
                        en: 'Back to gen',
                        fr: 'Retour au généré',
                        de: 'Zurück zu generiert',
                        ja: '生成コードへ戻る',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
              kOpenHandHGap6,
              // “原样” / “LSP” 胶囊外明确限定高 32，与右侧复制源码 /
              // 继续运行等动作胶囊保持同高，避免主侊变得徽高徽矮。
              SizedBox(
                height: 32,
                child: FilterChip(
                  label: Text(
                    _prettify
                        ? openHandLocalizedText(
                            context,
                            zh: '已美化',
                            zhHant: '已美化',
                            en: 'Pretty',
                            fr: 'Formaté',
                            de: 'Formatiert',
                            ja: '整形済み',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '原样',
                            zhHant: '原樣',
                            en: 'Raw',
                            fr: 'Brut',
                            de: 'Roh',
                            ja: 'そのまま',
                          ),
                  ),
                  selected: _prettify,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // 查看原始源时美化按钮无意义，置灰。
                  onSelected: _viewingOriginal
                      ? null
                      : (v) {
                          setState(() => _prettify = v);
                          _resetSourceScrollPositions();
                          _pushCurrentToLsp();
                        },
                ),
              ),
              kOpenHandHGap6,
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
                        ? openHandLocalizedText(
                            context,
                            zh: 'LSP 已开',
                            zhHant: 'LSP 已開',
                            en: 'LSP on',
                            fr: 'LSP activé',
                            de: 'LSP an',
                            ja: 'LSP オン',
                          )
                        : 'LSP',
                  ),
                  selected: _lspEnabled,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => _toggleLsp(),
                ),
              ),
              kOpenHandHGap4,
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: 'LSP 设置',
                    zhHant: 'LSP 設定',
                    en: 'LSP settings',
                    fr: 'Paramètres LSP',
                    de: 'LSP-Einstellungen',
                    ja: 'LSP 設定',
                  ),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  onPressed: () => _showLspSettings(),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
              kOpenHandHGap8,
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await copyWebReverseTextToClipboard(
                      context: context,
                      text: source,
                      successBase: openHandCopiedLabel(context),
                      logTag: 'web_reverse_sources_panel',
                      logAction: '复制源代码',
                      successDuration: const Duration(seconds: 1),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '复制源码',
                      zhHant: '複製源碼',
                      en: 'Copy',
                      fr: 'Copier',
                      de: 'Kopieren',
                      ja: 'コピー',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              kOpenHandHGap6,
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: widget.controller.resumeDebugger,
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '继续运行',
                      zhHant: '繼續執行',
                      en: 'Resume',
                      fr: 'Reprendre',
                      de: 'Fortsetzen',
                      ja: '再開',
                    ),
                  ),
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
        style: const TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 11.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  String _shortenUrl(String url) {
    const maxLen = 64;
    if (url.length <= maxLen) return url;
    final tail = safeUtf16SuffixStart(url, url.length - maxLen + 3);
    return '...${url.substring(tail)}';
  }
}

/// 跨脚本代码搜索对话框：输入关键字 → controller.searchScriptsGlobal
/// 拉取所有 parsedScripts 的源码逐行 grep；命中点列表点击即关闭对话框
/// 把 (scriptId, line) 返回给 _SourcesPanelState 跳转 + 高亮。
class _SourcesGlobalSearchDialog extends StatefulWidget {
  const _SourcesGlobalSearchDialog({required this.controller});

  final WebReverseSessionController controller;

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
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.travel_explore_rounded, color: cs.primary),
                kOpenHandHGap10,
                Expanded(
                  child: TextField(
                    controller: _qCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _run(),
                    decoration: InputDecoration(
                      hintText: openHandLocalizedText(
                        context,
                        zh: '在所有已加载脚本里搜索…',
                        zhHant: '在所有已載入腳本裡搜尋…',
                        en: 'Search across loaded scripts…',
                        fr: 'Rechercher dans les scripts chargés…',
                        de: 'In geladenen Skripten suchen…',
                        ja: '読み込み済みスクリプトを検索…',
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                kOpenHandHGap8,
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
                        ? _webReverseDashSearchingLabel(context)
                        : openHandSearchLabel(context),
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
                          ? _webReverseDashSearchingLabel(context)
                          : openHandLocalizedText(
                              context,
                              zh: '输入关键字后按回车或点击搜索；命中按行展示，点击即跳转。',
                              zhHant: '輸入關鍵字後按 Enter 或點擊搜尋；命中按行展示，點擊即跳轉。',
                              en: 'Type a query and press Enter; click a hit to jump.',
                              fr: 'Saisissez une requête puis Entrée ; cliquez un résultat pour sauter.',
                              de: 'Suchbegriff eingeben und Enter drücken; Treffer anklicken zum Springen.',
                              ja: '検索語を入力して Enter。結果をクリックすると移動します。',
                            ),
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
                          style: const TextStyle(
                            fontFamily: kOpenHandMonospaceFontFamily,
                          ),
                        ),
                        subtitle: Text(
                          'L${h.line + 1}: ${h.preview}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: kOpenHandMonospaceFontFamily,
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
          buildWebReverseDialogFooter(
            context,
            leading: Text(
              openHandLocalizedText(
                context,
                zh: '命中 ${_hits.length} 条（上限 200）',
                zhHant: '命中 ${_hits.length} 條（上限 200）',
                en: '${_hits.length} hits (cap 200)',
                fr: '${_hits.length} résultats (max 200)',
                de: '${_hits.length} Treffer (max. 200)',
                ja: '${_hits.length} 件ヒット（上限 200）',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: openHandCloseLabel(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 调试器右侧栏：暂停时显示 Call Stack / Scope / Watch，未暂停时仅显示
/// Watch + 「点页面任何一行可触发暂停」提示。所有项随 controller.notify 自动
/// 刷新；evaluateWatch 内部会按 paused 状态自动切换 evaluateOnCallFrame /
/// Runtime.evaluate。AnimatedSize 控制展开收起。
class _DebuggerSideRail extends StatefulWidget {
  const _DebuggerSideRail({required this.controller, required this.width});
  final WebReverseSessionController controller;
  final double width;
  @override
  State<_DebuggerSideRail> createState() => _DebuggerSideRailState();
}

class _DebuggerSideRailState extends State<_DebuggerSideRail> {
  final TextEditingController _watchCtrl = TextEditingController();
  final Map<String, String> _watchValues = <String, String>{};
  int _selectedFrame = 0;
  bool _watchEvaluationRunning = false;
  bool _watchEvaluationQueued = false;
  String? _lastPauseFrameId;
  bool _hasPauseSnapshot = false;

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
    final paused = widget.controller.pausedState;
    final pauseFrameId = paused == null
        ? null
        : '${paused.callFrames.firstOrNull?['callFrameId'] ?? ''}';
    if (!_hasPauseSnapshot || pauseFrameId != _lastPauseFrameId) {
      _selectedFrame = 0;
      _lastPauseFrameId = pauseFrameId;
      _hasPauseSnapshot = true;
    }
    _requestWatchEvaluation();
    setState(() {});
  }

  void _requestWatchEvaluation() {
    _watchEvaluationQueued = true;
    if (_watchEvaluationRunning) return;
    unawaited(_drainWatchEvaluations());
  }

  Future<void> _drainWatchEvaluations() async {
    _watchEvaluationRunning = true;
    try {
      while (mounted && _watchEvaluationQueued) {
        _watchEvaluationQueued = false;
        final watches = widget.controller.watchExpressions;
        final values = <String, String>{};
        for (final watch in watches) {
          final result = await widget.controller.evaluateWatch(watch);
          if (!mounted) return;
          if (_watchEvaluationQueued) break;
          values[watch] = _formatRemote(result);
        }
        if (!mounted) return;
        if (_watchEvaluationQueued) continue;
        final activeWatches = watches.toSet();
        _watchValues.removeWhere(
          (expression, _) => !activeWatches.contains(expression),
        );
        _watchValues.addAll(values);
        setState(() {});
      }
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '刷新调试器 Watch', error, stack);
    } finally {
      _watchEvaluationRunning = false;
      if (mounted && _watchEvaluationQueued) {
        unawaited(_drainWatchEvaluations());
      }
    }
  }

  String _formatRemote(Map<String, Object?>? r) {
    if (r == null) return '<n/a>';
    if (r['type'] == 'error') return 'Error: ${r['description']}';
    final desc = r['description'] ?? r['value'];
    return '$desc';
  }

  void _addWatch() {
    final v = _watchCtrl.text.trim();
    if (v.isEmpty) return;
    if (!widget.controller.addWatchExpression(v)) {
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Watch 表达式过长或数量已达上限',
          zhHant: 'Watch 運算式過長或數量已達上限',
          en: 'The watch expression is too long or the limit was reached',
          fr: 'L’expression Watch est trop longue ou la limite est atteinte',
          de: 'Der Watch-Ausdruck ist zu lang oder das Limit ist erreicht',
          ja: 'Watch 式が長すぎるか、上限に達しています',
        ),
      );
      return;
    }
    _watchCtrl.clear();
    _requestWatchEvaluation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
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
                  borderRadius: kOpenHandBorderRadius10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pause_circle_filled_rounded,
                      size: 16,
                      color: cs.onErrorContainer,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '已暂停 · ${paused.reason}',
                          zhHant: '已暫停 · ${paused.reason}',
                          en: 'Paused · ${paused.reason}',
                          fr: 'En pause · ${paused.reason}',
                          de: 'Pausiert · ${paused.reason}',
                          ja: '一時停止 · ${paused.reason}',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '继续',
                        zhHant: '繼續',
                        en: 'Resume',
                        fr: 'Reprendre',
                        de: 'Fortsetzen',
                        ja: '再開',
                      ),
                      iconSize: 18,
                      onPressed: () => widget.controller.resumeDebugger(),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '单步跳过',
                        zhHant: '單步跳過',
                        en: 'Step over',
                        fr: 'Pas à pas principal',
                        de: 'Step over',
                        ja: 'ステップオーバー',
                      ),
                      iconSize: 18,
                      onPressed: () => widget.controller.stepOverDebugger(),
                      icon: const Icon(Icons.redo_rounded),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '单步进入',
                        zhHant: '單步進入',
                        en: 'Step into',
                        fr: 'Entrer',
                        de: 'Step into',
                        ja: 'ステップイン',
                      ),
                      iconSize: 18,
                      onPressed: () => widget.controller.stepIntoDebugger(),
                      icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '单步跳出',
                        zhHant: '單步跳出',
                        en: 'Step out',
                        fr: 'Sortir',
                        de: 'Step out',
                        ja: 'ステップアウト',
                      ),
                      iconSize: 18,
                      onPressed: () => widget.controller.stepOutDebugger(),
                      icon: const Icon(Icons.subdirectory_arrow_left_rounded),
                    ),
                  ],
                ),
              ),
            if (paused != null) ...[
              kOpenHandGap10,
              _RailCard(
                title: openHandLocalizedText(
                  context,
                  zh: '调用栈',
                  zhHant: '呼叫堆疊',
                  en: 'Call Stack',
                  fr: 'Pile d’appels',
                  de: 'Call Stack',
                  ja: 'コールスタック',
                ),
                icon: Icons.layers_rounded,
                child: Column(
                  children: [
                    for (var i = 0; i < frames.length; i++)
                      InkWell(
                        borderRadius: kOpenHandBorderRadius8,
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
                            borderRadius: kOpenHandBorderRadius8,
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
                              kOpenHandHGap6,
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
              kOpenHandGap10,
              _RailCard(
                title: openHandLocalizedText(
                  context,
                  zh: '作用域',
                  zhHant: '作用域',
                  en: 'Scope',
                  fr: 'Portée',
                  de: 'Scope',
                  ja: 'スコープ',
                ),
                icon: Icons.account_tree_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in scopeChain.whereType<Map>())
                      _ScopeSection(
                        controller: widget.controller,
                        scope: s.cast<String, Object?>(),
                      ),
                  ],
                ),
              ),
            ],
            kOpenHandGap10,
            _RailCard(
              title: openHandLocalizedText(
                context,
                zh: '观察',
                zhHant: '觀察',
                en: 'Watch',
                fr: 'Surveillance',
                de: 'Watch',
                ja: 'ウォッチ',
              ),
              icon: Icons.visibility_outlined,
              trailing: IconButton(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '全部重算',
                  zhHant: '全部重算',
                  en: 'Re-evaluate',
                  fr: 'Réévaluer',
                  de: 'Neu auswerten',
                  ja: '再評価',
                ),
                iconSize: 16,
                onPressed: _requestWatchEvaluation,
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
                            hintText: openHandLocalizedText(
                              context,
                              zh: '表达式（回车添加）',
                              zhHant: '表達式（Enter 新增）',
                              en: 'expression (Enter)',
                              fr: 'expression (Entrée)',
                              de: 'Ausdruck (Enter)',
                              ja: '式（Enter で追加）',
                            ),
                          ),
                          style: const TextStyle(
                            fontFamily: kOpenHandMonospaceFontFamily,
                            fontSize: 12,
                          ),
                          onSubmitted: (_) => _addWatch(),
                        ),
                      ),
                      kOpenHandHGap6,
                      IconButton(
                        onPressed: _addWatch,
                        iconSize: 18,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  kOpenHandGap6,
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
                          kOpenHandHGap4,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  w,
                                  style: const TextStyle(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontSize: 11.5,
                                  ),
                                ),
                                SelectableText(
                                  _watchValues[w] ?? '...',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
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
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            kOpenHandGap10,
            Text(
              openHandLocalizedText(
                context,
                zh: '更多断点（XHR / EventListener / DOM / CSP / 全局监听器）请打开「Breakpoints」标签页。',
                zhHant:
                    '更多斷點（XHR / EventListener / DOM / CSP / 全域監聽器）請打開「Breakpoints」分頁。',
                en: 'More breakpoint types in the Breakpoints tab.',
                fr: 'Autres types de points d’arrêt dans l’onglet Breakpoints.',
                de: 'Weitere Breakpoint-Typen im Tab Breakpoints.',
                ja: 'その他のブレークポイント種別は Breakpoints タブにあります。',
              ),
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
      decoration: webReverseSurfaceCardDecoration(cs, radius: 12),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              kOpenHandHGap6,
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
          kOpenHandGap6,
          Padding(padding: const EdgeInsets.only(right: 4), child: child),
        ],
      ),
    );
  }
}

/// Scope 卡片中单个 scope（local / closure / global）的展开行：第一次展开时
/// 通过 `Runtime.getProperties` 拉一次属性列表并缓存到 State。
class _ScopeSection extends StatefulWidget {
  const _ScopeSection({required this.controller, required this.scope});
  final WebReverseSessionController controller;
  final Map<String, Object?> scope;
  @override
  State<_ScopeSection> createState() => _ScopeSectionState();
}

class _ScopeSectionState extends State<_ScopeSection> {
  bool _expanded = false;
  bool _loading = false;
  List<Map<String, Object?>>? _props;
  int _loadSerial = 0;

  @override
  void didUpdateWidget(covariant _ScopeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldObjectId = (oldWidget.scope['object'] as Map?)?['objectId'];
    final objectId = (widget.scope['object'] as Map?)?['objectId'];
    if (!identical(oldWidget.controller, widget.controller) ||
        oldObjectId != objectId) {
      _loadSerial++;
      _expanded = false;
      _loading = false;
      _props = null;
    }
  }

  Future<void> _toggle() async {
    if (_expanded) {
      _loadSerial++;
      setState(() {
        _expanded = false;
        _loading = false;
      });
      return;
    }
    setState(() => _expanded = true);
    if (_props != null) return;
    final obj = widget.scope['object'] as Map?;
    final objectId = obj?['objectId'] as String?;
    if (objectId == null || objectId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final serial = ++_loadSerial;
    final scope = widget.scope;
    setState(() => _loading = true);
    final list = await widget.controller.runtimeGetProperties(
      objectId: objectId,
    );
    if (!mounted || serial != _loadSerial || !identical(widget.scope, scope)) {
      return;
    }
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
            borderRadius: kOpenHandBorderRadius6,
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
                  kOpenHandHGap4,
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
              child: OpenHandContentStateSwitcher(
                stateKey: _loading ? 'loading' : 'content',
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
                                    fontFamily: kOpenHandMonospaceFontFamily,
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
        : clipTextByCodeUnits(markdown!, 360, suffix: '…');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Material(
        elevation: 6,
        borderRadius: kOpenHandBorderRadius10,
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: OpenHandContentStateSwitcher(
            stateKey: loading ? 'loading' : 'content',
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
                      kOpenHandHGap8,
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
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// Cmd+P / Ctrl+P 快速打开脚本（类 VSCode/Chrome DevTools）。
// 输入纯文本 → 模糊匹配脚本 URL（basename 命中加权）。结尾 `:42` 跳到指定
// 行。↑↓ 移动高亮项，Enter 选中，Esc 关闭。仅做文件/行跳转；符号检索受限
// 于 CDP（要拉源码现取），暂不放进首屏。
class _SourcesQuickOpenDialog extends StatefulWidget {
  const _SourcesQuickOpenDialog({
    required this.controller,
    required this.currentScriptId,
  });
  final WebReverseSessionController controller;
  final String? currentScriptId;
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
      final n = optionalPositiveIntFromValue(tail);
      if (n != null) {
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
        duration: kOpenHandMotion120,
        curve: kOpenHandSwitchInCurve,
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
    return buildOpenHandDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius14,
      ),
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
                  hintText: openHandLocalizedText(
                    context,
                    zh: '快速打开脚本… 末尾加 :42 可跳到指定行',
                    zhHant: '快速打開腳本… 末尾加 :42 可跳到指定行',
                    en: 'Go to file… (suffix :42 jumps to line)',
                    fr: 'Ouvrir un fichier… (:42 saute à la ligne)',
                    de: 'Datei öffnen… (:42 springt zur Zeile)',
                    ja: 'ファイルを開く…（末尾 :42 で行へ移動）',
                  ),
                  prefixIcon: const Icon(Icons.flash_on_rounded, size: 16),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
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
                  openHandLocalizedText(
                    context,
                    zh: '将跳到第 $_gotoLine 行',
                    zhHant: '將跳到第 $_gotoLine 行',
                    en: 'Will jump to line $_gotoLine',
                    fr: 'Sautera à la ligne $_gotoLine',
                    de: 'Springt zu Zeile $_gotoLine',
                    ja: '$_gotoLine 行目へ移動します',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? OpenHandInlineEmptyState(
                      message: openHandLocalizedText(
                        context,
                        zh: '无匹配脚本',
                        zhHant: '無匹配腳本',
                        en: 'No matches',
                        fr: 'Aucun résultat',
                        de: 'Keine Treffer',
                        ja: '一致なし',
                      ),
                      dense: true,
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
                                kOpenHandHGap8,
                                Text(
                                  base.isEmpty ? '(anonymous)' : base,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: active ? cs.primary : cs.onSurface,
                                  ),
                                ),
                                kOpenHandHGap10,
                                Expanded(
                                  child: Text(
                                    dir,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: kOpenHandMonospaceFontFamily,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '↑/↓ 选择 · Enter 打开 · Esc 关闭',
                  zhHant: '↑/↓ 選擇 · Enter 開啟 · Esc 關閉',
                  en: '↑/↓ navigate · Enter open · Esc close',
                  fr: '↑/↓ naviguer · Enter ouvrir · Esc fermer',
                  de: '↑/↓ navigieren · Enter öffnen · Esc schließen',
                  ja: '↑/↓ 選択 · Enter 開く · Esc 閉じる',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
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

String _webReverseDashSearchingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '搜索中…',
    zhHant: '搜尋中…',
    en: 'Searching…',
    fr: 'Recherche…',
    de: 'Suche…',
    ja: '検索中…',
  );
}

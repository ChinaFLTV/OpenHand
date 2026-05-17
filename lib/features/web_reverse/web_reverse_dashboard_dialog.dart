import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/media_preview_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../ai/index.dart';
import 'web_reverse_launch_diagnosis.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_profile_actions.dart';
import 'web_reverse_screenshot_markup.dart';
import 'web_reverse_session_controller.dart';

part 'web_reverse_dashboard_dialog.network.part.dart';
part 'web_reverse_dashboard_dialog.console.part.dart';
part 'web_reverse_dashboard_dialog.detail.part.dart';
part 'web_reverse_dashboard_dialog.toolbar.part.dart';
part 'web_reverse_dashboard_dialog.panels.part.dart';
part 'web_reverse_dashboard_dialog.advanced.part.dart';
part 'web_reverse_dashboard_dialog.sources.part.dart';
part 'web_reverse_dashboard_dialog.browser.part.dart';

// ── 视觉常量 ───────────────────────────────────────────────────────────
// 工具栏所有元素统一高度 36，沿用 Material outlined 风格的胶囊形。
// 数据来源：Chrome DevTools 工具栏元素自身约 26-30px；这里做了桌面侧
// 略大一点的视觉，保证 macOS 上点击命中区充足。
const double _kToolbarHeight = 36;
const double _kToolbarRadius = 999;
const Duration _kSwitchDuration = Duration(milliseconds: 220);
const Curve _kSwitchInCurve = Curves.easeOutCubic;
const Curve _kSwitchOutCurve = Curves.easeInCubic;

/// Web 逆向 CDP 仪表盘弹窗。
///
/// 核心 tab：
///   - Overview: 关键统计大格子
///   - Network: Chrome DevTools Network 面板等价（过滤 / 搜索 / 节流 / 详情）
///   - Console: 控制台日志（按 level 过滤 + 搜索）
///
/// 占位 tab（点开引导用户使用浏览器原生 DevTools 的对应面板）：
///   - Performance / Memory / Application / Security / Recorder
///
/// 真正的 F12 全功能由「打开官方 DevTools」按钮拉起，这是 OpenHand 与
/// Chrome DevTools 1:1 对齐的物理学最优解：浏览器自身的 inspector.html
/// 即原生面板，无任何功能裁剪。
Future<void> showWebReverseDashboardDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required String sessionId,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WebReverseDashboardDialog(
      controller: controller,
      sessionId: sessionId,
    ),
  );
}

class _WebReverseDashboardDialog extends StatefulWidget {
  const _WebReverseDashboardDialog({
    required this.controller,
    required this.sessionId,
  });
  final WebReverseSessionController controller;
  final String sessionId;

  @override
  State<_WebReverseDashboardDialog> createState() =>
      _WebReverseDashboardDialogState();
}

enum _Tab {
  browser,
  overview,
  network,
  console,
  sources,
  performance,
  memory,
  application,
  security,
  recorder,
}

class _WebReverseDashboardDialogState
    extends State<_WebReverseDashboardDialog> {
  static const _kLastTabMetaKey = 'web_reverse_dashboard_last_tab';
  static const _kBrowserTabOrderMetaKey = 'web_reverse_browser_tab_order';
  static const _kBrowserTabUrlsMetaKey = 'web_reverse_browser_tab_urls';
  static const _kReplHistoryMetaKey = 'web_reverse_console_repl_history';
  static const _kBreakpointsMetaKey = 'web_reverse_sources_breakpoints';
  static const _kInterceptRulesMetaKey = 'web_reverse_intercept_rules';
  _Tab _tab = _Tab.network;

  // Network 面板状态
  String _networkFilter = '';
  _ResourceFilter _resourceFilter = _ResourceFilter.all;
  bool _cacheDisabled = false;
  WebReverseThrottlePreset _throttle = WebReverseThrottlePreset.none;
  CdpNetworkEntry? _selectedRequest;
  final TextEditingController _filterCtrl = TextEditingController();

  // dashboard 上次记录的请求计数；用于 AnimatedList 增量插入。
  int _lastNetworkSize = 0;
  // 上次 rebuild 时记录的 dashboard 关键计数 / 状态；只有这些值变化才整体
  // rebuild 头部 / toolbar，避免 60fps screencast 帧把 dashboard 拖进
  // setState 旋涡。
  int _lastConsoleSize = 0;
  int _lastErrorCount = 0;
  bool _lastIsRunning = false;
  String _lastErrMsg = '';
  // 上次记录的浏览器面板 tab 列表标识：targets 数量 / currentId 任一变化
  // 即让 _BrowserBody 整体 rebuild 拿到新 tab strip。
  int _lastTabsLen = 0;
  String? _lastCurTabId;
  final GlobalKey<AnimatedListState> _networkListKey =
      GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _lastNetworkSize = widget.controller.networkRequests.length;
    _lastConsoleSize = widget.controller.consoleMessages.length;
    _lastErrorCount = widget.controller.errorCount;
    _lastIsRunning = widget.controller.isRunning;
    _lastErrMsg = widget.controller.errorMessage ?? '';
    _lastTabsLen = widget.controller.pageTargets.length;
    _lastCurTabId = widget.controller.currentPageTargetId;
    // 读取上次离开 dashboard 时停在的 tab。会话维度持久化到 metadata，
    // 用 enum.name 序列化；解析失败 / 没记录时保持 _Tab.network 默认。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = context
          .read<AiSessionController>()
          .sessions
          .firstWhere(
            (s) => s.id == widget.sessionId,
            orElse: () => context.read<AiSessionController>().sessions.first,
          );
      final raw = session.metadata[_kLastTabMetaKey];
      if (raw is String && raw.isNotEmpty) {
        for (final t in _Tab.values) {
          if (t.name == raw) {
            setState(() => _tab = t);
            break;
          }
        }
      }
      // 应用上次记录的 tab 顺序。
      final orderRaw = session.metadata[_kBrowserTabOrderMetaKey];
      if (orderRaw is List) {
        final order = orderRaw.whereType<String>().toList(growable: false);
        if (order.isNotEmpty) widget.controller.applyPageTargetOrder(order);
      }
      // 恢复 REPL 命令历史。
      final replRaw = session.metadata[_kReplHistoryMetaKey];
      if (replRaw is List) {
        final hist = replRaw.whereType<String>().toList(growable: false);
        if (hist.isNotEmpty) widget.controller.replaceReplHistory(hist);
      }
      // 恢复网络拦截规则。
      final rulesRaw = session.metadata[_kInterceptRulesMetaKey];
      if (rulesRaw is List) {
        final rules = rulesRaw
            .whereType<Map>()
            .map((m) =>
                WebReverseInterceptRule.fromJson(Map<String, Object?>.from(m)))
            .toList(growable: false);
        if (rules.isNotEmpty) widget.controller.setInterceptRules(rules);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final ctrl = widget.controller;
    final newSize = ctrl.networkRequests.length;
    final newConsole = ctrl.consoleMessages.length;
    final newErr = ctrl.errorCount;
    final newRunning = ctrl.isRunning;
    final newErrMsg = ctrl.errorMessage ?? '';
    final newTabsLen = ctrl.pageTargets.length;
    final newCurTab = ctrl.currentPageTargetId;
    // 关键：screencast 帧抵达不会改变这些计数，所以这里就早退。让浏览器
    // 面板内的 [_ScreencastImage] 自行 AnimatedBuilder 局部 repaint。
    final dashboardDirty = newSize != _lastNetworkSize ||
        newConsole != _lastConsoleSize ||
        newErr != _lastErrorCount ||
        newRunning != _lastIsRunning ||
        newErrMsg != _lastErrMsg ||
        newTabsLen != _lastTabsLen ||
        newCurTab != _lastCurTabId;
    if (newSize > _lastNetworkSize) {
      // FIFO 淘汰时 networkRequests 头部会被砍掉，导致新条目实际索引小于 newSize-1；
      // 这里只对追加场景做 AnimatedList 的 insert，不去精细同步淘汰，依赖 ValueKey
      // 让 list 在被打断时安全 rebuild（_NetworkBody 在过滤变化时也会整体 rebuild）。
      final delta = newSize - _lastNetworkSize;
      final state = _networkListKey.currentState;
      if (state != null) {
        for (var i = 0; i < delta; i++) {
          state.insertItem(_lastNetworkSize + i, duration: _kSwitchDuration);
        }
      }
    }
    _lastNetworkSize = newSize;
    _lastConsoleSize = newConsole;
    _lastErrorCount = newErr;
    _lastIsRunning = newRunning;
    _lastErrMsg = newErrMsg;
    _lastTabsLen = newTabsLen;
    _lastCurTabId = newCurTab;
    if (dashboardDirty) setState(() {});
  }

  /// 让 part 文件能从外部触发 dashboard 重建（part 文件不能直接调 setState）。
  void rebuildFromExternal(VoidCallback mutate) {
    setState(mutate);
  }

  /// 切换 tab 并把选择持久化到 session metadata，下次打开 dashboard 自动恢复。
  void _setTab(_Tab next) {
    if (next == _tab) return;
    setState(() => _tab = next);
    // 异步写回 metadata，失败不阻塞 UI；merge 写入避免覆盖其它键。
    final ctrl = context.read<AiSessionController>();
    unawaited(ctrl.updateSessionMetadata(widget.sessionId, <String, Object?>{
      _kLastTabMetaKey: next.name,
    }));
  }

  /// 浏览器刚拉起时由 _BrowserBody 调用：把上次持久化的 URL 列表逐条
  /// `Page.navigate` / `createTarget` 恢复到当前浏览器实例。已有的第一个
  /// target 复用 navigate；其余全部 createTarget。单 target 超时 6s 兜底，
  /// 整体不阻塞 UI。
  Future<void> restoreBrowserTabs() async {
    if (!mounted) return;
    final session = context.read<AiSessionController>().sessions.firstWhere(
          (s) => s.id == widget.sessionId,
          orElse: () => context.read<AiSessionController>().sessions.first,
        );
    final urlsRaw = session.metadata[_kBrowserTabUrlsMetaKey];
    final orderRaw = session.metadata[_kBrowserTabOrderMetaKey];
    if (urlsRaw is! Map || urlsRaw.isEmpty) return;
    final order = orderRaw is List
        ? orderRaw.whereType<String>().toList(growable: false)
        : <String>[];
    final urls = <String, String>{
      for (final entry in urlsRaw.entries)
        '${entry.key}': '${entry.value}',
    };
    final wantUrls = order
        .map((id) => urls[id])
        .where((u) => u != null && u.isNotEmpty && !u.startsWith('about:'))
        .cast<String>()
        .toList(growable: false);
    if (wantUrls.isEmpty) return;
    final ctrl = widget.controller;
    final hasFirst = ctrl.pageTargets.isNotEmpty;
    if (hasFirst) {
      try {
        await ctrl.navigate(wantUrls.first).timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    for (var i = hasFirst ? 1 : 0; i < wantUrls.length; i++) {
      try {
        await ctrl
            .createPageTarget(url: wantUrls[i])
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
  }

  /// 持久化 console REPL 历史到 session metadata，控制台面板每次执行命令
  /// 都会调用一次。fire-and-forget 不阻塞 UI。
  void persistConsoleReplHistory() {
    if (!mounted) return;
    final session = context.read<AiSessionController>();
    unawaited(
      session.updateSessionMetadata(widget.sessionId, <String, Object?>{
        _kReplHistoryMetaKey: widget.controller.replHistory,
      }),
    );
  }

  /// 持久化 Sources tab 用户设过的断点。Sources 面板每次 set/remove 后调一次。
  void persistBreakpoints() {
    if (!mounted) return;
    final session = context.read<AiSessionController>();
    final bps = widget.controller.userBreakpoints
        .map((b) => <String, Object?>{'url': b.url, 'line': b.line})
        .toList(growable: false);
    unawaited(
      session.updateSessionMetadata(widget.sessionId, <String, Object?>{
        _kBreakpointsMetaKey: bps,
      }),
    );
  }

  /// 持久化网络拦截规则。规则编辑 dialog 保存时调一次。
  void persistInterceptRules() {
    if (!mounted) return;
    final session = context.read<AiSessionController>();
    final rules = widget.controller.interceptRules
        .map((r) => r.toJson())
        .toList(growable: false);
    unawaited(
      session.updateSessionMetadata(widget.sessionId, <String, Object?>{
        _kInterceptRulesMetaKey: rules,
      }),
    );
  }

  /// 浏览器从 dead 切回 alive 时调用：恢复持久化的断点（先 enableDebugger）。
  Future<void> restoreBreakpoints() async {
    if (!mounted) return;
    final session = context.read<AiSessionController>().sessions.firstWhere(
          (s) => s.id == widget.sessionId,
          orElse: () => context.read<AiSessionController>().sessions.first,
        );
    final raw = session.metadata[_kBreakpointsMetaKey];
    if (raw is! List || raw.isEmpty) return;
    await widget.controller.enableDebugger();
    final list = <({String url, int line})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final url = '${item['url'] ?? ''}';
      final line = (item['line'] as num?)?.toInt() ?? -1;
      if (url.isEmpty || line < 0) continue;
      list.add((url: url, line: line));
    }
    if (list.isNotEmpty) {
      await widget.controller.restoreBreakpoints(list);
    }
  }

  /// 持久化浏览器面板状态：当前 tab 顺序 + 每个 target 的最后 URL。下次
  /// 重启浏览器（会话 / Chrome 进程级）时上层用这个数据恢复用户操作场景。
  /// 给 [_BrowserBodyState] 通过 ancestor lookup 调用。
  Future<void> persistBrowserPanelState() async {
    if (!mounted) return;
    final ctrl = widget.controller;
    final order = ctrl.pageTargetOrder;
    // 尝试拉每个 target 的真实 URL；失败则用 snapshot 里的。控制总耗时
    // ≤ 500ms，超时即用 snapshot。
    final urls = <String, String>{};
    for (final t in ctrl.pageTargets) {
      urls[t.id] = t.url;
    }
    final session = context.read<AiSessionController>();
    unawaited(
      session.updateSessionMetadata(widget.sessionId, <String, Object?>{
        _kBrowserTabOrderMetaKey: order,
        _kBrowserTabUrlsMetaKey: urls,
      }),
    );
  }

  bool _isZh() =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ctrl = widget.controller;
    final isZh = _isZh();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Cmd+Shift+R / Ctrl+Shift+R 启停 Recorder。
        const SingleActivator(LogicalKeyboardKey.keyR,
            meta: true, shift: true): () => _toggleRecorder(ctrl),
        const SingleActivator(LogicalKeyboardKey.keyR,
            control: true, shift: true): () => _toggleRecorder(ctrl),
        // Shift + ? 打开快捷键速查面板。`?` 在大多数键盘上需要 shift+/，
        // SingleActivator 的 includeRepeats 默认 true 不影响这里。
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () =>
            _showShortcutsHelp(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: cs.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(24),
          child: ClipRRect(
            // Dialog 自带 shape 只裁切 Material 自身的背景；body 内的 Container
            // / Image / Stack 等会延伸到 Dialog 边缘，覆盖掉本来的圆角。
            // 用一层 ClipRRect 把所有 body 内容统一裁成圆角，右下角不再是
            // 尖角。
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 1180, maxHeight: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // 关键：所有子项横向拉到 Dialog 全宽，避免不同 tab 切换时
                // body 内容更窄导致 Column 把 toolbar 行整体回缩并重新居中
                // （Network 行能拉满工具条变左对齐；Console / 性能行 body 窄、
                // 工具条又默认 MainAxisSize.min，外层 stretch 会强制铺满）。
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme, cs, isZh),
                  Divider(height: 1, color: cs.outlineVariant),
                  AnimatedSize(
                  duration:
                      reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: _kSwitchInCurve,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : _kSwitchDuration,
                    switchInCurve: _kSwitchInCurve,
                    switchOutCurve: _kSwitchOutCurve,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1,
                        child: child,
                      ),
                    ),
                    child: (ctrl.errorMessage ?? '').trim().isNotEmpty
                        ? _DiagnosisBanner(
                            key: const ValueKey('diagnosis-banner'),
                            controller: ctrl,
                            isZh: isZh,
                            reduceMotion: reduceMotion,
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('diagnosis-banner-empty'),
                          ),
                  ),
                ),
                _buildToolbar(theme, cs, isZh, ctrl, reduceMotion),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : _kSwitchDuration,
                    switchInCurve: _kSwitchInCurve,
                    switchOutCurve: _kSwitchOutCurve,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.02),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<_Tab>(_tab),
                      child: _buildBody(theme, cs, isZh, ctrl, reduceMotion),
                    ),
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shift + ? 打开快捷键速查面板：分类列出 dashboard / 浏览器面板 /
  /// recorder / network 等所有键盘快捷键。
  void _showShortcutsHelp() {
    final isZh = _isZh();
    showDialog<void>(
      context: context,
      builder: (_) => _ShortcutsHelpDialog(isZh: isZh),
    );
  }

  Future<void> _toggleRecorder(WebReverseSessionController ctrl) async {
    if (ctrl.isRecording) {
      await ctrl.stopRecording();
    } else {
      await ctrl.startRecording();
    }
    if (!mounted) return;
    final isZh = _isZh();
    OpenHandSnackBar.showInfo(
      context,
      ctrl.isRecording
          ? (isZh ? '已开始录制（Cmd+Shift+R 再次按下停止）' : 'Recording started')
          : (isZh ? '已停止录制' : 'Recording stopped'),
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    final ctrl = widget.controller;
    final port = ctrl.cdpPort;
    final version = ctrl.browserVersion ?? '-';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.travel_explore_rounded,
                color: cs.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? 'Web 逆向调试面板' : 'Web Reverse Debugger',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$version · CDP :$port',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isZh ? '关闭' : 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
    bool reduceMotion,
  ) {
    return switch (_tab) {
      _Tab.browser => _BrowserBody(
          controller: ctrl,
          isZh: isZh,
        ),
      _Tab.overview => _OverviewBody(controller: ctrl, isZh: isZh),
      _Tab.network => _NetworkBody(
          state: this,
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.console => _ConsoleBody(
          controller: ctrl,
          filter: _networkFilter,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.sources => _SourcesPanel(
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.performance => _PerformancePanel(
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.memory => _MemoryPanel(
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.application => _ApplicationPanel(
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
      _Tab.security => _SecurityPanel(
          controller: ctrl,
          isZh: isZh,
        ),
      _Tab.recorder => _RecorderPanel(
          controller: ctrl,
          isZh: isZh,
          reduceMotion: reduceMotion,
        ),
    };
  }

  Future<void> _openOfficialDevTools(
    WebReverseSessionController ctrl,
  ) async {
    await _openOfficialDevToolsForController(context, ctrl, _isZh());
  }
}

/// 打开浏览器官方 DevTools 前端：先读 `/json/list` 拿 `devtoolsFrontendUrl`，
/// 再用平台命令打开。失败时降级到 `/json/list` 列表页 + SnackBar 提示。
/// 提取为顶层函数让 [_BrowserBody] 的右键菜单也能直接复用。
Future<void> _openOfficialDevToolsForController(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final port = ctrl.cdpPort;
  if (port == null) return;
  final messenger = ScaffoldMessenger.of(context);
  String? frontendUrl;
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/list'),
      );
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body);
      if (list is List) {
        Map<String, Object?>? best;
        for (final item in list.whereType<Map>()) {
          final m = Map<String, Object?>.from(item);
          final type = '${m['type'] ?? ''}';
          final url = '${m['url'] ?? ''}';
          if (type == 'page' && !url.startsWith('about:')) {
            best = m;
            break;
          }
        }
        best ??= list
            .whereType<Map>()
            .where((m) => m['type'] == 'page')
            .map((m) => Map<String, Object?>.from(m))
            .firstOrNull;
        best ??= list
            .whereType<Map>()
            .map((m) => Map<String, Object?>.from(m))
            .firstOrNull;
        final fe = best?['devtoolsFrontendUrl'] as String?;
        if (fe != null && fe.isNotEmpty) {
          frontendUrl =
              fe.startsWith('http') ? fe : 'http://127.0.0.1:$port$fe';
        }
      }
    } finally {
      client.close(force: true);
    }
  } catch (error, stack) {
    silentLog('web_reverse_dashboard_dialog', 'fetch /json/list', error, stack);
  }
  final url = frontendUrl ?? 'http://127.0.0.1:$port/json/list';
  try {
    if (Platform.isMacOS) {
      await Process.run('/usr/bin/open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  } catch (error, stack) {
    silentLog(
      'web_reverse_dashboard_dialog',
      'open devtools url',
      error,
      stack,
    );
  }
  if (!context.mounted) return;
  if (frontendUrl == null) {
    OpenHandSnackBar.showInfoOn(
      context,
      messenger,
      isZh
          ? '未找到可用的 DevTools 前端，已退到 /json/list 列表页'
          : 'No DevTools frontend found; opened /json/list fallback',
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = controller;
    final antiBot = ctrl.detectAntiBot();
    final stats = <(String, String)>[
      (isZh ? '请求数' : 'Requests', '${ctrl.networkRequests.length}'),
      (
        isZh ? '错误' : 'Errors',
        '${ctrl.networkRequests.where((e) => e.isError).length}'
      ),
      (
        isZh ? '控制台条目' : 'Console',
        '${ctrl.consoleMessages.length}'
      ),
      (
        isZh ? '运行状态' : 'Status',
        ctrl.isRunning ? (isZh ? '运行中' : 'Running') : (isZh ? '已停止' : 'Stopped')
      ),
      (isZh ? '浏览器' : 'Browser', ctrl.browserVersion ?? '-'),
      (isZh ? 'CDP 端口' : 'CDP Port', '${ctrl.cdpPort ?? '-'}'),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (antiBot.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.tertiary.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_moon_rounded,
                    color: cs.onTertiaryContainer, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isZh ? '检测到反爬指纹' : 'Anti-bot signals detected',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        antiBot.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onTertiaryContainer,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isZh
                            ? '此站点使用反爬服务，纯 curl/fetch 复现可能失败。建议保留浏览器流程，或为请求脚本叠加 cookie / TLS 指纹工具。'
                            : 'This site uses anti-bot services. Bare curl/fetch may fail; keep the browser flow or add cookie / TLS fingerprint tooling.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onTertiaryContainer,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.4,
          children: [
            for (final (label, value) in stats)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}


/// Dashboard 顶部的诊断 banner：当 [WebReverseSessionController.errorMessage]
/// 不为空时挂在 header 与 toolbar 之间，把 [WebReverseLaunchDiagnosis]
/// 的"现象 / 根因 / 建议"渲染成一张可操作卡片，提供：
///   · 清理冲突 profile（删 SingletonLock 等残留锁）
///   · 重置整个 profile（rm -rf user-data-dir，红字次要按钮）
///   · 复制完整原始报错
///   · 关闭 banner（清掉 errorMessage）
class _DiagnosisBanner extends StatefulWidget {
  const _DiagnosisBanner({
    super.key,
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  State<_DiagnosisBanner> createState() => _DiagnosisBannerState();
}

class _DiagnosisBannerState extends State<_DiagnosisBanner> {
  bool _expanded = true;
  bool _busy = false;
  // 重置后 60s 冷却：避免误连击两次造成"刚建好的空 profile 又被删"。
  Timer? _cooldownTimer;
  int _cooldownLeftSec = 0;
  bool get _onCooldown => _cooldownLeftSec > 0;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeftSec = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldownLeftSec--);
      if (_cooldownLeftSec <= 0) {
        t.cancel();
      }
    });
  }

  Future<void> _runProgressive() async {
    setState(() => _busy = true);
    final outcome = await runProgressiveProfileResolve(
      context,
      userDataDir: widget.controller.config.userDataDir,
      isZh: widget.isZh,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case ProgressiveProfileOutcome.reset:
        widget.controller.clearErrorMessage();
        _startCooldown();
      case ProgressiveProfileOutcome.cleaned:
        // 清理已生效，diagnosis 仍保留以便用户复盘；不进冷却。
        break;
      case ProgressiveProfileOutcome.nothingToDo:
      case ProgressiveProfileOutcome.resetCancelled:
      case ProgressiveProfileOutcome.failed:
        break;
    }
  }

  Future<void> _copyRaw(WebReverseLaunchDiagnosis diagnosis) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: diagnosis.fullText));
    if (!mounted) return;
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      widget.isZh ? '已复制原始报错' : 'Raw error copied',
      duration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final raw = widget.controller.errorMessage ?? '';
    final diagnosis = WebReverseLaunchDiagnosis.parse(raw);
    return AnimatedSize(
      duration:
          widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.report_gmailerrorred_rounded,
                    size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diagnosis.phenomenon,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: _expanded
                      ? (isZh ? '收起' : 'Collapse')
                      : (isZh ? '展开' : 'Expand'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: isZh ? '关闭诊断' : 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  onPressed: widget.controller.clearErrorMessage,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < diagnosis.causes.length; i++) ...[
                _CauseEntry(cause: diagnosis.causes[i], index: i, isZh: isZh),
                if (i != diagnosis.causes.length - 1)
                  const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // 渐进式按钮：先清理 → 仍有锁则引导重置。重置成功后自动 60s 冷却。
                  FilledButton.tonalIcon(
                    onPressed: (_busy || _onCooldown) ? null : _runProgressive,
                    icon: Icon(
                      _busy
                          ? Icons.hourglass_top_rounded
                          : (_onCooldown
                              ? Icons.timer_rounded
                              : Icons.auto_fix_high_rounded),
                      size: 16,
                    ),
                    label: Text(_busy
                        ? (isZh ? '处理中…' : 'Working…')
                        : _onCooldown
                            ? (isZh
                                ? '冷却中（${_cooldownLeftSec}s）'
                                : 'Cool-down ${_cooldownLeftSec}s')
                            : (isZh
                                ? '解决 Profile 冲突'
                                : 'Resolve profile lock')),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyRaw(diagnosis),
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: Text(isZh ? '复制原始报错' : 'Copy raw error'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CauseEntry extends StatelessWidget {
  const _CauseEntry({
    required this.cause,
    required this.index,
    required this.isZh,
  });

  final WebReverseLaunchCause cause;
  final int index;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isZh ? '可能根因 ${index + 1}' : 'Cause ${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cause.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cause.suggestion,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}


/// dashboard 全局快捷键速查面板：按 Shift+? 打开，分类列出所有热键。
/// macOS 上 Cmd 用 ⌘ 渲染；其它平台用 Ctrl。
class _ShortcutsHelpDialog extends StatelessWidget {
  const _ShortcutsHelpDialog({required this.isZh});

  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cmd = Platform.isMacOS ? '⌘' : 'Ctrl';
    final groups = <({String title, List<({String keys, String desc})> rows})>[
      (
        title: isZh ? 'Dashboard' : 'Dashboard',
        rows: [
          (
            keys: 'Shift + ?',
            desc: isZh ? '打开本面板' : 'Open this panel',
          ),
          (
            keys: '$cmd + Shift + R',
            desc: isZh ? '启停 Recorder' : 'Toggle Recorder',
          ),
        ],
      ),
      (
        title: isZh ? '浏览器面板' : 'Browser surface',
        rows: [
          (keys: '$cmd + T', desc: isZh ? '新标签页' : 'New tab'),
          (keys: '$cmd + W', desc: isZh ? '关闭当前标签页' : 'Close tab'),
          (keys: '$cmd + R', desc: isZh ? '刷新' : 'Reload'),
          (keys: '$cmd + Shift + R', desc: isZh ? '强制刷新' : 'Hard reload'),
          (keys: '$cmd + L', desc: isZh ? '聚焦地址栏' : 'Focus address bar'),
          (keys: '$cmd + F', desc: isZh ? '页面查找' : 'Find in page'),
          (keys: 'Esc', desc: isZh ? '关闭查找条' : 'Close find bar'),
          (keys: '$cmd + +', desc: isZh ? '放大' : 'Zoom in'),
          (keys: '$cmd + -', desc: isZh ? '缩小' : 'Zoom out'),
          (keys: '$cmd + 0', desc: isZh ? '复位 100%' : 'Zoom 100%'),
        ],
      ),
      (
        title: isZh ? '控制台' : 'Console',
        rows: [
          (keys: '↑ / ↓', desc: isZh ? '浏览历史命令' : 'Browse history'),
          (keys: 'Enter', desc: isZh ? '执行' : 'Run'),
        ],
      ),
      (
        title: isZh ? '通用' : 'General',
        rows: [
          (
            keys: isZh ? '右键' : 'Right-click',
            desc: isZh
                ? '浏览器面板上下文菜单（复制 / 粘贴 / 检查 / 框选导出 …）'
                : 'Browser surface context menu',
          ),
        ],
      ),
    ];
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.keyboard_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isZh ? '快捷键速查' : 'Keyboard shortcuts',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                      child: Text(
                        g.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    for (final r in g.rows)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              constraints: const BoxConstraints(minWidth: 110),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Text(
                                r.keys,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                r.desc,
                                style: theme.textTheme.bodySmall,
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
      ),
    );
  }
}

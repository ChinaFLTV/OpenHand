import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/media_preview_dialog.dart';
import 'web_reverse_launch_diagnosis.dart';
import 'web_reverse_profile_actions.dart';
import 'web_reverse_screenshot_markup.dart';
import 'web_reverse_session_controller.dart';

part 'web_reverse_dashboard_dialog.network.part.dart';
part 'web_reverse_dashboard_dialog.console.part.dart';
part 'web_reverse_dashboard_dialog.detail.part.dart';
part 'web_reverse_dashboard_dialog.toolbar.part.dart';
part 'web_reverse_dashboard_dialog.panels.part.dart';
part 'web_reverse_dashboard_dialog.advanced.part.dart';

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
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WebReverseDashboardDialog(controller: controller),
  );
}

class _WebReverseDashboardDialog extends StatefulWidget {
  const _WebReverseDashboardDialog({required this.controller});
  final WebReverseSessionController controller;

  @override
  State<_WebReverseDashboardDialog> createState() =>
      _WebReverseDashboardDialogState();
}

enum _Tab {
  overview,
  network,
  console,
  performance,
  memory,
  application,
  security,
  recorder,
}

class _WebReverseDashboardDialogState
    extends State<_WebReverseDashboardDialog> {
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
  final GlobalKey<AnimatedListState> _networkListKey =
      GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _lastNetworkSize = widget.controller.networkRequests.length;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final newSize = widget.controller.networkRequests.length;
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
    } else if (newSize < _lastNetworkSize) {
      // clearBuffers / FIFO：让 _NetworkBody 整体 rebuild 由 setState 处理。
    }
    _lastNetworkSize = newSize;
    setState(() {});
  }

  /// 让 part 文件能从外部触发 dashboard 重建（part 文件不能直接调 setState）。
  void rebuildFromExternal(VoidCallback mutate) {
    setState(mutate);
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
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: cs.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 760),
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
                if ((ctrl.errorMessage ?? '').trim().isNotEmpty)
                  _DiagnosisBanner(
                    controller: ctrl,
                    isZh: isZh,
                    reduceMotion: reduceMotion,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ctrl.isRecording
          ? (isZh ? '已开始录制（Cmd+Shift+R 再次按下停止）' : 'Recording started')
          : (isZh ? '已停止录制' : 'Recording stopped')),
      duration: const Duration(seconds: 2),
    ));
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
    final port = ctrl.cdpPort;
    if (port == null) return;
    // 直接打开 http://127.0.0.1:<port>/ 只会拿到 CDP 的 JSON list 页（一片空白）。
    // 真实的 DevTools 前端 URL 来自 `GET /json/list` 里每条 target 的
    // devtoolsFrontendUrl 字段，类似：
    //   /devtools/inspector.html?ws=127.0.0.1:9223/devtools/page/<id>
    // 拿到这个相对 URL 后拼上 `http://127.0.0.1:<port>` 才是 F12 全功能面板。
    final isZh = _isZh();
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
          // 优先 type=page 且非 about:blank；否则取第一个 page；最后兜底任意 target。
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
            frontendUrl = fe.startsWith('http')
                ? fe
                : 'http://127.0.0.1:$port$fe';
          }
        }
      } finally {
        client.close(force: true);
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'fetch /json/list',
        error,
        stack,
      );
    }
    // 找不到合适的 frontend URL 时降级回根目录，至少不让用户面对空白。
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
    if (!mounted) return;
    if (frontendUrl == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          isZh
              ? '未找到可用的 DevTools 前端，已退到 /json/list 列表页'
              : 'No DevTools frontend found; opened /json/list fallback',
        ),
        duration: const Duration(seconds: 3),
      ));
    }
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
    messenger.showSnackBar(SnackBar(
      content: Text(widget.isZh ? '已复制原始报错' : 'Raw error copied'),
      duration: const Duration(seconds: 1),
    ));
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
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
                ),
                IconButton(
                  tooltip: isZh ? '关闭诊断' : 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.controller.clearErrorMessage,
                  icon: const Icon(Icons.close_rounded, size: 18),
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

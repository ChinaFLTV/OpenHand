import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import 'web_reverse_session_controller.dart';

part 'web_reverse_dashboard_dialog.network.part.dart';
part 'web_reverse_dashboard_dialog.console.part.dart';
part 'web_reverse_dashboard_dialog.detail.part.dart';
part 'web_reverse_dashboard_dialog.toolbar.part.dart';
part 'web_reverse_dashboard_dialog.panels.part.dart';

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
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            _buildToolbar(theme, cs, isZh, ctrl, reduceMotion),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : _kSwitchDuration,
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
    final url = 'http://127.0.0.1:$port/';
    if (Platform.isMacOS) {
      await Process.run('/usr/bin/open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.4,
        children: [
          for (final (label, value) in stats)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    );
  }
}

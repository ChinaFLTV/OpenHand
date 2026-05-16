import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/ui/animated_dialog.dart';
import 'web_reverse_session_controller.dart';

/// Web 逆向 CDP 仪表盘弹窗。
///
/// 设计取舍：
/// - 这是 OpenHand 端的"调试控制面板"——展示 CDP 实时数据缓冲
///   （网络 / 控制台 / 概览 3 个 tab），并提供 disable cache、清空、
///   搜索、一键打开官方 DevTools 等控制按钮。
/// - 真正的 F12（Elements / Sources / Performance / Memory / Application
///   / Security / Recorder 等八大面板）由"打开官方 DevTools"按钮拉起，
///   它装载 `http://127.0.0.1:<port>/devtools/inspector.html?ws=...`，
///   即浏览器自身的 DevTools 前端，所有面板 100% 等价于 F12。
/// - 弹窗采用 AnimatedSwitcher 切 tab 内容、AppearOnce 列表项淡入，
///   tab 切换 220ms easeOutCubic，与项目动效语言保持一致。
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

enum _Tab { overview, network, console }

class _WebReverseDashboardDialogState
    extends State<_WebReverseDashboardDialog> {
  _Tab _tab = _Tab.network;
  String _filter = '';
  bool _cacheDisabled = false;
  final TextEditingController _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            _buildToolbar(theme, cs, isZh, ctrl),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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
                child: _buildBody(theme, cs, isZh, ctrl),
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

  Widget _buildToolbar(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          for (final t in _Tab.values) ...[
            _TabPill(
              label: _tabLabel(t, isZh),
              icon: _tabIcon(t),
              count: _tabBadgeCount(t),
              active: _tab == t,
              onTap: () => setState(() => _tab = t),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _filterCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: isZh ? '搜索 URL / 文本' : 'Search URL / text',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isZh ? '禁用浏览器缓存（仅当前 tab）' : 'Disable browser cache',
            child: FilterChip(
              label: Text(isZh ? '禁用缓存' : 'Disable cache'),
              selected: _cacheDisabled,
              onSelected: (v) async {
                setState(() => _cacheDisabled = v);
                await ctrl.setCacheDisabled(v);
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: isZh ? '清空当前缓冲' : 'Clear buffers',
            child: IconButton(
              onPressed: ctrl.clearBuffers,
              icon: const Icon(Icons.cleaning_services_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: isZh ? '立即导出 HAR' : 'Export HAR now',
            child: IconButton(
              onPressed: () async {
                final path = await ctrl.exportHarNow();
                if (!mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(SnackBar(
                  content: Text(path == null
                      ? (isZh ? 'HAR 导出失败' : 'HAR export failed')
                      : (isZh ? 'HAR 已导出: $path' : 'HAR exported: $path')),
                  duration: const Duration(seconds: 3),
                ));
              },
              icon: const Icon(Icons.archive_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: isZh
                ? '在系统浏览器中打开官方 DevTools（F12 等价）'
                : 'Open native DevTools (F12 equivalent)',
            child: FilledButton.tonalIcon(
              onPressed: () => _openOfficialDevTools(ctrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(isZh ? '打开官方 DevTools' : 'Open DevTools'),
            ),
          ),
        ],
      ),
    );
  }

  String _tabLabel(_Tab t, bool isZh) => switch (t) {
    _Tab.overview => isZh ? '概览' : 'Overview',
    _Tab.network => isZh ? '网络' : 'Network',
    _Tab.console => isZh ? '控制台' : 'Console',
  };

  IconData _tabIcon(_Tab t) => switch (t) {
    _Tab.overview => Icons.dashboard_rounded,
    _Tab.network => Icons.swap_horiz_rounded,
    _Tab.console => Icons.terminal_rounded,
  };

  int? _tabBadgeCount(_Tab t) {
    final c = widget.controller;
    return switch (t) {
      _Tab.overview => null,
      _Tab.network => c.networkRequests.length,
      _Tab.console => c.consoleMessages.length,
    };
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
  ) {
    return KeyedSubtree(
      key: ValueKey<_Tab>(_tab),
      child: switch (_tab) {
        _Tab.overview => _OverviewBody(controller: ctrl, isZh: isZh),
        _Tab.network => _NetworkBody(
            controller: ctrl,
            filter: _filter,
            isZh: isZh,
          ),
        _Tab.console => _ConsoleBody(
            controller: ctrl,
            filter: _filter,
            isZh: isZh,
          ),
      },
    );
  }

  Future<void> _openOfficialDevTools(WebReverseSessionController ctrl) async {
    final port = ctrl.cdpPort;
    if (port == null) return;
    // /json/list 第一项的 devtoolsFrontendUrl 已经是 inspector.html?ws=...
    // 直接用 port + /json 让浏览器自己解析最新一条 page target。
    final url = 'http://127.0.0.1:$port/';
    if (Platform.isMacOS) {
      await Process.run('/usr/bin/open', [url]);
    }
  }
}

/// 顶部 tab 胶囊。active 时填充 primary 色，count 角标自然刷新。
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: active ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Container(
                      key: ValueKey<int>(count!),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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

class _NetworkBody extends StatelessWidget {
  const _NetworkBody({
    required this.controller,
    required this.filter,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final String filter;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = controller.networkRequests;
    final filtered = filter.isEmpty
        ? all
        : all
            .where(
              (e) => e.url.toLowerCase().contains(filter.toLowerCase()) ||
                  e.method.toLowerCase().contains(filter.toLowerCase()),
            )
            .toList(growable: false);
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isZh
                ? '暂无网络请求。在浏览器中操作页面后此处会实时刷新。'
                : 'No network requests yet. Interact with the page to populate this view.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (_, idx) {
        final e = filtered[filtered.length - 1 - idx];
        final color = e.isError
            ? cs.errorContainer
            : (e.statusCode != null && e.statusCode! >= 300
                ? cs.tertiaryContainer
                : cs.surfaceContainerHigh);
        final onColor = e.isError
            ? cs.onErrorContainer
            : (e.statusCode != null && e.statusCode! >= 300
                ? cs.onTertiaryContainer
                : cs.onSurface);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(ClipboardData(text: e.url));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(isZh ? '已复制 URL' : 'URL copied'),
                duration: const Duration(seconds: 1),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      e.method,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: onColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      e.statusCode?.toString() ?? (e.failed ? 'ERR' : '...'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: onColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 78,
                    child: Text(
                      e.resourceType,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: onColor,
                      ),
                    ),
                  ),
                  if (e.fromCache)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.cached_rounded,
                          size: 14, color: onColor.withValues(alpha: 0.6)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody({
    required this.controller,
    required this.filter,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final String filter;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = controller.consoleMessages;
    final filtered = filter.isEmpty
        ? all
        : all
            .where((e) => e.text.toLowerCase().contains(filter.toLowerCase()))
            .toList(growable: false);
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isZh ? '暂无控制台输出。' : 'No console output yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (_, idx) {
        final e = filtered[filtered.length - 1 - idx];
        final color = switch (e.level) {
          'error' => cs.errorContainer,
          'warning' => cs.tertiaryContainer,
          _ => cs.surfaceContainerHigh,
        };
        final onColor = switch (e.level) {
          'error' => cs.onErrorContainer,
          'warning' => cs.onTertiaryContainer,
          _ => cs.onSurface,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    e.level.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: onColor.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    e.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: onColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

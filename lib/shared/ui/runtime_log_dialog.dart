import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/support/silent_log.dart';
import '../db/atomic_file_operations.dart';
import '../util/localized_text.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'auto_follow_scroll_guard.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_clipboard.dart';
import 'openhand_console_log_panel.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_snack_bar.dart';

/// 运行时日志查看器。日志来源由调用方提供，组件只负责展示与导出。
///
/// [listenable] 的通知会触发有界刷新，短时间内的连续输出会合并处理；定时器作为
/// 兜底，每秒检查一次 revision，避免底层进程输出没有主动通知 UI 时日志停留在旧
/// 快照。列表只保留调用方提供的有界日志，不在弹窗内复制无限增长的数据。
class _OpenHandRuntimeLogDialog extends StatefulWidget {
  const _OpenHandRuntimeLogDialog({
    required this.title,
    required this.listenable,
    required this.logs,
    required this.revision,
    required this.clearLogs,
    this.fileNamePrefix = 'openhand-runtime',
    this.emptyPlaceholder,
  });

  final String title;
  final Listenable listenable;
  final List<String> Function() logs;
  final int Function() revision;
  final VoidCallback clearLogs;
  final String fileNamePrefix;
  final Widget? emptyPlaceholder;

  @override
  State<_OpenHandRuntimeLogDialog> createState() =>
      _OpenHandRuntimeLogDialogState();
}

class _OpenHandRuntimeLogDialogState extends State<_OpenHandRuntimeLogDialog> {
  static const Duration _refreshInterval = Duration(seconds: 1);
  static const Duration _renderDebounce = Duration(milliseconds: 120);

  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final OpenHandDebouncer _renderDebouncer = OpenHandDebouncer(
    delay: _renderDebounce,
  );
  Timer? _refreshTimer;
  List<String>? _cachedLogs;
  int _cachedLogsRevision = -1;
  int _lastRevision = -1;
  bool _follow = true;
  bool _refreshing = true;
  bool _exporting = false;
  bool _clearScheduled = false;

  @override
  void initState() {
    super.initState();
    _lastRevision = widget.revision();
    widget.listenable.addListener(_refresh);
    _refreshTimer = startNonOverlappingPeriodicTimer(
      _refreshInterval,
      (_) => _refresh(),
      onError: (error, stack) =>
          silentLog('runtime_log_dialog', '刷新运行日志', error, stack),
    );
    _scheduleFollow(animated: false);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_refresh);
    _refreshTimer?.cancel();
    _renderDebouncer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _OpenHandRuntimeLogDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final listenableChanged = !identical(
      oldWidget.listenable,
      widget.listenable,
    );
    if (listenableChanged) {
      oldWidget.listenable.removeListener(_refresh);
      widget.listenable.addListener(_refresh);
    }
    if (listenableChanged || oldWidget.revision != widget.revision) {
      _cachedLogs = null;
      _cachedLogsRevision = -1;
      _lastRevision = widget.revision();
      _refreshing = true;
      _renderDebouncer.scheduleIfIdle(_flushRefresh);
      _scheduleFollow(animated: false);
    }
  }

  void _refresh() {
    if (!mounted) return;
    final revision = widget.revision();
    if (revision == _lastRevision) return;
    _lastRevision = revision;
    _refreshing = true;
    _renderDebouncer.scheduleIfIdle(_flushRefresh);
  }

  void _flushRefresh() {
    if (!mounted) return;
    final revision = widget.revision();
    if (revision == _cachedLogsRevision && !_refreshing) return;
    setState(() {
      _cachedLogs = widget.logs();
      _cachedLogsRevision = revision;
      _lastRevision = revision;
      _refreshing = false;
    });
    if (_follow) _scheduleFollow();
  }

  void _scheduleFollow({bool animated = true}) {
    if (_clearScheduled) return;
    _clearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearScheduled = false;
      if (!mounted || !_follow) return;
      _scrollGuard.followToStart(
        _scrollController,
        animated: animated,
        animationDuration: openHandMotionDuration(context, kOpenHandMotion220),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revision = widget.revision();
    if (_cachedLogs == null || _cachedLogsRevision != revision) {
      _cachedLogs = widget.logs();
      _cachedLogsRevision = revision;
      _lastRevision = revision;
      _refreshing = false;
    }
    final logs = _cachedLogs!;
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightStandard,
      minHeight: 440,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
            child: Row(
              children: [
                Icon(Icons.article_outlined, color: theme.colorScheme.primary),
                kOpenHandHGap10,
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: _follow
                          ? _localized(context, '取消自动跟随')
                          : _localized(context, '自动跟随到底部'),
                      onPressed: () {
                        setState(() => _follow = !_follow);
                        if (_follow) _scheduleFollow();
                      },
                      icon: Icon(
                        _follow
                            ? Icons.vertical_align_bottom_rounded
                            : Icons.vertical_align_center_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: _localized(context, '复制日志'),
                      onPressed: logs.isEmpty ? null : () => _copy(logs),
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    IconButton(
                      tooltip: _localized(context, '导出日志'),
                      onPressed: _exporting || logs.isEmpty ? null : _export,
                      icon: _exporting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt_rounded),
                    ),
                    IconButton(
                      tooltip: _localized(context, '清屏'),
                      onPressed: logs.isEmpty ? null : _clear,
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                    IconButton(
                      tooltip: openHandCloseLabel(context),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RepaintBoundary(
              child: OpenHandSafeScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: OpenHandConsoleLogPanel(
                  lineCount: logs.length,
                  lineAt: (index) => logs[index],
                  controller: _scrollController,
                  onNotification: _scrollGuard.handleNotification,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  borderRadius: BorderRadius.zero,
                  lineSpacing: 2,
                  emptyPlaceholder:
                      widget.emptyPlaceholder ??
                      Text(
                        _localized(context, '暂无运行日志，等待组件输出。'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: OpenHandConsolePalette.muted,
                          fontFamily: 'monospace',
                        ),
                      ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _follow
                      ? Icons.sync_rounded
                      : Icons.pause_circle_outline_rounded,
                  size: 15,
                  color: _follow
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap7,
                Expanded(
                  child: Text(
                    _follow
                        ? _localized(context, '自动刷新并跟随最新日志')
                        : _localized(context, '自动刷新已开启，已暂停自动跟随'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  _localized(context, '${logs.length} 行'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _localized(BuildContext context, String zh) {
    final english = switch (zh) {
      '取消自动跟随' => 'Stop following',
      '自动跟随到底部' => 'Follow latest logs',
      '复制日志' => 'Copy logs',
      '导出日志' => 'Export logs',
      '清屏' => 'Clear display',
      '暂无运行日志，等待组件输出。' => 'No runtime logs yet.',
      '自动刷新并跟随最新日志' => 'Auto-refresh and follow latest logs',
      '自动刷新已开启，已暂停自动跟随' => 'Auto-refresh is on; following is paused',
      '日志已复制到剪贴板' => 'Logs copied to clipboard',
      '日志显示已清空' => 'Log display cleared',
      _ when zh.endsWith(' 行') => '${zh.substring(0, zh.length - 2)} lines',
      _ when zh.startsWith('日志已导出到 ') =>
        'Logs exported to ${zh.substring('日志已导出到 '.length)}',
      _ when zh.startsWith('日志导出失败') =>
        'Log export failed. Please try again: ${zh.substring('日志导出失败，请稍后重试：'.length)}',
      _ => zh,
    };
    return openHandLocalizedText(
      context,
      zh: zh,
      zhHant: zh,
      en: english,
      fr: english,
      de: english,
      ja: english,
    );
  }

  Future<void> _copy(List<String> logs) async {
    await copyOpenHandTextToClipboard(
      logTag: 'runtime_log_dialog',
      context: context,
      text: logs.join('\n'),
      successMessage: _localized(context, '日志已复制到剪贴板'),
      logAction: '复制运行日志',
    );
  }

  void _clear() {
    widget.clearLogs();
    final revision = widget.revision();
    if (mounted) {
      setState(() {
        _cachedLogs = const <String>[];
        _cachedLogsRevision = revision;
        _lastRevision = revision;
        _refreshing = false;
      });
    }
    showOpenHandSuccessSnack(context, _localized(context, '日志显示已清空'));
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final stamp = DateTime.now()
        .toLocal()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    try {
      final location = await getSaveLocation(
        suggestedName: '${widget.fileNamePrefix}-$stamp.log',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'Log', extensions: <String>['log', 'txt']),
        ],
      );
      if (location == null) return;
      await writeFileAtomically(
        File(location.path),
        '${widget.logs().join('\n')}\n',
      );
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        _localized(context, '日志已导出到 ${location.path}'),
        maxLines: 2,
      );
    } catch (error, stack) {
      silentLog('runtime_log_dialog', '导出运行日志', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        _localized(context, '日志导出失败，请稍后重试：$error'),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// 显示运行日志查看弹窗，统一采用全局弹窗动画配置。
Future<void> showOpenHandRuntimeLogDialog({
  required BuildContext context,
  required String title,
  required Listenable listenable,
  required List<String> Function() logs,
  required int Function() revision,
  required VoidCallback clearLogs,
  String fileNamePrefix = 'openhand-runtime',
  Widget? emptyPlaceholder,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OpenHandRuntimeLogDialog(
      title: title,
      listenable: listenable,
      logs: logs,
      revision: revision,
      clearLogs: clearLogs,
      fileNamePrefix: fileNamePrefix,
      emptyPlaceholder: emptyPlaceholder,
    ),
  );
}

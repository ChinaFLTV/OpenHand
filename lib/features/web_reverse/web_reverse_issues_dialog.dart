/// Issues 面板：订阅 CDP `Audits.issueAdded`，把页面真实存在的合规 /
/// 兼容性 / 安全 / Mixed Content / SameSite / CORS / Quirks Mode 等问题
/// 按类别汇总展示。开启后边浏览边采集，关闭弹窗仍保留缓冲，下次打开
/// 直接看历史。
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/serial_task_queue.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_cdp_client.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

// 进程级缓冲，跨弹窗保留。每次 controller 切换不清空——刻意保留多会话证据。
final ListQueue<_IssueEntry> _issueBuffer = ListQueue<_IssueEntry>();
StreamSubscription<CdpEvent>? _issueGlobalSub;
String? _issueBindingKey;
const int _maxPendingIssueBindings = 16;
final SerialTaskQueue _issueBindingQueue = SerialTaskQueue(
  maxPendingTasks: _maxPendingIssueBindings,
);
bool _issueDomainEnabled = false;
const Duration _issueEnableTimeout = Duration(seconds: 5);
const int _maxIssueEntries = 500;
const int _maxIssueBufferCharacters = 8 * 1024 * 1024;
const int _maxIssueCodeCharacters = 256;
const int _maxIssueBriefCharacters = 2048;
const int _maxIssueJsonPreviewCharacters = 64 * 1024;
int _issueBufferCharacters = 0;

Future<void> showWebReverseIssuesDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) async {
  final bindingKey = await _bindIssueStream(controller);
  var domainEnabled = false;
  if (controller.isBrowserAlive) {
    try {
      final res = await controller
          .sendRawCdp(method: 'Audits.enable')
          .timeout(_issueEnableTimeout);
      domainEnabled = res?['error'] == null;
    } catch (error, stack) {
      silentLog('web_reverse_issues_dialog', '启用 Audits 域', error, stack);
    }
  }
  if (_issueBindingKey == bindingKey) {
    _issueDomainEnabled = domainEnabled;
  }

  if (!context.mounted) return;
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _IssuesDialog(controller: controller),
  );
}

Future<String> _bindIssueStream(WebReverseSessionController controller) {
  final bindingKey =
      '${identityHashCode(controller)}:${controller.artifactsRootDir}:${controller.cdpConnectionGeneration}';
  return _issueBindingQueue.enqueue(() async {
    if (_issueBindingKey != bindingKey) {
      await _cancelIssueSubscription(_issueGlobalSub, '替换全局页面问题订阅');
      _issueGlobalSub = null;
      _issueBindingKey = bindingKey;
      _issueDomainEnabled = false;
    }
    _issueGlobalSub ??= controller.rawCdpEvents.listen(
      _handleIssueEvent,
      onDone: () => _resetIssueBinding(bindingKey),
      onError: (Object error, StackTrace stack) {
        silentLog('web_reverse_issues_dialog', '读取页面问题事件流', error, stack);
        _resetIssueBinding(bindingKey);
      },
      cancelOnError: true,
    );
    return bindingKey;
  });
}

void _resetIssueBinding(String bindingKey) {
  if (_issueBindingKey != bindingKey) return;
  final sub = _issueGlobalSub;
  _issueGlobalSub = null;
  _issueBindingKey = null;
  _issueDomainEnabled = false;
  unawaited(_cancelIssueSubscription(sub, '重置全局页面问题订阅'));
}

Future<void> _cancelIssueSubscription(
  StreamSubscription<CdpEvent>? subscription,
  String where,
) async {
  await cancelStreamSubscriptionBounded<CdpEvent>(
    subscription,
    onError: (error, stack) =>
        silentLog('web_reverse_issues_dialog', where, error, stack),
  );
}

void _handleIssueEvent(CdpEvent ev) {
  if (ev.method != 'Audits.issueAdded') return;
  try {
    final issue = optionalStringKeyedMapFromValue(ev.params['issue']);
    if (issue == null) return;
    final code = clipText(
      stringFromValue(issue['code'], fallback: 'Unknown'),
      _maxIssueCodeCharacters,
      suffix: '',
    );
    final brief = clipText(
      _issueBrief(stringKeyedMapFromValue(issue['details'])),
      _maxIssueBriefCharacters,
      suffix: '',
    );
    final rawJson = _retainedIssueJson(issue);
    final entry = _IssueEntry(
      ts: DateTime.now(),
      code: code,
      brief: brief,
      rawJson: rawJson,
    );
    _issueBuffer.addFirst(entry);
    _issueBufferCharacters += entry.retainedCharacters;
    while (_issueBuffer.length > _maxIssueEntries ||
        _issueBufferCharacters > _maxIssueBufferCharacters) {
      _issueBufferCharacters -= _issueBuffer.removeLast().retainedCharacters;
    }
  } catch (error, stack) {
    silentLog('web_reverse_issues_dialog', '归一化页面问题事件', error, stack);
  }
}

String _retainedIssueJson(Map<String, Object?> issue) {
  final encoded = prettyPrintJson(issue);
  if (encoded.length <= _maxIssueJsonPreviewCharacters) return encoded;
  return prettyPrintJson(<String, Object?>{
    '已截断': true,
    '原始字符数': encoded.length,
    '预览': clipText(encoded, _maxIssueJsonPreviewCharacters, suffix: ''),
  });
}

String _issueBrief(Map<String, Object?> details) {
  for (final detail in details.values) {
    if (detail is! Map) continue;
    final detailMap = stringKeyedMapFromValue(detail);
    final request = stringKeyedMapFromValue(detailMap['request']);
    final frame = stringKeyedMapFromValue(detailMap['frame']);
    final url = optionalStringFromValue(
      detailMap['url'] ?? request['url'] ?? frame['url'],
    );
    if (url != null) return url;
    final description = optionalStringFromValue(detailMap['description']);
    if (description != null) return description;
  }
  return '';
}

class _IssueEntry {
  _IssueEntry({
    required this.ts,
    required this.code,
    required this.brief,
    required this.rawJson,
  });
  final DateTime ts;
  final String code;
  final String brief;
  final String rawJson;

  int get retainedCharacters => code.length + brief.length + rawJson.length;
}

class _IssuesDialog extends StatefulWidget {
  const _IssuesDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_IssuesDialog> createState() => _IssuesDialogState();
}

class _IssuesDialogState extends State<_IssuesDialog> {
  late final VoidCallback _rebuild;
  Timer? _refreshTicker;
  String _filter = '';
  String? _focusedCode;
  int _expandedIndex = -1;

  @override
  void initState() {
    super.initState();
    // buffer 在全局变量里被 listener 写入，dialog 自身只需要定时 rebuild。
    _rebuild = () {
      if (mounted) setState(() {});
    };
    _refreshTicker = startSafePeriodicTimer(
      const Duration(milliseconds: 800),
      (_) => _rebuild(),
    );
  }

  @override
  void dispose() {
    _refreshTicker?.cancel();
    super.dispose();
  }

  List<_IssueEntry> get _visible {
    final lowered = _filter.toLowerCase();
    return _issueBuffer
        .where((e) {
          if (_focusedCode != null && e.code != _focusedCode) return false;
          if (lowered.isEmpty) return true;
          if (e.code.toLowerCase().contains(lowered)) return true;
          return e.brief.toLowerCase().contains(lowered);
        })
        .toList(growable: false);
  }

  Map<String, int> get _grouped {
    final m = <String, int>{};
    for (final e in _issueBuffer) {
      m[e.code] = (m[e.code] ?? 0) + 1;
    }
    return m;
  }

  Color _colorOf(String code, ColorScheme cs) {
    if (code.contains('Security') || code.contains('MixedContent')) {
      return cs.error;
    }
    if (code.contains('Cookie') ||
        code.contains('SameSite') ||
        code.contains('Cors')) {
      return cs.tertiary;
    }
    if (code.contains('Deprecation') || code.contains('Quirks')) {
      return cs.secondary;
    }
    return cs.primary;
  }

  Future<void> _copyJson(_IssueEntry e) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: e.rawJson,
      successBase:
          AppLocalizations.of(context)?.webReverseIssuesCopied ??
          'Issue JSON copied',
      logTag: 'web_reverse_issues_dialog',
    );
  }

  void _clear() {
    _issueBuffer.clear();
    _issueBufferCharacters = 0;
    _focusedCode = null;
    _expandedIndex = -1;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final visible = _visible;
    final grouped = _grouped;

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.report_problem_rounded,
            iconColor: cs.error,
            title:
                AppLocalizations.of(context)?.webReverseIssuesTitle ?? 'Issues',
            subtitle:
                AppLocalizations.of(context)?.webReverseIssuesSubtitle ??
                'Audits.issueAdded · live aggregator',
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  '${_issueBuffer.length}',
                  style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip:
                    AppLocalizations.of(context)?.webReverseIssuesClearBuffer ??
                    'Clear buffer',
                onPressed: _issueBuffer.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
            ],
            closeTooltip:
                AppLocalizations.of(context)?.webReverseIssuesClose ?? 'Close',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText:
                          AppLocalizations.of(
                            context,
                          )?.webReverseIssuesFilterHint ??
                          'Filter by code / URL / description…',
                      border: const OutlineInputBorder(
                        borderRadius: kOpenHandBorderRadius10,
                      ),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                if (_focusedCode != null) ...[
                  kOpenHandHGap8,
                  InputChip(
                    label: Text(_focusedCode!),
                    onDeleted: () => setState(() => _focusedCode = null),
                  ),
                ],
              ],
            ),
          ),
          if (grouped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in grouped.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          selected: _focusedCode == entry.key,
                          label: Text('${entry.key} · ${entry.value}'),
                          onSelected: (sel) => setState(() {
                            _focusedCode = sel ? entry.key : null;
                          }),
                          avatar: CircleAvatar(
                            radius: 5,
                            backgroundColor: _colorOf(entry.key, cs),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? OpenHandInlineEmptyState(
                    icon: Icons.verified_rounded,
                    dense: true,
                    message: _issueBuffer.isEmpty
                        ? (AppLocalizations.of(
                                context,
                              )?.webReverseIssuesEmptyBuffer ??
                              'No issues reported yet. Interact with the page.')
                        : (AppLocalizations.of(
                                context,
                              )?.webReverseIssuesNoMatch ??
                              'No matching issue.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => kOpenHandGap6,
                    itemBuilder: (_, i) {
                      final e = visible[i];
                      final brief = e.brief;
                      final color = _colorOf(e.code, cs);
                      final expanded = _expandedIndex == i;
                      return AnimatedContainer(
                        duration: openHandMotionDurationMs(context, 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: kOpenHandBorderRadius12,
                          border: Border(
                            left: BorderSide(color: color, width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.code,
                                    style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                                Text(
                                  _fmtTs(e.ts),
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip:
                                      AppLocalizations.of(
                                        context,
                                      )?.webReverseIssuesCopyJson ??
                                      'Copy JSON',
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () => _copyJson(e),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: expanded
                                      ? (AppLocalizations.of(
                                              context,
                                            )?.webReverseIssuesCollapse ??
                                            'Collapse')
                                      : (AppLocalizations.of(
                                              context,
                                            )?.webReverseIssuesExpand ??
                                            'Expand'),
                                  icon: Icon(
                                    expanded
                                        ? Icons.unfold_less_rounded
                                        : Icons.unfold_more_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () => setState(() {
                                    _expandedIndex = expanded ? -1 : i;
                                  }),
                                ),
                              ],
                            ),
                            if (brief.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: SelectableText(
                                  brief,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: expanded ? null : 2,
                                ),
                              ),
                            if (expanded)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLowest,
                                  borderRadius: kOpenHandBorderRadius8,
                                ),
                                child: SelectableText(
                                  e.rawJson,
                                  style: tt.bodySmall?.copyWith(
                                    fontFamily: kOpenHandMonospaceFontFamily,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          buildWebReverseDialogFooter(
            context,
            leading: Row(
              children: [
                Icon(
                  Icons.fiber_manual_record_rounded,
                  color: _issueDomainEnabled ? cs.tertiary : cs.outline,
                  size: 12,
                ),
                kOpenHandHGap6,
                Text(
                  _issueDomainEnabled
                      ? (AppLocalizations.of(
                              context,
                            )?.webReverseIssuesSubscribed ??
                            'Subscribed to Audits.issueAdded')
                      : (AppLocalizations.of(
                              context,
                            )?.webReverseIssuesAuditsNotReady ??
                            'Audits domain not ready'),
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              OpenHandDialogActionButton.primary(
                label:
                    AppLocalizations.of(context)?.webReverseIssuesClose ??
                    'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtTs(DateTime ts) {
    String pad(int v) => v < 10 ? '0$v' : '$v';
    return '${pad(ts.hour)}:${pad(ts.minute)}:${pad(ts.second)}';
  }
}

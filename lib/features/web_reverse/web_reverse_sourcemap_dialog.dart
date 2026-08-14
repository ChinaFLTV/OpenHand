/// Source Map 反解析面板。
///
/// 输入压缩文件 URL、行和列，由会话控制器安全抓取并解析映射文件，
/// 再通过 VLQ 解码定位原始源码位置。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSourceMapDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _SmDialog(controller: controller),
  );
}

class _SmDialog extends StatefulWidget {
  const _SmDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_SmDialog> createState() => _SmDialogState();
}

class _Resolved {
  _Resolved({
    required this.source,
    required this.line,
    required this.column,
    required this.name,
    required this.snippet,
  });
  final String source;
  final int line; // 映射从 0 开始，展示时加 1。
  final int column; // 映射从 0 开始，展示时加 1。
  final String? name;
  final String snippet;
}

class _SmDialogState extends State<_SmDialog> {
  final _url = TextEditingController();
  final _line = TextEditingController(text: '1');
  final _col = TextEditingController(text: '0');
  bool _busy = false;
  String _status = '';
  _Resolved? _result;

  @override
  void dispose() {
    _url.dispose();
    _line.dispose();
    _col.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final loc = AppLocalizations.of(context);
    final url = _url.text.trim();
    final line = positiveIntFromValue(_line.text, fallback: 0);
    final col = nonNegativeIntFromValue(_col.text, fallback: 0);
    if (url.isEmpty || line < 1) {
      setState(
        () => _status = loc?.webReverseSmInvalidInput ?? 'invalid input',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = loc?.webReverseSmFetching ?? 'Fetching sourcemap...';
      _result = null;
    });
    try {
      final info = await widget.controller.fetchSourceMapForUrl(url);
      if (!mounted) return;
      if (info == null) {
        final detail =
            loc?.webReverseSmBadEvalResult ?? 'Source Map unavailable';
        setState(() {
          _busy = false;
          _status =
              loc?.webReverseSmFetchFailed(detail) ?? 'Fetch failed: $detail';
        });
        return;
      }

      final hit = _decode(
        info.mappings,
        targetLine: line - 1,
        targetColumn: col,
      );
      if (hit == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = loc?.webReverseSmNoMapping ?? 'No mapping segment';
        });
        return;
      }
      final srcIdx = hit['source']!;
      final origLine = hit['origLine']!;
      final origCol = hit['origCol']!;
      final nameIdx = hit['name'];

      final src = info.resolveSource(srcIdx);
      String snippet = '';
      if (srcIdx >= 0 && srcIdx < info.sourcesContent.length) {
        final body = info.sourcesContent[srcIdx];
        if (body != null) {
          final lines = const LineSplitter().convert(body);
          if (origLine < lines.length) {
            final around = <String>[];
            for (
              var i = (origLine - 1).clamp(0, lines.length - 1);
              i <= (origLine + 1).clamp(0, lines.length - 1);
              i += 1
            ) {
              final marker = i == origLine ? '→' : ' ';
              around.add('$marker ${i + 1}: ${lines[i]}');
            }
            snippet = around.join('\n');
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = _Resolved(
          source: src,
          line: origLine,
          column: origCol,
          name: (nameIdx != null && nameIdx >= 0 && nameIdx < info.names.length)
              ? info.names[nameIdx]
              : null,
          snippet: snippet,
        );
        _status = loc?.webReverseSmResolved ?? 'Resolved';
      });
    } catch (e, st) {
      silentLog('web_reverse_sourcemap_dialog', '解析 Source Map', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = loc?.webReverseSmFetchFailed('$e') ?? 'Source Map 解析失败：$e';
      });
    }
  }

  /// VLQ 解码 mappings 字符串，找到 (targetLine, targetColumn) 所在段。
  /// 返回 {source, origLine, origCol, name?} 的 0-based 整数。
  Map<String, int?>? _decode(
    String mappings, {
    required int targetLine,
    required int targetColumn,
  }) {
    int srcIdx = 0;
    int origLine = 0;
    int origCol = 0;
    int nameIdx = 0;
    final lines = mappings.split(';');
    if (targetLine < 0 || targetLine >= lines.length) return null;
    final lineStr = lines[targetLine];
    if (lineStr.isEmpty) return null;
    // 走前面所有行更新跨行延续的字段（srcIdx/origLine/origCol/nameIdx 是
    // 整张 mappings 跨行的；generatedColumn 每行重置）。
    for (var li = 0; li < targetLine; li += 1) {
      final segs = lines[li].split(',');
      for (final seg in segs) {
        if (seg.isEmpty) continue;
        final nums = vlqDecode(seg);
        if (nums.length >= 4) {
          srcIdx += nums[1];
          origLine += nums[2];
          origCol += nums[3];
          if (nums.length >= 5) nameIdx += nums[4];
        }
      }
    }
    int genCol = 0;
    Map<String, int?>? best;
    for (final seg in lineStr.split(',')) {
      if (seg.isEmpty) continue;
      final nums = vlqDecode(seg);
      if (nums.isEmpty) continue;
      genCol += nums[0];
      if (genCol > targetColumn) break;
      if (nums.length < 4) continue;
      srcIdx += nums[1];
      origLine += nums[2];
      origCol += nums[3];
      if (nums.length >= 5) nameIdx += nums[4];
      best = <String, int?>{
        'source': srcIdx,
        'origLine': origLine,
        'origCol': origCol,
        'name': nums.length >= 5 ? nameIdx : null,
      };
    }
    return best;
  }

  Future<void> _copy() async {
    final loc = AppLocalizations.of(context);
    final r = _result;
    if (r == null) return;
    final text =
        '${r.source}:${r.line + 1}:${r.column + 1}${r.name != null ? '  (${r.name})' : ''}';
    await copyWebReverseTextToClipboard(
      context: context,
      text: text,
      successBase: loc?.webReverseSmCopied ?? 'Copied',
      logTag: 'web_reverse_sourcemap_dialog',
      logAction: '复制 Source Map 解析结果',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final r = _result;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.alt_route_rounded,
            title: loc?.webReverseSmTitle ?? 'SourceMap Resolver',
            subtitle:
                loc?.webReverseSmSubtitle ??
                'min file:line:col → original source:line:col',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _url,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: loc?.webReverseSmUrlLabel ?? 'Minified file URL',
                    hintText: 'https://.../app.min.js',
                    border: const OutlineInputBorder(
                      borderRadius: kOpenHandBorderRadius10,
                    ),
                  ),
                ),
                kOpenHandGap10,
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _line,
                        decoration: InputDecoration(
                          labelText:
                              loc?.webReverseSmLineLabel ?? 'Line (1-based)',
                          border: const OutlineInputBorder(
                            borderRadius: kOpenHandBorderRadius10,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: TextField(
                        controller: _col,
                        decoration: InputDecoration(
                          labelText:
                              loc?.webReverseSmColLabel ?? 'Column (0-based)',
                          border: const OutlineInputBorder(
                            borderRadius: kOpenHandBorderRadius10,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    kOpenHandHGap10,
                    FilledButton.icon(
                      onPressed: _busy ? null : _resolve,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(loc?.webReverseSmResolve ?? 'Resolve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OpenHandBusyProgressBar(busy: _busy),
          Expanded(
            child: r == null
                ? OpenHandInlineEmptyState(
                    message: _status.isEmpty
                        ? (loc?.webReverseSmEmptyHint ??
                              'Enter URL + position, then resolve')
                        : _status,
                    dense: true,
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                '${r.source}:${r.line + 1}:${r.column + 1}',
                                style: TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _copy,
                              icon: const Icon(Icons.copy_rounded),
                              tooltip: loc?.webReverseSmCopyTooltip ?? 'Copy',
                            ),
                          ],
                        ),
                        if (r.name != null && r.name!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${loc?.webReverseSmNameLabel ?? 'name'}: ${r.name}',
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        if (r.snippet.isNotEmpty) ...[
                          kOpenHandGap12,
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: webReverseSurfaceCardDecoration(cs),
                            child: SelectableText(
                              r.snippet,
                              style: const TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          buildWebReverseStatusBar(context, status: _status),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseSmClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

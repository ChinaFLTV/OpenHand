/// SourceMap 反解析面板。
///
/// 输入: 压缩文件 URL + 行 + 列 →
/// (1) JS 取 file text + sourceMappingURL → 解析后再取 map JSON
/// (2) Dart 端 VLQ 解码 mappings → 二分定位段 →
/// (3) 返回 source / originalLine / originalColumn / name
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSourceMapDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
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
  final int line; // 0-based in map → display +1
  final int column; // 0-based in map → display +1
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
    final line = int.tryParse(_line.text.trim()) ?? 0;
    final col = int.tryParse(_col.text.trim()) ?? 0;
    if (url.isEmpty || line < 1) {
      setState(() => _status = loc?.webReverseSmInvalidInput ?? 'invalid input');
      return;
    }
    setState(() {
      _busy = true;
      _status = loc?.webReverseSmFetching ?? 'Fetching sourcemap...';
      _result = null;
    });
    try {
      final js = '''
(async () => {
  try {
    const r = await fetch(${jsonEncode(url)});
    const text = await r.text();
    const m = /[#@]\\s*sourceMappingURL=(\\S+)/.exec(text);
    if (!m) return JSON.stringify({ error: 'no sourceMappingURL' });
    let mapUrl = m[1];
    if (mapUrl.startsWith('data:')) {
      const b64 = mapUrl.slice(mapUrl.indexOf('base64,') + 7);
      return JSON.stringify({ map: atob(b64) });
    }
    mapUrl = new URL(mapUrl, ${jsonEncode(url)}).toString();
    const mr = await fetch(mapUrl);
    const mt = await mr.text();
    return JSON.stringify({ map: mt, mapUrl });
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  }
})()
''';
      final r = await widget.controller.sendRawCdp(
        method: 'Runtime.evaluate',
        paramsJson: jsonEncode({
          'expression': js,
          'awaitPromise': true,
          'returnByValue': true,
        }),
      );
      if (r == null || r['error'] != null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status =
              loc?.webReverseSmFetchFailed('${r?['error']}') ?? 'Fetch failed: ${r?['error']}';
        });
        return;
      }
      final raw = (r['result'] as Map?)?['value'];
      if (raw is! String) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = loc?.webReverseSmBadEvalResult ?? 'Bad eval result';
        });
        return;
      }
      final wrap = jsonDecode(raw) as Map<String, Object?>;
      if (wrap['error'] != null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = 'Error: ${wrap['error']}';
        });
        return;
      }
      final mapText = '${wrap['map']}';
      final map = jsonDecode(mapText) as Map<String, Object?>;
      final sources =
          (map['sources'] as List?)?.cast<Object?>().map((e) => '$e').toList() ??
              const <String>[];
      final names =
          (map['names'] as List?)?.cast<Object?>().map((e) => '$e').toList() ??
              const <String>[];
      final sourceRoot = '${map['sourceRoot'] ?? ''}';
      final mappings = '${map['mappings'] ?? ''}';
      final sourcesContent = (map['sourcesContent'] as List?)
              ?.cast<Object?>()
              .map((e) => e == null ? null : '$e')
              .toList() ??
          const <String?>[];

      final hit = _decode(
        mappings,
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

      final srcRel = (srcIdx >= 0 && srcIdx < sources.length)
          ? sources[srcIdx]
          : '?';
      final src = sourceRoot.isEmpty
          ? srcRel
          : (sourceRoot.endsWith('/') ? '$sourceRoot$srcRel' : '$sourceRoot/$srcRel');
      String snippet = '';
      if (srcIdx >= 0 && srcIdx < sourcesContent.length) {
        final body = sourcesContent[srcIdx];
        if (body != null) {
          final lines = const LineSplitter().convert(body);
          if (origLine < lines.length) {
            final around = <String>[];
            for (var i = (origLine - 1).clamp(0, lines.length - 1);
                i <= (origLine + 1).clamp(0, lines.length - 1);
                i += 1) {
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
          name: (nameIdx != null && nameIdx >= 0 && nameIdx < names.length)
              ? names[nameIdx]
              : null,
          snippet: snippet,
        );
        _status = loc?.webReverseSmResolved ?? 'Resolved';
      });
    } catch (e, st) {
      silentLog('web-reverse', 'sourcemap.resolve', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Error: $e';
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
      genCol += nums[0];
      if (nums.length >= 4) {
        srcIdx += nums[1];
        origLine += nums[2];
        origCol += nums[3];
        if (nums.length >= 5) nameIdx += nums[4];
      }
      if (genCol > targetColumn) break;
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
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e, st) {
      silentLog('web-reverse', 'sourcemap.copy', e, st);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReverseSmCopied ?? 'Copied',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final r = _result;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseSmTitle ?? 'SourceMap Resolver',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          loc?.webReverseSmSubtitle ?? 'min file:line:col → original source:line:col',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _line,
                          decoration: InputDecoration(
                            labelText: loc?.webReverseSmLineLabel ?? 'Line (1-based)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _col,
                          decoration: InputDecoration(
                            labelText: loc?.webReverseSmColLabel ?? 'Column (0-based)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
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
            if (_busy) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: r == null
                  ? Center(
                      child: Text(
                        _status.isEmpty
                            ? (loc?.webReverseSmEmptyHint ?? 'Enter URL + position, then resolve')
                            : _status,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
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
                                    fontFamily: 'monospace',
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
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: SelectableText(
                                r.snippet,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHigh,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OpenHandDialogActionButton.primary(
                  label: loc?.webReverseSmClose ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

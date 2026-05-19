/// AI 加密参数还原助手。
///
/// 流程：
///   1. 从当前会话已抓的网络请求中按 (Method + path) 聚合 endpoint；
///   2. 选定一个 endpoint，对所有样本做 body diff，提取变化的字段 +
///      高熵 / 固定长度的 hash 候选；
///   3. 通过 `Page.getResourceTree` 拿到所有 frame 上的 Script 资源，
///      逐个调用 `Page.searchInResource` 搜索这些字段名（小写、原样），
///      只保留首 5 个命中（含行号）；
///   4. 把 endpoint + 多份样本 + 嫌疑字段 + JS 命中位置组装成 Markdown
///      提示词，复制后即可贴到任意 AI 会话让其推断加密算法。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

class _EndpointGroup {
  _EndpointGroup({required this.key, required this.entries});
  final String key; // METHOD path
  final List<CdpNetworkEntry> entries;
}

class _JsHit {
  _JsHit({required this.url, required this.lineNumber, required this.lineContent});
  final String url;
  final int lineNumber;
  final String lineContent;
}

Future<void> showWebReverseAiCryptoDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _AiCryptoDialog(controller: controller, isZh: isZh),
  );
}

class _AiCryptoDialog extends StatefulWidget {
  const _AiCryptoDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  // ignore: unused_field
  final bool isZh;
  @override
  State<_AiCryptoDialog> createState() => _AiCryptoDialogState();
}

class _AiCryptoDialogState extends State<_AiCryptoDialog> {
  List<_EndpointGroup> _groups = const <_EndpointGroup>[];
  _EndpointGroup? _selected;
  bool _busy = false;
  String? _status;

  /// 提取的嫌疑字段。
  List<String> _suspects = const <String>[];

  /// 最终拼好的 Markdown。
  String _prompt = '';

  @override
  void initState() {
    super.initState();
    _reloadGroups();
  }

  void _reloadGroups() {
    final raw = widget.controller.networkRequests;
    final map = <String, List<CdpNetworkEntry>>{};
    for (final e in raw) {
      try {
        final uri = Uri.parse(e.url);
        final path = uri.path.isEmpty ? '/' : uri.path;
        final key = '${e.method.toUpperCase()} ${uri.host}${path}';
        (map[key] ??= <CdpNetworkEntry>[]).add(e);
      } catch (err, st) {
        silentLog('web_reverse_ai_crypto', 'group', err, st);
      }
    }
    final list = map.entries
        .where((kv) => kv.value.length >= 2)
        .map((kv) => _EndpointGroup(key: kv.key, entries: kv.value))
        .toList()
      ..sort((a, b) => b.entries.length.compareTo(a.entries.length));
    setState(() {
      _groups = list;
      _selected = list.isNotEmpty ? list.first : null;
      _suspects = const <String>[];
      _prompt = '';
      _status = null;
    });
  }

  // ---------------- 嫌疑字段提取 ----------------

  Map<String, String>? _tryParseFlatPairs(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    final out = <String, String>{};
    // JSON
    try {
      final v = jsonDecode(body);
      if (v is Map) {
        v.forEach((k, val) {
          if (val is String || val is num || val is bool) {
            out['$k'] = '$val';
          }
        });
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    // form-urlencoded
    if (body.contains('=')) {
      for (final pair in body.split('&')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        try {
          final k = Uri.decodeQueryComponent(pair.substring(0, eq));
          final v = Uri.decodeQueryComponent(pair.substring(eq + 1));
          out[k] = v;
        } catch (_) {}
      }
    }
    return out.isEmpty ? null : out;
  }

  double _entropy(String s) {
    if (s.isEmpty) return 0;
    final counts = <int, int>{};
    for (final c in s.codeUnits) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final n = s.length;
    double h = 0;
    for (final c in counts.values) {
      final p = c / n;
      h -= p * (math.log(p) / math.ln2);
    }
    return h;
  }

  bool _looksHashy(String s) {
    if (s.length < 8 || s.length > 256) return false;
    final hex = RegExp(r'^[A-Fa-f0-9]+$');
    final b64 = RegExp(r'^[A-Za-z0-9+/=_-]+$');
    return hex.hasMatch(s) || (b64.hasMatch(s) && _entropy(s) >= 4.0);
  }

  List<String> _detectSuspects(_EndpointGroup g) {
    final samples = <Map<String, String>>[];
    for (final e in g.entries) {
      final m = _tryParseFlatPairs(e.requestPostData);
      if (m != null) samples.add(m);
    }
    if (samples.length < 2) {
      // 也尝试 URL query 参数
      final qs = <Map<String, String>>[];
      for (final e in g.entries) {
        try {
          final u = Uri.parse(e.url);
          if (u.queryParameters.isNotEmpty) {
            qs.add(Map<String, String>.from(u.queryParameters));
          }
        } catch (_) {}
      }
      if (qs.length >= 2) samples.addAll(qs);
    }
    if (samples.isEmpty) return const <String>[];

    // 所有 key 的并集
    final keys = <String>{};
    for (final s in samples) {
      keys.addAll(s.keys);
    }
    final variable = <String>[];
    for (final k in keys) {
      final values = <String>{};
      for (final s in samples) {
        final v = s[k];
        if (v != null) values.add(v);
      }
      if (values.length < 2) continue;
      final hashy = values.where(_looksHashy).length;
      final lengthsSame = values.map((v) => v.length).toSet().length == 1;
      if (hashy >= 1 || lengthsSame || _isWellKnownSignKey(k)) {
        variable.add(k);
      }
    }
    variable.sort((a, b) => a.compareTo(b));
    return variable;
  }

  bool _isWellKnownSignKey(String k) {
    final lower = k.toLowerCase();
    const known = <String>[
      'sign', 'signature', 'sig', 'hash', 'token',
      'ts', 'timestamp', 't', 'nonce', '_t', '_s',
      'salt', 'mac', 'checksum', 'verify', 'authorization',
      'x-sign', 'x-nonce', 'x-token', 'x-bogus', 'x-gorgon',
      'msToken', 'a_bogus', 'webid', 'devid',
    ];
    return known.contains(lower);
  }

  // ---------------- JS 资源搜索 ----------------

  Future<Map<String, List<_JsHit>>> _searchSuspects(List<String> suspects) async {
    if (suspects.isEmpty) return const <String, List<_JsHit>>{};
    final loc = AppLocalizations.of(context);
    setState(() => _status =
        loc?.webReverseAiCryptoStatusFetchResources ?? 'Fetching resources...');
    final tree = await widget.controller.sendRawCdp(
      method: 'Page.getResourceTree',
      paramsJson: '{}',
      useSession: true,
    );
    if (tree == null || tree['error'] != null) {
      return const <String, List<_JsHit>>{};
    }
    final scripts = <_ScriptResource>[];
    void walk(Object? node) {
      if (node is! Map) return;
      final frame = node['frame'];
      if (frame is Map) {
        final fid = frame['id']?.toString();
        final resources = node['resources'];
        if (resources is List && fid != null) {
          for (final r in resources) {
            if (r is Map &&
                (r['type']?.toString().toLowerCase() == 'script') &&
                r['url'] is String) {
              scripts.add(_ScriptResource(frameId: fid, url: r['url'] as String));
            }
          }
        }
      }
      final children = node['childFrames'];
      if (children is List) {
        for (final c in children) {
          walk(c);
        }
      }
    }

    walk(tree['frameTree']);
    if (scripts.isEmpty) return const <String, List<_JsHit>>{};

    // 限制以防扫死页面
    final scriptsToSearch = scripts.take(30).toList();
    final out = <String, List<_JsHit>>{};
    var done = 0;
    for (final key in suspects) {
      final list = <_JsHit>[];
      for (final s in scriptsToSearch) {
        if (list.length >= 5) break;
        try {
          final r = await widget.controller.sendRawCdp(
            method: 'Page.searchInResource',
            paramsJson: jsonEncode({
              'frameId': s.frameId,
              'url': s.url,
              'query': key,
              'caseSensitive': false,
              'isRegex': false,
            }),
            useSession: true,
          );
          if (r == null || r['error'] != null) continue;
          final results = r['result'];
          if (results is List) {
            for (final m in results) {
              if (m is Map) {
                final line = (m['lineNumber'] is int) ? m['lineNumber'] as int : 0;
                final content = m['lineContent']?.toString() ?? '';
                list.add(_JsHit(
                  url: s.url,
                  lineNumber: line,
                  lineContent: content.length > 200
                      ? '${content.substring(0, 200)}…'
                      : content,
                ));
                if (list.length >= 5) break;
              }
            }
          }
        } catch (e, st) {
          silentLog('web_reverse_ai_crypto', 'searchInResource', e, st);
        }
      }
      if (list.isNotEmpty) out[key] = list;
      done++;
      if (mounted) {
        final loc = AppLocalizations.of(context);
        setState(() => _status = loc?.webReverseAiCryptoStatusSearchProgress(
              done, suspects.length,
            ) ??
            'Search $done/${suspects.length}');
      }
    }
    return out;
  }

  // ---------------- prompt 拼装 ----------------

  String _buildPrompt(_EndpointGroup g, List<String> suspects,
      Map<String, List<_JsHit>> hits) {
    final buf = StringBuffer()
      ..writeln('# AI 加密参数还原任务')
      ..writeln()
      ..writeln('## 目标 endpoint')
      ..writeln('`${g.key}`')
      ..writeln()
      ..writeln('共抓到 ${g.entries.length} 次请求。')
      ..writeln()
      ..writeln('## 嫌疑字段（在多次请求间变化或形态像 hash）')
      ..writeln();
    if (suspects.isEmpty) {
      buf.writeln('(未自动识别到变化字段)');
    } else {
      for (final k in suspects) {
        buf.writeln('- `$k`');
      }
    }
    buf
      ..writeln()
      ..writeln('## 样本请求（最多取 3 次）');
    for (final e in g.entries.take(3)) {
      buf
        ..writeln()
        ..writeln('### ${e.method} ${e.url}')
        ..writeln('- status: `${e.statusCode ?? '-'}`')
        ..writeln('- timestamp: `${e.timestamp.toIso8601String()}`');
      if (e.requestHeaders.isNotEmpty) {
        buf.writeln('- request headers:');
        e.requestHeaders.forEach((k, v) {
          buf.writeln('  - `$k`: `$v`');
        });
      }
      if (e.requestPostData != null) {
        final body = e.requestPostData!;
        buf
          ..writeln('- request body:')
          ..writeln('```')
          ..writeln(body.length > 4000 ? '${body.substring(0, 4000)}…' : body)
          ..writeln('```');
      }
    }
    if (hits.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('## 嫌疑字段在 JS 源码中的引用');
      hits.forEach((key, lst) {
        buf
          ..writeln()
          ..writeln('### `$key`');
        for (final h in lst) {
          buf
            ..writeln('- `${h.url}:${h.lineNumber + 1}`')
            ..writeln('  ```')
            ..writeln('  ${h.lineContent.trim()}')
            ..writeln('  ```');
        }
      });
    }
    buf
      ..writeln()
      ..writeln('## 请你输出')
      ..writeln('1. 每个嫌疑字段最可能的算法（MD5 / SHA1 / SHA256 / HMAC-SHA256 / AES / 自实现累加）。')
      ..writeln('2. 还原算法用的输入字段及拼接顺序。')
      ..writeln('3. 给出可直接运行的 JS 复算函数，参数列表与样本对齐。')
      ..writeln('4. 列出仍需补充的 deobfuscated 源码片段（指明哪个 URL+ 行号）。');
    return buf.toString();
  }

  Future<void> _analyze() async {
    final g = _selected;
    if (g == null || _busy) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status =
          loc?.webReverseAiCryptoStatusDetecting ?? 'Detecting suspects...';
      _suspects = const <String>[];
      _prompt = '';
    });
    try {
      final suspects = _detectSuspects(g);
      final hits = await _searchSuspects(suspects);
      final prompt = _buildPrompt(g, suspects, hits);
      if (mounted) {
        setState(() {
          _suspects = suspects;
          _prompt = prompt;
          _status = loc?.webReverseAiCryptoStatusDone ?? 'Done';
        });
      }
    } catch (e, st) {
      silentLog('web_reverse_ai_crypto', 'analyze', e, st);
      if (mounted) setState(() => _status = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy() async {
    if (_prompt.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final loc = AppLocalizations.of(context);
    if (messenger != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        loc?.webReverseAiCryptoCopied ?? 'Copied to clipboard',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseAiCryptoTitle ??
                              'AI Crypto Param Recover',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          loc?.webReverseAiCryptoSubtitle ??
                              'Group endpoint → diff vars → locate in JS → copy prompt',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _reloadGroups,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: loc?.webReverseAiCryptoRefresh ?? 'Refresh',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 320,
                    child: Container(
                      color: cs.surfaceContainerLow,
                      child: _groups.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  loc?.webReverseAiCryptoEmpty ??
                                      'No analyzable endpoint (need ≥2 hits per endpoint)',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _groups.length,
                              itemBuilder: (_, i) {
                                final g = _groups[i];
                                final selected = g.key == _selected?.key;
                                return Material(
                                  color: selected
                                      ? cs.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() {
                                      _selected = g;
                                      _suspects = const <String>[];
                                      _prompt = '';
                                    }),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            g.key,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            loc?.webReverseAiCryptoHits(
                                                  g.entries.length,
                                                ) ??
                                                '${g.entries.length} hits',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                    color: cs.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: (_busy || _selected == null)
                                    ? null
                                    : _analyze,
                                icon: const Icon(Icons.psychology_rounded),
                                label: Text(
                                    loc?.webReverseAiCryptoAnalyze ?? 'Analyze'),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.tonalIcon(
                                onPressed:
                                    _prompt.isEmpty ? null : _copy,
                                icon: const Icon(Icons.copy_all_rounded),
                                label: Text(loc?.webReverseAiCryptoCopyPrompt ??
                                    'Copy prompt'),
                              ),
                              const Spacer(),
                              if (_status != null)
                                Text(
                                  _status!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                            ],
                          ),
                          if (_suspects.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Text(
                                  loc?.webReverseAiCryptoSuspectsLabel ??
                                      'Suspects:',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                for (final k in _suspects)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      k,
                                      style: const TextStyle(
                                          fontFamily: 'monospace', fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(10),
                                child: SelectableText(
                                  _prompt.isEmpty
                                      ? (loc?.webReverseAiCryptoPromptHint ??
                                          'Click Analyze to generate the prompt.')
                                      : _prompt,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: _prompt.isEmpty
                                        ? cs.onSurfaceVariant
                                        : cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseAiCryptoClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
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

class _ScriptResource {
  _ScriptResource({required this.frameId, required this.url});
  final String frameId;
  final String url;
}

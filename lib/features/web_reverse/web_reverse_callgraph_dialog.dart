/// JS 函数调用图面板。
///
/// 流程：
/// 1. `Page.getResourceTree` 取所有 frame 上的 Script 资源 URL；
/// 2. 逐个 `Page.getResourceContent` 取脚本源码（限制脚本数 + 单脚本大小避免压垮 UI）；
/// 3. 用启发式正则解析：
///    - `function NAME(` 声明
///    - `NAME = function(` / `NAME: function(` / `const NAME = (...) =>` 表达式
///    - 类方法 `NAME(...) { ... }`（简化处理）
///    - 调用点 `NAME(` 抠出标识符列表
/// 4. 构造 caller→callees 邻接图，按脚本展示；并提供「查找谁调用了 X」反查。
///
/// 注：对压缩/混淆的 bundle 噪点较多，仅作快速线索。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_expandable.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCallgraphDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _CallgraphDialog(controller: controller),
  );
}

class _CallgraphDialog extends StatefulWidget {
  const _CallgraphDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CallgraphDialog> createState() => _CallgraphDialogState();
}

class _CallgraphDialogState extends State<_CallgraphDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _scanning = false;
  String _status = '';
  int _scriptLimit = 20;
  int _maxScriptKb = 200;
  final List<_ScriptGraph> _graphs = [];
  String? _selectedUrl;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _scanning = true;
      _status = loc?.webReverseCallgraphFetching ?? 'Fetching resources...';
      _graphs.clear();
      _selectedUrl = null;
    });
    try {
      final tree = await widget.controller.sendRawCdp(
        method: 'Page.getResourceTree',
        paramsJson: '{}',
      );
      if (!mounted) return;
      if (tree == null || tree['error'] != null) {
        setState(
          () => _status = loc?.webReverseCallgraphFetchFailed ?? 'Fetch failed',
        );
        return;
      }
      final scripts = collectWebReverseScriptResources(
        tree['frameTree'],
        maxEntries: _scriptLimit,
      );
      if (scripts.isEmpty) {
        setState(
          () => _status =
              loc?.webReverseCallgraphNoScripts ?? 'No JS scripts found',
        );
        return;
      }
      final pickList = scripts.toList(growable: false);
      var done = 0;
      for (final s in pickList) {
        if (!mounted) return;
        done++;
        if (mounted) {
          setState(
            () => _status =
                loc?.webReverseCallgraphParsing(
                  done,
                  pickList.length,
                  _shortUrl(s.url),
                ) ??
                'Parsing $done/${pickList.length}: ${_shortUrl(s.url)}',
          );
        }
        try {
          final r = await widget.controller.sendRawCdp(
            method: 'Page.getResourceContent',
            paramsJson: jsonEncode({'frameId': s.frameId, 'url': s.url}),
          );
          if (r == null || r['error'] != null) continue;
          var content = r['content']?.toString() ?? '';
          final base64Encoded = r['base64Encoded'] == true;
          if (base64Encoded) {
            try {
              content = utf8.decode(
                base64.decode(content),
                allowMalformed: true,
              );
            } catch (e, st) {
              silentLog('web_reverse_callgraph', '解码 Base64 内容', e, st);
              continue;
            }
          }
          final maxBytes = _maxScriptKb * kBytesPerKiB;
          final end = safeUtf8PrefixCodeUnits(content, maxBytes);
          if (end < content.length) {
            content = content.substring(0, end);
          }
          final graph = _parseScript(s.url, content);
          if (graph.functions.isNotEmpty) {
            _graphs.add(graph);
          }
        } catch (e, st) {
          silentLog('web_reverse_callgraph', '获取资源内容', e, st);
        }
      }
      if (!mounted) return;
      setState(() {
        final scripts = _graphs.length;
        final fns = _graphs.fold<int>(0, (a, g) => a + g.functions.length);
        _status =
            loc?.webReverseCallgraphDone(scripts, fns) ??
            'Done: $scripts scripts, $fns functions';
        if (_graphs.isNotEmpty) _selectedUrl = _graphs.first.url;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  static final _funcDeclPattern = RegExp(r'function\s+([A-Za-z_$][\w$]*)\s*\(');
  static final _funcExprPattern = RegExp(
    r'(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?function\b',
  );
  static final _arrowPattern = RegExp(
    r'(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)=]*\)|[A-Za-z_$][\w$]*)\s*=>',
  );
  static final _methodPattern = RegExp(
    r'(?:^|[\s,{;])([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{',
  );
  static final _callPattern = RegExp(r'([A-Za-z_$][\w$]*)\s*\(');

  static const _reserved = <String>{
    'if',
    'for',
    'while',
    'switch',
    'return',
    'function',
    'typeof',
    'new',
    'catch',
    'do',
    'else',
    'throw',
    'await',
    'async',
    'yield',
    'delete',
    'void',
    'in',
    'of',
    'instanceof',
    'true',
    'false',
    'null',
    'undefined',
    'this',
    'super',
    'class',
    'extends',
    'try',
    'finally',
    'const',
    'let',
    'var',
    'import',
    'export',
    'from',
    'default',
    'case',
    'break',
    'continue',
    'with',
    'debugger',
    'NaN',
    'Infinity',
  };

  _ScriptGraph _parseScript(String url, String src) {
    // 1. 收集函数定义位置
    final defs = <_FnDef>[];
    void addDef(String name, int start) {
      if (name.isEmpty || _reserved.contains(name)) return;
      defs.add(_FnDef(name: name, start: start));
    }

    for (final m in _funcDeclPattern.allMatches(src)) {
      addDef(m.group(1) ?? '', m.start);
    }
    for (final m in _funcExprPattern.allMatches(src)) {
      addDef(m.group(1) ?? '', m.start);
    }
    for (final m in _arrowPattern.allMatches(src)) {
      addDef(m.group(1) ?? '', m.start);
    }

    if (defs.isEmpty) {
      // 兜底：扫类方法形式
      var count = 0;
      for (final m in _methodPattern.allMatches(src)) {
        addDef(m.group(1) ?? '', m.start);
        if (++count >= 200) break;
      }
    }

    if (defs.isEmpty) {
      return _ScriptGraph(url: url, functions: const []);
    }

    // 按位置排序
    defs.sort((a, b) => a.start.compareTo(b.start));

    // 2. 每个 def 的范围 = [start, nextDef.start) 切片
    final functions = <_FnNode>[];
    for (var i = 0; i < defs.length; i++) {
      final s = defs[i].start;
      final e = (i + 1 < defs.length) ? defs[i + 1].start : src.length;
      final body = src.substring(s, e);
      // 找匹配花括号缩小范围
      final braceStart = body.indexOf('{');
      String scope = body;
      if (braceStart >= 0) {
        var depth = 0;
        var found = false;
        for (var k = braceStart; k < body.length; k++) {
          final c = body[k];
          if (c == '{') depth++;
          if (c == '}') {
            depth--;
            if (depth == 0) {
              scope = body.substring(braceStart, k + 1);
              found = true;
              break;
            }
          }
        }
        if (!found) scope = body.substring(braceStart);
      }
      // 提取 callees
      final calleeSet = <String>{};
      final calleeOrdered = <String>[];
      var callCount = 0;
      for (final m in _callPattern.allMatches(scope)) {
        final name = m.group(1) ?? '';
        if (name == defs[i].name) continue;
        if (_reserved.contains(name)) continue;
        if (calleeSet.add(name)) {
          calleeOrdered.add(name);
        }
        if (++callCount >= 800) break;
      }
      functions.add(
        _FnNode(name: defs[i].name, offset: s, callees: calleeOrdered),
      );
    }
    return _ScriptGraph(url: url, functions: functions);
  }

  List<_CallerHit> _findCallers(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final out = <_CallerHit>[];
    for (final g in _graphs) {
      for (final fn in g.functions) {
        for (final c in fn.callees) {
          if (c.toLowerCase().contains(q.toLowerCase())) {
            out.add(_CallerHit(url: g.url, caller: fn.name, callee: c));
            break;
          }
        }
      }
    }
    return out;
  }

  String _shortUrl(String url) {
    try {
      final u = Uri.parse(url);
      final p = u.path.isEmpty ? '/' : u.path;
      final last = p.split('/').where((s) => s.isNotEmpty).toList();
      return '${u.host}/${last.isEmpty ? '' : last.last}';
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);

    final selected = _graphs.where((g) => g.url == _selectedUrl).firstOrNull;
    final callerHits = _findCallers(_searchCtrl.text);

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthFull,
      maxHeight: kOpenHandDialogHeightTall,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.account_tree_rounded,
            title: loc?.webReverseCallgraphTitle ?? 'JS Callgraph',
            subtitle:
                loc?.webReverseCallgraphSubtitle ??
                'Heuristic regex parsing (noisy for minified bundles)',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _scanning ? null : _scan,
                  icon: OpenHandBusyStatusIcon(
                    busy: _scanning,
                    icon: Icons.play_arrow_rounded,
                  ),
                  label: Text(loc?.webReverseCallgraphScanBtn ?? 'Scan'),
                ),
                kOpenHandHGap12,
                Text(
                  loc?.webReverseCallgraphScriptLimit ?? 'Script limit',
                  style: theme.textTheme.labelSmall,
                ),
                kOpenHandHGap6,
                WebReverseSelectButton<int>(
                  value: _scriptLimit,
                  dense: true,
                  minWidth: 64,
                  tooltip:
                      loc?.webReverseCallgraphScriptLimit ?? 'Script limit',
                  options: const [
                    WebReverseSelectOption(value: 10, label: '10'),
                    WebReverseSelectOption(value: 20, label: '20'),
                    WebReverseSelectOption(value: 30, label: '30'),
                    WebReverseSelectOption(value: 50, label: '50'),
                  ],
                  onChanged: _scanning
                      ? null
                      : (v) => setState(() => _scriptLimit = v),
                ),
                kOpenHandHGap12,
                Text(
                  loc?.webReverseCallgraphPerScriptKb ?? 'Per script (KB)',
                  style: theme.textTheme.labelSmall,
                ),
                kOpenHandHGap6,
                WebReverseSelectButton<int>(
                  value: _maxScriptKb,
                  dense: true,
                  minWidth: 72,
                  tooltip:
                      loc?.webReverseCallgraphPerScriptKb ?? 'Per script (KB)',
                  options: const [
                    WebReverseSelectOption(value: 100, label: '100'),
                    WebReverseSelectOption(value: 200, label: '200'),
                    WebReverseSelectOption(value: 400, label: '400'),
                    WebReverseSelectOption(value: 800, label: '800'),
                  ],
                  onChanged: _scanning
                      ? null
                      : (v) => setState(() => _maxScriptKb = v),
                ),
                kOpenHandHGap16,
                Expanded(
                  child: Text(
                    _status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText:
                    loc?.webReverseCallgraphReverseHint ??
                    'Reverse lookup: who calls …',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: webReverseSurfaceCardDecoration(cs),
              child: _graphs.isEmpty
                  ? OpenHandInlineEmptyState(
                      message:
                          loc?.webReverseCallgraphEmptyHint ??
                          'Click Scan to parse current page JS',
                      dense: true,
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: 340,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    loc?.webReverseCallgraphScriptsCount(
                                          _graphs.length,
                                        ) ??
                                        'Scripts (${_graphs.length})',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              Divider(height: 1, color: cs.outlineVariant),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: _graphs.length,
                                  separatorBuilder: (_, _) => Divider(
                                    height: 1,
                                    color: cs.outlineVariant,
                                  ),
                                  itemBuilder: (_, i) {
                                    final g = _graphs[i];
                                    final isSel = g.url == _selectedUrl;
                                    return Material(
                                      color: isSel
                                          ? cs.primaryContainer.withValues(
                                              alpha: 0.5,
                                            )
                                          : Colors.transparent,
                                      child: InkWell(
                                        onTap: () => setState(
                                          () => _selectedUrl = g.url,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _shortUrl(g.url),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      kOpenHandMonospaceFontFamily,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${g.functions.length} ${loc?.webReverseCallgraphFnsSuffix ?? 'fns'}',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
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
                          child: callerHits.isNotEmpty
                              ? _buildCallerHits(theme, cs, callerHits, loc)
                              : selected == null
                              ? Center(
                                  child: Text(
                                    loc?.webReverseCallgraphPickScript ??
                                        'Pick a script',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : _buildScriptDetail(theme, cs, selected, loc),
                        ),
                      ],
                    ),
            ),
          ),
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseCallgraphClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptDetail(
    ThemeData theme,
    ColorScheme cs,
    _ScriptGraph g,
    AppLocalizations? loc,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  g.url,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: loc?.webReverseCallgraphCopyGraph ?? 'Copy graph',
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                onPressed: () async {
                  final buf = StringBuffer()..writeln('# ${g.url}');
                  for (final fn in g.functions) {
                    buf.writeln(
                      '${fn.name} -> ${fn.callees.take(20).join(', ')}',
                    );
                  }
                  await copyWebReverseTextToClipboard(
                    context: context,
                    text: buf.toString(),
                    successBase:
                        loc?.webReverseCallgraphGraphCopied ?? 'Graph copied',
                    logTag: 'web_reverse_callgraph',
                    logAction: '复制调用图',
                  );
                },
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView.builder(
            itemCount: g.functions.length,
            itemBuilder: (_, i) {
              final fn = g.functions[i];
              return OpenHandExpansionTile(
                title: Text(
                  fn.name,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${fn.callees.length} ${loc?.webReverseCallgraphCalleesSuffix ?? 'callees'} · @${fn.offset}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (fn.callees.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        loc?.webReverseCallgraphNoDetectedCalls ??
                            '(no detected calls)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: fn.callees.take(80).map((c) {
                        return ActionChip(
                          label: Text(
                            c,
                            style: const TextStyle(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () => setState(() {
                            _searchCtrl.text = c;
                          }),
                        );
                      }).toList(),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCallerHits(
    ThemeData theme,
    ColorScheme cs,
    List<_CallerHit> hits,
    AppLocalizations? loc,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              Icon(Icons.travel_explore_rounded, size: 16, color: cs.primary),
              kOpenHandHGap6,
              Text(
                loc?.webReverseCallgraphHitsHeader(
                      hits.length,
                      _searchCtrl.text,
                    ) ??
                    '${hits.length} hits calling "${_searchCtrl.text}"',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView.separated(
            itemCount: hits.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: cs.outlineVariant),
            itemBuilder: (_, i) {
              final h = hits[i];
              return ListTile(
                dense: true,
                title: Text(
                  '${h.caller} → ${h.callee}',
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                subtitle: Text(
                  _shortUrl(h.url),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_rounded, size: 16),
                onTap: () => setState(() {
                  _selectedUrl = h.url;
                  _searchCtrl.clear();
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScriptGraph {
  const _ScriptGraph({required this.url, required this.functions});
  final String url;
  final List<_FnNode> functions;
}

class _FnDef {
  const _FnDef({required this.name, required this.start});
  final String name;
  final int start;
}

class _FnNode {
  const _FnNode({
    required this.name,
    required this.offset,
    required this.callees,
  });
  final String name;
  final int offset;
  final List<String> callees;
}

class _CallerHit {
  const _CallerHit({
    required this.url,
    required this.caller,
    required this.callee,
  });
  final String url;
  final String caller;
  final String callee;
}

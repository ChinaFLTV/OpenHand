/// 接口签名字段变量定位器。
///
/// 把当前 dashboard 里抓到的所有请求按 `METHOD path（去 query）` 分组，
/// 对组内 ≥2 条样本做字段稳定性分析：
///   * Query 参数（按 key 聚合 value 集合）
///   * 请求 Header（同上）
///   * 请求体（仅 JSON / form / urlencoded，扁平递归到叶子节点）
///
/// 字段判定：
///   * `稳定` ：组内所有样本值完全相同（强逆向特征：常量/通道码/版本号）
///   * `动态` ：组内值集合 >1（典型签名/时间戳/nonce）
///   * `递增` ：值集合全为数字且严格递增（典型 timestamp/sequence）
///   * `定长哈希`：动态且每个值长度一致 + hex/base64 字符集（典型 sign）
///
/// 这能让用户在「随便点几次」之后，立刻定位到"哪些字段是加密参数"，
/// 不需要在 Network 面板逐条比对。完全本地计算，不发任何请求。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSignatureDiffDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _SignatureDiffDialog(controller: controller, isZh: isZh),
  );
}

class _SignatureDiffDialog extends StatefulWidget {
  const _SignatureDiffDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_SignatureDiffDialog> createState() => _SignatureDiffDialogState();
}

class _SignatureDiffDialogState extends State<_SignatureDiffDialog> {
  late List<_EndpointGroup> _groups;
  String _filter = '';
  _EndpointGroup? _selected;

  @override
  void initState() {
    super.initState();
    _groups = _analyse(widget.controller.networkRequests);
    if (_groups.isNotEmpty) _selected = _groups.first;
  }

  void _refresh() {
    setState(() {
      _groups = _analyse(widget.controller.networkRequests);
      if (_selected != null) {
        _selected = _groups.firstWhere(
          (g) => g.key == _selected!.key,
          orElse: () => _groups.isEmpty
              ? _EndpointGroup.empty()
              : _groups.first,
        );
        if (_selected!.samples.isEmpty) _selected = null;
      } else if (_groups.isNotEmpty) {
        _selected = _groups.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final filtered = _filter.isEmpty
        ? _groups
        : _groups
            .where((g) => g.key.toLowerCase().contains(_filter.toLowerCase()))
            .toList(growable: false);
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
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 360,
                    child: _buildGroupList(theme, cs, isZh, filtered),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: _selected == null || _selected!.samples.isEmpty
                        ? _buildEmpty(theme, cs, isZh)
                        : _buildDetail(theme, cs, isZh, _selected!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '签名字段变量定位器' : 'Signature Field Locator',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isZh
                      ? '同 endpoint 多次抓包后自动识别动态字段（sign / ts / nonce）与稳定字段'
                      : 'Identify dynamic (sign / ts / nonce) vs stable fields across captures of the same endpoint',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isZh ? '刷新' : 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    List<_EndpointGroup> filtered,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: isZh ? '搜索 endpoint' : 'Search endpoint',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    isZh ? '暂无可分析的请求组（需 ≥2 次）' : 'No analyzable groups (need ≥2 samples)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (_, idx) {
                    final g = filtered[idx];
                    final active = _selected == g;
                    return Material(
                      color: active ? cs.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selected = g),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      g.method,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '×${g.samples.length}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (g.dynamicCount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.errorContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${g.dynamicCount} dyn',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: cs.onErrorContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                g.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: active
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface,
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
    );
  }

  Widget _buildEmpty(ThemeData theme, ColorScheme cs, bool isZh) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              isZh
                  ? '在 Network 面板里多次触发同一 API，再回来这里分析。'
                  : 'Hit the same API multiple times in Network panel, then return to analyze.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    _EndpointGroup g,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  g.key,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyReport(g, isZh),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(isZh ? '复制报告' : 'Copy report'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _summaryChip(
                cs,
                isZh ? '稳定' : 'Stable',
                g.stableCount,
                cs.secondaryContainer,
                cs.onSecondaryContainer,
              ),
              _summaryChip(
                cs,
                isZh ? '动态' : 'Dynamic',
                g.dynamicCount,
                cs.errorContainer,
                cs.onErrorContainer,
              ),
              _summaryChip(
                cs,
                isZh ? '递增' : 'Increasing',
                g.increasingCount,
                cs.tertiaryContainer,
                cs.onTertiaryContainer,
              ),
              _summaryChip(
                cs,
                isZh ? '定长哈希' : 'Fixed-len hash',
                g.fixedHashCount,
                cs.primaryContainer,
                cs.onPrimaryContainer,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (g.queryFields.isNotEmpty)
                _section(theme, cs, isZh ? 'Query 参数' : 'Query', g.queryFields),
              if (g.headerFields.isNotEmpty)
                _section(theme, cs, isZh ? '请求 Header' : 'Headers', g.headerFields),
              if (g.bodyFields.isNotEmpty)
                _section(theme, cs, isZh ? '请求体 JSON 字段' : 'Body fields', g.bodyFields),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(
    ColorScheme cs,
    String label,
    int n,
    Color bg,
    Color fg,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label · $n',
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  Widget _section(
    ThemeData theme,
    ColorScheme cs,
    String title,
    List<_FieldStat> fields,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                  _fieldRow(theme, cs, fields[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(ThemeData theme, ColorScheme cs, _FieldStat f) {
    Color tagBg;
    Color tagFg;
    String tagText;
    switch (f.classification) {
      case _FieldClass.stable:
        tagBg = cs.secondaryContainer;
        tagFg = cs.onSecondaryContainer;
        tagText = 'STABLE';
      case _FieldClass.increasing:
        tagBg = cs.tertiaryContainer;
        tagFg = cs.onTertiaryContainer;
        tagText = 'INC';
      case _FieldClass.fixedHash:
        tagBg = cs.primaryContainer;
        tagFg = cs.onPrimaryContainer;
        tagText = 'HASH${f.hashLen}';
      case _FieldClass.dynamic_:
        tagBg = cs.errorContainer;
        tagFg = cs.onErrorContainer;
        tagText = 'DYN';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tagText,
              style: TextStyle(
                color: tagFg,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatValuesPreview(f),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatValuesPreview(_FieldStat f) {
    if (f.classification == _FieldClass.stable) {
      return f.values.first;
    }
    final shown = f.values.take(3).join(' | ');
    final more = f.values.length > 3 ? '  +${f.values.length - 3}' : '';
    return '$shown$more';
  }

  void _copyReport(_EndpointGroup g, bool isZh) {
    final buf = StringBuffer()
      ..writeln('# ${isZh ? "签名字段分析" : "Signature Diff"}: ${g.key}')
      ..writeln('${isZh ? "样本数" : "samples"}: ${g.samples.length}')
      ..writeln();
    void dumpSection(String title, List<_FieldStat> fields) {
      if (fields.isEmpty) return;
      buf.writeln('## $title');
      for (final f in fields) {
        buf.writeln('- ${f.name}  [${f.classification.name}]');
        for (final v in f.values.take(5)) {
          buf.writeln('    · $v');
        }
        if (f.values.length > 5) {
          buf.writeln('    · ... +${f.values.length - 5}');
        }
      }
      buf.writeln();
    }
    dumpSection(isZh ? 'Query' : 'Query', g.queryFields);
    dumpSection(isZh ? 'Headers' : 'Headers', g.headerFields);
    dumpSection(isZh ? 'Body' : 'Body', g.bodyFields);
    Clipboard.setData(ClipboardData(text: buf.toString()));
    final messenger = ScaffoldMessenger.of(context);
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      isZh ? '报告已复制到剪贴板' : 'Report copied to clipboard',
      duration: const Duration(seconds: 2),
    );
  }
}

// ── 分析逻辑 ─────────────────────────────────────────────────────────

List<_EndpointGroup> _analyse(List<CdpNetworkEntry> entries) {
  final buckets = <String, _EndpointGroup>{};
  for (final e in entries) {
    // 只关心可能有载荷的 HTTP 请求
    if (e.isWebSocket) continue;
    if (e.url.isEmpty) continue;
    final uri = Uri.tryParse(e.url);
    if (uri == null) continue;
    final pathKey =
        '${e.method.toUpperCase()} ${uri.scheme}://${uri.authority}${uri.path}';
    final g = buckets.putIfAbsent(
      pathKey,
      () => _EndpointGroup(
        key: pathKey,
        method: e.method.toUpperCase(),
        path: '${uri.scheme}://${uri.authority}${uri.path}',
      ),
    );
    g.samples.add(e);
  }
  // 只保留 ≥2 次的组
  final groups = buckets.values.where((g) => g.samples.length >= 2).toList()
    ..sort((a, b) => b.samples.length.compareTo(a.samples.length));
  for (final g in groups) {
    g.queryFields = _diffQuery(g.samples);
    g.headerFields = _diffHeaders(g.samples);
    g.bodyFields = _diffBody(g.samples);
    g.refreshCounts();
  }
  return groups;
}

List<_FieldStat> _diffQuery(List<CdpNetworkEntry> samples) {
  final map = <String, List<String>>{};
  for (final e in samples) {
    final uri = Uri.tryParse(e.url);
    if (uri == null) continue;
    uri.queryParametersAll.forEach((k, vs) {
      map.putIfAbsent(k, () => <String>[]).add(vs.join(','));
    });
  }
  return _classifyAll(map);
}

List<_FieldStat> _diffHeaders(List<CdpNetworkEntry> samples) {
  // 忽略浏览器自动注入 / cookie / 长度类 header；这些 noise 太大。
  const ignored = <String>{
    'content-length',
    'content-type',
    'accept',
    'accept-encoding',
    'accept-language',
    'user-agent',
    'sec-ch-ua',
    'sec-ch-ua-mobile',
    'sec-ch-ua-platform',
    'sec-fetch-dest',
    'sec-fetch-mode',
    'sec-fetch-site',
    'sec-fetch-user',
    'upgrade-insecure-requests',
    'pragma',
    'cache-control',
    'connection',
    'host',
    'origin',
    'referer',
    'cookie',
  };
  final map = <String, List<String>>{};
  for (final e in samples) {
    e.requestHeaders.forEach((k, v) {
      final lk = k.toLowerCase();
      if (ignored.contains(lk)) return;
      map.putIfAbsent(k, () => <String>[]).add(v);
    });
  }
  return _classifyAll(map);
}

List<_FieldStat> _diffBody(List<CdpNetworkEntry> samples) {
  final map = <String, List<String>>{};
  for (final e in samples) {
    final body = e.requestPostData;
    if (body == null || body.isEmpty) continue;
    final ct = (e.requestHeaders['Content-Type'] ??
            e.requestHeaders['content-type'] ??
            '')
        .toLowerCase();
    if (ct.contains('json') || _looksLikeJson(body)) {
      _flattenJson(body, map);
    } else if (ct.contains('form-urlencoded') || body.contains('=')) {
      _flattenForm(body, map);
    } else {
      map.putIfAbsent('(raw body)', () => <String>[]).add(
        body.length > 80 ? '${body.substring(0, 80)}…' : body,
      );
    }
  }
  return _classifyAll(map);
}

bool _looksLikeJson(String s) {
  final t = s.trimLeft();
  return t.startsWith('{') || t.startsWith('[');
}

void _flattenJson(String body, Map<String, List<String>> out) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (e, st) {
    silentLog('web_reverse', '_flattenJson', e, st);
    return;
  }
  void walk(Object? node, String path) {
    if (node is Map) {
      node.forEach((k, v) {
        walk(v, path.isEmpty ? '$k' : '$path.$k');
      });
    } else if (node is List) {
      // 数组只取第一个样本，避免索引爆炸
      if (node.isNotEmpty) walk(node.first, '$path[]');
    } else {
      out.putIfAbsent(path, () => <String>[]).add(node?.toString() ?? '');
    }
  }
  walk(decoded, '');
}

void _flattenForm(String body, Map<String, List<String>> out) {
  for (final part in body.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final k = Uri.decodeQueryComponent(part.substring(0, eq));
    final v = Uri.decodeQueryComponent(part.substring(eq + 1));
    out.putIfAbsent(k, () => <String>[]).add(v);
  }
}

List<_FieldStat> _classifyAll(Map<String, List<String>> map) {
  final out = <_FieldStat>[];
  map.forEach((k, vs) {
    out.add(_classify(k, vs));
  });
  // 排序：动态在前 → 定长哈希 → 递增 → 稳定
  int rank(_FieldClass c) => switch (c) {
        _FieldClass.fixedHash => 0,
        _FieldClass.increasing => 1,
        _FieldClass.dynamic_ => 2,
        _FieldClass.stable => 3,
      };
  out.sort((a, b) {
    final r = rank(a.classification).compareTo(rank(b.classification));
    if (r != 0) return r;
    return a.name.compareTo(b.name);
  });
  return out;
}

_FieldStat _classify(String name, List<String> values) {
  final unique = values.toSet().toList();
  if (unique.length == 1) {
    return _FieldStat(name: name, values: unique, classification: _FieldClass.stable);
  }
  // 全部能解析为数字 → 检查严格递增
  final asInts = <int>[];
  var allInt = true;
  for (final v in values) {
    final n = int.tryParse(v);
    if (n == null) {
      allInt = false;
      break;
    }
    asInts.add(n);
  }
  if (allInt && asInts.length >= 2) {
    var inc = true;
    for (var i = 1; i < asInts.length; i++) {
      if (asInts[i] <= asInts[i - 1]) {
        inc = false;
        break;
      }
    }
    if (inc) {
      return _FieldStat(
        name: name,
        values: unique,
        classification: _FieldClass.increasing,
      );
    }
  }
  // 全部长度一致且字符集为 hex / base64 → 定长哈希
  final firstLen = unique.first.length;
  if (firstLen >= 8 && unique.every((v) => v.length == firstLen)) {
    final hashLike =
        unique.every((v) => _hexRe.hasMatch(v)) ||
        unique.every((v) => _b64Re.hasMatch(v));
    if (hashLike) {
      return _FieldStat(
        name: name,
        values: unique,
        classification: _FieldClass.fixedHash,
        hashLen: firstLen,
      );
    }
  }
  return _FieldStat(name: name, values: unique, classification: _FieldClass.dynamic_);
}

final RegExp _hexRe = RegExp(r'^[0-9a-fA-F]+$');
final RegExp _b64Re = RegExp(r'^[A-Za-z0-9+/=_-]+$');

// ── 数据模型 ─────────────────────────────────────────────────────────

class _EndpointGroup {
  _EndpointGroup({required this.key, required this.method, required this.path});
  factory _EndpointGroup.empty() =>
      _EndpointGroup(key: '', method: '', path: '');
  final String key;
  final String method;
  final String path;
  final List<CdpNetworkEntry> samples = <CdpNetworkEntry>[];
  List<_FieldStat> queryFields = const <_FieldStat>[];
  List<_FieldStat> headerFields = const <_FieldStat>[];
  List<_FieldStat> bodyFields = const <_FieldStat>[];
  int stableCount = 0;
  int dynamicCount = 0;
  int increasingCount = 0;
  int fixedHashCount = 0;

  void refreshCounts() {
    stableCount = 0;
    dynamicCount = 0;
    increasingCount = 0;
    fixedHashCount = 0;
    for (final f in [...queryFields, ...headerFields, ...bodyFields]) {
      switch (f.classification) {
        case _FieldClass.stable:
          stableCount++;
        case _FieldClass.dynamic_:
          dynamicCount++;
        case _FieldClass.increasing:
          increasingCount++;
        case _FieldClass.fixedHash:
          fixedHashCount++;
      }
    }
  }
}

class _FieldStat {
  _FieldStat({
    required this.name,
    required this.values,
    required this.classification,
    this.hashLen = 0,
  });
  final String name;
  final List<String> values;
  final _FieldClass classification;
  final int hashLen;
}

enum _FieldClass { stable, dynamic_, increasing, fixedHash }

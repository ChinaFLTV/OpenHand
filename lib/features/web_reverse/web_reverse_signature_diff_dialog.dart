/// 对同一接口的请求样本做字段稳定性分析，定位签名、时间戳和随机数。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseSignatureDiffDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _SignatureDiffDialog(controller: controller),
  );
}

class _SignatureDiffDialog extends StatefulWidget {
  const _SignatureDiffDialog({required this.controller});
  final WebReverseSessionController controller;
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
          orElse: () =>
              _groups.isEmpty ? _EndpointGroup.empty() : _groups.first,
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
    final loc = AppLocalizations.of(context);
    final filtered = _filter.isEmpty
        ? _groups
        : _groups
              .where((g) => g.key.toLowerCase().contains(_filter.toLowerCase()))
              .toList(growable: false);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthPanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(loc),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 360,
                  child: _buildGroupList(theme, cs, loc, filtered),
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  child: _selected == null || _selected!.samples.isEmpty
                      ? _buildEmpty(theme, cs, loc)
                      : _buildDetail(theme, cs, loc, _selected!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations? loc) {
    return buildOpenHandToolDialogHeader(
      context: context,
      icon: Icons.fingerprint_rounded,
      title:
          loc?.webReverseSignatureDiffHeaderTitle ?? 'Signature Field Locator',
      subtitle:
          loc?.webReverseSignatureDiffHeaderSubtitle ??
          'Identify dynamic (sign / ts / nonce) vs stable fields across captures of the same endpoint',
      actions: [
        IconButton(
          tooltip: loc?.webReverseSignatureDiffRefresh ?? 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildGroupList(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
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
              hintText:
                  loc?.webReverseSignatureDiffSearchHint ?? 'Search endpoint',
              border: const OutlineInputBorder(
                borderRadius: kOpenHandBorderRadius10,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? OpenHandInlineEmptyState(
                  message:
                      loc?.webReverseSignatureDiffNoGroups ??
                      'No analyzable groups (need ≥2 samples)',
                  dense: true,
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => kOpenHandGap2,
                  itemBuilder: (_, idx) {
                    final g = filtered[idx];
                    final active = _selected == g;
                    return Material(
                      color: active ? cs.primaryContainer : Colors.transparent,
                      borderRadius: kOpenHandBorderRadius8,
                      child: InkWell(
                        borderRadius: kOpenHandBorderRadius8,
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
                                      borderRadius: kOpenHandBorderRadius4,
                                    ),
                                    child: Text(
                                      g.method,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            fontFamily:
                                                kOpenHandMonospaceFontFamily,
                                          ),
                                    ),
                                  ),
                                  kOpenHandHGap6,
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.tertiaryContainer,
                                      borderRadius: kOpenHandBorderRadius4,
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
                                        borderRadius: kOpenHandBorderRadius4,
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
                              kOpenHandGap4,
                              Text(
                                g.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: kOpenHandMonospaceFontFamily,
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

  Widget _buildEmpty(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    return OpenHandInlineEmptyState(
      icon: Icons.insights_rounded,
      dense: true,
      message:
          loc?.webReverseSignatureDiffEmptyHint ??
          'Hit the same API multiple times in Network panel, then return to analyze.',
    );
  }

  Widget _buildDetail(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
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
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _copyReport(g, loc),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(
                  loc?.webReverseSignatureDiffCopyReport ?? 'Copy report',
                ),
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
                loc?.webReverseSignatureDiffStable ?? 'Stable',
                g.stableCount,
                cs.secondaryContainer,
                cs.onSecondaryContainer,
              ),
              _summaryChip(
                cs,
                loc?.webReverseSignatureDiffDynamic ?? 'Dynamic',
                g.dynamicCount,
                cs.errorContainer,
                cs.onErrorContainer,
              ),
              _summaryChip(
                cs,
                loc?.webReverseSignatureDiffIncreasing ?? 'Increasing',
                g.increasingCount,
                cs.tertiaryContainer,
                cs.onTertiaryContainer,
              ),
              _summaryChip(
                cs,
                loc?.webReverseSignatureDiffFixedHash ?? 'Fixed-len hash',
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
                _section(
                  theme,
                  cs,
                  loc?.webReverseSignatureDiffSectionQuery ?? 'Query',
                  g.queryFields,
                ),
              if (g.headerFields.isNotEmpty)
                _section(
                  theme,
                  cs,
                  loc?.webReverseSignatureDiffSectionHeaders ?? 'Headers',
                  g.headerFields,
                ),
              if (g.bodyFields.isNotEmpty)
                _section(
                  theme,
                  cs,
                  loc?.webReverseSignatureDiffSectionBody ?? 'Body fields',
                  g.bodyFields,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(ColorScheme cs, String label, int n, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: kOpenHandPillBorderRadius,
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
              borderRadius: kOpenHandBorderRadius8,
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
              borderRadius: kOpenHandBorderRadius4,
            ),
            child: Text(
              tagText,
              style: TextStyle(
                color: tagFg,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                fontFamily: kOpenHandMonospaceFontFamily,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  _formatValuesPreview(f),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: kOpenHandMonospaceFontFamily,
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

  Future<void> _copyReport(_EndpointGroup g, AppLocalizations? loc) async {
    final buf = StringBuffer()
      ..writeln(
        '# ${loc?.webReverseSignatureDiffReportTitle ?? 'Signature Diff'}: ${g.key}',
      )
      ..writeln(
        '${loc?.webReverseSignatureDiffReportSamples ?? 'samples'}: ${g.samples.length}',
      )
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

    dumpSection('Query', g.queryFields);
    dumpSection('Headers', g.headerFields);
    dumpSection('Body', g.bodyFields);
    await copyWebReverseTextToClipboard(
      context: context,
      text: buf.toString(),
      successBase:
          loc?.webReverseSignatureDiffReportCopied ??
          'Report copied to clipboard',
      logTag: 'web_reverse_signature_diff_dialog',
      logAction: '复制签名差异报告',
    );
  }
}

List<_EndpointGroup> _analyse(List<CdpNetworkEntry> entries) {
  final buckets = <String, _EndpointGroup>{};
  for (final e in entries) {
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
    decodeQueryParametersAll(uri.query).forEach((k, vs) {
      map.putIfAbsent(k, () => <String>[]).add(vs.join(','));
    });
  }
  return _classifyAll(map);
}

List<_FieldStat> _diffHeaders(List<CdpNetworkEntry> samples) {
  const ignored = <String>{
    'content-length',
    kContentTypeHeaderName,
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
    final ct =
        (e.requestHeaders['Content-Type'] ??
                e.requestHeaders[kContentTypeHeaderName] ??
                '')
            .toLowerCase();
    if (ct.contains('json') || _looksLikeJson(body)) {
      _flattenJson(body, map);
    } else if (ct.contains('form-urlencoded') || body.contains('=')) {
      _flattenForm(body, map);
    } else {
      map
          .putIfAbsent('(raw body)', () => <String>[])
          .add(clipTextWithEllipsis(body, 80));
    }
  }
  return _classifyAll(map);
}

bool _looksLikeJson(String s) {
  final t = s.trimLeft();
  return t.startsWith('{') || t.startsWith('[');
}

void _flattenJson(String body, Map<String, List<String>> out) {
  final decoded = tryDecodeJson(body);
  if (decoded == null) return;
  void walk(Object? node, String path) {
    if (node is Map) {
      node.forEach((k, v) {
        walk(v, path.isEmpty ? '$k' : '$path.$k');
      });
    } else if (node is List) {
      if (node.isNotEmpty) walk(node.first, '$path[]');
    } else {
      out.putIfAbsent(path, () => <String>[]).add(node?.toString() ?? '');
    }
  }

  walk(decoded, '');
}

void _flattenForm(String body, Map<String, List<String>> out) {
  decodeQueryParametersAll(body, requireValueSeparator: true).forEach(
    (key, values) => out.putIfAbsent(key, () => <String>[]).addAll(values),
  );
}

List<_FieldStat> _classifyAll(Map<String, List<String>> map) {
  final out = <_FieldStat>[];
  map.forEach((k, vs) {
    out.add(_classify(k, vs));
  });
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
    return _FieldStat(
      name: name,
      values: unique,
      classification: _FieldClass.stable,
    );
  }
  // 全部能解析为数字 → 检查严格递增
  final asInts = <int>[];
  var allInt = true;
  for (final v in values) {
    final n = optionalIntFromValue(v);
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
  return _FieldStat(
    name: name,
    values: unique,
    classification: _FieldClass.dynamic_,
  );
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

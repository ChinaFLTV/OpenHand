/// API 集合导出面板。
///
/// 把已抓到的 HTTP 请求一次性转换成 Postman v2.1 / Insomnia v4 /
/// Bruno (.bru 拼接文本) / cURL 列表 / HAR 1.2 五种主流格式之一，
/// 复制到剪贴板。可按 URL 子串过滤，避免把大量静态资源也带进集合。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

enum _CollectionFormat { postman, insomnia, bruno, curl, har }

const int _kCollectionExportMaxEntries = 200;

Future<void> showWebReverseCollectionExportDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _CollectionExportDialog(controller: controller),
  );
}

class _CollectionExportDialog extends StatefulWidget {
  const _CollectionExportDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_CollectionExportDialog> createState() =>
      _CollectionExportDialogState();
}

class _CollectionExportDialogState extends State<_CollectionExportDialog> {
  _CollectionFormat _format = _CollectionFormat.postman;
  final TextEditingController _filterCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController(
    text: 'OpenHand Capture',
  );
  bool _xhrOnly = true;

  @override
  void dispose() {
    _filterCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  List<CdpNetworkEntry> _selected() {
    final filter = _filterCtrl.text.trim().toLowerCase();
    final all = widget.controller.networkRequests;
    return all.where((e) {
      if (_xhrOnly) {
        final rt = e.resourceType.toLowerCase();
        if (rt != 'xhr' && rt != 'fetch') return false;
      }
      if (filter.isEmpty) return true;
      return e.url.toLowerCase().contains(filter);
    }).toList();
  }

  String _buildOutput(List<CdpNetworkEntry> entries) {
    switch (_format) {
      case _CollectionFormat.postman:
        return _buildPostman(entries);
      case _CollectionFormat.insomnia:
        return _buildInsomnia(entries);
      case _CollectionFormat.bruno:
        return _buildBruno(entries);
      case _CollectionFormat.curl:
        return _buildCurlList(entries);
      case _CollectionFormat.har:
        return _buildHar(entries);
    }
  }

  String _buildPostman(List<CdpNetworkEntry> entries) {
    final items = entries.map((e) {
      final uri = Uri.tryParse(e.url);
      final headerArr = e.requestHeaders.entries
          .map((h) => <String, Object?>{'key': h.key, 'value': h.value})
          .toList();
      return <String, Object?>{
        'name': '${e.method} ${uri?.path ?? e.url}',
        'request': <String, Object?>{
          'method': e.method,
          'header': headerArr,
          if (e.requestPostData != null)
            'body': <String, Object?>{'mode': 'raw', 'raw': e.requestPostData},
          'url': <String, Object?>{
            'raw': e.url,
            if (uri != null) ...{
              'protocol': uri.scheme,
              'host': uri.host.split('.'),
              if (uri.hasPort) 'port': '${uri.port}',
              'path': uri.pathSegments,
              if (uri.hasQuery)
                'query': uri.queryParameters.entries
                    .map(
                      (q) => <String, Object?>{'key': q.key, 'value': q.value},
                    )
                    .toList(),
            },
          },
        },
      };
    }).toList();
    return prettyPrintJson(<String, Object?>{
      'info': <String, Object?>{
        'name': _nameCtrl.text.trim().isEmpty
            ? 'OpenHand Capture'
            : _nameCtrl.text.trim(),
        '_postman_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'schema':
            'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': items,
    });
  }

  String _buildInsomnia(List<CdpNetworkEntry> entries) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final wsId = 'wrk_openhand_$now';
    final resources = <Map<String, Object?>>[
      <String, Object?>{
        '_id': wsId,
        '_type': 'workspace',
        'name': _nameCtrl.text.trim().isEmpty
            ? 'OpenHand Capture'
            : _nameCtrl.text.trim(),
      },
      ...entries.asMap().entries.map((kv) {
        final i = kv.key;
        final e = kv.value;
        return <String, Object?>{
          '_id': 'req_openhand_${now}_$i',
          '_type': 'request',
          'parentId': wsId,
          'method': e.method,
          'url': e.url,
          'name': '${e.method} ${Uri.tryParse(e.url)?.path ?? e.url}',
          'headers': e.requestHeaders.entries
              .map((h) => <String, Object?>{'name': h.key, 'value': h.value})
              .toList(),
          if (e.requestPostData != null)
            'body': <String, Object?>{
              'mimeType':
                  e.requestHeaders[kContentTypeHeaderName] ?? kApplicationJsonMimeType,
              'text': e.requestPostData,
            },
        };
      }),
    ];
    return prettyPrintJson(<String, Object?>{
      '_type': 'export',
      '__export_format': 4,
      '__export_date': DateTime.now().toUtc().toIso8601String(),
      '__export_source': 'openhand.web_reverse',
      'resources': resources,
    });
  }

  String _buildBruno(List<CdpNetworkEntry> entries) {
    final buf = StringBuffer()
      ..writeln('# Bruno collection (concat) — split each `--- request ---`')
      ..writeln('# Name: ${_nameCtrl.text.trim()}')
      ..writeln();
    for (final e in entries) {
      buf
        ..writeln('--- request ---')
        ..writeln('meta {')
        ..writeln('  name: ${e.method} ${Uri.tryParse(e.url)?.path ?? e.url}')
        ..writeln('  type: http')
        ..writeln('}')
        ..writeln()
        ..writeln('${e.method.toLowerCase()} {')
        ..writeln('  url: ${e.url}')
        ..writeln('  body: ${e.requestPostData == null ? 'none' : 'json'}')
        ..writeln('}');
      if (e.requestHeaders.isNotEmpty) {
        buf.writeln('headers {');
        for (final h in e.requestHeaders.entries) {
          buf.writeln('  ${h.key}: ${h.value}');
        }
        buf.writeln('}');
      }
      if (e.requestPostData != null) {
        buf
          ..writeln('body:json {')
          ..writeln(e.requestPostData)
          ..writeln('}');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  String _buildCurlList(List<CdpNetworkEntry> entries) {
    final buf = StringBuffer();
    for (final e in entries) {
      buf.write("curl -X ${e.method} '${e.url}'");
      for (final h in e.requestHeaders.entries) {
        buf.write(" \\\n  -H '${h.key}: ${_escSingle(h.value)}'");
      }
      if (e.requestPostData != null) {
        buf.write(" \\\n  --data-raw '${_escSingle(e.requestPostData!)}'");
      }
      buf.writeln();
      buf.writeln();
    }
    return buf.toString();
  }

  String _buildHar(List<CdpNetworkEntry> entries) {
    final harEntries = entries.map((e) {
      final uri = Uri.tryParse(e.url);
      return <String, Object?>{
        'startedDateTime': e.timestamp.toUtc().toIso8601String(),
        'time': 0,
        'request': <String, Object?>{
          'method': e.method,
          'url': e.url,
          'httpVersion': e.protocol ?? 'HTTP/1.1',
          'headers': e.requestHeaders.entries
              .map((h) => <String, Object?>{'name': h.key, 'value': h.value})
              .toList(),
          'queryString': (uri?.queryParameters ?? const <String, String>{})
              .entries
              .map((q) => <String, Object?>{'name': q.key, 'value': q.value})
              .toList(),
          if (e.requestPostData != null)
            'postData': <String, Object?>{
              'mimeType':
                  e.requestHeaders[kContentTypeHeaderName] ?? kApplicationJsonMimeType,
              'text': e.requestPostData,
            },
          'headersSize': -1,
          'bodySize': e.requestPostData?.length ?? 0,
          'cookies': <Object?>[],
        },
        'response': <String, Object?>{
          'status': e.statusCode ?? 0,
          'statusText': e.statusText ?? '',
          'httpVersion': e.protocol ?? 'HTTP/1.1',
          'headers': e.responseHeaders.entries
              .map((h) => <String, Object?>{'name': h.key, 'value': h.value})
              .toList(),
          'content': <String, Object?>{
            'size': e.decodedBodyLength ?? 0,
            'mimeType': e.mimeType ?? '',
            if (e.cachedBody != null) 'text': e.cachedBody,
            if (e.cachedBodyBase64) 'encoding': 'base64',
          },
          'redirectURL': '',
          'headersSize': -1,
          'bodySize': e.encodedDataLength ?? 0,
          'cookies': <Object?>[],
        },
        'cache': <String, Object?>{},
        'timings': <String, Object?>{'send': 0, 'wait': 0, 'receive': 0},
      };
    }).toList();
    return prettyPrintJson(<String, Object?>{
      'log': <String, Object?>{
        'version': '1.2',
        'creator': <String, Object?>{
          'name': 'OpenHand WebReverse',
          'version': '1.0',
        },
        'entries': harEntries,
      },
    });
  }


  String _escSingle(String s) => s.replaceAll("'", r"'\''");

  Future<void> _copy() async {
    final loc = AppLocalizations.of(context);
    final entries = _selected();
    if (entries.isEmpty) {
      showOpenHandErrorSnack(
        context,
        loc?.webReverseCollectionExportNothing ?? 'Nothing to export',
      );
      return;
    }
    try {
      final exportEntries = entries
          .take(_kCollectionExportMaxEntries)
          .toList(growable: false);
      final out = _buildOutput(exportEntries);
      final copyResult = await copyWebReverseTextToClipboard(
        context: context,
        text: out,
        logTag: 'web_reverse_collection_export',
        showSuccess: false,
      );
      if (copyResult == null) return;
      if (!mounted) return;
      final capped = entries.length > exportEntries.length;
      final copiedLabel =
          loc?.webReverseCollectionExportCopied(exportEntries.length) ??
          'Copied ${exportEntries.length} requests to clipboard';
      final cappedSuffix = openHandLocalizedText(
        context,
        zh: ' · 已按条目上限裁剪',
        zhHant: ' · 已依條目上限裁剪',
        en: ' · entry capped',
        fr: ' · limite d’entrées atteinte',
        de: ' · Eintragslimit erreicht',
        ja: ' · 件数上限で切り詰め',
      );
      final message = capped ? '$copiedLabel$cappedSuffix' : copiedLabel;
      showWebReverseClipboardSuccessSnack(
        context: context,
        base: message,
        result: copyResult,
      );
    } catch (e, st) {
      silentLog('web_reverse_collection_export', '复制导出集合', e, st);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导出失败：$e',
          zhHant: '匯出失敗：$e',
          en: 'Export failed: $e',
          fr: 'Échec de l’export : $e',
          de: 'Export fehlgeschlagen: $e',
          ja: 'エクスポートに失敗しました: $e',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final entries = _selected();
    final preview = entries.isEmpty
        ? (loc?.webReverseCollectionExportNoMatch ??
              '// No matching requests.\n// Adjust the filter or turn off "XHR/Fetch only".')
        : _buildOutput(entries.take(2).toList());

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthExtraWide,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.ios_share_rounded,
            title: loc?.webReverseCollectionExportTitle ?? 'Export Collection',
            subtitle:
                loc?.webReverseCollectionExportSubtitle ??
                'Postman / Insomnia / Bruno / cURL / HAR — copy to clipboard',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _CollectionFormat.values.map((f) {
                final selected = _format == f;
                return ChoiceChip(
                  label: Text(_labelOf(f)),
                  selected: selected,
                  onSelected: (_) => setState(() => _format = f),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText:
                          loc?.webReverseCollectionExportName ??
                          'Collection name',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText:
                          loc?.webReverseCollectionExportUrlFilter ??
                          'URL filter',
                      prefixIcon: const Icon(
                        Icons.filter_alt_rounded,
                        size: 18,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                kOpenHandHGap8,
                FilterChip(
                  label: Text(
                    loc?.webReverseCollectionExportXhrOnly ?? 'XHR/Fetch only',
                  ),
                  selected: _xhrOnly,
                  onSelected: (v) => setState(() => _xhrOnly = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    loc?.webReverseCollectionExportMatchCount(
                          entries.length,
                          widget.controller.networkRequestCount,
                        ) ??
                        '${entries.length} match · ${widget.controller.networkRequestCount} total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                kOpenHandHGap8,
                Flexible(
                  child: Text(
                    '${loc?.webReverseCollectionExportPreview2 ?? 'Preview: first 2 entries'} · ${openHandLocalizedText(context, zh: '导出上限', zhHant: '匯出上限', en: 'export cap', fr: 'limite d’export', de: 'Exportlimit', ja: 'エクスポート上限')} $_kCollectionExportMaxEntries',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          kOpenHandGap8,
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview,
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.all(12),
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseCollectionExportClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
              OpenHandDialogActionButton.primary(
                label:
                    loc?.webReverseCollectionExportCopyAction ??
                    'Copy collection',
                onPressed: entries.isEmpty ? null : _copy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _labelOf(_CollectionFormat f) {
    switch (f) {
      case _CollectionFormat.postman:
        return 'Postman v2.1';
      case _CollectionFormat.insomnia:
        return 'Insomnia v4';
      case _CollectionFormat.bruno:
        return 'Bruno (.bru)';
      case _CollectionFormat.curl:
        return 'cURL list';
      case _CollectionFormat.har:
        return 'HAR 1.2';
    }
  }
}

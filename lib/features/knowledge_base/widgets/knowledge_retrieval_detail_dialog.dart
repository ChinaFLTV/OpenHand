import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/knowledge_message_metadata.dart';

Future<void> showKnowledgeRetrievalDetailDialog(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeRetrievalDetailDialog(metadata: metadata),
  );
}

class KnowledgeRetrievalDetailDialog extends StatelessWidget {
  const KnowledgeRetrievalDetailDialog({super.key, required this.metadata});

  final Map<String, Object?> metadata;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final kb =
        KnowledgeMessageMetadata.fromMessageMetadata(metadata) ??
        const <String, Object?>{};
    final results = _listOfMaps(kb['results']);
    final prompt = KnowledgeMessageMetadata.promptAppendContent(metadata);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '引用知识库详情' : 'Knowledge Base References'),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(
                context,
                title: isZh ? '总览' : 'Overview',
                rows: {
                  'status': kb['status'],
                  'query': kb['query'],
                  'error': kb['error'],
                },
              ),
              _section(
                context,
                title: isZh ? 'Embedding' : 'Embedding',
                rows: _map(kb['embedding']),
              ),
              _section(
                context,
                title: isZh ? '检索参数' : 'Retrieval Parameters',
                rows: _map(kb['retrieval']),
              ),
              _section(
                context,
                title: isZh ? 'Prompt 追加' : 'Prompt Append',
                rows: _map(kb['prompt_append']),
              ),
              const SizedBox(height: 12),
              Text(
                isZh
                    ? '命中 chunks (${results.length})'
                    : 'Hit chunks (${results.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final hit in results) _HitCard(hit: hit),
              const SizedBox(height: 12),
              Text(
                isZh ? '实际追加给模型的上下文' : 'Actual context appended to the model',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SelectableText(
                prompt.isEmpty ? '-' : prompt,
                style: const TextStyle(fontFamily: 'monospace', height: 1.35),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(kb),
              ),
            );
            if (context.mounted) {
              OpenHandSnackBar.showSuccess(
                context,
                isZh ? '已复制知识库 metadata。' : 'Knowledge metadata copied.',
              );
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: Text(isZh ? '复制 metadata' : 'Copy metadata'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '关闭' : 'Close'),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Map<String, Object?> rows,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: SelectableText(_value(entry.value))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _listOfMaps(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  String _value(Object? value) {
    if (value == null) return '-';
    if (value is Map || value is List) return jsonEncode(value);
    final text = '$value'.trim();
    return text.isEmpty ? '-' : text;
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({required this.hit});

  final Map<String, Object?> hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${hit['title'] ?? hit['source_title'] ?? hit['chunk_id'] ?? 'KB hit'}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${hit['path'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pill(context, 'score ${hit['score'] ?? '-'}'),
                if (hit['rerank_score'] != null)
                  _pill(context, 'rerank ${hit['rerank_score']}'),
                if (hit['token_estimate'] != null)
                  _pill(context, '${hit['token_estimate']} tokens'),
                if ('${hit['document_time'] ?? ''}'.trim().isNotEmpty)
                  _pill(context, '${hit['document_time']}'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${hit['preview'] ?? ''}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

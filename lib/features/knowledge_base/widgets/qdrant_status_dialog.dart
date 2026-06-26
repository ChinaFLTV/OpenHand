import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../service/qdrant_monitoring_service.dart';

Future<void> showQdrantStatusDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const QdrantStatusDialog(),
  );
}

class QdrantStatusDialog extends StatelessWidget {
  const QdrantStatusDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KnowledgeBaseController>();
    final isZh = openHandIsChineseLocale(context);
    return FutureBuilder<QdrantMonitoringSnapshot>(
      future: controller.loadMonitoringSnapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        return buildOpenHandAlertDialog(
          title: Text(isZh ? 'Qdrant 运行状态' : 'Qdrant Runtime Status'),
          content: buildOpenHandDialogConstrainedContent(
            width: 760,
            maxHeight: MediaQuery.sizeOf(context).height * 0.76,
            child: snapshot.connectionState != ConnectionState.done
                ? const SizedBox(
                    height: 260,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : data == null
                ? Text(
                    isZh ? '无法读取 Qdrant 状态。' : 'Unable to read Qdrant status.',
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in data.sections.entries)
                          _StatusSection(
                            title: section.key,
                            values: section.value,
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            if (data != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent(
                        '  ',
                      ).convert(data.sections),
                    ),
                  );
                  if (context.mounted) {
                    OpenHandSnackBar.showSuccess(
                      context,
                      isZh ? '诊断信息已复制。' : 'Diagnostics copied.',
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(isZh ? '复制诊断' : 'Copy diagnostics'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(isZh ? '关闭' : 'Close'),
            ),
          ],
        );
      },
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.title, required this.values});

  final String title;
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final entry in values.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 190,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        entry.value is Map || entry.value is List
                            ? jsonEncode(entry.value)
                            : '${entry.value ?? '-'}',
                      ),
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

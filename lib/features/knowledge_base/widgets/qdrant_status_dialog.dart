import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../service/qdrant_monitoring_service.dart';
import 'knowledge_dialog_widgets.dart';

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
                ? KnowledgeDialogNotice(
                    icon: Icons.warning_amber_rounded,
                    error: true,
                    message: isZh
                        ? '无法读取 Qdrant 状态。'
                        : 'Unable to read Qdrant status.',
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final section in data.sections.entries)
                          _StatusSection(
                            title: section.key,
                            values: section.value,
                            isZh: isZh,
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            if (data != null)
              OpenHandDialogActionButton.secondary(
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
                icon: Icons.copy_rounded,
                label: isZh ? '复制诊断' : 'Copy diagnostics',
              ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: isZh ? '关闭' : 'Close',
            ),
          ],
        );
      },
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.title,
    required this.values,
    required this.isZh,
  });

  final String title;
  final Map<String, Object?> values;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    return KnowledgeDialogSection(
      title: _localizedSectionTitle(title),
      icon: Icons.monitor_heart_outlined,
      child: KnowledgeDialogKeyValueList(
        rows: {
          for (final entry in values.entries)
            _localizedMetricLabel(entry.key): _localizedMetricValue(
              entry.key,
              entry.value,
            ),
        },
        labelWidth: isZh ? 190 : 210,
      ),
    );
  }

  String _localizedSectionTitle(String value) {
    if (isZh) return value;
    return switch (value) {
      '总览' => 'Overview',
      'Qdrant API 指标' => 'Qdrant API Metrics',
      'OpenHand 知识库指标' => 'OpenHand Knowledge Metrics',
      _ => value,
    };
  }

  String _localizedMetricLabel(String value) {
    if (isZh) return value;
    return switch (value) {
      '服务状态' => 'Service status',
      '当前 collection' => 'Current collection',
      '最近健康检查时间' => 'Last health check',
      'collections 总数' => 'Collections total',
      '单机模式' => 'Single-node mode',
      'payload index 状态' => 'Payload index status',
      'source 数' => 'Sources',
      'chunk 数' => 'Chunks',
      '待 embedding job 数' => 'Pending embedding jobs',
      '失败 job 数' => 'Failed jobs',
      '当前 embedding model' => 'Current embedding model',
      '当前 dimensions' => 'Current dimensions',
      _ => value,
    };
  }

  Object? _localizedMetricValue(String key, Object? value) {
    if (isZh) return value;
    if (key == 'payload index 状态' && value == '可在管理弹窗检查/重建') {
      return 'Inspect or rebuild in Qdrant Admin';
    }
    return value;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_vector_distribution.dart';
import 'knowledge_dialog_widgets.dart';
import 'knowledge_vector_distribution_view.dart';

Future<void> showKnowledgeVectorDistributionDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const KnowledgeVectorDistributionDialog(),
  );
}

class KnowledgeVectorDistributionDialog extends StatefulWidget {
  const KnowledgeVectorDistributionDialog({super.key});

  @override
  State<KnowledgeVectorDistributionDialog> createState() =>
      _KnowledgeVectorDistributionDialogState();
}

class _KnowledgeVectorDistributionDialogState
    extends State<KnowledgeVectorDistributionDialog> {
  late Future<KnowledgeVectorDistribution> _future = _load();

  Future<KnowledgeVectorDistribution> _load() {
    return context.read<KnowledgeBaseController>().loadVectorDistribution();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '向量分布' : 'Vector Distribution'),
      content: buildOpenHandDialogConstrainedContent(
        width: 960,
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        child: FutureBuilder<KnowledgeVectorDistribution>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return SizedBox(
                height: 420,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        isZh
                            ? '正在采样并投影向量。'
                            : 'Sampling and projecting vectors.',
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return KnowledgeDialogNotice(
                icon: Icons.error_outline_rounded,
                message: '${snapshot.error}',
                tone: KnowledgeDialogNoticeTone.error,
              );
            }
            final distribution = snapshot.data;
            if (distribution == null || distribution.isEmpty) {
              return KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: isZh
                    ? '当前 collection 没有可展示的向量。'
                    : 'The current collection has no vectors to display.',
              );
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KnowledgeVectorDistributionView(
                    distribution: distribution,
                    height: 520,
                  ),
                  const SizedBox(height: 12),
                  KnowledgeDialogSection(
                    title: isZh ? '投影说明' : 'Projection',
                    icon: Icons.account_tree_outlined,
                    margin: EdgeInsets.zero,
                    child: KnowledgeDialogKeyValueList(
                      rows: {
                        isZh ? '算法' : 'Algorithm': distribution.algorithm,
                        isZh ? '原始维度' : 'Original dimensions':
                            distribution.originalDimensions,
                        isZh ? '展示点数' : 'Visible points':
                            distribution.points.length,
                        isZh ? '是否采样' : 'Sampled': distribution.hasMore,
                        if (distribution.durationMs != null)
                          isZh ? '耗时毫秒' : 'Duration ms':
                              distribution.durationMs,
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () {
            setState(() => _future = _load());
          },
          icon: Icons.refresh_rounded,
          label: isZh ? '重新采样' : 'Resample',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
}

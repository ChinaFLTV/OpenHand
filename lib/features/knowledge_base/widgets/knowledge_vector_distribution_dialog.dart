import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
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

  Future<KnowledgeVectorDistribution> _load() =>
      context.read<KnowledgeBaseController>().loadVectorDistribution();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return buildOpenHandAlertDialog(
      title: Text(l10n.knowledgeVectorDistributionTitle),
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
                      kOpenHandGap14,
                      Text(l10n.knowledgeVectorDistributionLoading),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return KnowledgeDialogNotice(
                icon: Icons.error_outline_rounded,
                message: knowledgeBaseFailureMessage(
                  snapshot.error!,
                  fallback: '加载知识向量分布失败，请稍后重试。',
                ),
                tone: KnowledgeDialogNoticeTone.error,
              );
            }
            final distribution = snapshot.data;
            if (distribution == null || distribution.isEmpty) {
              return KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: l10n.knowledgeVectorDistributionEmpty,
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
                  kOpenHandGap12,
                  KnowledgeDialogSection(
                    title: l10n.knowledgeVectorProjectionSection,
                    icon: Icons.account_tree_outlined,
                    margin: EdgeInsets.zero,
                    child: KnowledgeDialogKeyValueList(
                      rows: {
                        l10n.knowledgeVectorAlgorithm: distribution.algorithm,
                        l10n.knowledgeVectorOriginalDimensions:
                            distribution.originalDimensions,
                        l10n.knowledgeVectorVisiblePoints:
                            distribution.points.length,
                        l10n.knowledgeVectorSampled: distribution.hasMore,
                        if (distribution.durationMs != null)
                          l10n.knowledgeVectorDurationMs:
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
            setState(() {
              _future = _load();
            });
          },
          icon: Icons.refresh_rounded,
          label: l10n.knowledgeVectorResample,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonClose,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
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
    return FutureBuilder<KnowledgeVectorDistribution>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        return OpenHandEditorDialogScaffold(
          title: l10n.knowledgeVectorDistributionTitle,
          subtitle: snapshot.connectionState != ConnectionState.done
              ? l10n.knowledgeVectorDistributionLoading
              : l10n.knowledgeVectorProjectionSection,
          icon: Icons.scatter_plot_outlined,
          iconColor: OpenHandStatusColors.info,
          busy: loading,
          maxWidth: kOpenHandDialogWidthExtraWide,
          maxHeight: kOpenHandDialogHeightFull,
          body: _buildBody(context, l10n, snapshot),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: loading
                  ? null
                  : () {
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
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    AsyncSnapshot<KnowledgeVectorDistribution> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return KnowledgeDialogSection(
        title: l10n.knowledgeVectorDistributionTitle,
        icon: Icons.scatter_plot_outlined,
        accent: OpenHandStatusColors.info,
        margin: EdgeInsets.zero,
        child: KnowledgeDialogLoading(
          height: 280,
          message: l10n.knowledgeVectorDistributionLoading,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnowledgeDialogSection(
          title: l10n.knowledgeVectorDistributionTitle,
          icon: Icons.scatter_plot_outlined,
          accent: OpenHandStatusColors.info,
          subtitle: l10n.knowledgeVectorProjectionSection,
          child: KnowledgeVectorDistributionView(
            distribution: distribution,
            height: 480,
          ),
        ),
        KnowledgeDialogSection(
          title: l10n.knowledgeVectorProjectionSection,
          icon: Icons.account_tree_outlined,
          accent: Theme.of(context).colorScheme.tertiary,
          margin: EdgeInsets.zero,
          child: KnowledgeDialogKeyValueList(
            rows: {
              l10n.knowledgeVectorAlgorithm: distribution.algorithm,
              l10n.knowledgeVectorOriginalDimensions:
                  distribution.originalDimensions,
              l10n.knowledgeVectorVisiblePoints: distribution.points.length,
              l10n.knowledgeVectorSampled: distribution.hasMore,
              if (distribution.durationMs != null)
                l10n.knowledgeVectorDurationMs: distribution.durationMs,
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
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
          subtitle: _subtitle(l10n, snapshot),
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

  String _subtitle(
    AppLocalizations l10n,
    AsyncSnapshot<KnowledgeVectorDistribution> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return l10n.knowledgeVectorDistributionLoading;
    }
    if (snapshot.hasError || snapshot.data == null || snapshot.data!.isEmpty) {
      return l10n.knowledgeVectorProjectionSection;
    }
    final distribution = snapshot.data!;
    return '${distribution.algorithm} · ${distribution.points.length}';
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    AsyncSnapshot<KnowledgeVectorDistribution> snapshot,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return KnowledgeDialogLoading(
        height: 280,
        message: l10n.knowledgeVectorDistributionLoading,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OpenHandFactChip(
              icon: Icons.auto_awesome_outlined,
              label:
                  '${l10n.knowledgeVectorAlgorithm} · ${distribution.algorithm}',
              color: colorScheme.primary,
            ),
          ],
        ),
        kOpenHandGap12,
        KnowledgeDialogMetricGrid(
          items: [
            KnowledgeDialogMetric(
              icon: Icons.grid_4x4_rounded,
              label: l10n.knowledgeVectorOriginalDimensions,
              value: '${distribution.originalDimensions}',
              accent: colorScheme.tertiary,
            ),
            KnowledgeDialogMetric(
              icon: Icons.scatter_plot_outlined,
              label: l10n.knowledgeVectorVisiblePoints,
              value: '${distribution.points.length}',
              accent: OpenHandStatusColors.info,
            ),
            KnowledgeDialogMetric(
              icon: Icons.filter_alt_outlined,
              label: l10n.knowledgeVectorSampled,
              value: distribution.hasMore
                  ? openHandLocalizedText(
                      context,
                      zh: '已采样',
                      zhHant: '已取樣',
                      en: 'Sampled',
                      fr: 'Échantillonné',
                      de: 'Abgetastet',
                      ja: 'サンプル済み',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: '全量',
                      zhHant: '全量',
                      en: 'Full',
                      fr: 'Complet',
                      de: 'Vollständig',
                      ja: '全量',
                    ),
              accent: OpenHandStatusColors.warning,
            ),
            if (distribution.durationMs != null)
              KnowledgeDialogMetric(
                icon: Icons.timer_outlined,
                label: l10n.knowledgeVectorDurationMs,
                value: '${distribution.durationMs}',
                accent: OpenHandStatusColors.success,
              ),
          ],
        ),
        kOpenHandGap12,
        KnowledgeDialogSection(
          title: l10n.knowledgeVectorProjectionSection,
          icon: Icons.threed_rotation_rounded,
          accent: OpenHandStatusColors.info,
          margin: EdgeInsets.zero,
          child: KnowledgeVectorDistributionView(
            distribution: distribution,
            height: 480,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';

class WorkflowsView extends StatelessWidget {
  const WorkflowsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FeaturePageShell(
      title: l10n.workflowsTitle,
      subtitle: l10n.workflowsSubtitle,
      actions: FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.workflowsNew),
      ),
      body: SizedBox.expand(
        child: FeatureStateCard.centered(
          icon: Icons.account_tree_outlined,
          tone: FeatureStateTone.neutral,
          title: l10n.workflowsEmptyTitle,
          body: l10n.workflowsEmptyBody,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/util/localized_text.dart';

class AgentsView extends StatelessWidget {
  const AgentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return FeaturePageShell(
      title: openHandLocalizedText(context, zh: '智能体', en: 'Agents'),
      subtitle: openHandLocalizedText(
        context,
        zh: '面向 AI 数字员工、数字人与业务助理的统一编排入口；当前产品形态仍在打磨中。',
        en: 'A future orchestration home for AI digital employees, digital humans, and business assistants.',
      ),
      actions: const SizedBox.shrink(),
      body: const SizedBox.shrink(),
    );
  }
}

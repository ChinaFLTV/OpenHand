import 'package:flutter/widgets.dart';

import '../../../shared/util/localized_text.dart';
import '../model/ai_builtin_tool_config.dart'
    show
        AiBuiltinToolKind,
        agentBuiltinToolCanonicalName,
        agentBuiltinToolMetadata;

String agentBuiltinToolLabel(BuildContext context, AiBuiltinToolKind kind) {
  final metadata = agentBuiltinToolMetadata(kind);
  if (metadata == null) return agentBuiltinToolCanonicalName(kind);
  return openHandLocalizedText(
    context,
    zh: metadata.labelZh,
    en: metadata.labelEn,
  );
}

String agentBuiltinToolSummary(BuildContext context, AiBuiltinToolKind kind) {
  final metadata = agentBuiltinToolMetadata(kind);
  if (metadata == null) return kind.name;
  return openHandLocalizedText(
    context,
    zh: metadata.summaryZh,
    en: metadata.summaryEn,
  );
}

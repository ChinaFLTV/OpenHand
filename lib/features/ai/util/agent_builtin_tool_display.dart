import 'package:flutter/material.dart';

import '../../../shared/util/localized_text.dart';
import '../model/ai_builtin_tool_config.dart'
    show
        AiAgentBuiltinToolGroup,
        AiBuiltinToolKind,
        agentBuiltinToolCanonicalName,
        agentBuiltinToolMetadata;

/// 工具分组的图标：设置页分组卡片与数字员工工具选择器共用。
///
/// [group] 为 null 表示不属于任何数字员工分组的通用工具。
IconData agentBuiltinToolGroupIcon(AiAgentBuiltinToolGroup? group) {
  return switch (group) {
    AiAgentBuiltinToolGroup.discovery => Icons.travel_explore_rounded,
    AiAgentBuiltinToolGroup.taskLifecycle => Icons.playlist_add_check_rounded,
    AiAgentBuiltinToolGroup.governance => Icons.verified_user_outlined,
    AiAgentBuiltinToolGroup.operations => Icons.monitor_heart_outlined,
    AiAgentBuiltinToolGroup.cluster => Icons.account_tree_rounded,
    null => Icons.extension_rounded,
  };
}

/// 工具分组的名称，与 [agentBuiltinToolGroupIcon] 一一对应。
String agentBuiltinToolGroupLabel(
  BuildContext context,
  AiAgentBuiltinToolGroup? group,
) {
  return switch (group) {
    AiAgentBuiltinToolGroup.discovery => openHandLocalizedText(
      context,
      zh: '发现路由',
      en: 'Discovery',
    ),
    AiAgentBuiltinToolGroup.taskLifecycle => openHandLocalizedText(
      context,
      zh: '任务生命周期',
      en: 'Task lifecycle',
    ),
    AiAgentBuiltinToolGroup.governance => openHandLocalizedText(
      context,
      zh: '治理审计',
      en: 'Governance',
    ),
    AiAgentBuiltinToolGroup.operations => openHandLocalizedText(
      context,
      zh: '运营资源',
      en: 'Operations',
    ),
    AiAgentBuiltinToolGroup.cluster => openHandLocalizedText(
      context,
      zh: '集群调度',
      en: 'Cluster',
    ),
    null => openHandLocalizedText(context, zh: '其他工具', en: 'Other tools'),
  };
}

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

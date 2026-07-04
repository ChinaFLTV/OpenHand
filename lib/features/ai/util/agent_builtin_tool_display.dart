import 'package:flutter/widgets.dart';

import '../../../shared/util/localized_text.dart';
import '../model/ai_builtin_tool_config.dart' show AiBuiltinToolKind;

String agentBuiltinToolCanonicalName(AiBuiltinToolKind kind) {
  final name = kind.name;
  if (name.isEmpty) return '';
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

String agentBuiltinToolLabel(BuildContext context, AiBuiltinToolKind kind) {
  return switch (kind) {
    AiBuiltinToolKind.agentList => openHandLocalizedText(
      context,
      zh: '智能体列表',
      en: 'Agent list',
    ),
    AiBuiltinToolKind.agentDetail => openHandLocalizedText(
      context,
      zh: '智能体详情',
      en: 'Agent detail',
    ),
    AiBuiltinToolKind.agentActivityLog => openHandLocalizedText(
      context,
      zh: '活动记录',
      en: 'Activity log',
    ),
    AiBuiltinToolKind.agentAuditReport => openHandLocalizedText(
      context,
      zh: '审计报表',
      en: 'Audit report',
    ),
    AiBuiltinToolKind.agentAuditRecord => openHandLocalizedText(
      context,
      zh: '写入审计',
      en: 'Audit record',
    ),
    AiBuiltinToolKind.agentApprovalRequest => openHandLocalizedText(
      context,
      zh: '审批请求',
      en: 'Approval request',
    ),
    AiBuiltinToolKind.agentKpiUpsert => openHandLocalizedText(
      context,
      zh: 'KPI 维护',
      en: 'KPI upsert',
    ),
    AiBuiltinToolKind.agentResourceUpdate => openHandLocalizedText(
      context,
      zh: '资源更新',
      en: 'Resource update',
    ),
    AiBuiltinToolKind.agentClusterConfigure => openHandLocalizedText(
      context,
      zh: '集群配置',
      en: 'Cluster configure',
    ),
    AiBuiltinToolKind.agentClusterStatus => openHandLocalizedText(
      context,
      zh: '集群状态',
      en: 'Cluster status',
    ),
    AiBuiltinToolKind.agentTaskList => openHandLocalizedText(
      context,
      zh: '任务列表',
      en: 'Task list',
    ),
    AiBuiltinToolKind.agentTaskPublish => openHandLocalizedText(
      context,
      zh: '任务发布',
      en: 'Task publish',
    ),
    AiBuiltinToolKind.agentTaskTrack => openHandLocalizedText(
      context,
      zh: '任务追踪',
      en: 'Task track',
    ),
    AiBuiltinToolKind.agentTaskProgress => openHandLocalizedText(
      context,
      zh: '任务进度',
      en: 'Task progress',
    ),
    AiBuiltinToolKind.agentTaskCancel => openHandLocalizedText(
      context,
      zh: '任务取消',
      en: 'Task cancel',
    ),
    AiBuiltinToolKind.agentTaskPause => openHandLocalizedText(
      context,
      zh: '任务暂停',
      en: 'Task pause',
    ),
    AiBuiltinToolKind.agentTaskTerminate => openHandLocalizedText(
      context,
      zh: '任务终止',
      en: 'Task terminate',
    ),
    AiBuiltinToolKind.agentTaskResume => openHandLocalizedText(
      context,
      zh: '任务恢复',
      en: 'Task resume',
    ),
    AiBuiltinToolKind.agentTaskComplete => openHandLocalizedText(
      context,
      zh: '任务完成',
      en: 'Task complete',
    ),
    AiBuiltinToolKind.agentTaskResult => openHandLocalizedText(
      context,
      zh: '任务结果',
      en: 'Task result',
    ),
    _ => agentBuiltinToolCanonicalName(kind),
  };
}

String agentBuiltinToolSummary(BuildContext context, AiBuiltinToolKind kind) {
  return switch (kind) {
    AiBuiltinToolKind.agentList => openHandLocalizedText(
      context,
      zh: '发现可用智能体',
      en: 'Discover available agents',
    ),
    AiBuiltinToolKind.agentDetail => openHandLocalizedText(
      context,
      zh: '读取职责与绑定能力',
      en: 'Read profile and bindings',
    ),
    AiBuiltinToolKind.agentActivityLog => openHandLocalizedText(
      context,
      zh: '查看工作循环输出',
      en: 'Read work-loop output',
    ),
    AiBuiltinToolKind.agentAuditReport => openHandLocalizedText(
      context,
      zh: '汇总能力与任务审计',
      en: 'Summarize audit metrics',
    ),
    AiBuiltinToolKind.agentAuditRecord => openHandLocalizedText(
      context,
      zh: '记录能力调用审计',
      en: 'Write capability audit',
    ),
    AiBuiltinToolKind.agentApprovalRequest => openHandLocalizedText(
      context,
      zh: '提交 mentor 审批',
      en: 'Request mentor approval',
    ),
    AiBuiltinToolKind.agentKpiUpsert => openHandLocalizedText(
      context,
      zh: '创建或更新 KPI',
      en: 'Create or update KPI',
    ),
    AiBuiltinToolKind.agentResourceUpdate => openHandLocalizedText(
      context,
      zh: '登记资源占用',
      en: 'Record resource usage',
    ),
    AiBuiltinToolKind.agentClusterConfigure => openHandLocalizedText(
      context,
      zh: '调整 worker 池策略',
      en: 'Tune worker pool policy',
    ),
    AiBuiltinToolKind.agentClusterStatus => openHandLocalizedText(
      context,
      zh: '读取 worker 状态',
      en: 'Read worker status',
    ),
    AiBuiltinToolKind.agentTaskList => openHandLocalizedText(
      context,
      zh: '筛选任务台任务',
      en: 'Filter task desk',
    ),
    AiBuiltinToolKind.agentTaskPublish => openHandLocalizedText(
      context,
      zh: '向匹配智能体派发任务',
      en: 'Delegate matched work',
    ),
    AiBuiltinToolKind.agentTaskTrack => openHandLocalizedText(
      context,
      zh: '读取完整任务状态',
      en: 'Read full task state',
    ),
    AiBuiltinToolKind.agentTaskProgress => openHandLocalizedText(
      context,
      zh: '轮询进度与下一步',
      en: 'Poll progress and next step',
    ),
    AiBuiltinToolKind.agentTaskCancel => openHandLocalizedText(
      context,
      zh: '撤销队列或运行任务',
      en: 'Cancel queued or active task',
    ),
    AiBuiltinToolKind.agentTaskPause => openHandLocalizedText(
      context,
      zh: '暂停任务等待介入',
      en: 'Pause for intervention',
    ),
    AiBuiltinToolKind.agentTaskTerminate => openHandLocalizedText(
      context,
      zh: '异常终止并标记失败',
      en: 'Abort and mark failed',
    ),
    AiBuiltinToolKind.agentTaskResume => openHandLocalizedText(
      context,
      zh: '恢复暂停任务',
      en: 'Resume paused task',
    ),
    AiBuiltinToolKind.agentTaskComplete => openHandLocalizedText(
      context,
      zh: '回写任务结果',
      en: 'Write task result',
    ),
    AiBuiltinToolKind.agentTaskResult => openHandLocalizedText(
      context,
      zh: '读取终态结果',
      en: 'Read terminal result',
    ),
    _ => kind.name,
  };
}

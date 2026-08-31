import 'package:flutter/material.dart';

import 'model/workflow_definition.dart';

/// 工作流节点在编辑器与导出图中共用的视觉描述。
({String label, String description, IconData icon, Color color})
workflowNodeDescriptor(WorkflowNodeKind kind, ColorScheme colors) {
  return switch (kind) {
    WorkflowNodeKind.start => (
      label: '开始',
      description: '定义工作流的输入参数',
      icon: Icons.play_arrow_rounded,
      color: colors.primary,
    ),
    WorkflowNodeKind.condition => (
      label: '条件分支',
      description: '依据表达式选择后续路径',
      icon: Icons.call_split_rounded,
      color: colors.tertiary,
    ),
    WorkflowNodeKind.loop => (
      label: '循环',
      description: '按上限重复执行节点组',
      icon: Icons.loop_rounded,
      color: colors.secondary,
    ),
    WorkflowNodeKind.iteration => (
      label: '迭代',
      description: '逐项处理数组输入',
      icon: Icons.view_week_outlined,
      color: colors.primary,
    ),
    WorkflowNodeKind.parameterAssignment => (
      label: '参数赋值',
      description: '生成可供后续节点引用的参数',
      icon: Icons.assignment_turned_in_outlined,
      color: colors.secondary,
    ),
    WorkflowNodeKind.listOperation => (
      label: '列表操作',
      description: '筛选、截取、排序并限制数组',
      icon: Icons.filter_list_rounded,
      color: colors.tertiary,
    ),
    WorkflowNodeKind.codeExecution => (
      label: '代码执行',
      description: '运行 Python、JavaScript 或当前平台 Shell 代码',
      icon: Icons.code_rounded,
      color: colors.primary,
    ),
    WorkflowNodeKind.humanIntervention => (
      label: '人工介入',
      description: '暂停工作流并等待用户确认',
      icon: Icons.front_hand_outlined,
      color: colors.tertiary,
    ),
    WorkflowNodeKind.loopExit => (
      label: '退出循环',
      description: '立即结束当前循环',
      icon: Icons.exit_to_app_rounded,
      color: colors.error,
    ),
    WorkflowNodeKind.llm => (
      label: 'LLM',
      description: '调用模型完成推理与生成',
      icon: Icons.auto_awesome_rounded,
      color: colors.primary,
    ),
    WorkflowNodeKind.httpRequest => (
      label: 'HTTP 请求',
      description: '调用外部 HTTP API',
      icon: Icons.language_rounded,
      color: colors.secondary,
    ),
    WorkflowNodeKind.end => (
      label: '结束',
      description: '定义工作流的输出参数',
      icon: Icons.stop_rounded,
      color: colors.tertiary,
    ),
  };
}

bool isWorkflowControlFlowKind(WorkflowNodeKind kind) =>
    const <WorkflowNodeKind>{
      WorkflowNodeKind.condition,
      WorkflowNodeKind.loop,
      WorkflowNodeKind.iteration,
      WorkflowNodeKind.humanIntervention,
      WorkflowNodeKind.loopExit,
    }.contains(kind);

/// 与编辑器节点卡片一致的摘要文案。
String workflowNodeSummary(WorkflowNode node) {
  return switch (node.kind) {
    WorkflowNodeKind.start =>
      node.inputFields().isEmpty
          ? '暂无输入参数'
          : '${node.inputFields().length} 个输入参数',
    WorkflowNodeKind.llm =>
      node.stringSetting(WorkflowSettingKeys.prompt).trim().isEmpty
          ? '选择模型并编写提示词'
          : node.stringSetting(WorkflowSettingKeys.prompt).trim(),
    WorkflowNodeKind.httpRequest =>
      node.stringSetting(WorkflowSettingKeys.url).trim().isEmpty
          ? '配置请求方式、URL 与响应输出'
          : '${node.stringSetting(WorkflowSettingKeys.method, 'GET')}  ${node.stringSetting(WorkflowSettingKeys.url)}',
    WorkflowNodeKind.condition =>
      node.conditionCases().isEmpty
          ? node.stringSetting(WorkflowSettingKeys.expression)
          : '${node.conditionCases().length} 个条件分支 · ELSE',
    WorkflowNodeKind.loop =>
      '${node.loopVariables().length} 个循环变量 · 最多 ${node.intSetting(WorkflowSettingKeys.maxIterations, 10)} 次',
    WorkflowNodeKind.iteration =>
      '${node.boolSetting(WorkflowSettingKeys.iterationParallel) ? '并行' : '串行'}迭代 · ${node.stringSetting(WorkflowSettingKeys.iterationOutputName, 'iteration_result')}',
    WorkflowNodeKind.parameterAssignment =>
      node.outputFields().isEmpty
          ? '添加需要赋值的输出参数'
          : '${node.outputFields().length} 个赋值参数',
    WorkflowNodeKind.listOperation =>
      '${node.boolSetting(WorkflowSettingKeys.listFilterEnabled) ? '筛选 · ' : ''}${node.boolSetting(WorkflowSettingKeys.listOrderEnabled) ? '排序 · ' : ''}${node.boolSetting(WorkflowSettingKeys.listLimitEnabled) ? '限量' : '输出列表'}',
    WorkflowNodeKind.codeExecution =>
      '${WorkflowCodeLanguage.fromStorage(node.settings[WorkflowSettingKeys.codeLanguage]).label} · ${node.codeInputFields().length} 入 / ${node.outputFields().length} 出',
    WorkflowNodeKind.humanIntervention =>
      '${node.humanInputFields().length} 个输入 · ${node.humanActions().length} 个动作',
    WorkflowNodeKind.loopExit => '立即结束当前循环',
    WorkflowNodeKind.end =>
      node.outputFields().isEmpty
          ? '暂无输出参数'
          : '${node.outputFields().length} 个输出参数',
  };
}

/// 输入方向用 primary 与 onSurface 调和，避免 M3 secondary 在绿主题下偏紫红。
const double kWorkflowParameterInputAccentBlend = 0.38;

Color workflowParameterDirectionAccent(
  ColorScheme colors,
  WorkflowParameterDirection direction,
) => switch (direction) {
  WorkflowParameterDirection.input =>
    Color.lerp(
          colors.primary,
          colors.onSurface,
          kWorkflowParameterInputAccentBlend,
        ) ??
        colors.primary,
  WorkflowParameterDirection.output => colors.primary,
};

IconData workflowParameterDirectionIcon(WorkflowParameterDirection direction) =>
    switch (direction) {
      WorkflowParameterDirection.input => Icons.login_rounded,
      WorkflowParameterDirection.output => Icons.output_rounded,
    };

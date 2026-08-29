// Harness Engineering 阶段工具亲和矩阵，用于过滤无关能力并压缩上下文。

import '../../ai/index.dart';
import 'harness_phase.dart';

enum HarnessToolCategory {
  /// 文件系统操作。
  filesystem,

  /// 搜索工具。
  search,

  /// Shell 执行。
  shell,

  /// 版本控制。
  vcs,

  /// Web 操作。
  web,

  /// LSP 与诊断读取。
  lsp,

  /// 规划工具。
  planning,

  /// Skill 工具。
  skill,

  /// MCP 工具。
  mcp,

  /// 子任务工具；Harness 各阶段均不开放。
  subtask,
}

/// 将内建工具映射到阶段能力类别。
HarnessToolCategory? builtinToolCategory(AiBuiltinToolKind kind) {
  return switch (kind) {
    AiBuiltinToolKind.read ||
    AiBuiltinToolKind.glob ||
    AiBuiltinToolKind.ls ||
    AiBuiltinToolKind.write ||
    AiBuiltinToolKind.edit ||
    AiBuiltinToolKind.multiEdit ||
    AiBuiltinToolKind.applyFileDiffs ||
    AiBuiltinToolKind.notebookEdit ||
    AiBuiltinToolKind.deleteFile => HarnessToolCategory.filesystem,
    AiBuiltinToolKind.grep ||
    AiBuiltinToolKind.codebaseSearch ||
    AiBuiltinToolKind.knowledgeSearch ||
    AiBuiltinToolKind.knowledgeRead => HarnessToolCategory.search,
    AiBuiltinToolKind.bash ||
    AiBuiltinToolKind.bashBackground ||
    AiBuiltinToolKind.taskOutput ||
    AiBuiltinToolKind.taskStop ||
    AiBuiltinToolKind.machineTerminalRead ||
    AiBuiltinToolKind.machineTerminalWrite ||
    AiBuiltinToolKind.machineTerminalExec ||
    AiBuiltinToolKind.machineTerminalControl => HarnessToolCategory.shell,
    AiBuiltinToolKind.git => HarnessToolCategory.vcs,
    AiBuiltinToolKind.webFetch ||
    AiBuiltinToolKind.webSearch => HarnessToolCategory.web,
    AiBuiltinToolKind.lsp ||
    AiBuiltinToolKind.readLints => HarnessToolCategory.lsp,
    AiBuiltinToolKind.todoWrite ||
    AiBuiltinToolKind.exitPlanMode => HarnessToolCategory.planning,
    AiBuiltinToolKind.task => HarnessToolCategory.subtask,
    // 交互工具由提示词构建器统一排除。
    AiBuiltinToolKind.askUserChoice => null,
    // 下列工具由其他专用链路使用，不参与 Harness 阶段亲和。
    AiBuiltinToolKind.skillManager => null,
    // ToolSearch 由延迟加载策略动态控制。
    AiBuiltinToolKind.toolSearch => null,
    AiBuiltinToolKind.dingTalkToolSearch ||
    AiBuiltinToolKind.dingtalkDws ||
    AiBuiltinToolKind.dingtalkImageGeneration ||
    AiBuiltinToolKind.dingtalkVideoGeneration ||
    AiBuiltinToolKind.dingtalkAudioGeneration => null,
    // Memory 仅供自主学习链路使用。
    AiBuiltinToolKind.memory => null,
  };
}

/// 阶段工具亲和矩阵。
const Map<HarnessPhase, Set<HarnessToolCategory>> kPhaseToolAffinity = {
  // 元信息采集：扫描项目结构。
  HarnessPhase.metaCollection: {
    HarnessToolCategory.filesystem,
    HarnessToolCategory.search,
    HarnessToolCategory.shell,
    HarnessToolCategory.vcs,
  },

  // 调研：分析代码库。
  HarnessPhase.reading: {
    HarnessToolCategory.filesystem,
    HarnessToolCategory.search,
    HarnessToolCategory.shell,
    HarnessToolCategory.vcs,
    HarnessToolCategory.lsp,
    HarnessToolCategory.web,
  },

  // 规划：读取上下文并写入计划。
  HarnessPhase.planning: {
    HarnessToolCategory.filesystem,
    HarnessToolCategory.search,
    HarnessToolCategory.shell,
    HarnessToolCategory.planning,
  },

  // 实施：执行项目改动。
  HarnessPhase.implementing: {
    HarnessToolCategory.filesystem,
    HarnessToolCategory.search,
    HarnessToolCategory.shell,
    HarnessToolCategory.vcs,
    HarnessToolCategory.lsp,
    HarnessToolCategory.skill,
    HarnessToolCategory.mcp,
    HarnessToolCategory.web,
  },

  // 验收：只读核验和测试。
  HarnessPhase.reviewing: {
    HarnessToolCategory.filesystem,
    HarnessToolCategory.search,
    HarnessToolCategory.shell,
    HarnessToolCategory.vcs,
    HarnessToolCategory.lsp,
  },
};

/// 判断工具是否属于当前阶段能力范围。
bool isToolRelevantForPhase({
  required HarnessPhase phase,
  required AiResolvedTool tool,
}) {
  final affinity = kPhaseToolAffinity[phase];
  if (affinity == null) {
    // 未配置阶段保持向后兼容。
    return true;
  }

  // Skill 工具。
  if (tool.source == AiRuntimeToolSource.skill) {
    return affinity.contains(HarnessToolCategory.skill);
  }

  // MCP 工具。
  if (tool.source == AiRuntimeToolSource.mcp) {
    return affinity.contains(HarnessToolCategory.mcp);
  }

  // 内建工具。
  if (tool.source == AiRuntimeToolSource.builtin && tool.builtinKind != null) {
    final category = builtinToolCategory(tool.builtinKind!);
    if (category == null) {
      return true;
    }
    return affinity.contains(category);
  }

  // 未知来源保持向后兼容。
  return true;
}

/// 只读阶段排除的 Skill。
const Set<String> kReadOnlyPhaseExcludedSkillSlugs = {
  'imagegen',
  'pdf',
  'excel-report-generator',
};

/// 判断 Skill 是否应从只读阶段排除。
bool shouldExcludeSkillFromReadOnlyPhase(String skillSlug) {
  return kReadOnlyPhaseExcludedSkillSlugs.contains(skillSlug.toLowerCase());
}

// Harness Engineering phase-tool affinity configuration.
//
// This module defines which tool categories are relevant for each phase,
// enabling intelligent tool filtering to reduce token overhead while
// maintaining functional completeness.

import '../../ai/index.dart';
import 'hardness_phase.dart';

enum HardnessToolCategory {
  /// File system operations: Read, Glob, LS, DeleteFile
  filesystem,

  /// Search tools: Grep, CodebaseSearch
  search,

  /// Shell execution: Bash
  shell,

  /// Version control: Git
  vcs,

  /// Web operations: WebFetch, WebSearch
  web,

  /// Language Server Protocol: Lsp, ReadLints
  lsp,

  /// Planning tools: TodoWrite, ExitPlanMode
  planning,

  /// Skill tools: skill__*
  skill,

  /// MCP tools: mcp__*
  mcp,

  /// Agent delegation: Task
  agent,
}

/// Maps builtin tool kinds to their category.
HardnessToolCategory? builtinToolCategory(AiBuiltinToolKind kind) {
  return switch (kind) {
    AiBuiltinToolKind.read ||
    AiBuiltinToolKind.glob ||
    AiBuiltinToolKind.ls ||
    AiBuiltinToolKind.write ||
    AiBuiltinToolKind.edit ||
    AiBuiltinToolKind.multiEdit ||
    AiBuiltinToolKind.applyFileDiffs ||
    AiBuiltinToolKind.notebookEdit ||
    AiBuiltinToolKind.deleteFile => HardnessToolCategory.filesystem,
    AiBuiltinToolKind.grep ||
    AiBuiltinToolKind.codebaseSearch ||
    AiBuiltinToolKind.knowledgeSearch ||
    AiBuiltinToolKind.knowledgeRead => HardnessToolCategory.search,
    AiBuiltinToolKind.bash ||
    AiBuiltinToolKind.bashBackground ||
    AiBuiltinToolKind.taskOutput ||
    AiBuiltinToolKind.taskStop => HardnessToolCategory.shell,
    AiBuiltinToolKind.git => HardnessToolCategory.vcs,
    AiBuiltinToolKind.webFetch ||
    AiBuiltinToolKind.webSearch => HardnessToolCategory.web,
    AiBuiltinToolKind.lsp ||
    AiBuiltinToolKind.readLints => HardnessToolCategory.lsp,
    AiBuiltinToolKind.todoWrite ||
    AiBuiltinToolKind.exitPlanMode => HardnessToolCategory.planning,
    AiBuiltinToolKind.task => HardnessToolCategory.agent,
    // Interactive user-facing tool; not tied to any phase category so it stays
    // available across all phases without affinity filtering.
    AiBuiltinToolKind.askUserChoice => null,
    // Skill manager is Hermes-Talker-specific and is not exposed to
    // Harness Engineering sessions; treat as un-categorized.
    AiBuiltinToolKind.skillManager => null,
    // ToolSearch is dynamically gated by lazy-loading; not bound to any
    // phase category so it remains visible whenever the controller exposes it.
    AiBuiltinToolKind.toolSearch => null,
    // Memory tool is Hermes-Talker-specific (self-learning sub-agent only).
    AiBuiltinToolKind.memory => null,
  };
}

/// Phase-tool affinity matrix.
///
/// This defines which tool categories are relevant for each phase,
/// allowing filtering of irrelevant tools to reduce prompt size.
const Map<HardnessPhase, Set<HardnessToolCategory>> kPhaseToolAffinity = {
  // metaCollection: scanning project structure
  HardnessPhase.metaCollection: {
    HardnessToolCategory.filesystem,
    HardnessToolCategory.search,
    HardnessToolCategory.shell,
    HardnessToolCategory.vcs,
  },

  // reading: analyzing codebase deeply
  HardnessPhase.reading: {
    HardnessToolCategory.filesystem,
    HardnessToolCategory.search,
    HardnessToolCategory.shell,
    HardnessToolCategory.vcs,
    HardnessToolCategory.lsp,
    HardnessToolCategory.web, // For documentation lookup
  },

  // planning: creating execution plan (needs shell for mkdir to create
  // the plan directory before writing the plan file)
  HardnessPhase.planning: {
    HardnessToolCategory.filesystem,
    HardnessToolCategory.search,
    HardnessToolCategory.shell,
    HardnessToolCategory.planning,
  },

  // implementing: executing changes (full access)
  HardnessPhase.implementing: {
    HardnessToolCategory.filesystem,
    HardnessToolCategory.search,
    HardnessToolCategory.shell,
    HardnessToolCategory.vcs,
    HardnessToolCategory.lsp,
    HardnessToolCategory.skill,
    HardnessToolCategory.mcp,
    HardnessToolCategory.web,
  },

  // reviewing: verifying implementation
  HardnessPhase.reviewing: {
    HardnessToolCategory.filesystem,
    HardnessToolCategory.search,
    HardnessToolCategory.shell,
    HardnessToolCategory.vcs,
    HardnessToolCategory.lsp,
    HardnessToolCategory.agent, // Can delegate sub-tasks for verification
  },
};

/// Checks if a tool is relevant for a given phase based on affinity.
bool isToolRelevantForPhase({
  required HardnessPhase phase,
  required AiResolvedTool tool,
}) {
  final affinity = kPhaseToolAffinity[phase];
  if (affinity == null) {
    // If no affinity defined, include all tools
    return true;
  }

  // Skill tools
  if (tool.source == AiRuntimeToolSource.skill) {
    return affinity.contains(HardnessToolCategory.skill);
  }

  // MCP tools
  if (tool.source == AiRuntimeToolSource.mcp) {
    return affinity.contains(HardnessToolCategory.mcp);
  }

  // Builtin tools
  if (tool.source == AiRuntimeToolSource.builtin && tool.builtinKind != null) {
    final category = builtinToolCategory(tool.builtinKind!);
    if (category == null) {
      return true; // Unknown category, include by default
    }
    return affinity.contains(category);
  }

  // Unknown source, include by default
  return true;
}

/// Skill slugs that are excluded from certain phases.
///
/// These skills are not useful or potentially harmful in read-only phases.
const Set<String> kReadOnlyPhaseExcludedSkillSlugs = {
  'imagegen', // Image generation not needed in analysis phases
  'pdf', // PDF generation not needed in read-only phases
  'excel-report-generator', // Report generation is for output, not analysis
};

/// Checks if a skill should be excluded from read-only phases.
bool shouldExcludeSkillFromReadOnlyPhase(String skillSlug) {
  return kReadOnlyPhaseExcludedSkillSlugs.contains(skillSlug.toLowerCase());
}

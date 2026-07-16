// Harness Engineering prompt builder service.
// This module provides specialized prompt construction for Harness
// Engineering phases, implementing:
// - Compressed tool catalog rendering (~75% token reduction)
// - Phase-aware context loading (architecture, conventions, etc.)
// - Protocol-adaptive tool format (skip XML for API-native tools)
// - Unified language policy (no repetition)

import '../../ai/index.dart';
import '../model/harness_phase.dart';
import '../model/harness_tool_affinity.dart';

class HarnessPromptBuilder {
  const HarnessPromptBuilder();

  /// Renders a compressed tool catalog for HE phases.
  ///
  /// Compared to the default full catalog (~8000 chars), this compressed
  /// version targets ~2000 chars by:
  /// 1. Grouping tools by category with shared parameter signatures
  /// 2. Truncating descriptions to 60 chars
  /// 3. Omitting full JSON schemas (API tools array has those)
  /// 4. Using a concise list format
  String renderCompactToolCatalog({
    required List<AiToolDefinition> tools,
    required HarnessPhase phase,
  }) {
    if (tools.isEmpty) {
      return '无可用工具。';
    }

    final buffer = StringBuffer()
      ..writeln('# 可用工具（共 ${tools.length} 个）')
      ..writeln()
      ..writeln('能力优先级：Skill > MCP > Builtin');

    // Group tools by type
    final skillTools = <AiToolDefinition>[];
    final mcpTools = <AiToolDefinition>[];
    final builtinTools = <AiToolDefinition>[];

    final sortedTools = stableToolDefinitionsForAiRequest(tools);
    for (final tool in sortedTools) {
      if (tool.name.startsWith('skill__')) {
        skillTools.add(tool);
      } else if (tool.name.startsWith('mcp__')) {
        mcpTools.add(tool);
      } else {
        builtinTools.add(tool);
      }
    }
    skillTools.sort(_compareToolDefinitions);
    mcpTools.sort(_compareToolDefinitions);
    builtinTools.sort(_compareToolDefinitions);

    if (skillTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Skills（通用参数：task?: string）');
      for (final tool in skillTools) {
        final shortName = tool.name.replaceFirst('skill__', '');
        final desc = _truncateDescription(tool.description, 60);
        buffer.writeln('- $shortName: $desc');
      }
    }

    if (mcpTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## MCP 工具');
      for (final tool in mcpTools) {
        // Extract server and tool name from mcp__server__tool format
        final parts = tool.name.split('__');
        final displayName = parts.length >= 3
            ? '${parts[1]}/${parts.sublist(2).join('__')}'
            : tool.name.replaceFirst('mcp__', '');
        final desc = _truncateDescription(tool.description, 60);
        final requiredArgs = _extractRequiredArgs(tool.parameters);
        buffer.write('- $displayName: $desc');
        if (requiredArgs.isNotEmpty) {
          buffer.write(' [${requiredArgs.join(', ')}]');
        }
        buffer.writeln();
      }
    }

    if (builtinTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 内建工具');
      for (final tool in builtinTools) {
        final desc = _truncateDescription(tool.description, 60);
        final requiredArgs = _extractRequiredArgs(tool.parameters);
        buffer.write('- ${tool.name}: $desc');
        if (requiredArgs.isNotEmpty) {
          buffer.write(' [${requiredArgs.join(', ')}]');
        }
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  /// Filters tools based on phase affinity.
  ///
  /// Returns a filtered catalog containing only tools relevant to the phase.
  AiResolvedToolCatalog filterToolsForPhase({
    required HarnessPhase phase,
    required AiResolvedToolCatalog catalog,
  }) {
    // Implementing phase gets full access
    if (phase == HarnessPhase.implementing) {
      return catalog;
    }

    final filteredDefinitions = <AiToolDefinition>[];
    final filteredToolsByName = <String, AiResolvedTool>{};

    // Phases that produce mandatory output artifacts (architecture.md,
    // plan files, feedback files) need the Write tool; only the reading
    // phase is truly read-only with no file output.
    final phaseNeedsWrite =
        phase == HarnessPhase.metaCollection ||
        phase == HarnessPhase.planning ||
        phase == HarnessPhase.reviewing;

    // Edit / multi-edit are always excluded outside implementing; Write
    // is allowed for phases that produce artifacts.
    final readOnlyExcludeBuiltins = <AiBuiltinToolKind>{
      AiBuiltinToolKind.edit,
      AiBuiltinToolKind.multiEdit,
      if (!phaseNeedsWrite) AiBuiltinToolKind.write,
      AiBuiltinToolKind.notebookEdit,
    };
    bool isAllowed(AiResolvedTool tool) {
      if (tool.source == AiRuntimeToolSource.builtin &&
          readOnlyExcludeBuiltins.contains(tool.builtinKind)) {
        return false;
      }
      if (!isToolRelevantForPhase(phase: phase, tool: tool)) {
        return false;
      }
      if (tool.source == AiRuntimeToolSource.skill) {
        final slug = tool.name.replaceFirst('skill__', '');
        if (_isReadOnlyPhase(phase) &&
            shouldExcludeSkillFromReadOnlyPhase(slug)) {
          return false;
        }
      }
      return true;
    }

    final filteredEntries = <MapEntry<String, AiResolvedTool>>[];
    for (final entry in catalog.toolsByName.entries) {
      final tool = entry.value;
      if (!isAllowed(tool)) continue;
      filteredEntries.add(
        MapEntry<String, AiResolvedTool>(
          entry.key,
          _filterToolSearchDeferredTools(tool, isAllowed),
        ),
      );
    }

    filteredEntries.sort(_compareResolvedToolEntries);
    for (final entry in filteredEntries) {
      filteredToolsByName[entry.key] = entry.value;
      filteredDefinitions.add(
        stableToolDefinitionForAiRequest(entry.value.definition),
      );
    }

    return AiResolvedToolCatalog(
      definitions: filteredDefinitions,
      toolsByName: filteredToolsByName,
      notices: catalog.notices,
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  AiResolvedTool _filterToolSearchDeferredTools(
    AiResolvedTool tool,
    bool Function(AiResolvedTool tool) isAllowed,
  ) {
    if (tool.builtinKind != AiBuiltinToolKind.toolSearch ||
        tool.toolSearchDeferredTools.isEmpty) {
      return tool;
    }
    final deferredEntries = tool.toolSearchDeferredTools.entries
        .where((entry) => isAllowed(entry.value))
        .toList(growable: false);
    final allowedNames = deferredEntries.map((entry) => entry.key).toSet();
    return AiResolvedTool(
      name: tool.name,
      definition: tool.definition,
      source: tool.source,
      builtinKind: tool.builtinKind,
      mcpServer: tool.mcpServer,
      mcpTool: tool.mcpTool,
      skill: tool.skill,
      builtinConfig: tool.builtinConfig,
      toolSearchDeferredToolDefinitions: <String, AiToolDefinition>{
        for (final entry in tool.toolSearchDeferredToolDefinitions.entries)
          if (allowedNames.contains(entry.key)) entry.key: entry.value,
      },
      toolSearchDeferredTools: <String, AiResolvedTool>{
        for (final entry in deferredEntries) entry.key: entry.value,
      },
    );
  }

  /// Renders experience lessons as a compressed summary.
  ///
  /// When full lessons content exceeds the threshold, extracts and
  /// returns only the most important points (top 5 lessons).
  String renderLessonsSummary(String fullLessonsContent) {
    if (fullLessonsContent.trim().isEmpty) {
      return '';
    }

    // If content is short, return as-is
    if (fullLessonsContent.length < 1500) {
      return fullLessonsContent;
    }

    // Extract key points from lessons
    final lines = fullLessonsContent.split('\n');
    final keyPoints = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      // Capture section headers and key findings
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.contains('重要') ||
          trimmed.contains('注意') ||
          trimmed.contains('避免') ||
          trimmed.contains('必须') ||
          trimmed.contains('错误') ||
          trimmed.contains('问题')) {
        if (trimmed.isNotEmpty && keyPoints.length < 15) {
          keyPoints.add(trimmed);
        }
      }
    }

    if (keyPoints.isEmpty) {
      // Fallback: return first 1000 chars
      return '${fullLessonsContent.substring(0, 1000).trimRight()}…\n\n（经验教训已压缩；完整内容见 steering/lesson/ 目录）';
    }

    return '## 经验教训摘要\n\n${keyPoints.join('\n')}\n\n（完整经验教训见 steering/lesson/ 目录）';
  }

  /// Returns the compact XML tool call format instructions.
  ///
  /// This is a ~500 char version of the full ~3500 char instructions,
  /// used only when the model doesn't support native tool calls.
  String get compactXmlToolInstructions => '''
## 工具调用格式

在响应末尾输出以下 XML（之后不要有任何文字）：

```xml
<tool_calls>
  <tool_call><tool_name>工具名</tool_name><parameters>{"key":"value"}</parameters></tool_call>
</tool_calls>
```

规则：(1) XML 后不要有文字 (2) parameters 内为 JSON (3) 不要用 Markdown 代码块包裹 XML
''';

  /// Checks if XML tool instructions should be injected.
  ///
  /// Returns false for models with native tool call support.
  bool shouldInjectXmlInstructions(AiProtocolAdapter adapter) {
    return !adapter.supportsToolCalls;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _truncateDescription(String description, int maxChars) {
    final normalized = description
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\.\s*\.'), '.');

    if (normalized.length <= maxChars) {
      return normalized;
    }

    return '${normalized.substring(0, maxChars).trimRight()}…';
  }

  List<String> _extractRequiredArgs(Map<String, Object?> parameters) {
    final requiredValue = parameters['required'];
    if (requiredValue is! List) {
      return const <String>[];
    }
    final names = requiredValue
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    names.sort(compareToolNamesForAiRequest);
    return names;
  }

  bool _isReadOnlyPhase(HarnessPhase phase) {
    return phase != HarnessPhase.implementing;
  }

  int _compareToolDefinitions(AiToolDefinition left, AiToolDefinition right) {
    return compareToolNamesForAiRequest(left.name, right.name);
  }

  int _compareResolvedToolEntries(
    MapEntry<String, AiResolvedTool> left,
    MapEntry<String, AiResolvedTool> right,
  ) {
    final sourceCompare = _toolSourceRank(
      left.value.source,
    ).compareTo(_toolSourceRank(right.value.source));
    if (sourceCompare != 0) return sourceCompare;
    return compareToolNamesForAiRequest(left.key, right.key);
  }

  int _toolSourceRank(AiRuntimeToolSource source) {
    return switch (source) {
      AiRuntimeToolSource.skill => 0,
      AiRuntimeToolSource.mcp => 1,
      AiRuntimeToolSource.builtin => 2,
    };
  }
}

/// Global instance for convenience.
const harnessPromptBuilder = HarnessPromptBuilder();

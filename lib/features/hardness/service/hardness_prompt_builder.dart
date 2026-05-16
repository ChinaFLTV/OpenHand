// Hardness Engineering prompt builder service.
//
// This module provides specialized prompt construction for Hardness
// Engineering phases, implementing:
// - Compressed tool catalog rendering (~75% token reduction)
// - Phase-aware context loading (architecture, conventions, etc.)
// - Protocol-adaptive tool format (skip XML for API-native tools)
// - Unified language policy (no repetition)

import '../../ai/service/ai_protocol_adapter.dart';
import '../../ai/service/ai_tool_runtime_service.dart';
import '../model/hardness_phase.dart';
import '../model/hardness_tool_affinity.dart';

/// HE-specific prompt builder with optimizations.
class HardnessPromptBuilder {
  const HardnessPromptBuilder();

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
    required HardnessPhase phase,
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

    for (final tool in tools) {
      if (tool.name.startsWith('skill__')) {
        skillTools.add(tool);
      } else if (tool.name.startsWith('mcp__')) {
        mcpTools.add(tool);
      } else {
        builtinTools.add(tool);
      }
    }

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
    required HardnessPhase phase,
    required AiResolvedToolCatalog catalog,
  }) {
    // Implementing phase gets full access
    if (phase == HardnessPhase.implementing) {
      return catalog;
    }

    final filteredDefinitions = <AiToolDefinition>[];
    final filteredToolsByName = <String, AiResolvedTool>{};

    // Phases that produce mandatory output artifacts (architecture.md,
    // plan files, feedback files) need the Write tool; only the reading
    // phase is truly read-only with no file output.
    final phaseNeedsWrite =
        phase == HardnessPhase.metaCollection ||
        phase == HardnessPhase.planning ||
        phase == HardnessPhase.reviewing;

    // Edit / multi-edit are always excluded outside implementing; Write
    // is allowed for phases that produce artifacts.
    final readOnlyExcludeBuiltins = <AiBuiltinToolKind>{
      AiBuiltinToolKind.edit,
      AiBuiltinToolKind.multiEdit,
      if (!phaseNeedsWrite) AiBuiltinToolKind.write,
      AiBuiltinToolKind.notebookEdit,
    };

    for (final entry in catalog.toolsByName.entries) {
      final tool = entry.value;

      // Exclude write tools in read-only phases
      if (tool.source == AiRuntimeToolSource.builtin &&
          readOnlyExcludeBuiltins.contains(tool.builtinKind)) {
        continue;
      }

      // Check phase affinity
      if (!isToolRelevantForPhase(phase: phase, tool: tool)) {
        continue;
      }

      // For read-only phases, exclude certain skills
      if (tool.source == AiRuntimeToolSource.skill) {
        final slug = tool.name.replaceFirst('skill__', '');
        if (_isReadOnlyPhase(phase) &&
            shouldExcludeSkillFromReadOnlyPhase(slug)) {
          continue;
        }
      }

      filteredToolsByName[entry.key] = tool;
      filteredDefinitions.add(tool.definition);
    }

    return AiResolvedToolCatalog(
      definitions: filteredDefinitions,
      toolsByName: filteredToolsByName,
      notices: catalog.notices,
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
    return requiredValue
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool _isReadOnlyPhase(HardnessPhase phase) {
    return phase != HardnessPhase.implementing;
  }
}

/// Global instance for convenience.
const hardnessPromptBuilder = HardnessPromptBuilder();

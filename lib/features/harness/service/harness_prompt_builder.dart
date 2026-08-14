// Harness Engineering 提示词构建器：负责压缩工具目录、按阶段过滤工具，
// 并为不支持原生工具调用的模型补充 XML 调用格式。

import 'package:openhand/shared/util/text_normalization.dart';

import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../model/harness_phase.dart';
import '../model/harness_tool_affinity.dart';

class HarnessPromptBuilder {
  const HarnessPromptBuilder();

  static const int _toolDescriptionMaxCharacters = 60;
  static const int _lessonsSummaryThresholdCharacters = 1500;
  static const int _lessonsFallbackCharacters = 1000;
  static const int _lessonsMaxKeyPoints = 15;

  /// 按来源分组并省略完整 Schema，渲染精简工具目录。
  String renderCompactToolCatalog({required List<AiToolDefinition> tools}) {
    if (tools.isEmpty) {
      return '无可用工具。';
    }

    final buffer = StringBuffer()..writeln('# 可用工具（共 ${tools.length} 个）');

    // 按来源分组，组内保持稳定顺序。
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
        final desc = _truncateDescription(
          tool.description,
          _toolDescriptionMaxCharacters,
        );
        buffer.writeln('- ${tool.name}: $desc');
      }
    }

    if (mcpTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## MCP 工具');
      _appendToolDefinitions(buffer, mcpTools);
    }

    if (builtinTools.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 内建工具');
      _appendToolDefinitions(buffer, builtinTools);
    }

    return buffer.toString().trimRight();
  }

  void _appendToolDefinitions(
    StringBuffer buffer,
    Iterable<AiToolDefinition> tools,
  ) {
    for (final tool in tools) {
      final description = _truncateDescription(
        tool.description,
        _toolDescriptionMaxCharacters,
      );
      final requiredArgs = _extractRequiredArgs(tool.parameters);
      buffer.write('- ${tool.name}: $description');
      if (requiredArgs.isNotEmpty) {
        buffer.write(' [${requiredArgs.join(', ')}]');
      }
      buffer.writeln();
    }
  }

  /// 按阶段能力和写入权限过滤工具目录。
  AiResolvedToolCatalog filterToolsForPhase({
    required HarnessPhase phase,
    required AiResolvedToolCatalog catalog,
  }) {
    final filteredDefinitions = <AiToolDefinition>[];
    final filteredToolsByName = <String, AiResolvedTool>{};

    // 元信息、规划和验收阶段需要 Write 写入各自的持久化产物。
    final phaseNeedsWrite =
        phase == HarnessPhase.metaCollection ||
        phase == HarnessPhase.planning ||
        phase == HarnessPhase.reviewing;

    const alwaysExcludedBuiltins = <AiBuiltinToolKind>{
      AiBuiltinToolKind.askUserChoice,
      AiBuiltinToolKind.skillManager,
      AiBuiltinToolKind.memory,
    };
    final readOnlyExcludeBuiltins = <AiBuiltinToolKind>{
      AiBuiltinToolKind.edit,
      AiBuiltinToolKind.multiEdit,
      AiBuiltinToolKind.applyFileDiffs,
      AiBuiltinToolKind.deleteFile,
      if (!phaseNeedsWrite) AiBuiltinToolKind.write,
      AiBuiltinToolKind.notebookEdit,
      AiBuiltinToolKind.bashBackground,
      AiBuiltinToolKind.taskOutput,
      AiBuiltinToolKind.taskStop,
      AiBuiltinToolKind.machineTerminalWrite,
      AiBuiltinToolKind.machineTerminalExec,
      AiBuiltinToolKind.machineTerminalControl,
    };
    bool isAllowed(AiResolvedTool tool) {
      if (tool.source == AiRuntimeToolSource.builtin) {
        final kind = tool.builtinKind;
        if (kind != null &&
            (alwaysExcludedBuiltins.contains(kind) ||
                phase != HarnessPhase.implementing &&
                    readOnlyExcludeBuiltins.contains(kind))) {
          return false;
        }
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

  /// 超过阈值时提取经验记录中的标题、列表和关键提示。
  String renderLessonsSummary(String fullLessonsContent) {
    if (fullLessonsContent.trim().isEmpty) {
      return '';
    }

    if (fullLessonsContent.length < _lessonsSummaryThresholdCharacters) {
      return fullLessonsContent;
    }

    final lines = fullLessonsContent.split('\n');
    final keyPoints = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') ||
          trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.contains('重要') ||
          trimmed.contains('注意') ||
          trimmed.contains('避免') ||
          trimmed.contains('必须') ||
          trimmed.contains('错误') ||
          trimmed.contains('问题')) {
        if (trimmed.isNotEmpty && keyPoints.length < _lessonsMaxKeyPoints) {
          keyPoints.add(trimmed);
        }
      }
    }

    if (keyPoints.isEmpty) {
      final preview = clipTextByCodeUnits(
        fullLessonsContent,
        _lessonsFallbackCharacters,
        suffix: '…',
      ).trimRight();
      return '$preview\n\n（经验教训已压缩；完整内容见 steering/lesson/ 目录）';
    }

    return '## 经验教训摘要\n\n${keyPoints.join('\n')}\n\n（完整经验教训见 steering/lesson/ 目录）';
  }

  /// 非原生模型使用的精简 XML 工具调用格式。
  String get compactXmlToolInstructions => '''
## 工具调用格式

需要调用工具时，在响应末尾输出以下 XML：
<tool_calls>
  <tool_call><tool_name>工具名</tool_name><parameters>{"key":"value"}</parameters></tool_call>
</tool_calls>

`tool_name` 使用目录中的完整名称，`parameters` 必须是 JSON。XML 后停止输出，禁止代码围栏。
''';

  /// 原生工具调用模型不注入 XML 说明。
  bool shouldInjectXmlInstructions(AiProtocolAdapter adapter) {
    return !adapter.supportsToolCalls;
  }

  String _truncateDescription(String description, int maxChars) {
    final normalized = normalizeDescriptionText(description);

    return clipTextByCodeUnits(normalized, maxChars, suffix: '…').trimRight();
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

/// 全局无状态实例。
const harnessPromptBuilder = HarnessPromptBuilder();

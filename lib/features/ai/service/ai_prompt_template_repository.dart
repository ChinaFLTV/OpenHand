import 'package:flutter/services.dart';

import '../model/ai_thread_template.dart';
import 'machine_expert_prompts.dart';
import 'programming_expert_prompts.dart';

class AiPromptTemplateBundle {
  const AiPromptTemplateBundle({
    required this.template,
    required this.systemInstructions,
    required this.developerInstructions,
    required this.compressionSummaryInstructions,
  });

  final AiThreadTemplate template;
  final String systemInstructions;
  final String developerInstructions;
  final String compressionSummaryInstructions;
}

class AiPromptTemplateRepository {
  AiPromptTemplateRepository({
    Future<String> Function(String assetPath)? loader,
  }) : _loader = loader ?? rootBundle.loadString;

  final Future<String> Function(String assetPath) _loader;

  static const List<AiThreadTemplate> _templates = <AiThreadTemplate>[
    AiThreadTemplate(
      id: 'default',
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description:
          'A Claude Code style general-purpose template for tool-assisted work, MCP usage, and local skill activation.',
      internalVersion: '3.0.0',
      promptAssetDirectory: 'assets/prompts/default',
    ),
    AiThreadTemplate(
      id: 'machine_expert',
      name: '机器专家',
      iconName: 'build_circle_rounded',
      description: '主要是通过本地终端程序去与目标机器交互，完成用户提出的任务或需求。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/machine_expert',
    ),
    AiThreadTemplate(
      id: 'hardness_engineering',
      name: 'Hardness Engineering',
      iconName: 'hub_rounded',
      description: '多角色编排协调模式。OpenHand 作为 OS 层统一编排，将编码任务委托给用户配置的 CLI 工具（调查者→规划者→实施者→验收者），并管理结构化持久化上下文。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/hardness_engineering',
    ),
    AiThreadTemplate(
      id: 'programming_expert',
      name: '编程专家',
      iconName: 'code_rounded',
      description: '对标 Cursor Agent 的全栈 AI 编程助手。具备语义代码搜索、LSP 诊断、Git 集成、自主 Agent 循环，支持 Research→Synthesis→Implementation→Verification 四阶段工作流。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/programming_expert',
    ),
  ];

  List<AiThreadTemplate> get templates =>
      List<AiThreadTemplate>.unmodifiable(_templates);

  AiThreadTemplate resolveTemplate(String templateId) {
    for (final template in _templates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return _templates.first;
  }

  Future<AiPromptTemplateBundle> loadBundle(String templateId) async {
    final template = resolveTemplate(templateId);
    final assetDirectory = template.promptAssetDirectory;
    final String systemFallback;
    final String developerFallback;
    final String compressionFallback;
    switch (templateId) {
      case 'machine_expert':
        systemFallback = expertSystemInstructions;
        developerFallback = expertDeveloperInstructions;
        compressionFallback = expertCompressionSummaryInstructions;
      case 'hardness_engineering':
        systemFallback = _hardnessSystemInstructions;
        developerFallback = _hardnessDeveloperInstructions;
        compressionFallback = _hardnessCompressionSummaryInstructions;
      case 'programming_expert':
        systemFallback = programmingExpertSystemInstructions;
        developerFallback = programmingExpertDeveloperInstructions;
        compressionFallback = programmingExpertCompressionSummaryInstructions;
      default:
        systemFallback = _defaultSystemInstructions;
        developerFallback = _defaultDeveloperInstructions;
        compressionFallback = _defaultCompressionSummaryInstructions;
    }
    final systemInstructions = await _loadTemplateSection(
      '$assetDirectory/system_instructions.md',
      systemFallback,
    );
    final developerInstructions = await _loadTemplateSection(
      '$assetDirectory/developer_instructions.md',
      developerFallback,
    );
    final compressionSummaryInstructions = await _loadTemplateSection(
      '$assetDirectory/compression_summary_instructions.md',
      compressionFallback,
    );
    return AiPromptTemplateBundle(
      template: template,
      systemInstructions: systemInstructions,
      developerInstructions: developerInstructions,
      compressionSummaryInstructions: compressionSummaryInstructions,
    );
  }

  Future<String> _loadTemplateSection(String assetPath, String fallback) async {
    try {
      final content = (await _loader(assetPath)).trim();
      return content.isEmpty ? fallback : content;
    } catch (_) {
      return fallback;
    }
  }
}

const String _defaultSystemInstructions = '''
You are OpenHand, a desktop coding agent with Claude Code style operating rules.

- Follow a strict 4-phase workflow for most tasks: Research -> Synthesis -> Implementation -> Verification.
  1. Research: Investigate the codebase, find files, and thoroughly understand the problem.
  2. Synthesis: Formulate a specific execution plan based on the research before making any edits.
  3. Implementation: Make targeted code changes according to your synthesized plan.
  4. Verification: Prove the code works. Run tests, typechecks, and investigate failures.
- Help with software engineering tasks using analysis, coding, shell work, MCP tools, local skills, and structured tool use.
- Capability invocation priority: Skill > MCP > Builtin. Prefer skills over MCP tools, and MCP tools over builtins.
- Be concise, direct, and explicit about important assumptions.
- For very simple factual requests, a very short answer is preferred.
- Prefer tools when they materially improve accuracy or provide required local/runtime context.
- Respect user-configured safety controls such as deny rules, hooks, and write-command confirmations.
- Treat hook feedback, including prompt-submit hooks, as real runtime input.
- Do not invent tool names, outputs, MCP results, or skill contents.
- Do not commit, push, or open pull requests unless the user explicitly asks.
- Use the current runtime date for time-sensitive web work.
- Treat repository snapshot metadata as point-in-time context, not guaranteed live state.
''';

const String _defaultDeveloperInstructions = '''
Follow the prompt assembly contract exactly.

Capability invocation priority: Skill > MCP > Builtin.
When a task matches an available skill__* tool, use the skill first.
If no skill matches but a relevant mcp__* tool exists, prefer the MCP tool.
Fall back to builtin tools only when neither a matching skill nor a suitable MCP tool is available.
Do not silently fall back to a lower-priority tool after a failure; explain the fallback first.

- Keep replies practical and scoped to the user's request.
- Do not claim a tool, MCP service, or skill succeeded unless the result confirms it.
- When a tool call is denied, rejected, or times out, incorporate that result into the next step instead of fabricating success.
- Preserve important context, constraints, and environment details from the current session metadata and user memory.
- Use the exact runtime tool names provided for the current request.
- Do not ask the user for generic permission to use a listed tool such as Bash. Use the tool directly when appropriate and rely on the runtime's confirmation flow for write-like shell commands.
- Use TodoWrite frequently for non-trivial work and keep todo status current.
- Do not use TodoWrite for single trivial actions or purely informational replies.
- When in doubt on a non-trivial task, prefer using TodoWrite.
- Only mark todos completed when the corresponding work is truly done.
- Remove stale todo items and refresh blocker-related todo entries when the plan changes.
- For pure commit or PR tasks, prefer direct git and GitHub commands over opening extra subtasks unless broader implementation work is still active.
- Search and read before editing, then verify with the appropriate project validation commands when feasible.
''';

const String _defaultCompressionSummaryInstructions = '''
Summarize the compressed conversation history into a compact, high-value record.

- Keep user goals, constraints, confirmed facts, decisions, active plans, todo state, relevant file paths, commands, failures, validation outcomes, open questions, and important generated artifacts.
- Remove repetition and low-signal chatter.
- Do not invent facts that were not present in the source messages.
''';

// ── Hardness Engineering fallback prompts ─────────────────────────────────────

const String _hardnessSystemInstructions = '''
You are OpenHand operating in Hardness Engineering mode — acting as an OS-level orchestrator.
You do NOT write code yourself. Coordinate the reader, planner, implementer, and reviewer roles
via the user-configured CLI tools. Tag every orchestrator message with [HE_PHASE:...] and [HE_AGENT:...|...].
Read persistence files before each CLI invocation and follow the full HE protocol defined in the asset file.
''';

const String _hardnessDeveloperInstructions = '''
能力调用优先级（强制）：Skill > MCP > Builtin。
按顺序逐级试探，遇到第一个完全匹配的能力即停止。
Skill 失败或 MCP 失败后不得静默降级，必须先说明降级原因。

Parse the [HARDNESS_CONFIG] block on session start. Verify directories, check for first-run conditions,
load meta/architecture.md and meta/conventions.md, then orchestrate the phase sequence.
Construct comprehensive prompts for each role CLI. Escalate failures. Maintain lesson and handoff documents.
''';

const String _hardnessCompressionSummaryInstructions = '''
Preserve: session config (working dir, persistence dir, CLI assignments, task), current phase/agent state,
persistence file paths created, outstanding failures, and the latest execution plan content.
Format as a structured Hardness Engineering Session Summary.
''';

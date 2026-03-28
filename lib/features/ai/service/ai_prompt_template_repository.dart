import 'package:flutter/services.dart';

import '../model/ai_thread_template.dart';

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
    final systemInstructions = await _loadTemplateSection(
      '$assetDirectory/system_instructions.md',
      _defaultSystemInstructions,
    );
    final developerInstructions = await _loadTemplateSection(
      '$assetDirectory/developer_instructions.md',
      _defaultDeveloperInstructions,
    );
    final compressionSummaryInstructions = await _loadTemplateSection(
      '$assetDirectory/compression_summary_instructions.md',
      _defaultCompressionSummaryInstructions,
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

- Help with software engineering tasks using analysis, coding, shell work, MCP tools, local skills, and structured tool use.
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

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
      internalVersion: '2.0.0',
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
You are OpenHand, a desktop coding agent.

- Help with analysis, coding, shell tasks, MCP-assisted workflows, local skills, and structured tool use.
- Be concise, accurate, and explicit about important assumptions.
- Prefer using tools when they are necessary to verify facts or inspect the local environment.
- Respect user-configured safety controls such as deny rules and write-command confirmations.
''';

const String _defaultDeveloperInstructions = '''
Follow the prompt assembly contract exactly.

- Keep replies practical and scoped to the user's request.
- Do not claim a tool, MCP service, or skill succeeded unless the result confirms it.
- When a tool call is denied, rejected, or times out, incorporate that result into the next step instead of fabricating success.
- Preserve important context, constraints, and environment details from the current session metadata and user memory.
''';

const String _defaultCompressionSummaryInstructions = '''
Summarize the compressed conversation history into a compact, high-value record.

- Keep user goals, constraints, confirmed facts, decisions, relevant file paths, commands, failures, and open questions.
- Remove repetition and low-signal chatter.
- Do not invent facts that were not present in the source messages.
''';

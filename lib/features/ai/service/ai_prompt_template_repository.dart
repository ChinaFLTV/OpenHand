import 'package:flutter/services.dart';

import '../../../app/support/silent_log.dart';
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
      internalVersion: '1.1.0',
      promptAssetDirectory: 'assets/prompts/machine_expert',
    ),
    AiThreadTemplate(
      id: 'hardness_engineering',
      name: 'Hardness Engineering',
      iconName: 'hub_rounded',
      description:
          '多角色编排协调模式。OpenHand 作为 OS 层统一编排，将编码任务委托给用户配置的 CLI 工具（调查者→规划者→实施者→验收者），并管理结构化持久化上下文。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/hardness_engineering',
    ),
    AiThreadTemplate(
      id: 'programming_expert',
      name: '编程专家',
      iconName: 'code_rounded',
      description:
          '对标 Cursor Agent 的全栈 AI 编程助手。具备语义代码搜索、LSP 诊断、Git 集成、自主 Agent 循环，支持 Research→Synthesis→Implementation→Verification 四阶段工作流。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/programming_expert',
    ),
    AiThreadTemplate(
      id: 'hermes_talker',
      name: 'Hermes Talker',
      iconName: 'forum_rounded',
      description:
          '在 Default 模板基础上新增 skill_manager 工具与每 5 分钟运行的自我学习能力,持续在对话中积累用户画像与可复用技能。',
      internalVersion: '1.0.0',
      promptAssetDirectory: 'assets/prompts/hermes_talker',
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
      case 'hermes_talker':
        systemFallback = _hermesTalkerSystemInstructions;
        developerFallback = _hermesTalkerDeveloperInstructions;
        compressionFallback = _hermesTalkerCompressionSummaryInstructions;
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
    final systemWithDiscipline = await _appendV4DisciplineIfAbsent(
      systemInstructions,
    );
    return AiPromptTemplateBundle(
      template: template,
      systemInstructions: _appendMemoryTonePolicyIfAbsent(systemWithDiscipline),
      // Memory Tone Policy is a system-level concern; injecting it into both
      // [0] System and [1] Developer caused identical 6-line blocks to render
      // twice in every prompt. Keep it on [0] only.
      developerInstructions: developerInstructions,
      compressionSummaryInstructions: compressionSummaryInstructions,
    );
  }

  /// Appends the shared v4 discipline block (Uncertainty Honesty + Atomic
  /// Change Discipline; English variant additionally covers Session Bootstrap
  /// / Diff-Thinking / Verification Loop) loaded from
  /// `assets/prompts/common/v4_discipline_{en,zh}.md` when the target
  /// instruction text does not already contain a discipline marker. Templates
  /// that ship their own specialised version (`programming_expert`,
  /// `machine_expert`) are detected via marker presence and left untouched.
  /// Language is inferred from the instructions' CJK-character ratio.
  Future<String> _appendV4DisciplineIfAbsent(String instructions) async {
    final lower = instructions.toLowerCase();
    if (lower.contains('# atomic change discipline') ||
        lower.contains('## atomic change discipline') ||
        instructions.contains('原子化变更纪律') ||
        instructions.contains('不确定性诚实')) {
      return instructions;
    }
    final useChinese = _looksLikeChinese(instructions);
    final assetPath = useChinese
        ? 'assets/prompts/common/v4_discipline_zh.md'
        : 'assets/prompts/common/v4_discipline_en.md';
    final snippet = await _loadTemplateSection(assetPath, '');
    if (snippet.isEmpty) {
      return instructions;
    }
    return '${instructions.trimRight()}\n\n$snippet\n';
  }

  /// Heuristic: treat instructions as Chinese when CJK characters make up
  /// ≥15% of all non-whitespace characters. Threshold is intentionally low
  /// because English-only templates have ~0% CJK while Chinese templates
  /// (hardness_engineering, machine_expert) routinely exceed 40%.
  bool _looksLikeChinese(String text) {
    int cjk = 0;
    int total = 0;
    for (final rune in text.runes) {
      if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) {
        continue;
      }
      total++;
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0xF900 && rune <= 0xFAFF)) {
        cjk++;
      }
    }
    if (total == 0) {
      return false;
    }
    return cjk * 100 ~/ total >= 15;
  }

  Future<String> _loadTemplateSection(String assetPath, String fallback) async {
    try {
      final content = (await _loader(assetPath)).trim();
      return content.isEmpty ? fallback : content;
    } catch (error, stack) {
      silentLog(
        'ai_prompt_template_repository',
        '_loadTemplateSection: failed to load asset $assetPath; using Dart fallback',
        error,
        stack,
      );
      return fallback;
    }
  }

  /// Loads the shared auto-title system prompt from
  /// `assets/prompts/common/auto_title_system_prompt.md`. The
  /// `{{MAX_TITLE_CHARACTERS}}` placeholder is substituted with
  /// [maxTitleCharacters] so the prompt's hard length cap matches the
  /// runtime constraint enforced after the model replies. Falls back to
  /// [fallback] when the asset is missing or unreadable (debug builds, hot
  /// reload before assets re-bundle, etc.).
  Future<String> loadAutoTitleSystemPrompt({
    required int maxTitleCharacters,
    required String fallback,
  }) async {
    final raw = await _loadTemplateSection(
      'assets/prompts/common/auto_title_system_prompt.md',
      fallback,
    );
    return raw.replaceAll(
      '{{MAX_TITLE_CHARACTERS}}',
      maxTitleCharacters.toString(),
    );
  }
}

/// Shared "Memory Tone Policy" section applied to every template's system
/// instructions only (Task 22 / 2026-04-25; dedup'd from developer layer
/// 2026-05-01 — see [_resolveBundleAsync]).
///
/// Templates whose fallback already embeds this section (e.g.
/// `hermes_talker`) will NOT have it appended twice — see
/// [_appendMemoryTonePolicyIfAbsent].
const String _memoryTonePolicySection = '''

## Memory Tone Policy
When your answer draws on stored user memories or profile data, weave that
knowledge into your reply naturally without announcing it. Do NOT say "I
remember that…", "from memory…", "you told me earlier…", or similar
tell-tales. Treat memory as invisible context, not as something the user
needs to be reminded you're tracking.
''';

/// Marker used to detect whether an instruction payload already contains the
/// tone policy section. Matched case-insensitively.
const String _memoryTonePolicyMarker = '## memory tone policy';

String _appendMemoryTonePolicyIfAbsent(String instructions) {
  if (instructions.toLowerCase().contains(_memoryTonePolicyMarker)) {
    return instructions;
  }
  return '${instructions.trimRight()}\n$_memoryTonePolicySection';
}


// ── Emergency fallback prompts ────────────────────────────────────────────────
//
// 这些常量仅在 [rootBundle.loadString] 加载 `assets/prompts/{template_id}/*.md`
// 失败时（譬如打包损坏 / 资源未注册）才会被使用。生产构建中几乎不会触发。
//
// 模板的真正提示词内容以 `assets/prompts/` 下的 Markdown 文件为唯一可信来源。
// 此处保留极简的英文/中文双语桩，向用户与日志说明加载失败并请求修复，
// 避免与资源版本漂移。修改资源时请只改 `assets/prompts/`，无需同步本桩。

const String _fallbackNotice = '''
[OpenHand prompt asset failed to load]

The template prompt could not be read from `assets/prompts/`.
Falling back to a minimal safe stub. Please tell the user that
the bundled prompt assets are missing or unreadable, and ask them
to reinstall or re-run the build.

[OpenHand 提示词资源加载失败]

模板提示词无法从 `assets/prompts/` 读取。当前使用极简兜底文本。
请告知用户：打包的提示词资源缺失或不可读，建议重新安装或重新构建后再使用。

# Minimum behaviour while in fallback

- Do not fabricate tool results, file contents, or success status.
- Do not invent tool names that are not in the runtime tool catalog.
- Reply concisely in plain language and ask the user to recover the assets.
- 简洁、坦诚地告知用户当前是兜底模式，避免做出超出已掌握信息的承诺。
''';

const String _defaultSystemInstructions = _fallbackNotice;
const String _defaultDeveloperInstructions = _fallbackNotice;
const String _defaultCompressionSummaryInstructions = _fallbackNotice;

const String _hardnessSystemInstructions = _fallbackNotice;
const String _hardnessDeveloperInstructions = _fallbackNotice;
const String _hardnessCompressionSummaryInstructions = _fallbackNotice;

const String _hermesTalkerSystemInstructions = _fallbackNotice;
const String _hermesTalkerDeveloperInstructions = _fallbackNotice;
const String _hermesTalkerCompressionSummaryInstructions = _fallbackNotice;

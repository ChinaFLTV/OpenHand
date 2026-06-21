import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../app/support/silent_log.dart';
import '../../model/ai_thread_template.dart';
import 'ai_prompt_template_assembly.dart';
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
  final Map<String, Future<AiPromptTemplateBundle>> _bundleCache =
      <String, Future<AiPromptTemplateBundle>>{};

  static const List<AiThreadTemplate> _templates = <AiThreadTemplate>[
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.defaultTemplateId,
      name: 'Default Assistant',
      iconName: 'auto_awesome_rounded',
      description:
          'A Claude Code style general-purpose template for tool-assisted work, MCP usage, and local skill activation.',
      internalVersion: '3.0.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.defaultPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.machineExpertTemplateId,
      name: '机器专家',
      iconName: 'build_circle_rounded',
      description: '主要是通过本地终端程序去与目标机器交互，完成用户提出的任务或需求。',
      internalVersion: '1.1.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.machineExpertPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.hardnessEngineeringTemplateId,
      name: 'Harness Engineering',
      iconName: 'hub_rounded',
      description:
          '多角色编排协调模式。OpenHand 作为 OS 层统一编排，将编码任务委托给用户配置的 CLI 工具（调查者→规划者→实施者→验收者），并管理结构化持久化上下文。',
      internalVersion: '1.0.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.hardnessEngineeringPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.programmingExpertTemplateId,
      name: '编程专家',
      iconName: 'code_rounded',
      description:
          '对标 Claude Code 范式的全栈 AI 编程代理。以工具事实回灌、Plan/Todo 状态纪律、子代理隔离、对抗验证和上下文恢复推进端到端工程任务。',
      internalVersion: '1.2.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.programmingExpertPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.hermesTalkerTemplateId,
      name: 'Hermes Talker',
      iconName: 'forum_rounded',
      description:
          '在 Default 模板基础上新增 skill_manager 工具与每 5 分钟运行的自我学习能力,持续在对话中积累用户画像与可复用技能。',
      internalVersion: '1.0.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.hermesTalkerPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.webReverseExpertTemplateId,
      name: 'Web 逆向专家',
      iconName: 'travel_explore_rounded',
      description:
          '通过 Google Chrome（或同核 Chromium）+ CDP 通道完成 Web 站点的接口逆向、参数还原、复现脚本产出。Dashboard 提供内嵌浏览器面板（screencast + 输入桥）与 F12 等价控制台。',
      internalVersion: '1.2.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.webReverseExpertPromptAssetDirectory,
    ),
    AiThreadTemplate(
      id: AiPromptTemplatePolicies.siriHelperTemplateId,
      name: 'Siri 助手',
      iconName: 'assistant_rounded',
      description: '默认模板的苹果设备特化版本，内置 Siri 风格系统提示词，适合依赖 Apple 生态语义与交互氛围的任务。',
      internalVersion: '1.0.0',
      promptAssetDirectory:
          AiPromptTemplatePolicies.siriHelperPromptAssetDirectory,
      availability: AiThreadTemplateAvailability.appleOnly,
    ),
  ];

  List<AiThreadTemplate> get templates =>
      List<AiThreadTemplate>.unmodifiable(_templates);

  List<AiThreadTemplate> templatesForPlatform([TargetPlatform? platform]) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return List<AiThreadTemplate>.unmodifiable(
      _templates.where(
        (template) => template.isSupportedOnPlatform(effectivePlatform),
      ),
    );
  }

  AiThreadTemplate resolveTemplate(String templateId) {
    for (final template in _templates) {
      if (template.id == templateId) {
        return template;
      }
    }
    return _templates.first;
  }

  AiThreadTemplate resolveTemplateForPlatform(
    String templateId, {
    TargetPlatform? platform,
  }) {
    final resolved = resolveTemplate(templateId);
    final effectivePlatform = platform ?? defaultTargetPlatform;
    if (resolved.isSupportedOnPlatform(effectivePlatform)) {
      return resolved;
    }
    final supportedTemplates = templatesForPlatform(effectivePlatform);
    if (supportedTemplates.isNotEmpty) {
      return supportedTemplates.first;
    }
    return _templates.first;
  }

  Future<AiPromptTemplateBundle> loadBundle(String templateId) async {
    final resolvedTemplateId = resolveTemplate(templateId).id;
    final cached = _bundleCache[resolvedTemplateId];
    if (cached != null) {
      return cached;
    }
    final future = _loadBundleUncached(resolvedTemplateId);
    _bundleCache[resolvedTemplateId] = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace stackTrace) {
          if (identical(_bundleCache[resolvedTemplateId], future)) {
            _bundleCache.remove(resolvedTemplateId);
          }
        },
      ),
    );
    return future;
  }

  Future<AiPromptTemplateBundle> _loadBundleUncached(String templateId) async {
    final template = resolveTemplate(templateId);
    final policy = AiPromptTemplatePolicies.resolve(template.id);
    final assetDirectory = template.promptAssetDirectory;
    final fallback = _TemplatePromptFallbacks.resolve(policy.templateId);
    final systemInstructions = await _loadTemplateSection(
      '$assetDirectory/system_instructions.md',
      fallback.systemInstructions,
    );
    final developerInstructions = await _loadTemplateSection(
      '$assetDirectory/developer_instructions.md',
      fallback.developerInstructions,
    );
    final compressionSummaryInstructions = await _loadTemplateSection(
      '$assetDirectory/compression_summary_instructions.md',
      fallback.compressionSummaryInstructions,
    );
    final systemWithSharedSections = await _appendSectionsIfAbsent(
      systemInstructions,
      policy.sharedSections,
    );
    final systemWithTemplateSections = await _appendSectionsIfAbsent(
      systemWithSharedSections,
      policy.extensionSections,
    );
    final systemWithDiscipline = await _appendV4DisciplineIfAbsent(
      systemWithTemplateSections,
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

  Future<String> _appendSectionsIfAbsent(
    String instructions,
    Iterable<AiPromptSharedSectionSpec> sections,
  ) async {
    if (sections.isEmpty) {
      return instructions;
    }
    final loadedSections = <AiPromptLoadedSection>[];
    for (final section in sections) {
      final snippet = await _loadTemplateSection(section.assetPath, '');
      if (snippet.isEmpty) {
        continue;
      }
      loadedSections.add(
        AiPromptLoadedSection(tag: section.tag, content: snippet),
      );
    }
    return appendAiPromptSharedSectionsIfAbsent(instructions, loadedSections);
  }

  /// Appends the shared v4 discipline block (Uncertainty Honesty + Atomic
  /// Change Discipline; English variant additionally covers Session Bootstrap
  /// / Diff-Thinking / Verification Loop) loaded from
  /// `assets/prompts/common/v4_discipline_{en,zh}.md` when the target
  /// instruction text does not already contain a structural discipline block.
  /// Templates that ship their own specialised version (`programming_expert`,
  /// `machine_expert`) are detected via heading/tag markers and left untouched.
  /// Language is inferred from the instructions' CJK-character ratio.
  Future<String> _appendV4DisciplineIfAbsent(String instructions) async {
    final zhSnippet = await _loadTemplateSection(
      'assets/prompts/common/v4_discipline_zh.md',
      '',
    );
    final enSnippet = await _loadTemplateSection(
      'assets/prompts/common/v4_discipline_en.md',
      '',
    );
    return appendAiPromptV4DisciplineIfAbsent(
      instructions,
      zhSnippet: zhSnippet,
      enSnippet: enSnippet,
    );
  }

  /// Heuristic: treat instructions as Chinese when CJK characters make up
  /// ≥15% of all non-whitespace characters. Threshold is intentionally low
  /// because English-only templates have ~0% CJK while Chinese templates
  /// (hardness_engineering, machine_expert) routinely exceed 40%.

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
String _appendMemoryTonePolicyIfAbsent(String instructions) {
  return appendAiPromptMemoryTonePolicyIfAbsent(instructions);
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

const String _siriHelperSystemInstructions = _fallbackNotice;
const String _siriHelperDeveloperInstructions = _fallbackNotice;
const String _siriHelperCompressionSummaryInstructions = _fallbackNotice;

const String _webReverseFallbackNotice =
    '''
$_fallbackNotice

# Web Reverse fallback minimum

- Treat CDP as the source of truth for browser state, network, console, DOM, storage, screenshots, WebSocket/SSE, and HAR work.
- Use exact CDP / Chrome DevTools / js-reverse MCP tool names from the runtime catalog. If absent but deferred, call ToolSearch first; if still absent, ask the user to recover prompt assets or refresh the CDP MCP catalog.
- Live CDP requires the injected `cdp_runtime` to report `browser_alive=true` plus `cdp_http_endpoint` / `json_list_url` / `cdp_port`.
- Observe before patching: collect target request, initiator, suspicious script, runtime values, first divergence, and local artifact paths.
- Do not use Bash/WebFetch/WebSearch for target-origin capture. If live CDP is unavailable, use local jsonl/HAR artifacts or ask the user to restart the Web Reverse browser.
''';

const String _webReverseSystemInstructions = _webReverseFallbackNotice;
const String _webReverseDeveloperInstructions = _webReverseFallbackNotice;
const String _webReverseCompressionSummaryInstructions =
    _webReverseFallbackNotice;

class _TemplatePromptFallback {
  const _TemplatePromptFallback({
    required this.systemInstructions,
    required this.developerInstructions,
    required this.compressionSummaryInstructions,
  });

  final String systemInstructions;
  final String developerInstructions;
  final String compressionSummaryInstructions;
}

class _TemplatePromptFallbacks {
  const _TemplatePromptFallbacks._();

  static const _TemplatePromptFallback _default = _TemplatePromptFallback(
    systemInstructions: _defaultSystemInstructions,
    developerInstructions: _defaultDeveloperInstructions,
    compressionSummaryInstructions: _defaultCompressionSummaryInstructions,
  );

  static const Map<String, _TemplatePromptFallback>
  _byTemplateId = <String, _TemplatePromptFallback>{
    AiPromptTemplatePolicies.defaultTemplateId: _default,
    AiPromptTemplatePolicies.machineExpertTemplateId: _TemplatePromptFallback(
      systemInstructions: expertSystemInstructions,
      developerInstructions: expertDeveloperInstructions,
      compressionSummaryInstructions: expertCompressionSummaryInstructions,
    ),
    AiPromptTemplatePolicies
        .hardnessEngineeringTemplateId: _TemplatePromptFallback(
      systemInstructions: _hardnessSystemInstructions,
      developerInstructions: _hardnessDeveloperInstructions,
      compressionSummaryInstructions: _hardnessCompressionSummaryInstructions,
    ),
    AiPromptTemplatePolicies.programmingExpertTemplateId:
        _TemplatePromptFallback(
          systemInstructions: programmingExpertSystemInstructions,
          developerInstructions: programmingExpertDeveloperInstructions,
          compressionSummaryInstructions:
              programmingExpertCompressionSummaryInstructions,
        ),
    AiPromptTemplatePolicies.hermesTalkerTemplateId: _TemplatePromptFallback(
      systemInstructions: _hermesTalkerSystemInstructions,
      developerInstructions: _hermesTalkerDeveloperInstructions,
      compressionSummaryInstructions:
          _hermesTalkerCompressionSummaryInstructions,
    ),
    AiPromptTemplatePolicies
        .webReverseExpertTemplateId: _TemplatePromptFallback(
      systemInstructions: _webReverseSystemInstructions,
      developerInstructions: _webReverseDeveloperInstructions,
      compressionSummaryInstructions: _webReverseCompressionSummaryInstructions,
    ),
    AiPromptTemplatePolicies.siriHelperTemplateId: _TemplatePromptFallback(
      systemInstructions: _siriHelperSystemInstructions,
      developerInstructions: _siriHelperDeveloperInstructions,
      compressionSummaryInstructions: _siriHelperCompressionSummaryInstructions,
    ),
  };

  static _TemplatePromptFallback resolve(String templateId) {
    return _byTemplateId[templateId] ?? _default;
  }
}

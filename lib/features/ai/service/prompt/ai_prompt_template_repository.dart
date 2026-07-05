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

  static final Map<String, AiThreadTemplate> _templatesById =
      Map<String, AiThreadTemplate>.unmodifiable(<String, AiThreadTemplate>{
        for (final info in AiPromptTemplatePolicies.templateInfos)
          info.id: _threadTemplateFromInfo(info),
      });

  static final List<AiThreadTemplate> _templates =
      List<AiThreadTemplate>.unmodifiable(_templatesById.values);

  List<AiThreadTemplate> get templates => _templates;

  List<AiThreadTemplate> templatesForPlatform([TargetPlatform? platform]) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return List<AiThreadTemplate>.unmodifiable(
      templates.where(
        (template) => template.isSupportedOnPlatform(effectivePlatform),
      ),
    );
  }

  AiThreadTemplate resolveTemplate(String templateId) {
    final resolvedId = AiPromptTemplatePolicies.resolveEntry(templateId).id;
    return _templatesById[resolvedId] ?? _templatesById[_defaultTemplateId]!;
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
    return _templatesById[_defaultTemplateId]!;
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
    final catalogEntry = AiPromptTemplatePolicies.resolveEntry(templateId);
    final template = resolveTemplate(catalogEntry.id);
    final policy = catalogEntry.policy;
    final fallback = _TemplatePromptFallbacks.resolve(policy.templateId);
    final systemInstructions = await _loadTemplateAsset(
      policy,
      AiPromptTemplateAssetFiles.systemInstructions,
      fallback: fallback.systemInstructions,
    );
    final developerInstructions = await _loadTemplateAsset(
      policy,
      AiPromptTemplateAssetFiles.developerInstructions,
      fallback: fallback.developerInstructions,
    );
    final compressionSummaryInstructions = await _loadTemplateAsset(
      policy,
      AiPromptTemplateAssetFiles.compressionSummaryInstructions,
      fallback: fallback.compressionSummaryInstructions,
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

  Future<String> _loadTemplateAsset(
    AiPromptTemplatePolicy policy,
    String fileName, {
    required String fallback,
  }) {
    return _loadTemplateSection(policy.promptAssetPathFor(fileName), fallback);
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

const String _defaultTemplateId = AiPromptTemplatePolicies.defaultTemplateId;

AiThreadTemplate _threadTemplateFromInfo(AiPromptTemplateInfo info) {
  final locale = PlatformDispatcher.instance.locale;
  return AiThreadTemplate(
    id: info.id,
    name: info.nameForLocale(locale),
    iconName: info.iconName,
    description: info.descriptionForLocale(locale),
    internalVersion: info.internalVersion,
    promptAssetDirectory: info.promptAssetDirectory,
    availability: _availabilityFromScope(info.availability),
  );
}

AiThreadTemplateAvailability _availabilityFromScope(
  AiPromptTemplateAvailabilityScope availability,
) {
  return switch (availability) {
    AiPromptTemplateAvailabilityScope.appleOnly =>
      AiThreadTemplateAvailability.appleOnly,
    AiPromptTemplateAvailabilityScope.all => AiThreadTemplateAvailability.all,
  };
}

/// Shared "Memory Tone Policy" section applied to every template's system
/// instructions only. Keeping it out of the developer layer prevents the same
/// guidance from rendering twice in every assembled prompt.
///
/// Templates whose fallback already embeds this section (e.g.
/// `hermes_talker`) will NOT have it appended twice — see
/// [_appendMemoryTonePolicyIfAbsent].
String _appendMemoryTonePolicyIfAbsent(String instructions) {
  return appendAiPromptMemoryTonePolicyIfAbsent(instructions);
}

// ── Emergency fallback prompts ────────────────────────────────────────────────
// 这些常量仅在 [rootBundle.loadString] 加载 `assets/prompts/{template_id}/*.md`
// 失败时（譬如打包损坏 / 资源未注册）才会被使用。生产构建中几乎不会触发。
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

const String _androidReverseFallbackNotice =
    '''
$_fallbackNotice

# Android Reverse fallback minimum

- Run `adb devices` first to confirm a device is online before any shell / file / Frida operation.
- Use exact ADB MCP / Frida MCP tool names from the runtime catalog. If absent but deferred, call ToolSearch first.
- Static analysis (jadx / apktool / radare2) before dynamic hooking; hook scripts MUST be loaded from `assets/prompts/android_reverse_expert/snippets/`.
- Do not fabricate class names, method signatures, or API paths. If the APK has not been decompiled, decompile it first.
- Stop and report after 2 consecutive Frida / ADB failures on the same target.
''';

class _TemplatePromptFallback {
  const _TemplatePromptFallback({
    required this.systemInstructions,
    required this.developerInstructions,
    required this.compressionSummaryInstructions,
  });

  const _TemplatePromptFallback.same(String instructions)
    : systemInstructions = instructions,
      developerInstructions = instructions,
      compressionSummaryInstructions = instructions;

  final String systemInstructions;
  final String developerInstructions;
  final String compressionSummaryInstructions;
}

class _TemplatePromptFallbacks {
  const _TemplatePromptFallbacks._();

  static const _TemplatePromptFallback _default = _TemplatePromptFallback.same(
    _fallbackNotice,
  );

  static const Map<String, _TemplatePromptFallback>
  _byTemplateId = <String, _TemplatePromptFallback>{
    AiPromptTemplatePolicies.defaultTemplateId: _default,
    AiPromptTemplatePolicies.machineExpertTemplateId: _TemplatePromptFallback(
      systemInstructions: expertSystemInstructions,
      developerInstructions: expertDeveloperInstructions,
      compressionSummaryInstructions: expertCompressionSummaryInstructions,
    ),
    AiPromptTemplatePolicies.harnessEngineeringTemplateId: _default,
    AiPromptTemplatePolicies.programmingExpertTemplateId:
        _TemplatePromptFallback(
          systemInstructions: programmingExpertSystemInstructions,
          developerInstructions: programmingExpertDeveloperInstructions,
          compressionSummaryInstructions:
              programmingExpertCompressionSummaryInstructions,
        ),
    AiPromptTemplatePolicies.hermesTalkerTemplateId: _default,
    AiPromptTemplatePolicies.webReverseExpertTemplateId:
        _TemplatePromptFallback.same(_webReverseFallbackNotice),
    AiPromptTemplatePolicies.androidReverseExpertTemplateId:
        _TemplatePromptFallback.same(_androidReverseFallbackNotice),
    AiPromptTemplatePolicies.siriHelperTemplateId: _default,
  };

  static _TemplatePromptFallback resolve(String templateId) {
    return _byTemplateId[templateId] ?? _default;
  }
}

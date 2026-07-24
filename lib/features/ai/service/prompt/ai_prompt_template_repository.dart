import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../app/support/silent_log.dart';
import '../../model/ai_thread_template.dart';
import 'ai_prompt_template_assembly.dart';

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
      systemInstructions: appendAiPromptMemoryTonePolicyIfAbsent(
        systemWithDiscipline,
      ),
      // 记忆语气策略仅注入系统层，避免与开发者层重复。
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
        '加载模板片段失败，使用内置兜底：$assetPath',
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

// ── 紧急兜底提示词 ────────────────────────────────────────────────
// 仅用于提示词资源加载失败；完整内容统一在 assets/prompts/ 维护。

const String _fallbackNotice = '''
[OpenHand prompt assets unavailable]

The template prompt could not be loaded from `assets/prompts/`. Tell the user
to reinstall or rebuild the app. Do not fabricate results, files, tools, or
success. Use only tools listed in the runtime catalog. Respond briefly using
only verified information.

[OpenHand 提示词资源不可用]

无法从 `assets/prompts/` 加载模板。请告知用户重新安装或构建应用。
禁止伪造结果、文件、工具或成功状态；仅使用运行时目录中的工具，
并根据已验证信息简洁回复。
''';

const String _machineExpertFallbackNotice =
    '''
$_fallbackNotice

# Machine Expert fallback

- Use only MachineTerminal tools for terminal operations.
- Obtain user approval before write operations.
- 终端操作仅使用 MachineTerminal 工具。
- 写操作前必须征得用户同意。
''';

const String _webReverseFallbackNotice =
    '''
$_fallbackNotice

# Web Reverse fallback minimum

- Treat CDP as the source of truth for browser state, network, console, DOM, storage, screenshots, WebSocket/SSE, and HAR work.
- Use exact CDP / Chrome DevTools / js-reverse MCP names from the runtime catalog. If deferred, query and invoke them through ToolSearch; if absent, ask the user to recover prompt assets or refresh the CDP MCP catalog.
- Live CDP requires the injected `cdp_runtime` to report `browser_alive=true` plus `cdp_http_endpoint` / `json_list_url` / `cdp_port`.
- Observe before patching: collect target request, initiator, suspicious script, runtime values, first divergence, and local artifact paths.
- Do not use Bash/WebFetch/WebSearch for target-origin capture. If live CDP is unavailable, use local jsonl/HAR artifacts or ask the user to restart the Web Reverse browser.
''';

const String _androidReverseFallbackNotice =
    '''
$_fallbackNotice

# Android Reverse fallback minimum

- Run `adb devices` first to confirm a device is online before any shell / file / Frida operation.
- Use exact ADB MCP / Frida MCP names from the runtime catalog. If deferred, query and invoke them through ToolSearch.
- Static analysis (jadx / apktool / radare2) before dynamic hooking; hook scripts MUST be loaded from `assets/prompts/android_reverse_expert/snippets/`.
- Do not fabricate class names, method signatures, or API paths. If the APK has not been decompiled, decompile it first.
- Stop and report after 2 consecutive Frida / ADB failures on the same target.
''';

class _TemplatePromptFallback {
  const _TemplatePromptFallback(String instructions)
    : systemInstructions = instructions,
      developerInstructions = instructions,
      compressionSummaryInstructions = instructions;

  final String systemInstructions;
  final String developerInstructions;
  final String compressionSummaryInstructions;
}

class _TemplatePromptFallbacks {
  const _TemplatePromptFallbacks._();

  static const _TemplatePromptFallback _default = _TemplatePromptFallback(
    _fallbackNotice,
  );

  static const Map<String, _TemplatePromptFallback> _byTemplateId =
      <String, _TemplatePromptFallback>{
        AiPromptTemplatePolicies.machineExpertTemplateId:
            _TemplatePromptFallback(_machineExpertFallbackNotice),
        AiPromptTemplatePolicies.webReverseExpertTemplateId:
            _TemplatePromptFallback(_webReverseFallbackNotice),
        AiPromptTemplatePolicies.androidReverseExpertTemplateId:
            _TemplatePromptFallback(_androidReverseFallbackNotice),
      };

  static _TemplatePromptFallback resolve(String templateId) {
    return _byTemplateId[templateId] ?? _default;
  }
}

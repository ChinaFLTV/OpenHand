import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
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
  }) : _loader =
           loader ??
           ((assetPath) => rootBundle.loadString(assetPath, cache: false));

  final Future<String> Function(String assetPath) _loader;
  final Map<String, AiPromptTemplateBundle> _bundleCache =
      <String, AiPromptTemplateBundle>{};
  final OpenHandKeyedSingleFlight<String, AiPromptTemplateBundle>
  _bundleFlights = OpenHandKeyedSingleFlight<String, AiPromptTemplateBundle>();

  static final Map<String, AiThreadTemplate> _templatesById =
      Map<String, AiThreadTemplate>.unmodifiable(<String, AiThreadTemplate>{
        for (final info in AiPromptTemplatePolicies.templateInfos)
          info.id: _threadTemplateFromInfo(info),
      });

  static final List<AiThreadTemplate> _templates =
      List<AiThreadTemplate>.unmodifiable(_templatesById.values);
  static final Map<TargetPlatform, List<AiThreadTemplate>>
  _templatesByPlatform =
      Map<TargetPlatform, List<AiThreadTemplate>>.unmodifiable(
        <TargetPlatform, List<AiThreadTemplate>>{
          for (final platform in TargetPlatform.values)
            platform: List<AiThreadTemplate>.unmodifiable(
              _templates.where(
                (template) => template.isSupportedOnPlatform(platform),
              ),
            ),
        },
      );

  List<AiThreadTemplate> get templates => _templates;

  List<AiThreadTemplate> templatesForPlatform([TargetPlatform? platform]) {
    final effectivePlatform = platform ?? defaultTargetPlatform;
    return _templatesByPlatform[effectivePlatform] ?? _templates;
  }

  AiThreadTemplate resolveTemplate(String templateId) {
    final resolvedId = AiPromptTemplatePolicies.resolveEntry(templateId).id;
    return _templatesById[resolvedId] ?? _templatesById[_defaultTemplateId]!;
  }

  Future<AiPromptTemplateBundle> loadBundle(String templateId) {
    final resolvedTemplateId = resolveTemplate(templateId).id;
    final cached = _bundleCache[resolvedTemplateId];
    if (cached != null) return Future<AiPromptTemplateBundle>.value(cached);
    return _bundleFlights.run(resolvedTemplateId, () async {
      final loadState = _PromptTemplateLoadState();
      final bundle = await _loadBundleUncached(resolvedTemplateId, loadState);
      if (!loadState.assetLoadFailed) {
        _bundleCache[resolvedTemplateId] = bundle;
      }
      return bundle;
    });
  }

  Future<AiPromptTemplateBundle> _loadBundleUncached(
    String templateId,
    _PromptTemplateLoadState loadState,
  ) async {
    final catalogEntry = AiPromptTemplatePolicies.resolveEntry(templateId);
    final template = resolveTemplate(catalogEntry.id);
    final policy = catalogEntry.policy;
    final fallback = _TemplatePromptFallbacks.resolve(policy.templateId);
    final baseInstructions = await Future.wait<String>(<Future<String>>[
      _loadTemplateAsset(
        policy,
        AiPromptTemplateAssetFiles.systemInstructions,
        fallback: fallback.systemInstructions,
        loadState: loadState,
      ),
      _loadTemplateAsset(
        policy,
        AiPromptTemplateAssetFiles.developerInstructions,
        fallback: fallback.developerInstructions,
        loadState: loadState,
      ),
      _loadTemplateAsset(
        policy,
        AiPromptTemplateAssetFiles.compressionSummaryInstructions,
        fallback: fallback.compressionSummaryInstructions,
        loadState: loadState,
      ),
    ]);
    final systemInstructions = baseInstructions[0];
    final developerInstructions = baseInstructions[1];
    final compressionSummaryInstructions = baseInstructions[2];
    final systemWithSharedSections = await _appendSectionsIfAbsent(
      systemInstructions,
      policy.sharedSections,
      loadState,
    );
    final systemWithTemplateSections = await _appendSectionsIfAbsent(
      systemWithSharedSections,
      policy.extensionSections,
      loadState,
    );
    final systemWithDiscipline = await _appendV4DisciplineIfAbsent(
      systemWithTemplateSections,
      loadState,
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
    required _PromptTemplateLoadState loadState,
  }) {
    return _loadTemplateSection(
      policy.promptAssetPathFor(fileName),
      fallback,
      loadState: loadState,
    );
  }

  Future<String> _appendSectionsIfAbsent(
    String instructions,
    Iterable<AiPromptSharedSectionSpec> sections,
    _PromptTemplateLoadState loadState,
  ) async {
    if (sections.isEmpty) {
      return instructions;
    }
    final loadedSections = await Future.wait<AiPromptLoadedSection?>(
      sections.map((section) async {
        final snippet = await _loadTemplateSection(
          section.assetPath,
          '',
          loadState: loadState,
        );
        return snippet.isEmpty
            ? null
            : AiPromptLoadedSection(tag: section.tag, content: snippet);
      }),
    );
    return appendAiPromptSharedSectionsIfAbsent(
      instructions,
      loadedSections.whereType<AiPromptLoadedSection>(),
    );
  }

  /// 当目标指令尚未包含结构化纪律区块时，追加共享的 v4 纪律内容。
  /// 已内置专用版本的模板通过标题或标签识别并保持不变；语言根据中日韩字符占比判断。
  Future<String> _appendV4DisciplineIfAbsent(
    String instructions,
    _PromptTemplateLoadState loadState,
  ) async {
    final snippets = await Future.wait<String>(<Future<String>>[
      _loadTemplateSection(
        'assets/prompts/common/v4_discipline_zh.md',
        '',
        loadState: loadState,
      ),
      _loadTemplateSection(
        'assets/prompts/common/v4_discipline_en.md',
        '',
        loadState: loadState,
      ),
    ]);
    return appendAiPromptV4DisciplineIfAbsent(
      instructions,
      zhSnippet: snippets[0],
      enSnippet: snippets[1],
    );
  }

  Future<String> _loadTemplateSection(
    String assetPath,
    String fallback, {
    _PromptTemplateLoadState? loadState,
  }) async {
    try {
      final content = (await _loader(assetPath)).trim();
      return content.isEmpty ? fallback : content;
    } catch (error, stack) {
      loadState?.assetLoadFailed = true;
      silentLog(
        'ai_prompt_template_repository',
        '加载模板片段失败，使用内置兜底：$assetPath',
        error,
        stack,
      );
      return fallback;
    }
  }

  /// 加载共享的自动标题系统提示词，并替换最大标题字符数占位符。
  /// 资源缺失或不可读时使用 [fallback]。
  Future<String> loadAutoTitleSystemPrompt({
    required int maxTitleCharacters,
    required String fallback,
    void Function()? onFallback,
  }) async {
    final loadState = _PromptTemplateLoadState();
    final raw = await _loadTemplateSection(
      'assets/prompts/common/auto_title_system_prompt.md',
      fallback,
      loadState: loadState,
    );
    if (loadState.assetLoadFailed) onFallback?.call();
    return raw.replaceAll(
      '{{MAX_TITLE_CHARACTERS}}',
      maxTitleCharacters.toString(),
    );
  }
}

final class _PromptTemplateLoadState {
  bool assetLoadFailed = false;
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

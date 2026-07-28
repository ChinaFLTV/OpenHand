import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/stable_hash.dart';
import 'ai_provider_settings_shared.dart';

enum AiTranslationProvider {
  ai('ai'),
  youdao('youdao'),
  google('google'),
  bing('bing'),
  apple('apple'),
  baidu('baidu'),
  doubao('doubao');

  const AiTranslationProvider(this.storageKey);

  final String storageKey;

  static AiTranslationProvider fromStorageKey(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (provider) => provider.storageKey,
      fallback: AiTranslationProvider.ai,
    );
  }
}

class AiTranslationProviderSettings extends AiProviderCoreSettings {
  const AiTranslationProviderSettings({
    required this.provider,
    required super.enabled,
    required super.endpoint,
    required super.appId,
    required super.apiKey,
    required super.apiSecret,
    required super.accessToken,
    required super.region,
    required super.modelConfigId,
    required super.modelId,
    required super.extra,
  });

  AiTranslationProviderSettings._({
    required this.provider,
    required AiProviderCoreSettings core,
  }) : super.from(core);

  /// 出厂值构造：凭据字段一律留空，各渠道只需声明真正有差异的项。
  const AiTranslationProviderSettings._defaults({
    required this.provider,
    super.enabled,
    super.endpoint,
    super.extra,
  });

  factory AiTranslationProviderSettings.defaults(
    AiTranslationProvider provider,
  ) {
    return switch (provider) {
      // 内置 AI 渠道复用会话模型，无独立端点，默认即可用。
      AiTranslationProvider.ai => const AiTranslationProviderSettings._defaults(
        provider: AiTranslationProvider.ai,
        enabled: true,
      ),
      AiTranslationProvider.youdao =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.youdao,
          endpoint: 'https://openapi.youdao.com/api',
        ),
      AiTranslationProvider.google =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.google,
          endpoint: 'https://translation.googleapis.com/language/translate/v2',
        ),
      AiTranslationProvider.bing =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.bing,
          endpoint: 'https://api.cognitive.microsofttranslator.com/translate',
        ),
      // Apple 走系统翻译框架，没有可配置端点。
      AiTranslationProvider.apple =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.apple,
        ),
      AiTranslationProvider.baidu =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.baidu,
          endpoint: 'https://fanyi-api.baidu.com/api/trans/vip/translate',
        ),
      AiTranslationProvider.doubao =>
        const AiTranslationProviderSettings._defaults(
          provider: AiTranslationProvider.doubao,
          endpoint:
              'https://openspeech.bytedance.com/api/v3/machine_translation/matx_translate',
          extra: <String, Object?>{
            'resource_id': 'volc.speech.mt',
            'corpus_json': '',
          },
        ),
    };
  }

  factory AiTranslationProviderSettings.fromJson(
    Object? raw, {
    required AiTranslationProvider provider,
  }) {
    final defaults = AiTranslationProviderSettings.defaults(provider);
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaults;
    return AiTranslationProviderSettings._(
      provider: provider,
      core: AiProviderCoreSettings.fromJson(json, fallback: defaults),
    ).normalized();
  }

  final AiTranslationProvider provider;

  @override
  AiTranslationProviderSettings copyWith({
    bool? enabled,
    String? endpoint,
    String? appId,
    String? apiKey,
    String? apiSecret,
    String? accessToken,
    String? region,
    String? modelConfigId,
    String? modelId,
    Map<String, Object?>? extra,
  }) {
    return AiTranslationProviderSettings._(
      provider: provider,
      core: super.copyWith(
        enabled: enabled,
        endpoint: endpoint,
        appId: appId,
        apiKey: apiKey,
        apiSecret: apiSecret,
        accessToken: accessToken,
        region: region,
        modelConfigId: modelConfigId,
        modelId: modelId,
        extra: extra,
      ),
    );
  }

  AiTranslationProviderSettings normalized() {
    return AiTranslationProviderSettings._(
      provider: provider,
      core: normalizedCore(),
    );
  }
}

class AiTranslationSettings {
  const AiTranslationSettings({
    required this.enabled,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.timeoutSeconds,
    required this.maxTextCharacters,
    required this.providers,
    required this.providerPriority,
  });

  factory AiTranslationSettings.defaults() {
    return AiTranslationSettings(
      enabled: false,
      sourceLanguage: defaultSourceLanguage,
      targetLanguage: defaultTargetLanguage,
      timeoutSeconds: defaultTimeoutSeconds,
      maxTextCharacters: defaultMaxTextCharacters,
      providers: <AiTranslationProvider, AiTranslationProviderSettings>{
        for (final provider in AiTranslationProvider.values)
          provider: AiTranslationProviderSettings.defaults(provider),
      },
      providerPriority: defaultProviderPriority,
    );
  }

  factory AiTranslationSettings.fromJson(Object? raw) {
    final defaults = AiTranslationSettings.defaults();
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaults;
    return AiTranslationSettings(
      enabled: boolFromValue(json['enabled']),
      sourceLanguage:
          _normalizeLanguage(
            optionalStringFromValue(json['source_language']),
          ) ??
          defaultSourceLanguage,
      targetLanguage:
          _normalizeLanguage(
            optionalStringFromValue(json['target_language']),
          ) ??
          defaultTargetLanguage,
      timeoutSeconds: timeoutSecondsFromValue(json['timeout_seconds']),
      maxTextCharacters: maxTextCharactersFromValue(
        json['max_text_characters'],
      ),
      providers: parseAiProviderSettings(
        json['providers'],
        providers: AiTranslationProvider.values,
        storageKey: (provider) => provider.storageKey,
        parse: (provider, raw) =>
            AiTranslationProviderSettings.fromJson(raw, provider: provider),
      ),
      providerPriority: parseAiProviderPriority(
        json['provider_priority'],
        fallback: defaultProviderPriority,
        parse: AiTranslationProvider.fromStorageKey,
      ),
    ).normalized();
  }

  static const String defaultSourceLanguage = 'auto';
  static const String defaultTargetLanguage = 'zh-CN';
  static const int defaultTimeoutSeconds = 30;
  static const int minTimeoutSeconds = 3;
  static const int maxTimeoutSeconds = 120;
  static const int defaultMaxTextCharacters = 6000;
  static const int minMaxTextCharacters = 20;
  static const int maxMaxTextCharacters = 30000;
  static const IntValueRange _timeoutSecondsRange = IntValueRange(
    fallback: defaultTimeoutSeconds,
    min: minTimeoutSeconds,
    max: maxTimeoutSeconds,
  );
  static const IntValueRange _maxTextCharactersRange = IntValueRange(
    fallback: defaultMaxTextCharacters,
    min: minMaxTextCharacters,
    max: maxMaxTextCharacters,
  );
  static const List<AiTranslationProvider> defaultProviderPriority =
      <AiTranslationProvider>[
        AiTranslationProvider.ai,
        AiTranslationProvider.youdao,
        AiTranslationProvider.google,
        AiTranslationProvider.bing,
        AiTranslationProvider.apple,
        AiTranslationProvider.baidu,
        AiTranslationProvider.doubao,
      ];
  static const Set<String> supportedLanguages = <String>{
    'auto',
    'zh-CN',
    'zh-TW',
    'en',
    'ja',
    'ko',
    'fr',
    'de',
    'es',
    'ru',
    'it',
    'pt',
    'vi',
    'th',
    'id',
    'ar',
    'tr',
    'hi',
    'he',
    'nl',
    'pl',
    'sv',
    'da',
  };

  static int timeoutSecondsFromValue(Object? value) {
    return _timeoutSecondsRange.fromValue(value);
  }

  static int normalizeTimeoutSeconds(int value) {
    return _timeoutSecondsRange.normalize(value);
  }

  static int maxTextCharactersFromValue(Object? value) {
    return _maxTextCharactersRange.fromValue(value);
  }

  static int normalizeMaxTextCharacters(int value) {
    return _maxTextCharactersRange.normalize(value);
  }

  final bool enabled;
  final String sourceLanguage;
  final String targetLanguage;
  final int timeoutSeconds;
  final int maxTextCharacters;
  final Map<AiTranslationProvider, AiTranslationProviderSettings> providers;
  final List<AiTranslationProvider> providerPriority;

  AiTranslationSettings copyWith({
    bool? enabled,
    String? sourceLanguage,
    String? targetLanguage,
    int? timeoutSeconds,
    int? maxTextCharacters,
    Map<AiTranslationProvider, AiTranslationProviderSettings>? providers,
    List<AiTranslationProvider>? providerPriority,
  }) {
    return AiTranslationSettings(
      enabled: enabled ?? this.enabled,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      timeoutSeconds: normalizeTimeoutSeconds(
        timeoutSeconds ?? this.timeoutSeconds,
      ),
      maxTextCharacters: normalizeMaxTextCharacters(
        maxTextCharacters ?? this.maxTextCharacters,
      ),
      providers: providers ?? this.providers,
      providerPriority: providerPriority ?? this.providerPriority,
    );
  }

  AiTranslationSettings normalized() {
    final normalizedProviders =
        <AiTranslationProvider, AiTranslationProviderSettings>{
          for (final provider in AiTranslationProvider.values)
            provider:
                (providers[provider] ??
                        AiTranslationProviderSettings.defaults(provider))
                    .normalized(),
        };
    final normalizedTarget =
        _normalizeLanguage(targetLanguage) ?? defaultTargetLanguage;
    final normalizedSource =
        _normalizeLanguage(sourceLanguage) ?? defaultSourceLanguage;
    return AiTranslationSettings(
      enabled: enabled,
      sourceLanguage: normalizedSource,
      targetLanguage: normalizedTarget == 'auto'
          ? defaultTargetLanguage
          : normalizedTarget,
      timeoutSeconds: normalizeTimeoutSeconds(timeoutSeconds),
      maxTextCharacters: normalizeMaxTextCharacters(maxTextCharacters),
      providers:
          Map<
            AiTranslationProvider,
            AiTranslationProviderSettings
          >.unmodifiable(normalizedProviders),
      providerPriority: List<AiTranslationProvider>.unmodifiable(
        normalizeAiProviderPriority(providerPriority, defaultProviderPriority),
      ),
    );
  }

  AiTranslationProviderSettings provider(AiTranslationProvider provider) {
    return providers[provider] ??
        AiTranslationProviderSettings.defaults(provider);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'timeout_seconds': normalizeTimeoutSeconds(timeoutSeconds),
      'max_text_characters': normalizeMaxTextCharacters(maxTextCharacters),
      ...aiProviderSettingsToJson(
        providers: providers,
        priority: providerPriority,
        storageKey: (provider) => provider.storageKey,
        toJson: (settings) => settings.toJson(),
      ),
    };
  }

  String get cacheFingerprint {
    return stableJsonSha256(normalized().toJson());
  }
}

String? _normalizeLanguage(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  for (final language in AiTranslationSettings.supportedLanguages) {
    if (language.toLowerCase() == trimmed.toLowerCase()) return language;
  }
  return null;
}

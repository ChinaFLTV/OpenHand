enum AiTranslationProvider {
  ai('ai'),
  youdao('youdao'),
  google('google'),
  bing('bing'),
  apple('apple'),
  baidu('baidu');

  const AiTranslationProvider(this.storageKey);

  final String storageKey;

  static AiTranslationProvider fromStorageKey(Object? value) {
    if (value is! String) return AiTranslationProvider.ai;
    return AiTranslationProvider.values.firstWhere(
      (provider) => provider.storageKey == value,
      orElse: () => AiTranslationProvider.ai,
    );
  }
}

class AiTranslationProviderSettings {
  const AiTranslationProviderSettings({
    required this.provider,
    required this.enabled,
    required this.endpoint,
    required this.appId,
    required this.apiKey,
    required this.apiSecret,
    required this.accessToken,
    required this.region,
    required this.modelConfigId,
    required this.modelId,
    required this.extra,
  });

  factory AiTranslationProviderSettings.defaults(
    AiTranslationProvider provider,
  ) {
    switch (provider) {
      case AiTranslationProvider.ai:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.ai,
          enabled: true,
          endpoint: '',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTranslationProvider.youdao:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.youdao,
          enabled: false,
          endpoint: 'https://openapi.youdao.com/api',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTranslationProvider.google:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.google,
          enabled: false,
          endpoint: 'https://translation.googleapis.com/language/translate/v2',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTranslationProvider.bing:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.bing,
          enabled: false,
          endpoint: 'https://api.cognitive.microsofttranslator.com/translate',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTranslationProvider.apple:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.apple,
          enabled: false,
          endpoint: '',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTranslationProvider.baidu:
        return const AiTranslationProviderSettings(
          provider: AiTranslationProvider.baidu,
          enabled: false,
          endpoint: 'https://fanyi-api.baidu.com/api/trans/vip/translate',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
    }
  }

  factory AiTranslationProviderSettings.fromJson(
    Object? raw, {
    required AiTranslationProvider provider,
  }) {
    final defaults = AiTranslationProviderSettings.defaults(provider);
    if (raw is! Map) return defaults;
    final json = Map<String, Object?>.from(raw);
    return defaults
        .copyWith(
          enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
          endpoint: _stringOrNull(json['endpoint']),
          appId: _stringOrNull(json['app_id']),
          apiKey: _stringOrNull(json['api_key']),
          apiSecret: _stringOrNull(json['api_secret']),
          accessToken: _stringOrNull(json['access_token']),
          region: _stringOrNull(json['region']),
          modelConfigId: _stringOrNull(json['model_config_id']),
          modelId: _stringOrNull(json['model_id']),
          extra: json['extra'] is Map
              ? Map<String, Object?>.from(json['extra'] as Map)
              : null,
        )
        .normalized();
  }

  final AiTranslationProvider provider;
  final bool enabled;
  final String endpoint;
  final String appId;
  final String apiKey;
  final String apiSecret;
  final String accessToken;
  final String region;
  final String modelConfigId;
  final String modelId;
  final Map<String, Object?> extra;

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
    return AiTranslationProviderSettings(
      provider: provider,
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      appId: appId ?? this.appId,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      accessToken: accessToken ?? this.accessToken,
      region: region ?? this.region,
      modelConfigId: modelConfigId ?? this.modelConfigId,
      modelId: modelId ?? this.modelId,
      extra: extra ?? this.extra,
    );
  }

  AiTranslationProviderSettings normalized() {
    return copyWith(
      endpoint: endpoint.trim(),
      appId: appId.trim(),
      apiKey: apiKey.trim(),
      apiSecret: apiSecret.trim(),
      accessToken: accessToken.trim(),
      region: region.trim(),
      modelConfigId: modelConfigId.trim(),
      modelId: modelId.trim(),
      extra: Map<String, Object?>.unmodifiable(extra),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'endpoint': endpoint,
      'app_id': appId,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'access_token': accessToken,
      'region': region,
      'model_config_id': modelConfigId,
      'model_id': modelId,
      'extra': extra,
    };
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
    if (raw is! Map) return defaults;
    final json = Map<String, Object?>.from(raw);
    final rawProviders = json['providers'];
    final providers = <AiTranslationProvider, AiTranslationProviderSettings>{
      for (final provider in AiTranslationProvider.values)
        provider: AiTranslationProviderSettings.fromJson(
          rawProviders is Map ? rawProviders[provider.storageKey] : null,
          provider: provider,
        ),
    };
    final rawPriority = json['provider_priority'];
    final priority = rawPriority is List
        ? _uniqueProviders(
            rawPriority.map(AiTranslationProvider.fromStorageKey),
          )
        : defaultProviderPriority;
    return AiTranslationSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      sourceLanguage:
          _normalizeLanguage(_stringOrNull(json['source_language'])) ??
          defaultSourceLanguage,
      targetLanguage:
          _normalizeLanguage(_stringOrNull(json['target_language'])) ??
          defaultTargetLanguage,
      timeoutSeconds:
          _intOrNull(json['timeout_seconds']) ?? defaultTimeoutSeconds,
      maxTextCharacters:
          _intOrNull(json['max_text_characters']) ?? defaultMaxTextCharacters,
      providers: providers,
      providerPriority: _normalizePriority(priority),
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
  static const List<AiTranslationProvider> defaultProviderPriority =
      <AiTranslationProvider>[
        AiTranslationProvider.ai,
        AiTranslationProvider.youdao,
        AiTranslationProvider.google,
        AiTranslationProvider.bing,
        AiTranslationProvider.apple,
        AiTranslationProvider.baidu,
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
  };

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
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      maxTextCharacters: maxTextCharacters ?? this.maxTextCharacters,
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
      timeoutSeconds: timeoutSeconds
          .clamp(minTimeoutSeconds, maxTimeoutSeconds)
          .toInt(),
      maxTextCharacters: maxTextCharacters
          .clamp(minMaxTextCharacters, maxMaxTextCharacters)
          .toInt(),
      providers:
          Map<
            AiTranslationProvider,
            AiTranslationProviderSettings
          >.unmodifiable(normalizedProviders),
      providerPriority: List<AiTranslationProvider>.unmodifiable(
        _normalizePriority(providerPriority),
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
      'timeout_seconds': timeoutSeconds,
      'max_text_characters': maxTextCharacters,
      'provider_priority': providerPriority
          .map((provider) => provider.storageKey)
          .toList(growable: false),
      'providers': <String, Object?>{
        for (final entry in providers.entries)
          entry.key.storageKey: entry.value.toJson(),
      },
    };
  }

  String get cacheFingerprint {
    final activeProviders = providerPriority
        .map((provider) {
          final settings = this.provider(provider);
          return [
            provider.storageKey,
            settings.enabled,
            settings.endpoint,
            settings.region,
            settings.modelConfigId,
            settings.modelId,
          ].join(':');
        })
        .join('|');
    return [
      enabled,
      sourceLanguage,
      targetLanguage,
      timeoutSeconds,
      maxTextCharacters,
      activeProviders,
    ].join('::');
  }

  static List<AiTranslationProvider> _normalizePriority(
    List<AiTranslationProvider> priority,
  ) {
    final seen = <AiTranslationProvider>{};
    final result = <AiTranslationProvider>[];
    for (final provider in priority) {
      if (seen.add(provider)) result.add(provider);
    }
    for (final provider in defaultProviderPriority) {
      if (seen.add(provider)) result.add(provider);
    }
    return result;
  }
}

List<AiTranslationProvider> _uniqueProviders(
  Iterable<AiTranslationProvider> providers,
) {
  final seen = <AiTranslationProvider>{};
  final result = <AiTranslationProvider>[];
  for (final provider in providers) {
    if (seen.add(provider)) result.add(provider);
  }
  return result;
}

String? _normalizeLanguage(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  for (final language in AiTranslationSettings.supportedLanguages) {
    if (language.toLowerCase() == trimmed.toLowerCase()) return language;
  }
  return null;
}

String? _stringOrNull(Object? value) => value is String ? value : null;

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

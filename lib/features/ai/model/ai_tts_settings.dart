import '../../../shared/util/input_value_parsing.dart';

enum AiTtsProvider {
  ai('ai'),
  system('system'),
  xfyun('xfyun'),
  youdao('youdao'),
  bing('bing'),
  google('google'),
  baidu('baidu'),
  doubao('doubao'),
  mimo('mimo'),
  apple('apple');

  const AiTtsProvider(this.storageKey);

  final String storageKey;

  static AiTtsProvider fromStorageKey(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (provider) => provider.storageKey,
      fallback: AiTtsProvider.system,
    );
  }
}

class AiTtsProviderSettings {
  const AiTtsProviderSettings({
    required this.provider,
    required this.enabled,
    required this.voice,
    required this.language,
    required this.speed,
    required this.volume,
    required this.pitch,
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

  factory AiTtsProviderSettings.defaults(AiTtsProvider provider) {
    switch (provider) {
      case AiTtsProvider.ai:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.ai,
          enabled: false,
          voice: 'alloy',
          language: 'zh-CN',
          speed: 1.0,
          volume: 1.0,
          pitch: 0.0,
          endpoint: '',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{
            'format': 'mp3',
            'sample_rate': 24000,
            'bit_rate': 128000,
          },
        );
      case AiTtsProvider.system:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.system,
          enabled: true,
          voice: '',
          language: 'zh-CN',
          speed: 1.0,
          volume: 1.0,
          pitch: 1.0,
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
      case AiTtsProvider.xfyun:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.xfyun,
          enabled: false,
          voice: 'xiaoyan',
          language: 'zh-CN',
          speed: 50,
          volume: 50,
          pitch: 50,
          endpoint: 'wss://tts-api.xfyun.cn/v2/tts',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{
            'aue': 'lame',
            'auf': 'audio/L16;rate=16000',
          },
        );
      case AiTtsProvider.youdao:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.youdao,
          enabled: false,
          voice: '',
          language: 'zh-CHS',
          speed: 1.0,
          volume: 1.0,
          pitch: 1.0,
          endpoint: 'https://openapi.youdao.com/ttsapi',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTtsProvider.bing:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.bing,
          enabled: false,
          voice: 'zh-CN-XiaoxiaoNeural',
          language: 'zh-CN',
          speed: 1.0,
          volume: 1.0,
          pitch: 1.0,
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
      case AiTtsProvider.google:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.google,
          enabled: false,
          voice: 'zh-CN-Standard-A',
          language: 'zh-CN',
          speed: 1.0,
          volume: 0.0,
          pitch: 0.0,
          endpoint: 'https://texttospeech.googleapis.com/v1/text:synthesize',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{'audioEncoding': 'MP3'},
        );
      case AiTtsProvider.baidu:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.baidu,
          enabled: false,
          voice: '0',
          language: 'zh',
          speed: 5,
          volume: 5,
          pitch: 5,
          endpoint: 'https://tsn.baidu.com/text2audio',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{},
        );
      case AiTtsProvider.doubao:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.doubao,
          enabled: false,
          voice: 'zh_female_vv_uranus_bigtts',
          language: 'zh-CN',
          speed: 0,
          volume: 0,
          pitch: 0,
          endpoint:
              'https://openspeech.bytedance.com/api/v3/tts/unidirectional',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{
            'resource_id': 'seed-tts-2.0',
            'model': 'seed-tts-2.0-standard',
            'format': 'mp3',
            'sample_rate': 24000,
            'bit_rate': 128000,
          },
        );
      case AiTtsProvider.mimo:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.mimo,
          enabled: false,
          voice: '冰糖',
          language: 'zh-CN',
          speed: 1.0,
          volume: 1.0,
          pitch: 1.0,
          endpoint: 'https://api.xiaomimimo.com/v1/chat/completions',
          appId: '',
          apiKey: '',
          apiSecret: '',
          accessToken: '',
          region: '',
          modelConfigId: '',
          modelId: '',
          extra: <String, Object?>{
            'model': 'mimo-v2.5-tts',
            'format': 'wav',
            'style_prompt': '自然清晰，语速适中，语气友好。',
            'sample_rate': 24000,
            'voice_sample_path': '',
          },
        );
      case AiTtsProvider.apple:
        return const AiTtsProviderSettings(
          provider: AiTtsProvider.apple,
          enabled: false,
          voice: '',
          language: 'zh-CN',
          speed: 1.0,
          volume: 1.0,
          pitch: 1.0,
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
    }
  }

  factory AiTtsProviderSettings.fromJson(
    Object? raw, {
    required AiTtsProvider provider,
  }) {
    final defaults = AiTtsProviderSettings.defaults(provider);
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaults;
    return defaults
        .copyWith(
          enabled: optionalBoolFromValue(json['enabled']),
          voice: optionalStringFromValue(json['voice']),
          language: optionalStringFromValue(json['language']),
          speed: optionalDoubleFromValue(json['speed']),
          volume: optionalDoubleFromValue(json['volume']),
          pitch: optionalDoubleFromValue(json['pitch']),
          endpoint: optionalStringFromValue(json['endpoint']),
          appId: optionalStringFromValue(json['app_id']),
          apiKey: optionalStringFromValue(json['api_key']),
          apiSecret: optionalStringFromValue(json['api_secret']),
          accessToken: optionalStringFromValue(json['access_token']),
          region: optionalStringFromValue(json['region']),
          modelConfigId: optionalStringFromValue(json['model_config_id']),
          modelId: optionalStringFromValue(json['model_id']),
          extra: json['extra'] is Map
              ? stringKeyedMapFromValue(json['extra'])
              : null,
        )
        .normalized();
  }

  final AiTtsProvider provider;
  final bool enabled;
  final String voice;
  final String language;
  final double speed;
  final double volume;
  final double pitch;
  final String endpoint;
  final String appId;
  final String apiKey;
  final String apiSecret;
  final String accessToken;
  final String region;
  final String modelConfigId;
  final String modelId;
  final Map<String, Object?> extra;

  AiTtsProviderSettings copyWith({
    bool? enabled,
    String? voice,
    String? language,
    double? speed,
    double? volume,
    double? pitch,
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
    return AiTtsProviderSettings(
      provider: provider,
      enabled: enabled ?? this.enabled,
      voice: voice ?? this.voice,
      language: language ?? this.language,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
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

  AiTtsProviderSettings normalized() {
    final defaults = AiTtsProviderSettings.defaults(provider);
    final normalizedVoice = voice.trim();
    final normalizedLanguage = language.trim();
    return copyWith(
      voice: normalizedVoice.isEmpty ? defaults.voice : normalizedVoice,
      language: normalizedLanguage.isEmpty
          ? defaults.language
          : normalizedLanguage,
      speed: speed.clamp(0.1, 200.0).toDouble(),
      volume: volume.clamp(0.0, 100.0).toDouble(),
      pitch: pitch.clamp(-20.0, 100.0).toDouble(),
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
      'voice': voice,
      'language': language,
      'speed': speed,
      'volume': volume,
      'pitch': pitch,
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

class AiTtsSettings {
  const AiTtsSettings({
    required this.enabled,
    required this.timeoutSeconds,
    required this.maxTextCharacters,
    required this.providers,
    required this.providerPriority,
  });

  factory AiTtsSettings.defaults() {
    return AiTtsSettings(
      enabled: false,
      timeoutSeconds: defaultTimeoutSeconds,
      maxTextCharacters: defaultMaxTextCharacters,
      providers: <AiTtsProvider, AiTtsProviderSettings>{
        for (final provider in AiTtsProvider.values)
          provider: AiTtsProviderSettings.defaults(provider),
      },
      providerPriority: defaultProviderPriority,
    );
  }

  factory AiTtsSettings.fromJson(Object? raw) {
    final defaults = AiTtsSettings.defaults();
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaults;
    final rawProviders = json['providers'];
    final providers = <AiTtsProvider, AiTtsProviderSettings>{
      for (final provider in AiTtsProvider.values)
        provider: AiTtsProviderSettings.fromJson(
          rawProviders is Map ? rawProviders[provider.storageKey] : null,
          provider: provider,
        ),
    };
    final rawPriority = json['provider_priority'];
    final rawPriorityValues = stringListFromValueOrJsonText(rawPriority);
    final priority = rawPriorityValues.isNotEmpty
        ? _uniqueProviders(rawPriorityValues.map(AiTtsProvider.fromStorageKey))
        : defaultProviderPriority;
    return AiTtsSettings(
      enabled: boolFromValue(json['enabled']),
      timeoutSeconds:
          optionalIntFromValue(json['timeout_seconds']) ??
          defaultTimeoutSeconds,
      maxTextCharacters:
          optionalIntFromValue(json['max_text_characters']) ??
          defaultMaxTextCharacters,
      providers: providers,
      providerPriority: _normalizePriority(priority),
    ).normalized();
  }

  static const int defaultTimeoutSeconds = 30;
  static const int minTimeoutSeconds = 3;
  static const int maxTimeoutSeconds = 120;
  static const int defaultMaxTextCharacters = 4000;
  static const int minMaxTextCharacters = 20;
  static const int maxMaxTextCharacters = 20000;
  static const List<AiTtsProvider> defaultProviderPriority = <AiTtsProvider>[
    AiTtsProvider.system,
    AiTtsProvider.ai,
    AiTtsProvider.apple,
    AiTtsProvider.xfyun,
    AiTtsProvider.bing,
    AiTtsProvider.google,
    AiTtsProvider.baidu,
    AiTtsProvider.doubao,
    AiTtsProvider.youdao,
    AiTtsProvider.mimo,
  ];

  final bool enabled;
  final int timeoutSeconds;
  final int maxTextCharacters;
  final Map<AiTtsProvider, AiTtsProviderSettings> providers;
  final List<AiTtsProvider> providerPriority;

  AiTtsSettings copyWith({
    bool? enabled,
    int? timeoutSeconds,
    int? maxTextCharacters,
    Map<AiTtsProvider, AiTtsProviderSettings>? providers,
    List<AiTtsProvider>? providerPriority,
  }) {
    return AiTtsSettings(
      enabled: enabled ?? this.enabled,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      maxTextCharacters: maxTextCharacters ?? this.maxTextCharacters,
      providers: providers ?? this.providers,
      providerPriority: providerPriority ?? this.providerPriority,
    );
  }

  AiTtsSettings normalized() {
    final normalizedProviders = <AiTtsProvider, AiTtsProviderSettings>{
      for (final provider in AiTtsProvider.values)
        provider:
            (providers[provider] ?? AiTtsProviderSettings.defaults(provider))
                .normalized(),
    };
    return AiTtsSettings(
      enabled: enabled,
      timeoutSeconds: timeoutSeconds
          .clamp(minTimeoutSeconds, maxTimeoutSeconds)
          .toInt(),
      maxTextCharacters: maxTextCharacters
          .clamp(minMaxTextCharacters, maxMaxTextCharacters)
          .toInt(),
      providers: Map<AiTtsProvider, AiTtsProviderSettings>.unmodifiable(
        normalizedProviders,
      ),
      providerPriority: List<AiTtsProvider>.unmodifiable(
        _normalizePriority(providerPriority),
      ),
    );
  }

  AiTtsProviderSettings provider(AiTtsProvider provider) {
    return providers[provider] ?? AiTtsProviderSettings.defaults(provider);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
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

  static List<AiTtsProvider> _normalizePriority(List<AiTtsProvider> priority) {
    final seen = <AiTtsProvider>{};
    final result = <AiTtsProvider>[];
    for (final provider in priority) {
      if (seen.add(provider)) result.add(provider);
    }
    for (final provider in defaultProviderPriority) {
      if (seen.add(provider)) result.add(provider);
    }
    return result;
  }
}

List<AiTtsProvider> _uniqueProviders(Iterable<AiTtsProvider> providers) {
  final seen = <AiTtsProvider>{};
  final result = <AiTtsProvider>[];
  for (final provider in providers) {
    if (seen.add(provider)) result.add(provider);
  }
  return result;
}

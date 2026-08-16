import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/util/input_value_parsing.dart';
import 'ai_provider_settings_shared.dart';

const String aiMimoDefaultAudioFormat = 'wav';

const Set<String> _aiTtsConfigurationErrorMarkers = <String>{
  'credentials are incomplete',
  'api key is empty',
  'subscription key is empty',
  'region is empty',
  'speaker is empty',
  'voice is empty',
  'voice sample',
  'api key or secret is empty',
  'ai tts model',
};

bool isAiTtsConfigurationError(Object error) {
  if (error is! StateError) return false;
  final message = error.message.toLowerCase();
  return _aiTtsConfigurationErrorMarkers.any(message.contains);
}

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

class AiTtsProviderSettings extends AiProviderCoreSettings {
  const AiTtsProviderSettings({
    required this.provider,
    required super.enabled,
    required this.voice,
    required this.language,
    required this.speed,
    required this.volume,
    required this.pitch,
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

  AiTtsProviderSettings._({
    required this.provider,
    required AiProviderCoreSettings core,
    required this.voice,
    required this.language,
    required this.speed,
    required this.volume,
    required this.pitch,
  }) : super.from(core);

  /// 出厂值构造：凭据字段一律留空，各渠道只需声明真正有差异的项。
  ///
  /// [speed]、[volume]、[pitch] 的量纲由渠道自身定义（多数为 0~2 的倍率，
  /// 讯飞/百度为 0~100 与 0~15 的整数档），因此这里只提供最常见的倍率默认值。
  const AiTtsProviderSettings._defaults({
    required this.provider,
    this.voice = '',
    this.language = _defaultLanguage,
    this.speed = 1.0,
    this.volume = 1.0,
    this.pitch = 1.0,
    super.enabled,
    super.endpoint,
    super.extra,
  });

  factory AiTtsProviderSettings.defaults(AiTtsProvider provider) {
    return switch (provider) {
      // 内置 AI 渠道复用会话模型，端点由所选模型配置提供。
      AiTtsProvider.ai => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.ai,
        voice: 'alloy',
        pitch: 0.0,
        extra: <String, Object?>{
          'format': 'mp3',
          'sample_rate': _defaultSampleRate,
          'bit_rate': _defaultBitRate,
        },
      ),
      // 系统朗读无需凭据，作为开箱即用的兜底渠道默认开启。
      AiTtsProvider.system => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.system,
        enabled: true,
      ),
      AiTtsProvider.xfyun => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.xfyun,
        voice: 'xiaoyan',
        speed: 50,
        volume: 50,
        pitch: 50,
        endpoint: 'wss://tts-api.xfyun.cn/v2/tts',
        extra: <String, Object?>{'aue': 'lame', 'auf': kAudioL16Rate16000},
      ),
      AiTtsProvider.youdao => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.youdao,
        language: 'zh-CHS',
        endpoint: 'https://openapi.youdao.com/ttsapi',
      ),
      // Bing 端点由 region 拼接得到，故不预置。
      AiTtsProvider.bing => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.bing,
        voice: 'zh-CN-XiaoxiaoNeural',
      ),
      AiTtsProvider.google => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.google,
        voice: 'zh-CN-Standard-A',
        volume: 0.0,
        pitch: 0.0,
        endpoint: 'https://texttospeech.googleapis.com/v1/text:synthesize',
        extra: <String, Object?>{'audioEncoding': 'MP3'},
      ),
      AiTtsProvider.baidu => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.baidu,
        voice: '0',
        language: 'zh',
        speed: 5,
        volume: 5,
        pitch: 5,
        endpoint: 'https://tsn.baidu.com/text2audio',
      ),
      AiTtsProvider.doubao => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.doubao,
        voice: 'zh_female_vv_uranus_bigtts',
        speed: 0,
        volume: 0,
        pitch: 0,
        endpoint: 'https://openspeech.bytedance.com/api/v3/tts/unidirectional',
        extra: <String, Object?>{
          'resource_id': 'seed-tts-2.0',
          'model': 'seed-tts-2.0-standard',
          'format': 'mp3',
          'sample_rate': _defaultSampleRate,
          'bit_rate': _defaultBitRate,
        },
      ),
      AiTtsProvider.mimo => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.mimo,
        voice: 'mimo_default',
        endpoint: 'https://api.xiaomimimo.com/v1/chat/completions',
        extra: <String, Object?>{
          'model': 'mimo-v2.5-tts',
          'format': aiMimoDefaultAudioFormat,
          'style_prompt': '自然清晰，语速适中，语气友好。',
          'sample_rate': _defaultSampleRate,
          'voice_sample_path': '',
        },
      ),
      // Apple 走系统语音框架，音色随系统安装的语音包变化，不预置。
      AiTtsProvider.apple => const AiTtsProviderSettings._defaults(
        provider: AiTtsProvider.apple,
      ),
    };
  }

  factory AiTtsProviderSettings.fromJson(
    Object? raw, {
    required AiTtsProvider provider,
  }) {
    final defaults = AiTtsProviderSettings.defaults(provider);
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return defaults;
    return AiTtsProviderSettings._(
      provider: provider,
      core: AiProviderCoreSettings.fromJson(json, fallback: defaults),
      voice: optionalStringFromValue(json['voice']) ?? defaults.voice,
      language: optionalStringFromValue(json['language']) ?? defaults.language,
      speed: optionalDoubleFromValue(json['speed']) ?? defaults.speed,
      volume: optionalDoubleFromValue(json['volume']) ?? defaults.volume,
      pitch: optionalDoubleFromValue(json['pitch']) ?? defaults.pitch,
    ).normalized();
  }

  static const String _defaultLanguage = 'zh-CN';
  static const int _defaultSampleRate = 24000;
  static const int _defaultBitRate = 128000;

  final AiTtsProvider provider;
  final String voice;
  final String language;
  final double speed;
  final double volume;
  final double pitch;

  @override
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
    final defaults = AiTtsProviderSettings.defaults(provider);
    return AiTtsProviderSettings._(
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
      voice: voice ?? this.voice,
      language: language ?? this.language,
      speed: normalizeSpeed(speed ?? this.speed, fallback: defaults.speed),
      volume: normalizeVolume(volume ?? this.volume, fallback: defaults.volume),
      pitch: normalizePitch(pitch ?? this.pitch, fallback: defaults.pitch),
    );
  }

  AiTtsProviderSettings normalized() {
    final defaults = AiTtsProviderSettings.defaults(provider);
    final normalizedVoice = voice.trim();
    final normalizedLanguage = language.trim();
    final normalizedExtra = Map<String, Object?>.from(extra);
    if (provider == AiTtsProvider.mimo) {
      final format = lowercaseStringFromValue(
        normalizedExtra['format'],
        fallback: aiMimoDefaultAudioFormat,
      );
      normalizedExtra['format'] = format == 'mp3'
          ? 'mp3'
          : aiMimoDefaultAudioFormat;
    }
    return AiTtsProviderSettings._(
      provider: provider,
      core: normalizedCore(extra: normalizedExtra),
      voice: normalizedVoice.isEmpty ? defaults.voice : normalizedVoice,
      language: normalizedLanguage.isEmpty
          ? defaults.language
          : normalizedLanguage,
      speed: normalizeSpeed(speed, fallback: defaults.speed),
      volume: normalizeVolume(volume, fallback: defaults.volume),
      pitch: normalizePitch(pitch, fallback: defaults.pitch),
    );
  }

  @override
  Map<String, Object?> toJson() {
    final defaults = AiTtsProviderSettings.defaults(provider);
    final coreJson = super.toJson();
    final enabledValue = coreJson.remove('enabled');
    return <String, Object?>{
      'enabled': enabledValue,
      'voice': voice,
      'language': language,
      'speed': normalizeSpeed(speed, fallback: defaults.speed),
      'volume': normalizeVolume(volume, fallback: defaults.volume),
      'pitch': normalizePitch(pitch, fallback: defaults.pitch),
      ...coreJson,
    };
  }

  static const double minSpeed = 0.1;
  static const double maxSpeed = 200.0;
  static const double minVolume = 0.0;
  static const double maxVolume = 100.0;
  static const double minPitch = -20.0;
  static const double maxPitch = 100.0;

  static double normalizeSpeed(double value, {double fallback = 1.0}) {
    return clampDoubleToRange(
      value,
      fallback: fallback,
      min: minSpeed,
      max: maxSpeed,
    );
  }

  static double normalizeVolume(double value, {double fallback = 1.0}) {
    return clampDoubleToRange(
      value,
      fallback: fallback,
      min: minVolume,
      max: maxVolume,
    );
  }

  static double normalizePitch(double value, {double fallback = 1.0}) {
    return clampDoubleToRange(
      value,
      fallback: fallback,
      min: minPitch,
      max: maxPitch,
    );
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
    return AiTtsSettings(
      enabled: boolFromValue(json['enabled']),
      timeoutSeconds: _timeoutSecondsRange.fromValue(json['timeout_seconds']),
      maxTextCharacters: _maxTextCharactersRange.fromValue(
        json['max_text_characters'],
      ),
      providers: parseAiProviderSettings(
        json['providers'],
        providers: AiTtsProvider.values,
        storageKey: (provider) => provider.storageKey,
        parse: (provider, raw) =>
            AiTtsProviderSettings.fromJson(raw, provider: provider),
      ),
      providerPriority: parseAiProviderPriority(
        json['provider_priority'],
        fallback: defaultProviderPriority,
        parse: AiTtsProvider.fromStorageKey,
      ),
    ).normalized();
  }

  static const int defaultTimeoutSeconds = 30;
  static const int minTimeoutSeconds = 3;
  static const int maxTimeoutSeconds = 120;
  static const int defaultMaxTextCharacters = 4000;
  static const int minMaxTextCharacters = 20;
  static const int maxMaxTextCharacters = 20000;
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
      timeoutSeconds: _timeoutSecondsRange.normalize(
        timeoutSeconds ?? this.timeoutSeconds,
      ),
      maxTextCharacters: _maxTextCharactersRange.normalize(
        maxTextCharacters ?? this.maxTextCharacters,
      ),
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
      timeoutSeconds: _timeoutSecondsRange.normalize(timeoutSeconds),
      maxTextCharacters: _maxTextCharactersRange.normalize(maxTextCharacters),
      providers: Map<AiTtsProvider, AiTtsProviderSettings>.unmodifiable(
        normalizedProviders,
      ),
      providerPriority: List<AiTtsProvider>.unmodifiable(
        normalizeAiProviderPriority(providerPriority, defaultProviderPriority),
      ),
    );
  }

  AiTtsProviderSettings provider(AiTtsProvider provider) {
    return providers[provider] ?? AiTtsProviderSettings.defaults(provider);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'timeout_seconds': _timeoutSecondsRange.normalize(timeoutSeconds),
      'max_text_characters': _maxTextCharactersRange.normalize(
        maxTextCharacters,
      ),
      ...aiProviderSettingsToJson(
        providers: providers,
        priority: providerPriority,
        storageKey: (provider) => provider.storageKey,
        toJson: (settings) => settings.toJson(),
      ),
    };
  }
}

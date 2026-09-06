import '../../../shared/util/input_value_parsing.dart';

enum OfflineSpeechKind {
  recognition('asr'),
  synthesis('tts');

  const OfflineSpeechKind(this.storageKey);

  final String storageKey;
}

enum OfflineSpeechRuntime {
  funAsr,
  qwenAsr,
  fasterWhisper,
  sherpaOnnx,
  cosyVoice,
  qwenTts,
}

enum OfflineSpeechDeployment { local, online }

enum OnlineSpeechTransport {
  aoq('AOQ'),
  webSocket('WSS'),
  http('HTTP');

  const OnlineSpeechTransport(this.label);

  final String label;
}

enum OnlineSpeechService {
  xfyunRtasr,
  xfyunRtasrLlm,
  xfyunTts,
  bailianTaskAsr,
  bailianRealtimeAsr,
  bailianTaskTts,
  bailianRealtimeTts,
  bailianSambertTts,
}

enum OfflineSpeechSynthesisTransport {
  http('HTTP'),
  webSocket('WSS');

  const OfflineSpeechSynthesisTransport(this.label);

  final String label;
}

enum OfflineSpeechParameterType {
  text,
  json,
  secret,
  integer,
  decimal,
  toggle,
  choice,
  multiChoice,
  path,
}

class OfflineSpeechOption {
  const OfflineSpeechOption(
    this.value,
    this.label, {
    this.language = '',
    this.description = '',
  });

  final String value;
  final String label;
  final String language;
  final String description;

  bool get hasDetails => language.isNotEmpty || description.isNotEmpty;
}

class OfflineSpeechParameter {
  const OfflineSpeechParameter({
    required this.key,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.options = const <OfflineSpeechOption>[],
    this.min,
    this.max,
  });

  final String key;
  final String label;
  final String description;
  final OfflineSpeechParameterType type;
  final Object defaultValue;
  final List<OfflineSpeechOption> options;
  final double? min;
  final double? max;

  Object normalize(Object? value) {
    return switch (type) {
      OfflineSpeechParameterType.toggle => boolFromValue(
        value,
        defaultValue: defaultValue as bool,
      ),
      OfflineSpeechParameterType.integer => _number(value, integer: true),
      OfflineSpeechParameterType.decimal => _number(value, integer: false),
      OfflineSpeechParameterType.choice => _choice(value),
      OfflineSpeechParameterType.multiChoice => _multiChoice(value),
      OfflineSpeechParameterType.text ||
      OfflineSpeechParameterType.json ||
      OfflineSpeechParameterType.secret ||
      OfflineSpeechParameterType.path =>
        value is String ? value.trim() : '$defaultValue',
    };
  }

  Object _number(Object? value, {required bool integer}) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    final fallback = (defaultValue as num).toDouble();
    final normalized = (parsed ?? fallback).clamp(
      min ?? double.negativeInfinity,
      max ?? double.infinity,
    );
    return integer ? normalized.round() : normalized;
  }

  Object _choice(Object? value) {
    final candidate = value is String ? value.trim() : '$defaultValue';
    return options.any((option) => option.value == candidate)
        ? candidate
        : defaultValue;
  }

  Object _multiChoice(Object? value) {
    final source = value is Iterable
        ? value.map((item) => '$item')
        : '${value ?? defaultValue}'.split(',');
    final allowed = options.map((option) => option.value).toSet();
    return source
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && allowed.contains(item))
        .toSet()
        .join(',');
  }
}

class OfflineSpeechModelDefinition {
  const OfflineSpeechModelDefinition({
    required this.id,
    required this.name,
    required this.kind,
    OfflineSpeechRuntime? runtime,
    required this.repository,
    required this.description,
    required this.sizeLabel,
    required this.parameters,
    this.deployment = OfflineSpeechDeployment.local,
    this.onlineService,
    this.onlineTransports = const <OnlineSpeechTransport>[
      OnlineSpeechTransport.webSocket,
    ],
    this.synthesisTransport = OfflineSpeechSynthesisTransport.http,
  }) : _runtime = runtime,
       assert(
         deployment == OfflineSpeechDeployment.local
             ? onlineService == null && runtime != null
             : onlineService != null,
       );

  final String id;
  final String name;
  final OfflineSpeechKind kind;
  final OfflineSpeechRuntime? _runtime;
  final String repository;
  final String description;
  final String sizeLabel;
  final List<OfflineSpeechParameter> parameters;
  final OfflineSpeechDeployment deployment;
  final OnlineSpeechService? onlineService;
  final List<OnlineSpeechTransport> onlineTransports;
  final OfflineSpeechSynthesisTransport synthesisTransport;

  bool get isOnline => deployment == OfflineSpeechDeployment.online;
  OfflineSpeechRuntime get runtime =>
      _runtime ?? (throw StateError('在线语音服务没有本地运行时。'));

  OnlineSpeechTransport? selectOnlineTransport(
    Set<OnlineSpeechTransport> available,
  ) {
    if (!isOnline) return null;
    for (final transport in OnlineSpeechTransport.values) {
      if (onlineTransports.contains(transport) &&
          available.contains(transport)) {
        return transport;
      }
    }
    return null;
  }

  Map<String, Object?> defaults() => <String, Object?>{
    for (final parameter in parameters) parameter.key: parameter.defaultValue,
  };

  Map<String, Object?> normalizeConfiguration(Object? raw) {
    final source = raw is Map
        ? stringKeyedMapFromValue(raw)
        : const <String, Object?>{};
    return <String, Object?>{
      for (final parameter in parameters)
        parameter.key: parameter.normalize(source[parameter.key]),
    };
  }
}

class OfflineSpeechModelSettings {
  const OfflineSpeechModelSettings({
    required this.enabledModelId,
    required this.configurations,
  });

  factory OfflineSpeechModelSettings.defaults(OfflineSpeechKind kind) {
    return const OfflineSpeechModelSettings(
      enabledModelId: null,
      configurations: <String, Map<String, Object?>>{},
    ).normalized(kind);
  }

  factory OfflineSpeechModelSettings.fromJson(
    Object? raw,
    OfflineSpeechKind kind,
  ) {
    if (raw is! Map) return OfflineSpeechModelSettings.defaults(kind);
    final json = stringKeyedMapFromValue(raw);
    final rawConfigurations = json['configurations'];
    final configurations = <String, Map<String, Object?>>{};
    if (rawConfigurations is Map) {
      for (final entry in rawConfigurations.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        configurations[entry.key as String] = stringKeyedMapFromValue(
          entry.value,
        );
      }
    }
    return OfflineSpeechModelSettings(
      enabledModelId: optionalStringFromValue(json['enabled_model_id']),
      configurations: configurations,
    ).normalized(kind);
  }

  final String? enabledModelId;
  final Map<String, Map<String, Object?>> configurations;

  Map<String, Object?> configuration(OfflineSpeechModelDefinition model) {
    return model.normalizeConfiguration(configurations[model.id]);
  }

  OfflineSpeechModelSettings select(String? modelId) {
    return OfflineSpeechModelSettings(
      enabledModelId: modelId,
      configurations: configurations,
    );
  }

  OfflineSpeechModelSettings updateConfiguration(
    OfflineSpeechModelDefinition model,
    Map<String, Object?> configuration,
  ) {
    return OfflineSpeechModelSettings(
      enabledModelId: enabledModelId,
      configurations: <String, Map<String, Object?>>{
        ...configurations,
        model.id: model.normalizeConfiguration(configuration),
      },
    );
  }

  OfflineSpeechModelSettings normalized(OfflineSpeechKind kind) {
    final models = OfflineSpeechModelCatalog.forKind(kind);
    final modelIds = models.map((model) => model.id).toSet();
    final normalizedConfigurations = <String, Map<String, Object?>>{};
    for (final model in models) {
      final raw = configurations[model.id];
      if (raw != null) {
        normalizedConfigurations[model.id] = model.normalizeConfiguration(raw);
      }
    }
    return OfflineSpeechModelSettings(
      enabledModelId: modelIds.contains(enabledModelId) ? enabledModelId : null,
      configurations: normalizedConfigurations,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (enabledModelId != null) 'enabled_model_id': enabledModelId,
    'configurations': configurations,
  };
}

class OfflineSpeechTextPolishingSettings {
  const OfflineSpeechTextPolishingSettings({
    required this.enabled,
    required this.modelConfigId,
    required this.modelId,
    required this.reasoningEffort,
  });

  const OfflineSpeechTextPolishingSettings.disabled()
    : enabled = false,
      modelConfigId = null,
      modelId = null,
      reasoningEffort = null;

  factory OfflineSpeechTextPolishingSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return const OfflineSpeechTextPolishingSettings.disabled();
    }
    final json = stringKeyedMapFromValue(raw);
    return OfflineSpeechTextPolishingSettings(
      enabled: boolFromValue(json['enabled']),
      modelConfigId: optionalStringFromValue(json['model_config_id']),
      modelId: optionalStringFromValue(json['model_id']),
      reasoningEffort: optionalStringFromValue(json['reasoning_effort']),
    ).normalized();
  }

  final bool enabled;
  final String? modelConfigId;
  final String? modelId;
  final String? reasoningEffort;

  OfflineSpeechTextPolishingSettings setEnabled(bool value) {
    return OfflineSpeechTextPolishingSettings(
      enabled: value,
      modelConfigId: modelConfigId,
      modelId: modelId,
      reasoningEffort: reasoningEffort,
    );
  }

  OfflineSpeechTextPolishingSettings selectModel({
    required String modelConfigId,
    required String modelId,
    required String? reasoningEffort,
  }) {
    return OfflineSpeechTextPolishingSettings(
      enabled: enabled,
      modelConfigId: modelConfigId,
      modelId: modelId,
      reasoningEffort: reasoningEffort,
    ).normalized();
  }

  OfflineSpeechTextPolishingSettings setReasoningEffort(String? value) {
    return OfflineSpeechTextPolishingSettings(
      enabled: enabled,
      modelConfigId: modelConfigId,
      modelId: modelId,
      reasoningEffort: value,
    ).normalized();
  }

  OfflineSpeechTextPolishingSettings normalized() {
    final normalizedConfigId = optionalStringFromValue(modelConfigId);
    final normalizedModelId = optionalStringFromValue(modelId);
    return OfflineSpeechTextPolishingSettings(
      enabled: enabled,
      modelConfigId: normalizedConfigId,
      modelId: normalizedConfigId == null ? null : normalizedModelId,
      reasoningEffort: normalizedConfigId == null || normalizedModelId == null
          ? null
          : optionalStringFromValue(reasoningEffort),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    if (modelConfigId != null) 'model_config_id': modelConfigId,
    if (modelId != null) 'model_id': modelId,
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
  };
}

class OfflineSpeechSettings {
  const OfflineSpeechSettings({
    required this.recognition,
    required this.synthesis,
    required this.textPolishing,
    required this.silenceTimeoutSeconds,
  });

  factory OfflineSpeechSettings.defaults() => OfflineSpeechSettings(
    recognition: OfflineSpeechModelSettings.defaults(
      OfflineSpeechKind.recognition,
    ),
    synthesis: OfflineSpeechModelSettings.defaults(OfflineSpeechKind.synthesis),
    textPolishing: const OfflineSpeechTextPolishingSettings.disabled(),
    silenceTimeoutSeconds: defaultSilenceTimeoutSeconds,
  );

  factory OfflineSpeechSettings.fromJson(Object? raw) {
    if (raw is! Map) return OfflineSpeechSettings.defaults();
    final json = stringKeyedMapFromValue(raw);
    return OfflineSpeechSettings(
      recognition: OfflineSpeechModelSettings.fromJson(
        json[OfflineSpeechKind.recognition.storageKey],
        OfflineSpeechKind.recognition,
      ),
      synthesis: OfflineSpeechModelSettings.fromJson(
        json[OfflineSpeechKind.synthesis.storageKey],
        OfflineSpeechKind.synthesis,
      ),
      textPolishing: OfflineSpeechTextPolishingSettings.fromJson(
        json['text_polishing'],
      ),
      silenceTimeoutSeconds: intFromValue(
        json['silence_timeout_seconds'],
        fallback: defaultSilenceTimeoutSeconds,
      ),
    ).normalized();
  }

  static const int defaultSilenceTimeoutSeconds = 3;
  static const int minSilenceTimeoutSeconds = 1;
  static const int maxSilenceTimeoutSeconds = 15;

  final OfflineSpeechModelSettings recognition;
  final OfflineSpeechModelSettings synthesis;
  final OfflineSpeechTextPolishingSettings textPolishing;
  final int silenceTimeoutSeconds;

  OfflineSpeechModelSettings settingsFor(OfflineSpeechKind kind) {
    return kind == OfflineSpeechKind.recognition ? recognition : synthesis;
  }

  OfflineSpeechSettings update(
    OfflineSpeechKind kind,
    OfflineSpeechModelSettings settings,
  ) {
    return OfflineSpeechSettings(
      recognition: kind == OfflineSpeechKind.recognition
          ? settings.normalized(kind)
          : recognition,
      synthesis: kind == OfflineSpeechKind.synthesis
          ? settings.normalized(kind)
          : synthesis,
      textPolishing: textPolishing,
      silenceTimeoutSeconds: silenceTimeoutSeconds,
    );
  }

  OfflineSpeechSettings updateTextPolishing(
    OfflineSpeechTextPolishingSettings settings,
  ) {
    return OfflineSpeechSettings(
      recognition: recognition,
      synthesis: synthesis,
      textPolishing: settings.normalized(),
      silenceTimeoutSeconds: silenceTimeoutSeconds,
    );
  }

  OfflineSpeechSettings setSilenceTimeoutSeconds(int value) {
    return OfflineSpeechSettings(
      recognition: recognition,
      synthesis: synthesis,
      textPolishing: textPolishing,
      silenceTimeoutSeconds: value.clamp(
        minSilenceTimeoutSeconds,
        maxSilenceTimeoutSeconds,
      ),
    );
  }

  OfflineSpeechSettings normalized() => OfflineSpeechSettings(
    recognition: recognition.normalized(OfflineSpeechKind.recognition),
    synthesis: synthesis.normalized(OfflineSpeechKind.synthesis),
    textPolishing: textPolishing.normalized(),
    silenceTimeoutSeconds: silenceTimeoutSeconds.clamp(
      minSilenceTimeoutSeconds,
      maxSilenceTimeoutSeconds,
    ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    OfflineSpeechKind.recognition.storageKey: recognition.toJson(),
    OfflineSpeechKind.synthesis.storageKey: synthesis.toJson(),
    'text_polishing': textPolishing.toJson(),
    'silence_timeout_seconds': silenceTimeoutSeconds,
  };
}

abstract final class OfflineSpeechModelCatalog {
  static const _autoLanguage = <OfflineSpeechOption>[
    OfflineSpeechOption('auto', '自动检测'),
    OfflineSpeechOption('zh', '中文'),
    OfflineSpeechOption('yue', '粤语'),
    OfflineSpeechOption('en', '英语'),
    OfflineSpeechOption('ja', '日语'),
    OfflineSpeechOption('ko', '韩语'),
  ];
  static const _device = <OfflineSpeechOption>[
    OfflineSpeechOption('auto', '自动'),
    OfflineSpeechOption('cpu', 'CPU'),
    OfflineSpeechOption('cuda', 'CUDA'),
    OfflineSpeechOption('mps', 'Apple Metal'),
  ];
  static const _dtype = <OfflineSpeechOption>[
    OfflineSpeechOption('auto', '自动'),
    OfflineSpeechOption('float32', 'FP32'),
    OfflineSpeechOption('float16', 'FP16'),
    OfflineSpeechOption('bfloat16', 'BF16'),
  ];
  static const _provider = <OfflineSpeechOption>[
    OfflineSpeechOption('cpu', 'CPU'),
    OfflineSpeechOption('coreml', 'Core ML'),
    OfflineSpeechOption('cuda', 'CUDA'),
  ];
  static const _xfyunTranslationLanguages = <OfflineSpeechOption>[
    OfflineSpeechOption('', '关闭翻译'),
    OfflineSpeechOption('cn', '中文'),
    OfflineSpeechOption('en', '英语'),
    OfflineSpeechOption('ja', '日语'),
    OfflineSpeechOption('ko', '韩语'),
    OfflineSpeechOption('ru', '俄语'),
    OfflineSpeechOption('fr', '法语'),
    OfflineSpeechOption('es', '西班牙语'),
    OfflineSpeechOption('vi', '越南语'),
    OfflineSpeechOption('cn_cantonese', '粤语'),
    OfflineSpeechOption('de', '德语'),
    OfflineSpeechOption('it', '意大利语'),
    OfflineSpeechOption('ar', '阿拉伯语'),
  ];
  static const _xfyunDomains = <OfflineSpeechOption>[
    OfflineSpeechOption('', '通用'),
    OfflineSpeechOption('court', '法律／法院'),
    OfflineSpeechOption('finance', '金融'),
    OfflineSpeechOption('medical', '医疗'),
    OfflineSpeechOption('tech', '科技'),
    OfflineSpeechOption('sport', '体育'),
    OfflineSpeechOption('edu', '教育'),
    OfflineSpeechOption('isp', '运营商'),
    OfflineSpeechOption('gov', '政府'),
    OfflineSpeechOption('game', '游戏'),
    OfflineSpeechOption('ecom', '电商'),
    OfflineSpeechOption('mil', '军事'),
    OfflineSpeechOption('com', '企业'),
    OfflineSpeechOption('life', '生活'),
    OfflineSpeechOption('ent', '娱乐'),
    OfflineSpeechOption('culture', '人文历史'),
    OfflineSpeechOption('car', '汽车'),
  ];
  static const _xfyunStandardDomains = <OfflineSpeechOption>[
    OfflineSpeechOption('', '通用'),
    OfflineSpeechOption('court', '法院'),
    OfflineSpeechOption('edu', '教育'),
    OfflineSpeechOption('finance', '金融'),
    OfflineSpeechOption('medical', '医疗'),
    OfflineSpeechOption('tech', '科技'),
    OfflineSpeechOption('isp', '运营商'),
    OfflineSpeechOption('gov', '政府'),
    OfflineSpeechOption('ecom', '电商'),
    OfflineSpeechOption('mil', '军事'),
    OfflineSpeechOption('com', '企业'),
    OfflineSpeechOption('life', '生活'),
    OfflineSpeechOption('car', '汽车'),
  ];
  static const _xfyunRecognitionLanguages = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'cn',
      '中文普通话',
      language: '中文',
      description: '标准实时转写默认语种，支持中英文混合识别。',
    ),
    OfflineSpeechOption(
      'en',
      '英语',
      language: 'English',
      description: '英语实时转写；其他已开通小语种仍可直接输入控制台参数值。',
    ),
  ];
  static const _xfyunLlmLanguages = <OfflineSpeechOption>[
    OfflineSpeechOption('cn', '中文', language: '普通话'),
    OfflineSpeechOption('en', '英语', language: 'English'),
    OfflineSpeechOption('ja', '日语', language: '日本語'),
    OfflineSpeechOption('ko', '韩语', language: '한국어'),
    OfflineSpeechOption('ru', '俄语', language: 'Русский'),
    OfflineSpeechOption('fr', '法语', language: 'Français'),
    OfflineSpeechOption('es', '西班牙语', language: 'Español'),
    OfflineSpeechOption('ar', '阿拉伯语', language: 'العربية'),
    OfflineSpeechOption('de', '德语', language: 'Deutsch'),
    OfflineSpeechOption('th', '泰语', language: 'ไทย'),
    OfflineSpeechOption('vi', '越南语', language: 'Tiếng Việt'),
    OfflineSpeechOption('hi', '印地语', language: 'हिन्दी'),
    OfflineSpeechOption('pt', '葡萄牙语', language: 'Português'),
    OfflineSpeechOption('it', '意大利语', language: 'Italiano'),
    OfflineSpeechOption('ms', '马来语', language: 'Bahasa Melayu'),
    OfflineSpeechOption('id', '印尼语', language: 'Bahasa Indonesia'),
    OfflineSpeechOption('fil', '菲律宾语', language: 'Filipino'),
    OfflineSpeechOption('tr', '土耳其语', language: 'Türkçe'),
    OfflineSpeechOption('el', '希腊语', language: 'Ελληνικά'),
    OfflineSpeechOption('cs', '捷克语', language: 'Čeština'),
    OfflineSpeechOption('ur', '乌尔都语', language: 'اردو'),
    OfflineSpeechOption('bn', '孟加拉语', language: 'বাংলা'),
    OfflineSpeechOption('ta', '泰米尔语', language: 'தமிழ்'),
    OfflineSpeechOption('uk', '乌克兰语', language: 'Українська'),
    OfflineSpeechOption('kk', '哈萨克语', language: 'Қазақша'),
    OfflineSpeechOption('uz', '乌兹别克语', language: 'Oʻzbekcha'),
    OfflineSpeechOption('pl', '波兰语', language: 'Polski'),
    OfflineSpeechOption('mn', '蒙古语', language: 'Монгол'),
    OfflineSpeechOption('sw', '斯瓦希里语', language: 'Kiswahili'),
    OfflineSpeechOption('ha', '豪萨语', language: 'Hausa'),
    OfflineSpeechOption('fa', '波斯语', language: 'فارسی'),
    OfflineSpeechOption('nl', '荷兰语', language: 'Nederlands'),
    OfflineSpeechOption('sv', '瑞典语', language: 'Svenska'),
    OfflineSpeechOption('ro', '罗马尼亚语', language: 'Română'),
    OfflineSpeechOption('bg', '保加利亚语', language: 'Български'),
    OfflineSpeechOption('cn_uyghur', '维吾尔语', language: 'ئۇيغۇرچە'),
    OfflineSpeechOption('cn_tibetan', '藏语', language: 'བོད་སྐད'),
  ];
  static const _xfyunTtsVoices = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'x4_xiaoyan',
      '讯飞小燕',
      language: '普通话',
      description: '官方默认基础发音人；自然通用女声。',
    ),
    OfflineSpeechOption(
      'x4_yezi',
      '讯飞小露',
      language: '普通话',
      description: '控制台基础发音人，适合通用中文朗读。',
    ),
    OfflineSpeechOption(
      'xiaoyan',
      '讯飞小燕（经典）',
      language: '普通话',
      description: '经典参数值；是否可用取决于账号已开通资源。',
    ),
    OfflineSpeechOption(
      'aisjiuxu',
      '讯飞许久',
      language: '普通话',
      description: '控制台常用中文发音人。',
    ),
    OfflineSpeechOption(
      'aisxping',
      '讯飞小萍',
      language: '普通话',
      description: '控制台常用中文发音人。',
    ),
    OfflineSpeechOption(
      'aisjinger',
      '讯飞小婧',
      language: '普通话',
      description: '控制台常用中文发音人。',
    ),
    OfflineSpeechOption(
      'aisbabyxu',
      '讯飞许小宝',
      language: '普通话',
      description: '控制台常用童声音色。',
    ),
    OfflineSpeechOption(
      'x2_xiaofeng',
      '讯飞小峰',
      language: '普通话',
      description: '控制台常用中文男声。',
    ),
  ];
  static const _bailianInferenceEndpoints = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
      '华北 2（北京）',
      language: '公网',
      description: '百炼北京地域通用 WebSocket 任务端点。',
    ),
    OfflineSpeechOption(
      'wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference',
      '新加坡',
      language: '国际站',
      description: '百炼新加坡地域 WebSocket 任务端点。',
    ),
  ];
  static const _bailianRealtimeEndpoints = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'wss://dashscope.aliyuncs.com/api-ws/v1/realtime',
      '华北 2（北京）',
      language: '公网',
      description: '百炼北京地域 Realtime WebSocket 端点。',
    ),
    OfflineSpeechOption(
      'wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime',
      '新加坡',
      language: '国际站',
      description: '百炼新加坡地域 Realtime WebSocket 端点。',
    ),
  ];
  static const _bailianCredentials = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'api_key',
      label: '百炼 API Key',
      description: '必须与服务地域、业务空间一致，仅用于建立加密连接。',
      type: OfflineSpeechParameterType.secret,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'workspace_id',
      label: '业务空间 ID',
      description: '可选；使用子业务空间时填写 Workspace ID。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'data_inspection',
      label: '内容安全检查',
      description: '通过 X-DashScope-DataInspection 请求头开启官方内容检查。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
  ];
  static const _bailianAudioFormats = <OfflineSpeechOption>[
    OfflineSpeechOption('pcm', 'PCM · 实时麦克风'),
    OfflineSpeechOption('wav', 'WAV（PCM 编码）'),
    OfflineSpeechOption('mp3', 'MP3'),
    OfflineSpeechOption('opus', 'Ogg Opus'),
    OfflineSpeechOption('speex', 'Ogg Speex'),
    OfflineSpeechOption('aac', 'AAC'),
    OfflineSpeechOption('amr', 'AMR-NB'),
  ];
  static const _bailianAsrLanguages = <OfflineSpeechOption>[
    OfflineSpeechOption('', '自动检测'),
    OfflineSpeechOption('zh', '中文'),
    OfflineSpeechOption('yue', '粤语'),
    OfflineSpeechOption('en', '英语'),
    OfflineSpeechOption('ja', '日语'),
    OfflineSpeechOption('ko', '韩语'),
    OfflineSpeechOption('vi', '越南语'),
    OfflineSpeechOption('th', '泰语'),
    OfflineSpeechOption('id', '印尼语'),
    OfflineSpeechOption('ms', '马来语'),
    OfflineSpeechOption('tl', '菲律宾语'),
    OfflineSpeechOption('hi', '印地语'),
    OfflineSpeechOption('ar', '阿拉伯语'),
    OfflineSpeechOption('fr', '法语'),
    OfflineSpeechOption('de', '德语'),
    OfflineSpeechOption('es', '西班牙语'),
    OfflineSpeechOption('pt', '葡萄牙语'),
    OfflineSpeechOption('ru', '俄语'),
    OfflineSpeechOption('it', '意大利语'),
    OfflineSpeechOption('nl', '荷兰语'),
    OfflineSpeechOption('sv', '瑞典语'),
    OfflineSpeechOption('da', '丹麦语'),
    OfflineSpeechOption('fi', '芬兰语'),
    OfflineSpeechOption('no', '挪威语'),
    OfflineSpeechOption('el', '希腊语'),
    OfflineSpeechOption('pl', '波兰语'),
    OfflineSpeechOption('cs', '捷克语'),
    OfflineSpeechOption('hu', '匈牙利语'),
    OfflineSpeechOption('ro', '罗马尼亚语'),
    OfflineSpeechOption('bg', '保加利亚语'),
    OfflineSpeechOption('hr', '克罗地亚语'),
    OfflineSpeechOption('sk', '斯洛伐克语'),
    OfflineSpeechOption('tr', '土耳其语'),
    OfflineSpeechOption('uk', '乌克兰语'),
    OfflineSpeechOption('is', '冰岛语'),
  ];
  static const _bailianQwen3AsrLanguages = <OfflineSpeechOption>[
    OfflineSpeechOption('', '自动检测'),
    OfflineSpeechOption('zh', '中文'),
    OfflineSpeechOption('yue', '粤语'),
    OfflineSpeechOption('en', '英语'),
    OfflineSpeechOption('ja', '日语'),
    OfflineSpeechOption('de', '德语'),
    OfflineSpeechOption('ko', '韩语'),
    OfflineSpeechOption('ru', '俄语'),
    OfflineSpeechOption('fr', '法语'),
    OfflineSpeechOption('pt', '葡萄牙语'),
    OfflineSpeechOption('ar', '阿拉伯语'),
    OfflineSpeechOption('it', '意大利语'),
    OfflineSpeechOption('es', '西班牙语'),
    OfflineSpeechOption('hi', '印地语'),
    OfflineSpeechOption('id', '印尼语'),
    OfflineSpeechOption('th', '泰语'),
    OfflineSpeechOption('tr', '土耳其语'),
    OfflineSpeechOption('uk', '乌克兰语'),
    OfflineSpeechOption('vi', '越南语'),
    OfflineSpeechOption('cs', '捷克语'),
    OfflineSpeechOption('da', '丹麦语'),
    OfflineSpeechOption('fil', '菲律宾语'),
    OfflineSpeechOption('fi', '芬兰语'),
    OfflineSpeechOption('is', '冰岛语'),
    OfflineSpeechOption('ms', '马来语'),
    OfflineSpeechOption('no', '挪威语'),
    OfflineSpeechOption('pl', '波兰语'),
    OfflineSpeechOption('sv', '瑞典语'),
  ];
  static const _bailianTaskTtsVoices = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'longanlingxin',
      '龙安灵心',
      language: '普通话、英语',
      description: 'Qwen-Audio Plus · 25 岁女声 · 知心温暖，适合社交陪伴。',
    ),
    OfflineSpeechOption(
      'longanlufeng',
      '龙安鲁风',
      language: '普通话、英语',
      description: 'Qwen-Audio Plus · 25 岁男声 · 明亮开朗。',
    ),
    OfflineSpeechOption(
      'longanfengyue',
      '龙安风悦',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 30 岁女声 · 自然亲切。',
    ),
    OfflineSpeechOption(
      'longanyuanfei',
      '龙安元妃',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 30 岁女声 · 高傲妃子音。',
    ),
    OfflineSpeechOption(
      'longanlingxi',
      '龙安灵希',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 25 岁女声 · 可爱甜美。',
    ),
    OfflineSpeechOption(
      'longanxiaoxin',
      '龙安小昕',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 22 岁女声 · 亲切活泼。',
    ),
    OfflineSpeechOption(
      'longanhuan_v3.6',
      '龙安欢',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 25 岁女声。',
    ),
    OfflineSpeechOption(
      'longjielidou_v3.6',
      '龙杰力豆',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 5 岁男童 · 天真活泼。',
    ),
    OfflineSpeechOption(
      'longpaopao_v3.6',
      '龙泡泡',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 5 岁女童 · 软糯可爱。',
    ),
    OfflineSpeechOption(
      'longhuohuo_v3.6',
      '龙火火',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 8 岁男童 · 顽皮少年音。',
    ),
    OfflineSpeechOption(
      'longchuanshu_v3.6',
      '龙川叔',
      language: '普通话、英语',
      description: 'Qwen-Audio Flash · 40 岁男声 · 川普大叔音。',
    ),
    OfflineSpeechOption(
      'loongmary',
      'Mary',
      language: '英语',
      description: 'Qwen-Audio Flash · 20 岁女声 · 温暖英音。',
    ),
    OfflineSpeechOption(
      'loongeva_v3.6',
      'Eva',
      language: '英语',
      description: 'Qwen-Audio Flash · 28 岁女声 · 高智感美音。',
    ),
    OfflineSpeechOption(
      'loongjohn',
      'John',
      language: '英语',
      description: 'Qwen-Audio Flash · 28 岁男声 · 沉稳亲切美音。',
    ),
    OfflineSpeechOption(
      'longanyang',
      '龙安洋',
      language: '普通话、英语',
      description: 'CosyVoice V3 · 阳光大男孩，支持 SSML、指令与时间戳。',
    ),
    OfflineSpeechOption(
      'longanhuan_v3',
      '龙安欢（V3）',
      language: '普通话、九种方言、英语',
      description: 'CosyVoice V3 Flash · 欢脱元气女，支持方言指令。',
    ),
    OfflineSpeechOption(
      'longanhuan',
      '龙安欢',
      language: '普通话、英语',
      description: 'CosyVoice V3 · 欢脱元气女，支持情感与场景指令。',
    ),
    OfflineSpeechOption(
      'longhuhu_v3',
      '龙呼呼',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 天真烂漫女童。',
    ),
    OfflineSpeechOption(
      'longyingxiao_v3',
      '龙应笑',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 清甜推销女声，适合电话销售。',
    ),
    OfflineSpeechOption(
      'longyingxun_v3',
      '龙应询',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 年轻青涩男声，适合客服。',
    ),
    OfflineSpeechOption(
      'longyingjing_v3',
      '龙应静',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 低调冷静女声，适合客服。',
    ),
    OfflineSpeechOption(
      'longxiaochun_v3',
      '龙小淳',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 知性积极女声，适合语音助手。',
    ),
    OfflineSpeechOption(
      'longxiaoxia_v3',
      '龙小夏',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 沉稳权威女声，适合语音助手。',
    ),
    OfflineSpeechOption(
      'longanyun_v3',
      '龙安昀',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 居家暖男。',
    ),
    OfflineSpeechOption(
      'longanwen_v3',
      '龙安温',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 优雅知性女声。',
    ),
    OfflineSpeechOption(
      'longanli_v3',
      '龙安莉',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 利落从容女声。',
    ),
    OfflineSpeechOption(
      'longanlang_v3',
      '龙安朗',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 清爽利落男声。',
    ),
    OfflineSpeechOption(
      'longantai_v3',
      '龙安台',
      language: '普通话、英语',
      description: 'CosyVoice V3 Flash · 嗲甜台湾女声。',
    ),
    OfflineSpeechOption(
      'longanyue',
      '龙安粤',
      language: '粤语、英语',
      description: 'CosyVoice V2 · 欢脱粤语男声。',
    ),
    OfflineSpeechOption(
      'longshange',
      '龙陕哥',
      language: '陕西话、英语',
      description: 'CosyVoice V2 · 原味陕北男声。',
    ),
    OfflineSpeechOption(
      'longanmin',
      '龙安敏',
      language: '闽南话、英语',
      description: 'CosyVoice V2 · 甜美闽南女声。',
    ),
    OfflineSpeechOption(
      'longdaiyu',
      '龙黛玉',
      language: '普通话、英语',
      description: 'CosyVoice V2 · 娇率才女音，适合角色配音。',
    ),
    OfflineSpeechOption(
      'longgaoseng',
      '龙高僧',
      language: '普通话、英语',
      description: 'CosyVoice V2 · 得道高僧音，适合角色配音。',
    ),
  ];
  static const _qwenTtsLanguages = '普通话、英、法、德、俄、意、西、葡、日、韩';
  static const _bailianRealtimeTtsVoices = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'Cherry',
      '芊悦',
      language: _qwenTtsLanguages,
      description: '女声 · 阳光积极、亲切自然。',
    ),
    OfflineSpeechOption(
      'Serena',
      '苏瑶',
      language: _qwenTtsLanguages,
      description: '女声 · 温柔自然。',
    ),
    OfflineSpeechOption(
      'Ethan',
      '晨煦',
      language: _qwenTtsLanguages,
      description: '男声 · 标准普通话略带北方口音，阳光温暖。',
    ),
    OfflineSpeechOption(
      'Chelsie',
      '千雪',
      language: _qwenTtsLanguages,
      description: '女声 · 二次元虚拟女友风格。',
    ),
    OfflineSpeechOption(
      'Momo',
      '茉兔',
      language: _qwenTtsLanguages,
      description: '女声 · 撒娇搞怪、轻快活泼。',
    ),
    OfflineSpeechOption(
      'Vivian',
      '十三',
      language: _qwenTtsLanguages,
      description: '女声 · 率真可爱，略带小暴躁。',
    ),
    OfflineSpeechOption(
      'Moon',
      '月白',
      language: _qwenTtsLanguages,
      description: '男声 · 率性帅气。',
    ),
    OfflineSpeechOption(
      'Maia',
      '四月',
      language: _qwenTtsLanguages,
      description: '女声 · 知性温柔。',
    ),
    OfflineSpeechOption(
      'Kai',
      '凯',
      language: _qwenTtsLanguages,
      description: '男声 · 舒缓、有沉浸感。',
    ),
    OfflineSpeechOption(
      'Nofish',
      '不吃鱼',
      language: _qwenTtsLanguages,
      description: '男声 · 自然口语化、不翘舌。',
    ),
    OfflineSpeechOption(
      'Bella',
      '萌宝',
      language: _qwenTtsLanguages,
      description: '女声 · 活泼小萝莉。',
    ),
    OfflineSpeechOption(
      'Jennifer',
      '詹妮弗',
      language: _qwenTtsLanguages,
      description: '女声 · 品牌级电影质感美语。',
    ),
    OfflineSpeechOption(
      'Ryan',
      '甜茶',
      language: _qwenTtsLanguages,
      description: '男声 · 节奏鲜明、富有戏剧张力。',
    ),
    OfflineSpeechOption(
      'Katerina',
      '卡捷琳娜',
      language: _qwenTtsLanguages,
      description: '女声 · 成熟御姐、韵律感强。',
    ),
    OfflineSpeechOption(
      'Aiden',
      '艾登',
      language: _qwenTtsLanguages,
      description: '男声 · 亲切的美语青年。',
    ),
    OfflineSpeechOption(
      'Eldric Sage',
      '沧明子',
      language: _qwenTtsLanguages,
      description: '男声 · 沉稳睿智的老者。',
    ),
    OfflineSpeechOption(
      'Mia',
      '乖小妹',
      language: _qwenTtsLanguages,
      description: '女声 · 温顺乖巧。',
    ),
    OfflineSpeechOption(
      'Mochi',
      '沙小弥',
      language: _qwenTtsLanguages,
      description: '男童 · 聪明伶俐、童真早慧。',
    ),
    OfflineSpeechOption(
      'Bellona',
      '燕铮莺',
      language: _qwenTtsLanguages,
      description: '女声 · 洪亮清晰，适合热血叙事。',
    ),
    OfflineSpeechOption(
      'Vincent',
      '田叔',
      language: _qwenTtsLanguages,
      description: '男声 · 沙哑烟嗓、江湖豪情。',
    ),
    OfflineSpeechOption(
      'Bunny',
      '萌小姬',
      language: _qwenTtsLanguages,
      description: '女声 · 萌系小萝莉。',
    ),
    OfflineSpeechOption(
      'Neil',
      '阿闻',
      language: _qwenTtsLanguages,
      description: '男声 · 字正腔圆，专业新闻主持。',
    ),
    OfflineSpeechOption(
      'Elias',
      '墨讲师',
      language: _qwenTtsLanguages,
      description: '女声 · 严谨清晰，适合知识讲解。',
    ),
    OfflineSpeechOption(
      'Arthur',
      '徐大爷',
      language: _qwenTtsLanguages,
      description: '男声 · 质朴沧桑，适合故事叙述。',
    ),
    OfflineSpeechOption(
      'Nini',
      '邻家妹妹',
      language: _qwenTtsLanguages,
      description: '女声 · 软糯甜美。',
    ),
    OfflineSpeechOption(
      'Seren',
      '小婉',
      language: _qwenTtsLanguages,
      description: '女声 · 温和舒缓，适合助眠。',
    ),
    OfflineSpeechOption(
      'Pip',
      '顽屁小孩',
      language: _qwenTtsLanguages,
      description: '男童 · 调皮捣蛋、童真活泼。',
    ),
    OfflineSpeechOption(
      'Stella',
      '少女阿月',
      language: _qwenTtsLanguages,
      description: '女声 · 甜美迷糊、富有角色感。',
    ),
    OfflineSpeechOption(
      'Bodega',
      '博德加',
      language: _qwenTtsLanguages,
      description: '男声 · 热情的西班牙大叔。',
    ),
    OfflineSpeechOption(
      'Sonrisa',
      '索尼莎',
      language: _qwenTtsLanguages,
      description: '女声 · 热情开朗的拉美女声。',
    ),
    OfflineSpeechOption(
      'Alek',
      '阿列克',
      language: _qwenTtsLanguages,
      description: '男声 · 冷峻中带温暖的俄语气质。',
    ),
    OfflineSpeechOption(
      'Dolce',
      '多尔切',
      language: _qwenTtsLanguages,
      description: '男声 · 慵懒的意大利大叔。',
    ),
    OfflineSpeechOption(
      'Sohee',
      '素熙',
      language: _qwenTtsLanguages,
      description: '女声 · 温柔开朗、情绪丰富。',
    ),
    OfflineSpeechOption(
      'Ono Anna',
      '小野杏',
      language: _qwenTtsLanguages,
      description: '女声 · 鬼灵精怪的日系少女。',
    ),
    OfflineSpeechOption(
      'Lenn',
      '莱恩',
      language: _qwenTtsLanguages,
      description: '男声 · 理性叛逆的德国青年。',
    ),
    OfflineSpeechOption(
      'Emilien',
      '埃米尔安',
      language: _qwenTtsLanguages,
      description: '男声 · 浪漫的法国青年。',
    ),
    OfflineSpeechOption(
      'Andre',
      '安德雷',
      language: _qwenTtsLanguages,
      description: '男声 · 磁性自然、沉稳舒服。',
    ),
    OfflineSpeechOption(
      'Radio Gol',
      '拉迪奥·戈尔',
      language: _qwenTtsLanguages,
      description: '男声 · 热烈足球解说。',
    ),
    OfflineSpeechOption(
      'Jada',
      '上海－阿珍',
      language: '上海话及九种外语',
      description: '女声 · 风风火火的沪上阿姐。',
    ),
    OfflineSpeechOption(
      'Dylan',
      '北京－晓东',
      language: '北京话及九种外语',
      description: '男声 · 胡同少年风格。',
    ),
    OfflineSpeechOption(
      'Li',
      '南京－老李',
      language: '南京话及九种外语',
      description: '男声 · 耐心沉稳。',
    ),
    OfflineSpeechOption(
      'Marcus',
      '陕西－秦川',
      language: '陕西话及九种外语',
      description: '男声 · 质朴沉稳的老陕风格。',
    ),
    OfflineSpeechOption(
      'Roy',
      '闽南－阿杰',
      language: '闽南语及九种外语',
      description: '男声 · 诙谐直爽、市井活泼。',
    ),
    OfflineSpeechOption(
      'Peter',
      '天津－李彼得',
      language: '天津话及九种外语',
      description: '男声 · 天津相声、专业捧哏。',
    ),
    OfflineSpeechOption(
      'Sunny',
      '四川－晴儿',
      language: '四川话及九种外语',
      description: '女声 · 甜美川妹子。',
    ),
    OfflineSpeechOption(
      'Eric',
      '四川－程川',
      language: '四川话及九种外语',
      description: '男声 · 跳脱市井的成都风格。',
    ),
    OfflineSpeechOption(
      'Rocky',
      '粤语－阿强',
      language: '粤语及九种外语',
      description: '男声 · 幽默风趣、适合陪聊。',
    ),
    OfflineSpeechOption(
      'Kiki',
      '粤语－阿清',
      language: '粤语及九种外语',
      description: '女声 · 甜美港妹闺蜜。',
    ),
  ];
  static const _sambertVoices = <OfflineSpeechOption>[
    OfflineSpeechOption(
      'sambert-zhinan-v1',
      '知楠',
      language: '中文、英语',
      description: '48 kHz · 广告男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiqi-v1',
      '知琪',
      language: '中文、英语',
      description: '48 kHz · 温柔女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhichu-v1',
      '知厨',
      language: '中文、英语',
      description: '48 kHz · 舌尖男声 · 新闻播报。',
    ),
    OfflineSpeechOption(
      'sambert-zhide-v1',
      '知德',
      language: '中文、英语',
      description: '48 kHz · 新闻男声。',
    ),
    OfflineSpeechOption(
      'sambert-zhijia-v1',
      '知佳',
      language: '中文、英语',
      description: '48 kHz · 标准女声 · 新闻播报。',
    ),
    OfflineSpeechOption(
      'sambert-zhiru-v1',
      '知茹',
      language: '中文、英语',
      description: '48 kHz · 新闻女声。',
    ),
    OfflineSpeechOption(
      'sambert-zhiqian-v1',
      '知倩',
      language: '中文、英语',
      description: '48 kHz · 资讯女声 · 配音及新闻。',
    ),
    OfflineSpeechOption(
      'sambert-zhixiang-v1',
      '知祥',
      language: '中文、英语',
      description: '48 kHz · 磁性男声 · 配音解说。',
    ),
    OfflineSpeechOption(
      'sambert-zhiwei-v1',
      '知薇',
      language: '中文、英语',
      description: '48 kHz · 萝莉女声 · 产品介绍。',
    ),
    OfflineSpeechOption(
      'sambert-zhihao-v1',
      '知浩',
      language: '中文、英语',
      description: '16 kHz · 咨询男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhijing-v1',
      '知婧',
      language: '中文、英语',
      description: '16 kHz · 严厉女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiming-v1',
      '知茗',
      language: '中文、英语',
      description: '16 kHz · 诙谐男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhimo-v1',
      '知墨',
      language: '中文、英语',
      description: '16 kHz · 情感男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhina-v1',
      '知娜',
      language: '中文、英语',
      description: '16 kHz · 浙普女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhishu-v1',
      '知树',
      language: '中文、英语',
      description: '16 kHz · 资讯男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhistella-v1',
      '知莎',
      language: '中文、英语',
      description: '16 kHz · 知性女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiting-v1',
      '知婷',
      language: '中文、英语',
      description: '16 kHz · 电台女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhixiao-v1',
      '知笑',
      language: '中文、英语',
      description: '16 kHz · 资讯女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiya-v1',
      '知雅',
      language: '中文、英语',
      description: '16 kHz · 严厉女声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiye-v1',
      '知晔',
      language: '中文、英语',
      description: '16 kHz · 青年男声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiying-v1',
      '知颖',
      language: '中文、英语',
      description: '16 kHz · 软萌童声 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiyuan-v1',
      '知媛',
      language: '中文、英语',
      description: '16 kHz · 知心姐姐 · 通用场景。',
    ),
    OfflineSpeechOption(
      'sambert-zhiyue-v1',
      '知悦',
      language: '中文、英语',
      description: '16 kHz · 温柔女声 · 客服。',
    ),
    OfflineSpeechOption(
      'sambert-zhigui-v1',
      '知柜',
      language: '中文、英语',
      description: '16 kHz · 直播女声 · 产品介绍。',
    ),
    OfflineSpeechOption(
      'sambert-zhishuo-v1',
      '知硕',
      language: '中文、英语',
      description: '16 kHz · 自然男声 · 数字人。',
    ),
    OfflineSpeechOption(
      'sambert-zhimiao-emo-v1',
      '知妙（多情感）',
      language: '中文、英语',
      description: '16 kHz · 多情感女声 · 数字人及直播。',
    ),
    OfflineSpeechOption(
      'sambert-zhimao-v1',
      '知猫',
      language: '中文、英语',
      description: '16 kHz · 直播女声 · 配音及数字人。',
    ),
    OfflineSpeechOption(
      'sambert-zhilun-v1',
      '知伦',
      language: '中文、英语',
      description: '16 kHz · 悬疑解说男声。',
    ),
    OfflineSpeechOption(
      'sambert-zhifei-v1',
      '知飞',
      language: '中文、英语',
      description: '16 kHz · 激昂解说男声。',
    ),
    OfflineSpeechOption(
      'sambert-zhida-v1',
      '知达',
      language: '中文、英语',
      description: '16 kHz · 标准男声 · 新闻播报。',
    ),
    OfflineSpeechOption(
      'sambert-camila-v1',
      'Camila',
      language: '西班牙语',
      description: '16 kHz · 西班牙语女声。',
    ),
    OfflineSpeechOption(
      'sambert-perla-v1',
      'Perla',
      language: '意大利语',
      description: '16 kHz · 意大利语女声。',
    ),
    OfflineSpeechOption(
      'sambert-indah-v1',
      'Indah',
      language: '印尼语',
      description: '16 kHz · 印尼语女声。',
    ),
    OfflineSpeechOption(
      'sambert-clara-v1',
      'Clara',
      language: '法语',
      description: '16 kHz · 法语女声。',
    ),
    OfflineSpeechOption(
      'sambert-hanna-v1',
      'Hanna',
      language: '德语',
      description: '16 kHz · 德语女声。',
    ),
    OfflineSpeechOption(
      'sambert-beth-v1',
      'Beth',
      language: '美式英语',
      description: '16 kHz · 咨询女声。',
    ),
    OfflineSpeechOption(
      'sambert-betty-v1',
      'Betty',
      language: '美式英语',
      description: '16 kHz · 客服女声。',
    ),
    OfflineSpeechOption(
      'sambert-cally-v1',
      'Cally',
      language: '美式英语',
      description: '16 kHz · 自然女声。',
    ),
    OfflineSpeechOption(
      'sambert-cindy-v1',
      'Cindy',
      language: '美式英语',
      description: '16 kHz · 对话女声。',
    ),
    OfflineSpeechOption(
      'sambert-eva-v1',
      'Eva',
      language: '美式英语',
      description: '16 kHz · 陪伴女声。',
    ),
    OfflineSpeechOption(
      'sambert-donna-v1',
      'Donna',
      language: '美式英语',
      description: '16 kHz · 教育女声。',
    ),
    OfflineSpeechOption(
      'sambert-brian-v1',
      'Brian',
      language: '美式英语',
      description: '16 kHz · 客服男声。',
    ),
    OfflineSpeechOption(
      'sambert-waan-v1',
      'Waan',
      language: '泰语',
      description: '16 kHz · 泰语女声。',
    ),
  ];
  static const _speechInstructionPresets = <OfflineSpeechOption>[
    OfflineSpeechOption(
      '',
      '不使用指令',
      language: '自动',
      description: '保留音色的默认表达方式。',
    ),
    OfflineSpeechOption(
      '你说话的情感是neutral。',
      '自然中性',
      language: 'CosyVoice 指令',
      description: '稳定、克制的默认情感。',
    ),
    OfflineSpeechOption(
      '你说话的情感是happy。',
      '开心',
      language: 'CosyVoice 指令',
      description: '明亮愉悦，适合欢迎语与轻松内容。',
    ),
    OfflineSpeechOption(
      '你说话的情感是sad。',
      '悲伤',
      language: 'CosyVoice 指令',
      description: '低沉克制，适合情绪化叙事。',
    ),
    OfflineSpeechOption(
      '你说话的情感是angry。',
      '愤怒',
      language: 'CosyVoice 指令',
      description: '强烈有力，适合戏剧化表达。',
    ),
    OfflineSpeechOption(
      '你正在进行新闻播报，你说话的情感是neutral。',
      '新闻播报',
      language: 'CosyVoice 指令',
      description: '清晰、严谨、节奏稳定。',
    ),
    OfflineSpeechOption(
      '你正在进行语音导航，你说话的情感是neutral。',
      '语音导航',
      language: 'CosyVoice 指令',
      description: '简洁清楚，适合短句提示。',
    ),
    OfflineSpeechOption(
      '请用山东话表达。',
      '山东话',
      language: '方言指令',
      description: '适用于支持方言指令的 CosyVoice 音色。',
    ),
    OfflineSpeechOption(
      '自然清晰，语速适中。',
      '自然清晰',
      language: '通用指令',
      description: '平衡自然度、清晰度与节奏。',
    ),
    OfflineSpeechOption(
      '语气温暖亲切，表达自然，语速稍慢。',
      '温暖亲切',
      language: '通用指令',
      description: '适合陪伴、客服和长文本朗读。',
    ),
  ];
  static const _voiceDescriptionPresets = <OfflineSpeechOption>[
    OfflineSpeechOption(
      '温暖自然的青年女声，吐字清晰。',
      '温暖青年女声',
      language: '普通话',
      description: '自然亲切，适合助手与通用朗读。',
    ),
    OfflineSpeechOption(
      '沉稳磁性的青年男声，语速适中，吐字清晰。',
      '沉稳青年男声',
      language: '普通话',
      description: '稳重可靠，适合新闻和知识讲解。',
    ),
    OfflineSpeechOption(
      '活泼甜美的少女声线，情绪明亮，节奏轻快。',
      '活泼少女声',
      language: '普通话',
      description: '适合陪伴、短视频与轻松内容。',
    ),
    OfflineSpeechOption(
      '温柔知性的成年女声，语调舒缓，富有亲和力。',
      '知性成年女声',
      language: '普通话',
      description: '适合客服、助眠与长文本。',
    ),
    OfflineSpeechOption(
      '成熟沧桑的中年男声，低沉有力，叙事感强。',
      '沧桑中年男声',
      language: '普通话',
      description: '适合故事、纪录片与角色配音。',
    ),
    OfflineSpeechOption(
      '清爽自然的美式英语女声，节奏舒展，发音清晰。',
      '美式英语女声',
      language: '英语',
      description: '适合英文助手与品牌旁白。',
    ),
  ];
  static const _bailianTaskAsrParameters = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'format',
      label: '输入音频格式',
      description: '官方全部格式；OpenHand 麦克风实时输入需选 PCM。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'pcm',
      options: _bailianAudioFormats,
    ),
    OfflineSpeechParameter(
      key: 'sample_rate',
      label: '输入采样率',
      description: '8k 模型固定 8000 Hz，其他模型支持原始采样率。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 16000,
      min: 8000,
      max: 48000,
    ),
    OfflineSpeechParameter(
      key: 'vocabulary_id',
      label: '预编译热词 ID',
      description: '可选；填写已在百炼创建的热词表 ID。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'vocabulary',
      label: '即时热词',
      description: 'JSON 对象，权重为 1–5 或 50；仅 Qwen-Audio 模型支持。',
      type: OfflineSpeechParameterType.json,
      defaultValue: '{}',
    ),
    OfflineSpeechParameter(
      key: 'language_hints',
      label: '语种提示',
      description: '逗号分隔语言代码；Qwen-Audio 最多 4 个，Fun-ASR 只使用第 1 个。',
      type: OfflineSpeechParameterType.multiChoice,
      defaultValue: '',
      options: _bailianAsrLanguages,
    ),
    OfflineSpeechParameter(
      key: 'semantic_punctuation_enabled',
      label: '语义断句',
      description: '根据语义输出更自然的断句与标点；Paraformer 仅 V2 支持。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'max_sentence_silence',
      label: '最大句间静音',
      description: 'VAD 断句静音时长，200–6000 ms；Paraformer 仅 V2 支持。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 1300,
      min: 200,
      max: 6000,
    ),
    OfflineSpeechParameter(
      key: 'multi_threshold_mode_enabled',
      label: '多阈值断句',
      description: '在缩短延迟的同时减少误切句；Paraformer 仅 V2 支持。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'heartbeat',
      label: '心跳模式',
      description: '保持长时间无音频输入的任务连接；Paraformer 仅 V2 支持。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'speech_noise_threshold',
      label: '语音噪声阈值',
      description: 'Qwen-Audio/Fun-ASR 专用；范围 -1–1，越大越倾向判定为噪声。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 0.0,
      min: -1,
      max: 1,
    ),
    OfflineSpeechParameter(
      key: 'special_word_filter',
      label: '特殊词过滤',
      description: 'Qwen-Audio/Fun-ASR 专用；填写官方 JSON 对象，空对象不启用。',
      type: OfflineSpeechParameterType.json,
      defaultValue: '{}',
    ),
    OfflineSpeechParameter(
      key: 'context',
      label: '对话上下文',
      description: 'JSON 数组；每类角色最多 5 条、文本合计最多 400 字。',
      type: OfflineSpeechParameterType.json,
      defaultValue: '[]',
    ),
  ];
  static const _bailianTaskTtsParameters = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'voice',
      label: '合成音色',
      description: '搜索官方系统音色，或直接填写基础、复刻及专属音色 ID；音色必须与模型匹配。',
      type: OfflineSpeechParameterType.text,
      defaultValue: 'longanhuan_v3.6',
      options: _bailianTaskTtsVoices,
    ),
    OfflineSpeechParameter(
      key: 'format',
      label: '输出音频格式',
      description: 'PCM 可直接流式播放；CosyVoice V1 不支持 Opus。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'pcm',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('pcm', 'PCM · 低延迟推荐'),
        OfflineSpeechOption('wav', 'WAV'),
        OfflineSpeechOption('mp3', 'MP3 · 官方默认'),
        OfflineSpeechOption('opus', 'Opus'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'sample_rate',
      label: '输出采样率',
      description: '官方支持 8、16、22.05、24、44.1 与 48 kHz，默认 22.05 kHz。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: '22050',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('8000', '8 kHz'),
        OfflineSpeechOption('16000', '16 kHz'),
        OfflineSpeechOption('22050', '22.05 kHz · 默认'),
        OfflineSpeechOption('24000', '24 kHz'),
        OfflineSpeechOption('44100', '44.1 kHz'),
        OfflineSpeechOption('48000', '48 kHz'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'volume',
      label: '音量',
      description: '范围 0–100，默认 50。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 50,
      min: 0,
      max: 100,
    ),
    OfflineSpeechParameter(
      key: 'rate',
      label: '语速',
      description: '范围 0.5–2.0，默认 1.0。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'pitch',
      label: '音调',
      description: '范围 0.5–2.0，默认 1.0。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'bit_rate',
      label: '音频码率',
      description: 'MP3/Opus 时生效，范围 6–510 kbps，默认 32；V1 不支持。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 32,
      min: 6,
      max: 510,
    ),
    OfflineSpeechParameter(
      key: 'enable_ssml',
      label: 'SSML',
      description: '开启后文本按 SSML 解析，单任务仅允许一次文本提交。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'word_timestamp_enabled',
      label: '字级时间戳',
      description: '为支持的模型与音色返回字级时间戳。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'seed',
      label: '随机种子',
      description: '范围 0–65535，默认 0；CosyVoice V1 不支持。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 0,
      min: 0,
      max: 65535,
    ),
    OfflineSpeechParameter(
      key: 'language_hint',
      label: '目标语种',
      description: '官方当前仅处理第一个语种提示；留空自动。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: '',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('', '自动'),
        OfflineSpeechOption('zh', '中文'),
        OfflineSpeechOption('en', '英语'),
        OfflineSpeechOption('fr', '法语'),
        OfflineSpeechOption('de', '德语'),
        OfflineSpeechOption('ja', '日语'),
        OfflineSpeechOption('ko', '韩语'),
        OfflineSpeechOption('ru', '俄语'),
        OfflineSpeechOption('pt', '葡萄牙语'),
        OfflineSpeechOption('th', '泰语'),
        OfflineSpeechOption('id', '印尼语'),
        OfflineSpeechOption('vi', '越南语'),
        OfflineSpeechOption('es', '西班牙语'),
        OfflineSpeechOption('it', '意大利语'),
        OfflineSpeechOption('ms', '马来西亚语'),
        OfflineSpeechOption('fil', '菲律宾语'),
        OfflineSpeechOption('ar', '阿拉伯语'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'instruction',
      label: '合成指令',
      description: '用自然语言控制方言、情感或角色；按模型支持范围生效。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
      options: _speechInstructionPresets,
    ),
    OfflineSpeechParameter(
      key: 'enable_aigc_tag',
      label: 'AIGC 隐性标识',
      description: '为支持的 WAV、MP3 或 Opus 音频嵌入内容标识。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'aigc_propagator',
      label: 'AIGC 传播者',
      description: '开启隐性标识后可选，默认由服务端使用阿里云 UID。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'aigc_propagate_id',
      label: 'AIGC 传播 ID',
      description: '开启隐性标识后可选，默认由服务端使用请求 ID。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'hot_fix_pronunciation',
      label: '发音热修复',
      description: 'hot_fix.pronunciation JSON 数组；CosyVoice V1/V2 不支持。',
      type: OfflineSpeechParameterType.json,
      defaultValue: '[]',
    ),
    OfflineSpeechParameter(
      key: 'hot_fix_replace',
      label: '文本替换热修复',
      description: 'hot_fix.replace JSON 数组；CosyVoice V1/V2 不支持。',
      type: OfflineSpeechParameterType.json,
      defaultValue: '[]',
    ),
    OfflineSpeechParameter(
      key: 'enable_markdown_filter',
      label: 'Markdown 过滤',
      description: '仅 CosyVoice V3 Flash 专属音色支持。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
  ];
  static const _bailianRealtimeTtsParameters = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'voice',
      label: '合成音色',
      description: '搜索官方系统音色，或直接填写与 VC/VD 模型匹配的专属音色 ID。',
      type: OfflineSpeechParameterType.text,
      defaultValue: 'Cherry',
      options: _bailianRealtimeTtsVoices,
    ),
    OfflineSpeechParameter(
      key: 'mode',
      label: '文本提交模式',
      description: '服务端自动提交平衡质量与延迟；手动提交延迟最低。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'server_commit',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('server_commit', '服务端自动提交 · 默认'),
        OfflineSpeechOption('commit', '客户端手动提交'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'language_type',
      label: '合成语种',
      description: '单一语种时固定选项可提升发音准确性。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'Auto',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('Auto', '自动检测 · 默认'),
        OfflineSpeechOption('Chinese', '中文'),
        OfflineSpeechOption('English', '英语'),
        OfflineSpeechOption('German', '德语'),
        OfflineSpeechOption('Italian', '意大利语'),
        OfflineSpeechOption('Portuguese', '葡萄牙语'),
        OfflineSpeechOption('Spanish', '西班牙语'),
        OfflineSpeechOption('Japanese', '日语'),
        OfflineSpeechOption('Korean', '韩语'),
        OfflineSpeechOption('French', '法语'),
        OfflineSpeechOption('Russian', '俄语'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'response_format',
      label: '输出音频格式',
      description: 'PCM 可流式播放；旧版 Qwen-TTS Realtime 仅支持 PCM。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'pcm',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('pcm', 'PCM · 默认'),
        OfflineSpeechOption('wav', 'WAV'),
        OfflineSpeechOption('mp3', 'MP3'),
        OfflineSpeechOption('opus', 'Opus'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'sample_rate',
      label: '输出采样率',
      description: '旧版 Qwen-TTS Realtime 仅支持 24 kHz。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: '24000',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption('8000', '8 kHz'),
        OfflineSpeechOption('16000', '16 kHz'),
        OfflineSpeechOption('24000', '24 kHz · 默认'),
        OfflineSpeechOption('48000', '48 kHz'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'speech_rate',
      label: '语速',
      description: '范围 0.5–2.0；旧版 Qwen-TTS Realtime 不支持。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'volume',
      label: '音量',
      description: '范围 0–100，默认 50；旧版模型不支持。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 50,
      min: 0,
      max: 100,
    ),
    OfflineSpeechParameter(
      key: 'pitch_rate',
      label: '音调',
      description: '范围 0.5–2.0；旧版 Qwen-TTS Realtime 不支持。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'bit_rate',
      label: 'Opus 码率',
      description: '仅 Opus 生效，范围 6–510 kbps，默认 128。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 128,
      min: 6,
      max: 510,
    ),
    OfflineSpeechParameter(
      key: 'instructions',
      label: '表达指令',
      description: '仅 Qwen3-TTS Instruct Flash Realtime 支持，最多 1600 Token。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
      options: _speechInstructionPresets,
    ),
    OfflineSpeechParameter(
      key: 'optimize_instructions',
      label: '优化表达指令',
      description: '有指令时由服务端增强其自然度与表现力。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
  ];
  static const _asrCommon = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'language',
      label: '识别语言',
      description: '指定语言可减少误判。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'auto',
      options: _autoLanguage,
    ),
    OfflineSpeechParameter(
      key: 'hotwords',
      label: '热词',
      description: '用空格分隔专业词和专有名词。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'itn',
      label: '数字与符号规整',
      description: '把口语数字、日期和符号转换为书面形式。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: true,
    ),
    OfflineSpeechParameter(
      key: 'vad',
      label: '语音活动检测',
      description: '自动跳过静音并切分长音频。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: true,
    ),
    OfflineSpeechParameter(
      key: 'punctuation',
      label: '恢复标点',
      description: '为识别文本自动补充标点。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: true,
    ),
    OfflineSpeechParameter(
      key: 'speaker_diarization',
      label: '说话人分离',
      description: '区分录音中的不同说话人。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: false,
    ),
    OfflineSpeechParameter(
      key: 'device',
      label: '计算设备',
      description: '选择模型推理设备。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'auto',
      options: _device,
    ),
  ];
  static const _generation = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'temperature',
      label: '采样温度',
      description: '较低值更稳定，较高值更有变化。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 0.7,
      min: 0,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'top_p',
      label: 'Top P',
      description: '核采样概率阈值。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 0.8,
      min: 0.01,
      max: 1,
    ),
    OfflineSpeechParameter(
      key: 'top_k',
      label: 'Top K',
      description: '每步保留的候选数量。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 50,
      min: 1,
      max: 1000,
    ),
    OfflineSpeechParameter(
      key: 'repetition_penalty',
      label: '重复惩罚',
      description: '抑制异常重复输出。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.05,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'max_new_tokens',
      label: '最大输出 Token',
      description: '限制单次生成长度。',
      type: OfflineSpeechParameterType.integer,
      defaultValue: 2048,
      min: 64,
      max: 32768,
    ),
  ];
  static const _ttsCommon = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'language',
      label: '朗读语言',
      description: '自动或固定朗读语言。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'zh',
      options: _autoLanguage,
    ),
    OfflineSpeechParameter(
      key: 'speed',
      label: '语速',
      description: '朗读速度倍率。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'volume',
      label: '音量',
      description: '输出音量倍率。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'pitch',
      label: '音高',
      description: '输出音高倍率。',
      type: OfflineSpeechParameterType.decimal,
      defaultValue: 1.0,
      min: 0.5,
      max: 2,
    ),
    OfflineSpeechParameter(
      key: 'device',
      label: '计算设备',
      description: '选择模型推理设备。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'auto',
      options: _device,
    ),
    OfflineSpeechParameter(
      key: 'dtype',
      label: '计算精度',
      description: '降低精度可节省内存。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'auto',
      options: _dtype,
    ),
  ];

  static const models = <OfflineSpeechModelDefinition>[
    OfflineSpeechModelDefinition(
      id: 'xfyun-rtasr',
      name: '讯飞实时语音转写 · 标准版',
      kind: OfflineSpeechKind.recognition,
      repository: 'https://www.xfyun.cn/doc/asr/rtasr/API.html',
      sizeLabel: 'WSS',
      description: '云端实时中英文、方言和小语种转写，可选翻译、领域优化与角色分离。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.xfyunRtasr,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: '服务地址',
          description: '官方实时语音转写 WebSocket 地址。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://rtasr.xfyun.cn/v1/ws',
        ),
        OfflineSpeechParameter(
          key: 'appid',
          label: 'APPID',
          description: '讯飞开放平台应用 ID。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'api_key',
          label: 'APIKey',
          description: '实时语音转写服务的 APIKey，用于 HMAC-SHA1 签名。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'lang',
          label: '识别语种',
          description: '默认 cn；英语填 en，已开通的方言或小语种填写控制台显示的参数值。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'cn',
          options: _xfyunRecognitionLanguages,
        ),
        OfflineSpeechParameter(
          key: 'trans_type',
          label: '翻译类型',
          description: '开通翻译功能后可使用普通翻译。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'normal',
          options: <OfflineSpeechOption>[OfflineSpeechOption('normal', '普通翻译')],
        ),
        OfflineSpeechParameter(
          key: 'trans_strategy',
          label: '翻译策略',
          description: '策略 2 会返回中间过程，官方建议优先使用。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '2',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('1', 'VAD 结果直接翻译'),
            OfflineSpeechOption('2', '返回中间结果 · 推荐'),
            OfflineSpeechOption('3', '按结束性标点拆分'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'target_lang',
          label: '目标翻译语种',
          description: '留空关闭翻译；非中文语种之间会以中文为过渡语种。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: _xfyunTranslationLanguages,
        ),
        OfflineSpeechParameter(
          key: 'punc',
          label: '标点',
          description: '默认返回标点，也可过滤识别结果中的标点。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('', '返回标点 · 默认'),
            OfflineSpeechOption('0', '过滤标点'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'pd',
          label: '领域优化',
          description: '优化特定垂直领域的识别效果。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: _xfyunStandardDomains,
        ),
        OfflineSpeechParameter(
          key: 'vad_mdn',
          label: '收音场景',
          description: '远场为默认值，近场适合贴近麦克风说话。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '1',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('1', '远场 · 默认'),
            OfflineSpeechOption('2', '近场'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'role_type',
          label: '角色分离',
          description: '识别并区分不同说话人。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '关闭 · 默认'),
            OfflineSpeechOption('2', '开启'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'eng_lang_type',
          label: '中英文模式',
          description: '控制中文场景中的英文识别范围。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '1',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('1', '自动中英文 · 默认'),
            OfflineSpeechOption('2', '中文为主，允许少量英文'),
            OfflineSpeechOption('4', '纯中文'),
          ],
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'xfyun-rtasr-llm',
      name: '讯飞实时语音转写 · 大模型版',
      kind: OfflineSpeechKind.recognition,
      repository: 'https://www.xfyun.cn/doc/spark/asr_llm/rtasr_llm.html',
      sizeLabel: 'WSS',
      description: '云端大模型实时转写，支持中英与 202 种方言免切及 37 个语种免切识别。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.xfyunRtasrLlm,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: '服务地址',
          description: '官方实时语音转写大模型 WebSocket 地址。',
          type: OfflineSpeechParameterType.text,
          defaultValue:
              'wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1',
        ),
        OfflineSpeechParameter(
          key: 'app_id',
          label: 'App ID',
          description: '讯飞开放平台应用 ID。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'access_key_id',
          label: 'AccessKey ID',
          description: '实时语音转写大模型服务的应用 Key。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'access_key_secret',
          label: 'AccessKey Secret',
          description: '用于 HMAC-SHA1 签名的应用密钥。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'uuid',
          label: '用户标识',
          description: '可选业务用户标识；留空时每次请求自动生成 UUID。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'lang',
          label: '免切识别模式',
          description: '方言模式覆盖中英与 202 种方言；多语种模式覆盖 37 个语种。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'autodialect',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('autodialect', '中英＋202 种方言'),
            OfflineSpeechOption('autominor', '37 个语种'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'recognized_language',
          label: '目标语种',
          description: '仅多语种模式有效；可搜索并组合官方支持的 37 个语种。',
          type: OfflineSpeechParameterType.multiChoice,
          defaultValue: 'cn,en',
          options: _xfyunLlmLanguages,
        ),
        OfflineSpeechParameter(
          key: 'audio_encode',
          label: '音频编码',
          description: '语音沟通录音使用 PCM；Speex 与 Opus 适合已编码的外部音频流。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'pcm_s16le',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('pcm_s16le', 'PCM 16-bit'),
            OfflineSpeechOption('speex-7', 'Speex 7'),
            OfflineSpeechOption('speex-10', 'Speex 10'),
            OfflineSpeechOption('opus-wb', 'Opus 16k · 推荐'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'samplerate',
          label: '采样率',
          description: 'PCM 音频必须指定；语音沟通固定产生 16 kHz 音频。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '16000',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('16000', '16 kHz'),
            OfflineSpeechOption('8000', '8 kHz'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'role_type',
          label: '说话人分离',
          description: '盲分模式可与注册声纹配合使用。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '关闭 · 默认'),
            OfflineSpeechOption('2', '实时角色分离'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'feature_ids',
          label: '声纹 ID',
          description: '多个已注册声纹 ID 使用英文逗号分隔；需开启说话人分离。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'eng_spk_match',
          label: '仅匹配注册声纹',
          description: '开启后，角色信息全部来自已注册声纹库。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '关闭 · 默认'),
            OfflineSpeechOption('1', '开启'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'pd',
          label: '领域优化',
          description: '优化特定垂直领域的识别效果。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: _xfyunDomains,
        ),
        OfflineSpeechParameter(
          key: 'eng_punc',
          label: '标点',
          description: '默认返回标点，也可过滤识别结果中的标点。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('', '返回标点 · 默认'),
            OfflineSpeechOption('0', '过滤标点'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'eng_vad_mdn',
          label: '收音场景',
          description: '远场为默认值，近场适合贴近麦克风说话。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '1',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('1', '远场 · 默认'),
            OfflineSpeechOption('2', '近场'),
          ],
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-qwen-fun-asr',
      name: '阿里云百炼 · Qwen-Audio / Fun-ASR',
      kind: OfflineSpeechKind.recognition,
      repository:
          'https://help.aliyun.com/zh/model-studio/real-time-speech-recognition-user-guide',
      sizeLabel: 'AOQ / WSS',
      description: '低延迟云端流式识别，支持上下文、热词、语种提示与语义断句。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianTaskAsr,
      onlineTransports: <OnlineSpeechTransport>[
        OnlineSpeechTransport.aoq,
        OnlineSpeechTransport.webSocket,
      ],
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: '北京地域默认地址；新加坡请改为 dashscope-intl 域名。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
          options: _bailianInferenceEndpoints,
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '识别模型',
          description: '覆盖北京与新加坡地域官方实时模型及快照。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'qwen-audio-3.0-asr-flash-streaming',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              'qwen-audio-3.0-asr-flash-streaming',
              'Qwen-Audio 3.0 ASR Flash Streaming',
            ),
            OfflineSpeechOption('fun-asr-realtime', 'Fun-ASR Realtime 稳定版'),
            OfflineSpeechOption(
              'fun-asr-realtime-2026-02-28',
              'Fun-ASR Realtime · 2026-02-28',
            ),
            OfflineSpeechOption(
              'fun-asr-realtime-2025-11-07',
              'Fun-ASR Realtime · 2025-11-07',
            ),
            OfflineSpeechOption(
              'fun-asr-realtime-2025-09-15',
              'Fun-ASR Realtime · 2025-09-15',
            ),
            OfflineSpeechOption(
              'fun-asr-flash-8k-realtime',
              'Fun-ASR Flash 8k Realtime 稳定版',
            ),
            OfflineSpeechOption(
              'fun-asr-flash-8k-realtime-2026-01-28',
              'Fun-ASR Flash 8k · 2026-01-28',
            ),
          ],
        ),
        ..._bailianTaskAsrParameters,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-qwen3-asr-realtime',
      name: '阿里云百炼 · Qwen3-ASR Realtime',
      kind: OfflineSpeechKind.recognition,
      repository:
          'https://help.aliyun.com/zh/model-studio/qwen-asr-realtime-api',
      sizeLabel: 'WSS',
      description: '云端多语种实时识别，支持服务端 VAD 与客户端手动提交。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianRealtimeAsr,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: '北京地域默认地址；模型名由系统自动追加。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime',
          options: _bailianRealtimeEndpoints,
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '识别模型',
          description: '稳定版会随官方升级，快照版行为固定。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'qwen3-asr-flash-realtime',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              'qwen3-asr-flash-realtime',
              'Qwen3-ASR Flash 稳定版',
            ),
            OfflineSpeechOption(
              'qwen3-asr-flash-realtime-2026-02-10',
              'Qwen3-ASR Flash · 2026-02-10',
            ),
            OfflineSpeechOption(
              'qwen3-asr-flash-realtime-2025-10-27',
              'Qwen3-ASR Flash · 2025-10-27',
            ),
          ],
        ),
        OfflineSpeechParameter(
          key: 'input_audio_format',
          label: '输入音频格式',
          description: 'OpenHand 麦克风实时输入需选 PCM。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'pcm',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('pcm', 'PCM · 默认'),
            OfflineSpeechOption('opus', 'Ogg Opus'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'sample_rate',
          label: '输入采样率',
          description: '16 kHz 质量更好；8 kHz 适合电话线路。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '16000',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('16000', '16 kHz · 默认'),
            OfflineSpeechOption('8000', '8 kHz'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'language',
          label: '音频语种',
          description: '留空自动识别；固定语种可降低误判。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '',
          options: _bailianQwen3AsrLanguages,
        ),
        OfflineSpeechParameter(
          key: 'vad_enabled',
          label: '服务端 VAD',
          description: '开启时由服务端自动检测语音起止；关闭时手动提交。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'vad_threshold',
          label: 'VAD 阈值',
          description: '范围 -1–1，官方推荐 0.0，默认 0.2。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 0.2,
          min: -1,
          max: 1,
        ),
        OfflineSpeechParameter(
          key: 'silence_duration_ms',
          label: 'VAD 静音时长',
          description: '200–6000 ms，官方推荐 400 ms，默认 800 ms。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 800,
          min: 200,
          max: 6000,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-paraformer-realtime',
      name: '阿里云百炼 · Paraformer Realtime',
      kind: OfflineSpeechKind.recognition,
      repository:
          'https://help.aliyun.com/zh/model-studio/paraformer-real-time-speech-recognition-api-reference',
      sizeLabel: 'WSS',
      description: '北京地域低延迟中英日粤等语种识别，支持数字规整和语气词过滤。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianTaskAsr,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: 'Paraformer Realtime 官方 WebSocket 任务端点。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '识别模型',
          description: '8k 模型面向电话音频，其他模型默认 16 kHz。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'paraformer-realtime-v2',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              'paraformer-realtime-v2',
              'Paraformer Realtime V2',
            ),
            OfflineSpeechOption(
              'paraformer-realtime-v1',
              'Paraformer Realtime V1',
            ),
            OfflineSpeechOption(
              'paraformer-realtime-8k-v2',
              'Paraformer Realtime 8k V2',
            ),
            OfflineSpeechOption(
              'paraformer-realtime-8k-v1',
              'Paraformer Realtime 8k V1',
            ),
          ],
        ),
        ..._bailianTaskAsrParameters,
        OfflineSpeechParameter(
          key: 'disfluency_removal_enabled',
          label: '语气词过滤',
          description: '自动删除“嗯”“呃”等口语语气词。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
        OfflineSpeechParameter(
          key: 'punctuation_prediction_enabled',
          label: '标点预测',
          description: '为识别文本补充标点，默认开启。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'inverse_text_normalization_enabled',
          label: '数字与符号规整',
          description: '将口语数字、日期和符号转换为书面形式。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'sensevoice-small',
      name: 'SenseVoice Small',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.funAsr,
      repository: 'FunAudioLLM/SenseVoiceSmall',
      sizeLabel: '约 900 MB',
      description: '低延迟中英日韩及粤语识别，同时支持情绪和声音事件检测。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        OfflineSpeechParameter(
          key: 'emotion_detection',
          label: '情绪识别',
          description: '返回语音情绪标签。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'event_detection',
          label: '声音事件',
          description: '检测掌声、笑声、咳嗽等事件。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'batch_size',
          label: '批处理大小',
          description: '并行处理的音频片段数量。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 1,
          min: 1,
          max: 128,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'paraformer-zh-streaming',
      name: 'Paraformer 中文流式版',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.funAsr,
      repository: 'funasr/paraformer-zh-streaming',
      sizeLabel: '约 900 MB',
      description: '面向普通话和中英混说的低延迟流式识别。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        OfflineSpeechParameter(
          key: 'chunk_size',
          label: '分块大小',
          description: '流式推理分块配置，单位为帧。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '0,10,5',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              '0,10,5',
              '均衡',
              language: '600 ms',
              description: '官方常用配置，兼顾实时性与识别效果。',
            ),
            OfflineSpeechOption(
              '0,5,5',
              '低延迟',
              language: '300 ms',
              description: '更快输出中间结果，对设备性能要求更高。',
            ),
            OfflineSpeechOption(
              '0,20,5',
              '稳定优先',
              language: '1200 ms',
              description: '分块更大，适合更重视稳定性的场景。',
            ),
          ],
        ),
        OfflineSpeechParameter(
          key: 'encoder_lookback',
          label: '编码器回看块数',
          description: '增加上下文会提高延迟和内存占用。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 4,
          min: 0,
          max: 16,
        ),
        OfflineSpeechParameter(
          key: 'decoder_lookback',
          label: '解码器回看块数',
          description: '控制解码端历史上下文。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 1,
          min: 0,
          max: 8,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'zipformer-zh-en',
      name: 'Zipformer 中英流式版',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.sherpaOnnx,
      repository:
          'csukuangfj/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20',
      sizeLabel: '约 500 MB',
      description: '适合 Flutter、桌面和移动端的中英双语实时识别。',
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'decoding_method',
          label: '解码方法',
          description: '贪心速度快，束搜索准确率更高。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'greedy_search',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('greedy_search', '贪心搜索'),
            OfflineSpeechOption('modified_beam_search', '改进束搜索'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'max_active_paths',
          label: '最大活跃路径',
          description: '束搜索保留的候选路径数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 4,
          min: 1,
          max: 128,
        ),
        OfflineSpeechParameter(
          key: 'blank_penalty',
          label: '空白惩罚',
          description: '降低漏字时可适当提高。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 0.0,
          min: -5,
          max: 5,
        ),
        OfflineSpeechParameter(
          key: 'hotwords_file',
          label: '热词文件',
          description: '指定 sherpa-onnx 格式的本地热词文件路径。',
          type: OfflineSpeechParameterType.path,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'hotwords_score',
          label: '热词权重',
          description: '数值越大，热词越容易被识别。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 1.5,
          min: 0,
          max: 10,
        ),
        OfflineSpeechParameter(
          key: 'threads',
          label: '推理线程',
          description: 'CPU 推理线程数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 4,
          min: 1,
          max: 32,
        ),
        OfflineSpeechParameter(
          key: 'provider',
          label: '执行提供器',
          description: '选择 ONNX Runtime 执行后端。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'cpu',
          options: _provider,
        ),
      ],
    ),
    ..._qwenAsrModels,
    ..._funAsrModels,
    OfflineSpeechModelDefinition(
      id: 'whisper',
      name: 'Whisper',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.fasterWhisper,
      repository: 'Systran/faster-whisper-small',
      sizeLabel: '约 75 MB–3.1 GB',
      description: '成熟的多语言离线转写方案，支持 CPU／CUDA 量化推理。',
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'model',
          label: '模型尺寸',
          description: '尺寸越大通常越准确，也越占内存。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'small',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('tiny', 'Tiny'),
            OfflineSpeechOption('base', 'Base'),
            OfflineSpeechOption('small', 'Small'),
            OfflineSpeechOption('medium', 'Medium'),
            OfflineSpeechOption('large-v3-turbo', 'Large V3 Turbo'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'language',
          label: '识别语言',
          description: '自动检测或固定语言。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: _autoLanguage,
        ),
        OfflineSpeechParameter(
          key: 'translate',
          label: '翻译为英语',
          description: '识别后直接输出英文译文。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
        OfflineSpeechParameter(
          key: 'temperature',
          label: '温度',
          description: '解码采样温度。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 0.0,
          min: 0,
          max: 1,
        ),
        OfflineSpeechParameter(
          key: 'beam_size',
          label: '束宽',
          description: '束搜索候选数量。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 5,
          min: 1,
          max: 20,
        ),
        OfflineSpeechParameter(
          key: 'best_of',
          label: '候选数量',
          description: '采样时保留的候选数量。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 5,
          min: 1,
          max: 20,
        ),
        OfflineSpeechParameter(
          key: 'word_timestamps',
          label: '词级时间戳',
          description: '返回词级开始和结束时间。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'vad',
          label: '语音活动检测',
          description: '过滤静音区间。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'threads',
          label: '推理线程',
          description: 'CPU 推理线程数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 4,
          min: 1,
          max: 32,
        ),
        OfflineSpeechParameter(
          key: 'device',
          label: '计算设备',
          description: '自动选择 CUDA 或 CPU。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('auto', '自动'),
            OfflineSpeechOption('cpu', 'CPU'),
            OfflineSpeechOption('cuda', 'CUDA'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'compute_type',
          label: '计算精度',
          description: 'INT8 更省内存，FP16 适合 CUDA。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'default',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('default', '自动'),
            OfflineSpeechOption('int8', 'INT8'),
            OfflineSpeechOption('int8_float16', 'INT8 + FP16'),
            OfflineSpeechOption('float16', 'FP16'),
            OfflineSpeechOption('float32', 'FP32'),
          ],
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'xfyun-online-tts',
      name: '讯飞在线语音合成',
      kind: OfflineSpeechKind.synthesis,
      repository: 'https://www.xfyun.cn/doc/tts/online_tts/API.html',
      sizeLabel: 'WSS',
      description: '云端 WebSocket 流式语音合成，支持多语种、方言、语速、音量和音高控制。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.xfyunTts,
      synthesisTransport: OfflineSpeechSynthesisTransport.webSocket,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: '服务地址',
          description: '官方在线语音合成 WebSocket 地址。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://tts-api.xfyun.cn/v2/tts',
        ),
        OfflineSpeechParameter(
          key: 'auth_mode',
          label: '鉴权方式',
          description: '支持 API Password 或 APPID、APIKey、APISecret 签名。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'hmac',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('hmac', 'HMAC-SHA256 签名'),
            OfflineSpeechOption('api_password', 'API Password'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'app_id',
          label: 'APPID',
          description: '讯飞开放平台应用 ID；两种鉴权方式都需要。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'api_key',
          label: 'APIKey',
          description: 'HMAC-SHA256 签名鉴权所需。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'api_secret',
          label: 'APISecret',
          description: 'HMAC-SHA256 签名鉴权所需。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'api_password',
          label: 'API Password',
          description: 'API Password 鉴权所需，从在线语音合成控制台获取。',
          type: OfflineSpeechParameterType.secret,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'aue',
          label: '音频编码',
          description: 'PCM 可边生成边播放；其他编码通过 WebSocket 完整接收后播放。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'raw',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('raw', 'PCM · 低延迟推荐'),
            OfflineSpeechOption('lame', 'MP3'),
            OfflineSpeechOption('opus', 'Opus 8k'),
            OfflineSpeechOption('opus-wb', 'Opus 16k'),
            OfflineSpeechOption('speex-org-wb', '开源 Speex 16k'),
            OfflineSpeechOption('speex-org-nb', '开源 Speex 8k'),
            OfflineSpeechOption('speex', '讯飞 Speex 8k'),
            OfflineSpeechOption('speex-wb', '讯飞 Speex 16k'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'compression_level',
          label: 'Speex 压缩等级',
          description: '选择 Speex 时生效，取值 1–10，默认 7。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 7,
          min: 1,
          max: 10,
        ),
        OfflineSpeechParameter(
          key: 'sfl',
          label: 'MP3 流式返回',
          description: '选择 MP3 编码时开启，官方接口要求值为 1。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'auf',
          label: '采样率',
          description: '选择 8 kHz 或 16 kHz 合成音频。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'audio/L16;rate=16000',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('audio/L16;rate=16000', '16 kHz · 默认'),
            OfflineSpeechOption('audio/L16;rate=8000', '8 kHz'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'vcn',
          label: '发音人',
          description: '搜索常用发音人，或直接填写控制台已开通音色的参数值。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'x4_xiaoyan',
          options: _xfyunTtsVoices,
        ),
        OfflineSpeechParameter(
          key: 'speed',
          label: '语速',
          description: '取值 0–100，默认 50。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 50,
          min: 0,
          max: 100,
        ),
        OfflineSpeechParameter(
          key: 'volume',
          label: '音量',
          description: '取值 0–100，默认 50。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 50,
          min: 0,
          max: 100,
        ),
        OfflineSpeechParameter(
          key: 'pitch',
          label: '音高',
          description: '取值 0–100，默认 50。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 50,
          min: 0,
          max: 100,
        ),
        OfflineSpeechParameter(
          key: 'bgs',
          label: '背景音',
          description: '控制是否为合成音频添加背景音。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '无背景音 · 默认'),
            OfflineSpeechOption('1', '有背景音'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'tte',
          label: '文本编码',
          description: '小语种建议使用 UTF-8。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'UTF8',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('UTF8', 'UTF-8 · 推荐'),
            OfflineSpeechOption('GB2312', 'GB2312'),
            OfflineSpeechOption('GBK', 'GBK'),
            OfflineSpeechOption('BIG5', 'BIG5'),
            OfflineSpeechOption('UNICODE', 'Unicode UTF-16LE'),
            OfflineSpeechOption('GB18030', 'GB18030'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'reg',
          label: '英文发音方式',
          description: '控制无法确定的英文内容按单词还是字母朗读。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '自动，优先按单词 · 默认'),
            OfflineSpeechOption('1', '全部按字母'),
            OfflineSpeechOption('2', '自动，优先按字母'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'rdn',
          label: '数字发音方式',
          description: '控制数字按数值还是字符串朗读。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '0',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('0', '自动判断 · 默认'),
            OfflineSpeechOption('1', '完全数值'),
            OfflineSpeechOption('2', '完全字符串'),
            OfflineSpeechOption('3', '字符串优先'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'binary_output',
          label: '二进制音频帧',
          description: '使用 output_proto=binary 接收二进制音频帧。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-qwen-cosyvoice-tts',
      name: '阿里云百炼 · Qwen-Audio / CosyVoice',
      kind: OfflineSpeechKind.synthesis,
      repository:
          'https://help.aliyun.com/zh/model-studio/realtime-tts-user-guide',
      sizeLabel: 'AOQ / WSS',
      description: '云端双工流式合成，支持系统、复刻与设计音色及细粒度表达控制。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianTaskTts,
      onlineTransports: <OnlineSpeechTransport>[
        OnlineSpeechTransport.aoq,
        OnlineSpeechTransport.webSocket,
      ],
      synthesisTransport: OfflineSpeechSynthesisTransport.webSocket,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: '北京地域默认地址；新加坡请改为 dashscope-intl 域名。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
          options: _bailianInferenceEndpoints,
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '合成模型',
          description: '覆盖北京与新加坡地域 Qwen-Audio-TTS 和 CosyVoice 实时模型。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'qwen-audio-3.0-tts-flash',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              'qwen-audio-3.0-tts-plus',
              'Qwen-Audio 3.0 TTS Plus',
            ),
            OfflineSpeechOption(
              'qwen-audio-3.0-tts-flash',
              'Qwen-Audio 3.0 TTS Flash',
            ),
            OfflineSpeechOption(
              'cosyvoice-v3.5-plus',
              'CosyVoice V3.5 Plus · 北京',
            ),
            OfflineSpeechOption(
              'cosyvoice-v3.5-flash',
              'CosyVoice V3.5 Flash · 北京',
            ),
            OfflineSpeechOption('cosyvoice-v3-plus', 'CosyVoice V3 Plus'),
            OfflineSpeechOption('cosyvoice-v3-flash', 'CosyVoice V3 Flash'),
            OfflineSpeechOption('cosyvoice-v2', 'CosyVoice V2'),
            OfflineSpeechOption('cosyvoice-v1', 'CosyVoice V1'),
          ],
        ),
        ..._bailianTaskTtsParameters,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-qwen-tts-realtime',
      name: '阿里云百炼 · Qwen-TTS Realtime',
      kind: OfflineSpeechKind.synthesis,
      repository:
          'https://help.aliyun.com/zh/model-studio/qwen-tts-realtime-api-reference',
      sizeLabel: 'WSS',
      description: '低延迟云端流式合成，支持指令音色、声音复刻和声音设计系列。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianRealtimeTts,
      synthesisTransport: OfflineSpeechSynthesisTransport.webSocket,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: '北京地域默认地址；新加坡请改为 dashscope-intl 域名。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime',
          options: _bailianRealtimeEndpoints,
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '合成模型',
          description: '覆盖稳定版与官方公开快照，专属音色需与 VC/VD 系列匹配。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'qwen3-tts-flash-realtime',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption(
              'qwen3-tts-instruct-flash-realtime',
              'Qwen3-TTS Instruct Flash 稳定版',
            ),
            OfflineSpeechOption(
              'qwen3-tts-instruct-flash-realtime-2026-01-22',
              'Qwen3-TTS Instruct · 2026-01-22',
            ),
            OfflineSpeechOption(
              'qwen3-tts-vd-realtime-2026-01-15',
              'Qwen3-TTS VD · 2026-01-15',
            ),
            OfflineSpeechOption(
              'qwen3-tts-vd-realtime-2025-12-16',
              'Qwen3-TTS VD · 2025-12-16',
            ),
            OfflineSpeechOption(
              'qwen3-tts-vc-realtime-2026-01-15',
              'Qwen3-TTS VC · 2026-01-15',
            ),
            OfflineSpeechOption(
              'qwen3-tts-vc-realtime-2025-11-27',
              'Qwen3-TTS VC · 2025-11-27',
            ),
            OfflineSpeechOption(
              'qwen3-tts-flash-realtime',
              'Qwen3-TTS Flash 稳定版',
            ),
            OfflineSpeechOption(
              'qwen3-tts-flash-realtime-2025-11-27',
              'Qwen3-TTS Flash · 2025-11-27',
            ),
            OfflineSpeechOption(
              'qwen3-tts-flash-realtime-2025-09-18',
              'Qwen3-TTS Flash · 2025-09-18',
            ),
            OfflineSpeechOption('qwen-tts-realtime', 'Qwen-TTS Realtime 稳定版'),
            OfflineSpeechOption(
              'qwen-tts-realtime-latest',
              'Qwen-TTS Realtime Latest',
            ),
            OfflineSpeechOption(
              'qwen-tts-realtime-2025-07-15',
              'Qwen-TTS Realtime · 2025-07-15',
            ),
          ],
        ),
        ..._bailianRealtimeTtsParameters,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'bailian-sambert-tts',
      name: '阿里云百炼 · Sambert',
      kind: OfflineSpeechKind.synthesis,
      repository:
          'https://help.aliyun.com/zh/model-studio/sambert-websocket-api',
      sizeLabel: 'WSS',
      description: '北京地域云端流式合成，内置完整的中英与多语种音色阵容。',
      deployment: OfflineSpeechDeployment.online,
      onlineService: OnlineSpeechService.bailianSambertTts,
      synthesisTransport: OfflineSpeechSynthesisTransport.webSocket,
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'endpoint',
          label: 'WebSocket 服务地址',
          description: 'Sambert 官方 WebSocket 任务端点，仅北京地域。',
          type: OfflineSpeechParameterType.text,
          defaultValue: 'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
        ),
        ..._bailianCredentials,
        OfflineSpeechParameter(
          key: 'model',
          label: '音色模型',
          description: '百炼官方全部 Sambert V1 实时音色模型。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'sambert-zhinan-v1',
          options: _sambertVoices,
        ),
        OfflineSpeechParameter(
          key: 'format',
          label: '输出音频格式',
          description: 'PCM 可流式播放；官方默认 WAV。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'pcm',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('pcm', 'PCM · 低延迟推荐'),
            OfflineSpeechOption('wav', 'WAV · 官方默认'),
            OfflineSpeechOption('mp3', 'MP3'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'sample_rate',
          label: '输出采样率',
          description: '官方支持 8、16、22.05 与 24 kHz，默认 16 kHz。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: '16000',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('8000', '8 kHz'),
            OfflineSpeechOption('16000', '16 kHz · 默认'),
            OfflineSpeechOption('22050', '22.05 kHz'),
            OfflineSpeechOption('24000', '24 kHz'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'volume',
          label: '音量',
          description: '范围 0–100，默认 50。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 50,
          min: 0,
          max: 100,
        ),
        OfflineSpeechParameter(
          key: 'rate',
          label: '语速',
          description: '范围 0.5–2.0，默认 1.0。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 1.0,
          min: 0.5,
          max: 2,
        ),
        OfflineSpeechParameter(
          key: 'pitch',
          label: '音调',
          description: '范围 0.5–2.0，默认 1.0。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 1.0,
          min: 0.5,
          max: 2,
        ),
        OfflineSpeechParameter(
          key: 'word_timestamp_enabled',
          label: '字级时间戳',
          description: '返回字级别起止时间。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
        OfflineSpeechParameter(
          key: 'phoneme_timestamp_enabled',
          label: '音素级时间戳',
          description: '需同时开启字级时间戳。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'cosyvoice3-0.5b',
      name: 'Fun-CosyVoice 3 · 0.5B',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.cosyVoice,
      repository: 'FunAudioLLM/Fun-CosyVoice3-0.5B-2512',
      sizeLabel: '约 4 GB',
      description: '中文、方言和多语言自然语音，支持音色克隆与双向流式生成。',
      synthesisTransport: OfflineSpeechSynthesisTransport.webSocket,
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        OfflineSpeechParameter(
          key: 'reference_audio',
          label: '参考音频',
          description: '用于零样本音色克隆的音频路径。',
          type: OfflineSpeechParameterType.path,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'prompt_text',
          label: '参考文本',
          description: '参考音频对应的准确文本。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '',
        ),
        OfflineSpeechParameter(
          key: 'instruct',
          label: '风格指令',
          description: '控制方言、情绪、速度和表达方式。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '自然清晰，语速适中。',
          options: _speechInstructionPresets,
        ),
        OfflineSpeechParameter(
          key: 'text_frontend',
          label: '文本前端',
          description: '启用数字、符号和多音字规整。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
      ],
    ),
    ..._qwenTtsModels,
    OfflineSpeechModelDefinition(
      id: 'kokoro-82m',
      name: 'Kokoro · 82M',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.sherpaOnnx,
      repository: 'csukuangfj/kokoro-multi-lang-v1_1',
      sizeLabel: '约 190–400 MB',
      description: '轻量中英离线朗读，内置 103 种音色。',
      parameters: <OfflineSpeechParameter>[
        OfflineSpeechParameter(
          key: 'speaker_id',
          label: '音色编号',
          description: '0–1 美式女声，2 英式女声，3–57 中文女声，58–102 中文男声。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 3,
          min: 0,
          max: 102,
        ),
        OfflineSpeechParameter(
          key: 'quantization',
          label: '模型精度',
          description: '低精度模型更小、更快，FP32 保留完整精度。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'int8',
          options: <OfflineSpeechOption>[
            OfflineSpeechOption('int8', 'INT8 · 推荐'),
            OfflineSpeechOption('fp32', 'FP32'),
          ],
        ),
        OfflineSpeechParameter(
          key: 'speed',
          label: '语速',
          description: '朗读速度倍率。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 1.0,
          min: 0.5,
          max: 2,
        ),
        OfflineSpeechParameter(
          key: 'silence_scale',
          label: '停顿倍率',
          description: '调整标点处的停顿长度。',
          type: OfflineSpeechParameterType.decimal,
          defaultValue: 1.0,
          min: 0.2,
          max: 3,
        ),
        OfflineSpeechParameter(
          key: 'max_num_sentences',
          label: '单批句子数',
          description: '较小的值可降低长文本合成的内存占用。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 1,
          min: 1,
          max: 64,
        ),
        OfflineSpeechParameter(
          key: 'threads',
          label: '推理线程',
          description: 'CPU 推理线程数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 4,
          min: 1,
          max: 32,
        ),
        OfflineSpeechParameter(
          key: 'provider',
          label: '执行提供器',
          description: '选择 ONNX Runtime 执行后端。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'cpu',
          options: _provider,
        ),
      ],
    ),
  ];

  static const _qwenAsrModels = <OfflineSpeechModelDefinition>[
    OfflineSpeechModelDefinition(
      id: 'qwen3-asr-0.6b',
      name: 'Qwen3-ASR · 0.6B',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.qwenAsr,
      repository: 'Qwen/Qwen3-ASR-0.6B',
      sizeLabel: '约 1.8 GB',
      description: '兼顾准确率与资源占用的 52 语言及中文方言识别。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        ..._generation,
        OfflineSpeechParameter(
          key: 'streaming',
          label: '流式识别',
          description: '通过 vLLM 边说边输出。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'timestamps',
          label: '时间戳',
          description: '离线识别时调用强制对齐器。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
        OfflineSpeechParameter(
          key: 'dtype',
          label: '计算精度',
          description: '降低精度可节省显存。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: _dtype,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'qwen3-asr-1.7b',
      name: 'Qwen3-ASR · 1.7B',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.qwenAsr,
      repository: 'Qwen/Qwen3-ASR-1.7B',
      sizeLabel: '约 4.5 GB',
      description: '更高准确率的 52 语言、方言、歌曲和复杂声学环境识别。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        ..._generation,
        OfflineSpeechParameter(
          key: 'streaming',
          label: '流式识别',
          description: '通过 vLLM 边说边输出。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: true,
        ),
        OfflineSpeechParameter(
          key: 'timestamps',
          label: '时间戳',
          description: '离线识别时调用强制对齐器。',
          type: OfflineSpeechParameterType.toggle,
          defaultValue: false,
        ),
        OfflineSpeechParameter(
          key: 'dtype',
          label: '计算精度',
          description: '降低精度可节省显存。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: _dtype,
        ),
      ],
    ),
  ];

  static const _funAsrModels = <OfflineSpeechModelDefinition>[
    OfflineSpeechModelDefinition(
      id: 'fun-asr-nano',
      name: 'Fun-ASR Nano',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.funAsr,
      repository: 'FunAudioLLM/Fun-ASR-Nano-2512',
      sizeLabel: '约 2.5 GB',
      description: '针对中文、方言、口音、远场和噪声环境优化。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        ..._generation,
        OfflineSpeechParameter(
          key: 'chunk_ms',
          label: '流式分块',
          description: '每次送入模型的音频毫秒数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 720,
          min: 160,
          max: 5000,
        ),
        OfflineSpeechParameter(
          key: 'batch_size_s',
          label: '批处理音频秒数',
          description: '长音频批处理窗口。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 60,
          min: 1,
          max: 600,
        ),
        OfflineSpeechParameter(
          key: 'dtype',
          label: '计算精度',
          description: '降低精度可节省显存。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: _dtype,
        ),
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'fun-asr-mlt-nano',
      name: 'Fun-ASR MLT Nano',
      kind: OfflineSpeechKind.recognition,
      runtime: OfflineSpeechRuntime.funAsr,
      repository: 'FunAudioLLM/Fun-ASR-MLT-Nano-2512',
      sizeLabel: '约 2.5 GB',
      description: '覆盖 31 种语言的多语言版本。',
      parameters: <OfflineSpeechParameter>[
        ..._asrCommon,
        ..._generation,
        OfflineSpeechParameter(
          key: 'chunk_ms',
          label: '流式分块',
          description: '每次送入模型的音频毫秒数。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 720,
          min: 160,
          max: 5000,
        ),
        OfflineSpeechParameter(
          key: 'batch_size_s',
          label: '批处理音频秒数',
          description: '长音频批处理窗口。',
          type: OfflineSpeechParameterType.integer,
          defaultValue: 60,
          min: 1,
          max: 600,
        ),
        OfflineSpeechParameter(
          key: 'dtype',
          label: '计算精度',
          description: '降低精度可节省显存。',
          type: OfflineSpeechParameterType.choice,
          defaultValue: 'auto',
          options: _dtype,
        ),
      ],
    ),
  ];

  static const _qwenTtsModels = <OfflineSpeechModelDefinition>[
    OfflineSpeechModelDefinition(
      id: 'qwen3-tts-0.6b-custom',
      name: 'Qwen3-TTS · 0.6B 预设音色',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.qwenTts,
      repository: 'Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice',
      sizeLabel: '约 2 GB',
      description: '轻量多语言朗读，提供九种预设音色和风格控制。',
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        ..._generation,
        ..._qwenPreset,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'qwen3-tts-1.7b-custom',
      name: 'Qwen3-TTS · 1.7B 预设音色',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.qwenTts,
      repository: 'Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice',
      sizeLabel: '约 4.5 GB',
      description: '质量更高的多语言预设音色与风格控制模型。',
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        ..._generation,
        ..._qwenPreset,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'qwen3-tts-0.6b-base',
      name: 'Qwen3-TTS · 0.6B 音色克隆',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.qwenTts,
      repository: 'Qwen/Qwen3-TTS-12Hz-0.6B-Base',
      sizeLabel: '约 2 GB',
      description: '使用三秒参考音频快速克隆音色。',
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        ..._generation,
        ..._qwenClone,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'qwen3-tts-1.7b-base',
      name: 'Qwen3-TTS · 1.7B 音色克隆',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.qwenTts,
      repository: 'Qwen/Qwen3-TTS-12Hz-1.7B-Base',
      sizeLabel: '约 4.5 GB',
      description: '更高质量的多语言三秒音色克隆。',
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        ..._generation,
        ..._qwenClone,
      ],
    ),
    OfflineSpeechModelDefinition(
      id: 'qwen3-tts-1.7b-design',
      name: 'Qwen3-TTS · 1.7B 音色设计',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.qwenTts,
      repository: 'Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign',
      sizeLabel: '约 4.5 GB',
      description: '通过自然语言描述设计新的音色与表达风格。',
      parameters: <OfflineSpeechParameter>[
        ..._ttsCommon,
        ..._generation,
        OfflineSpeechParameter(
          key: 'voice_description',
          label: '音色描述',
          description: '描述性别、年龄、音质、口音和表达风格。',
          type: OfflineSpeechParameterType.text,
          defaultValue: '温暖自然的青年女声，吐字清晰。',
          options: _voiceDescriptionPresets,
        ),
      ],
    ),
  ];

  static const _qwenPreset = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'speaker',
      label: '预设音色',
      description: '选择模型内置音色。',
      type: OfflineSpeechParameterType.choice,
      defaultValue: 'Vivian',
      options: <OfflineSpeechOption>[
        OfflineSpeechOption(
          'Vivian',
          'Vivian',
          language: '中文',
          description: '明亮、略带个性的青年女声。',
        ),
        OfflineSpeechOption(
          'Serena',
          'Serena',
          language: '中文',
          description: '温暖柔和的青年女声。',
        ),
        OfflineSpeechOption(
          'Uncle_Fu',
          'Uncle Fu',
          language: '中文',
          description: '低沉醇厚的成熟男声。',
        ),
        OfflineSpeechOption(
          'Dylan',
          'Dylan',
          language: '北京话',
          description: '清晰自然的年轻北京男声。',
        ),
        OfflineSpeechOption(
          'Eric',
          'Eric',
          language: '四川话',
          description: '活泼、略带沙哑亮度的成都男声。',
        ),
        OfflineSpeechOption(
          'Ryan',
          'Ryan',
          language: '英语',
          description: '节奏感强、富有活力的男声。',
        ),
        OfflineSpeechOption(
          'Aiden',
          'Aiden',
          language: '英语',
          description: '阳光清晰的美式男声。',
        ),
        OfflineSpeechOption(
          'Ono_Anna',
          'Ono Anna',
          language: '日语',
          description: '轻盈灵动、俏皮的日语女声。',
        ),
        OfflineSpeechOption(
          'Sohee',
          'Sohee',
          language: '韩语',
          description: '温暖且情感丰富的韩语女声。',
        ),
      ],
    ),
    OfflineSpeechParameter(
      key: 'instruct',
      label: '风格指令',
      description: '用自然语言控制情绪和表达方式。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '自然清晰，语速适中。',
      options: _speechInstructionPresets,
    ),
  ];
  static const _qwenClone = <OfflineSpeechParameter>[
    OfflineSpeechParameter(
      key: 'reference_audio',
      label: '参考音频',
      description: '建议使用至少三秒的清晰单人语音。',
      type: OfflineSpeechParameterType.path,
      defaultValue: '',
    ),
    OfflineSpeechParameter(
      key: 'reference_text',
      label: '参考文本',
      description: '参考音频对应的准确文本。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '',
    ),
  ];

  static List<OfflineSpeechModelDefinition> forKind(OfflineSpeechKind kind) {
    return models.where((model) => model.kind == kind).toList(growable: false);
  }

  static OfflineSpeechModelDefinition? byId(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

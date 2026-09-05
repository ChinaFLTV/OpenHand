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

enum OfflineSpeechParameterType { text, integer, decimal, toggle, choice, path }

class OfflineSpeechOption {
  const OfflineSpeechOption(this.value, this.label);

  final String value;
  final String label;
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
      OfflineSpeechParameterType.text || OfflineSpeechParameterType.path =>
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
}

class OfflineSpeechModelDefinition {
  const OfflineSpeechModelDefinition({
    required this.id,
    required this.name,
    required this.kind,
    required this.runtime,
    required this.repository,
    required this.description,
    required this.sizeLabel,
    required this.parameters,
  });

  final String id;
  final String name;
  final OfflineSpeechKind kind;
  final OfflineSpeechRuntime runtime;
  final String repository;
  final String description;
  final String sizeLabel;
  final List<OfflineSpeechParameter> parameters;

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
  });

  factory OfflineSpeechSettings.defaults() => OfflineSpeechSettings(
    recognition: OfflineSpeechModelSettings.defaults(
      OfflineSpeechKind.recognition,
    ),
    synthesis: OfflineSpeechModelSettings.defaults(OfflineSpeechKind.synthesis),
    textPolishing: const OfflineSpeechTextPolishingSettings.disabled(),
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
    );
  }

  final OfflineSpeechModelSettings recognition;
  final OfflineSpeechModelSettings synthesis;
  final OfflineSpeechTextPolishingSettings textPolishing;

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
    );
  }

  OfflineSpeechSettings updateTextPolishing(
    OfflineSpeechTextPolishingSettings settings,
  ) {
    return OfflineSpeechSettings(
      recognition: recognition,
      synthesis: synthesis,
      textPolishing: settings.normalized(),
    );
  }

  OfflineSpeechSettings normalized() => OfflineSpeechSettings(
    recognition: recognition.normalized(OfflineSpeechKind.recognition),
    synthesis: synthesis.normalized(OfflineSpeechKind.synthesis),
    textPolishing: textPolishing.normalized(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    OfflineSpeechKind.recognition.storageKey: recognition.toJson(),
    OfflineSpeechKind.synthesis.storageKey: synthesis.toJson(),
    'text_polishing': textPolishing.toJson(),
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
      key: 'streaming',
      label: '流式输出',
      description: '生成首段音频后立即开始播放。',
      type: OfflineSpeechParameterType.toggle,
      defaultValue: true,
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
      id: 'cosyvoice3-0.5b',
      name: 'Fun-CosyVoice 3 · 0.5B',
      kind: OfflineSpeechKind.synthesis,
      runtime: OfflineSpeechRuntime.cosyVoice,
      repository: 'FunAudioLLM/Fun-CosyVoice3-0.5B-2512',
      sizeLabel: '约 4 GB',
      description: '中文、方言和多语言自然语音，支持音色克隆与双向流式生成。',
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
        OfflineSpeechOption('Vivian', 'Vivian · 明亮女声'),
        OfflineSpeechOption('Serena', 'Serena · 温柔女声'),
        OfflineSpeechOption('Uncle_Fu', 'Uncle Fu · 沉稳男声'),
        OfflineSpeechOption('Dylan', 'Dylan · 北京男声'),
        OfflineSpeechOption('Eric', 'Eric · 成都男声'),
        OfflineSpeechOption('Ryan', 'Ryan · 英语男声'),
      ],
    ),
    OfflineSpeechParameter(
      key: 'instruct',
      label: '风格指令',
      description: '用自然语言控制情绪和表达方式。',
      type: OfflineSpeechParameterType.text,
      defaultValue: '自然清晰，语速适中。',
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

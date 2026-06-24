import 'ai_model_config.dart';
import 'ai_tts_settings.dart';

class AiTtsCatalogOption {
  const AiTtsCatalogOption(this.value, this.label);

  final String value;
  final String label;
}

class AiTtsProviderCatalog {
  const AiTtsProviderCatalog({
    required this.provider,
    required this.voiceOptions,
    required this.languageOptions,
    this.modelOptions = const <AiTtsCatalogOption>[],
    this.formatOptions = const <AiTtsCatalogOption>[],
    this.resourceIdOptions = const <AiTtsCatalogOption>[],
  });

  final AiTtsProvider provider;
  final List<AiTtsCatalogOption> voiceOptions;
  final List<AiTtsCatalogOption> languageOptions;
  final List<AiTtsCatalogOption> modelOptions;
  final List<AiTtsCatalogOption> formatOptions;
  final List<AiTtsCatalogOption> resourceIdOptions;
}

class AiTtsProviderCatalogs {
  const AiTtsProviderCatalogs._();

  static const String openAiDefaultVoice = 'alloy';
  static const String stepFunDefaultVoice = 'cixingnansheng';

  static AiTtsProviderCatalog of(AiTtsProvider provider) {
    return _catalogs[provider]!;
  }

  static List<AiTtsCatalogOption> voices(AiTtsProvider provider) {
    return of(provider).voiceOptions;
  }

  static List<AiTtsCatalogOption> languages(AiTtsProvider provider) {
    return of(provider).languageOptions;
  }

  static List<AiTtsCatalogOption> voiceOptionsForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (!usesStepFunSpeech(protocol: protocol, modelId: modelId)) {
      return _aiVoices;
    }
    if (isStepAudio25TtsModel(modelId)) return _stepAudio25Voices;
    if (_isStepTtsMiniModel(modelId)) return _stepTtsMiniVoices;
    if (_isStepTtsClassicModel(modelId)) return _stepTtsClassicVoices;
    return _stepFunVoices;
  }

  static List<AiTtsCatalogOption> formatOptionsForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return usesStepFunSpeech(protocol: protocol, modelId: modelId)
        ? _stepFunFormats
        : _aiFormats;
  }

  static String defaultVoiceForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return usesStepFunSpeech(protocol: protocol, modelId: modelId)
        ? stepFunDefaultVoice
        : openAiDefaultVoice;
  }

  static String normalizeVoiceForAiModel({
    required String? voice,
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (usesStepFunSpeech(protocol: protocol, modelId: modelId)) {
      final normalized = normalizeStepFunVoice(voice);
      final options = voiceOptionsForAiModel(
        protocol: protocol,
        modelId: modelId,
      );
      final supported = options.any((option) => option.value == normalized);
      return supported ? normalized : stepFunDefaultVoice;
    }
    final normalized = voice?.trim() ?? '';
    return normalized.isEmpty ? openAiDefaultVoice : normalized;
  }

  static String normalizeStepFunVoice(String? voice) {
    final normalized = voice?.trim() ?? '';
    if (normalized.isEmpty || isOpenAiPresetVoice(normalized)) {
      return stepFunDefaultVoice;
    }
    return normalized;
  }

  static String normalizeStepFunResponseFormat(Object? raw) {
    final format = '${raw ?? ''}'.trim().toLowerCase();
    if (stepFunSupportedFormats.contains(format)) return format;
    return 'mp3';
  }

  static bool usesStepFunSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.stepfun || isStepFunTtsModel(modelId);
  }

  static bool isStepFunTtsModel(String modelId) {
    final normalized = modelId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.startsWith('step-tts') ||
        (normalized.startsWith('stepaudio-') && normalized.contains('tts'));
  }

  static bool isStepAudio25TtsModel(String modelId) {
    return modelId.trim().toLowerCase().startsWith('stepaudio-2.5-tts');
  }

  static bool _isStepTtsMiniModel(String modelId) {
    return modelId.trim().toLowerCase().startsWith('step-tts-mini');
  }

  static bool _isStepTtsClassicModel(String modelId) {
    final normalized = modelId.trim().toLowerCase();
    return normalized.startsWith('step-tts') &&
        !normalized.startsWith('step-tts-mini');
  }

  static bool isOpenAiPresetVoice(String voice) {
    return _openAiPresetVoices.contains(voice.trim().toLowerCase());
  }

  static const Set<String> stepFunSupportedFormats = <String>{
    'wav',
    'mp3',
    'flac',
    'opus',
    'pcm',
  };

  static const Set<int> stepFunSupportedSampleRates = <int>{
    8000,
    16000,
    22050,
    24000,
    48000,
  };

  static const List<AiTtsCatalogOption> _commonLanguages = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh-CN', '简体中文 zh-CN'),
    AiTtsCatalogOption('zh-TW', '繁体中文 zh-TW'),
    AiTtsCatalogOption('en-US', 'English en-US'),
    AiTtsCatalogOption('en-GB', 'English en-GB'),
    AiTtsCatalogOption('ja-JP', '日本語 ja-JP'),
    AiTtsCatalogOption('ko-KR', '한국어 ko-KR'),
    AiTtsCatalogOption('fr-FR', 'Français fr-FR'),
    AiTtsCatalogOption('de-DE', 'Deutsch de-DE'),
  ];

  static const List<AiTtsCatalogOption> _browserVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('', '自动匹配系统默认音色'),
    AiTtsCatalogOption('Tingting', 'macOS Tingting'),
    AiTtsCatalogOption('Sinji', 'macOS Sinji'),
    AiTtsCatalogOption('Meijia', 'macOS Meijia'),
    AiTtsCatalogOption('Samantha', 'macOS Samantha'),
    AiTtsCatalogOption('Microsoft Xiaoxiao', 'Windows Xiaoxiao'),
    AiTtsCatalogOption('Microsoft Yunxi', 'Windows Yunxi'),
    AiTtsCatalogOption('Google 普通话', 'Chrome 普通话'),
  ];

  static const List<AiTtsCatalogOption> _aiVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('alloy', 'Alloy'),
    AiTtsCatalogOption('ash', 'Ash'),
    AiTtsCatalogOption('ballad', 'Ballad'),
    AiTtsCatalogOption('coral', 'Coral'),
    AiTtsCatalogOption('echo', 'Echo'),
    AiTtsCatalogOption('fable', 'Fable'),
    AiTtsCatalogOption('nova', 'Nova'),
    AiTtsCatalogOption('onyx', 'Onyx'),
    AiTtsCatalogOption('sage', 'Sage'),
    AiTtsCatalogOption('shimmer', 'Shimmer'),
    AiTtsCatalogOption('verse', 'Verse'),
  ];

  static const Set<String> _openAiPresetVoices = <String>{
    'alloy',
    'ash',
    'ballad',
    'cedar',
    'coral',
    'echo',
    'fable',
    'marin',
    'nova',
    'onyx',
    'sage',
    'shimmer',
    'verse',
  };

  static final List<AiTtsCatalogOption> _stepFunVoices = List.unmodifiable(
    _uniqueOptions(<AiTtsCatalogOption>[
      ..._stepAudio25Voices,
      ..._stepTtsClassicVoices,
      ..._stepTtsMiniVoices,
    ]),
  );

  static const List<AiTtsCatalogOption> _stepAudio25Voices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('cixingnansheng', '磁性男声'),
        AiTtsCatalogOption('vibrant-youth', '活力青年'),
        AiTtsCatalogOption('lively-girl', '活力女声'),
        AiTtsCatalogOption('soft-spoken-gentleman', '温和绅士'),
        AiTtsCatalogOption('magnetic-voiced-male', '磁性男声'),
        AiTtsCatalogOption('zixinnansheng', '自信男声'),
        AiTtsCatalogOption('elegantgentle-female', '优雅温柔女声'),
        AiTtsCatalogOption('livelybreezy-female', '轻快活力女声'),
        AiTtsCatalogOption('wenrounansheng', '温柔男声'),
        AiTtsCatalogOption('wenrougongzi', '温柔公子'),
        AiTtsCatalogOption('yuanqinansheng', '元气男声'),
        AiTtsCatalogOption('jingdiannvsheng', '经典女声'),
        AiTtsCatalogOption('wenroushunv', '温柔淑女'),
        AiTtsCatalogOption('tianmeinvsheng', '甜美女声'),
        AiTtsCatalogOption('qingchunshaonv', '青春少女'),
        AiTtsCatalogOption('yuanqishaonv', '元气少女'),
        AiTtsCatalogOption('linjiajiejie', '邻家姐姐'),
        AiTtsCatalogOption('zhengpaiqingnian', '正派青年'),
        AiTtsCatalogOption('qingniandaxuesheng', '青年大学生'),
        AiTtsCatalogOption('boyinnansheng', '播音男声'),
        AiTtsCatalogOption('ruyananshi', '儒雅男士'),
        AiTtsCatalogOption('shenchennanyin', '深沉男音'),
        AiTtsCatalogOption('qinqienvsheng', '亲切女声'),
        AiTtsCatalogOption('wenrounvsheng', '温柔女声'),
        AiTtsCatalogOption('jilingshaonv', '机灵少女'),
        AiTtsCatalogOption('ruanmengnvsheng', '软萌女声'),
        AiTtsCatalogOption('youyanvsheng', '优雅女声'),
        AiTtsCatalogOption('lengyanyujie', '冷艳御姐'),
        AiTtsCatalogOption('shuangkuaijiejie', '爽快姐姐'),
        AiTtsCatalogOption('wenjingxuejie', '文静学姐'),
        AiTtsCatalogOption('linjiameimei', '邻家妹妹'),
        AiTtsCatalogOption('zhixingjiejie', '知性姐姐'),
        AiTtsCatalogOption('shuangkuainansheng', '爽快男声'),
        AiTtsCatalogOption('ganliannvsheng', '干练女声'),
        AiTtsCatalogOption('qinhenvsheng', '亲和女声'),
        AiTtsCatalogOption('huolinvsheng', '活力女声'),
      ];

  static const List<AiTtsCatalogOption> _stepTtsClassicVoices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('cixingnansheng', '磁性男声'),
        AiTtsCatalogOption('chengshunvsheng', '成熟女声'),
        AiTtsCatalogOption('zhengpainansheng', '正派男声'),
        AiTtsCatalogOption('qingnianwenyinvsheng', '青年文艺女声'),
        AiTtsCatalogOption('shuangkuainansheng', '爽快男声'),
        AiTtsCatalogOption('wenrounvsheng', '温柔女声'),
        AiTtsCatalogOption('jilingshaonv', '机灵少女'),
      ];

  static const List<AiTtsCatalogOption> _stepTtsMiniVoices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('cixingnansheng', '磁性男声'),
        AiTtsCatalogOption('zhengpainansheng', '正派男声'),
        AiTtsCatalogOption('female-shaonv', '少女女声'),
        AiTtsCatalogOption('male-qn-qingse', '青涩青年男声'),
      ];

  static const List<AiTtsCatalogOption> _aiFormats = <AiTtsCatalogOption>[
    AiTtsCatalogOption('mp3', 'MP3'),
    AiTtsCatalogOption('wav', 'WAV'),
    AiTtsCatalogOption('opus', 'Opus'),
    AiTtsCatalogOption('aac', 'AAC'),
    AiTtsCatalogOption('flac', 'FLAC'),
    AiTtsCatalogOption('pcm', 'PCM'),
  ];

  static const List<AiTtsCatalogOption> _stepFunFormats = <AiTtsCatalogOption>[
    AiTtsCatalogOption('mp3', 'MP3'),
    AiTtsCatalogOption('wav', 'WAV'),
    AiTtsCatalogOption('flac', 'FLAC'),
    AiTtsCatalogOption('opus', 'Opus'),
    AiTtsCatalogOption('pcm', 'PCM'),
  ];

  static const List<AiTtsCatalogOption> _xfyunVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('xiaoyan', '讯飞小燕 - 女声'),
    AiTtsCatalogOption('aisjiuxu', '讯飞许久 - 男声'),
    AiTtsCatalogOption('aisxping', '讯飞小萍 - 女声'),
    AiTtsCatalogOption('aisjinger', '讯飞小婧 - 女声'),
    AiTtsCatalogOption('aisbabyxu', '讯飞许小宝 - 童声'),
    AiTtsCatalogOption('x2_xiaoyan', '讯飞小燕 2.0 - 女声'),
    AiTtsCatalogOption('x2_xiaofeng', '讯飞小峰 2.0 - 男声'),
  ];

  static const List<AiTtsCatalogOption> _youdaoVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('', '有道默认发音人'),
    AiTtsCatalogOption('0', '女声'),
    AiTtsCatalogOption('1', '男声'),
  ];

  static const List<AiTtsCatalogOption> _youdaoLanguages = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh-CHS', '中文 zh-CHS'),
    AiTtsCatalogOption('en', 'English en'),
    AiTtsCatalogOption('ja', '日本語 ja'),
    AiTtsCatalogOption('ko', '한국어 ko'),
    AiTtsCatalogOption('fr', 'Français fr'),
    AiTtsCatalogOption('de', 'Deutsch de'),
    AiTtsCatalogOption('es', 'Español es'),
    AiTtsCatalogOption('ru', 'Русский ru'),
  ];

  static const List<AiTtsCatalogOption> _bingVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh-CN-XiaoxiaoNeural', '晓晓 - 中文女声'),
    AiTtsCatalogOption('zh-CN-YunxiNeural', '云希 - 中文男声'),
    AiTtsCatalogOption('zh-CN-YunjianNeural', '云健 - 中文男声'),
    AiTtsCatalogOption('zh-CN-XiaoyiNeural', '晓伊 - 中文女声'),
    AiTtsCatalogOption('zh-CN-YunyangNeural', '云扬 - 中文男声'),
    AiTtsCatalogOption('zh-TW-HsiaoChenNeural', '曉臻 - 繁中女声'),
    AiTtsCatalogOption('en-US-JennyNeural', 'Jenny - English'),
    AiTtsCatalogOption('en-US-GuyNeural', 'Guy - English'),
    AiTtsCatalogOption('ja-JP-NanamiNeural', 'Nanami - 日本語'),
  ];

  static const List<AiTtsCatalogOption> _googleVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh-CN-Standard-A', '中文女声 Standard-A'),
    AiTtsCatalogOption('zh-CN-Standard-B', '中文男声 Standard-B'),
    AiTtsCatalogOption('zh-CN-Standard-C', '中文男声 Standard-C'),
    AiTtsCatalogOption('zh-CN-Standard-D', '中文女声 Standard-D'),
    AiTtsCatalogOption('zh-CN-Wavenet-A', '中文女声 Wavenet-A'),
    AiTtsCatalogOption('zh-CN-Wavenet-B', '中文男声 Wavenet-B'),
    AiTtsCatalogOption('en-US-Standard-C', 'English Standard-C'),
    AiTtsCatalogOption('en-US-Standard-D', 'English Standard-D'),
    AiTtsCatalogOption('ja-JP-Standard-A', '日本語 Standard-A'),
  ];

  static const List<AiTtsCatalogOption> _baiduVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('0', '普通女声'),
    AiTtsCatalogOption('1', '普通男声'),
    AiTtsCatalogOption('3', '度逍遥'),
    AiTtsCatalogOption('4', '度丫丫'),
  ];

  static const List<AiTtsCatalogOption> _doubaoVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh_female_vv_uranus_bigtts', 'Vivi 2.0 - 女声'),
    AiTtsCatalogOption('zh_female_wanwanxiaohe_moon_bigtts', '湾湾小何 - 女声'),
    AiTtsCatalogOption('zh_male_beijingxiaoye_moon_bigtts', '北京小爷 - 男声'),
    AiTtsCatalogOption('zh_female_shuangkuaisisi_moon_bigtts', '爽快思思 - 女声'),
    AiTtsCatalogOption('zh_male_yangguangqingnian_moon_bigtts', '阳光青年 - 男声'),
    AiTtsCatalogOption('zh_female_tianmeixiaoyuan_moon_bigtts', '甜美小源 - 女声'),
    AiTtsCatalogOption('en_female_amanda_mars_bigtts', 'Amanda - English'),
    AiTtsCatalogOption('en_male_jackson_mars_bigtts', 'Jackson - English'),
  ];

  static const List<AiTtsCatalogOption> _mimoVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('冰糖', '冰糖 - 中文女声'),
    AiTtsCatalogOption('茉莉', '茉莉 - 中文女声'),
    AiTtsCatalogOption('苏打', '苏打 - 中文男声'),
    AiTtsCatalogOption('白桦', '白桦 - 中文男声'),
    AiTtsCatalogOption('Mia', 'Mia - English Female'),
    AiTtsCatalogOption('Chloe', 'Chloe - English Female'),
    AiTtsCatalogOption('Milo', 'Milo - English Male'),
    AiTtsCatalogOption('Dean', 'Dean - English Male'),
  ];

  static const List<AiTtsCatalogOption> _mimoLanguages = <AiTtsCatalogOption>[
    AiTtsCatalogOption('zh-CN', '简体中文 zh-CN'),
    AiTtsCatalogOption('zh-TW', '繁体中文 zh-TW'),
    AiTtsCatalogOption('en-US', 'English en-US'),
    AiTtsCatalogOption('en-GB', 'English en-GB'),
  ];

  static const Map<AiTtsProvider, AiTtsProviderCatalog> _catalogs =
      <AiTtsProvider, AiTtsProviderCatalog>{
        AiTtsProvider.ai: AiTtsProviderCatalog(
          provider: AiTtsProvider.ai,
          voiceOptions: _aiVoices,
          languageOptions: _commonLanguages,
          formatOptions: _aiFormats,
        ),
        AiTtsProvider.system: AiTtsProviderCatalog(
          provider: AiTtsProvider.system,
          voiceOptions: _browserVoices,
          languageOptions: _commonLanguages,
        ),
        AiTtsProvider.xfyun: AiTtsProviderCatalog(
          provider: AiTtsProvider.xfyun,
          voiceOptions: _xfyunVoices,
          languageOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('zh-CN', '中文 zh-CN'),
          ],
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('lame', 'MP3 (lame)'),
            AiTtsCatalogOption('raw', 'PCM raw'),
          ],
        ),
        AiTtsProvider.youdao: AiTtsProviderCatalog(
          provider: AiTtsProvider.youdao,
          voiceOptions: _youdaoVoices,
          languageOptions: _youdaoLanguages,
        ),
        AiTtsProvider.bing: AiTtsProviderCatalog(
          provider: AiTtsProvider.bing,
          voiceOptions: _bingVoices,
          languageOptions: _commonLanguages,
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption(
              'audio-24khz-48kbitrate-mono-mp3',
              'MP3 24kHz 48kbps',
            ),
            AiTtsCatalogOption(
              'audio-16khz-32kbitrate-mono-mp3',
              'MP3 16kHz 32kbps',
            ),
            AiTtsCatalogOption('riff-24khz-16bit-mono-pcm', 'WAV 24kHz PCM'),
            AiTtsCatalogOption('ogg-24khz-16bit-mono-opus', 'OGG Opus 24kHz'),
          ],
        ),
        AiTtsProvider.google: AiTtsProviderCatalog(
          provider: AiTtsProvider.google,
          voiceOptions: _googleVoices,
          languageOptions: _commonLanguages,
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('MP3', 'MP3'),
            AiTtsCatalogOption('LINEAR16', 'WAV LINEAR16'),
            AiTtsCatalogOption('OGG_OPUS', 'OGG Opus'),
          ],
        ),
        AiTtsProvider.baidu: AiTtsProviderCatalog(
          provider: AiTtsProvider.baidu,
          voiceOptions: _baiduVoices,
          languageOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('zh', '中文 zh'),
          ],
        ),
        AiTtsProvider.doubao: AiTtsProviderCatalog(
          provider: AiTtsProvider.doubao,
          voiceOptions: _doubaoVoices,
          languageOptions: _commonLanguages,
          modelOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('seed-tts-2.0-standard', 'Seed TTS 2.0 标准版'),
            AiTtsCatalogOption('seed-tts-2.0-expressive', 'Seed TTS 2.0 高表现力版'),
          ],
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('mp3', 'MP3'),
            AiTtsCatalogOption('wav', 'WAV'),
            AiTtsCatalogOption('ogg_opus', 'OGG Opus'),
            AiTtsCatalogOption('pcm', 'PCM'),
          ],
          resourceIdOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('seed-tts-2.0', 'Seed TTS 2.0'),
            AiTtsCatalogOption('seed-icl-2.0', 'Seed ICL 2.0 复刻音色'),
          ],
        ),
        AiTtsProvider.mimo: AiTtsProviderCatalog(
          provider: AiTtsProvider.mimo,
          voiceOptions: _mimoVoices,
          languageOptions: _mimoLanguages,
          modelOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('mimo-v2.5-tts', 'MiMo V2.5 TTS'),
            AiTtsCatalogOption(
              'mimo-v2.5-tts-voicedesign',
              'MiMo V2.5 TTS Voice Design',
            ),
            AiTtsCatalogOption(
              'mimo-v2.5-tts-voiceclone',
              'MiMo V2.5 TTS Voice Clone',
            ),
          ],
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('wav', 'WAV'),
            AiTtsCatalogOption('mp3', 'MP3'),
            AiTtsCatalogOption('pcm16', 'PCM 16-bit'),
          ],
        ),
        AiTtsProvider.apple: AiTtsProviderCatalog(
          provider: AiTtsProvider.apple,
          voiceOptions: _browserVoices,
          languageOptions: _commonLanguages,
        ),
      };

  static List<AiTtsCatalogOption> _uniqueOptions(
    List<AiTtsCatalogOption> options,
  ) {
    final seen = <String>{};
    final result = <AiTtsCatalogOption>[];
    for (final option in options) {
      if (seen.add(option.value)) result.add(option);
    }
    return result;
  }
}

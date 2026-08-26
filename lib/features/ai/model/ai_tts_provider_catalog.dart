import '../../../shared/util/input_value_parsing.dart';
import 'ai_model_config.dart';
import 'ai_tts_settings.dart';

class AiTtsCatalogOption {
  const AiTtsCatalogOption(this.value, this.label, [this.enLabel]);

  final String value;
  final String label;
  final String? enLabel;
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
  static const String qwenDefaultVoice = 'Cherry';
  static const String minimaxDefaultVoice = 'female-shaonv';
  static const String doubaoDefaultVoice = 'zh_female_vv_uranus_bigtts';
  static const String mimoDefaultVoice = 'mimo_default';
  static const String stepFunDefaultFormat = 'mp3';
  static const String _mimoPresetModelId = 'mimo-v2.5-tts';
  static const String _stepAudio25ModelPrefix = 'stepaudio-2.5-tts';
  static const String _stepTtsModelPrefix = 'step-tts';
  static const String _stepTtsMiniModelPrefix = 'step-tts-mini';

  static AiTtsProviderCatalog of(AiTtsProvider provider) {
    return _catalogs[provider]!;
  }

  static List<AiTtsCatalogOption> voiceOptionsForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (usesStepFunSpeech(protocol: protocol, modelId: modelId)) {
      if (isStepAudio25TtsModel(modelId)) return _stepAudio25Voices;
      if (_isStepTtsMiniModel(modelId)) return _stepTtsMiniVoices;
      if (_isStepTtsClassicModel(modelId)) return _stepTtsClassicVoices;
      return _stepFunVoices;
    }
    if (usesQwenSpeech(protocol: protocol, modelId: modelId)) {
      return _qwenVoiceOptionsForModel(modelId);
    }
    if (usesMiniMaxSpeech(protocol: protocol, modelId: modelId)) {
      return _minimaxVoices;
    }
    if (usesSeedSpeech(protocol: protocol, modelId: modelId)) {
      return _doubaoVoices;
    }
    if (usesMimoSpeech(protocol: protocol, modelId: modelId)) {
      return _mimoPresetVoiceOptionsForModel(modelId);
    }
    return _aiVoices;
  }

  static List<AiTtsCatalogOption> formatOptionsForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (isMiniMaxMusicModel(modelId)) return _minimaxMusicFormats;
    if (usesStepFunSpeech(protocol: protocol, modelId: modelId)) {
      return _stepFunFormats;
    }
    if (usesSeedSpeech(protocol: protocol, modelId: modelId)) {
      return of(AiTtsProvider.doubao).formatOptions;
    }
    if (usesMimoSpeech(protocol: protocol, modelId: modelId)) {
      return of(AiTtsProvider.mimo).formatOptions;
    }
    if (usesMiniMaxSpeech(protocol: protocol, modelId: modelId)) {
      return _minimaxFormats;
    }
    return _aiFormats;
  }

  static String defaultVoiceForAiModel({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    if (usesStepFunSpeech(protocol: protocol, modelId: modelId)) {
      return stepFunDefaultVoice;
    }
    if (usesQwenSpeech(protocol: protocol, modelId: modelId)) {
      return qwenDefaultVoice;
    }
    if (usesMiniMaxSpeech(protocol: protocol, modelId: modelId)) {
      return minimaxDefaultVoice;
    }
    if (usesSeedSpeech(protocol: protocol, modelId: modelId)) {
      return doubaoDefaultVoice;
    }
    if (usesMimoSpeech(protocol: protocol, modelId: modelId)) {
      return mimoDefaultVoice;
    }
    return openAiDefaultVoice;
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
    if (usesQwenSpeech(protocol: protocol, modelId: modelId)) {
      final normalized = _trimmedVoice(voice);
      final options = voiceOptionsForAiModel(
        protocol: protocol,
        modelId: modelId,
      );
      final supported = options.any((option) => option.value == normalized);
      return supported ? normalized : qwenDefaultVoice;
    }
    final normalized = _trimmedVoice(voice);
    return normalized.isEmpty
        ? defaultVoiceForAiModel(protocol: protocol, modelId: modelId)
        : normalized;
  }

  static String normalizeStepFunVoice(String? voice) {
    final normalized = _trimmedVoice(voice);
    if (normalized.isEmpty || isOpenAiPresetVoice(normalized)) {
      return stepFunDefaultVoice;
    }
    return normalized;
  }

  static String normalizeStepFunResponseFormat(Object? raw) {
    final format = _normalizedLookupValue(raw);
    if (stepFunSupportedFormats.contains(format)) return format;
    return stepFunDefaultFormat;
  }

  static bool usesStepFunSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.stepfun || isStepFunTtsModel(modelId);
  }

  static bool usesQwenSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.qwen || isQwenTtsModel(modelId);
  }

  static bool usesMiniMaxSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    final normalized = _normalizedLookupValue(modelId);
    return normalized.startsWith('speech-') ||
        normalized.startsWith('minimax/speech-') ||
        normalized.contains('/speech-') ||
        normalized.startsWith('t2a') ||
        (protocol == AiProtocolType.minimax && normalized.contains('speech'));
  }

  static bool usesSeedSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.seed || isSeedTtsModel(modelId);
  }

  static bool usesMimoSpeech({
    required AiProtocolType protocol,
    required String modelId,
  }) {
    return protocol == AiProtocolType.mimo || isMimoTtsModel(modelId);
  }

  static bool isStepFunTtsModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    if (normalized.isEmpty) return false;
    return normalized.startsWith(_stepTtsModelPrefix) ||
        (normalized.startsWith('stepaudio-') && normalized.contains('tts'));
  }

  static bool isStepAudio25TtsModel(String modelId) {
    return _normalizedLookupValue(modelId).startsWith(_stepAudio25ModelPrefix);
  }

  static bool isQwenTtsModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    if (normalized.isEmpty) return false;
    return normalized.startsWith('qwen-tts') ||
        normalized.startsWith('qwen2-tts') ||
        normalized.startsWith('qwen3-tts') ||
        normalized.contains('cosyvoice');
  }

  static bool isSeedTtsModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    return normalized.startsWith('seed-tts') ||
        normalized.startsWith('doubao-tts') ||
        normalized.contains('seed-tts') ||
        normalized.contains('bigtts');
  }

  static bool isMimoTtsModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    return normalized.startsWith(_mimoPresetModelId);
  }

  static bool isMiniMaxMusicModel(String modelId) {
    return _normalizedLookupValue(modelId).contains('minimax-music');
  }

  static bool _isStepTtsMiniModel(String modelId) {
    return _normalizedLookupValue(modelId).startsWith(_stepTtsMiniModelPrefix);
  }

  static bool _isStepTtsClassicModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    return normalized.startsWith(_stepTtsModelPrefix) &&
        !normalized.startsWith(_stepTtsMiniModelPrefix);
  }

  static bool isOpenAiPresetVoice(String voice) {
    return _openAiPresetVoices.contains(_normalizedLookupValue(voice));
  }

  static const Set<String> stepFunSupportedFormats = <String>{
    'wav',
    'mp3',
    'flac',
    'opus',
    'pcm',
  };

  static const List<AiTtsCatalogOption> _minimaxMusicFormats =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('mp3', 'MP3'),
        AiTtsCatalogOption('wav', 'WAV'),
        AiTtsCatalogOption('pcm', 'PCM'),
      ];

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
    AiTtsCatalogOption('cedar', 'Cedar'),
    AiTtsCatalogOption('coral', 'Coral'),
    AiTtsCatalogOption('echo', 'Echo'),
    AiTtsCatalogOption('fable', 'Fable'),
    AiTtsCatalogOption('marin', 'Marin'),
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

  static const List<AiTtsCatalogOption>
  _stepAudio25Voices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('cixingnansheng', '磁性男声', 'Magnetic Male Voice'),
    AiTtsCatalogOption('vibrant-youth', '活力青年', 'Vibrant Young Voice'),
    AiTtsCatalogOption('lively-girl', '活力女声', 'Lively Female Voice'),
    AiTtsCatalogOption(
      'soft-spoken-gentleman',
      '温和绅士',
      'Soft-Spoken Gentleman',
    ),
    AiTtsCatalogOption('magnetic-voiced-male', '磁性男声', 'Magnetic Male Voice'),
    AiTtsCatalogOption('zixinnansheng', '自信男声', 'Confident Male Voice'),
    AiTtsCatalogOption(
      'elegantgentle-female',
      '优雅温柔女声',
      'Elegant Gentle Female Voice',
    ),
    AiTtsCatalogOption(
      'livelybreezy-female',
      '轻快活力女声',
      'Breezy Lively Female Voice',
    ),
    AiTtsCatalogOption('wenrounansheng', '温柔男声', 'Gentle Male Voice'),
    AiTtsCatalogOption('wenrougongzi', '温柔公子', 'Gentle Gentleman'),
    AiTtsCatalogOption('yuanqinansheng', '元气男声', 'Energetic Male Voice'),
    AiTtsCatalogOption('jingdiannvsheng', '经典女声', 'Classic Female Voice'),
    AiTtsCatalogOption('wenroushunv', '温柔淑女', 'Gentle Lady'),
    AiTtsCatalogOption('tianmeinvsheng', '甜美女声', 'Sweet Female Voice'),
    AiTtsCatalogOption('qingchunshaonv', '青春少女', 'Youthful Girl Voice'),
    AiTtsCatalogOption('yuanqishaonv', '元气少女', 'Energetic Girl Voice'),
    AiTtsCatalogOption('linjiajiejie', '邻家姐姐', 'Girl-Next-Door Voice'),
    AiTtsCatalogOption(
      'zhengpaiqingnian',
      '正派青年',
      'Upstanding Young Male Voice',
    ),
    AiTtsCatalogOption('qingniandaxuesheng', '青年大学生', 'College Student Voice'),
    AiTtsCatalogOption('boyinnansheng', '播音男声', 'Male Announcer Voice'),
    AiTtsCatalogOption('ruyananshi', '儒雅男士', 'Refined Gentleman'),
    AiTtsCatalogOption('shenchennanyin', '深沉男音', 'Deep Male Voice'),
    AiTtsCatalogOption('qinqienvsheng', '亲切女声', 'Warm Female Voice'),
    AiTtsCatalogOption('wenrounvsheng', '温柔女声', 'Gentle Female Voice'),
    AiTtsCatalogOption('jilingshaonv', '机灵少女', 'Clever Girl Voice'),
    AiTtsCatalogOption('ruanmengnvsheng', '软萌女声', 'Soft Cute Female Voice'),
    AiTtsCatalogOption('youyanvsheng', '优雅女声', 'Elegant Female Voice'),
    AiTtsCatalogOption('lengyanyujie', '冷艳御姐', 'Cool Mature Female Voice'),
    AiTtsCatalogOption('shuangkuaijiejie', '爽快姐姐', 'Bright Female Voice'),
    AiTtsCatalogOption('wenjingxuejie', '文静学姐', 'Quiet Senior Student Voice'),
    AiTtsCatalogOption('linjiameimei', '邻家妹妹', 'Friendly Younger Female Voice'),
    AiTtsCatalogOption('zhixingjiejie', '知性姐姐', 'Intellectual Female Voice'),
    AiTtsCatalogOption('shuangkuainansheng', '爽快男声', 'Bright Male Voice'),
    AiTtsCatalogOption('ganliannvsheng', '干练女声', 'Capable Female Voice'),
    AiTtsCatalogOption('qinhenvsheng', '亲和女声', 'Approachable Female Voice'),
    AiTtsCatalogOption('huolinvsheng', '活力女声', 'Energetic Female Voice'),
  ];

  static const List<AiTtsCatalogOption> _stepTtsClassicVoices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('cixingnansheng', '磁性男声', 'Magnetic Male Voice'),
        AiTtsCatalogOption('chengshunvsheng', '成熟女声', 'Mature Female Voice'),
        AiTtsCatalogOption('zhengpainansheng', '正派男声', 'Upstanding Male Voice'),
        AiTtsCatalogOption(
          'qingnianwenyinvsheng',
          '青年文艺女声',
          'Young Artistic Female Voice',
        ),
        AiTtsCatalogOption('shuangkuainansheng', '爽快男声', 'Bright Male Voice'),
        AiTtsCatalogOption('wenrounvsheng', '温柔女声', 'Gentle Female Voice'),
        AiTtsCatalogOption('jilingshaonv', '机灵少女', 'Clever Girl Voice'),
      ];

  static const List<AiTtsCatalogOption> _stepTtsMiniVoices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('cixingnansheng', '磁性男声', 'Magnetic Male Voice'),
        AiTtsCatalogOption('zhengpainansheng', '正派男声', 'Upstanding Male Voice'),
        AiTtsCatalogOption('female-shaonv', '少女女声', 'Young Female Voice'),
        AiTtsCatalogOption('male-qn-qingse', '青涩青年男声', 'Young Male Voice'),
      ];

  static const List<AiTtsCatalogOption> _qwenLegacyVoices =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('Cherry', '芊悦 - 阳光女声', 'Cherry - sunny female'),
        AiTtsCatalogOption('Serena', '苏瑶 - 温柔女声', 'Serena - gentle female'),
        AiTtsCatalogOption('Ethan', '晨煦 - 活力男声', 'Ethan - vibrant male'),
        AiTtsCatalogOption('Chelsie', '千雪 - 二次元女声', 'Chelsie - anime female'),
        AiTtsCatalogOption('Jada', '上海-阿珍', 'Shanghai - Jada'),
        AiTtsCatalogOption('Dylan', '北京-晓东', 'Beijing - Dylan'),
        AiTtsCatalogOption('Sunny', '四川-晴儿', 'Sichuan - Sunny'),
      ];

  static const List<AiTtsCatalogOption> _qwen3Voices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('Cherry', '芊悦 - 阳光女声', 'Cherry - sunny female'),
    AiTtsCatalogOption('Serena', '苏瑶 - 温柔女声', 'Serena - gentle female'),
    AiTtsCatalogOption('Ethan', '晨煦 - 活力男声', 'Ethan - vibrant male'),
    AiTtsCatalogOption('Chelsie', '千雪 - 二次元女声', 'Chelsie - anime female'),
    AiTtsCatalogOption('Momo', '茉兔 - 俏皮女声', 'Momo - playful female'),
    AiTtsCatalogOption('Vivian', '十三 - 可爱女声', 'Vivian - cute female'),
    AiTtsCatalogOption('Moon', '月白 - 率性男声', 'Moon - bold male'),
    AiTtsCatalogOption(
      'Maia',
      '四月 - 知性女声',
      'Maia - gentle intellectual female',
    ),
    AiTtsCatalogOption('Kai', '凯 - 舒缓男声', 'Kai - soothing male'),
    AiTtsCatalogOption('Nofish', '不吃鱼 - 设计师男声', 'Nofish - designer male'),
    AiTtsCatalogOption('Bella', '萌宝 - 活泼女声', 'Bella - bubbly female'),
    AiTtsCatalogOption('Jennifer', '詹妮弗 - 美式女声', 'Jennifer - American female'),
    AiTtsCatalogOption('Ryan', '甜茶 - 英语男声', 'Ryan - English male'),
    AiTtsCatalogOption('Katerina', '卡捷琳娜 - 俄语女声', 'Katerina - Russian female'),
    AiTtsCatalogOption('Aiden', '艾登 - 英语男声', 'Aiden - English male'),
    AiTtsCatalogOption('Eldric Sage', '沧明子 - 仙侠男声', 'Eldric Sage'),
    AiTtsCatalogOption('Mia', '乖小妹 - 甜美女声', 'Mia - sweet female'),
    AiTtsCatalogOption('Mochi', '沙小弥 - 软萌女声', 'Mochi - soft cute female'),
    AiTtsCatalogOption('Bellona', '燕铮莺 - 戏剧女声', 'Bellona - dramatic female'),
    AiTtsCatalogOption('Vincent', '田叔 - 成熟男声', 'Vincent - mature male'),
    AiTtsCatalogOption('Bunny', '萌小姬 - 萌系女声', 'Bunny - cute female'),
    AiTtsCatalogOption('Neil', '阿闻 - 自然男声', 'Neil - natural male'),
    AiTtsCatalogOption('Elias', '墨讲师 - 讲师男声', 'Elias - lecturer male'),
    AiTtsCatalogOption('Arthur', '徐大爷 - 长者男声', 'Arthur - elderly male'),
    AiTtsCatalogOption('Nini', '邻家妹妹 - 亲切女声', 'Nini - friendly female'),
    AiTtsCatalogOption('Seren', '小婉 - 温婉女声', 'Seren - warm female'),
    AiTtsCatalogOption('Pip', '顽屁小孩 - 童声', 'Pip - child voice'),
    AiTtsCatalogOption('Stella', '少女阿月 - 少女声', 'Stella - young female'),
    AiTtsCatalogOption('Bodega', '博德加 - 西语男声', 'Bodega - Spanish male'),
    AiTtsCatalogOption('Sonrisa', '索尼莎 - 西语女声', 'Sonrisa - Spanish female'),
    AiTtsCatalogOption('Alek', '阿列克 - 俄语男声', 'Alek - Russian male'),
    AiTtsCatalogOption('Dolce', '多尔切 - 意语女声', 'Dolce - Italian female'),
    AiTtsCatalogOption('Sohee', '素熙 - 韩语女声', 'Sohee - Korean female'),
    AiTtsCatalogOption('Ono Anna', '小野杏 - 日语女声', 'Ono Anna - Japanese female'),
    AiTtsCatalogOption('Lenn', '莱恩 - 德语男声', 'Lenn - German male'),
    AiTtsCatalogOption('Emilien', '埃米尔安 - 法语男声', 'Emilien - French male'),
    AiTtsCatalogOption('Andre', '安德雷 - 磁性男声', 'Andre - magnetic male'),
    AiTtsCatalogOption(
      'Radio Gol',
      '拉迪奥·戈尔 - 解说男声',
      'Radio Gol - commentator male',
    ),
    AiTtsCatalogOption('Jada', '上海-阿珍', 'Shanghai - Jada'),
    AiTtsCatalogOption('Dylan', '北京-晓东', 'Beijing - Dylan'),
    AiTtsCatalogOption('Li', '南京-老李', 'Nanjing - Li'),
    AiTtsCatalogOption('Marcus', '陕西-秦川', 'Shaanxi - Marcus'),
    AiTtsCatalogOption('Roy', '闽南-阿杰', 'Southern Min - Roy'),
    AiTtsCatalogOption('Peter', '天津-李彼得', 'Tianjin - Peter'),
    AiTtsCatalogOption('Sunny', '四川-晴儿', 'Sichuan - Sunny'),
    AiTtsCatalogOption('Eric', '四川-程川', 'Sichuan - Eric'),
    AiTtsCatalogOption('Rocky', '粤语-阿强', 'Cantonese - Rocky'),
    AiTtsCatalogOption('Kiki', '粤语-阿清', 'Cantonese - Kiki'),
  ];

  static const List<AiTtsCatalogOption> _qwenCosyVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption(
      'longxiaochun',
      '龙小淳 - 中文女声',
      'Longxiaochun - Chinese female',
    ),
    AiTtsCatalogOption(
      'longxiaoxia',
      '龙小夏 - 中文女声',
      'Longxiaoxia - Chinese female',
    ),
    AiTtsCatalogOption(
      'longxiaocheng',
      '龙小诚 - 中文男声',
      'Longxiaocheng - Chinese male',
    ),
    AiTtsCatalogOption(
      'longxiaobai',
      '龙小白 - 中文女声',
      'Longxiaobai - Chinese female',
    ),
  ];

  static const List<AiTtsCatalogOption> _minimaxVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption('female-shaonv', '少女女声', 'Young Female Voice'),
    AiTtsCatalogOption('male-qn-qingse', '青涩青年男声', 'Young Male Voice'),
    AiTtsCatalogOption('male-qn-jingying', '精英青年男声', 'Elite Young Male Voice'),
    AiTtsCatalogOption('male-qn-badao', '霸道青年男声', 'Assertive Young Male Voice'),
    AiTtsCatalogOption('male-qn-daxuesheng', '青年大学生男声', 'College Male Voice'),
    AiTtsCatalogOption('female-yujie', '御姐女声', 'Mature Female Voice'),
    AiTtsCatalogOption('female-chengshu', '成熟女声', 'Mature Female Voice'),
    AiTtsCatalogOption('female-tianmei', '甜美女声', 'Sweet Female Voice'),
    AiTtsCatalogOption('presenter_male', '男性主持人', 'Male Presenter'),
    AiTtsCatalogOption('presenter_female', '女性主持人', 'Female Presenter'),
    AiTtsCatalogOption('audiobook_male_1', '有声书男声 1', 'Audiobook Male 1'),
    AiTtsCatalogOption('audiobook_female_1', '有声书女声 1', 'Audiobook Female 1'),
    AiTtsCatalogOption(
      'Chinese (Mandarin)_Lyrical_Voice',
      '中文抒情女声',
      'Chinese Lyrical Voice',
    ),
    AiTtsCatalogOption(
      'Chinese (Mandarin)_HK_Flight_Attendant',
      '中文空乘女声',
      'Chinese Flight Attendant',
    ),
    AiTtsCatalogOption(
      'English_Graceful_Lady',
      '英文优雅女声',
      'English Graceful Lady',
    ),
    AiTtsCatalogOption(
      'English_Insightful_Speaker',
      '英文睿智讲述',
      'English Insightful Speaker',
    ),
    AiTtsCatalogOption(
      'English_Persuasive_Man',
      '英文说服力男声',
      'English Persuasive Man',
    ),
    AiTtsCatalogOption(
      'Japanese_Whisper_Belle',
      '日文轻语女声',
      'Japanese Whisper Belle',
    ),
  ];

  static const List<AiTtsCatalogOption> _aiFormats = <AiTtsCatalogOption>[
    AiTtsCatalogOption('mp3', 'MP3'),
    AiTtsCatalogOption('wav', 'WAV'),
    AiTtsCatalogOption('opus', 'Opus'),
    AiTtsCatalogOption('aac', 'AAC'),
    AiTtsCatalogOption('flac', 'FLAC'),
    AiTtsCatalogOption('pcm', 'PCM'),
  ];

  static const List<AiTtsCatalogOption> _minimaxFormats = <AiTtsCatalogOption>[
    AiTtsCatalogOption('mp3', 'MP3'),
    AiTtsCatalogOption('wav', 'WAV'),
    AiTtsCatalogOption('pcm', 'PCM'),
    AiTtsCatalogOption('flac', 'FLAC'),
    AiTtsCatalogOption('opus', 'Ogg/Opus'),
    AiTtsCatalogOption('pcmu_raw', 'G.711 μ-law Raw'),
    AiTtsCatalogOption('pcmu_wav', 'G.711 μ-law WAV'),
  ];

  static const List<AiTtsCatalogOption> miniMaxLanguageOptions =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('auto', '自动识别', 'Auto Detect'),
        AiTtsCatalogOption('Chinese', '中文', 'Chinese'),
        AiTtsCatalogOption('Chinese,Yue', '粤语', 'Cantonese'),
        AiTtsCatalogOption('English', '英语', 'English'),
        AiTtsCatalogOption('Japanese', '日语', 'Japanese'),
        AiTtsCatalogOption('Korean', '韩语', 'Korean'),
        AiTtsCatalogOption('French', '法语', 'French'),
        AiTtsCatalogOption('German', '德语', 'German'),
        AiTtsCatalogOption('Spanish', '西班牙语', 'Spanish'),
        AiTtsCatalogOption('Portuguese', '葡萄牙语', 'Portuguese'),
        AiTtsCatalogOption('Italian', '意大利语', 'Italian'),
        AiTtsCatalogOption('Russian', '俄语', 'Russian'),
        AiTtsCatalogOption('Arabic', '阿拉伯语', 'Arabic'),
        AiTtsCatalogOption('Thai', '泰语', 'Thai'),
        AiTtsCatalogOption('Vietnamese', '越南语', 'Vietnamese'),
        AiTtsCatalogOption('Indonesian', '印度尼西亚语', 'Indonesian'),
        AiTtsCatalogOption('Hindi', '印地语', 'Hindi'),
        AiTtsCatalogOption('Turkish', '土耳其语', 'Turkish'),
        AiTtsCatalogOption('Dutch', '荷兰语', 'Dutch'),
        AiTtsCatalogOption('Polish', '波兰语', 'Polish'),
        AiTtsCatalogOption('Ukrainian', '乌克兰语', 'Ukrainian'),
        AiTtsCatalogOption('Romanian', '罗马尼亚语', 'Romanian'),
        AiTtsCatalogOption('Greek', '希腊语', 'Greek'),
        AiTtsCatalogOption('Czech', '捷克语', 'Czech'),
        AiTtsCatalogOption('Finnish', '芬兰语', 'Finnish'),
        AiTtsCatalogOption('Bulgarian', '保加利亚语', 'Bulgarian'),
        AiTtsCatalogOption('Danish', '丹麦语', 'Danish'),
        AiTtsCatalogOption('Hebrew', '希伯来语', 'Hebrew'),
        AiTtsCatalogOption('Malay', '马来语', 'Malay'),
        AiTtsCatalogOption('Persian', '波斯语', 'Persian'),
        AiTtsCatalogOption('Slovak', '斯洛伐克语', 'Slovak'),
        AiTtsCatalogOption('Swedish', '瑞典语', 'Swedish'),
        AiTtsCatalogOption('Croatian', '克罗地亚语', 'Croatian'),
        AiTtsCatalogOption('Filipino', '菲律宾语', 'Filipino'),
        AiTtsCatalogOption('Hungarian', '匈牙利语', 'Hungarian'),
        AiTtsCatalogOption('Norwegian', '挪威语', 'Norwegian'),
        AiTtsCatalogOption('Slovenian', '斯洛文尼亚语', 'Slovenian'),
        AiTtsCatalogOption('Catalan', '加泰罗尼亚语', 'Catalan'),
        AiTtsCatalogOption('Nynorsk', '新挪威语', 'Nynorsk'),
        AiTtsCatalogOption('Tamil', '泰米尔语', 'Tamil'),
        AiTtsCatalogOption('Afrikaans', '南非荷兰语', 'Afrikaans'),
      ];

  static const List<AiTtsCatalogOption> miniMaxEmotionOptions =
      <AiTtsCatalogOption>[
        AiTtsCatalogOption('', '自动匹配', 'Automatic'),
        AiTtsCatalogOption('happy', '高兴', 'Happy'),
        AiTtsCatalogOption('sad', '悲伤', 'Sad'),
        AiTtsCatalogOption('angry', '愤怒', 'Angry'),
        AiTtsCatalogOption('fearful', '害怕', 'Fearful'),
        AiTtsCatalogOption('disgusted', '厌恶', 'Disgusted'),
        AiTtsCatalogOption('surprised', '惊讶', 'Surprised'),
        AiTtsCatalogOption('calm', '中性', 'Calm'),
        AiTtsCatalogOption('fluent', '生动', 'Fluent'),
        AiTtsCatalogOption('whisper', '低语', 'Whisper'),
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
    AiTtsCatalogOption(
      'zh_female_vv_uranus_bigtts',
      'Vivi 2.0 - 女声',
      'Vivi 2.0 - female voice',
    ),
    AiTtsCatalogOption(
      'zh_female_wanwanxiaohe_moon_bigtts',
      '湾湾小何 - 女声',
      'Wanwan Xiaohe - female voice',
    ),
    AiTtsCatalogOption(
      'zh_male_beijingxiaoye_moon_bigtts',
      '北京小爷 - 男声',
      'Beijing Xiaoye - male voice',
    ),
    AiTtsCatalogOption(
      'zh_female_shuangkuaisisi_moon_bigtts',
      '爽快思思 - 女声',
      'Bright Sisi - female voice',
    ),
    AiTtsCatalogOption(
      'zh_male_yangguangqingnian_moon_bigtts',
      '阳光青年 - 男声',
      'Sunny Youth - male voice',
    ),
    AiTtsCatalogOption(
      'zh_female_tianmeixiaoyuan_moon_bigtts',
      '甜美小源 - 女声',
      'Sweet Xiaoyuan - female voice',
    ),
    AiTtsCatalogOption(
      'en_female_amanda_mars_bigtts',
      'Amanda - 英语女声',
      'Amanda - English female voice',
    ),
    AiTtsCatalogOption(
      'en_male_jackson_mars_bigtts',
      'Jackson - 英语男声',
      'Jackson - English male voice',
    ),
  ];

  static const List<AiTtsCatalogOption> _mimoVoices = <AiTtsCatalogOption>[
    AiTtsCatalogOption(
      'mimo_default',
      'MiMo 默认音色（随部署区域）',
      'MiMo default voice (region-aware)',
    ),
    AiTtsCatalogOption('冰糖', '冰糖 - 中文女声', 'Bingtang - Chinese female'),
    AiTtsCatalogOption('茉莉', '茉莉 - 中文女声', 'Moli - Chinese female'),
    AiTtsCatalogOption('苏打', '苏打 - 中文男声', 'Soda - Chinese male'),
    AiTtsCatalogOption('白桦', '白桦 - 中文男声', 'Baihua - Chinese male'),
    AiTtsCatalogOption('Mia', 'Mia - 英语女声', 'Mia - English Female'),
    AiTtsCatalogOption('Chloe', 'Chloe - 英语女声', 'Chloe - English Female'),
    AiTtsCatalogOption('Milo', 'Milo - 英语男声', 'Milo - English Male'),
    AiTtsCatalogOption('Dean', 'Dean - 英语男声', 'Dean - English Male'),
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
            AiTtsCatalogOption(_mimoPresetModelId, 'MiMo V2.5 TTS'),
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
            AiTtsCatalogOption(aiMimoDefaultAudioFormat, 'WAV', 'WAV'),
            AiTtsCatalogOption('mp3', 'MP3', 'MP3'),
          ],
        ),
        AiTtsProvider.apple: AiTtsProviderCatalog(
          provider: AiTtsProvider.apple,
          voiceOptions: _browserVoices,
          languageOptions: _commonLanguages,
        ),
      };

  static List<AiTtsCatalogOption> _qwenVoiceOptionsForModel(String modelId) {
    final normalized = _normalizedLookupValue(modelId);
    if (normalized.contains('cosyvoice')) return _qwenCosyVoices;
    if (normalized.startsWith('qwen-tts') &&
        !normalized.startsWith('qwen3-tts')) {
      return _qwenLegacyVoices;
    }
    return _qwen3Voices;
  }

  static List<AiTtsCatalogOption> _mimoPresetVoiceOptionsForModel(
    String modelId,
  ) {
    final normalized = _normalizedLookupValue(modelId);
    if (normalized.isNotEmpty && normalized != _mimoPresetModelId) {
      return const <AiTtsCatalogOption>[];
    }
    return _mimoVoices;
  }

  static String _trimmedVoice(String? voice) => nullIfBlank(voice) ?? '';

  static String _normalizedLookupValue(Object? value) =>
      lowercaseStringFromValue(value);

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

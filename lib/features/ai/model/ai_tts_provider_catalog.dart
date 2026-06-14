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

  static AiTtsProviderCatalog of(AiTtsProvider provider) {
    return _catalogs[provider]!;
  }

  static List<AiTtsCatalogOption> voices(AiTtsProvider provider) {
    return of(provider).voiceOptions;
  }

  static List<AiTtsCatalogOption> languages(AiTtsProvider provider) {
    return of(provider).languageOptions;
  }

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
    AiTtsCatalogOption('Sin-ji', 'macOS Sin-ji'),
    AiTtsCatalogOption('Mei-Jia', 'macOS Mei-Jia'),
    AiTtsCatalogOption('Samantha', 'macOS Samantha'),
    AiTtsCatalogOption('Microsoft Xiaoxiao', 'Windows Xiaoxiao'),
    AiTtsCatalogOption('Microsoft Yunxi', 'Windows Yunxi'),
    AiTtsCatalogOption('Google 普通话', 'Chrome 普通话'),
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

  static const Map<AiTtsProvider, AiTtsProviderCatalog> _catalogs =
      <AiTtsProvider, AiTtsProviderCatalog>{
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
            AiTtsCatalogOption('seed-tts-2.0', 'Seed TTS 2.0'),
          ],
          formatOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('mp3', 'MP3'),
            AiTtsCatalogOption('wav', 'WAV'),
            AiTtsCatalogOption('ogg_opus', 'OGG Opus'),
            AiTtsCatalogOption('pcm', 'PCM'),
          ],
          resourceIdOptions: <AiTtsCatalogOption>[
            AiTtsCatalogOption('seed-tts-2.0', 'Seed TTS 2.0'),
          ],
        ),
        AiTtsProvider.apple: AiTtsProviderCatalog(
          provider: AiTtsProvider.apple,
          voiceOptions: _browserVoices,
          languageOptions: _commonLanguages,
        ),
      };
}

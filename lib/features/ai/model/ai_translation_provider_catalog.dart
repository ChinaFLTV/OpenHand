import 'ai_translation_settings.dart';

class AiTranslationCatalogOption {
  const AiTranslationCatalogOption(this.value, this.label);

  final String value;
  final String label;
}

class AiTranslationProviderCatalog {
  const AiTranslationProviderCatalog({
    required this.provider,
    required this.sourceLanguageOptions,
    required this.targetLanguageOptions,
  });

  final AiTranslationProvider provider;
  final List<AiTranslationCatalogOption> sourceLanguageOptions;
  final List<AiTranslationCatalogOption> targetLanguageOptions;
}

class AiTranslationProviderCatalogs {
  const AiTranslationProviderCatalogs._();

  static const List<AiTranslationCatalogOption> targetLanguageOptions =
      <AiTranslationCatalogOption>[
        AiTranslationCatalogOption('zh-CN', '简体中文 zh-CN'),
        AiTranslationCatalogOption('zh-TW', '繁體中文 zh-TW'),
        AiTranslationCatalogOption('en', 'English en'),
        AiTranslationCatalogOption('ja', '日本語 ja'),
        AiTranslationCatalogOption('ko', '한국어 ko'),
        AiTranslationCatalogOption('fr', 'Français fr'),
        AiTranslationCatalogOption('de', 'Deutsch de'),
        AiTranslationCatalogOption('es', 'Español es'),
        AiTranslationCatalogOption('ru', 'Русский ru'),
        AiTranslationCatalogOption('it', 'Italiano it'),
        AiTranslationCatalogOption('pt', 'Português pt'),
        AiTranslationCatalogOption('vi', 'Tiếng Việt vi'),
        AiTranslationCatalogOption('th', 'ไทย th'),
        AiTranslationCatalogOption('id', 'Bahasa Indonesia id'),
        AiTranslationCatalogOption('ar', 'العربية ar'),
        AiTranslationCatalogOption('tr', 'Türkçe tr'),
        AiTranslationCatalogOption('hi', 'हिन्दी hi'),
        AiTranslationCatalogOption('he', 'עברית he'),
        AiTranslationCatalogOption('nl', 'Nederlands nl'),
        AiTranslationCatalogOption('pl', 'Polski pl'),
        AiTranslationCatalogOption('sv', 'Svenska sv'),
        AiTranslationCatalogOption('da', 'Dansk da'),
      ];

  static const List<AiTranslationCatalogOption> sourceLanguageOptions =
      <AiTranslationCatalogOption>[
        AiTranslationCatalogOption('auto', '自动检测 Auto'),
        ...targetLanguageOptions,
      ];

  static AiTranslationProviderCatalog of(AiTranslationProvider provider) {
    return AiTranslationProviderCatalog(
      provider: provider,
      sourceLanguageOptions: sourceLanguageOptions,
      targetLanguageOptions: targetLanguageOptions,
    );
  }
}

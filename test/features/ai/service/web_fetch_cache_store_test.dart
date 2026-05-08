import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_web_fetch_settings.dart';
import 'package:openhand/features/ai/service/web_fetch/web_fetch_cache_store.dart';

void main() {
  group('WebFetchCacheStore.computeKey', () {
    test('normalizes URL/prompt surrounding whitespace', () {
      final settings = _settingsWith([
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.bing,
          enabled: true,
        ),
      ]);

      final keyA = WebFetchCacheStore.computeKey(
        url: ' https://example.com/a ',
        prompt: ' summarize ',
        settings: settings,
        modelProtocol: 'openai',
        modelId: 'gpt-4o',
      );
      final keyB = WebFetchCacheStore.computeKey(
        url: 'https://example.com/a',
        prompt: 'summarize',
        settings: settings,
        modelProtocol: 'openai',
        modelId: 'gpt-4o',
      );

      expect(keyA, keyB);
    });

    test('changes when focused-answer model changes', () {
      final settings = _settingsWith([
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.bing,
          enabled: true,
        ),
      ]);

      final keyA = _key(settings: settings);
      final keyB = _key(settings: settings, modelId: 'claude-4-sonnet');

      expect(keyA, isNot(keyB));
    });

    test('changes when engine order changes', () {
      final settingsA = _settingsWith([
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.bing,
          enabled: true,
        ),
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.duckduckgo,
          enabled: true,
        ),
      ]);
      final settingsB = _settingsWith([
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.duckduckgo,
          enabled: true,
        ),
        const AiWebFetchEngineConfig(
          kind: AiWebFetchEngineKind.bing,
          enabled: true,
        ),
      ]);

      expect(_key(settings: settingsA), isNot(_key(settings: settingsB)));
    });

    test(
      'changes when parallel mode or truncation-affecting engine config changes',
      () {
        final serialSettings = _settingsWith([
          const AiWebFetchEngineConfig(
            kind: AiWebFetchEngineKind.bing,
            enabled: true,
            truncationChars: 1000,
          ),
        ], parallel: false);
        final parallelSettings = _settingsWith([
          const AiWebFetchEngineConfig(
            kind: AiWebFetchEngineKind.bing,
            enabled: true,
            truncationChars: 1000,
          ),
        ]);
        final differentTruncationSettings = _settingsWith([
          const AiWebFetchEngineConfig(
            kind: AiWebFetchEngineKind.bing,
            enabled: true,
            truncationChars: 2000,
          ),
        ]);

        expect(
          _key(settings: serialSettings),
          isNot(_key(settings: parallelSettings)),
        );
        expect(
          _key(settings: parallelSettings),
          isNot(_key(settings: differentTruncationSettings)),
        );
      },
    );
  });
}

AiWebFetchSettings _settingsWith(
  List<AiWebFetchEngineConfig> engines, {
  bool parallel = true,
}) {
  return AiWebFetchSettings(engines: engines, parallel: parallel);
}

String _key({required AiWebFetchSettings settings, String modelId = 'gpt-4o'}) {
  return WebFetchCacheStore.computeKey(
    url: 'https://example.com/a',
    prompt: 'summarize',
    settings: settings,
    modelProtocol: 'openai',
    modelId: modelId,
  );
}

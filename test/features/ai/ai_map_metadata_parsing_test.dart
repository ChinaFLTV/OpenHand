import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('translation and tts extras normalize dirty string-keyed maps', () {
    final translation = AiTranslationProviderSettings.fromJson(
      <String, Object?>{
        'extra': <Object?, Object?>{42: 'answer', 'region': ' cn '},
      },
      provider: AiTranslationProvider.doubao,
    );
    final tts = AiTtsProviderSettings.fromJson(<String, Object?>{
      'extra': <Object?, Object?>{7: true, 'voice_id': ' v1 '},
    }, provider: AiTtsProvider.doubao);

    expect(translation.extra['42'], 'answer');
    expect(translation.extra['region'], ' cn ');
    expect(tts.extra['7'], isTrue);
    expect(tts.extra['voice_id'], ' v1 ');
  });

  test('session and message metadata normalize dirty maps', () {
    final session = AiSession.fromJson(<String, Object?>{
      'session': <String, Object?>{
        'id': 's1',
        'title': 'Session',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      },
      'messages': <Object?>[
        <String, Object?>{
          'id': 'm1',
          'kind': 'assistant',
          'role': 'assistant',
          'content': 'done',
          'created_at': '2026-01-01T00:00:00Z',
          'usage': <Object?, Object?>{'prompt_tokens': 3},
          'metadata': <Object?, Object?>{99: 'message-meta'},
        },
      ],
      'environment': <String, Object?>{},
      'statistics': <String, Object?>{},
      'metadata': <Object?, Object?>{1: 'session-meta'},
      'last_prompt_metadata': <Object?, Object?>{2: 'prompt-meta'},
    });

    expect(session.metadata['1'], 'session-meta');
    expect(session.lastPromptMetadata['2'], 'prompt-meta');
    expect(session.messages.single.metadata['99'], 'message-meta');
    expect(session.messages.single.usage?.promptTokens, 3);
  });

  test(
    'model profile maps and model profile registry normalize dirty maps',
    () {
      final profile = AiModelProfile.fromJson(<String, Object?>{
        'architecture': <Object?, Object?>{'modality': 'text', 1: 'ignored'},
        'links': <Object?, Object?>{'details': 'https://example.test/model'},
        'default_parameters': <Object?, Object?>{1: 'one', 'top_p': 0.8},
      });

      expect(profile.architecture?.modality, 'text');
      expect(profile.links?.details, 'https://example.test/model');
      expect(profile.defaultParameters['1'], 'one');
      expect(profile.defaultParameters['top_p'], 0.8);

      final model = AiModelConfig.fromJson(<String, Object?>{
        'id': 'cfg',
        'name': 'Config',
        'base_url': 'https://example.test',
        'model_id': 'model',
        'model_profiles': <Object?, Object?>{
          42: <Object?, Object?>{
            'capabilities': <Object?>['rerank'],
          },
        },
      });

      expect(model.modelProfiles['42']?.supportsRerank, isTrue);
    },
  );
}

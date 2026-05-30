import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';

void main() {
  group('AiModelProfile raw metadata', () {
    test('parses and serializes OpenRouter raw fields', () {
      final profile = AiModelProfile.fromJson(<String, Object?>{
        'display_name': 'Test Model',
        'canonical_slug': 'provider/test-model-20260601',
        'hugging_face_id': 'org/test-model',
        'created': 1778000212,
        'architecture': <String, Object?>{
          'modality': 'text+image+file->text',
          'input_modalities': <String>['text', 'image', 'file'],
          'output_modalities': <String>['text'],
          'tokenizer': 'GPT',
          'instruct_type': 'chat',
        },
        'supported_parameters': <String>['max_tokens', 'tools'],
        'default_parameters': <String, Object?>{
          'temperature': null,
          'top_p': null,
        },
        'supported_voices': <String>['alloy', 'verse'],
        'knowledge_cutoff': '2025-12',
        'expiration_date': '2026-12-31',
        'links': <String, Object?>{
          'details': '/api/v1/models/provider/test-model-20260601/endpoints',
        },
      });

      expect(profile.canonicalSlug, 'provider/test-model-20260601');
      expect(profile.huggingFaceId, 'org/test-model');
      expect(profile.created, 1778000212);
      expect(profile.architecture?.modality, 'text+image+file->text');
      expect(profile.architecture?.inputModalities, <String>[
        'text',
        'image',
        'file',
      ]);
      expect(profile.supportedParameters, <String>['max_tokens', 'tools']);
      expect(profile.defaultParameters['temperature'], isNull);
      expect(profile.supportedVoices, <String>['alloy', 'verse']);
      expect(profile.knowledgeCutoff, '2025-12');
      expect(profile.expirationDate, '2026-12-31');
      expect(
        profile.links?.details,
        '/api/v1/models/provider/test-model-20260601/endpoints',
      );

      final json = profile.toJson();
      expect(json['canonical_slug'], 'provider/test-model-20260601');
      expect(json['hugging_face_id'], 'org/test-model');
      expect(json['created'], 1778000212);
      expect(
        (json['architecture'] as Map<String, Object?>)['tokenizer'],
        'GPT',
      );
      expect(json['supported_parameters'], <String>['max_tokens', 'tools']);
      expect(
        (json['default_parameters'] as Map<String, Object?>).containsKey(
          'temperature',
        ),
        isTrue,
      );
      expect(json['supported_voices'], <String>['alloy', 'verse']);
      expect(json['knowledge_cutoff'], '2025-12');
      expect(json['expiration_date'], '2026-12-31');
      expect(
        (json['links'] as Map<String, Object?>)['details'],
        '/api/v1/models/provider/test-model-20260601/endpoints',
      );
    });

    test('profileFor merges override with catalog-backed raw metadata', () {
      const model = AiModelConfig(
        id: 'provider-raw',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'qwen/qwen3.7-max',
        protocolType: AiProtocolType.qwen,
        modelProfiles: <String, AiModelProfile>{
          'qwen/qwen3.7-max': AiModelProfile(
            requiresReasoningEcho: true,
            knowledgeCutoff: 'user-override-cutoff',
          ),
        },
      );

      final profile = model.profileFor(model.modelId);
      expect(profile.requiresReasoningEcho, isTrue);
      expect(profile.knowledgeCutoff, 'user-override-cutoff');
      expect(profile.canonicalSlug, isNotNull);
      expect(profile.architecture, isNotNull);
      expect(profile.supportedParameters, isNotEmpty);
      expect(profile.links, isNotNull);
    });

    test('file modality implies attachment support', () {
      const model = AiModelConfig(
        id: 'provider-file',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'custom/file-model',
        protocolType: AiProtocolType.openai,
        modelProfiles: <String, AiModelProfile>{
          'custom/file-model': AiModelProfile(
            supportedModalities: <AiModelModality>{
              AiModelModality.text,
              AiModelModality.file,
            },
          ),
        },
      );

      expect(model.resolvedSupportsAttachments, isTrue);
    });

    test(
      'reasoning-capable models do not automatically require reasoning echo',
      () {
        const model = AiModelConfig(
          id: 'provider-reasoning',
          baseUrl: 'https://example.com',
          authScheme: AiAuthScheme.bearer,
          token: 'token',
          modelId: 'qwen/qwen3.7-max',
          protocolType: AiProtocolType.qwen,
        );

        final profile = model.profileFor(model.modelId);
        expect(profile.supportedParameters, contains('reasoning'));
        expect(profile.supportedParameters, contains('include_reasoning'));
        expect(model.requiresReasoningEcho, isFalse);
      },
    );

    test('exact catalog preserves file modality for file-capable models', () {
      const model = AiModelConfig(
        id: 'provider-openai',
        baseUrl: 'https://example.com',
        authScheme: AiAuthScheme.bearer,
        token: 'token',
        modelId: 'openai/gpt-chat-latest',
        protocolType: AiProtocolType.openai,
      );

      final profile = model.profileFor(model.modelId);
      expect(profile.supportedModalities, contains(AiModelModality.file));
      expect(profile.supportedModalities, contains(AiModelModality.image));
    });
  });
}

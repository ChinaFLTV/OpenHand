import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_api_family.dart';
import 'package:openhand/features/ai/model/ai_operation_routing.dart';
import 'package:openhand/features/ai/model/ai_realtime_config.dart';

void main() {
  group('AiRealtimeConfig.fromJson', () {
    test('parses JSON text and normalizes scalar fields', () {
      final config = AiRealtimeConfig.fromJson('''
        {
          "transport": " websocket ",
          "url_override": " https://realtime.example.com ",
          "voice": 123,
          "sample_rate": "24000",
          "input_format": " pcm16 ",
          "output_format": " opus ",
          "session_defaults": {"temperature": 0.4, "modalities": ["audio"]}
        }
      ''');

      expect(config, isNotNull);
      expect(config!.transport, 'websocket');
      expect(config.urlOverride, 'https://realtime.example.com');
      expect(config.voice, '123');
      expect(config.sampleRate, 24000);
      expect(config.inputFormat, 'pcm16');
      expect(config.outputFormat, 'opus');
      expect(config.sessionDefaults, <String, Object?>{
        'temperature': 0.4,
        'modalities': <Object?>['audio'],
      });
    });

    test('parses loose map values and rejects non-object input', () {
      final config = AiRealtimeConfig.fromJson(<Object?, Object?>{
        'transport': ' sse ',
        'sample_rate': '-1',
        'session_defaults': <Object?, Object?>{1: 'one'},
      });

      expect(config, isNotNull);
      expect(config!.transport, 'sse');
      expect(config.sampleRate, isNull);
      expect(config.sessionDefaults, <String, Object?>{'1': 'one'});
      expect(AiRealtimeConfig.fromJson('[]'), isNull);
      expect(AiRealtimeConfig.fromJson('not-json'), isNull);
    });
  });

  group('AiOperationRouting.fromJson', () {
    test('parses JSON text and trims loose scalar values', () {
      final routing = AiOperationRouting.fromJson('''
        {
          "chat_model_id": " chat-model ",
          "responses_model_id": 42,
          "embedding_model_id": "   ",
          "default_voice": " alloy "
        }
      ''');

      expect(routing, isNotNull);
      expect(routing!.chatModelId, 'chat-model');
      expect(routing.responsesModelId, '42');
      expect(routing.embeddingModelId, isNull);
      expect(routing.defaultVoice, 'alloy');
      expect(
        routing.resolveModelId(AiApiFamily.chatCompletions, 'fallback'),
        'chat-model',
      );
      expect(
        routing.resolveModelId(AiApiFamily.embeddings, ' fallback '),
        'fallback',
      );
    });

    test('parses loose map keys and rejects non-object input', () {
      final routing = AiOperationRouting.fromJson(<Object?, Object?>{
        'rerank_model_id': ' rerank-v1 ',
        123: 'ignored',
      });

      expect(routing, isNotNull);
      expect(routing!.rerankModelId, 'rerank-v1');
      expect(AiOperationRouting.fromJson('[]'), isNull);
      expect(AiOperationRouting.fromJson(42), isNull);
    });
  });
}

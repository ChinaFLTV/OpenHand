import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_realtime_config.dart';

void main() {
  group('AiRealtimeConfig', () {
    test('fromJson keeps positive sample rate', () {
      final config = AiRealtimeConfig.fromJson(<String, Object?>{
        'voice': 'alloy',
        'sample_rate': '24000',
      });

      expect(config, isNotNull);
      expect(config!.voice, 'alloy');
      expect(config.sampleRate, 24000);
      expect(config.toJson()['sample_rate'], 24000);
    });

    test('fromJson drops non-positive sample rate', () {
      expect(
        AiRealtimeConfig.fromJson(<String, Object?>{
          'sample_rate': 0,
        })!.sampleRate,
        isNull,
      );
      expect(
        AiRealtimeConfig.fromJson(<String, Object?>{
          'sample_rate': -16000,
        })!.sampleRate,
        isNull,
      );
    });

    test('fromJson accepts json text payloads', () {
      final config = AiRealtimeConfig.fromJson(
        '{"transport":"websocket","sample_rate":16000}',
      );

      expect(config, isNotNull);
      expect(config!.transport, 'websocket');
      expect(config.sampleRate, 16000);
    });
  });
}

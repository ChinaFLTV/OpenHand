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

    test('fromJson clamps sample rate bounds', () {
      expect(
        AiRealtimeConfig.fromJson(<String, Object?>{
          'sample_rate': 1,
        })!.sampleRate,
        AiRealtimeConfig.minSampleRate,
      );
      expect(
        AiRealtimeConfig.fromJson(<String, Object?>{
          'sample_rate': 999999,
        })!.sampleRate,
        AiRealtimeConfig.maxSampleRate,
      );
    });

    test('copyWith and toJson normalize unsafe sample rates', () {
      const config = AiRealtimeConfig(sampleRate: 999999);
      final normalized = config.copyWith();

      expect(normalized.sampleRate, AiRealtimeConfig.maxSampleRate);
      expect(
        config.copyWith(sampleRate: 1).sampleRate,
        AiRealtimeConfig.minSampleRate,
      );
      expect(config.toJson()['sample_rate'], AiRealtimeConfig.maxSampleRate);
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

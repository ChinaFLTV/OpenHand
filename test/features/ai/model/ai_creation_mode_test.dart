import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';

void main() {
  group('AiCreationOptions', () {
    test('fromMetadata keeps positive integer options', () {
      final options = AiCreationOptions.fromMetadata(<String, Object?>{
        'duration_seconds': '6',
        'count': '2',
        'seed': '123',
        'frame_rate': '24',
        'num_frames': '96',
        'sample_rate': '32000',
        'bitrate': '128000',
      });

      expect(options.durationSeconds, 6);
      expect(options.count, 2);
      expect(options.seed, 123);
      expect(options.frameRate, 24);
      expect(options.numFrames, 96);
      expect(options.sampleRate, 32000);
      expect(options.bitrate, 128000);
    });

    test('fromMetadata drops non-positive integer options', () {
      final options = AiCreationOptions.fromMetadata(<String, Object?>{
        'duration_seconds': -8,
        'count': -2,
        'seed': 0,
        'frame_rate': -24,
        'fps': '30',
        'num_frames': 0,
        'sample_rate': -16000,
        'bitrate': 'bad',
      });

      expect(options.durationSeconds, isNull);
      expect(options.count, 1);
      expect(options.seed, isNull);
      expect(options.frameRate, 30);
      expect(options.numFrames, isNull);
      expect(options.sampleRate, isNull);
      expect(options.bitrate, isNull);
      expect(options.toMetadata(), <String, Object?>{'frame_rate': 30});
    });
  });
}

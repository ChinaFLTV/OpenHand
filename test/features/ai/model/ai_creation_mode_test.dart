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

    test('fromMetadata clamps bounded numeric options', () {
      final options = AiCreationOptions.fromMetadata(<String, Object?>{
        'duration_seconds': 999999,
        'count': 999,
        'frame_rate': 999,
        'num_frames': 999999,
        'sample_rate': 999999,
        'bitrate': 999999999,
        'speed': 999,
        'volume': -1,
        'pitch': -999,
      });

      expect(options.durationSeconds, AiCreationOptions.maxDurationSeconds);
      expect(options.count, AiCreationOptions.maxCount);
      expect(options.frameRate, AiCreationOptions.maxFrameRate);
      expect(options.numFrames, AiCreationOptions.maxNumFrames);
      expect(options.sampleRate, AiCreationOptions.maxSampleRate);
      expect(options.bitrate, AiCreationOptions.maxBitrate);
      expect(options.speed, AiCreationOptions.maxSpeed);
      expect(options.volume, AiCreationOptions.minVolume);
      expect(options.pitch, AiCreationOptions.minPitch);
    });

    test('fromMetadata drops malformed optional double options', () {
      final options = AiCreationOptions.fromMetadata(<String, Object?>{
        'speed': double.nan,
        'volume': double.infinity,
        'pitch': 'bad',
      });

      expect(options.speed, isNull);
      expect(options.volume, isNull);
      expect(options.pitch, isNull);
      expect(options.hasExplicitOptions, isFalse);
    });

    test('copyWith and toMetadata normalize unsafe numeric values', () {
      const options = AiCreationOptions(
        durationSeconds: 999999,
        count: -1,
        frameRate: 999,
        numFrames: 999999,
        sampleRate: 1,
        bitrate: 999999999,
        speed: double.nan,
        volume: double.infinity,
        pitch: double.negativeInfinity,
      );

      final normalized = options.copyWith();
      final metadata = options.toMetadata();

      expect(normalized.durationSeconds, AiCreationOptions.maxDurationSeconds);
      expect(normalized.count, AiCreationOptions.defaultCount);
      expect(normalized.frameRate, AiCreationOptions.maxFrameRate);
      expect(normalized.numFrames, AiCreationOptions.maxNumFrames);
      expect(normalized.sampleRate, AiCreationOptions.minSampleRate);
      expect(normalized.bitrate, AiCreationOptions.maxBitrate);
      expect(normalized.speed, AiCreationOptions.defaultSpeed);
      expect(normalized.volume, AiCreationOptions.maxVolume);
      expect(normalized.pitch, AiCreationOptions.minPitch);
      expect(metadata, <String, Object?>{
        'duration_seconds': AiCreationOptions.maxDurationSeconds,
        'frame_rate': AiCreationOptions.maxFrameRate,
        'num_frames': AiCreationOptions.maxNumFrames,
        'speed': AiCreationOptions.defaultSpeed,
        'sample_rate': AiCreationOptions.minSampleRate,
        'bitrate': AiCreationOptions.maxBitrate,
        'volume': AiCreationOptions.maxVolume,
        'pitch': AiCreationOptions.minPitch,
      });
    });
  });
}

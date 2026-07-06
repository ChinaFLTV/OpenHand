import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';

void main() {
  group('AppSettingsSnapshot', () {
    test('normalizes AI message compression threshold bounds', () {
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(-1),
        AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(1),
        AppSettingsSnapshot.minAiMessageCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(
          999999999,
        ),
        AppSettingsSnapshot.maxAiMessageCompressionThresholdChars,
      );
    });

    test('normalizes AI tool result compression threshold bounds', () {
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(-1),
        AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(1),
        AppSettingsSnapshot.minAiToolResultCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(
          999999999,
        ),
        AppSettingsSnapshot.maxAiToolResultCompressionThresholdChars,
      );
    });
  });
}

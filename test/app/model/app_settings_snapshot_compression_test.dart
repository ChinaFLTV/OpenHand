import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/app/model/app_settings_snapshot.dart';

void main() {
  group('AppSettingsSnapshot compression bounds', () {
    test('normalizes message compression threshold', () {
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(0),
        AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(100),
        AppSettingsSnapshot.minAiMessageCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(
          AppSettingsSnapshot.maxAiMessageCompressionThresholdChars + 1,
        ),
        AppSettingsSnapshot.maxAiMessageCompressionThresholdChars,
      );
    });

    test('normalizes tool result compression threshold', () {
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(0),
        AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(1),
        AppSettingsSnapshot.minAiToolResultCompressionThresholdChars,
      );
      expect(
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(
          AppSettingsSnapshot.maxAiToolResultCompressionThresholdChars + 1,
        ),
        AppSettingsSnapshot.maxAiToolResultCompressionThresholdChars,
      );
    });
  });
}

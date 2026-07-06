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

    test('normalizes AI tool call safety limit bounds', () {
      expect(
        AppSettingsSnapshot.aiSingleRoundToolCallLimitFromValue(null),
        AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit,
      );
      expect(
        AppSettingsSnapshot.aiSingleRoundToolCallLimitFromValue(0),
        AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit,
      );
      expect(
        AppSettingsSnapshot.aiSingleRoundToolCallLimitFromValue(999999),
        AppSettingsSnapshot.maxAiSingleRoundToolCallLimit,
      );
      expect(
        AppSettingsSnapshot.aiSequentialToolRoundLimitFromValue(-1),
        AppSettingsSnapshot.defaultAiSequentialToolRoundLimit,
      );
      expect(
        AppSettingsSnapshot.aiSequentialToolRoundLimitFromValue(999999),
        AppSettingsSnapshot.maxAiSequentialToolRoundLimit,
      );

      final snapshot = AppSettingsSnapshot.defaults().copyWith(
        aiSingleRoundToolCallLimit: 0,
        aiSequentialToolRoundLimit: 999999,
      );

      expect(
        snapshot.aiSingleRoundToolCallLimit,
        AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit,
      );
      expect(
        snapshot.aiSequentialToolRoundLimit,
        AppSettingsSnapshot.maxAiSequentialToolRoundLimit,
      );
    });

    test('normalizes AI tool execution resource bounds', () {
      expect(
        AppSettingsSnapshot.aiMaxToolOutputCharsFromValue(-1),
        AppSettingsSnapshot.minAiMaxToolOutputChars,
      );
      expect(
        AppSettingsSnapshot.aiWriteConfirmationTimeoutMsFromValue(999999999),
        AppSettingsSnapshot.maxAiWriteConfirmationTimeoutMs,
      );
      expect(
        AppSettingsSnapshot.aiFastPathWriteAnalysisThresholdFromValue(-1),
        AppSettingsSnapshot.minAiFastPathWriteAnalysisThreshold,
      );
      expect(
        AppSettingsSnapshot.aiMaxHookTextCharactersFromValue(999999999),
        AppSettingsSnapshot.maxAiMaxHookTextCharacters,
      );
      expect(
        AppSettingsSnapshot.subprocessGracefulShutdownMsFromValue(0),
        AppSettingsSnapshot.minSubprocessGracefulShutdownMs,
      );
      expect(
        AppSettingsSnapshot.bashOutputMaxBytesFromValue(999999999),
        AppSettingsSnapshot.maxBashOutputMaxBytes,
      );
      expect(
        AppSettingsSnapshot.maxConcurrentToolsFromValue(0),
        AppSettingsSnapshot.minMaxConcurrentTools,
      );

      final snapshot = AppSettingsSnapshot.defaults().copyWith(
        aiMaxToolOutputChars: -1,
        aiWriteConfirmationTimeoutMs: 999999999,
        aiFastPathWriteAnalysisThreshold: -1,
        aiMaxHookTextCharacters: 999999999,
        subprocessGracefulShutdownMs: 0,
        bashOutputMaxBytes: 999999999,
        maxConcurrentTools: 0,
      );

      expect(
        snapshot.aiMaxToolOutputChars,
        AppSettingsSnapshot.minAiMaxToolOutputChars,
      );
      expect(
        snapshot.aiWriteConfirmationTimeoutMs,
        AppSettingsSnapshot.maxAiWriteConfirmationTimeoutMs,
      );
      expect(
        snapshot.aiFastPathWriteAnalysisThreshold,
        AppSettingsSnapshot.minAiFastPathWriteAnalysisThreshold,
      );
      expect(
        snapshot.aiMaxHookTextCharacters,
        AppSettingsSnapshot.maxAiMaxHookTextCharacters,
      );
      expect(
        snapshot.subprocessGracefulShutdownMs,
        AppSettingsSnapshot.minSubprocessGracefulShutdownMs,
      );
      expect(
        snapshot.bashOutputMaxBytes,
        AppSettingsSnapshot.maxBashOutputMaxBytes,
      );
      expect(
        snapshot.maxConcurrentTools,
        AppSettingsSnapshot.minMaxConcurrentTools,
      );
    });

    test('normalizes AI stream throttle bounds', () {
      expect(
        AppSettingsSnapshot.aiStreamMaxCharsPerSecondFromValue(-1),
        AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond,
      );
      expect(
        AppSettingsSnapshot.aiStreamMaxCharsPerSecondFromValue(999999999),
        AppSettingsSnapshot.maxAiStreamMaxCharsPerSecond,
      );
      expect(
        AppSettingsSnapshot.aiStreamMaxMessageCardsPerSecondFromValue(-1),
        AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond,
      );
      expect(
        AppSettingsSnapshot.aiStreamMaxMessageCardsPerSecondFromValue(999999),
        AppSettingsSnapshot.maxAiStreamMaxMessageCardsPerSecond,
      );
      expect(
        AppSettingsSnapshot.aiStreamThrottleDurationSecondsFromValue(999999),
        AppSettingsSnapshot.maxAiStreamThrottleDurationSeconds,
      );

      final snapshot = AppSettingsSnapshot.defaults().copyWith(
        aiStreamMaxCharsPerSecond: -1,
        aiStreamMaxMessageCardsPerSecond: 999999,
        aiStreamThrottleDurationSeconds: 999999,
      );

      expect(
        snapshot.aiStreamMaxCharsPerSecond,
        AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond,
      );
      expect(
        snapshot.aiStreamMaxMessageCardsPerSecond,
        AppSettingsSnapshot.maxAiStreamMaxMessageCardsPerSecond,
      );
      expect(
        snapshot.aiStreamThrottleDurationSeconds,
        AppSettingsSnapshot.maxAiStreamThrottleDurationSeconds,
      );
    });
  });
}

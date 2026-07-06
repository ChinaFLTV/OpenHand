import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';

void main() {
  test('AiSessionRuntimeContext normalizes tool call safety limits', () {
    final context = _runtimeContext(
      singleRoundToolCallLimit: 999999,
      sequentialToolRoundLimit: 0,
      maxToolOutputChars: -1,
      writeConfirmationTimeoutMs: 999999999,
      fastPathWriteAnalysisThreshold: -1,
      maxHookTextCharacters: 999999999,
      subprocessGracefulShutdownMs: 0,
      bashOutputMaxBytes: 999999999,
      maxConcurrentTools: 0,
      streamMaxCharsPerSecond: -1,
      streamMaxMessageCardsPerSecond: 999999,
      streamThrottleDurationSeconds: 999999,
    );

    expect(
      context.singleRoundToolCallLimit,
      AiSessionRuntimeContext.maxSingleRoundToolCallLimit,
    );
    expect(
      context.sequentialToolRoundLimit,
      AiSessionRuntimeContext.defaultSequentialToolRoundLimit,
    );
    expect(
      context.toJson()['single_round_tool_call_limit'],
      AiSessionRuntimeContext.maxSingleRoundToolCallLimit,
    );
    expect(
      context.toJson()['sequential_tool_round_limit'],
      AiSessionRuntimeContext.defaultSequentialToolRoundLimit,
    );
    expect(
      context.maxToolOutputChars,
      AiSessionRuntimeContext.minMaxToolOutputChars,
    );
    expect(
      context.writeConfirmationTimeoutMs,
      AiSessionRuntimeContext.maxWriteConfirmationTimeoutMs,
    );
    expect(
      context.fastPathWriteAnalysisThreshold,
      AiSessionRuntimeContext.minFastPathWriteAnalysisThreshold,
    );
    expect(
      context.maxHookTextCharacters,
      AiSessionRuntimeContext.maxMaxHookTextCharacters,
    );
    expect(
      context.subprocessGracefulShutdownMs,
      AiSessionRuntimeContext.minSubprocessGracefulShutdownMs,
    );
    expect(
      context.bashOutputMaxBytes,
      AiSessionRuntimeContext.maxBashOutputMaxBytes,
    );
    expect(
      context.maxConcurrentTools,
      AiSessionRuntimeContext.minMaxConcurrentTools,
    );
    expect(
      context.toJson()['max_tool_output_chars'],
      AiSessionRuntimeContext.minMaxToolOutputChars,
    );
    expect(
      context.toJson()['write_confirmation_timeout_ms'],
      AiSessionRuntimeContext.maxWriteConfirmationTimeoutMs,
    );
    expect(
      context.toJson()['fast_path_write_analysis_threshold'],
      AiSessionRuntimeContext.minFastPathWriteAnalysisThreshold,
    );
    expect(
      context.toJson()['max_hook_text_characters'],
      AiSessionRuntimeContext.maxMaxHookTextCharacters,
    );
    expect(
      context.toJson()['subprocess_graceful_shutdown_ms'],
      AiSessionRuntimeContext.minSubprocessGracefulShutdownMs,
    );
    expect(
      context.toJson()['bash_output_max_bytes'],
      AiSessionRuntimeContext.maxBashOutputMaxBytes,
    );
    expect(
      context.toJson()['max_concurrent_tools'],
      AiSessionRuntimeContext.minMaxConcurrentTools,
    );
    expect(
      context.streamMaxCharsPerSecond,
      AiSessionRuntimeContext.defaultStreamMaxCharsPerSecond,
    );
    expect(
      context.streamMaxMessageCardsPerSecond,
      AiSessionRuntimeContext.maxStreamMaxMessageCardsPerSecond,
    );
    expect(
      context.streamThrottleDurationSeconds,
      AiSessionRuntimeContext.maxStreamThrottleDurationSeconds,
    );
    expect(
      _runtimeContext().streamMaxCharsPerSecond,
      AiSessionRuntimeContext.defaultStreamMaxCharsPerSecond,
    );
  });
}

AiSessionRuntimeContext _runtimeContext({
  int? singleRoundToolCallLimit,
  int? sequentialToolRoundLimit,
  int? maxToolOutputChars,
  int? writeConfirmationTimeoutMs,
  int? fastPathWriteAnalysisThreshold,
  int? maxHookTextCharacters,
  int? subprocessGracefulShutdownMs,
  int? bashOutputMaxBytes,
  int? maxConcurrentTools,
  int? streamMaxCharsPerSecond,
  int? streamMaxMessageCardsPerSecond,
  int? streamThrottleDurationSeconds,
}) {
  return AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: '1.0.0',
    appBuildNumber: '1',
    settingsFilePath: '',
    skillsStoragePath: '',
    mcpServersFilePath: '',
    userMemoryFilePath: '',
    compressionThresholdChars: 0,
    memoryEnabled: false,
    memoryEntries: const [],
    singleRoundToolCallLimit:
        singleRoundToolCallLimit ??
        AiSessionRuntimeContext.defaultSingleRoundToolCallLimit,
    sequentialToolRoundLimit:
        sequentialToolRoundLimit ??
        AiSessionRuntimeContext.defaultSequentialToolRoundLimit,
    maxToolOutputChars:
        maxToolOutputChars ?? AiSessionRuntimeContext.defaultMaxToolOutputChars,
    writeConfirmationTimeoutMs:
        writeConfirmationTimeoutMs ??
        AiSessionRuntimeContext.defaultWriteConfirmationTimeoutMs,
    fastPathWriteAnalysisThreshold:
        fastPathWriteAnalysisThreshold ??
        AiSessionRuntimeContext.defaultFastPathWriteAnalysisThreshold,
    maxHookTextCharacters:
        maxHookTextCharacters ??
        AiSessionRuntimeContext.defaultMaxHookTextCharacters,
    subprocessGracefulShutdownMs:
        subprocessGracefulShutdownMs ??
        AiSessionRuntimeContext.defaultSubprocessGracefulShutdownMs,
    bashOutputMaxBytes:
        bashOutputMaxBytes ?? AiSessionRuntimeContext.defaultBashOutputMaxBytes,
    maxConcurrentTools:
        maxConcurrentTools ?? AiSessionRuntimeContext.defaultMaxConcurrentTools,
    streamMaxCharsPerSecond:
        streamMaxCharsPerSecond ??
        AiSessionRuntimeContext.defaultStreamMaxCharsPerSecond,
    streamMaxMessageCardsPerSecond:
        streamMaxMessageCardsPerSecond ??
        AiSessionRuntimeContext.defaultStreamMaxMessageCardsPerSecond,
    streamThrottleDurationSeconds:
        streamThrottleDurationSeconds ??
        AiSessionRuntimeContext.defaultStreamThrottleDurationSeconds,
  );
}

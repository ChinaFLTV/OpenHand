import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';

void main() {
  test('AiSessionRuntimeContext normalizes tool call safety limits', () {
    final context = AiSessionRuntimeContext(
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
      singleRoundToolCallLimit: 999999,
      sequentialToolRoundLimit: 0,
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
  });
}

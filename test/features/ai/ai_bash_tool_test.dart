import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('returns invalid arguments for out-of-range timeouts', () async {
    for (final timeout in const <int>[0, -1, 600001]) {
      final result =
          await AiBashTool(
            bashToolService: AiBashToolService(),
            hookService: AiNoopClaudeHookService(),
          ).execute(
            _context(<String, Object?>{
              'command': 'echo ok',
              'timeout': timeout,
            }),
          );

      expect(
        result.status,
        BashToolExecutionStatus.invalidArguments,
        reason: '$timeout',
      );
      expect(result.stderr, contains('between 1 and 600000'));
    }
  });
}

AiToolExecutionContext _context(Map<String, Object?> args) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call',
      name: 'Bash',
      arguments: jsonEncode(args),
    ),
    decodedArguments: args,
    model: const AiModelConfig(
      id: 'test-model',
      baseUrl: 'https://example.invalid',
      authScheme: AiAuthScheme.none,
      token: '',
      modelId: 'test',
      protocolType: AiProtocolType.openai,
    ),
    previouslyReadFiles: <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

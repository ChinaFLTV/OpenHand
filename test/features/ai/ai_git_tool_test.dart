import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('rejects invalid blame line ranges before running git', () async {
    final cases = <Map<String, Object?>>[
      <String, Object?>{
        'operation': 'blame',
        'file_path': 'lib/main.dart',
        'start_line': 1,
      },
      <String, Object?>{
        'operation': 'blame',
        'file_path': 'lib/main.dart',
        'start_line': 0,
        'end_line': 1,
      },
      <String, Object?>{
        'operation': 'blame',
        'file_path': 'lib/main.dart',
        'start_line': 5,
        'end_line': 3,
      },
    ];

    for (final args in cases) {
      final result = await AiGitTool().execute(_context(args));

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(
        result.stderr,
        anyOf(contains('provided together'), contains('line range')),
      );
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
      name: 'Git',
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

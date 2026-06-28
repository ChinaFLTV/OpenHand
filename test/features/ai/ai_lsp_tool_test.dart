import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('rejects unsupported operations before contacting LSP', () async {
    final result = await AiLspTool().execute(
      _context(<String, Object?>{
        'operation': 'renameEverything',
        'file_path': 'lib/main.dart',
        'line': 1,
        'character': 1,
      }),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('Unsupported LSP operation'));
  });

  test('rejects missing or non-positive 1-based positions', () async {
    final cases = <Map<String, Object?>>[
      <String, Object?>{
        'operation': 'hover',
        'file_path': 'lib/main.dart',
        'line': 0,
        'character': 1,
      },
      <String, Object?>{
        'operation': 'hover',
        'file_path': 'lib/main.dart',
        'line': 1,
        'character': -1,
      },
      <String, Object?>{
        'operation': 'hover',
        'file_path': 'lib/main.dart',
        'character': 1,
      },
    ];

    for (final args in cases) {
      final result = await AiLspTool().execute(_context(args));

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('positive 1-based integers'));
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
      name: 'LSP',
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test('rejects out-of-range read limits before handle lookup', () async {
    final tool = AiBashBackgroundTool();
    final cases = <Map<String, Object?>>[
      <String, Object?>{'action': 'read', 'handle': 'missing', 'max_bytes': -1},
      <String, Object?>{
        'action': 'read',
        'handle': 'missing',
        'max_bytes': 65537,
      },
      <String, Object?>{'action': 'read', 'handle': 'missing', 'timeout': -1},
      <String, Object?>{
        'action': 'read',
        'handle': 'missing',
        'timeout_ms': 600001,
      },
    ];

    for (final args in cases) {
      final result = await tool.execute(_context(args));

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, isNot(contains('Unknown handle')));
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
      name: 'BashBackground',
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

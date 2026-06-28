import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openhand_grep_tool_test_');
    await File(p.join(tempDir.path, 'sample.txt')).writeAsString('needle\n');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'rejects negative context line options before running ripgrep',
    () async {
      for (final option in const <String>['-B', '-A', '-C', 'context']) {
        final result = await AiGrepTool().execute(
          _context(<String, Object?>{
            'pattern': 'needle',
            'path': tempDir.path,
            'output_mode': 'content',
            option: -1,
          }),
        );

        expect(
          result.status,
          BashToolExecutionStatus.invalidArguments,
          reason: option,
        );
        expect(result.stderr, contains('must be non-negative integers'));
      }
    },
  );
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
      name: 'Grep',
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

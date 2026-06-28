import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_read_lints_tool_test_',
    );
    await File(p.join(tempDir.path, 'sample.dart')).writeAsString(
      'void main() {\n'
      '  final value = 1;\n'
      '  print(value);\n'
      '}\n',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('parses JSON text paths relative to working directory', () async {
    final result = await AiReadLintsTool().execute(
      _context(<String, Object?>{
        'working_directory': tempDir.path,
        'paths': '["sample.dart"]',
      }),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout, contains('No issues found'));
    expect(result.stdout, isNot(contains('does not exist')));
    expect(result.stdout, isNot(contains('doesn\'t exist')));
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
      name: 'ReadLints',
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

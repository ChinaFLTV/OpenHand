import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_codebase_search_tool_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts target_directories encoded as JSON array text', () async {
    final result = await AiCodebaseSearchTool().execute(
      _context(<String, Object?>{
        'query': 'unlikely symbol',
        'target_directories': jsonEncode(<String>[tempDir.path]),
      }),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.workingDirectory, tempDir.path);
  });

  test('rejects file path search roots before running ripgrep', () async {
    final file = File(p.join(tempDir.path, 'sample.dart'));
    await file.writeAsString('void main() {}\n');

    final result = await AiCodebaseSearchTool().execute(
      _context(<String, Object?>{'query': 'main', 'path': file.path}),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('not a directory'));
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
      name: 'CodebaseSearch',
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

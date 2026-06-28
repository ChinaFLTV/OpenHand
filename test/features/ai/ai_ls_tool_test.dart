import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openhand_ls_tool_test_');
    await File(p.join(tempDir.path, 'keep.txt')).writeAsString('keep');
    await File(p.join(tempDir.path, 'skip.log')).writeAsString('skip');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts ignore patterns encoded as JSON array text', () async {
    final result = await AiLsTool().execute(
      _context(<String, Object?>{'path': tempDir.path, 'ignore': '["*.log"]'}),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout, contains('keep.txt'));
    expect(result.stdout, isNot(contains('skip.log')));
    expect(result.metadata['ls_ignored_count'], 1);
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
      name: 'LS',
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

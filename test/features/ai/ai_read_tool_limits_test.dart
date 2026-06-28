import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_read_tool_limits_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects read limits above the bounded maximum', () async {
    final file = File(p.join(tempDir.path, 'sample.txt'));
    await file.writeAsString('line\n');

    final result = await AiReadTool().execute(
      _context(<String, Object?>{
        'file_path': file.path,
        'limit': AiToolUtils.maxReadLimit + 1,
      }),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('at most ${AiToolUtils.maxReadLimit}'));
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
      name: 'Read',
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_read_tool.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openhand-read-tool-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('allows empty PDF pages collections on non-PDF reads', () async {
    final file = File(p.join(tempDir.path, 'notes.txt'));
    await file.writeAsString('hello\nworld\n');

    final result = await _executeRead(
      filePath: file.path,
      pages: const <Object?>[],
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.resultText, contains('hello'));
    expect(result.resultText, contains('world'));
  });

  test('rejects PDF pages for non-PDF files when pages are provided', () async {
    final file = File(p.join(tempDir.path, 'notes.txt'));
    await file.writeAsString('hello\n');

    final result = await _executeRead(filePath: file.path, pages: '1');

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.resultText, contains('Read pages is only supported'));
  });

  test('rejects blank PDF page range segments', () async {
    final file = File(p.join(tempDir.path, 'report.pdf'));
    await file.writeAsBytes(const <int>[]);

    final result = await _executeRead(filePath: file.path, pages: '1,,2');

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.resultText, contains('Invalid PDF pages range "1,,2"'));
  });
}

Future<AiToolExecutionResult> _executeRead({
  required String filePath,
  Object? pages,
}) {
  final arguments = <String, Object?>{
    'file_path': filePath,
    if (pages != null) 'pages': pages,
  };
  return AiReadTool().execute(
    AiToolExecutionContext(
      sessionId: 'session-1',
      catalog: const AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[],
        toolsByName: <String, AiResolvedTool>{},
      ),
      toolCall: const AiToolCall(id: 'call-1', name: 'Read', arguments: '{}'),
      decodedArguments: arguments,
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: (BashCommandApprovalRequest request) async =>
          BashCommandApprovalDecision.approved,
    ),
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://example.invalid',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxTokens: 1024,
  );
}

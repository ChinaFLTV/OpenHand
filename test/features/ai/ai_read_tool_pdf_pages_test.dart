import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File pdfFile;
  late File textFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_read_tool_pdf_pages_test_',
    );
    pdfFile = File(p.join(tempDir.path, 'sample.pdf'));
    await pdfFile.writeAsString(
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Page >>\nendobj\n'
      '2 0 obj\n<< /Type /Page >>\nendobj\n',
    );
    textFile = File(p.join(tempDir.path, 'notes.txt'));
    await textFile.writeAsString('plain text');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('accepts PDF pages from JSON array text', () async {
    final result = await AiReadTool().execute(
      _context(<String, Object?>{
        'file_path': pdfFile.path,
        'pages': '["1","3-4"]',
      }),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout, contains('requested_pages: 1,3-4'));
    expect(result.stdout, contains('requested_page_count: 3'));
  });

  test('accepts PDF pages from native arrays', () async {
    final result = await AiReadTool().execute(
      _context(<String, Object?>{
        'file_path': pdfFile.path,
        'pages': <Object?>[1, '2-3'],
      }),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(result.stdout, contains('requested_pages: 1,2-3'));
    expect(result.stdout, contains('requested_page_count: 3'));
  });

  test('rejects empty page range segments', () async {
    final result = await AiReadTool().execute(
      _context(<String, Object?>{
        'file_path': pdfFile.path,
        'pages': <Object?>['1', '', '2'],
      }),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('Invalid PDF pages range'));
  });

  test('rejects PDF pages for non PDF files', () async {
    final result = await AiReadTool().execute(
      _context(<String, Object?>{
        'file_path': textFile.path,
        'pages': <Object?>[1],
      }),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('only supported for PDF files'));
  });

  test('enforces the maximum PDF page range count', () async {
    final result = await AiReadTool().execute(
      _context(<String, Object?>{'file_path': pdfFile.path, 'pages': '1-21'}),
    );

    expect(result.status, BashToolExecutionStatus.invalidArguments);
    expect(result.stderr, contains('at most 20 PDF pages'));
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

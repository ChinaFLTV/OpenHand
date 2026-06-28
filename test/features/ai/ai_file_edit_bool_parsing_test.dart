import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_file_edit_bool_parsing_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Edit accepts replace_all encoded as text', () async {
    final file = await _seedFile(tempDir, 'edit.txt', 'foo foo');
    final result = await AiEditTool().execute(
      _context(
        toolName: 'Edit',
        args: <String, Object?>{
          'file_path': file.path,
          'old_string': 'foo',
          'new_string': 'bar',
          'replace_all': 'true',
        },
        previouslyReadFiles: <String>{file.path},
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(await file.readAsString(), 'bar bar');
  });

  test('MultiEdit accepts replace_all encoded as text', () async {
    final file = await _seedFile(tempDir, 'multi_edit.txt', 'foo foo');
    final result = await AiMultiEditTool().execute(
      _context(
        toolName: 'MultiEdit',
        args: <String, Object?>{
          'file_path': file.path,
          'edits': <Object?>[
            <String, Object?>{
              'old_string': 'foo',
              'new_string': 'bar',
              'replace_all': 'true',
            },
          ],
        },
        previouslyReadFiles: <String>{file.path},
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(await file.readAsString(), 'bar bar');
  });

  test('MultiEdit accepts edits encoded as JSON text', () async {
    final file = await _seedFile(tempDir, 'multi_edit_json.txt', 'alpha beta');
    final result = await AiMultiEditTool().execute(
      _context(
        toolName: 'MultiEdit',
        args: <String, Object?>{
          'file_path': file.path,
          'edits': jsonEncode(<Object?>[
            <String, Object?>{'old_string': 'alpha', 'new_string': 'gamma'},
          ]),
        },
        previouslyReadFiles: <String>{file.path},
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(await file.readAsString(), 'gamma beta');
  });

  test('ApplyFileDiffs accepts replace_all encoded as text', () async {
    final file = await _seedFile(tempDir, 'apply_diffs.txt', 'foo foo');
    final result = await AiApplyFileDiffsTool().execute(
      _context(
        toolName: 'ApplyFileDiffs',
        args: <String, Object?>{
          'diffs': <Object?>[
            <String, Object?>{
              'file_path': file.path,
              'hunks': <Object?>[
                <String, Object?>{
                  'old_string': 'foo',
                  'new_string': 'bar',
                  'replace_all': 'true',
                },
              ],
            },
          ],
        },
        previouslyReadFiles: <String>{file.path},
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(await file.readAsString(), 'bar bar');
  });

  test('ApplyFileDiffs accepts diffs and hunks encoded as JSON text', () async {
    final file = await _seedFile(tempDir, 'apply_diffs_json.txt', 'red blue');
    final result = await AiApplyFileDiffsTool().execute(
      _context(
        toolName: 'ApplyFileDiffs',
        args: <String, Object?>{
          'diffs': jsonEncode(<Object?>[
            <String, Object?>{
              'file_path': file.path,
              'hunks': jsonEncode(<Object?>[
                <String, Object?>{'old_string': 'blue', 'new_string': 'green'},
              ]),
            },
          ]),
        },
        previouslyReadFiles: <String>{file.path},
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(await file.readAsString(), 'red green');
  });
}

Future<File> _seedFile(Directory tempDir, String name, String content) async {
  final file = File(p.join(tempDir.path, name));
  await file.writeAsString(content);
  return file;
}

AiToolExecutionContext _context({
  required String toolName,
  required Map<String, Object?> args,
  Set<String> previouslyReadFiles = const <String>{},
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call',
      name: toolName,
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
    previouslyReadFiles: previouslyReadFiles,
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_apply_file_diffs_tool.dart';
import 'package:openhand/features/ai/tools/fs/ai_edit_tool.dart';
import 'package:openhand/features/ai/tools/fs/ai_multi_edit_tool.dart';

void main() {
  group('AiEditTool', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_edit_tool_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates a missing file when old_string is empty', () async {
      final file = File('${tempDir.path}/created.txt');

      final result = await AiEditTool().execute(
        _context(
          toolName: 'Edit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'old_string': '',
            'new_string': 'hello\n',
          },
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('Created'));
      expect(await file.readAsString(), 'hello\n');
    });

    test('replaces an existing empty file when old_string is empty', () async {
      final file = File('${tempDir.path}/empty.txt');
      await file.writeAsString('');

      final result = await AiEditTool().execute(
        _context(
          toolName: 'Edit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'old_string': '',
            'new_string': 'seed\n',
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(await file.readAsString(), 'seed\n');
    });

    test('preserves existing curly quote style during exact edit', () async {
      final file = File('${tempDir.path}/quotes.dart');
      await file.writeAsString('const title = \u201cHello\u201d;\n');

      final result = await AiEditTool().execute(
        _context(
          toolName: 'Edit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'old_string': 'const title = "Hello";',
            'new_string': 'const title = "World";',
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(await file.readAsString(), 'const title = \u201cWorld\u201d;\n');
    });

    test('matches LF edit strings while preserving CRLF files', () async {
      final file = File('${tempDir.path}/crlf.txt');
      await file.writeAsString('one\r\nalpha\r\nbeta\r\nend\r\n');

      final result = await AiEditTool().execute(
        _context(
          toolName: 'Edit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'old_string': 'alpha\nbeta',
            'new_string': 'gamma\ndelta',
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(await file.readAsString(), 'one\r\ngamma\r\ndelta\r\nend\r\n');
    });

    test(
      'rejects ambiguous single replacement and leaves file unchanged',
      () async {
        final file = File('${tempDir.path}/ambiguous.txt');
        await file.writeAsString('target\nkeep\ntarget\n');

        final result = await AiEditTool().execute(
          _context(
            toolName: 'Edit',
            arguments: <String, Object?>{
              'file_path': file.path,
              'old_string': 'target',
              'new_string': 'changed',
            },
            previouslyReadFiles: <String>{file.path},
          ),
        );

        expect(result.status.storageValue, 'invalid_arguments');
        expect(result.stderr, contains('matched multiple locations'));
        expect(await file.readAsString(), 'target\nkeep\ntarget\n');
      },
    );
  });

  group('AiMultiEditTool', () {
    test('preserves CRLF line endings after sequential edits', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_multi_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/crlf.txt');
      await file.writeAsString('alpha\r\nbeta\r\n');

      final result = await AiMultiEditTool().execute(
        _context(
          toolName: 'MultiEdit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'edits': <Object?>[
              <String, Object?>{'old_string': 'alpha', 'new_string': 'one'},
              <String, Object?>{'old_string': 'beta', 'new_string': 'two'},
            ],
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(await file.readAsString(), 'one\r\ntwo\r\n');
    });

    test('rejects edits that retarget a previous new_string', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_multi_edit_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');

      final result = await AiMultiEditTool().execute(
        _context(
          toolName: 'MultiEdit',
          arguments: <String, Object?>{
            'file_path': file.path,
            'edits': <Object?>[
              <String, Object?>{
                'old_string': 'alpha',
                'new_string': 'beta gamma',
              },
              <String, Object?>{'old_string': 'beta', 'new_string': 'delta'},
            ],
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('substring of a new_string'));
      expect(await file.readAsString(), 'alpha\n');
    });
  });

  group('AiApplyFileDiffsTool', () {
    test('rejects hunks that retarget a previous new_string', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_apply_file_diffs_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');

      final result = await AiApplyFileDiffsTool().execute(
        _context(
          toolName: 'ApplyFileDiffs',
          arguments: <String, Object?>{
            'diffs': <Object?>[
              <String, Object?>{
                'file_path': file.path,
                'hunks': <Object?>[
                  <String, Object?>{
                    'old_string': 'alpha',
                    'new_string': 'beta gamma',
                  },
                  <String, Object?>{
                    'old_string': 'beta',
                    'new_string': 'delta',
                  },
                ],
              },
            ],
          },
          previouslyReadFiles: <String>{file.path},
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('substring of a new_string'));
      expect(await file.readAsString(), 'alpha\n');
    });
  });
}

AiToolExecutionContext _context({
  required String toolName,
  required Map<String, Object?> arguments,
  Set<String> previouslyReadFiles = const <String>{},
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-test',
      name: toolName,
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: previouslyReadFiles,
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
  );
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_glob_tool.dart';

void main() {
  group('AiGlobTool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('openhand-glob-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns relative file paths and omits directories', () async {
      final srcDir = Directory('${tempDir.path}/src')..createSync();
      File('${srcDir.path}/main.dart').writeAsStringSync('void main() {}\n');
      Directory('${srcDir.path}/nested.dart').createSync();

      final result = await AiGlobTool().execute(
        _context(<String, Object?>{
          'pattern': '**/*.dart',
          'path': tempDir.path,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('src/main.dart'));
      expect(result.stdout, isNot(contains('nested.dart')));
      expect(result.stdout.split('\n').first.startsWith('/'), isFalse);
      expect(result.metadata['glob_result_count'], 1);
    });

    test('rejects file paths as search roots', () async {
      final file = File('${tempDir.path}/single.dart')
        ..writeAsStringSync('void main() {}\n');

      final result = await AiGlobTool().execute(
        _context(<String, Object?>{'pattern': '*.dart', 'path': file.path}),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('not a directory'));
    });

    test('sorts matches by modification time', () async {
      final oldFile = File('${tempDir.path}/old.dart')
        ..writeAsStringSync('void oldFile() {}\n');
      final newFile = File('${tempDir.path}/new.dart')
        ..writeAsStringSync('void newFile() {}\n');
      final middleFile = File('${tempDir.path}/middle.dart')
        ..writeAsStringSync('void middleFile() {}\n');
      oldFile.setLastModifiedSync(DateTime.utc(2024));
      middleFile.setLastModifiedSync(DateTime.utc(2024, 1, 2));
      newFile.setLastModifiedSync(DateTime.utc(2024, 1, 3));

      final result = await AiGlobTool().execute(
        _context(<String, Object?>{'pattern': '*.dart', 'path': tempDir.path}),
      );

      final resultLines = result.stdout
          .split('\n')
          .where((line) => line.endsWith('.dart'))
          .toList(growable: false);

      expect(result.status, BashToolExecutionStatus.success);
      expect(resultLines, hasLength(3));
      expect(resultLines[0], contains('old.dart'));
      expect(resultLines[1], contains('middle.dart'));
      expect(resultLines[2], contains('new.dart'));
    });

    test('caps broad results at Claude-style 100 matches', () async {
      for (var index = 0; index < 105; index++) {
        File(
          '${tempDir.path}/file_${index.toString().padLeft(3, '0')}.dart',
        ).writeAsStringSync('void f$index() {}\n');
      }

      final result = await AiGlobTool().execute(
        _context(<String, Object?>{'pattern': '*.dart', 'path': tempDir.path}),
      );

      final resultLines = result.stdout
          .split('\n')
          .where((line) => line.endsWith('.dart'))
          .toList(growable: false);

      expect(result.status, BashToolExecutionStatus.success);
      expect(resultLines, hasLength(100));
      expect(result.stdout, contains('Results are truncated'));
      expect(result.metadata['glob_result_truncated'], true);
      expect(result.metadata['glob_max_results'], 100);
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'glob-test',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'glob-call',
      name: 'Glob',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: true,
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

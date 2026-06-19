import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/search/ai_grep_tool.dart';

void main() {
  group('AiGrepTool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('openhand-grep-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('accepts Claude-style context alias for -C', () async {
      final file = File('${tempDir.path}/context.txt')
        ..writeAsStringSync('before\nneedle\nafter\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'content',
          'context': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('before'));
      expect(result.stdout, contains('needle'));
      expect(result.stdout, contains('after'));
    });

    test('applies offset before head_limit', () async {
      final file = File('${tempDir.path}/matches.txt')
        ..writeAsStringSync('match one\nmatch two\nmatch three\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'match',
          'path': file.path,
          'output_mode': 'content',
          'offset': 1,
          'head_limit': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('match two'));
      expect(result.stdout, isNot(contains('match one')));
      expect(result.stdout, isNot(contains('match three')));
    });

    test('defaults to Claude-style 250 result cap', () async {
      final file = File('${tempDir.path}/many.txt')
        ..writeAsStringSync(
          List<String>.generate(
            260,
            (index) => 'needle-${(index + 1).toString().padLeft(3, '0')}',
          ).join('\n'),
        );

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'content',
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('needle-250'));
      expect(result.stdout, isNot(contains('needle-251')));
      expect(result.stdout, contains('pagination = limit: 250'));
      expect(result.metadata['grep_head_limit_defaulted'], isTrue);
      expect(result.metadata['grep_applied_limit'], 250);
    });

    test('head_limit zero keeps Grep output unlimited', () async {
      final file = File('${tempDir.path}/unlimited.txt')
        ..writeAsStringSync(
          List<String>.generate(
            260,
            (index) => 'needle-${(index + 1).toString().padLeft(3, '0')}',
          ).join('\n'),
        );

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'content',
          'head_limit': 0,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('needle-260'));
      expect(result.stdout, isNot(contains('pagination =')));
      expect(result.metadata['grep_head_limit'], 0);
      expect(result.metadata['grep_applied_limit'], isNull);
    });

    test('content mode shows line numbers by default', () async {
      final file = File('${tempDir.path}/lines.txt')
        ..writeAsStringSync('before\nneedle\nafter\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'content',
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('2:needle'));
    });

    test('searches hidden files while excluding VCS directories', () async {
      File('${tempDir.path}/.env').writeAsStringSync('OPENHAND_NEEDLE=1\n');
      final gitDir = Directory('${tempDir.path}/.git');
      gitDir.createSync();
      File('${gitDir.path}/config').writeAsStringSync('OPENHAND_NEEDLE=2\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'OPENHAND_NEEDLE',
          'path': tempDir.path,
          'output_mode': 'files_with_matches',
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('.env'));
      expect(result.stdout, isNot(contains('.git')));
    });

    test('passes dash-prefixed patterns through -e', () async {
      final file = File('${tempDir.path}/flags.txt')
        ..writeAsStringSync('--openhand-flag\nplain\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': '--openhand-flag',
          'path': file.path,
          'output_mode': 'content',
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('--openhand-flag'));
    });

    test('splits comma and space separated glob patterns', () async {
      File('${tempDir.path}/one.dart').writeAsStringSync('OPENHAND_SPLIT\n');
      File('${tempDir.path}/two.md').writeAsStringSync('OPENHAND_SPLIT\n');
      File('${tempDir.path}/three.txt').writeAsStringSync('OPENHAND_SPLIT\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'OPENHAND_SPLIT',
          'path': tempDir.path,
          'glob': '*.dart,*.md',
          'output_mode': 'files_with_matches',
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('one.dart'));
      expect(result.stdout, contains('two.md'));
      expect(result.stdout, isNot(contains('three.txt')));
    });

    test('rejects unsupported output modes', () async {
      final file = File('${tempDir.path}/mode.txt')
        ..writeAsStringSync('needle\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'lines',
        }),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('output_mode'));
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'grep-test',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'grep-call',
      name: 'Grep',
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

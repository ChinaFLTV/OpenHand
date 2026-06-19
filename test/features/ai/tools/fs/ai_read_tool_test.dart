import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/fs/ai_file_tracker_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_read_tool.dart';

void main() {
  group('AiReadTool', () {
    test('offset is interpreted as a 1-based starting line', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\ngamma\ndelta\n');

      final result = await AiReadTool().execute(
        AiToolExecutionContext(
          sessionId: 'test-session',
          catalog: const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          ),
          toolCall: AiToolCall(
            id: 'read-offset',
            name: 'Read',
            arguments: jsonEncode(<String, Object?>{
              'file_path': file.path,
              'offset': 2,
              'limit': 2,
            }),
          ),
          decodedArguments: <String, Object?>{
            'file_path': file.path,
            'offset': 2,
            'limit': 2,
          },
          model: _testModel,
          previouslyReadFiles: <String>{},
          denyCommandRules: const <Never>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('   2\tbeta'));
      expect(result.stdout, contains('   3\tgamma'));
      expect(result.stdout, isNot(contains('alpha')));
      expect(result.stdout, isNot(contains('delta')));
    });

    test('returns unchanged stub for repeated same-range reads', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\ngamma\n');
      final tracker = AiFileTrackerService();
      final tool = AiReadTool();

      final first = await tool.execute(
        _context(
          id: 'read-first',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );
      final second = await tool.execute(
        _context(
          id: 'read-second',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );

      expect(first.status.storageValue, 'success');
      expect(first.stdout, contains('alpha'));
      expect(second.status.storageValue, 'success');
      expect(second.stdout, contains('File unchanged since last read'));
      expect(second.stdout, isNot(contains('alpha')));
      expect(second.metadata['read_file_unchanged'], isTrue);
    });

    test('re-reads content after same-range file changes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_read_tool_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\nbeta\n');
      final tracker = AiFileTrackerService();
      final tool = AiReadTool();

      await tool.execute(
        _context(
          id: 'read-before-change',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );
      await file.writeAsString('delta\nepsilon\n');

      final result = await tool.execute(
        _context(
          id: 'read-after-change',
          filePath: file.path,
          offset: 1,
          limit: 2,
          fileTracker: tracker,
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('delta'));
      expect(result.stdout, isNot(contains('File unchanged since last read')));
    });
  });
}

AiToolExecutionContext _context({
  required String id,
  required String filePath,
  required int offset,
  required int limit,
  required AiFileTrackerService fileTracker,
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: id,
      name: 'Read',
      arguments: jsonEncode(<String, Object?>{
        'file_path': filePath,
        'offset': offset,
        'limit': limit,
      }),
    ),
    decodedArguments: <String, Object?>{
      'file_path': filePath,
      'offset': offset,
      'limit': limit,
    },
    model: _testModel,
    previouslyReadFiles: <String>{},
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: <String, Object?>{'file_tracker': fileTracker},
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

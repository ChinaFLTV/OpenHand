import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/fs/ai_file_history_service.dart';
import 'package:openhand/features/ai/service/fs/ai_file_tracker_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';
import 'package:openhand/features/ai/tools/fs/ai_write_tool.dart';

void main() {
  group('AiWriteTool', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_write_tool_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rejects overwrite when file changed after tracked read', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();
      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      await file.writeAsString('omega\n');
      await file.setLastModified(readModified);

      final result = await AiWriteTool().execute(
        _context(
          filePath: file.path,
          content: 'replacement\n',
          previouslyReadFiles: <String>{file.path},
          fileTracker: tracker,
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('Re-read the file before editing'));
      expect(await file.readAsString(), 'omega\n');
    });

    test('rechecks stale state immediately before writing', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();
      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      final result = await AiWriteTool().execute(
        _context(
          filePath: file.path,
          content: 'replacement\n',
          previouslyReadFiles: <String>{file.path},
          fileTracker: tracker,
          fileHistory: _MutatingFileHistoryService(
            content: 'external\n',
            modified: readModified,
          ),
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('Re-read the file before editing'));
      expect(await file.readAsString(), 'external\n');
    });

    test('guard rejects new-file write when target appears first', () async {
      final file = File('${tempDir.path}/new.txt');
      await file.writeAsString('external\n');

      final result = await AiToolUtils.writeTextFileWithMutationGuard(
        toolName: 'Write',
        file: file,
        content: 'replacement\n',
        previouslyReadFiles: const <String>{},
        requireExistingFileRead: false,
      );

      expect(result, isNotNull);
      expect(result!.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('target now exists'));
      expect(await file.readAsString(), 'external\n');
    });
  });
}

AiToolExecutionContext _context({
  required String filePath,
  required String content,
  required Set<String> previouslyReadFiles,
  required AiFileTrackerService fileTracker,
  AiFileHistoryService? fileHistory,
}) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'write-stale',
      name: 'Write',
      arguments: jsonEncode(<String, Object?>{
        'file_path': filePath,
        'content': content,
      }),
    ),
    decodedArguments: <String, Object?>{
      'file_path': filePath,
      'content': content,
    },
    model: _testModel,
    previouslyReadFiles: previouslyReadFiles,
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: <String, Object?>{
      'file_tracker': fileTracker,
      if (fileHistory != null) 'file_history': fileHistory,
    },
  );
}

class _MutatingFileHistoryService extends AiFileHistoryService {
  _MutatingFileHistoryService({required this.content, required this.modified});

  final String content;
  final DateTime modified;

  @override
  Future<String?> saveVersion({
    required String filePath,
    required String sessionId,
    String? toolCallId,
  }) async {
    final file = File(filePath);
    await file.writeAsString(content);
    await file.setLastModified(modified);
    return 'mutated-during-history';
  }
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

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
import 'package:openhand/features/ai/tools/fs/ai_delete_file_tool.dart';

void main() {
  group('AiDeleteFileTool', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory(
        '${Directory.current.path}/.tmp_openhand_delete_file_tool_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      await tempDir.create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'deletes relative target_file alias from the working directory',
      () async {
        final originalWorkingDirectory = Directory.current.path;
        addTearDown(() {
          Directory.current = originalWorkingDirectory;
        });
        Directory.current = tempDir.path;

        final file = File('${tempDir.path}/sample.txt');
        await file.writeAsString('alpha\n');
        final tracker = AiFileTrackerService();
        await tracker.recordFileRead(file.path);

        final result = await AiDeleteFileTool().execute(
          _context(
            filePath: 'sample.txt',
            pathArgumentName: 'target_file',
            previouslyReadFiles: <String>{file.path},
            fileTracker: tracker,
          ),
        );

        expect(result.status.storageValue, 'success');
        expect(await file.exists(), isFalse);
        expect(result.metadata['file_mutation_path'], file.path);
      },
    );

    test('rejects delete when file changed after tracked read', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();
      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      await file.writeAsString('omega\n');
      await file.setLastModified(readModified);

      final result = await AiDeleteFileTool().execute(
        _context(
          filePath: file.path,
          previouslyReadFiles: <String>{file.path},
          fileTracker: tracker,
        ),
      );

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('Re-read the file before editing'));
      expect(await file.readAsString(), 'omega\n');
    });

    test('deletes after tracked read and clears file tracking', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();
      await tracker.recordFileRead(file.path);

      final result = await AiDeleteFileTool().execute(
        _context(
          filePath: file.path,
          previouslyReadFiles: <String>{file.path},
          fileTracker: tracker,
          fileHistory: _RecordingFileHistoryService(),
        ),
      );

      expect(result.status.storageValue, 'success');
      expect(await file.exists(), isFalse);
      expect(
        result.metadata['file_mutation_history_version_id'],
        'history-before-delete',
      );

      await file.writeAsString('replacement\n');
      expect(await tracker.validateSafeToWrite(file.path), isNull);
    });

    test('rechecks stale state immediately before deleting', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = AiFileTrackerService();
      await tracker.recordFileRead(file.path);
      final readModified = (await file.stat()).modified;

      final result = await AiDeleteFileTool().execute(
        _context(
          filePath: file.path,
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

    test('serializes delete and write final guards per file path', () async {
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('alpha\n');
      final tracker = _ObservingFileTrackerService(
        delay: const Duration(milliseconds: 50),
      );
      await tracker.recordFileRead(file.path);

      final results = await Future.wait(<Future<AiToolExecutionResult?>>[
        AiToolUtils.deleteFileWithMutationGuard(
          toolName: 'DeleteFile',
          file: file,
          previouslyReadFiles: <String>{file.path},
          fileTracker: tracker,
        ),
        AiToolUtils.writeTextFileWithMutationGuard(
          toolName: 'Write',
          file: file,
          content: 'replacement\n',
          previouslyReadFiles: <String>{file.path},
          requireExistingFileRead: true,
          fileTracker: tracker,
        ),
      ]);

      expect(tracker.maxConcurrentValidations, 1);
      expect(results, everyElement(isNull));
      if (await file.exists()) {
        expect(await file.readAsString(), 'replacement\n');
      }
    });
  });
}

AiToolExecutionContext _context({
  required String filePath,
  String pathArgumentName = 'file_path',
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
      id: 'delete-stale',
      name: 'DeleteFile',
      arguments: jsonEncode(<String, Object?>{pathArgumentName: filePath}),
    ),
    decodedArguments: <String, Object?>{pathArgumentName: filePath},
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

class _RecordingFileHistoryService extends AiFileHistoryService {
  @override
  Future<String?> saveVersion({
    required String filePath,
    required String sessionId,
    String? toolCallId,
  }) async {
    return 'history-before-delete';
  }
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

class _ObservingFileTrackerService extends AiFileTrackerService {
  _ObservingFileTrackerService({required this.delay});

  final Duration delay;
  int _activeValidations = 0;
  int maxConcurrentValidations = 0;

  @override
  Future<String?> validateSafeToWrite(String filePath) async {
    _activeValidations += 1;
    if (_activeValidations > maxConcurrentValidations) {
      maxConcurrentValidations = _activeValidations;
    }
    try {
      await Future<void>.delayed(delay);
      return await super.validateSafeToWrite(filePath);
    } finally {
      _activeValidations -= 1;
    }
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

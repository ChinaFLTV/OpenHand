import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_file_mutation_ledger.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiFileMutationLedger undone state', () {
    late Directory tempDir;
    late String root;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('openhand-ledger-test-');
      root = p.join(tempDir.path, 'file_history');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pruning versions does not materialize empty state.json', () async {
      final ledger = AiFileMutationLedger(rootDirectoryOverride: root);
      const sessionId = 'session-a';
      final filePath = p.join(tempDir.path, 'work.txt');

      await ledger.recordMutation(
        sessionId: sessionId,
        toolCallId: 'tool-1',
        toolName: 'Write',
        filePath: filePath,
        kind: FileMutationKind.modify,
        beforeContent: 'v0',
        afterContent: 'v1',
      );
      await ledger.recordMutation(
        sessionId: sessionId,
        toolCallId: 'tool-2',
        toolName: 'Edit',
        filePath: filePath,
        kind: FileMutationKind.modify,
        beforeContent: 'v1',
        afterContent: 'v2',
      );

      final state = File(p.join(root, 'sessions', sessionId, 'state.json'));
      expect(await state.exists(), isFalse);

      final removed = await ledger.pruneToMaxVersionsPerFile(1);

      expect(removed, 1);
      expect(await state.exists(), isFalse);
      expect(await ledger.recordsForSession(sessionId), hasLength(1));
    });

    test('redo removes state.json when undone set becomes empty', () async {
      final ledger = AiFileMutationLedger(rootDirectoryOverride: root);
      const sessionId = 'session-b';
      final filePath = p.join(tempDir.path, 'work.txt');

      final first = await ledger.recordMutation(
        sessionId: sessionId,
        toolCallId: 'tool-1',
        toolName: 'Write',
        filePath: filePath,
        kind: FileMutationKind.create,
        beforeContent: null,
        afterContent: 'v1',
      );
      final second = await ledger.recordMutation(
        sessionId: sessionId,
        toolCallId: 'tool-2',
        toolName: 'Edit',
        filePath: filePath,
        kind: FileMutationKind.modify,
        beforeContent: 'v1',
        afterContent: 'v2',
      );
      expect(first, isNotNull);
      expect(second, isNotNull);

      final state = File(p.join(root, 'sessions', sessionId, 'state.json'));
      final undo = await ledger.undoRecord(
        sessionId: sessionId,
        recordId: first!.recordId,
      );
      expect(undo.success, isTrue);
      expect(await state.exists(), isTrue);

      final redoSecond = await ledger.redoRecord(
        sessionId: sessionId,
        recordId: second!.recordId,
      );
      expect(redoSecond.success, isTrue);
      expect(await state.exists(), isTrue);

      final redoFirst = await ledger.redoRecord(
        sessionId: sessionId,
        recordId: first.recordId,
      );
      expect(redoFirst.success, isTrue);
      expect(await state.exists(), isFalse);
    });
  });
}

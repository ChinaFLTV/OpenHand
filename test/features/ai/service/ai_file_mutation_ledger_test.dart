// 2026-05-03 — 阶段①：文件变动 ledger 基础回归测试。
//
// 覆盖：recordMutation 双快照 + 撤销 → 磁盘回到 before；级联：撤销 B
// 时 C/D 同文件记录被自动标 undone；redo 单条只清自己的 undone；
// 内容寻址去重；clearSession + gcUnreferencedBlobs 协同回收 blob。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_file_mutation_ledger.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late AiFileMutationLedger ledger;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('openhand_ledger_test_');
    ledger = AiFileMutationLedger(rootDirectoryOverride: tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> stagingFile(String name, String body) async {
    final f = File(p.join(tmp.path, 'workspace', name));
    await f.parent.create(recursive: true);
    await f.writeAsString(body);
    return f;
  }

  test('recordMutation 持久化 before/after 并允许 undo 恢复 before', () async {
    final f = await stagingFile('foo.txt', 'A');
    final r = await ledger.recordMutation(
      sessionId: 's1',
      toolCallId: 'tc1',
      toolName: 'Write',
      filePath: f.path,
      kind: FileMutationKind.modify,
      beforeContent: 'A',
      afterContent: 'B',
    );
    expect(r, isNotNull);

    // 模拟工具已经把磁盘改成 'B'
    await f.writeAsString('B');
    expect(await f.readAsString(), 'B');

    final outcome = await ledger.undoRecord(sessionId: 's1', recordId: r!.recordId);
    expect(outcome.success, isTrue, reason: outcome.errorMessage);
    expect(await f.readAsString(), 'A');
  });

  test('撤销 B 时 C、D 同文件记录被级联标记 undone', () async {
    final f = await stagingFile('foo.txt', 'A');
    final rA = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tcA', toolName: 'Edit',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'A', afterContent: 'B',
    );
    final rB = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tcB', toolName: 'Edit',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'B', afterContent: 'C',
    );
    final rC = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tcC', toolName: 'Edit',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'C', afterContent: 'D',
    );
    await f.writeAsString('D');

    final outcome = await ledger.undoRecord(sessionId: 's1', recordId: rB!.recordId);
    expect(outcome.success, isTrue);
    expect(await f.readAsString(), 'B'); // B.before == 'B'

    final viewA = await ledger.viewForRecord(sessionId: 's1', recordId: rA!.recordId);
    final viewB = await ledger.viewForRecord(sessionId: 's1', recordId: rB.recordId);
    final viewC = await ledger.viewForRecord(sessionId: 's1', recordId: rC!.recordId);
    expect(viewA!.canUndo, isTrue);
    expect(viewB!.directlyUndone || viewB.cascadeUndone, isTrue);
    expect(viewC!.cascadeUndone, isTrue, reason: 'C 应被级联标记');
    expect(viewC.canRedo, isTrue);
  });

  test('redo 仅恢复自身 after 内容', () async {
    final f = await stagingFile('foo.txt', 'X');
    final r = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tc', toolName: 'Write',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'X', afterContent: 'Y',
    );
    await f.writeAsString('Y');
    await ledger.undoRecord(sessionId: 's1', recordId: r!.recordId);
    expect(await f.readAsString(), 'X');

    final redo = await ledger.redoRecord(sessionId: 's1', recordId: r.recordId);
    expect(redo.success, isTrue);
    expect(await f.readAsString(), 'Y');

    final view = await ledger.viewForRecord(sessionId: 's1', recordId: r.recordId);
    expect(view!.canUndo, isTrue);
  });

  test('blob 内容寻址去重 + clearSession 后 gc 回收', () async {
    final f = await stagingFile('foo.txt', 'same');
    await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tc1', toolName: 'Write',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'same', afterContent: 'same',
    );
    await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tc2', toolName: 'Write',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'same', afterContent: 'same',
    );
    final blobsDir = Directory(p.join(tmp.path, 'blobs'));
    int countBlobFiles() {
      var n = 0;
      for (final e in blobsDir.listSync(recursive: true)) {
        if (e is File) n++;
      }
      return n;
    }
    expect(countBlobFiles(), 1, reason: '同内容应去重');
    await ledger.clearSession('s1');
    expect(countBlobFiles(), 0, reason: 'gc 回收孤儿 blob');
  });

  test('删除类记录：undo 写回原内容、redo 删除文件', () async {
    final f = await stagingFile('foo.txt', 'orig');
    final r = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tc', toolName: 'DeleteFile',
      filePath: f.path, kind: FileMutationKind.delete,
      beforeContent: 'orig', afterContent: null,
    );
    await f.delete();
    final undo = await ledger.undoRecord(sessionId: 's1', recordId: r!.recordId);
    expect(undo.success, isTrue);
    expect(await f.readAsString(), 'orig');
    final redo = await ledger.redoRecord(sessionId: 's1', recordId: r.recordId);
    expect(redo.success, isTrue);
    expect(await f.exists(), isFalse);
  });

  test('blob 缺失时 undo 优雅失败而非抛出', () async {
    final f = await stagingFile('foo.txt', 'A');
    final r = await ledger.recordMutation(
      sessionId: 's1', toolCallId: 'tc', toolName: 'Edit',
      filePath: f.path, kind: FileMutationKind.modify,
      beforeContent: 'A', afterContent: 'B',
    );
    // 故意破坏 blob
    final blobsDir = Directory(p.join(tmp.path, 'blobs'));
    for (final e in blobsDir.listSync(recursive: true)) {
      if (e is File) e.deleteSync();
    }
    final outcome = await ledger.undoRecord(sessionId: 's1', recordId: r!.recordId);
    expect(outcome.success, isFalse);
    expect(outcome.errorMessage, contains('blob'));
  });
}

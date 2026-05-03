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

  // ─── 阶段⑥a 配置 + 自动修剪 ───
  test('LedgerConfig fromJson/toJson 双向 + clamp 越界值', () {
    final raw = const LedgerConfig(maxVersionsPerFile: 999, autoCleanupDays: -5)
        .toJson();
    final restored = LedgerConfig.fromJson(raw);
    expect(restored.maxVersionsPerFile,
        equals(LedgerConfig.maxMaxVersionsPerFile));
    expect(restored.autoCleanupDays,
        equals(LedgerConfig.minAutoCleanupDays));

    final mid = LedgerConfig.fromJson(<String, Object?>{
      'max_versions_per_file': 5,
      'auto_cleanup_days': 7,
    });
    expect(mid.maxVersionsPerFile, 5);
    expect(mid.autoCleanupDays, 7);
  });

  test('saveConfig 落盘后 loadConfig 取回相同值', () async {
    await ledger.saveConfig(
      const LedgerConfig(maxVersionsPerFile: 4, autoCleanupDays: 14),
    );
    // 新实例从同一 root 读
    final ledger2 = AiFileMutationLedger(rootDirectoryOverride: tmp.path);
    final cfg = await ledger2.loadConfig();
    expect(cfg.maxVersionsPerFile, 4);
    expect(cfg.autoCleanupDays, 14);
  });

  test('recordMutation 后 _trimSessionFileVersions 自动截断到 maxVersionsPerFile',
      () async {
    final f = await stagingFile('foo.txt', '0');
    await ledger.saveConfig(
      const LedgerConfig(maxVersionsPerFile: 3, autoCleanupDays: 0),
    );
    for (var i = 0; i < 6; i++) {
      await ledger.recordMutation(
        sessionId: 's1',
        toolCallId: 'tc$i',
        toolName: 'Edit',
        filePath: f.path,
        kind: FileMutationKind.modify,
        beforeContent: '$i',
        afterContent: '${i + 1}',
      );
    }
    final remaining = await ledger.recordsForSession('s1');
    expect(remaining.length, 3,
        reason: '只应保留最近 3 条同文件记录');
  });

  // ─── 阶段⑦f unifiedDiffLineSummary 单测（FileMutationCard 复制按钮所用）───
  test('unifiedDiffLineSummary 完全相同 → 全部 ` ` 行', () {
    final out = unifiedDiffLineSummary('a\nb\nc', 'a\nb\nc');
    expect(out.split('\n'), [' a', ' b', ' c']);
  });

  test('unifiedDiffLineSummary 中间一行修改 → -/+ 配对', () {
    final out = unifiedDiffLineSummary('a\nb\nc', 'a\nB\nc');
    expect(out.split('\n'), [' a', '-b', '+B', ' c']);
  });

  test('unifiedDiffLineSummary 仅新增 → 末尾全 +', () {
    final out = unifiedDiffLineSummary('a', 'a\nb\nc');
    expect(out.split('\n'), [' a', '+b', '+c']);
  });

  test('unifiedDiffLineSummary 仅删除 → 末尾全 -', () {
    final out = unifiedDiffLineSummary('a\nb\nc', 'a');
    expect(out.split('\n'), [' a', '-b', '-c']);
  });

  test('unifiedDiffLineSummary 空 before → 全部 +; 空 after → 全部 -', () {
    expect(unifiedDiffLineSummary('', 'x\ny').split('\n'), ['-', '+x', '+y']);
    // 注意：'' split('\n') → ['']，所以会产出一个 ` ` 空行配对
    expect(unifiedDiffLineSummary('x\ny', '').split('\n'), ['-x', '+', '-y']);
  });

  // ─── 阶段⑨d unifiedDiffLineSummary 大文本限压 ───
  test('unifiedDiffLineSummary 任一侧超过 maxBytes → 占位摘要 + 字节数', () {
    final huge = 'a' * 600;
    final out = unifiedDiffLineSummary(huge, 'b', maxBytes: 256);
    expect(out, contains('<file too large for inline diff'));
    expect(out, contains('before=600B'));
    expect(out, contains('after=1B'));
    // 不应出现完整逐行 + / - 列表
    expect(out.contains('\n'), isFalse);
  });

  test('unifiedDiffLineSummary 占位摘要带 sha 短前缀', () {
    final huge = 'x' * 1024;
    final out = unifiedDiffLineSummary(
      huge,
      '${huge}y',
      maxBytes: 512,
      beforeSha: 'abcdef0123456789aabbcc',
      afterSha: 'ffeeddccbbaa9988776655',
    );
    expect(out, contains('sha=abcdef012345'));
    expect(out, contains('sha=ffeeddccbbaa'));
  });

  test('unifiedDiffLineSummary 双侧均小 → 仍走完整逐行模式', () {
    final out = unifiedDiffLineSummary('a\nb', 'a\nB', maxBytes: 1024);
    expect(out.split('\n'), [' a', '-b', '+B']);
  });

  // ─── 阶段⑪d：清理 pipeline 集成测试 ───
  // pruneOlderThan + pruneToMaxVersionsPerFile + gcUnreferencedBlobs 串
  // 起来跑一遍：模拟跨会话 / 多文件 / 多版本，最后断言：
  //   1. 旧 session 目录被删除；
  //   2. 每个 (session,file) 只剩最近 N 条；
  //   3. blobs/ 下没有任何记录引用的旧 blob 都被回收。
  test('集成：pruneOlderThan → pruneToMaxVersionsPerFile → gcUnreferencedBlobs',
      () async {
    final fooA = await stagingFile('a.txt', 'A0');
    final fooB = await stagingFile('b.txt', 'B0');

    // session "old" — 5 条 a.txt 改动 + 2 条 b.txt 改动；待会儿改 mtime
    // 让它跨过 retention cutoff。
    for (int i = 0; i < 5; i++) {
      final next = 'A${i + 1}';
      await ledger.recordMutation(
        sessionId: 'old',
        toolCallId: 'old-a-$i',
        toolName: 'Edit',
        filePath: fooA.path,
        kind: FileMutationKind.modify,
        beforeContent: 'A$i',
        afterContent: next,
      );
      await fooA.writeAsString(next);
    }
    for (int i = 0; i < 2; i++) {
      final next = 'B${i + 1}';
      await ledger.recordMutation(
        sessionId: 'old',
        toolCallId: 'old-b-$i',
        toolName: 'Edit',
        filePath: fooB.path,
        kind: FileMutationKind.modify,
        beforeContent: 'B$i',
        afterContent: next,
      );
      await fooB.writeAsString(next);
    }

    // session "fresh" — 6 条 a.txt 改动（待会儿 prune 到 max=3）。
    await fooA.writeAsString('Z0');
    for (int i = 0; i < 6; i++) {
      final next = 'Z${i + 1}';
      await ledger.recordMutation(
        sessionId: 'fresh',
        toolCallId: 'fresh-a-$i',
        toolName: 'Edit',
        filePath: fooA.path,
        kind: FileMutationKind.modify,
        beforeContent: 'Z$i',
        afterContent: next,
      );
      await fooA.writeAsString(next);
    }

    // 预条件：blobs 目录中 sha 集合 = old + fresh 全部条目的 before/after 并集。
    final oldRecords = await ledger.recordsForSession('old');
    final freshRecords = await ledger.recordsForSession('fresh');
    expect(oldRecords.length, 7);
    expect(freshRecords.length, 6);

    // 把 old session 目录的 mtime 倒推到 30 天前。
    final oldDir = Directory(
      p.join(tmp.path, 'sessions', 'old'),
    );
    expect(await oldDir.exists(), isTrue);
    // Dart 没有跨平台 utime API；走 shell `touch -t` 兜底。
    final result = await Process.run('touch', [
      '-t',
      _mtimeStamp(DateTime.now().subtract(const Duration(days: 30))),
      oldDir.path,
    ]);
    expect(result.exitCode, 0);

    // ── Step 1：retention=14 天 → 删 old，留 fresh
    final removedSessions =
        await ledger.pruneOlderThan(const Duration(days: 14));
    expect(removedSessions, 1);
    expect(await oldDir.exists(), isFalse);
    expect(
      Directory(p.join(tmp.path, 'sessions', 'fresh')).existsSync(),
      isTrue,
    );

    // ── Step 2：每文件每会话最多保留 3 条
    final removedRecords = await ledger.pruneToMaxVersionsPerFile(3);
    expect(removedRecords, 3); // fresh: 6 → 3
    final survivors = await ledger.recordsForSession('fresh');
    expect(survivors.length, 3);
    // 应保留最新 3 条（按 createdAt 倒序）
    final survivorAfters =
        survivors.map((r) => r.afterSha).whereType<String>().toSet();
    expect(survivorAfters, hasLength(3));

    // ── Step 3：再来一轮 gc（pipeline 步骤都已隐式调过，这里显式再跑一次
    //          确保幂等且 blobs 集合 = 现存 ledger 引用集合）。
    await ledger.gcUnreferencedBlobs();

    final blobsRoot = Directory(p.join(tmp.path, 'blobs'));
    final remainingShas = <String>{};
    if (await blobsRoot.exists()) {
      await for (final shard in blobsRoot.list()) {
        if (shard is! Directory) continue;
        await for (final blob in shard.list()) {
          if (blob is! File) continue;
          remainingShas.add(p.basenameWithoutExtension(blob.path));
        }
      }
    }
    final referenced = <String>{};
    for (final r in survivors) {
      if (r.beforeSha != null) referenced.add(r.beforeSha!);
      if (r.afterSha != null) referenced.add(r.afterSha!);
    }
    // 引用集合 ⊆ 磁盘集合，且磁盘集合不含未引用 sha。
    expect(referenced.difference(remainingShas), isEmpty,
        reason: '所有引用的 blob 都应保留');
    expect(remainingShas.difference(referenced), isEmpty,
        reason: '所有未被引用的 blob 都应被 gc 掉');
  });

  test('clearSessionsExcept 保留白名单会话并 gc 释放孤儿 blob', () async {
    final f = await stagingFile('only.txt', 'a');
    await ledger.recordMutation(
      sessionId: 'keep',
      toolCallId: 'k1',
      toolName: 'Edit',
      filePath: f.path,
      kind: FileMutationKind.modify,
      beforeContent: 'a',
      afterContent: 'b',
    );
    await ledger.recordMutation(
      sessionId: 'drop',
      toolCallId: 'd1',
      toolName: 'Edit',
      filePath: f.path,
      kind: FileMutationKind.modify,
      beforeContent: 'b',
      afterContent: 'c',
    );

    final removed = await ledger.clearSessionsExcept({'keep'});
    expect(removed, 1);
    expect(
      Directory(p.join(tmp.path, 'sessions', 'drop')).existsSync(),
      isFalse,
    );
    expect(
      Directory(p.join(tmp.path, 'sessions', 'keep')).existsSync(),
      isTrue,
    );

    // drop 独有的 sha=hash('c') 应该被回收
    final keepRecords = await ledger.recordsForSession('keep');
    final keptShas = <String>{
      for (final r in keepRecords) ...[
        if (r.beforeSha != null) r.beforeSha!,
        if (r.afterSha != null) r.afterSha!,
      ],
    };
    final blobsRoot = Directory(p.join(tmp.path, 'blobs'));
    final remainingShas = <String>{};
    await for (final shard in blobsRoot.list()) {
      if (shard is! Directory) continue;
      await for (final blob in shard.list()) {
        if (blob is! File) continue;
        remainingShas.add(p.basenameWithoutExtension(blob.path));
      }
    }
    expect(remainingShas, equals(keptShas));
  });
}

/// `touch -t` 期望的 stamp 格式：CCYYMMDDhhmm.SS
String _mtimeStamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}${two(dt.hour)}${two(dt.minute)}.${two(dt.second)}';
}

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/fs/ai_file_history_service.dart';
import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/fs/ai_file_tracker_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 跨文件批量 hunk 应用工具。把多个 MultiEdit 操作合成单次调用：
/// 一次提交可以包含 N 个文件、每个文件 M 个 hunk。
///
/// 与 [AiMultiEditTool] 的差异：
/// - MultiEdit 一次只能改 1 个文件；ApplyFileDiffs 改多个。
/// - 计划阶段 → 确认阶段 → 写入阶段：任一 hunk 不匹配或确认被拒，整体不写入。
/// - 写入阶段若中途失败，会尽力把已写文件回滚到原始内容。
/// - 用于跨文件的小规模重构（重命名 / 接口签名调整 / 同步配置）。
///
/// 输入 schema：
/// ```json
/// {
///   "diffs": [
///     {
///       "file_path": "lib/foo.dart",
///       "hunks": [
///         {"old_string": "...", "new_string": "...", "replace_all": false}
///       ]
///     }
///   ]
/// }
/// ```
class AiApplyFileDiffsTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.applyFileDiffs;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final diffs = args['diffs'];
    if (diffs is! List || diffs.isEmpty) {
      return AiToolUtils.invalidResult(
        'ApplyFileDiffs',
        'ApplyFileDiffs requires a non-empty diffs array.',
      );
    }
    if (diffs.length > 32) {
      return AiToolUtils.invalidResult(
        'ApplyFileDiffs',
        'ApplyFileDiffs supports at most 32 files per call (got ${diffs.length}).',
      );
    }

    final fileTracker =
        context.metadata['file_tracker'] as AiFileTrackerService?;
    final fileHistory =
        context.metadata['file_history'] as AiFileHistoryService?;
    final mutationLedger =
        context.metadata['mutation_ledger'] as AiFileMutationLedger?;

    // ── 阶段 1：解析 + 内存中应用所有 hunk，发现不匹配立即整体失败 ──
    final plans = <_FileDiffPlan>[];
    final seenFilePaths = <String>{};
    for (var i = 0; i < diffs.length; i++) {
      final raw = diffs[i];
      if (raw is! Map) {
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'diffs[$i] must be an object with file_path + hunks.',
        );
      }
      final entry = Map<String, Object?>.from(raw);
      final rawPath = '${entry['file_path'] ?? ''}'.trim();
      if (rawPath.isEmpty) {
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'diffs[$i] missing file_path.',
        );
      }
      final filePath = AiToolUtils.resolvePath(rawPath);
      if (!seenFilePaths.add(filePath)) {
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'diffs[$i] duplicates file_path already planned in this call: $filePath',
        );
      }
      final hunks = entry['hunks'];
      if (hunks is! List || hunks.isEmpty) {
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'diffs[$i] (file=$filePath) requires non-empty hunks array.',
        );
      }
      final file = File(filePath);
      final exists = await file.exists();

      final readValidation = await AiToolUtils.validateReadBeforeMutation(
        toolName: 'ApplyFileDiffs',
        filePath: filePath,
        previouslyReadFiles: context.previouslyReadFiles,
        requireExistingFileRead: exists,
        fileTracker: fileTracker,
      );
      if (readValidation != null) return readValidation;

      final AiEditableTextSnapshot editableText;
      if (exists) {
        try {
          editableText = await AiToolUtils.readEditableTextFile(file);
        } on FormatException {
          return AiToolUtils.invalidResult(
            'ApplyFileDiffs',
            'File does not appear to be a valid text file: $filePath',
          );
        }
      } else {
        editableText = AiEditableTextSnapshot.empty();
      }
      var content = editableText.normalizedContent;
      final appliedNewStrings = <String>[];
      for (var hunkIndex = 0; hunkIndex < hunks.length; hunkIndex++) {
        final rawHunk = hunks[hunkIndex];
        if (rawHunk is! Map) {
          return AiToolUtils.invalidResult(
            'ApplyFileDiffs',
            'diffs[$i].hunks[$hunkIndex] must be an object.',
          );
        }
        final hunk = Map<String, Object?>.from(rawHunk);
        final oldString = '${hunk['old_string'] ?? ''}';
        final newString = '${hunk['new_string'] ?? ''}';
        final replaceAll = hunk['replace_all'] == true;
        final sequentialValidation = AiToolUtils.validateSequentialEditTarget(
          oldString: oldString,
          previousNewStrings: appliedNewStrings,
        );
        if (sequentialValidation != null) {
          return AiToolUtils.invalidResult(
            'ApplyFileDiffs',
            'diffs[$i].hunks[$hunkIndex] failed for $filePath: $sequentialValidation',
          );
        }
        final replacement = AiToolUtils.applyExactStringEdit(
          content: content,
          oldString: oldString,
          newString: newString,
          replaceAll: replaceAll,
          allowCreationFromEmptyOldString: !exists && hunkIndex == 0,
        );
        if (!replacement.success) {
          return AiToolUtils.invalidResult(
            'ApplyFileDiffs',
            'diffs[$i].hunks[$hunkIndex] failed for $filePath: ${replacement.errorMessage}',
          );
        }
        content = replacement.content;
        appliedNewStrings.add(newString);
      }
      final newContent = editableText.restoreLineEndings(content);
      plans.add(
        _FileDiffPlan(
          filePath: filePath,
          file: file,
          existed: exists,
          originalContent: editableText.rawContent,
          newContent: newContent,
          hunkCount: hunks.length,
        ),
      );
    }

    // ── 阶段 2：先收齐所有确认；任一拒绝则不写任何文件 ──
    for (final plan in plans) {
      final confirmation = await AiToolUtils.requestWriteConfirmation(
        toolName: 'ApplyFileDiffs',
        operationDescription:
            'Apply ${plan.hunkCount} hunk${plan.hunkCount > 1 ? 's' : ''} to file',
        targetPath: plan.filePath,
        requireWriteConfirmation: context.requireWriteCommandConfirmation,
        confirmWriteCommand: context.confirmWriteCommand,
        cancelSignal: context.cancelSignal,
        timeoutMs: context.metadata['write_confirmation_timeout_ms'] as int?,
      );
      if (confirmation != null) return confirmation;
    }

    // ── 阶段 3：写入；失败时尽力回滚已写文件 ──
    final applied = <_AppliedFileDiff>[];
    for (final plan in plans) {
      String? versionId;
      String? beforeContentForLedger;
      if (plan.existed) {
        versionId = await AiToolUtils.saveFileVersionBeforeMutation(
          filePath: plan.filePath,
          sessionId: context.sessionId,
          toolCallId: context.toolCall.id,
          fileHistory: fileHistory,
        );
        beforeContentForLedger = await AiToolUtils.readFileContentForLedger(
          plan.filePath,
        );
      }
      try {
        final guardedWrite = await AiToolUtils.writeTextFileWithMutationGuard(
          toolName: 'ApplyFileDiffs',
          file: plan.file,
          content: plan.newContent,
          previouslyReadFiles: context.previouslyReadFiles,
          requireExistingFileRead: plan.existed,
          fileTracker: fileTracker,
        );
        if (guardedWrite != null) {
          final rollback = await _rollbackAppliedPlans(
            applied,
            fileTracker: fileTracker,
          );
          return AiToolUtils.invalidResult(
            'ApplyFileDiffs',
            'Write guard rejected ${plan.filePath}: ${guardedWrite.stderr}$rollback',
          );
        }
        applied.add(
          _AppliedFileDiff(
            plan: plan,
            versionId: versionId,
            beforeContentForLedger: beforeContentForLedger,
          ),
        );
      } catch (error) {
        final rollback = await _rollbackAppliedPlans(
          applied,
          fileTracker: fileTracker,
        );
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'Write failed for ${plan.filePath}: $error$rollback',
        );
      }

      // 写后读回校验
      String verify;
      try {
        verify = await plan.file.readAsString();
      } catch (e) {
        final rollback = await _rollbackAppliedPlans(
          applied,
          fileTracker: fileTracker,
        );
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'File was written but verification read failed for ${plan.filePath}: $e$rollback',
        );
      }
      if (verify != plan.newContent) {
        final rollback = await _rollbackAppliedPlans(
          applied,
          fileTracker: fileTracker,
        );
        return AiToolUtils.invalidResult(
          'ApplyFileDiffs',
          'Verification mismatch after write for ${plan.filePath}.$rollback',
        );
      }
    }

    final results = <_FileDiffResult>[];
    for (final item in applied) {
      final plan = item.plan;
      final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
        ledger: mutationLedger,
        sessionId: context.sessionId,
        toolCallId: context.toolCall.id,
        toolName: 'ApplyFileDiffs',
        filePath: plan.filePath,
        kind: plan.existed ? FileMutationKind.modify : FileMutationKind.create,
        beforeContent: item.beforeContentForLedger,
        afterContent: plan.newContent,
      );
      results.add(
        _FileDiffResult(
          filePath: plan.filePath,
          hunkCount: plan.hunkCount,
          versionId: item.versionId,
          ledgerRecordId: ledgerRecordId,
        ),
      );
    }

    final lines = <String>[
      'Applied ${results.length} file diff${results.length > 1 ? 's' : ''} (verified):',
    ];
    for (final r in results) {
      lines.add(
        '  - ${r.filePath} (${r.hunkCount} hunk${r.hunkCount > 1 ? 's' : ''})',
      );
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'ApplyFileDiffs (${results.length} files)',
      output: lines.join('\n'),
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: results.isEmpty
          ? null
          : p.dirname(results.first.filePath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'apply_file_diffs',
        'file_mutation_file_count': results.length,
        'file_mutation_total_hunks': results.fold<int>(
          0,
          (acc, r) => acc + r.hunkCount,
        ),
        'file_mutation_paths': results.map((r) => r.filePath).toList(),
        'file_mutation_version_ids': <String, String?>{
          for (final r in results) r.filePath: r.versionId,
        },
        'file_mutation_ledger_record_ids': <String, String?>{
          for (final r in results) r.filePath: r.ledgerRecordId,
        },
        'file_mutation_transactional_write': true,
      },
    );
  }

  Future<String> _rollbackAppliedPlans(
    List<_AppliedFileDiff> applied, {
    required AiFileTrackerService? fileTracker,
  }) async {
    if (applied.isEmpty) {
      return ' No files had been written yet.';
    }
    final restored = <String>[];
    final failed = <String>[];
    for (final item in applied.reversed) {
      final plan = item.plan;
      try {
        if (plan.existed) {
          await AiToolUtils.writeTextFileSafely(
            plan.file,
            plan.originalContent,
          );
        } else if (await plan.file.exists()) {
          await plan.file.delete();
        }
        await AiToolUtils.updateTrackerAfterMutation(
          filePath: plan.filePath,
          fileTracker: fileTracker,
        );
        restored.add(plan.filePath);
      } catch (error) {
        failed.add('${plan.filePath} ($error)');
      }
    }
    if (failed.isEmpty) {
      return ' Rolled back ${restored.length} previously written file${restored.length == 1 ? '' : 's'}.';
    }
    return ' Rollback attempted: restored ${restored.length}; failed ${failed.length}: ${failed.join('; ')}.';
  }
}

class _FileDiffPlan {
  _FileDiffPlan({
    required this.filePath,
    required this.file,
    required this.existed,
    required this.originalContent,
    required this.newContent,
    required this.hunkCount,
  });
  final String filePath;
  final File file;
  final bool existed;
  final String originalContent;
  final String newContent;
  final int hunkCount;
}

class _AppliedFileDiff {
  _AppliedFileDiff({
    required this.plan,
    required this.versionId,
    required this.beforeContentForLedger,
  });

  final _FileDiffPlan plan;
  final String? versionId;
  final String? beforeContentForLedger;
}

class _FileDiffResult {
  _FileDiffResult({
    required this.filePath,
    required this.hunkCount,
    required this.versionId,
    required this.ledgerRecordId,
  });
  final String filePath;
  final int hunkCount;
  final String? versionId;
  final String? ledgerRecordId;
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/input_value_parsing.dart';
import '../../service/fs/ai_file_mutation_ledger.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiNotebookEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.notebookEdit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawNotebookPath = AiToolUtils.readString(args['notebook_path']);
    if (rawNotebookPath.isEmpty) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'NotebookEdit requires a non-empty notebook_path.',
      );
    }
    final notebookPath = AiToolUtils.resolvePathForContext(
      context,
      rawNotebookPath,
    );
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'NotebookEdit',
      path: notebookPath,
    );
    if (boundaryError != null) return boundaryError;
    if (p.extension(notebookPath).toLowerCase() != '.ipynb') {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'NotebookEdit requires a .ipynb notebook file.',
      );
    }
    final newSource = '${args['new_source'] ?? ''}';
    final editMode = _normalizeEditMode(
      AiToolUtils.readString(args['edit_mode'], fallback: 'replace'),
    );
    final cellId = AiToolUtils.readString(args['cell_id']);
    final cellType = _normalizeCellType(
      AiToolUtils.readString(args['cell_type']),
    );
    final file = File(notebookPath);
    if (!await AiToolUtils.fileExistsBounded(file)) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        await AiToolUtils.missingPathMessage(
          subject: 'Notebook',
          path: notebookPath,
        ),
      );
    }
    if (editMode == null) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'NotebookEdit edit_mode must be one of replace, insert, or delete.',
      );
    }
    if (cellType == null) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'NotebookEdit cell_type must be code, markdown, or raw when provided.',
      );
    }
    if (editMode != 'delete') {
      final payloadSizeValidation =
          AiToolUtils.validateGeneratedTextPayloadSize(
            toolName: 'NotebookEdit',
            fieldName: 'new_source',
            value: newSource,
          );
      if (payloadSizeValidation != null) return payloadSizeValidation;
    }

    // 写操作权限确认检查
    final confirmationResult = await AiToolUtils.requestWriteConfirmation(
      toolName: 'NotebookEdit',
      operationDescription: '$editMode cell in notebook',
      targetPath: notebookPath,
      requireWriteConfirmation: context.requireWriteCommandConfirmation,
      confirmWriteCommand: context.confirmWriteCommand,
      cancelSignal: context.cancelSignal,
      timeoutMs: context.writeConfirmationTimeoutMs,
    );
    if (confirmationResult != null) {
      return confirmationResult;
    }

    // 从 metadata 获取追踪服务
    final fileTracker = context.fileTracker;
    final fileHistory = context.fileHistory;

    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'NotebookEdit',
      filePath: notebookPath,
      previouslyReadFiles: context.previouslyReadFiles,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;

    // 保存历史版本
    final versionId = await AiToolUtils.saveFileVersionBeforeMutation(
      filePath: notebookPath,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      fileHistory: fileHistory,
    );

    // 双快照中的 before 捕获
    final mutationLedger = context.mutationLedger;
    final beforeContentForLedger = await AiToolUtils.readFileContentForLedger(
      notebookPath,
    );

    late final Object? decoded;
    try {
      final editableText = await AiToolUtils.readEditableTextFile(file);
      decoded = jsonDecode(editableText.rawContent);
    } on AiEditableTextFileTooLargeException catch (error) {
      return AiToolUtils.invalidResult('NotebookEdit', error.message);
    } on FormatException catch (error) {
      return AiToolUtils.invalidResult('NotebookEdit', error.message);
    }
    if (decoded is! Map) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'Notebook JSON root is invalid.',
      );
    }
    final notebook = stringKeyedMapFromValue(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List) {
      return AiToolUtils.invalidResult(
        'NotebookEdit',
        'Notebook cells array is invalid.',
      );
    }
    final cells = rawCells
        .map(
          (item) =>
              item is Map ? stringKeyedMapFromValue(item) : <String, Object?>{},
        )
        .toList(growable: true);
    final index = cellId.isEmpty
        ? -1
        : cells.indexWhere((cell) => '${cell['id'] ?? ''}'.trim() == cellId);
    switch (editMode) {
      case 'insert':
        if (cellType.isEmpty) {
          return AiToolUtils.invalidResult(
            'NotebookEdit',
            'NotebookEdit insert requires cell_type.',
          );
        }
        // 指定了 cell_id 却没找到，是「在某个不存在的单元格后插入」——按错误处理，
        // 而不是静默插到开头。仅当未指定 cell_id 时才插到开头（index == -1）。
        if (cellId.isNotEmpty && index == -1) {
          return AiToolUtils.invalidResult(
            'NotebookEdit',
            'Target cell_id was not found.',
          );
        }
        final insertedCell = <String, Object?>{
          'cell_type': cellType,
          'metadata': const <String, Object?>{},
          'source': newSource,
        };
        if (index == -1) {
          cells.insert(0, insertedCell);
        } else {
          cells.insert(index + 1, insertedCell);
        }
      case 'delete':
        if (index == -1) {
          return AiToolUtils.invalidResult(
            'NotebookEdit',
            'Target cell_id was not found.',
          );
        }
        cells.removeAt(index);
      case 'replace':
        if (index == -1) {
          return AiToolUtils.invalidResult(
            'NotebookEdit',
            'Target cell_id was not found.',
          );
        }
        final updatedCell = Map<String, Object?>.from(cells[index]);
        if (cellType.isNotEmpty) updatedCell['cell_type'] = cellType;
        updatedCell['source'] = newSource;
        cells[index] = updatedCell;
    }
    notebook['cells'] = cells;
    final guardedWrite = await AiToolUtils.writeTextFileWithMutationGuard(
      toolName: 'NotebookEdit',
      file: file,
      content: prettyPrintJson(notebook),
      previouslyReadFiles: context.previouslyReadFiles,
      requireExistingFileRead: true,
      fileTracker: fileTracker,
    );
    if (guardedWrite != null) return guardedWrite;

    // ledger 记录双快照
    final afterContentForLedger = await AiToolUtils.readFileContentForLedger(
      notebookPath,
    );
    final ledgerRecordId = await AiToolUtils.recordFileMutationToLedger(
      ledger: mutationLedger,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      toolName: 'NotebookEdit',
      filePath: notebookPath,
      kind: FileMutationKind.modify,
      beforeContent: beforeContentForLedger,
      afterContent: afterContentForLedger,
    );

    return AiToolUtils.simpleSuccessResult(
      command: 'NotebookEdit $notebookPath',
      output: 'Updated notebook $notebookPath',
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(notebookPath),
      isWriteCommand: true,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'file_mutation_kind': 'notebook_edit',
        'file_mutation_path': notebookPath,
        'file_mutation_edit_mode': editMode,
        if (editMode != 'delete')
          'file_mutation_new_source_char_count': newSource.length,
        if (cellId.isNotEmpty) 'file_mutation_cell_id': cellId,
        if (cellType.isNotEmpty) 'file_mutation_cell_type': cellType,
        if (versionId != null) 'file_mutation_history_version_id': versionId,
        if (ledgerRecordId != null)
          'file_mutation_ledger_record_id': ledgerRecordId,
      },
    );
  }

  String? _normalizeEditMode(String rawMode) {
    final normalized = lowercaseStringFromValue(rawMode);
    if (normalized.isEmpty) return 'replace';
    return switch (normalized) {
      'replace' || 'insert' || 'delete' => normalized,
      _ => null,
    };
  }

  String? _normalizeCellType(String rawCellType) {
    final normalized = lowercaseStringFromValue(rawCellType);
    if (normalized.isEmpty) return '';
    return switch (normalized) {
      'code' || 'markdown' || 'raw' => normalized,
      _ => null,
    };
  }
}

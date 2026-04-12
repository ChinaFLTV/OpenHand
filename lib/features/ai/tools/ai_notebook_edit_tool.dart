// 2026-04-01 02:02:39 从 AiToolRuntimeService._executeNotebookEditTool 迁移
// 2026-04-12 添加脏写检测和历史版本支持 (参考 opencode_workflow_analysis.md)
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_file_history_service.dart';
import '../service/ai_file_tracker_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiNotebookEditTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.notebookEdit;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final notebookPath = AiToolUtils.requireAbsoluteFilePath(
      '${args['notebook_path'] ?? ''}'.trim(),
    );
    if (notebookPath == null) {
      return AiToolUtils.invalidResult(
          'NotebookEdit', 'NotebookEdit requires an absolute notebook_path.');
    }
    final newSource = '${args['new_source'] ?? ''}';
    final editMode = _normalizeEditMode('${args['edit_mode'] ?? 'replace'}');
    final cellId = '${args['cell_id'] ?? ''}'.trim();
    final cellType = _normalizeCellType('${args['cell_type'] ?? ''}');
    final file = File(notebookPath);
    if (!await file.exists()) {
      return AiToolUtils.invalidResult(
          'NotebookEdit', 'Notebook does not exist: $notebookPath');
    }
    if (editMode == null) {
      return AiToolUtils.invalidResult('NotebookEdit',
          'NotebookEdit edit_mode must be one of replace, insert, or delete.');
    }
    if (cellType == null) {
      return AiToolUtils.invalidResult('NotebookEdit',
          'NotebookEdit cell_type must be code, markdown, or raw when provided.');
    }
    
    // 2026-04-12: 从 metadata 获取追踪服务
    final fileTracker = context.metadata['file_tracker'] as AiFileTrackerService?;
    final fileHistory = context.metadata['file_history'] as AiFileHistoryService?;
    
    final readValidation = await AiToolUtils.validateReadBeforeMutation(
      toolName: 'NotebookEdit',
      filePath: notebookPath,
      previouslyReadFiles: context.previouslyReadFiles,
      fileTracker: fileTracker,
    );
    if (readValidation != null) return readValidation;
    
    // 2026-04-12: 保存历史版本
    final versionId = await AiToolUtils.saveFileVersionBeforeMutation(
      filePath: notebookPath,
      sessionId: context.sessionId,
      toolCallId: context.toolCall.id,
      fileHistory: fileHistory,
    );
    
    late final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      return AiToolUtils.invalidResult('NotebookEdit', error.message);
    }
    if (decoded is! Map) {
      return AiToolUtils.invalidResult(
          'NotebookEdit', 'Notebook JSON root is invalid.');
    }
    final notebook = Map<String, Object?>.from(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List) {
      return AiToolUtils.invalidResult(
          'NotebookEdit', 'Notebook cells array is invalid.');
    }
    final cells = rawCells
        .map((item) => item is Map
            ? Map<String, Object?>.from(item)
            : <String, Object?>{})
        .toList(growable: true);
    final index = cellId.isEmpty
        ? -1
        : cells.indexWhere((cell) => '${cell['id'] ?? ''}'.trim() == cellId);
    switch (editMode) {
      case 'insert':
        if (cellType.isEmpty) {
          return AiToolUtils.invalidResult(
              'NotebookEdit', 'NotebookEdit insert requires cell_type.');
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
              'NotebookEdit', 'Target cell_id was not found.');
        }
        cells.removeAt(index);
      case 'replace':
        if (index == -1) {
          return AiToolUtils.invalidResult(
              'NotebookEdit', 'Target cell_id was not found.');
        }
        final updatedCell = Map<String, Object?>.from(cells[index]);
        if (cellType.isNotEmpty) updatedCell['cell_type'] = cellType;
        updatedCell['source'] = newSource;
        cells[index] = updatedCell;
    }
    notebook['cells'] = cells;
    await AiToolUtils.writeTextFileSafely(
      file,
      const JsonEncoder.withIndent('  ').convert(notebook),
    );
    
    // 2026-04-12: 更新追踪器（写入成功后更新 lastReadTime）
    await AiToolUtils.updateTrackerAfterMutation(
      filePath: notebookPath,
      fileTracker: fileTracker,
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
        'file_mutation_new_source_char_count': newSource.length,
        'file_mutation_edit_mode': editMode,
        if (cellId.isNotEmpty) 'file_mutation_cell_id': cellId,
        if (cellType.isNotEmpty) 'file_mutation_cell_type': cellType,
        if (versionId != null) 'file_mutation_history_version_id': versionId,
      },
    );
  }

  String? _normalizeEditMode(String rawMode) {
    final normalized = rawMode.trim().toLowerCase();
    if (normalized.isEmpty) return 'replace';
    return switch (normalized) {
      'replace' || 'insert' || 'delete' => normalized,
      _ => null,
    };
  }

  String? _normalizeCellType(String rawCellType) {
    final normalized = rawCellType.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    return switch (normalized) {
      'code' || 'markdown' || 'raw' => normalized,
      _ => null,
    };
  }
}

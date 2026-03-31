import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../service/ai_claude_hook_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

// 2026-04-01 01:21:38 从 AiToolRuntimeService._executeReadTool 提取
class AiReadTool extends AiTool {
  AiReadTool();

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.read;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final filePath = AiToolUtils.requireAbsoluteFilePath(
      '${args['file_path'] ?? ''}'.trim(),
    );
    if (filePath == null) {
      return AiToolUtils.invalidResult('Read', 'Read requires an absolute file_path.');
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AiToolUtils.invalidResult('Read', 'File does not exist: $filePath');
    }
    final offset = AiToolUtils.readInt(args['offset']);
    final limit = AiToolUtils.readInt(args['limit']) ?? AiToolUtils.defaultReadLimit;
    if (limit <= 0) {
      return AiToolUtils.invalidResult('Read', 'Read limit must be a positive integer.');
    }
    final renderedRead = await _DefaultRenderedReadContentLoader().load(file, filePath);
    final rawContent = renderedRead.content;
    if (rawContent.isEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $filePath',
        output: 'File is empty: $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          aiHookSystemRemindersMetadataKey: <String>[
            'Read opened an empty file: $filePath',
          ],
        },
      );
    }
    if (!renderedRead.lineAddressable) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $filePath',
        output: rawContent,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          'read_truncated': renderedRead.truncated,
        },
      );
    }
    final lines = const LineSplitter().convert(rawContent);
    final startIndex = offset == null || offset <= 1 ? 0 : offset - 1;
    final safeStartIndex = startIndex < lines.length ? startIndex : lines.length;
    final endIndex = (safeStartIndex + limit) < lines.length
        ? safeStartIndex + limit
        : lines.length;
    final visibleLines = lines.sublist(safeStartIndex, endIndex);
    final lineNumberWidth =
        endIndex.toString().length < 4 ? 4 : endIndex.toString().length;
    final output = visibleLines.isEmpty
        ? 'No lines available in the requested range.'
        : visibleLines
            .asMap()
            .entries
            .map((entry) {
              final lineNumber = safeStartIndex + entry.key + 1;
              final line = entry.value.length > AiToolUtils.maxReadLineLength
                  ? '${entry.value.substring(0, AiToolUtils.maxReadLineLength)}...'
                  : entry.value;
              return '${lineNumber.toString().padLeft(lineNumberWidth)}\t$line';
            })
            .join('\n');
    return AiToolUtils.simpleSuccessResult(
      command: 'Read $filePath',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(filePath),
      metadata: <String, Object?>{
        'read_file_path': filePath,
        'read_file_kind': renderedRead.fileKind,
        'read_render_mode': renderedRead.renderMode,
        'read_truncated': renderedRead.truncated,
        if (renderedRead.truncated)
          aiHookSystemRemindersMetadataKey: <String>[
            'Read truncated a large file preview: $filePath',
          ],
      },
    );
  }
}

abstract class _RenderedReadContentLoader {
  const _RenderedReadContentLoader();
  Future<RenderedReadContent> load(File file, String filePath);
}

class _DefaultRenderedReadContentLoader extends _RenderedReadContentLoader {
  const _DefaultRenderedReadContentLoader();

  @override
  Future<RenderedReadContent> load(File file, String filePath) async {
    // Delegates to the service-level renderer; injected via AiToolRuntimeService
    // when registered through AiToolRegistry.
    throw UnimplementedError(
        'Provide a concrete loader via AiReadTool(loader: ...) at registration time.');
  }
}

/// Value object returned by file render operations.
class RenderedReadContent {
  const RenderedReadContent({
    required this.content,
    required this.fileKind,
    required this.renderMode,
    required this.lineAddressable,
    this.truncated = false,
  });

  final String content;
  final String fileKind;
  final String renderMode;
  final bool lineAddressable;
  final bool truncated;
}

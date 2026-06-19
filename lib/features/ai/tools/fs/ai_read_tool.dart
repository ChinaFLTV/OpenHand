import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/fs/ai_file_tracker_service.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';
import 'ai_file_read_renderer.dart';

class AiReadTool extends AiTool {
  AiReadTool({AiFileReadRenderer? renderer})
    : _renderer = renderer ?? const AiFileReadRenderer();

  static const String _unchangedSinceLastReadMessage =
      'File unchanged since last read. The content from the earlier Read tool result in this conversation is still current; refer to that result instead of re-reading.';

  final AiFileReadRenderer _renderer;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.read;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawFilePath = '${args['file_path'] ?? ''}'.trim();
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'Read',
        'Read requires a non-empty file_path.',
      );
    }
    final filePath = AiToolUtils.resolvePath(rawFilePath);
    final file = File(filePath);
    if (!await file.exists()) {
      return AiToolUtils.invalidResult(
        'Read',
        'File does not exist: $filePath',
      );
    }

    // 2026-04-12: 从 metadata 获取追踪服务
    final fileTracker =
        context.metadata['file_tracker'] as AiFileTrackerService?;

    final offset = AiToolUtils.readInt(args['offset']);
    final limit =
        AiToolUtils.readInt(args['limit']) ?? AiToolUtils.defaultReadLimit;
    if (limit <= 0) {
      return AiToolUtils.invalidResult(
        'Read',
        'Read limit must be a positive integer.',
      );
    }
    final effectiveOffset = offset == null || offset <= 1 ? 1 : offset;
    if (fileTracker != null &&
        await fileTracker.isReadResultUnchanged(
          filePath: filePath,
          offset: effectiveOffset,
          limit: limit,
        )) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $filePath',
        output: '$_unchangedSinceLastReadMessage\npath: $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(filePath),
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_unchanged': true,
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
        },
      );
    }
    final renderedRead = await _renderer.render(file, filePath);
    final rawContent = renderedRead.content;

    if (renderedRead.lineAddressable) {
      await fileTracker?.recordReadResult(
        filePath: filePath,
        offset: effectiveOffset,
        limit: limit,
      );
    } else {
      await fileTracker?.recordFileRead(filePath);
    }

    if (rawContent.isEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $filePath',
        output: 'File is empty: $filePath',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          'read_file_path': filePath,
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
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
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
        },
      );
    }
    final lines = const LineSplitter().convert(rawContent);
    final startIndex = effectiveOffset <= 1 ? 0 : effectiveOffset - 1;
    final safeStartIndex = startIndex < lines.length
        ? startIndex
        : lines.length;
    final endIndex = (safeStartIndex + limit) < lines.length
        ? safeStartIndex + limit
        : lines.length;
    final visibleLines = lines.sublist(safeStartIndex, endIndex);
    final lineNumberWidth = endIndex.toString().length < 4
        ? 4
        : endIndex.toString().length;
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
        'read_file_offset': effectiveOffset,
        'read_file_limit': limit,
        if (renderedRead.truncated)
          aiHookSystemRemindersMetadataKey: <String>[
            'Read truncated a large file preview: $filePath',
          ],
      },
    );
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

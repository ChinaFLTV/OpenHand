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

  static const int _maxPdfPageRangeCount = 20;

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
    final pdfPagesResult = _parsePdfPagesArgument(
      args['pages'],
      filePath: filePath,
    );
    if (pdfPagesResult.error != null) {
      return pdfPagesResult.error!;
    }
    final pdfPages = pdfPagesResult.pages;

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
    final renderedRead = await _renderer.render(
      file,
      filePath,
      offset: effectiveOffset,
      limit: limit,
      pdfPages: pdfPages,
    );
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

    if (rawContent.isEmpty && renderedRead.fileEmpty) {
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
    final visibleLines = renderedRead.lineRangeApplied
        ? lines
        : _sliceLines(lines, effectiveOffset: effectiveOffset, limit: limit);
    final firstLineNumber = renderedRead.lineRangeApplied
        ? renderedRead.lineNumberStart
        : effectiveOffset;
    final lastLineNumber = visibleLines.isEmpty
        ? firstLineNumber
        : firstLineNumber + visibleLines.length - 1;
    final lineNumberWidth = lastLineNumber.toString().length < 4
        ? 4
        : lastLineNumber.toString().length;
    final output = visibleLines.isEmpty
        ? 'No lines available in the requested range.'
        : visibleLines
              .asMap()
              .entries
              .map((entry) {
                final lineNumber = firstLineNumber + entry.key;
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
            renderedRead.lineRangeApplied
                ? 'Read returned a bounded file range: $filePath'
                : 'Read truncated a large file preview: $filePath',
          ],
      },
    );
  }

  List<String> _sliceLines(
    List<String> lines, {
    required int effectiveOffset,
    required int limit,
  }) {
    final startIndex = effectiveOffset <= 1 ? 0 : effectiveOffset - 1;
    final safeStartIndex = startIndex < lines.length
        ? startIndex
        : lines.length;
    final endIndex = (safeStartIndex + limit) < lines.length
        ? safeStartIndex + limit
        : lines.length;
    return lines.sublist(safeStartIndex, endIndex);
  }

  _PdfPagesParseResult _parsePdfPagesArgument(
    Object? rawPages, {
    required String filePath,
  }) {
    if (rawPages == null) return const _PdfPagesParseResult();
    final raw = '$rawPages'.trim();
    if (raw.isEmpty) return const _PdfPagesParseResult();
    if (p.extension(filePath).toLowerCase() != '.pdf') {
      return _PdfPagesParseResult(
        error: AiToolUtils.invalidResult(
          'Read',
          'Read pages is only supported for PDF files.',
        ),
      );
    }

    final pages = <int>{};
    for (final segment in raw.split(',')) {
      final part = segment.trim();
      if (part.isEmpty) {
        return _invalidPdfPages(raw);
      }
      final rangeMatch = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(part);
      if (rangeMatch == null) {
        return _invalidPdfPages(raw);
      }
      final start = int.tryParse(rangeMatch.group(1) ?? '');
      final end = int.tryParse(rangeMatch.group(2) ?? '') ?? start;
      if (start == null || start <= 0 || end == null || end < start) {
        return _invalidPdfPages(raw);
      }
      for (var page = start; page <= end; page++) {
        pages.add(page);
        if (pages.length > _maxPdfPageRangeCount) {
          return _PdfPagesParseResult(
            error: AiToolUtils.invalidResult(
              'Read',
              'Read pages supports at most $_maxPdfPageRangeCount PDF pages per request.',
            ),
          );
        }
      }
    }
    return _PdfPagesParseResult(
      pages: AiPdfPageRange(label: raw, pageCount: pages.length),
    );
  }

  _PdfPagesParseResult _invalidPdfPages(String raw) {
    return _PdfPagesParseResult(
      error: AiToolUtils.invalidResult(
        'Read',
        'Invalid PDF pages range "$raw". Use "1", "1-5", or comma-separated ranges up to $_maxPdfPageRangeCount pages.',
      ),
    );
  }
}

class _PdfPagesParseResult {
  const _PdfPagesParseResult({this.pages, this.error});

  final AiPdfPageRange? pages;
  final AiToolExecutionResult? error;
}

/// Value object returned by file render operations.
class RenderedReadContent {
  const RenderedReadContent({
    required this.content,
    required this.fileKind,
    required this.renderMode,
    required this.lineAddressable,
    this.truncated = false,
    this.lineRangeApplied = false,
    this.lineNumberStart = 1,
    this.fileEmpty = false,
  });

  final String content;
  final String fileKind;
  final String renderMode;
  final bool lineAddressable;
  final bool truncated;
  final bool lineRangeApplied;
  final int lineNumberStart;
  final bool fileEmpty;
}

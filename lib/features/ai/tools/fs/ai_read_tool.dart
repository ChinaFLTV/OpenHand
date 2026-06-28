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
  static const String _macScreenshotThinSpace = '\u202f';

  static const String _unchangedSinceLastReadMessage =
      'File unchanged since last read. The content from the earlier Read tool result in this conversation is still current; refer to that result instead of re-reading.';

  static const Set<String> _blockedDeviceReadPaths = <String>{
    '/dev/zero',
    '/dev/random',
    '/dev/urandom',
    '/dev/full',
    '/dev/stdin',
    '/dev/tty',
    '/dev/console',
    '/dev/stdout',
    '/dev/stderr',
    '/dev/fd/0',
    '/dev/fd/1',
    '/dev/fd/2',
  };

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
    if (_isBlockedDeviceReadPath(filePath)) {
      return AiToolUtils.invalidResult(
        'Read',
        'Refused to read special device path that may block, never reach EOF, or produce infinite output: $filePath',
      );
    }
    final resolvedFile = await _resolveExistingReadFile(filePath);
    if (resolvedFile == null) {
      return AiToolUtils.invalidResult(
        'Read',
        await AiToolUtils.missingPathMessage(subject: 'File', path: filePath),
      );
    }
    final actualFilePath = resolvedFile.filePath;
    final file = resolvedFile.file;
    final pdfPagesResult = _parsePdfPagesArgument(
      args['pages'],
      filePath: actualFilePath,
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
          filePath: actualFilePath,
          offset: effectiveOffset,
          limit: limit,
        )) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $actualFilePath',
        output: '$_unchangedSinceLastReadMessage\npath: $actualFilePath',
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(actualFilePath),
        metadata: <String, Object?>{
          ..._pathMetadata(resolvedFile),
          'read_file_unchanged': true,
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
        },
      );
    }
    final renderedRead = await _renderer.render(
      file,
      actualFilePath,
      offset: effectiveOffset,
      limit: limit,
      pdfPages: pdfPages,
    );
    final rawContent = renderedRead.content;

    if (renderedRead.lineAddressable) {
      await fileTracker?.recordReadResult(
        filePath: actualFilePath,
        offset: effectiveOffset,
        limit: limit,
      );
    } else {
      await fileTracker?.recordFileRead(actualFilePath);
    }

    if (rawContent.isEmpty && renderedRead.fileEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $actualFilePath',
        output: 'File is empty: $actualFilePath',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          ..._pathMetadata(resolvedFile),
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
          aiHookSystemRemindersMetadataKey: <String>[
            'Read opened an empty file: $actualFilePath',
          ],
        },
      );
    }
    if (!renderedRead.lineAddressable) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $actualFilePath',
        output: rawContent,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(actualFilePath),
        metadata: <String, Object?>{
          ..._pathMetadata(resolvedFile),
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
      command: 'Read $actualFilePath',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      workingDirectory: p.dirname(actualFilePath),
      metadata: <String, Object?>{
        ..._pathMetadata(resolvedFile),
        'read_file_kind': renderedRead.fileKind,
        'read_render_mode': renderedRead.renderMode,
        'read_truncated': renderedRead.truncated,
        'read_file_offset': effectiveOffset,
        'read_file_limit': limit,
        if (renderedRead.truncated)
          aiHookSystemRemindersMetadataKey: <String>[
            renderedRead.lineRangeApplied
                ? 'Read returned a bounded file range: $actualFilePath'
                : 'Read truncated a large file preview: $actualFilePath',
          ],
      },
    );
  }

  Future<_ResolvedReadFile?> _resolveExistingReadFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return _ResolvedReadFile(file: file, filePath: filePath);
    }
    final alternatePath = _alternateMacScreenshotPath(filePath);
    if (alternatePath == null || alternatePath == filePath) {
      return null;
    }
    final alternateFile = File(alternatePath);
    if (!await alternateFile.exists()) {
      return null;
    }
    return _ResolvedReadFile(
      file: alternateFile,
      filePath: alternatePath,
      requestedPath: filePath,
      alternatePathUsed: true,
    );
  }

  String? _alternateMacScreenshotPath(String filePath) {
    final filename = p.basename(filePath);
    final match = RegExp(
      r'^(.+)([ \u202f])(AM|PM)(\.png)$',
      caseSensitive: false,
    ).firstMatch(filename);
    if (match == null) return null;
    final currentSpace = match.group(2);
    if (currentSpace == null) return null;
    final alternateSpace = currentSpace == ' ' ? _macScreenshotThinSpace : ' ';
    final alternateFilename =
        '${match.group(1)}$alternateSpace${match.group(3)}${match.group(4)}';
    return p.join(p.dirname(filePath), alternateFilename);
  }

  Map<String, Object?> _pathMetadata(_ResolvedReadFile resolvedFile) {
    return <String, Object?>{
      'read_file_path': resolvedFile.filePath,
      if (resolvedFile.requestedPath != null)
        'read_file_requested_path': resolvedFile.requestedPath,
      if (resolvedFile.alternatePathUsed) 'read_file_alternate_path_used': true,
    };
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
    final raw = _pdfPagesRawLabel(rawPages);
    final segments = _pdfPageRangeSegments(rawPages);
    if (segments.isEmpty && raw.isEmpty) return const _PdfPagesParseResult();
    if (segments.isEmpty && _isEmptyPdfPagesCollection(rawPages)) {
      return const _PdfPagesParseResult();
    }
    if (p.extension(filePath).toLowerCase() != '.pdf') {
      return _PdfPagesParseResult(
        error: AiToolUtils.invalidResult(
          'Read',
          'Read pages is only supported for PDF files.',
        ),
      );
    }

    final pages = <int>{};
    for (final segment in segments) {
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
      pages: AiPdfPageRange(label: segments.join(','), pageCount: pages.length),
    );
  }

  String _pdfPagesRawLabel(Object rawPages) {
    if (rawPages is String) return rawPages.trim();
    if (rawPages is Iterable) {
      return rawPages.map(_pdfPageRangeSegmentText).join(',').trim();
    }
    return _pdfPageRangeSegmentText(rawPages).trim();
  }

  List<String> _pdfPageRangeSegments(Object rawPages) {
    if (rawPages is Iterable) {
      return rawPages.map(_pdfPageRangeSegmentText).toList(growable: false);
    }
    if (rawPages is String) {
      final trimmed = rawPages.trim();
      if (trimmed.isEmpty) return const <String>[];
      final jsonList = _pdfPageRangeSegmentsFromJsonList(trimmed);
      if (jsonList != null) return jsonList;
      return trimmed
          .split(',')
          .map((part) => part.trim())
          .toList(growable: false);
    }
    return <String>[_pdfPageRangeSegmentText(rawPages)];
  }

  List<String>? _pdfPageRangeSegmentsFromJsonList(String rawPages) {
    try {
      final decoded = jsonDecode(rawPages);
      if (decoded is! List) return null;
      return decoded.map(_pdfPageRangeSegmentText).toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  String _pdfPageRangeSegmentText(Object? value) {
    final page = AiToolUtils.readInt(value);
    if (page != null) return page.toString();
    return '$value'.trim();
  }

  bool _isEmptyPdfPagesCollection(Object rawPages) {
    if (rawPages is Iterable) return rawPages.isEmpty;
    if (rawPages is String) {
      return _pdfPageRangeSegmentsFromJsonList(rawPages)?.isEmpty ?? false;
    }
    return false;
  }

  _PdfPagesParseResult _invalidPdfPages(String raw) {
    return _PdfPagesParseResult(
      error: AiToolUtils.invalidResult(
        'Read',
        'Invalid PDF pages range "$raw". Use "1", "1-5", or comma-separated ranges up to $_maxPdfPageRangeCount pages.',
      ),
    );
  }

  bool _isBlockedDeviceReadPath(String filePath) {
    final normalized = p.normalize(filePath);
    if (_blockedDeviceReadPaths.contains(normalized)) return true;
    if (!normalized.startsWith('/proc/')) return false;
    return RegExp(r'/fd/[0-2]$').hasMatch(normalized);
  }
}

class _ResolvedReadFile {
  const _ResolvedReadFile({
    required this.file,
    required this.filePath,
    this.requestedPath,
    this.alternatePathUsed = false,
  });

  final File file;
  final String filePath;
  final String? requestedPath;
  final bool alternatePathUsed;
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

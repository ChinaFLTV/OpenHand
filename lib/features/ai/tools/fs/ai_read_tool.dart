import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/input_value_parsing.dart';
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
  static final RegExp _pdfPageRangePattern = RegExp(
    r'^(\d+)(?:\s*-\s*(\d+))?$',
  );

  static const String _unchangedSinceLastReadMessage =
      '文件自上次读取后未变化，请直接参考本会话中此前的 Read 结果。';

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
    final rawFilePath = AiToolUtils.readString(args['file_path']);
    if (rawFilePath.isEmpty) {
      return AiToolUtils.invalidResult('Read', 'Read 需要非空 file_path。');
    }
    final filePath = AiToolUtils.resolvePathForContext(context, rawFilePath);
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'Read',
      path: filePath,
    );
    if (boundaryError != null) return boundaryError;
    if (_isBlockedDeviceReadPath(filePath)) {
      return AiToolUtils.invalidResult(
        'Read',
        '拒绝读取可能阻塞、无法到达 EOF 或无限输出的特殊设备路径：$filePath',
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

    // 从 metadata 获取追踪服务
    final fileTracker = context.fileTracker;

    final offset = AiToolUtils.readInt(args['offset']);
    final limit =
        AiToolUtils.readInt(args['limit']) ?? AiToolUtils.defaultReadLimit;
    if (limit <= 0) {
      return AiToolUtils.invalidResult('Read', 'Read 的 limit 必须为正整数。');
    }
    if (limit > AiToolUtils.maxReadLimit) {
      return AiToolUtils.invalidResult(
        'Read',
        'Read 的 limit 最多为 ${AiToolUtils.maxReadLimit} 行。',
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
    late final RenderedReadContent renderedRead;
    try {
      Future<RenderedReadContent> render() => _renderer.render(
        file,
        actualFilePath,
        offset: effectiveOffset,
        limit: limit,
        pdfPages: pdfPages,
      );
      renderedRead = fileTracker == null
          ? await render()
          : await fileTracker.readConsistently<RenderedReadContent>(
              filePath: actualFilePath,
              offset: effectiveOffset,
              limit: limit,
              read: render,
              trackResultRange: (value) => value.lineAddressable,
            );
    } on AiFileChangedDuringReadException catch (error) {
      return AiToolUtils.invalidResult('Read', '$error');
    }
    final rawContent = renderedRead.content;

    if (rawContent.isEmpty && renderedRead.fileEmpty) {
      return AiToolUtils.simpleSuccessResult(
        command: 'Read $actualFilePath',
        output: '文件为空：$actualFilePath',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          ..._pathMetadata(resolvedFile),
          'read_file_kind': renderedRead.fileKind,
          'read_render_mode': renderedRead.renderMode,
          'read_file_offset': effectiveOffset,
          'read_file_limit': limit,
          aiHookSystemRemindersMetadataKey: <String>[
            'Read 打开了空文件：$actualFilePath',
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
        ? '请求范围内没有可用行。'
        : visibleLines
              .asMap()
              .entries
              .map((entry) {
                final lineNumber = firstLineNumber + entry.key;
                final line = AiToolUtils.truncateContent(
                  entry.value,
                  AiToolUtils.maxReadLineLength,
                );
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
                ? 'Read 返回了有界文件范围：$actualFilePath'
                : 'Read 已截断大文件预览：$actualFilePath',
          ],
      },
    );
  }

  Future<_ResolvedReadFile?> _resolveExistingReadFile(String filePath) async {
    final file = File(filePath);
    if (await AiToolUtils.fileExistsBounded(file)) {
      return _ResolvedReadFile(file: file, filePath: filePath);
    }
    final alternatePath = _alternateMacScreenshotPath(filePath);
    if (alternatePath == null || alternatePath == filePath) {
      return null;
    }
    final alternateFile = File(alternatePath);
    if (!await AiToolUtils.fileExistsBounded(alternateFile)) {
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
        error: AiToolUtils.invalidResult('Read', 'Read 的 pages 仅支持 PDF 文件。'),
      );
    }

    final pages = <int>{};
    for (final segment in segments) {
      final part = nullIfBlank(segment);
      if (part == null) {
        return _invalidPdfPages(raw);
      }
      final rangeMatch = _pdfPageRangePattern.firstMatch(part);
      if (rangeMatch == null) {
        return _invalidPdfPages(raw);
      }
      final start = optionalPositiveIntFromValue(rangeMatch.group(1));
      final end = optionalPositiveIntFromValue(rangeMatch.group(2)) ?? start;
      if (start == null || end == null || end < start) {
        return _invalidPdfPages(raw);
      }
      for (var page = start; page <= end; page++) {
        pages.add(page);
        if (pages.length > _maxPdfPageRangeCount) {
          return _PdfPagesParseResult(
            error: AiToolUtils.invalidResult(
              'Read',
              'Read 的 pages 每次最多支持 $_maxPdfPageRangeCount 页 PDF。',
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
    if (rawPages is String) return nullIfBlank(rawPages) ?? '';
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
      final trimmed = nullIfBlank(rawPages);
      if (trimmed == null) return const <String>[];
      final jsonList = _pdfPageRangeSegmentsFromJsonList(trimmed);
      if (jsonList != null) return jsonList;
      return splitTrimmed(trimmed);
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
        '无效 PDF 页码范围“$raw”。请使用“1”“1-5”或逗号分隔的范围，最多 $_maxPdfPageRangeCount 页。',
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

/// 文件渲染结果值对象。
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

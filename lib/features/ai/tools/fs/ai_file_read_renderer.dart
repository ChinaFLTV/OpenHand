import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../shared/net/http_redirect_utils.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/hex_encoding.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../ai_tool_utils.dart';
import 'ai_read_tool.dart';

class AiFileReadRenderer {
  const AiFileReadRenderer();

  Future<RenderedReadContent> render(
    File file,
    String filePath, {
    int? offset,
    int? limit,
    AiPdfPageRange? pdfPages,
  }) async {
    final extension = p.extension(filePath).toLowerCase();
    final fileLength = await AiToolUtils.fileLengthBounded(file);
    if (fileLength == 0) {
      return RenderedReadContent(
        content: '',
        fileKind: extension.isEmpty ? 'text' : extension,
        renderMode: 'text',
        lineAddressable: true,
        fileEmpty: true,
      );
    }
    if (extension == '.ipynb') {
      if (fileLength > AiToolUtils.maxStructuredReadBytes) {
        return _renderOversizedStructuredFile(
          filePath: filePath,
          fileKind: extension,
          renderMode: 'notebook',
          totalByteSize: fileLength,
        );
      }
      return RenderedReadContent(
        content: await _renderNotebookForRead(file),
        fileKind: extension,
        renderMode: 'notebook',
        lineAddressable: true,
      );
    }
    if (AiToolUtils.isRasterImageExtension(extension)) {
      if (fileLength > AiToolUtils.maxStructuredReadBytes) {
        return _renderOversizedStructuredFile(
          filePath: filePath,
          fileKind: extension,
          renderMode: 'image',
          totalByteSize: fileLength,
        );
      }
      final bytes = await readBoundedFileBytes(
        file,
        maxBytes: AiToolUtils.maxStructuredReadBytes,
        idleTimeout: defaultBoundedFileReadIdleTimeout,
        totalTimeout: defaultBoundedFileReadTotalTimeout,
      );
      return _renderImage(bytes, filePath, extension);
    }
    if (extension == '.pdf') {
      if (fileLength > AiToolUtils.maxStructuredReadBytes) {
        return _renderOversizedStructuredFile(
          filePath: filePath,
          fileKind: extension,
          renderMode: 'pdf',
          totalByteSize: fileLength,
          pdfPages: pdfPages,
        );
      }
      final bytes = await readBoundedFileBytes(
        file,
        maxBytes: AiToolUtils.maxStructuredReadBytes,
        idleTimeout: defaultBoundedFileReadIdleTimeout,
        totalTimeout: defaultBoundedFileReadTotalTimeout,
      );
      return _renderPdf(bytes, filePath, pageRange: pdfPages);
    }
    // 这段前缀只用于二进制判别与十六进制预览；文本分支随后会用
    // _renderTextRange 从头流式重读，所以这里读满整个文件毫无意义。
    final sniffBytes = await AiToolUtils.readFilePrefix(
      file,
      fileLength < AiToolUtils.binarySniffBytes
          ? fileLength
          : AiToolUtils.binarySniffBytes,
    );
    if (AiToolUtils.looksBinary(sniffBytes) &&
        !AiToolUtils.isKnownTextExtension(extension)) {
      return _renderBinary(
        sniffBytes,
        filePath,
        extension,
        totalByteSize: fileLength,
        truncated: fileLength > sniffBytes.length,
      );
    }
    return _renderTextRange(
      file,
      extension,
      offset: offset ?? 1,
      limit: limit ?? AiToolUtils.defaultReadLimit,
    );
  }

  RenderedReadContent _renderOversizedStructuredFile({
    required String filePath,
    required String fileKind,
    required String renderMode,
    required int totalByteSize,
    AiPdfPageRange? pdfPages,
  }) {
    final buffer = StringBuffer()
      ..writeln('file_type: ${renderMode == 'image' ? 'image' : renderMode}')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: $totalByteSize')
      ..writeln('size_limit_bytes: ${AiToolUtils.maxStructuredReadBytes}');
    if (fileKind.isNotEmpty) buffer.writeln('extension: $fileKind');
    if (pdfPages != null) {
      buffer
        ..writeln('requested_pages: ${pdfPages.label}')
        ..writeln('requested_page_count: ${pdfPages.pageCount}');
    }
    buffer.writeln(
      'preview: Full structured rendering is skipped because the file exceeds the bounded Read size. Use a narrower tool or external command if you need detailed inspection.',
    );
    return RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: fileKind.isEmpty ? renderMode : fileKind,
      renderMode: renderMode,
      lineAddressable: false,
      truncated: true,
    );
  }

  Future<RenderedReadContent> _renderTextRange(
    File file,
    String extension, {
    required int offset,
    required int limit,
  }) async {
    final startLine = offset <= 1 ? 1 : offset;
    final result = await readBoundedUtf8Lines(
      file,
      startLine: startLine,
      maxLines: limit,
      maxScanBytes: AiToolUtils.maxReadBytes,
      maxLineCharacters: AiToolUtils.maxReadLineLength + 1,
    );

    return RenderedReadContent(
      content: result.lines.join('\n'),
      fileKind: extension.isEmpty ? 'text' : extension,
      renderMode: 'text',
      lineAddressable: true,
      truncated: startLine > 1 || result.truncated,
      lineRangeApplied: true,
      lineNumberStart: startLine,
    );
  }

  Future<String> _renderNotebookForRead(File file) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(
        await readBoundedFileString(
          file,
          maxBytes: AiToolUtils.maxStructuredReadBytes,
        ),
      );
    } catch (_) {
      return '';
    }
    if (decoded is! Map) return '';
    final notebook = stringKeyedMapFromValue(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List || rawCells.isEmpty) return '';
    final buffer = StringBuffer();
    for (var index = 0; index < rawCells.length; index++) {
      final cell =
          optionalStringKeyedMapFromValue(rawCells[index]) ??
          const <String, Object?>{};
      final cellType = _readText(cell['cell_type']);
      buffer.writeln('# Cell $index [$cellType]');
      final source = _renderNotebookValue(cell['source']);
      if (source.isNotEmpty) buffer.writeln(source.trimRight());
      final outputs = cell['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        buffer.writeln('## Outputs');
        for (final output in outputs) {
          final outputMap =
              optionalStringKeyedMapFromValue(output) ??
              const <String, Object?>{};
          final text = _renderNotebookValue(
            outputMap['text'] ?? outputMap['data'] ?? outputMap['traceback'],
          );
          if (text.isNotEmpty) buffer.writeln(text.trimRight());
        }
      }
      if (index != rawCells.length - 1) buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  RenderedReadContent _renderImage(
    List<int> bytes,
    String filePath,
    String extension,
  ) {
    final decodedImage = _tryDecodeImage(bytes);
    final byteSize = bytes.length;
    final buffer = StringBuffer()
      ..writeln('file_type: image')
      ..writeln('path: $filePath')
      ..writeln(
        'format: ${extension.isEmpty ? 'unknown' : extension.substring(1)}',
      )
      ..writeln('size_bytes: $byteSize');
    if (decodedImage != null) {
      buffer
        ..writeln('width: ${decodedImage.width}')
        ..writeln('height: ${decodedImage.height}');
    }
    buffer.writeln(
      'preview: Raster image files are not line-addressable in this runtime.',
    );
    return RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: extension.isEmpty ? 'image' : extension,
      renderMode: 'image',
      lineAddressable: false,
    );
  }

  img.Image? _tryDecodeImage(List<int> bytes) {
    try {
      return img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  RenderedReadContent _renderPdf(
    List<int> bytes,
    String filePath, {
    AiPdfPageRange? pageRange,
  }) {
    final latinText = latin1.decode(bytes, allowInvalid: true);
    final headerLine = latinText.split(RegExp(r'[\r\n]')).first.trim();
    final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(latinText).length;
    final buffer = StringBuffer()
      ..writeln('file_type: pdf')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: ${bytes.length}');
    if (headerLine.isNotEmpty) buffer.writeln('header: $headerLine');
    if (pageCount > 0) buffer.writeln('page_count_estimate: $pageCount');
    if (pageRange != null) {
      buffer
        ..writeln('requested_pages: ${pageRange.label}')
        ..writeln('requested_page_count: ${pageRange.pageCount}')
        ..writeln(
          'requested_pages_note: Page-range text extraction is not available in this runtime; only PDF metadata is returned.',
        );
    }
    buffer.writeln(
      'preview: PDF files are not line-addressable in this runtime.',
    );
    return RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: '.pdf',
      renderMode: 'pdf',
      lineAddressable: false,
    );
  }

  RenderedReadContent _renderBinary(
    List<int> bytes,
    String filePath,
    String extension, {
    required int totalByteSize,
    required bool truncated,
  }) {
    final previewBytes = bytes.take(AiToolUtils.maxBinaryPreviewBytes).toList();
    final hexPreview = bytesToHex(previewBytes, separator: ' ');
    final buffer = StringBuffer()
      ..writeln('file_type: binary')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: $totalByteSize');
    if (extension.isNotEmpty) buffer.writeln('extension: $extension');
    if (hexPreview.isNotEmpty) buffer.writeln('hex_preview: $hexPreview');
    if (truncated) {
      buffer.writeln(
        'preview_scope: first ${bytes.length} bytes captured for binary inspection',
      );
    }
    buffer.writeln(
      'preview: Binary files are not line-addressable in this runtime.',
    );
    return RenderedReadContent(
      content: buffer.toString().trimRight(),
      fileKind: extension.isEmpty ? 'binary' : extension,
      renderMode: 'binary',
      lineAddressable: false,
      truncated: truncated,
    );
  }

  String _renderNotebookValue(Object? value) {
    if (value is List) return value.map((item) => '$item').join();
    if (value is Map) {
      final textPlain = value[kTextPlainMimeType];
      if (textPlain != null) return _renderNotebookValue(textPlain);
      return prettyPrintJson(value);
    }
    return '$value'.trim();
  }

  String _readText(Object? value) {
    return stringFromValue(value, ignoreLiteralNull: true);
  }
}

class AiPdfPageRange {
  const AiPdfPageRange({required this.label, required this.pageCount});

  final String label;
  final int pageCount;
}

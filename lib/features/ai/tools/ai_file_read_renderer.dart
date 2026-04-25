import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'ai_read_tool.dart';
import 'ai_tool_utils.dart';

class AiFileReadRenderer {
  const AiFileReadRenderer();

  Future<RenderedReadContent> render(File file, String filePath) async {
    final extension = p.extension(filePath).toLowerCase();
    if (extension == '.ipynb') {
      return RenderedReadContent(
        content: await _renderNotebookForRead(file),
        fileKind: extension,
        renderMode: 'notebook',
        lineAddressable: true,
      );
    }
    final fileLength = await file.length();
    if (fileLength == 0) {
      return RenderedReadContent(
        content: '',
        fileKind: extension.isEmpty ? 'text' : extension,
        renderMode: 'text',
        lineAddressable: true,
      );
    }
    if (AiToolUtils.isRasterImageExtension(extension)) {
      final bytes = await file.readAsBytes();
      return _renderImage(bytes, filePath, extension);
    }
    if (extension == '.pdf') {
      final bytes = await file.readAsBytes();
      return _renderPdf(bytes, filePath);
    }
    final bytes = await AiToolUtils.readFilePrefix(file, fileLength);
    final truncated = fileLength > bytes.length;
    if (AiToolUtils.looksBinary(bytes) &&
        !AiToolUtils.isKnownTextExtension(extension)) {
      return _renderBinary(
        bytes,
        filePath,
        extension,
        totalByteSize: fileLength,
        truncated: truncated,
      );
    }
    var content = AiToolUtils.decodeTextBytes(bytes);
    if (truncated) {
      content =
          '${AiToolUtils.truncateContent(content, AiToolUtils.maxFileCharacters)}'
          '\n\n[truncated: showing the first ${bytes.length} bytes of $fileLength bytes]';
    } else {
      content = AiToolUtils.truncateContent(
        content,
        AiToolUtils.maxFileCharacters,
      );
    }
    return RenderedReadContent(
      content: content,
      fileKind: extension.isEmpty ? 'text' : extension,
      renderMode: 'text',
      lineAddressable: true,
      truncated: truncated,
    );
  }

  Future<String> _renderNotebookForRead(File file) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (_) {
      return '';
    }
    if (decoded is! Map) return '';
    final notebook = Map<String, Object?>.from(decoded);
    final rawCells = notebook['cells'];
    if (rawCells is! List || rawCells.isEmpty) return '';
    final buffer = StringBuffer();
    for (var index = 0; index < rawCells.length; index++) {
      final cell = _asMap(rawCells[index]) ?? const <String, Object?>{};
      final cellType = _readText(cell['cell_type']);
      buffer.writeln('# Cell $index [$cellType]');
      final source = _renderNotebookValue(cell['source']);
      if (source.isNotEmpty) buffer.writeln(source.trimRight());
      final outputs = cell['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        buffer.writeln('## Outputs');
        for (final output in outputs) {
          final outputMap = _asMap(output) ?? const <String, Object?>{};
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
    final decodedImage = img.decodeImage(Uint8List.fromList(bytes));
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

  RenderedReadContent _renderPdf(List<int> bytes, String filePath) {
    final latinText = latin1.decode(bytes, allowInvalid: true);
    final headerLine = latinText.split(RegExp(r'[\r\n]')).first.trim();
    final pageCount = RegExp(r'/Type\s*/Page\b').allMatches(latinText).length;
    final buffer = StringBuffer()
      ..writeln('file_type: pdf')
      ..writeln('path: $filePath')
      ..writeln('size_bytes: ${bytes.length}');
    if (headerLine.isNotEmpty) buffer.writeln('header: $headerLine');
    if (pageCount > 0) buffer.writeln('page_count_estimate: $pageCount');
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
    final hexPreview = previewBytes
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join(' ');
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
      final textPlain = value['text/plain'];
      if (textPlain != null) return _renderNotebookValue(textPlain);
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return '$value'.trim();
  }

  Map<String, Object?>? _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return null;
  }

  String _readText(Object? value) {
    final text = '$value'.trim();
    return text == 'null' ? '' : text;
  }
}

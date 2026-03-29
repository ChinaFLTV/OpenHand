import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import '../model/ai_attachment.dart';

class AiAttachmentException implements Exception {
  const AiAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiAttachmentService {
  AiAttachmentService({required String attachmentsDirectoryPath})
    : _attachmentsDirectoryPath = attachmentsDirectoryPath;

  static const int maxAttachmentPromptCharactersPerFile = 8000;
  static const int maxAttachmentPromptCharactersPerMessage = 32000;
  static const int _minAttachmentPromptCharactersPerFile = 512;
  static const int _maxInlineImageDimension = 1568;
  static const int _maxTextRawBytes = 2 * 1024 * 1024;
  static const int _maxSpreadsheetSheets = 3;
  static const int _maxSpreadsheetRowsPerSheet = 32;
  static const int _maxSpreadsheetArchiveBytes = 8 * 1024 * 1024;
  static const int _maxZipEntryBytes = 4 * 1024 * 1024;
  static const int _maxPdfRawBytes = 2 * 1024 * 1024;

  final String _attachmentsDirectoryPath;

  String get attachmentsDirectoryPath => _attachmentsDirectoryPath;

  Future<void> deleteMessageAttachments({
    required String sessionId,
    required String messageId,
  }) async {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: 'session id',
    );
    final normalizedMessageId = _requireSafeStorageIdentifier(
      messageId,
      label: 'message id',
    );
    final directory = Directory(
      p.join(
        _attachmentsDirectoryPath,
        normalizedSessionId,
        normalizedMessageId,
      ),
    );
    await _deleteDirectoryIfExists(directory);
  }

  Future<List<AiMessageAttachment>> importAttachments({
    required String sessionId,
    required String messageId,
    required List<String> filePaths,
    required String Function() idGenerator,
  }) async {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: 'session id',
    );
    final normalizedMessageId = _requireSafeStorageIdentifier(
      messageId,
      label: 'message id',
    );
    if (filePaths.isEmpty) {
      return const <AiMessageAttachment>[];
    }
    if (filePaths.length > aiMessageAttachmentLimit) {
      throw AiAttachmentException(
        'A single message supports at most $aiMessageAttachmentLimit attachments.',
      );
    }
    final targetDirectory = Directory(
      p.join(
        _attachmentsDirectoryPath,
        normalizedSessionId,
        normalizedMessageId,
      ),
    );
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }
    final attachments = <AiMessageAttachment>[];
    var remainingPromptBudget = maxAttachmentPromptCharactersPerMessage;
    try {
      for (var index = 0; index < filePaths.length; index++) {
        final sourcePath = p.normalize(filePaths[index].trim());
        if (sourcePath.isEmpty) {
          continue;
        }
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists()) {
          throw AiAttachmentException(
            'Attachment file does not exist: $sourcePath',
          );
        }
        final remainingAttachments = filePaths.length - index;
        final reservedBudgetForRemaining = math.max(
          0,
          (remainingAttachments - 1) * _minAttachmentPromptCharactersPerFile,
        );
        final fairShareBudget = remainingPromptBudget ~/ remainingAttachments;
        final minimumBudget = math.min(
          _minAttachmentPromptCharactersPerFile,
          remainingPromptBudget,
        );
        var filePromptBudget = math.min(
          maxAttachmentPromptCharactersPerFile,
          math.max(minimumBudget, fairShareBudget),
        );
        final maxAllowedForCurrent = math.max(
          0,
          remainingPromptBudget - reservedBudgetForRemaining,
        );
        if (maxAllowedForCurrent > 0) {
          filePromptBudget = math.min(filePromptBudget, maxAllowedForCurrent);
        } else {
          filePromptBudget = math.min(
            maxAttachmentPromptCharactersPerFile,
            remainingPromptBudget,
          );
        }
        final attachment = await _importSingleAttachment(
          sourceFile: sourceFile,
          targetDirectory: targetDirectory,
          sequence: index + 1,
          idGenerator: idGenerator,
          promptCharacterLimit: filePromptBudget,
        );
        attachments.add(attachment);
        remainingPromptBudget = math.max(
          0,
          remainingPromptBudget - attachment.promptText.length,
        );
      }
    } on Object {
      await _deleteDirectoryIfExists(targetDirectory);
      rethrow;
    }
    return attachments;
  }

  Future<AiMessageAttachment> _importSingleAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required int sequence,
    required String Function() idGenerator,
    required int promptCharacterLimit,
  }) async {
    final sourcePath = sourceFile.path;
    final stat = await sourceFile.stat();
    final sourceName = p.basename(sourcePath).trim();
    final normalizedName = sourceName.isEmpty
        ? 'attachment-$sequence'
        : sourceName;
    final kind = aiAttachmentKindForPath(sourcePath);
    return switch (kind) {
      AiAttachmentKind.image => _importImageAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        idGenerator: idGenerator,
        promptCharacterLimit: promptCharacterLimit,
      ),
      AiAttachmentKind.text => _importTextAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        idGenerator: idGenerator,
        promptCharacterLimit: promptCharacterLimit,
      ),
      AiAttachmentKind.spreadsheet => _importSpreadsheetAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        idGenerator: idGenerator,
        promptCharacterLimit: promptCharacterLimit,
      ),
      AiAttachmentKind.pdf => _importPdfAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        idGenerator: idGenerator,
        promptCharacterLimit: promptCharacterLimit,
      ),
      AiAttachmentKind.binary => _importBinaryAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        idGenerator: idGenerator,
        fileSizeBytes: stat.size,
      ),
    };
  }

  Future<AiMessageAttachment> _importImageAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String Function() idGenerator,
    required int promptCharacterLimit,
  }) async {
    final extension = p.extension(sourceName).toLowerCase();
    final sourceBytes = await sourceFile.readAsBytes();
    final decodedImage = extension == '.svg'
        ? null
        : img.decodeImage(sourceBytes);
    var outputBytes = Uint8List.fromList(sourceBytes);
    var width = decodedImage?.width;
    var height = decodedImage?.height;
    var targetName = _targetFileName(sequence, sourceName);
    if (decodedImage != null) {
      final resizedImage = _resizeImageIfNeeded(decodedImage);
      width = resizedImage.width;
      height = resizedImage.height;
      if (extension == '.png') {
        outputBytes = Uint8List.fromList(img.encodePng(resizedImage));
      } else {
        outputBytes = Uint8List.fromList(
          img.encodeJpg(resizedImage, quality: 86),
        );
        targetName = _replaceExtension(targetName, '.jpg');
      }
    }
    final targetFile = File(p.join(targetDirectory.path, targetName));
    await targetFile.writeAsBytes(outputBytes, flush: true);
    final summary = StringBuffer()
      ..write('Image attachment: $sourceName')
      ..write(' (${aiFormatBytes(outputBytes.length)}');
    if (width != null && height != null) {
      summary.write(', ${width}x$height');
    }
    summary.write(').');
    final summaryText = summary.toString();
    return AiMessageAttachment(
      id: idGenerator(),
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.image,
      mimeType: aiMimeTypeForPath(targetFile.path),
      sizeBytes: outputBytes.length,
      promptText: _truncateText(summaryText, promptCharacterLimit),
      summaryText: summaryText,
      width: width,
      height: height,
    );
  }

  Future<AiMessageAttachment> _importTextAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String Function() idGenerator,
    required int promptCharacterLimit,
  }) async {
    final targetFile = await _copyFile(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      targetName: _targetFileName(sequence, sourceName),
    );
    final rawText = await _readTextFile(
      sourceFile,
      characterLimit: promptCharacterLimit,
    );
    final promptText = _buildDocumentPromptText(
      sourceName: sourceName,
      typeLabel: _textTypeLabel(sourceFile.path),
      excerpt: rawText,
      characterLimit: promptCharacterLimit,
    );
    return AiMessageAttachment(
      id: idGenerator(),
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.text,
      mimeType: aiMimeTypeForPath(sourceFile.path),
      sizeBytes: await targetFile.length(),
      promptText: promptText,
      summaryText: _summaryFromPrompt(promptText),
    );
  }

  Future<AiMessageAttachment> _importSpreadsheetAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String Function() idGenerator,
    required int promptCharacterLimit,
  }) async {
    final targetFile = await _copyFile(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      targetName: _targetFileName(sequence, sourceName),
    );
    final extension = p.extension(sourceName).toLowerCase();
    final excerpt = extension == '.xlsx'
        ? await _readXlsxPreview(sourceFile, promptCharacterLimit)
        : 'Legacy XLS preview is not available in this runtime. Keep the file name and use the surrounding prompt to explain what to inspect.';
    final promptText = _buildDocumentPromptText(
      sourceName: sourceName,
      typeLabel: 'spreadsheet',
      excerpt: excerpt,
      characterLimit: promptCharacterLimit,
    );
    return AiMessageAttachment(
      id: idGenerator(),
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.spreadsheet,
      mimeType: aiMimeTypeForPath(sourceFile.path),
      sizeBytes: await targetFile.length(),
      promptText: promptText,
      summaryText: _summaryFromPrompt(promptText),
    );
  }

  Future<AiMessageAttachment> _importPdfAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String Function() idGenerator,
    required int promptCharacterLimit,
  }) async {
    final targetFile = await _copyFile(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      targetName: _targetFileName(sequence, sourceName),
    );
    final excerpt = await _readPdfPreview(sourceFile, promptCharacterLimit);
    final promptText = _buildDocumentPromptText(
      sourceName: sourceName,
      typeLabel: 'pdf',
      excerpt: excerpt,
      characterLimit: promptCharacterLimit,
    );
    return AiMessageAttachment(
      id: idGenerator(),
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.pdf,
      mimeType: 'application/pdf',
      sizeBytes: await targetFile.length(),
      promptText: promptText,
      summaryText: _summaryFromPrompt(promptText),
    );
  }

  Future<AiMessageAttachment> _importBinaryAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String Function() idGenerator,
    required int fileSizeBytes,
  }) async {
    final targetFile = await _copyFile(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      targetName: _targetFileName(sequence, sourceName),
    );
    final summaryText =
        'Binary attachment: $sourceName (${aiFormatBytes(fileSizeBytes)}). No structured preview is available in this runtime.';
    return AiMessageAttachment(
      id: idGenerator(),
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.binary,
      mimeType: aiMimeTypeForPath(sourceFile.path),
      sizeBytes: await targetFile.length(),
      promptText: summaryText,
      summaryText: summaryText,
    );
  }

  img.Image _resizeImageIfNeeded(img.Image source) {
    final maxSide = math.max(source.width, source.height);
    if (maxSide <= _maxInlineImageDimension) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: _maxInlineImageDimension);
    }
    return img.copyResize(source, height: _maxInlineImageDimension);
  }

  Future<File> _copyFile({
    required File sourceFile,
    required Directory targetDirectory,
    required String targetName,
  }) async {
    final targetFile = File(p.join(targetDirectory.path, targetName));
    await sourceFile.copy(targetFile.path);
    return targetFile;
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (!await directory.exists()) {
      return;
    }
    await directory.delete(recursive: true);
    await _deleteEmptyAttachmentAncestors(directory.parent);
  }

  Future<void> _deleteEmptyAttachmentAncestors(Directory directory) async {
    final rootPath = p.normalize(_attachmentsDirectoryPath);
    var current = directory;
    while (true) {
      final currentPath = p.normalize(current.path);
      if (currentPath == rootPath || !p.isWithin(rootPath, currentPath)) {
        return;
      }
      if (!await current.exists()) {
        current = current.parent;
        continue;
      }
      final entries = await current.list(followLinks: false).take(1).toList();
      if (entries.isNotEmpty) {
        return;
      }
      await current.delete();
      current = current.parent;
    }
  }

  String _targetFileName(int sequence, String sourceName) {
    final sanitized = sourceName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final normalized = sanitized.isEmpty ? 'attachment' : sanitized;
    return '${sequence.toString().padLeft(2, '0')}-$normalized';
  }

  String _replaceExtension(String fileName, String nextExtension) {
    return '${p.basenameWithoutExtension(fileName)}$nextExtension';
  }

  Future<String> _readTextFile(File file, {required int characterLimit}) async {
    final fileLength = await file.length();
    final readLength = math.min(fileLength, _maxTextRawBytes);
    final raf = await file.open();
    try {
      final bytes = await raf.read(readLength);
      final decoded = _decodeTextBytes(bytes);
      final buffer = StringBuffer(decoded.trim());
      if (fileLength > readLength) {
        if (buffer.isNotEmpty) {
          buffer
            ..writeln()
            ..writeln();
        }
        buffer.write(
          '[preview truncated: read ${aiFormatBytes(readLength)} from ${aiFormatBytes(fileLength)}]',
        );
      }
      return _truncateText(buffer.toString().trim(), characterLimit);
    } finally {
      await raf.close();
    }
  }

  String _decodeTextBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Future<String> _readPdfPreview(File file, int characterLimit) async {
    final fileLength = await file.length();
    final readLength = math.min(fileLength, _maxPdfRawBytes);
    final raf = await file.open();
    try {
      final bytes = await raf.read(readLength);
      final latin = latin1.decode(bytes, allowInvalid: true);
      final buffer = StringBuffer();
      final textMatchPattern = RegExp(r'\(([^()]{2,})\)\s*Tj');
      for (final match in textMatchPattern.allMatches(latin)) {
        final text = _decodePdfString(match.group(1) ?? '');
        if (text.isEmpty) {
          continue;
        }
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.write(text);
        if (buffer.length >= characterLimit) {
          break;
        }
      }
      if (buffer.isEmpty) {
        final fallback = latin
            .replaceAll(RegExp(r'[^\x20-\x7E\u4E00-\u9FFF\r\n\t]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (fallback.isNotEmpty) {
          buffer.write(fallback);
        }
      }
      if (fileLength > readLength) {
        buffer
          ..writeln()
          ..writeln()
          ..write(
            '[preview truncated: read ${aiFormatBytes(readLength)} from ${aiFormatBytes(fileLength)}]',
          );
      }
      return _truncateText(buffer.toString().trim(), characterLimit);
    } finally {
      await raf.close();
    }
  }

  String _decodePdfString(String input) {
    return input
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', '\\')
        .trim();
  }

  Future<String> _readXlsxPreview(File file, int characterLimit) async {
    try {
      final fileLength = await file.length();
      if (fileLength > _maxSpreadsheetArchiveBytes) {
        return 'XLSX preview skipped because the archive exceeds ${aiFormatBytes(_maxSpreadsheetArchiveBytes)}.';
      }
      final bytes = await file.readAsBytes();
      final archive = _ZipArchiveReader(
        Uint8List.fromList(bytes),
        maxEntryBytes: _maxZipEntryBytes,
      );
      final workbookXml = archive.readUtf8('xl/workbook.xml');
      final relationsXml = archive.readUtf8('xl/_rels/workbook.xml.rels');
      if (workbookXml == null || relationsXml == null) {
        return 'Unable to read workbook structure from the XLSX file.';
      }
      final workbookDocument = xml.XmlDocument.parse(workbookXml);
      final relationsDocument = xml.XmlDocument.parse(relationsXml);
      final sharedStringsXml = archive.readUtf8('xl/sharedStrings.xml');
      final sharedStrings = sharedStringsXml == null
          ? const <String>[]
          : _parseSharedStrings(xml.XmlDocument.parse(sharedStringsXml));
      final relationTargets = <String, String>{};
      for (final relation in relationsDocument.findAllElements(
        'Relationship',
      )) {
        final relationId = _attributeByLocalName(relation, 'Id');
        final target = _attributeByLocalName(relation, 'Target');
        if (relationId == null || target == null) {
          continue;
        }
        relationTargets[relationId] = p.posix.normalize(
          p.posix.join('xl', target),
        );
      }
      final buffer = StringBuffer();
      var renderedSheets = 0;
      for (final sheet in workbookDocument.findAllElements('sheet')) {
        if (renderedSheets >= _maxSpreadsheetSheets ||
            buffer.length >= characterLimit) {
          break;
        }
        final sheetName = _attributeByLocalName(sheet, 'name') ?? 'Sheet';
        final relationId = _attributeByLocalName(sheet, 'id');
        if (relationId == null) {
          continue;
        }
        final targetPath = relationTargets[relationId];
        if (targetPath == null) {
          continue;
        }
        final sheetXml = archive.readUtf8(targetPath);
        if (sheetXml == null) {
          continue;
        }
        final sheetPreview = _renderWorksheetPreview(
          xml.XmlDocument.parse(sheetXml),
          sharedStrings,
          characterLimit - buffer.length,
        );
        if (sheetPreview.isEmpty) {
          continue;
        }
        if (buffer.isNotEmpty) {
          buffer.writeln();
          buffer.writeln();
        }
        buffer
          ..writeln('Sheet: $sheetName')
          ..write(sheetPreview);
        renderedSheets += 1;
      }
      if (buffer.isEmpty) {
        return 'The XLSX workbook did not contain any readable cells in the preview range.';
      }
      return _truncateText(buffer.toString().trim(), characterLimit);
    } catch (_) {
      return 'Unable to read workbook structure from the XLSX file.';
    }
  }

  List<String> _parseSharedStrings(xml.XmlDocument document) {
    return document
        .findAllElements('si')
        .map(
          (item) =>
              item.findAllElements('t').map((node) => node.innerText).join(),
        )
        .toList(growable: false);
  }

  String _renderWorksheetPreview(
    xml.XmlDocument document,
    List<String> sharedStrings,
    int characterLimit,
  ) {
    final rows = <String>[];
    for (final row in document.findAllElements('row')) {
      if (rows.length >= _maxSpreadsheetRowsPerSheet) {
        break;
      }
      final cells = <int, String>{};
      for (final cell in row.findElements('c')) {
        final ref = _attributeByLocalName(cell, 'r') ?? '';
        final cellType = _attributeByLocalName(cell, 't') ?? '';
        final cellValue = _readWorksheetCellValue(
          cell,
          cellType,
          sharedStrings,
        );
        if (cellValue.isEmpty) {
          continue;
        }
        final columnIndex = _columnIndexFromCellRef(ref);
        cells[columnIndex] = cellValue;
      }
      if (cells.isEmpty) {
        continue;
      }
      final maxColumnIndex = cells.keys.fold<int>(0, math.max);
      final ordered = <String>[];
      for (var columnIndex = 0; columnIndex <= maxColumnIndex; columnIndex++) {
        ordered.add(cells[columnIndex] ?? '');
      }
      final rowText = ordered.join('\t').trimRight();
      if (rowText.isEmpty) {
        continue;
      }
      rows.add(rowText);
      final currentPreview = rows.join('\n');
      if (currentPreview.length >= characterLimit) {
        break;
      }
    }
    return _truncateText(rows.join('\n').trim(), characterLimit);
  }

  String _readWorksheetCellValue(
    xml.XmlElement cell,
    String cellType,
    List<String> sharedStrings,
  ) {
    if (cellType == 'inlineStr') {
      return cell
          .findAllElements('t')
          .map((item) => item.innerText)
          .join()
          .trim();
    }
    final rawValue = cell.getElement('v')?.innerText.trim() ?? '';
    if (rawValue.isEmpty) {
      return '';
    }
    if (cellType == 's') {
      final index = int.tryParse(rawValue);
      if (index == null || index < 0 || index >= sharedStrings.length) {
        return '';
      }
      return sharedStrings[index].trim();
    }
    if (cellType == 'b') {
      return rawValue == '1' ? 'TRUE' : 'FALSE';
    }
    return rawValue;
  }

  int _columnIndexFromCellRef(String ref) {
    final match = RegExp(r'([A-Z]+)', caseSensitive: false).firstMatch(ref);
    if (match == null) {
      return 0;
    }
    final letters = (match.group(1) ?? '').toUpperCase();
    var value = 0;
    for (final codeUnit in letters.codeUnits) {
      value = value * 26 + (codeUnit - 64);
    }
    return math.max(0, value - 1);
  }

  String? _attributeByLocalName(xml.XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) {
        return attribute.value;
      }
    }
    return null;
  }

  String _buildDocumentPromptText({
    required String sourceName,
    required String typeLabel,
    required String excerpt,
    required int characterLimit,
  }) {
    final buffer = StringBuffer()
      ..writeln('Attachment: $sourceName')
      ..writeln('Type: $typeLabel');
    final normalizedExcerpt = excerpt.trim();
    if (normalizedExcerpt.isEmpty) {
      buffer.write(
        'Preview: No readable text was extracted from this attachment.',
      );
    } else {
      buffer
        ..writeln()
        ..writeln('Extracted preview:')
        ..write(normalizedExcerpt);
    }
    return _truncateText(buffer.toString().trim(), characterLimit);
  }

  String _summaryFromPrompt(String promptText) {
    final lines = promptText
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return lines.join(' · ');
  }

  String _textTypeLabel(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return switch (extension) {
      '.md' || '.markdown' => 'markdown',
      '.csv' => 'csv',
      '.tsv' => 'tsv',
      '.json' => 'json',
      '.yaml' || '.yml' => 'yaml',
      '.xml' => 'xml',
      _ => 'text',
    };
  }

  String _truncateText(String input, int characterLimit) {
    final trimmed = input.trim();
    if (characterLimit <= 0 || trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length <= characterLimit) {
      return trimmed;
    }
    if (characterLimit <= 18) {
      return trimmed.substring(0, math.min(characterLimit, trimmed.length));
    }
    final safeLimit = math.min(
      trimmed.length,
      math.max(1, characterLimit - 18),
    );
    return '${trimmed.substring(0, safeLimit).trimRight()}\n\n[truncated]';
  }
}

class _ZipArchiveReader {
  _ZipArchiveReader(this.bytes, {required this.maxEntryBytes})
    : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final int maxEntryBytes;
  final ByteData _data;
  Map<String, _ZipEntry>? _entries;

  String? readUtf8(String name) {
    final entry = _entryFor(name);
    if (entry == null) {
      return null;
    }
    final content = _readEntryBytes(entry);
    if (content == null) {
      return null;
    }
    try {
      return utf8.decode(content);
    } on FormatException {
      return utf8.decode(content, allowMalformed: true);
    }
  }

  _ZipEntry? _entryFor(String name) {
    _entries ??= _parseEntries();
    return _entries![name];
  }

  Map<String, _ZipEntry> _parseEntries() {
    final endOfCentralDirectoryOffset = _findEndOfCentralDirectoryOffset();
    if (endOfCentralDirectoryOffset == -1) {
      return const <String, _ZipEntry>{};
    }
    final totalEntries = _readUint16(endOfCentralDirectoryOffset + 10);
    final centralDirectoryOffset = _readUint32(
      endOfCentralDirectoryOffset + 16,
    );
    final entries = <String, _ZipEntry>{};
    var cursor = centralDirectoryOffset;
    for (var index = 0; index < totalEntries; index++) {
      if (_readUint32(cursor) != 0x02014b50) {
        break;
      }
      final compressionMethod = _readUint16(cursor + 10);
      final compressedSize = _readUint32(cursor + 20);
      final uncompressedSize = _readUint32(cursor + 24);
      final fileNameLength = _readUint16(cursor + 28);
      final extraFieldLength = _readUint16(cursor + 30);
      final fileCommentLength = _readUint16(cursor + 32);
      final localHeaderOffset = _readUint32(cursor + 42);
      final nameStart = cursor + 46;
      final nameEnd = nameStart + fileNameLength;
      final name = utf8.decode(
        bytes.sublist(nameStart, nameEnd),
        allowMalformed: true,
      );
      entries[name] = _ZipEntry(
        name: name,
        compressionMethod: compressionMethod,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset,
      );
      cursor = nameEnd + extraFieldLength + fileCommentLength;
    }
    return entries;
  }

  Uint8List? _readEntryBytes(_ZipEntry entry) {
    if (entry.compressedSize > maxEntryBytes ||
        entry.uncompressedSize > maxEntryBytes) {
      return null;
    }
    final localHeaderOffset = entry.localHeaderOffset;
    if (_readUint32(localHeaderOffset) != 0x04034b50) {
      return null;
    }
    final fileNameLength = _readUint16(localHeaderOffset + 26);
    final extraFieldLength = _readUint16(localHeaderOffset + 28);
    final dataOffset =
        localHeaderOffset + 30 + fileNameLength + extraFieldLength;
    final dataEnd = dataOffset + entry.compressedSize;
    if (dataOffset < 0 || dataEnd > bytes.length || dataOffset >= dataEnd) {
      return null;
    }
    final payload = bytes.sublist(dataOffset, dataEnd);
    if (entry.compressionMethod == 0) {
      return Uint8List.fromList(payload);
    }
    if (entry.compressionMethod == 8) {
      try {
        final decoded = ZLibCodec(raw: true).decode(payload);
        if (decoded.length > maxEntryBytes) {
          return null;
        }
        return Uint8List.fromList(decoded);
      } on Object {
        return null;
      }
    }
    return null;
  }

  int _findEndOfCentralDirectoryOffset() {
    final minOffset = math.max(0, bytes.length - 65557);
    for (var offset = bytes.length - 22; offset >= minOffset; offset--) {
      if (_readUint32(offset) == 0x06054b50) {
        return offset;
      }
    }
    return -1;
  }

  int _readUint16(int offset) => _data.getUint16(offset, Endian.little);

  int _readUint32(int offset) => _data.getUint32(offset, Endian.little);
}

class _ZipEntry {
  const _ZipEntry({
    required this.name,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String name;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}

final RegExp _unsafeAttachmentStorageIdentifierPattern = RegExp(
  r'[\u0000-\u001F\u007F/\\]',
);

String _requireSafeStorageIdentifier(String value, {required String label}) {
  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty ||
      normalizedValue == '.' ||
      normalizedValue == '..' ||
      _unsafeAttachmentStorageIdentifierPattern.hasMatch(normalizedValue)) {
    throw AiAttachmentException('Invalid $label: $value');
  }
  return normalizedValue;
}

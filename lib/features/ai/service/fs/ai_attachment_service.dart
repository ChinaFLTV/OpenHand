import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import '../../../../app/support/silent_log.dart';
import '../../../../shared/db/atomic_file_operations.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_delete.dart';
import '../../../../shared/util/bounded_directory_io.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/directory_cleanup.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/path_safety.dart';
import '../../../../shared/util/storage_identifier.dart';
import '../../model/ai_attachment.dart';

class AiAttachmentException implements Exception {
  const AiAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiAttachmentService {
  AiAttachmentService({
    required String attachmentsDirectoryPath,
    String Function(String sessionId)? perSessionAttachmentsDirectoryPath,
  }) : _attachmentsDirectoryPath = attachmentsDirectoryPath,
       _perSessionAttachmentsDirectoryPath = perSessionAttachmentsDirectoryPath;

  static const int maxAttachmentPromptCharactersPerFile = 8000;
  static const int maxAttachmentPromptCharactersPerMessage = 32000;
  static const int _minAttachmentPromptCharactersPerFile = 512;
  int maxInlineImageDimension = 1568;
  int maxTextRawBytes = 2 * kBytesPerMiB;
  static const int _maxSpreadsheetSheets = 3;
  static const int _maxSpreadsheetRowsPerSheet = 32;
  static const int _maxSpreadsheetArchiveBytes = 8 * kBytesPerMiB;
  static const int _maxZipEntryBytes = 4 * kBytesPerMiB;
  static const int _maxStoredAttachmentBytes = kBytesPerGiB;
  static const int _maxImageRawBytesHardLimit = 64 * kBytesPerMiB;
  static const int _maxDecodedImagePixels = 40 * 1000 * 1000;
  static const int _maxPdfTextSpanMatches = 10000;
  static const int _maxAttachmentCleanupEntries = 100000;
  static const BoundedDeletePolicy _attachmentDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: _maxAttachmentCleanupEntries,
        maxDepth: 64,
      );
  static final RegExp _pdfTextSpanPattern = RegExp(r'\(([^()]{2,})\)\s*Tj');
  static final RegExp _pdfFallbackUnsupportedCharsPattern = RegExp(
    r'[^\x20-\x7E\u4E00-\u9FFF\r\n\t]+',
  );
  static final RegExp _pdfFallbackWhitespacePattern = RegExp(r'\s+');
  static final RegExp _spreadsheetColumnRefPattern = RegExp(
    r'([A-Z]+)',
    caseSensitive: false,
  );
  int maxPdfRawBytes = 2 * kBytesPerMiB;

  final String _attachmentsDirectoryPath;
  final String Function(String sessionId)? _perSessionAttachmentsDirectoryPath;

  String get attachmentsDirectoryPath => _attachmentsDirectoryPath;

  /// 解析 [sessionId] 新附件的写入目录。配置会话目录解析器时使用新版布局：
  /// `~/.openhand/sessions/{sessionId}/attachments/{messageId}-{attachmentId}.{ext}`。
  /// 否则回退到旧版消息子目录布局。
  String _resolveTargetDirectoryPath({
    required String sessionId,
    required String messageId,
  }) {
    final resolver = _perSessionAttachmentsDirectoryPath;
    if (resolver != null) {
      return resolver(sessionId);
    }
    return p.join(_attachmentsDirectoryPath, sessionId, messageId);
  }

  bool get _useModernLayout => _perSessionAttachmentsDirectoryPath != null;

  Future<void> deleteMessageAttachments({
    required String sessionId,
    required String messageId,
  }) async {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    final normalizedMessageId = _requireSafeStorageIdentifier(
      messageId,
      label: '消息标识符',
    );
    if (_useModernLayout) {
      // 新版布局的文件同处会话附件目录，仅删除带目标消息前缀的文件。
      final sessionDirPath = _resolveTargetDirectoryPath(
        sessionId: normalizedSessionId,
        messageId: normalizedMessageId,
      );
      final sessionDir = Directory(sessionDirPath);
      if (await sessionDir.exists().timeout(
        defaultBoundedFileReadIdleTimeout,
      )) {
        final prefix = '$normalizedMessageId-';
        final listing = await listDirectoryBounded(
          sessionDir,
          maxEntries: _maxAttachmentCleanupEntries,
        );
        for (final entity in listing.entries) {
          if (entity is! File) {
            continue;
          }
          final basename = p.basename(entity.path);
          if (basename.startsWith(prefix)) {
            try {
              await entity.delete().timeout(defaultBoundedFileReadIdleTimeout);
            } catch (error, stack) {
              silentLog('ai_attachment_service', '删除旧版附件文件', error, stack);
            }
          }
        }
        await _maybeDeleteIfEmpty(sessionDir);
      }
      return;
    }
    final directory = Directory(
      p.join(
        _attachmentsDirectoryPath,
        normalizedSessionId,
        normalizedMessageId,
      ),
    );
    await _deleteDirectoryIfExists(directory);
  }

  Future<void> _maybeDeleteIfEmpty(Directory directory) async {
    try {
      if (await isDirectoryEmpty(directory)) {
        await directory.delete().timeout(defaultBoundedFileReadIdleTimeout);
      }
    } catch (error, stack) {
      silentLog('ai_attachment_service', '尝试删除空附件目录', error, stack);
    }
  }

  Future<List<AiMessageAttachment>> importAttachments({
    required String sessionId,
    required String messageId,
    required List<String> filePaths,
    required String Function() idGenerator,
    int? imageSizeLimitBytes,
  }) async {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    final normalizedMessageId = _requireSafeStorageIdentifier(
      messageId,
      label: '消息标识符',
    );
    if (filePaths.isEmpty) {
      return const <AiMessageAttachment>[];
    }
    if (filePaths.length > aiMessageAttachmentLimit) {
      throw const AiAttachmentException(
        'A single message supports at most $aiMessageAttachmentLimit attachments.',
      );
    }
    final targetDirectory = Directory(
      _resolveTargetDirectoryPath(
        sessionId: normalizedSessionId,
        messageId: normalizedMessageId,
      ),
    );
    if (!await targetDirectory.exists().timeout(
      defaultBoundedFileReadIdleTimeout,
    )) {
      await targetDirectory
          .create(recursive: true)
          .timeout(defaultBoundedFileReadIdleTimeout);
    }
    final attachments = <AiMessageAttachment>[];
    final createdFiles = <File>[];
    var remainingPromptBudget = maxAttachmentPromptCharactersPerMessage;
    try {
      for (var index = 0; index < filePaths.length; index++) {
        final sourcePath = p.normalize(filePaths[index].trim());
        if (sourcePath.isEmpty) {
          continue;
        }
        final sourceFile = File(sourcePath);
        if (!await sourceFile.exists().timeout(
          defaultBoundedFileReadIdleTimeout,
        )) {
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
          messageId: normalizedMessageId,
          idGenerator: idGenerator,
          promptCharacterLimit: filePromptBudget,
          imageSizeLimitBytes: imageSizeLimitBytes,
        );
        attachments.add(attachment);
        createdFiles.add(File(attachment.storagePath));
        remainingPromptBudget = math.max(
          0,
          remainingPromptBudget - attachment.promptText.length,
        );
      }
    } on Object {
      if (_useModernLayout) {
        // 仅回滚本次创建的文件，保留同一会话中其他消息的附件。
        for (final file in createdFiles) {
          try {
            if (await file.exists().timeout(
              defaultBoundedFileReadIdleTimeout,
            )) {
              await file.delete().timeout(defaultBoundedFileReadIdleTimeout);
            }
          } catch (error, stack) {
            silentLog('ai_attachment_service', '回滚已创建附件', error, stack);
          }
        }
      } else {
        await _deleteDirectoryIfExists(targetDirectory);
      }
      rethrow;
    }
    return attachments;
  }

  Future<List<AiMessageAttachment>> copyAttachmentsForFork({
    required String targetSessionId,
    required String targetMessageId,
    required List<AiMessageAttachment> attachments,
    required String Function() idGenerator,
  }) async {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      targetSessionId,
      label: '目标会话标识符',
    );
    final normalizedMessageId = _requireSafeStorageIdentifier(
      targetMessageId,
      label: '目标消息标识符',
    );
    if (attachments.isEmpty) {
      return const <AiMessageAttachment>[];
    }
    final targetDirectory = Directory(
      _resolveTargetDirectoryPath(
        sessionId: normalizedSessionId,
        messageId: normalizedMessageId,
      ),
    );
    await targetDirectory
        .create(recursive: true)
        .timeout(defaultBoundedFileReadIdleTimeout);
    final copied = <AiMessageAttachment>[];
    final usedAttachmentIds = <String>{};
    for (var index = 0; index < attachments.length; index += 1) {
      final attachment = attachments[index];
      final sourcePath = attachment.storagePath.trim();
      final sourceFile = File(sourcePath);
      if (sourcePath.isEmpty) {
        copied.add(attachment);
        continue;
      }
      try {
        if (!await sourceFile.exists().timeout(
          defaultBoundedFileReadIdleTimeout,
        )) {
          copied.add(attachment);
          continue;
        }
        final attachmentId = _safeForkAttachmentId(
          attachment.id,
          idGenerator,
          usedAttachmentIds,
        );
        final targetName = _composeForkTargetName(
          sequence: index + 1,
          attachment: attachment,
          messageId: normalizedMessageId,
          attachmentId: attachmentId,
        );
        final targetFile = await _copyFile(
          sourceFile: sourceFile,
          targetDirectory: targetDirectory,
          targetName: targetName,
        );
        copied.add(
          attachment.copyWith(
            id: attachmentId,
            storagePath: targetFile.path,
            sizeBytes: await targetFile.length().timeout(
              defaultBoundedFileReadIdleTimeout,
            ),
          ),
        );
      } catch (error, stack) {
        silentLog('ai_attachment_service', '复制分支附件', error, stack);
        copied.add(attachment);
      }
    }
    return List<AiMessageAttachment>.unmodifiable(copied);
  }

  Future<AiMessageAttachment> _importSingleAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required int sequence,
    required String messageId,
    required String Function() idGenerator,
    required int promptCharacterLimit,
    int? imageSizeLimitBytes,
  }) async {
    final sourcePath = sourceFile.path;
    final sourceName = p.basename(sourcePath).trim();
    final normalizedName = sourceName.isEmpty
        ? 'attachment-$sequence'
        : sourceName;
    final kind = aiAttachmentKindForPath(sourcePath);
    if (kind == AiAttachmentKind.image) {
      return _importImageAttachment(
        sourceFile: sourceFile,
        targetDirectory: targetDirectory,
        sourceName: normalizedName,
        sequence: sequence,
        messageId: messageId,
        idGenerator: idGenerator,
        promptCharacterLimit: promptCharacterLimit,
        imageSizeLimitBytes: imageSizeLimitBytes,
      );
    }
    final stat = await sourceFile.stat().timeout(
      defaultBoundedFileReadIdleTimeout,
    );
    final sizeLabel = aiFormatBytes(stat.size);
    return _importCopiedAttachment(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      sourceName: normalizedName,
      sequence: sequence,
      messageId: messageId,
      idGenerator: idGenerator,
      kind: kind,
      promptCharacterLimit: promptCharacterLimit,
      // PDF 的扩展名映射不一定被 aiMimeTypeForPath 覆盖，这里固定声明。
      mimeType: kind == AiAttachmentKind.pdf ? _pdfMimeType : null,
      // 兜底摘要只在无法提取正文时使用；未识别的新类型一律按不透明二进制描述。
      fallbackSummary: switch (kind) {
        AiAttachmentKind.video =>
          'Video attachment: $normalizedName '
              '($sizeLabel).',
        AiAttachmentKind.audio =>
          'Audio attachment: $normalizedName '
              '($sizeLabel).',
        _ =>
          'Binary attachment: $normalizedName ($sizeLabel). '
              'No structured preview is available in this runtime.',
      },
      describe: switch (kind) {
        AiAttachmentKind.text => () async => (
          typeLabel: _textTypeLabel(sourcePath),
          excerpt: await _readTextFile(
            sourceFile,
            characterLimit: promptCharacterLimit,
          ),
        ),
        AiAttachmentKind.spreadsheet => () async => (
          typeLabel: 'spreadsheet',
          excerpt: p.extension(normalizedName).toLowerCase() == '.xlsx'
              ? await _readXlsxPreview(sourceFile, promptCharacterLimit)
              : _legacyXlsPreviewNotice,
        ),
        AiAttachmentKind.pdf => () async => (
          typeLabel: 'pdf',
          excerpt: await _readPdfPreview(sourceFile, promptCharacterLimit),
        ),
        // 视频、音频与未识别的二进制没有可提取的正文，直接用兜底摘要。
        _ => null,
      },
    );
  }

  static const String _pdfMimeType = 'application/pdf';
  static const String _legacyXlsPreviewNotice =
      'Legacy XLS preview is not available in this runtime. Keep the file name '
      'and use the surrounding prompt to explain what to inspect.';

  int _maxImageRawBytes = 50 * kBytesPerMiB;
  int get maxImageRawBytes => _maxImageRawBytes;
  set maxImageRawBytes(int value) {
    _maxImageRawBytes = value.clamp(1, _maxImageRawBytesHardLimit);
  }

  Future<AiMessageAttachment> _importImageAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String messageId,
    required String Function() idGenerator,
    required int promptCharacterLimit,
    int? imageSizeLimitBytes,
  }) async {
    final extension = p.extension(sourceName).toLowerCase();
    final Uint8List sourceBytes;
    try {
      sourceBytes = await readBoundedFileBytes(
        sourceFile,
        maxBytes: maxImageRawBytes,
        idleTimeout: defaultBoundedFileReadIdleTimeout,
        totalTimeout: defaultBoundedFileReadTotalTimeout,
      );
    } on BoundedFileReadException catch (error) {
      if (error.failure != BoundedFileReadFailure.tooLarge) rethrow;
      throw AiAttachmentException(
        'Image file exceeds the ${aiFormatBytes(maxImageRawBytes)} limit.',
      );
    }
    final originalSize = sourceBytes.length;
    final attachmentId = idGenerator();
    late final Uint8List outputBytes;
    late final String outputExtension;
    int? width;
    int? height;
    if (extension == '.svg') {
      outputBytes = sourceBytes;
      outputExtension = extension;
    } else {
      try {
        final processed =
            await compute(_processRasterImageAttachment, <String, Object?>{
              'bytes': sourceBytes,
              'extension': extension,
              'max_dimension': maxInlineImageDimension,
              'max_output_bytes': imageSizeLimitBytes,
              'hard_max_output_bytes': _maxImageRawBytesHardLimit,
              'max_pixels': _maxDecodedImagePixels,
            });
        outputBytes = processed['bytes']! as Uint8List;
        outputExtension = processed['extension']! as String;
        width = processed['width'] as int?;
        height = processed['height'] as int?;
      } catch (error) {
        throw AiAttachmentException('处理图片附件失败：$error');
      }
    }
    final targetName = _useModernLayout
        ? '$messageId-$attachmentId$outputExtension'
        : _replaceExtension(
            _targetFileName(sequence, sourceName),
            outputExtension,
          );
    final targetFile = File(p.join(targetDirectory.path, targetName));
    await writeBytesFileAtomically(targetFile, outputBytes);
    final summary = StringBuffer()
      ..write('Image attachment: $sourceName')
      ..write(' (${aiFormatBytes(outputBytes.length)}');
    if (width != null && height != null) {
      summary.write(', ${width}x$height');
    }
    summary.write(').');
    final summaryText = summary.toString();
    final pixelCount = (width != null && height != null)
        ? width * height
        : null;
    final compressionRatio = originalSize > 0
        ? outputBytes.length / originalSize
        : null;
    return AiMessageAttachment(
      id: attachmentId,
      name: sourceName,
      storagePath: targetFile.path,
      kind: AiAttachmentKind.image,
      mimeType: aiMimeTypeForPath(targetFile.path),
      sizeBytes: outputBytes.length,
      promptText: _truncateText(summaryText, promptCharacterLimit),
      summaryText: summaryText,
      width: width,
      height: height,
      originalSourcePath: sourceFile.path,
      pixelCount: pixelCount,
      compressionRatio: compressionRatio,
    );
  }

  /// 原样落盘类附件的统一导入骨架：分配 id、复制副本、组装附件记录。
  ///
  /// 图片需要解码与压缩后才知道最终字节，因此单独走 [_importImageAttachment]。
  /// [describe] 在副本落盘后执行，读取的仍是原文件，与逐类实现时的时序一致；
  /// 返回 `null` 表示该类附件没有可提取的正文，此时用 [fallbackSummary] 兜底。
  Future<AiMessageAttachment> _importCopiedAttachment({
    required File sourceFile,
    required Directory targetDirectory,
    required String sourceName,
    required int sequence,
    required String messageId,
    required String Function() idGenerator,
    required AiAttachmentKind kind,
    required String fallbackSummary,
    Future<({String typeLabel, String excerpt})> Function()? describe,
    int promptCharacterLimit = 0,
    String? mimeType,
  }) async {
    final attachmentId = idGenerator();
    final targetFile = await _copyFile(
      sourceFile: sourceFile,
      targetDirectory: targetDirectory,
      targetName: _composeTargetName(
        sequence: sequence,
        sourceName: sourceName,
        messageId: messageId,
        attachmentId: attachmentId,
      ),
    );
    final described = await describe?.call();
    final promptText = described == null
        ? fallbackSummary
        : _buildDocumentPromptText(
            sourceName: sourceName,
            typeLabel: described.typeLabel,
            excerpt: described.excerpt,
            characterLimit: promptCharacterLimit,
          );
    return AiMessageAttachment(
      id: attachmentId,
      name: sourceName,
      storagePath: targetFile.path,
      kind: kind,
      mimeType: mimeType ?? aiMimeTypeForPath(sourceFile.path),
      sizeBytes: await targetFile.length().timeout(
        defaultBoundedFileReadIdleTimeout,
      ),
      promptText: promptText,
      summaryText: described == null
          ? fallbackSummary
          : _summaryFromPrompt(promptText),
      originalSourcePath: sourceFile.path,
    );
  }

  /// 生成非图片附件文件名；新版布局优先使用
  /// `<messageId>-<attachmentId>.<ext>`。
  String _composeTargetName({
    required int sequence,
    required String sourceName,
    required String messageId,
    required String attachmentId,
  }) {
    if (_useModernLayout) {
      final ext = p.extension(sourceName);
      return '$messageId-$attachmentId$ext';
    }
    return _targetFileName(sequence, sourceName);
  }

  String _composeForkTargetName({
    required int sequence,
    required AiMessageAttachment attachment,
    required String messageId,
    required String attachmentId,
  }) {
    final sourceName = attachment.name.trim().isEmpty
        ? p.basename(attachment.storagePath)
        : attachment.name.trim();
    if (_useModernLayout) {
      final extension = _attachmentExtension(attachment, sourceName);
      return '$messageId-$attachmentId$extension';
    }
    return _targetFileName(sequence, sourceName);
  }

  String _attachmentExtension(
    AiMessageAttachment attachment,
    String sourceName,
  ) {
    final fromStorage = p.extension(attachment.storagePath).trim();
    if (fromStorage.isNotEmpty) {
      return fromStorage;
    }
    return p.extension(sourceName).trim();
  }

  String _safeForkAttachmentId(
    String preferredId,
    String Function() idGenerator,
    Set<String> usedAttachmentIds,
  ) {
    final preferred = preferredId.trim();
    if (isSafeStorageIdentifier(preferred) &&
        usedAttachmentIds.add(preferred)) {
      return preferred;
    }
    for (var attempt = 0; attempt < 32; attempt += 1) {
      final generated = idGenerator().trim();
      if (isSafeStorageIdentifier(generated) &&
          usedAttachmentIds.add(generated)) {
        return generated;
      }
    }
    throw const AiAttachmentException(
      'Unable to allocate a unique attachment id.',
    );
  }

  Future<File> _copyFile({
    required File sourceFile,
    required Directory targetDirectory,
    required String targetName,
  }) async {
    final targetFile = File(p.join(targetDirectory.path, targetName));
    await copyFileAtomically(
      sourceFile,
      targetFile,
      maxBytes: _maxStoredAttachmentBytes,
    );
    return targetFile;
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    await deletePathBounded(
      p.absolute(directory.path),
      policy: _attachmentDeletePolicy,
      allowedRoot: p.absolute(_attachmentsDirectoryPath),
    );
    await deleteEmptyAncestorDirectories(
      start: directory.parent,
      stopAt: Directory(_attachmentsDirectoryPath),
    );
  }

  String _targetFileName(int sequence, String sourceName) {
    final normalized = sanitizePortableFileNamePart(
      sourceName,
      fallback: 'attachment',
    );
    return '${sequence.toString().padLeft(2, '0')}-$normalized';
  }

  String _replaceExtension(String fileName, String nextExtension) {
    return '${p.basenameWithoutExtension(fileName)}$nextExtension';
  }

  Future<String> _readTextFile(File file, {required int characterLimit}) async {
    final preview = await _readAttachmentPrefix(file, maxTextRawBytes);
    final decoded = _decodeTextBytes(preview.bytes);
    final buffer = StringBuffer(decoded.trim());
    if (preview.totalBytes > preview.bytes.length) {
      if (buffer.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln();
      }
      buffer.write(
        '[preview truncated: read ${aiFormatBytes(preview.bytes.length)} from ${aiFormatBytes(preview.totalBytes)}]',
      );
    }
    return _truncateText(buffer.toString().trim(), characterLimit);
  }

  String _decodeTextBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Future<String> _readPdfPreview(File file, int characterLimit) async {
    final preview = await _readAttachmentPrefix(file, maxPdfRawBytes);
    final latin = latin1.decode(preview.bytes, allowInvalid: true);
    final buffer = StringBuffer();
    var matchCount = 0;
    for (final match in _pdfTextSpanPattern.allMatches(latin)) {
      matchCount += 1;
      if (matchCount > _maxPdfTextSpanMatches) break;
      final text = _decodePdfString(match.group(1) ?? '');
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(text);
      if (buffer.length >= characterLimit) break;
    }
    if (buffer.isEmpty) {
      final fallback = latin
          .replaceAll(_pdfFallbackUnsupportedCharsPattern, ' ')
          .replaceAll(_pdfFallbackWhitespacePattern, ' ')
          .trim();
      if (fallback.isNotEmpty) {
        buffer.write(fallback);
      }
    }
    if (preview.totalBytes > preview.bytes.length) {
      buffer
        ..writeln()
        ..writeln()
        ..write(
          '[preview truncated: read ${aiFormatBytes(preview.bytes.length)} from ${aiFormatBytes(preview.totalBytes)}]',
        );
    }
    return _truncateText(buffer.toString().trim(), characterLimit);
  }

  Future<({Uint8List bytes, int totalBytes})> _readAttachmentPrefix(
    File file,
    int maxBytes,
  ) async {
    final deadline = MonotonicDeadline(
      defaultBoundedFileReadTotalTimeout,
      timeoutMessage: '附件读取超过总时限。',
    );
    try {
      final initialLength = await file.length().timeout(
        deadline.limit(defaultBoundedFileReadIdleTimeout),
      );
      final remaining = deadline.remaining();
      final bytes = await readBoundedFilePrefixBytes(
        file,
        maxBytes: maxBytes,
        totalTimeout: remaining,
      );
      final finalLength = await file.length().timeout(
        deadline.limit(defaultBoundedFileReadIdleTimeout),
      );
      if (finalLength != initialLength) {
        throw FileSystemException('附件读取期间发生变化。', file.path);
      }
      return (bytes: bytes, totalBytes: initialLength);
    } finally {
      deadline.stop();
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
      final bytes = await readBoundedFileBytes(
        file,
        maxBytes: _maxSpreadsheetArchiveBytes,
        idleTimeout: defaultBoundedFileReadIdleTimeout,
        totalTimeout: defaultBoundedFileReadTotalTimeout,
      );
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
    } on BoundedFileReadException catch (error) {
      if (error.failure == BoundedFileReadFailure.tooLarge) {
        return 'XLSX preview skipped because the archive exceeds ${aiFormatBytes(_maxSpreadsheetArchiveBytes)}.';
      }
      return 'Unable to read workbook structure from the XLSX file.';
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
      final index = optionalNonNegativeIntFromValue(rawValue);
      if (index == null || index >= sharedStrings.length) {
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
    final match = _spreadsheetColumnRefPattern.firstMatch(ref);
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
    final lines = splitTrimmedNonEmpty(
      promptText,
      separator: '\n',
    ).take(3).toList(growable: false);
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

/// 在后台 isolate 解码、缩放并压缩单帧栅格图片。
Map<String, Object?> _processRasterImageAttachment(Map<String, Object?> input) {
  final bytes = input['bytes']! as Uint8List;
  final extension = input['extension']! as String;
  final maxDimension = (input['max_dimension']! as int).clamp(1, 16384);
  final requestedOutputBytes = input['max_output_bytes'] as int?;
  final hardMaxOutputBytes = input['hard_max_output_bytes']! as int;
  final maxOutputBytes =
      requestedOutputBytes == null || requestedOutputBytes <= 0
      ? hardMaxOutputBytes
      : math.min(requestedOutputBytes, hardMaxOutputBytes);
  final maxPixels = input['max_pixels']! as int;
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) {
    return <String, Object?>{
      'bytes': bytes,
      'extension': extension,
      'width': null,
      'height': null,
    };
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > maxPixels) {
    throw const FormatException('图片尺寸无效或像素总量超过安全上限。');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null ||
      decoded.width <= 0 ||
      decoded.height <= 0 ||
      decoded.width * decoded.height > maxPixels) {
    throw const FormatException('图片解码失败或像素总量超过安全上限。');
  }
  final maxSide = math.max(decoded.width, decoded.height);
  final resized = maxSide <= maxDimension
      ? decoded
      : decoded.width >= decoded.height
      ? img.copyResize(decoded, width: maxDimension)
      : img.copyResize(decoded, height: maxDimension);
  var outputExtension = extension;
  var outputBytes = extension == '.png'
      ? Uint8List.fromList(img.encodePng(resized))
      : Uint8List.fromList(img.encodeJpg(resized, quality: 86));
  if (extension != '.png') outputExtension = '.jpg';
  if (outputBytes.length > maxOutputBytes) {
    final compressed = _compressRasterImageToLimit(
      source: resized,
      limitBytes: maxOutputBytes,
    );
    outputBytes = compressed.bytes;
    outputExtension = '.jpg';
    return <String, Object?>{
      'bytes': outputBytes,
      'extension': outputExtension,
      'width': compressed.width,
      'height': compressed.height,
    };
  }
  return <String, Object?>{
    'bytes': outputBytes,
    'extension': outputExtension,
    'width': resized.width,
    'height': resized.height,
  };
}

/// 逐步降低 JPEG 质量和尺寸，避免压缩过程无上限重试。
({Uint8List bytes, int width, int height}) _compressRasterImageToLimit({
  required img.Image source,
  required int limitBytes,
}) {
  img.Image current = source;
  Uint8List bytes = Uint8List.fromList(img.encodeJpg(current, quality: 92));
  if (bytes.length <= limitBytes) {
    return (bytes: bytes, width: current.width, height: current.height);
  }
  for (var quality = 84; quality >= 30; quality -= 8) {
    bytes = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    if (bytes.length <= limitBytes) {
      return (bytes: bytes, width: current.width, height: current.height);
    }
  }
  while (current.width > 256 && current.height > 256) {
    current = img.copyResize(current, width: (current.width * 0.75).round());
    for (var quality = 80; quality >= 30; quality -= 10) {
      bytes = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      if (bytes.length <= limitBytes) {
        return (bytes: bytes, width: current.width, height: current.height);
      }
    }
  }
  return (bytes: bytes, width: current.width, height: current.height);
}

class _ZipArchiveReader {
  _ZipArchiveReader(this.bytes, {required this.maxEntryBytes})
    : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final int maxEntryBytes;
  final ByteData _data;
  Map<String, _ZipEntry>? _entries;

  /// 所有条目的累计解压上限，防止大量小条目构造压缩炸弹。
  static const int _maxCumulativeDecompressedBytes = 32 * kBytesPerMiB;
  int _cumulativeDecompressedBytes = 0;

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
    // 校验累计解压大小，防止压缩炸弹。
    if (_cumulativeDecompressedBytes + entry.uncompressedSize >
        _maxCumulativeDecompressedBytes) {
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
      _cumulativeDecompressedBytes += payload.length;
      return Uint8List.fromList(payload);
    }
    if (entry.compressionMethod == 8) {
      try {
        final decoded = ZLibCodec(raw: true).decode(payload);
        if (decoded.length > maxEntryBytes) {
          return null;
        }
        _cumulativeDecompressedBytes += decoded.length;
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

String _requireSafeStorageIdentifier(String value, {required String label}) {
  return requireSafeStorageIdentifier(
    value,
    label: label,
    errorFactory: AiAttachmentException.new,
  );
}

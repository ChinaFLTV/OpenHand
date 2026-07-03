import 'package:path/path.dart' as p;

import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';

enum AiAttachmentKind {
  image('image'),
  text('text'),
  spreadsheet('spreadsheet'),
  pdf('pdf'),
  binary('binary');

  const AiAttachmentKind(this.storageValue);

  final String storageValue;

  static AiAttachmentKind fromStorage(String value) {
    return AiAttachmentKind.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => AiAttachmentKind.binary,
    );
  }
}

const String aiSessionMessageAttachmentsMetadataKey = 'attachments';
const int aiMessageAttachmentLimit = 20;

/// Maximum size in bytes for any single attachment a user adds via the
/// composer (paste / file picker). 10 MB matches the user-facing contract
/// "每个附件的尺寸不超过 10MB". The cap is enforced at pick time so
/// oversize files never reach the per-protocol encoding pipeline.
const int aiMessageAttachmentMaxFileBytes = 10 * kBytesPerMiB;

List<String> aiAttachmentPickerExtensions() {
  final extensions = <String>{
    ..._imageExtensions,
    ..._textExtensions,
    ..._spreadsheetExtensions,
    '.pdf',
  };
  return extensions
      .map((item) => item.startsWith('.') ? item.substring(1) : item)
      .toList(growable: false);
}

class AiMessageAttachment {
  factory AiMessageAttachment.fromJson(Object? raw) {
    final json = stringKeyedMapFromValueOrJsonText(raw);
    return AiMessageAttachment(
      id: stringFromValue(json['id']),
      name: stringFromValue(json['name']),
      storagePath: stringFromValue(json['storage_path']),
      kind: AiAttachmentKind.fromStorage(stringFromValue(json['kind'])),
      mimeType: stringFromValue(json['mime_type']),
      sizeBytes: _readInt(json['size_bytes']),
      promptText: json['prompt_text'] == null ? '' : '${json['prompt_text']}',
      summaryText: json['summary_text'] == null
          ? ''
          : '${json['summary_text']}',
      width: _readNullableInt(json['width']),
      height: _readNullableInt(json['height']),
      originalSourcePath: optionalStringFromValue(json['original_source_path']),
      pixelCount: _readNullableInt(json['pixel_count']),
      compressionRatio: optionalDoubleFromValue(json['compression_ratio']),
    );
  }
  const AiMessageAttachment({
    required this.id,
    required this.name,
    required this.storagePath,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.promptText = '',
    this.summaryText = '',
    this.width,
    this.height,
    this.originalSourcePath,
    this.pixelCount,
    this.compressionRatio,
  });

  final String id;
  final String name;
  final String storagePath;
  final AiAttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final String promptText;
  final String summaryText;
  final int? width;
  final int? height;

  /// Absolute path to the original (pre-compression / pre-edit) source file the
  /// user picked, when known. Useful for the `[图片附件；原始图片路径…]`
  /// history-message placeholder so the model can still reason about provenance
  /// after the resized copy has replaced the inline image part.
  final String? originalSourcePath;

  /// Total pixel count (`width * height`) of the stored image, when known.
  /// Independent of `width` / `height` so callers can populate it when the
  /// dimensions themselves are unavailable (e.g. SVG, partially decoded).
  final int? pixelCount;

  /// Ratio of stored size relative to the original source size, in `[0, 1]`.
  /// `null` for non-image attachments or when the original size is unknown.
  final double? compressionRatio;

  bool get isImage => kind == AiAttachmentKind.image;

  String get extension => p.extension(name).toLowerCase();

  AiMessageAttachment copyWith({
    String? id,
    String? name,
    String? storagePath,
    AiAttachmentKind? kind,
    String? mimeType,
    int? sizeBytes,
    String? promptText,
    String? summaryText,
    int? width,
    int? height,
    String? originalSourcePath,
    int? pixelCount,
    double? compressionRatio,
  }) {
    return AiMessageAttachment(
      id: id ?? this.id,
      name: name ?? this.name,
      storagePath: storagePath ?? this.storagePath,
      kind: kind ?? this.kind,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      promptText: promptText ?? this.promptText,
      summaryText: summaryText ?? this.summaryText,
      width: width ?? this.width,
      height: height ?? this.height,
      originalSourcePath: originalSourcePath ?? this.originalSourcePath,
      pixelCount: pixelCount ?? this.pixelCount,
      compressionRatio: compressionRatio ?? this.compressionRatio,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'storage_path': storagePath,
      'kind': kind.storageValue,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'prompt_text': promptText,
      'summary_text': summaryText,
      'width': width,
      'height': height,
      'original_source_path': originalSourcePath,
      'pixel_count': pixelCount,
      'compression_ratio': compressionRatio,
    };
  }

  static List<AiMessageAttachment> listFromMetadata(Object? rawValue) {
    return stringKeyedMapListFromValueOrJsonText(rawValue)
        .map(AiMessageAttachment.fromJson)
        .where((item) => item.id.isNotEmpty && item.storagePath.isNotEmpty)
        .toList(growable: false);
  }

  static List<Map<String, Object?>> listToMetadata(
    List<AiMessageAttachment> attachments,
  ) {
    return attachments.map((item) => item.toJson()).toList(growable: false);
  }

  static int _readInt(Object? value) {
    final parsed = _readNullableInt(value);
    return parsed ?? 0;
  }

  static int? _readNullableInt(Object? value) {
    return optionalNonNegativeIntFromValue(value);
  }
}

AiAttachmentKind aiAttachmentKindForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  if (_imageExtensions.contains(extension)) {
    return AiAttachmentKind.image;
  }
  if (_textExtensions.contains(extension)) {
    return AiAttachmentKind.text;
  }
  if (_spreadsheetExtensions.contains(extension)) {
    return AiAttachmentKind.spreadsheet;
  }
  if (extension == '.pdf') {
    return AiAttachmentKind.pdf;
  }
  return AiAttachmentKind.binary;
}

String aiMimeTypeForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return switch (extension) {
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.bmp' => 'image/bmp',
    '.svg' => 'image/svg+xml',
    '.md' || '.markdown' => 'text/markdown',
    '.txt' => 'text/plain',
    '.json' => 'application/json',
    '.yaml' || '.yml' => 'application/yaml',
    '.toml' => 'application/toml',
    '.xml' => 'application/xml',
    '.csv' => 'text/csv',
    '.tsv' => 'text/tab-separated-values',
    '.log' => 'text/plain',
    '.sql' => 'text/plain',
    '.dart' => 'text/plain',
    '.go' => 'text/plain',
    '.js' => 'text/plain',
    '.ts' => 'text/plain',
    '.tsx' => 'text/plain',
    '.jsx' => 'text/plain',
    '.py' => 'text/plain',
    '.sh' => 'text/plain',
    '.zsh' => 'text/plain',
    '.bash' => 'text/plain',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.xls' => 'application/vnd.ms-excel',
    '.pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

String aiFormatBytes(int sizeBytes) => formatByteSize(sizeBytes);

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.svg',
};

const Set<String> _textExtensions = <String>{
  '.txt',
  '.md',
  '.markdown',
  '.json',
  '.yaml',
  '.yml',
  '.toml',
  '.xml',
  '.html',
  '.htm',
  '.css',
  '.scss',
  '.sass',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.dart',
  '.go',
  '.py',
  '.java',
  '.kt',
  '.kts',
  '.rb',
  '.rs',
  '.c',
  '.cc',
  '.cpp',
  '.h',
  '.hpp',
  '.sh',
  '.zsh',
  '.bash',
  '.fish',
  '.sql',
  '.csv',
  '.tsv',
  '.env',
  '.ini',
  '.cfg',
  '.conf',
  '.log',
  '.vue',
};

const Set<String> _spreadsheetExtensions = <String>{'.xlsx', '.xls'};

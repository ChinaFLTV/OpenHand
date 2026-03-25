import 'package:path/path.dart' as p;

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

  bool get isImage => kind == AiAttachmentKind.image;

  String get extension => p.extension(name).toLowerCase();

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
    };
  }

  factory AiMessageAttachment.fromJson(Map<String, Object?> json) {
    return AiMessageAttachment(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      storagePath: '${json['storage_path'] ?? ''}'.trim(),
      kind: AiAttachmentKind.fromStorage('${json['kind'] ?? ''}'),
      mimeType: '${json['mime_type'] ?? ''}'.trim(),
      sizeBytes: _readInt(json['size_bytes']),
      promptText: '${json['prompt_text'] ?? ''}',
      summaryText: '${json['summary_text'] ?? ''}',
      width: _readNullableInt(json['width']),
      height: _readNullableInt(json['height']),
    );
  }

  static List<AiMessageAttachment> listFromMetadata(Object? rawValue) {
    if (rawValue is! List) {
      return const <AiMessageAttachment>[];
    }
    return rawValue
        .map((item) {
          if (item is Map<String, Object?>) {
            return AiMessageAttachment.fromJson(item);
          }
          if (item is Map) {
            return AiMessageAttachment.fromJson(
              Map<String, Object?>.from(item),
            );
          }
          return null;
        })
        .whereType<AiMessageAttachment>()
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
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return int.tryParse(text);
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

String aiFormatBytes(int sizeBytes) {
  if (sizeBytes < 1024) {
    return '$sizeBytes B';
  }
  if (sizeBytes < 1024 * 1024) {
    return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
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
  '.svg',
  '.vue',
};

const Set<String> _spreadsheetExtensions = <String>{'.xlsx', '.xls'};

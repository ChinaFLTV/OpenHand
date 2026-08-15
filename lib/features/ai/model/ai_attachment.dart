import 'package:path/path.dart' as p;

import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/text_clip.dart';

enum AiAttachmentKind {
  image('image'),
  video('video'),
  audio('audio'),
  text('text'),
  spreadsheet('spreadsheet'),
  pdf('pdf'),
  binary('binary');

  const AiAttachmentKind(this.storageValue);

  final String storageValue;

  static AiAttachmentKind fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (kind) => kind.storageValue,
      fallback: AiAttachmentKind.binary,
    );
  }
}

const String aiSessionMessageAttachmentsMetadataKey = 'attachments';
const int aiMessageAttachmentLimit = 20;
const int aiMessageAttachmentMaxIdCharacters = 256;
const int aiMessageAttachmentMaxNameCharacters = 512;
const int aiMessageAttachmentMaxPathCharacters = 4096;
const int aiMessageAttachmentMaxMimeTypeCharacters = 256;
const int aiMessageAttachmentMaxPromptCharacters = 8000;
const int aiMessageAttachmentsMaxPromptCharactersPerMessage = 32000;
const int aiMessageAttachmentMaxSummaryCharacters = 2000;
const int _aiMessageAttachmentMetadataScanLimit = aiMessageAttachmentLimit * 5;

/// 单个消息附件的最大字节数。文件选择阶段即执行限制，避免超限文件进入协议编码链路。
const int aiMessageAttachmentMaxFileBytes = 10 * kBytesPerMiB;

List<String> aiAttachmentPickerExtensions() {
  final extensions = <String>{
    ..._imageExtensions,
    ..._videoExtensions,
    ..._audioExtensions,
    ...ReaderFileType.textLikeExtensions,
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
      compressionRatio: optionalUnitIntervalFromValue(
        json['compression_ratio'],
      ),
    );
  }
  AiMessageAttachment({
    required String id,
    required String name,
    required String storagePath,
    required this.kind,
    required String mimeType,
    required int sizeBytes,
    String promptText = '',
    String summaryText = '',
    int? width,
    int? height,
    String? originalSourcePath,
    int? pixelCount,
    double? compressionRatio,
  }) : id = _clip(id, aiMessageAttachmentMaxIdCharacters),
       name = _clip(name, aiMessageAttachmentMaxNameCharacters),
       storagePath = _clip(storagePath, aiMessageAttachmentMaxPathCharacters),
       mimeType = _clip(mimeType, aiMessageAttachmentMaxMimeTypeCharacters),
       sizeBytes = sizeBytes < 0 ? 0 : sizeBytes,
       promptText = _clip(promptText, aiMessageAttachmentMaxPromptCharacters),
       summaryText = _clip(
         summaryText,
         aiMessageAttachmentMaxSummaryCharacters,
       ),
       width = width != null && width >= 0 ? width : null,
       height = height != null && height >= 0 ? height : null,
       originalSourcePath = nullIfBlank(originalSourcePath) == null
           ? null
           : _clip(originalSourcePath!, aiMessageAttachmentMaxPathCharacters),
       pixelCount = pixelCount != null && pixelCount >= 0 ? pixelCount : null,
       compressionRatio = optionalUnitIntervalFromValue(compressionRatio);

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

  /// 用户所选原始文件的绝对路径，用于压缩或编辑后保留来源信息。
  final String? originalSourcePath;

  /// 已存图片的像素总数；尺寸未知时也可单独提供。
  final int? pixelCount;

  /// 存储大小与原始大小之比，范围为 `[0, 1]`。
  final double? compressionRatio;

  bool get isImage => kind == AiAttachmentKind.image;

  bool get isVideo => kind == AiAttachmentKind.video;

  bool get isAudio => kind == AiAttachmentKind.audio;

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
    return _boundedAttachments(
      stringKeyedMapListFromValueOrJsonText(
            rawValue,
            limit: _aiMessageAttachmentMetadataScanLimit,
          )
          .map(AiMessageAttachment.fromJson)
          .where((item) => item.id.isNotEmpty && item.storagePath.isNotEmpty),
    );
  }

  static List<Map<String, Object?>> listToMetadata(
    List<AiMessageAttachment> attachments,
  ) {
    return _boundedAttachments(
      attachments,
    ).map((item) => item.toJson()).toList(growable: false);
  }

  static List<AiMessageAttachment> _boundedAttachments(
    Iterable<AiMessageAttachment> attachments,
  ) {
    final items = <AiMessageAttachment>[];
    var remainingPromptCharacters =
        aiMessageAttachmentsMaxPromptCharactersPerMessage;
    for (final attachment in attachments) {
      if (attachment.id.isEmpty || attachment.storagePath.isEmpty) continue;
      final bounded = attachment.promptText.length <= remainingPromptCharacters
          ? attachment
          : attachment.copyWith(
              promptText: _clip(
                attachment.promptText,
                remainingPromptCharacters,
              ),
            );
      items.add(bounded);
      remainingPromptCharacters -= bounded.promptText.length;
      if (items.length >= aiMessageAttachmentLimit) break;
    }
    return items.toList(growable: false);
  }

  static int _readInt(Object? value) {
    final parsed = _readNullableInt(value);
    return parsed ?? 0;
  }

  static int? _readNullableInt(Object? value) {
    return optionalNonNegativeIntFromValue(value);
  }

  static String _clip(String value, int maxCharacters) {
    return clipTextByCodeUnits(value.trim(), maxCharacters, suffix: '…');
  }
}

AiAttachmentKind aiAttachmentKindForPath(String path) {
  final extension = p.extension(path).toLowerCase();
  if (_imageExtensions.contains(extension)) {
    return AiAttachmentKind.image;
  }
  if (_videoExtensions.contains(extension)) {
    return AiAttachmentKind.video;
  }
  if (_audioExtensions.contains(extension)) {
    return AiAttachmentKind.audio;
  }
  if (ReaderFileType.isTextLikeExtension(extension)) {
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
    '.png' => kImagePngMimeType,
    '.jpg' || '.jpeg' => kImageJpegMimeType,
    '.gif' => kImageGifMimeType,
    '.webp' => kImageWebpMimeType,
    '.bmp' => 'image/bmp',
    '.svg' => kImageSvgXmlMimeType,
    '.mp4' => kVideoMp4MimeType,
    '.avi' => 'video/x-msvideo',
    '.mov' => 'video/mov',
    '.mkv' => 'video/x-matroska',
    '.wmv' => 'video/x-ms-wmv',
    '.mp3' => kAudioMpegMimeType,
    '.wav' => 'audio/wav',
    '.flac' => 'audio/flac',
    '.m4a' => 'audio/mp4',
    '.ogg' => 'audio/ogg',
    '.md' || '.markdown' => 'text/markdown',
    '.txt' => kTextPlainMimeType,
    '.json' => kApplicationJsonMimeType,
    '.yaml' || '.yml' => 'application/yaml',
    '.toml' => 'application/toml',
    '.xml' => 'application/xml',
    '.csv' => 'text/csv',
    '.tsv' => 'text/tab-separated-values',
    '.log' => kTextPlainMimeType,
    '.sql' => kTextPlainMimeType,
    '.dart' => kTextPlainMimeType,
    '.go' => kTextPlainMimeType,
    '.js' => kTextPlainMimeType,
    '.ts' => kTextPlainMimeType,
    '.tsx' => kTextPlainMimeType,
    '.jsx' => kTextPlainMimeType,
    '.py' => kTextPlainMimeType,
    '.sh' => kTextPlainMimeType,
    '.zsh' => kTextPlainMimeType,
    '.bash' => kTextPlainMimeType,
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.xls' => 'application/vnd.ms-excel',
    '.pdf' => 'application/pdf',
    _ => kApplicationOctetStreamMimeType,
  };
}

const Set<String> _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.svg',
};

const Set<String> _videoExtensions = <String>{
  '.mp4',
  '.avi',
  '.mov',
  '.mkv',
  '.wmv',
};

const Set<String> _audioExtensions = <String>{
  '.mp3',
  '.wav',
  '.flac',
  '.m4a',
  '.ogg',
};

const Set<String> _spreadsheetExtensions = <String>{'.xlsx', '.xls'};

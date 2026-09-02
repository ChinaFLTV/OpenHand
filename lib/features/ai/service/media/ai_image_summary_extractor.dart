import '../../../../shared/util/text_normalization.dart';

/// 提取助手回复中的 `<image_summary>` 指令，并从用户可见文本中移除该指令。
class AiImageSummaryExtractionResult {
  const AiImageSummaryExtractionResult({
    required this.summariesByAttachmentId,
    required this.strippedContent,
  });

  /// 附件 ID 到已去除首尾空白的摘要映射。
  final Map<String, String> summariesByAttachmentId;

  /// 已移除所有 `<image_summary>` 块的助手回复。
  final String strippedContent;
}

class AiImageSummaryExtractor {
  AiImageSummaryExtractor._();

  static final RegExp _pattern = RegExp(
    r'''<image_summary\b[^>]*\battachment_id\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)</image_summary\s*>''',
    caseSensitive: false,
  );

  /// 提取图片摘要并返回清洗后的可见正文；未闭合标签同样不会进入正文。
  static AiImageSummaryExtractionResult extractAndStrip(String content) {
    if (content.isEmpty) {
      return const AiImageSummaryExtractionResult(
        summariesByAttachmentId: <String, String>{},
        strippedContent: '',
      );
    }
    final summaries = <String, String>{};
    for (final match in _pattern.allMatches(content)) {
      final id = (match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
          .trim();
      final summary = (match.group(4) ?? '').trim();
      if (id.isEmpty || summary.isEmpty) {
        continue;
      }
      // 同一 ID 重复出现时保留最后一条摘要。
      summaries[id] = summary;
    }
    final stripped = stripImageSummaryMarkup(content);
    return AiImageSummaryExtractionResult(
      summariesByAttachmentId: summaries,
      strippedContent: stripped.trim(),
    );
  }
}

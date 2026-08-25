import '../../../../shared/util/text_normalization.dart';

/// Parses `<image_summary attachment_id="…">…</image_summary>` directives the
/// assistant is instructed to emit alongside its visible reply, exposes the
/// extracted summaries keyed by attachment id, and returns the reply with the
/// directives stripped so the user-visible transcript stays clean.
class AiImageSummaryExtractionResult {
  const AiImageSummaryExtractionResult({
    required this.summariesByAttachmentId,
    required this.strippedContent,
  });

  /// Map of attachment id → trimmed summary text.
  final Map<String, String> summariesByAttachmentId;

  /// The original assistant reply with all `<image_summary …>` blocks
  /// removed.
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
      // Last writer wins if the same id appears multiple times.
      summaries[id] = summary;
    }
    final stripped = stripImageSummaryMarkup(content);
    return AiImageSummaryExtractionResult(
      summariesByAttachmentId: summaries,
      strippedContent: stripped.trim(),
    );
  }
}

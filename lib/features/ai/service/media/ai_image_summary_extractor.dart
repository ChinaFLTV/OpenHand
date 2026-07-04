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
    r'<image_summary\s+attachment_id\s*=\s*"([^"]+)"\s*>([\s\S]*?)</image_summary>',
    multiLine: true,
  );
  static final RegExp _collapsedBlankLinesPattern = RegExp(r'\n{3,}');

  /// Extracts every `<image_summary>` directive from [content] and returns
  /// both the lookup map and a stripped copy of the content. When no
  /// directive is present the original content is returned unchanged and
  /// the map is empty.
  static AiImageSummaryExtractionResult extractAndStrip(String content) {
    if (content.isEmpty) {
      return const AiImageSummaryExtractionResult(
        summariesByAttachmentId: <String, String>{},
        strippedContent: '',
      );
    }
    final summaries = <String, String>{};
    for (final match in _pattern.allMatches(content)) {
      final id = (match.group(1) ?? '').trim();
      final summary = (match.group(2) ?? '').trim();
      if (id.isEmpty || summary.isEmpty) {
        continue;
      }
      // Last writer wins if the same id appears multiple times.
      summaries[id] = summary;
    }
    if (summaries.isEmpty) {
      return AiImageSummaryExtractionResult(
        summariesByAttachmentId: const <String, String>{},
        strippedContent: content,
      );
    }
    final stripped = content
        .replaceAll(_pattern, '')
        .replaceAll(_collapsedBlankLinesPattern, '\n\n');
    return AiImageSummaryExtractionResult(
      summariesByAttachmentId: summaries,
      strippedContent: stripped.trim(),
    );
  }
}

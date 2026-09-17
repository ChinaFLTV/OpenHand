class AiImageSummaryExtractor {
  AiImageSummaryExtractor._();

  static final RegExp _pattern = RegExp(
    r'''<image_summary\b[^>]*\battachment_id\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)</image_summary\s*>''',
    caseSensitive: false,
  );

  /// 提取完整图片摘要，按附件 ID 归集；正文清理由可见内容管线统一处理。
  static Map<String, String> extract(String content) {
    if (content.isEmpty) return const <String, String>{};
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
    return summaries;
  }
}

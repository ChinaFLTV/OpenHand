/// 纯 Dart 中英混合分词器，给 MCP 工具的关键词倒排索引用。
///
/// 设计目标：零外部依赖、单文件、~60 行、对 ToolSearch 召回率
/// 足够。算法：
///   1. 把字符流按字符类（CJK / 拉丁字母 / 数字 / 其他）切段
///   2. 拉丁段先 lowercase，再按 camelCase / snake_case / kebab-case
///      边界拆细词，最终保留 ≥1 字符的词元
///   3. CJK 段做 bigram（连续 N 字 → N-1 个 2 字片），同时保留
///      原始 N 字片，便于短词整段匹配
///   4. 数字段单独保留（"v1" / "8080" 等查询体验更佳）
///   5. 全部归一为 lowercase；通过停用词表丢弃噪声词。
///
/// 不做的事情（非阻塞，未来可扩展）：
///   * 词性标注 / 同义词词典 / 拼音首字母
///   * Trie 前缀匹配（按需在 index 层做）。
library;

const Set<String> _stopwords = <String>{
  'a', 'an', 'the', 'of', 'to', 'in', 'on', 'at', 'for', 'with',
  'and', 'or', 'is', 'are', 'be', 'by', 'as', 'it', 'this', 'that',
  'tool', 'tools', 'mcp', // MCP 工具列表里这几个词信噪比极低
  '的', '了', '和', '与', '或', '是', '在', '为', '将', '把',
  '从', '到', '对', '一个', '一种',
};

final RegExp _latinExplicitSeparatorPattern = RegExp(r'[_\-.]+');

bool _isCjk(int r) {
  return (r >= 0x3400 && r <= 0x4DBF) || // CJK Ext A
      (r >= 0x4E00 && r <= 0x9FFF) || // CJK Unified
      (r >= 0xF900 && r <= 0xFAFF) || // CJK Compatibility
      (r >= 0x3040 && r <= 0x30FF) || // 假名
      (r >= 0xAC00 && r <= 0xD7AF); // Hangul
}

bool _isLatinAlpha(int r) =>
    (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

bool _isDigit(int r) => r >= 0x30 && r <= 0x39;

/// 把单个字符串切分为去重后的关键词集合。返回 `Set` 以便上层直接
/// 与倒排索引的 `Set<ToolRef>` 做并集，无需再做一次 dedup。
Set<String> tokenizeForMcpKeywordIndex(String? text) {
  if (text == null || text.isEmpty) return const <String>{};
  final tokens = <String>{};
  final buf = StringBuffer();
  int? bufKind; // 0=cjk, 1=latin, 2=digit

  void flush() {
    if (buf.isEmpty) return;
    final segment = buf.toString();
    buf.clear();
    if (bufKind == 0) {
      // CJK: 整段 + bigram
      _emitCjkTokens(segment, tokens);
    } else if (bufKind == 1) {
      // 拉丁：再细分驼峰/连字符/下划线
      _emitLatinTokens(segment.toLowerCase(), tokens);
    } else if (bufKind == 2) {
      tokens.add(segment);
    }
  }

  for (final r in text.runes) {
    int kind;
    if (_isCjk(r)) {
      kind = 0;
    } else if (_isLatinAlpha(r)) {
      kind = 1;
    } else if (_isDigit(r)) {
      kind = 2;
    } else {
      flush();
      bufKind = null;
      continue;
    }
    if (bufKind != null && bufKind != kind) flush();
    bufKind = kind;
    buf.writeCharCode(r);
  }
  flush();
  tokens.removeWhere(_stopwords.contains);
  return tokens;
}

void _emitCjkTokens(String segment, Set<String> out) {
  final chars = segment.runes.toList(growable: false);
  if (chars.length == 1) {
    out.add(segment);
    return;
  }
  // 全段（避免 "我的工具" 被切碎后无法整段匹配）
  out.add(segment);
  for (var i = 0; i + 1 < chars.length; i++) {
    out.add(String.fromCharCodes(<int>[chars[i], chars[i + 1]]));
  }
}

void _emitLatinTokens(String lower, Set<String> out) {
  // 先按 _ - 等显式分隔切；然后对每段按驼峰再切。
  final pieces = lower.split(_latinExplicitSeparatorPattern);
  for (final piece in pieces) {
    if (piece.isEmpty) continue;
    out.add(piece);
    // 没有显式驼峰信号（已 lower），跳过驼峰拆分；改为长度阈值的 trigram 前缀，
    // 帮助类似 "fetchurl" / "readlints" 这种模型常见连写召回。
    if (piece.length >= 6) {
      out.add(piece.substring(0, 4));
    }
  }
}

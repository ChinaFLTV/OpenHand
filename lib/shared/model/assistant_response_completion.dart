const String assistantResponseContinuationMetadataKey =
    'assistant_response_continuation';

final RegExp _unfinishedEndingPattern = RegExp(r'[:：(\[{（【｛]\s*$');
final RegExp _backtickFencePattern = RegExp(r'^\s*```', multiLine: true);
final RegExp _tildeFencePattern = RegExp(r'^\s*~~~', multiLine: true);
final RegExp _pendingChineseActionPattern = RegExp(
  r'(?:^|[。！？!?\n])\s*'
  r'(?:(?:我|让我|这就|现在|马上|立即|接下来|下面|然后|重新|继续|再|正在)[^。！？!?\n]{0,32})?'
  '(?:重试|再试|尝试|调用|执行|查询|搜索|获取|读取|检查|验证|处理|生成|继续)'
  r'(?:一下|一次|中)?\s*(?:[。！!]|…+|\.{3})?$',
);
final RegExp _pendingEnglishActionPattern = RegExp(
  r'(?:^|[.!?\n])\s*'
  '(?:'
  r'(?:let me|i(?:\x27ll| will)|now|next)\s+[^.!?\n]{0,64}'
  '(?:retry|try|call|run|query|search|fetch|read|check|verify|continue|generate)'
  r'(?:\s+(?:again|now|once))?'
  '|(?:retrying|continuing|trying|calling|running|querying|searching|fetching|reading|checking|verifying|generating)'
  r'(?:\s+(?:again|now|once))?'
  r')\s*(?:[.!]|…+|\.{3})?$',
  caseSensitive: false,
);

/// 判断模型是否只声明了下一步动作，却没有给出工具调用或最终结论。
bool assistantResponseNeedsContinuation(String value) {
  final text = value.trimRight();
  if (text.isEmpty) return false;
  if (_unfinishedEndingPattern.hasMatch(text)) return true;

  final backtickFences = _backtickFencePattern.allMatches(text).length;
  final tildeFences = _tildeFencePattern.allMatches(text).length;
  if (backtickFences.isOdd || tildeFences.isOdd) return true;

  final tail = text.length <= 120 ? text : text.substring(text.length - 120);
  return _pendingChineseActionPattern.hasMatch(tail) ||
      _pendingEnglishActionPattern.hasMatch(tail);
}

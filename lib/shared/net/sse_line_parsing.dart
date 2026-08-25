/// SSE (Server-Sent Events) 行级字段解析。
///
/// AI 流式对话、MCP Streamable HTTP、扫描引擎实时事件等多处均消费 SSE，
/// 统一处理 SSE 的 `data:` 前缀和行结束符。
library;

const String _kSseDataFieldPrefix = 'data:';
const String _kSseEventFieldPrefix = 'event:';

/// 提取 SSE `data:` 字段载荷（去前缀并 trim）；非 data 行返回 null。
String? sseDataPayload(String line) {
  if (!line.startsWith(_kSseDataFieldPrefix)) return null;
  return line.substring(_kSseDataFieldPrefix.length).trim();
}

/// 提取 SSE `event:` 字段值（去前缀并 trim）；非 event 行返回 null。
String? sseEventName(String line) {
  if (!line.startsWith(_kSseEventFieldPrefix)) return null;
  return line.substring(_kSseEventFieldPrefix.length).trim();
}

/// 从完整 SSE 事件块文本中提取全部 `data:` 载荷行。
List<String> extractSseDataLines(String block) {
  final trimmedBlock = block.trim();
  if (trimmedBlock.isEmpty) return const <String>[];
  return trimmedBlock
      .split('\n')
      .map(sseDataPayload)
      .whereType<String>()
      .toList(growable: false);
}

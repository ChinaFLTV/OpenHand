import '../../ai/service/mcp_loaded_tools_tracker.dart';

/// 把 [AiToolSearchLoadHistoryEntry] 序列化为 CSV / Markdown 的纯函数集合。
///
/// 所有函数均为纯函数：不读 BuildContext、不写剪贴板、不依赖 setState；
/// 把「序列化」与「投递（剪贴板/文件）」职责分开，方便单测并在多入口复用。
///
/// CSV 协议：
///   - 第一行固定 header `timestamp,source,query,added_count,total_deferred,added_names`
///   - `added_names` 列内用 `;` 拼接
///   - 单元格在出现 `,` `"` `\r` `\n` 任一字符时整体加双引号，并把 `"` → `""`
///
/// Markdown 协议：
///   - 5 列表头 + 分隔行 `| --- | --- | --- | --- | --- |`
///   - timestamp 用反引号包裹便于阅读
///   - `+Added / Deferred` 列固定形如 `+3 / 7`
///   - 单元格内 `|` 转义为 `\|`、`\n` 折成空格，以避免破坏表格
class ToolSearchHistorySerializer {
  const ToolSearchHistorySerializer._();

  static String toCsv(List<AiToolSearchLoadHistoryEntry> entries) {
    final buf = StringBuffer()
      ..writeln(
        'timestamp,source,query,added_count,total_deferred,added_names',
      );
    for (final e in entries) {
      buf
        ..write(_csvEscape(e.timestamp.toIso8601String()))
        ..write(',')
        ..write(_csvEscape(e.source.name))
        ..write(',')
        ..write(_csvEscape(e.query))
        ..write(',')
        ..write(e.addedCount)
        ..write(',')
        ..write(e.totalDeferred)
        ..write(',')
        ..writeln(_csvEscape(e.addedNames.join(';')));
    }
    return buf.toString();
  }

  static String toMarkdown(List<AiToolSearchLoadHistoryEntry> entries) {
    final buf = StringBuffer()
      ..writeln('| Timestamp | Source | Query | +Added / Deferred | Names |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final e in entries) {
      buf
        ..write('| `')
        ..write(e.timestamp.toIso8601String())
        ..write('` | ')
        ..write(e.source.name)
        ..write(' | ')
        ..write(_mdEscape(e.query))
        ..write(' | ')
        ..write('+${e.addedCount} / ${e.totalDeferred}')
        ..write(' | ')
        ..writeln('${_mdEscape(e.addedNames.join(', '))} |');
    }
    return buf.toString();
  }

  static String _csvEscape(String raw) {
    if (raw.isEmpty) return '';
    final needsQuote = raw.contains(',') ||
        raw.contains('"') ||
        raw.contains('\n') ||
        raw.contains('\r');
    if (!needsQuote) return raw;
    return '"${raw.replaceAll('"', '""')}"';
  }

  static String _mdEscape(String raw) =>
      raw.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

import 'dart:convert';

import '../../../shared/util/csv_encoding.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';

/// 把 [AiToolSearchLoadHistoryEntry] 序列化为 CSV / Markdown 的纯函数集合。
///
/// 所有函数均为纯函数：不读 BuildContext、不写剪贴板、不依赖 setState；
/// 把「序列化」与「投递（剪贴板/文件）」职责分开，供多个入口复用。
///
/// CSV 协议：
///   - 第一行固定 header `timestamp,source,query,added_count,total_deferred,added_names`
///   - `added_names` 列内用 `;` 拼接
///   - 单元格在出现 `,` `"` `\r` `\n` 任一字符时整体加双引号，并把 `"` → `""`
///   - 可能被表格软件解释为公式的字符串统一转为纯文本
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
      buf.writeln(
        encodeCsvRow(<Object?>[
          e.timestamp.toIso8601String(),
          e.source.name,
          e.query,
          e.addedCount,
          e.totalDeferred,
          e.addedNames.join(';'),
        ]),
      );
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

  static String _mdEscape(String raw) =>
      raw.replaceAll('|', r'\|').replaceAll('\n', ' ');

  /// 把历史序列化为 indent-2 的 JSON 字符串：根对象包含 `version`/`exportedAt`
  /// 元数据 + `entries` 数组。便于后续调试 / 回放 / diff 工具二次解析。
  ///
  /// 单条 entry 字段保持稳定 key（snake_case 与 CSV header 对齐）：
  /// `timestamp` (ISO8601), `source` (`ai`/`harness` 等), `query`,
  /// `added_count`, `total_deferred`, `added_names` (`List&lt;String&gt;`).
  static String toJson(List<AiToolSearchLoadHistoryEntry> entries) {
    final root = <String, Object?>{
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'entries': [
        for (final e in entries)
          <String, Object?>{
            'timestamp': e.timestamp.toIso8601String(),
            'source': e.source.name,
            'query': e.query,
            'added_count': e.addedCount,
            'total_deferred': e.totalDeferred,
            'added_names': e.addedNames,
          },
      ],
    };
    return prettyPrintJson(root);
  }

  /// 反向解析由 [toJson] 生成的字符串。仅识别 `version: 1` 协议；其它版本
  /// 抛 [FormatException]。容忍：
  ///   - `entries` 中条目缺少 `query`/`added_names` 时分别回落 `''` / `<>`；
  ///   - `source` 字符串非已知 enum 时回落 [AiToolSearchLoadSource.aiSession]；
  ///   - `timestamp` 非法 ISO8601 抛 [FormatException]。
  ///
  /// 返回的 entries 顺序与 JSON 中 `entries` 数组顺序一致（与 [toJson] 对称）。
  static List<AiToolSearchLoadHistoryEntry> fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException(
        'ToolSearchHistorySerializer.fromJson: ${e.message}',
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'ToolSearchHistorySerializer.fromJson: root must be a JSON object',
      );
    }
    final root = stringKeyedMapFromValue(decoded);
    final version = intFromValue(root['version'], fallback: -1);
    if (version != 1) {
      throw FormatException(
        'ToolSearchHistorySerializer.fromJson: unsupported version $version',
      );
    }
    final raw = root['entries'];
    if (raw is! List) {
      throw const FormatException(
        'ToolSearchHistorySerializer.fromJson: "entries" must be a JSON array',
      );
    }
    final result = <AiToolSearchLoadHistoryEntry>[];
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) {
        throw FormatException(
          'ToolSearchHistorySerializer.fromJson: entries[$i] must be a JSON object',
        );
      }
      final rowMap = stringKeyedMapFromValue(row);
      final tsRaw = rowMap['timestamp'];
      if (tsRaw is! String) {
        throw FormatException(
          'ToolSearchHistorySerializer.fromJson: entries[$i].timestamp missing or not a string',
        );
      }
      final timestamp = DateTime.parse(tsRaw);
      final sourceName = rowMap['source'];
      final src = enumByNameOr(
        AiToolSearchLoadSource.values,
        sourceName,
        fallback: AiToolSearchLoadSource.aiSession,
      );
      final query = (rowMap['query'] is String)
          ? rowMap['query'] as String
          : '';
      final addedNames = stringListFromValue(rowMap['added_names']);
      final totalDeferred = nonNegativeIntFromValue(
        rowMap['total_deferred'],
        fallback: 0,
      );
      result.add(
        AiToolSearchLoadHistoryEntry(
          timestamp: timestamp,
          query: query,
          addedNames: addedNames,
          totalDeferred: totalDeferred,
          source: src,
        ),
      );
    }
    return result;
  }
}

import '../../../shared/util/bounded_json_conversion.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/csv_encoding.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
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

  static const int maxImportBytes = 8 * kBytesPerMiB;
  static const int _maxImportedJsonNodes =
      2 +
      McpLoadedToolsTracker.defaultMaxHistoryPerSession *
          (7 + McpLoadedToolsTracker.defaultMaxNamesPerSession);
  static const BoundedJsonConversionConfig _importJsonConfig =
      BoundedJsonConversionConfig(
        maxDepth: 4,
        maxContainerItems: McpLoadedToolsTracker.defaultMaxNamesPerSession,
        maxTotalNodes: _maxImportedJsonNodes,
      );

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
    if (utf8ByteLength(source) > maxImportBytes) {
      throw const FormatException('工具搜索历史文件超过安全上限。');
    }
    final Map<String, Object?> root;
    try {
      root = decodeJsonObjectTextUsingConfig(
        source,
        maxTextCodeUnits: maxImportBytes,
        config: _importJsonConfig,
        invalidRootMessage: '工具搜索历史的根节点必须是 JSON 对象。',
      );
    } on FormatException catch (e) {
      throw FormatException('工具搜索历史格式无效：${e.message}');
    }
    final version = intFromValue(root['version'], fallback: -1);
    if (version != 1) {
      throw FormatException('不支持工具搜索历史版本 $version。');
    }
    final raw = root['entries'];
    if (raw is! List) {
      throw const FormatException('工具搜索历史 entries 必须是 JSON 数组。');
    }
    if (raw.length > McpLoadedToolsTracker.defaultMaxHistoryPerSession) {
      throw const FormatException('工具搜索历史条目数量超过安全上限。');
    }
    final result = <AiToolSearchLoadHistoryEntry>[];
    for (var i = 0; i < raw.length; i++) {
      final row = raw[i];
      if (row is! Map) {
        throw FormatException('工具搜索历史 entries[$i] 必须是 JSON 对象。');
      }
      final rowMap = stringKeyedMapFromValue(row);
      final tsRaw = rowMap['timestamp'];
      if (tsRaw is! String || tsRaw.length > 64) {
        throw FormatException('工具搜索历史 entries[$i].timestamp 无效。');
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
      if (query.length > McpLoadedToolsTracker.defaultMaxQueryCharacters) {
        throw FormatException('工具搜索历史 entries[$i].query 超过安全上限。');
      }
      final rawAddedNames = rowMap['added_names'];
      if (rawAddedNames != null && rawAddedNames is! List) {
        throw FormatException('工具搜索历史 entries[$i].added_names 必须是数组。');
      }
      final addedNameValues = rawAddedNames as List? ?? const <Object?>[];
      if (addedNameValues.length >
          McpLoadedToolsTracker.defaultMaxNamesPerSession) {
        throw FormatException('工具搜索历史 entries[$i].added_names 数量过多。');
      }
      final addedNames = <String>[];
      for (final value in addedNameValues) {
        if (value is! String) {
          throw FormatException('工具搜索历史 entries[$i].added_names 包含无效名称。');
        }
        final name = value.trim();
        if (name.length > McpLoadedToolsTracker.defaultMaxNameCharacters) {
          throw FormatException('工具搜索历史 entries[$i].added_names 存在超长名称。');
        }
        if (name.isNotEmpty) addedNames.add(name);
      }
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
    return List<AiToolSearchLoadHistoryEntry>.unmodifiable(result);
  }
}

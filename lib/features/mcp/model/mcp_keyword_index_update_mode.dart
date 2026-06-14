import '../../../shared/util/date_time_format.dart';

/// MCP 关键词倒排索引的更新模式。控制何时（重新）构建索引：
///
///   - [coldStart]: 仅在 App 启动期惰性加载磁盘缓存；不再主动构建。
///     用户仍可点击「构建关键词映射」手动触发，定时任务保持禁用。
///   - [interval]: 启动期惰性加载 + 定时任务按 [intervalValue]+[intervalUnit]
///     周期重建并整体覆盖磁盘缓存。
///   - [scheduled]: 启动期惰性加载 + 每日固定时间（[scheduledTimeOfDay]
///     `HH:mm`）触发一次重建。
///
/// 选择 [interval] / [scheduled] 时，复用同一个内建 cron 任务
/// `mcp_keyword_index.rebuild`，仅修改其 cronExpression / enabled，
/// 避免任务碎片化。
enum McpKeywordIndexUpdateMode {
  coldStart('cold_start'),
  interval('interval'),
  scheduled('scheduled');

  const McpKeywordIndexUpdateMode(this.storageValue);

  final String storageValue;

  static McpKeywordIndexUpdateMode fromStorage(String? raw) {
    final v = raw?.trim().toLowerCase();
    for (final mode in McpKeywordIndexUpdateMode.values) {
      if (mode.storageValue == v) return mode;
    }
    return McpKeywordIndexUpdateMode.coldStart;
  }
}

/// [McpKeywordIndexUpdateMode.interval] 模式下的时间单位。
enum McpKeywordIndexIntervalUnit {
  minute('minute'),
  hour('hour'),
  day('day');

  const McpKeywordIndexIntervalUnit(this.storageValue);

  final String storageValue;

  static McpKeywordIndexIntervalUnit fromStorage(String? raw) {
    final v = raw?.trim().toLowerCase();
    for (final unit in McpKeywordIndexIntervalUnit.values) {
      if (unit.storageValue == v) return unit;
    }
    return McpKeywordIndexIntervalUnit.hour;
  }
}

/// 把（mode, intervalValue, intervalUnit, scheduledTimeOfDay）规约为
/// 5 段标准 cron 表达式（分 时 日 月 周）。
///
/// 防御点：
///  - 单位 minute 时 value 限定 [1,59]；超过 60 强制截到 59，再大也只在每小时
///    内重复，避免拼出非法 step。若需「每 60 分钟」请直接选 hour=1。
///  - 单位 hour 时 value 限定 [1,23]；同理。
///  - 单位 day 时 value 限定 [1,30]；day-step 任务统一在 02:00 触发，
///    给 stdio MCP 留充足启动余量。
///  - 兜底：解析失败 → 返回 `0 2 * * *`（每天 02:00 一次）。
String buildMcpKeywordIndexCronExpression({
  required McpKeywordIndexUpdateMode mode,
  required int intervalValue,
  required McpKeywordIndexIntervalUnit intervalUnit,
  required String scheduledTimeOfDay,
}) {
  switch (mode) {
    case McpKeywordIndexUpdateMode.coldStart:
      // cold-start 模式下任务保持 disabled，cron 表达式占位即可。
      return '0 2 * * *';
    case McpKeywordIndexUpdateMode.interval:
      switch (intervalUnit) {
        case McpKeywordIndexIntervalUnit.minute:
          final v = intervalValue.clamp(1, 59);
          if (v == 1) return '* * * * *';
          return '*/$v * * * *';
        case McpKeywordIndexIntervalUnit.hour:
          final v = intervalValue.clamp(1, 23);
          if (v == 1) return '0 * * * *';
          return '0 */$v * * *';
        case McpKeywordIndexIntervalUnit.day:
          final v = intervalValue.clamp(1, 30);
          if (v == 1) return '0 2 * * *';
          return '0 2 */$v * *';
      }
    case McpKeywordIndexUpdateMode.scheduled:
      final parsed = parseHourMinuteOfDay(scheduledTimeOfDay, fallbackHour: 2);
      return '${parsed.minute} ${parsed.hour} * * *';
  }
}

/// 校验 `HH:mm` 字符串。失败时返回默认 `02:00`。
String normalizeMcpKeywordIndexScheduledTimeOfDay(String raw) {
  return normalizeHourMinuteOfDay(raw, fallbackHour: 2);
}

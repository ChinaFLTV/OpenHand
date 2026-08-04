import '../../../l10n/app_localizations.dart';
import '../../../shared/util/input_value_parsing.dart';

/// 五段式分钟级 cron 表达式解析器。
///
/// 支持 `*`、精确值、逗号列表、范围（`1-5`）和步长（`*/5`、`1-30/5`）。
///
/// 不支持秒字段，界面固定为 0 秒。
class CronParser {
  CronParser._();

  static final RegExp _fieldSeparatorPattern = RegExp(r'\s+');

  /// 返回 [after] 之后的下一次执行时间；表达式无效或八年内无匹配时返回 null。
  static DateTime? nextRun(String expression, {DateTime? after}) {
    final fields = expression.trim().split(_fieldSeparatorPattern);
    final parsed = _parseExpressionFields(fields);
    if (parsed == null) return null;
    final (minutes, hours, daysOfMonth, months, daysOfWeek) = parsed;

    // 星期 0 和 7 都表示周日。
    final normalizedDow = daysOfWeek.map((d) => d == 7 ? 0 : d).toSet();
    final dayOfMonthUnrestricted = fields[2] == '*';
    final dayOfWeekUnrestricted = fields[4] == '*';
    final sortedHours = hours.toList(growable: false)..sort();
    final sortedMinutes = minutes.toList(growable: false)..sort();
    final start = after ?? DateTime.now();
    final isUtc = start.isUtc;
    var day = isUtc
        ? DateTime.utc(start.year, start.month, start.day)
        : DateTime(start.year, start.month, start.day);

    // 覆盖闰日跨 2100 年等最长八年间隔，同时按天扫描避免数百万次分钟循环。
    const maxDays = 366 * 8 + 2;
    for (var scannedDays = 0; scannedDays < maxDays; scannedDays++) {
      final dayOfMonthMatches = daysOfMonth.contains(day.day);
      final dayOfWeekMatches = normalizedDow.contains(day.weekday % 7);
      final dayMatches = dayOfMonthUnrestricted
          ? dayOfWeekUnrestricted || dayOfWeekMatches
          : dayOfWeekUnrestricted
          ? dayOfMonthMatches
          : dayOfMonthMatches || dayOfWeekMatches;
      if (months.contains(day.month) && dayMatches) {
        for (final hour in sortedHours) {
          for (final minute in sortedMinutes) {
            final candidate = isUtc
                ? DateTime.utc(day.year, day.month, day.day, hour, minute)
                : DateTime(day.year, day.month, day.day, hour, minute);
            if (candidate.year == day.year &&
                candidate.month == day.month &&
                candidate.day == day.day &&
                candidate.hour == hour &&
                candidate.minute == minute &&
                candidate.isAfter(start)) {
              return candidate;
            }
          }
        }
      }
      day = isUtc
          ? DateTime.utc(day.year, day.month, day.day + 1)
          : DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }

  static bool isValid(String expression) {
    return _parseExpressionFields(
          expression.trim().split(_fieldSeparatorPattern),
        ) !=
        null;
  }

  static (Set<int>, Set<int>, Set<int>, Set<int>, Set<int>)?
  _parseExpressionFields(List<String> fields) {
    if (fields.length != 5) return null;
    final minutes = _parseField(fields[0], 0, 59);
    final hours = _parseField(fields[1], 0, 23);
    final daysOfMonth = _parseField(fields[2], 1, 31);
    final months = _parseField(fields[3], 1, 12);
    final daysOfWeek = _parseField(fields[4], 0, 7);
    if (minutes == null ||
        hours == null ||
        daysOfMonth == null ||
        months == null ||
        daysOfWeek == null) {
      return null;
    }
    return (minutes, hours, daysOfMonth, months, daysOfWeek);
  }

  /// 校验五段式表达式；有效时返回 null，否则返回本地化错误。
  static String? validate(String expression, {required AppLocalizations l10n}) {
    final fields = expression.trim().split(_fieldSeparatorPattern);
    if (fields.length != 5) {
      return l10n.cronParserFieldCountError;
    }
    final labels = [
      l10n.cronParserFieldMinute,
      l10n.cronParserFieldHour,
      l10n.cronParserFieldDayOfMonth,
      l10n.cronParserFieldMonth,
      l10n.cronParserFieldDayOfWeek,
    ];
    const ranges = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)];
    for (var i = 0; i < 5; i++) {
      final parsed = _parseField(fields[i], ranges[i].$1, ranges[i].$2);
      if (parsed == null) {
        return l10n.cronParserInvalidField(labels[i], fields[i]);
      }
    }
    return null;
  }

  /// 解析单个 cron 字段；语法无效时返回 null。
  static Set<int>? _parseField(String field, int min, int max) {
    final result = <int>{};
    for (final part in field.split(',')) {
      if (part.isEmpty) return null;
      // 处理 */n 或 range/n 步长。
      final stepParts = part.split('/');
      if (stepParts.length > 2) return null;
      final step = stepParts.length == 2
          ? optionalPositiveIntFromValue(stepParts[1])
          : null;
      if (stepParts.length == 2 && step == null) return null;

      final rangePart = stepParts[0];

      int rangeStart;
      int rangeEnd;

      if (rangePart == '*') {
        rangeStart = min;
        rangeEnd = max;
      } else if (rangePart.contains('-')) {
        final bounds = rangePart.split('-');
        if (bounds.length != 2) return null;
        final a = optionalIntFromValue(bounds[0]);
        final b = optionalIntFromValue(bounds[1]);
        if (a == null || b == null) return null;
        if (a < min || b > max || a > b) return null;
        rangeStart = a;
        rangeEnd = b;
      } else {
        final val = optionalIntFromValue(rangePart);
        if (val == null || val < min || val > max) return null;
        if (step == null) {
          result.add(val);
          continue;
        }
        rangeStart = val;
        rangeEnd = max;
      }

      final effectiveStep = step ?? 1;
      for (var v = rangeStart; v <= rangeEnd; v += effectiveStep) {
        result.add(v);
      }
    }
    return result.isEmpty ? null : result;
  }
}

import 'duration_bounds.dart';
import 'input_value_parsing.dart';

const int _minHourOfDay = 0;
const int _maxHourOfDay = 23;
const int _minMinuteOfHour = 0;
const int _maxMinuteOfHour = 59;

String twoDigit(int value) => value.toString().padLeft(2, '0');

String threeDigit(int value) => value.toString().padLeft(3, '0');

String fourDigit(int value) => value.toString().padLeft(4, '0');

String formatHourMinute(DateTime value) {
  return '${twoDigit(value.hour)}:${twoDigit(value.minute)}';
}

String formatHourMinuteParts({required int hour, required int minute}) {
  return '${twoDigit(_clampHour(hour))}:${twoDigit(_clampMinute(minute))}';
}

({int hour, int minute}) parseHourMinuteOfDay(
  String raw, {
  int fallbackHour = 0,
  int fallbackMinute = 0,
}) {
  final safeFallbackHour = _clampHour(fallbackHour);
  final safeFallbackMinute = _clampMinute(fallbackMinute);
  final value = raw.trim();
  final colon = value.indexOf(':');
  if (colon <= 0 || colon >= value.length - 1) {
    return (hour: safeFallbackHour, minute: safeFallbackMinute);
  }
  final hour = optionalIntFromValue(value.substring(0, colon));
  final minute = optionalIntFromValue(value.substring(colon + 1));
  if (hour == null || minute == null) {
    return (hour: safeFallbackHour, minute: safeFallbackMinute);
  }
  return (hour: _clampHour(hour), minute: _clampMinute(minute));
}

int _clampHour(int value) => value.clamp(_minHourOfDay, _maxHourOfDay);

int _clampMinute(int value) => value.clamp(_minMinuteOfHour, _maxMinuteOfHour);

String normalizeHourMinuteOfDay(
  String raw, {
  int fallbackHour = 0,
  int fallbackMinute = 0,
}) {
  final parsed = parseHourMinuteOfDay(
    raw,
    fallbackHour: fallbackHour,
    fallbackMinute: fallbackMinute,
  );
  return formatHourMinuteParts(hour: parsed.hour, minute: parsed.minute);
}

String formatHourMinuteSecond(DateTime value) {
  return '${formatHourMinute(value)}:${twoDigit(value.second)}';
}

String formatHourMinuteSecondMillis(DateTime value) {
  return '${formatHourMinuteSecond(value)}.${threeDigit(value.millisecond)}';
}

String formatMonthDay(DateTime value) {
  return '${twoDigit(value.month)}-${twoDigit(value.day)}';
}

String formatMonthDayHm(DateTime value) {
  return '${formatMonthDay(value)} ${formatHourMinute(value)}';
}

String formatMonthDayHms(DateTime value) {
  return '${formatMonthDay(value)} ${formatHourMinuteSecond(value)}';
}

String formatYearMonthDay(DateTime value) {
  return '${fourDigit(value.year)}-${twoDigit(value.month)}-${twoDigit(value.day)}';
}

const int kRollingUsageWeekDays = 7;
const int kRollingUsageMonthSpan = 1;
const int kRollingUsageQuarterMonths = 3;
const int kRollingUsageYearMonths = 12;
const int kRollingUsageMaxTrendDays = 400;

/// 本地日历日（去掉时分秒），用于滚动统计窗口。
DateTime calendarDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 按日历月平移，自动夹到目标月最后一天（1 月 31 日减一个月 → 2 月 28/29 日）。
DateTime shiftCalendarMonths(DateTime date, int months) {
  final totalMonths = date.year * 12 + (date.month - 1) + months;
  final year = (totalMonths ~/ 12).clamp(1, 9999);
  final month = totalMonths - (totalMonths ~/ 12) * 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(year, month, day);
}

/// 最近 N 个自然日或最近 N 个日历月，两端都包含当天。
({DateTime start, DateTime end}) rollingCalendarDateWindow(
  DateTime now, {
  int daysInclusive = 1,
  int monthsBack = 0,
}) {
  final today = calendarDate(now);
  if (monthsBack > 0) {
    return (start: shiftCalendarMonths(today, -monthsBack), end: today);
  }
  final offset = daysInclusive < 1 ? 0 : daysInclusive - 1;
  return (start: today.subtract(Duration(days: offset)), end: today);
}

String formatYearMonthDayRange(DateTime start, DateTime end) {
  final startKey = formatYearMonthDay(start);
  final endKey = formatYearMonthDay(end);
  return startKey == endKey ? startKey : '$startKey ~ $endKey';
}

Iterable<DateTime> rollingCalendarDateDays(DateTime start, DateTime end) sync* {
  var date = calendarDate(start);
  final last = calendarDate(end);
  var steps = 0;
  while (!date.isAfter(last) && steps < kRollingUsageMaxTrendDays) {
    yield date;
    date = DateTime(date.year, date.month, date.day + 1);
    steps += 1;
  }
}

String formatYearMonthDayHm(DateTime value) {
  return '${formatYearMonthDay(value)} ${formatHourMinute(value)}';
}

String formatYearMonthDayHms(DateTime value) {
  return '${formatYearMonthDay(value)} ${formatHourMinuteSecond(value)}';
}

String formatYearMonthDayHmsMillis(DateTime value) {
  return '${formatYearMonthDayHms(value)}.${threeDigit(value.millisecond)}';
}

String formatHourMinuteLocal(DateTime value) =>
    formatHourMinute(value.toLocal());

String formatHourMinuteSecondLocal(DateTime value) =>
    formatHourMinuteSecond(value.toLocal());

String formatMonthDayHmLocal(DateTime value) =>
    formatMonthDayHm(value.toLocal());

String formatMonthDayHmsLocal(DateTime value) =>
    formatMonthDayHms(value.toLocal());

String formatYearMonthDayLocal(DateTime value) =>
    formatYearMonthDay(value.toLocal());

String formatYearMonthDayHmLocal(DateTime value) =>
    formatYearMonthDayHm(value.toLocal());

String formatYearMonthDayHmsLocal(DateTime value) =>
    formatYearMonthDayHms(value.toLocal());

String formatYearMonthDayHmsMillisLocal(DateTime value) =>
    formatYearMonthDayHmsMillis(value.toLocal());

/// 列表记录统一日期时间：yyyy-MM-dd HH:mm:ss（本地时区，24 小时制）。
String formatListDateTime(DateTime value) => formatYearMonthDayHmsLocal(value);

bool isDateTimeInUtcRange(
  DateTime value, {
  required DateTime? startUtc,
  required DateTime? endUtc,
}) {
  final utc = value.toUtc();
  final start = startUtc?.toUtc();
  final end = endUtc?.toUtc();
  if (start != null && utc.isBefore(start)) return false;
  if (end != null && utc.isAfter(end)) return false;
  return true;
}

const String kCompactDurationHourSuffix = 'h';
const String kCompactDurationMinuteSuffix = 'm';
const String kCompactDurationSecondSuffix = 's';

/// 紧凑时长的一段：数值与单位拆开，供日志拼串和运维胶囊共用。
class CompactDurationPart {
  const CompactDurationPart({required this.value, required this.suffix});

  final int value;
  final String suffix;

  String get label => '$value$suffix';

  /// 次级单位补到两位，避免 9s → 10s 时胶囊宽度跳动。
  String displayValue({required bool pad}) {
    if (!pad) return value < 0 ? '0' : '$value';
    if (value < 0) return '00';
    if (value > 99) return '$value';
    return value.toString().padLeft(2, '0');
  }
}

List<CompactDurationPart> compactDurationParts(Duration value) {
  final duration = nonNegativeDuration(value);
  if (duration.inHours > 0) {
    return [
      CompactDurationPart(
        value: duration.inHours,
        suffix: kCompactDurationHourSuffix,
      ),
      CompactDurationPart(
        value: duration.inMinutes.remainder(60),
        suffix: kCompactDurationMinuteSuffix,
      ),
    ];
  }
  if (duration.inMinutes > 0) {
    return [
      CompactDurationPart(
        value: duration.inMinutes,
        suffix: kCompactDurationMinuteSuffix,
      ),
      CompactDurationPart(
        value: duration.inSeconds.remainder(60),
        suffix: kCompactDurationSecondSuffix,
      ),
    ];
  }
  return [
    CompactDurationPart(
      value: duration.inSeconds,
      suffix: kCompactDurationSecondSuffix,
    ),
  ];
}

String formatCompactDuration(Duration value) {
  return compactDurationParts(value).map((part) => part.label).join(' ');
}

String formatCompactDurationMs(int milliseconds) {
  return formatCompactDuration(Duration(milliseconds: milliseconds));
}

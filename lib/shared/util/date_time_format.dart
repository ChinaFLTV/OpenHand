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

String formatYearMonthDayHm(DateTime value) {
  return '${formatYearMonthDay(value)} ${formatHourMinute(value)}';
}

String formatYearMonthDayHms(DateTime value) {
  return '${formatYearMonthDay(value)} ${formatHourMinuteSecond(value)}';
}

// 统一处理展示时间的本地时区转换。

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

String formatCompactDuration(Duration value) {
  final duration = nonNegativeDuration(value);
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
  return '${duration.inSeconds}s';
}

String formatCompactDurationMs(int milliseconds) {
  return formatCompactDuration(Duration(milliseconds: milliseconds));
}

String twoDigit(int value) => value.toString().padLeft(2, '0');

String threeDigit(int value) => value.toString().padLeft(3, '0');

String fourDigit(int value) => value.toString().padLeft(4, '0');

String formatHourMinute(DateTime value) {
  return '${twoDigit(value.hour)}:${twoDigit(value.minute)}';
}

String formatHourMinuteParts({required int hour, required int minute}) {
  return '${twoDigit(hour.clamp(0, 23))}:${twoDigit(minute.clamp(0, 59))}';
}

({int hour, int minute}) parseHourMinuteOfDay(
  String raw, {
  int fallbackHour = 0,
  int fallbackMinute = 0,
}) {
  final safeFallbackHour = fallbackHour.clamp(0, 23);
  final safeFallbackMinute = fallbackMinute.clamp(0, 59);
  final value = raw.trim();
  final colon = value.indexOf(':');
  if (colon <= 0 || colon >= value.length - 1) {
    return (hour: safeFallbackHour, minute: safeFallbackMinute);
  }
  final hour = int.tryParse(value.substring(0, colon));
  final minute = int.tryParse(value.substring(colon + 1));
  if (hour == null || minute == null) {
    return (hour: safeFallbackHour, minute: safeFallbackMinute);
  }
  return (hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
}

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

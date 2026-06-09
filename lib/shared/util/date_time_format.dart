String twoDigit(int value) => value.toString().padLeft(2, '0');

String threeDigit(int value) => value.toString().padLeft(3, '0');

String fourDigit(int value) => value.toString().padLeft(4, '0');

String formatHourMinute(DateTime value) {
  return '${twoDigit(value.hour)}:${twoDigit(value.minute)}';
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

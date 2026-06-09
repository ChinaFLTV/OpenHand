import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/date_time_format.dart';

void main() {
  group('date time formatting', () {
    final value = DateTime(2026, 1, 2, 3, 4, 5, 6);

    test('pads compact time fields consistently', () {
      expect(twoDigit(7), '07');
      expect(threeDigit(7), '007');
      expect(fourDigit(26), '0026');
    });

    test('formats common local display variants', () {
      expect(formatHourMinute(value), '03:04');
      expect(formatHourMinuteSecond(value), '03:04:05');
      expect(formatHourMinuteSecondMillis(value), '03:04:05.006');
      expect(formatMonthDay(value), '01-02');
      expect(formatMonthDayHm(value), '01-02 03:04');
      expect(formatMonthDayHms(value), '01-02 03:04:05');
      expect(formatYearMonthDay(value), '2026-01-02');
      expect(formatYearMonthDayHm(value), '2026-01-02 03:04');
      expect(formatYearMonthDayHms(value), '2026-01-02 03:04:05');
    });
  });
}

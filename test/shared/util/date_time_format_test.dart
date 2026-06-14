import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/date_time_format.dart';

void main() {
  group('hour-minute helpers', () {
    test('normalizes valid and out-of-range HH:mm values', () {
      expect(normalizeHourMinuteOfDay('09:05'), '09:05');
      expect(normalizeHourMinuteOfDay('28:77'), '23:59');
    });

    test('falls back on malformed input', () {
      expect(normalizeHourMinuteOfDay('bad', fallbackHour: 2), '02:00');
      expect(parseHourMinuteOfDay('11:', fallbackHour: 3, fallbackMinute: 15), (
        hour: 3,
        minute: 15,
      ));
    });
  });
}

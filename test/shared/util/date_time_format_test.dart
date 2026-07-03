import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/date_time_format.dart';

void main() {
  group('formatHourMinuteParts', () {
    test('pads valid hour and minute values', () {
      expect(formatHourMinuteParts(hour: 9, minute: 5), '09:05');
    });

    test('clamps out-of-range hour and minute values', () {
      expect(formatHourMinuteParts(hour: -4, minute: 80), '00:59');
      expect(formatHourMinuteParts(hour: 40, minute: -2), '23:00');
    });
  });

  group('parseHourMinuteOfDay', () {
    test('parses trimmed hour-minute text', () {
      expect(parseHourMinuteOfDay(' 08:45 '), (hour: 8, minute: 45));
    });

    test('allows whitespace around hour and minute parts', () {
      expect(parseHourMinuteOfDay('08 : 45'), (hour: 8, minute: 45));
    });

    test('clamps parsed values into the day range', () {
      expect(parseHourMinuteOfDay('99:70'), (hour: 23, minute: 59));
      expect(parseHourMinuteOfDay('-1:-2'), (hour: 0, minute: 0));
    });

    test('uses clamped fallback for malformed text', () {
      expect(
        parseHourMinuteOfDay(
          'not-a-time',
          fallbackHour: 30,
          fallbackMinute: -8,
        ),
        (hour: 23, minute: 0),
      );
    });
  });

  test('normalizeHourMinuteOfDay formats parsed values', () {
    expect(normalizeHourMinuteOfDay('7:3'), '07:03');
  });
}

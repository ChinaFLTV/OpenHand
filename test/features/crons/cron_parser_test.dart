import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/crons/model/cron_parser.dart';

void main() {
  test('nextRun handles step expressions from the following minute', () {
    final next = CronParser.nextRun(
      '*/15 * * * *',
      after: DateTime(2026, 7, 4, 10, 7),
    );

    expect(next, DateTime(2026, 7, 4, 10, 15));
  });

  test('nextRun handles ranges and day-of-week Sunday aliases', () {
    final next = CronParser.nextRun(
      '0 9 1-7 7 7',
      after: DateTime(2026, 7, 4, 10),
    );

    expect(next, DateTime(2026, 7, 5, 9));
  });

  test('nextRun rejects invalid or non-positive step expressions', () {
    expect(CronParser.nextRun('*/0 * * * *'), isNull);
    expect(CronParser.nextRun('1-0 * * * *'), isNull);
    expect(CronParser.nextRun('1.5 * * * *'), isNull);
  });
}

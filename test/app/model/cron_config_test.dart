import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/cron_config.dart';

void main() {
  test('cron retry count stays within supported bounds', () {
    expect(clampCronRetryCount(-1), kCronMinRetryCount);
    expect(clampCronRetryCount(kCronDefaultRetryCount), kCronDefaultRetryCount);
    expect(clampCronRetryCount(kCronMaxRetryCount + 1), kCronMaxRetryCount);
  });

  test('cron timeout stays within supported bounds', () {
    expect(clampCronTimeoutSeconds(0), kCronMinTimeoutSeconds);
    expect(
      clampCronTimeoutSeconds(kCronDefaultTimeoutSeconds),
      kCronDefaultTimeoutSeconds,
    );
    expect(
      clampCronTimeoutSeconds(kCronMaxTimeoutSeconds + 1),
      kCronMaxTimeoutSeconds,
    );
  });

  test('cron retry delay stays within supported bounds', () {
    expect(clampCronRetryDelaySeconds(0), kCronMinRetryDelaySeconds);
    expect(
      clampCronRetryDelaySeconds(kCronDefaultRetryDelaySeconds),
      kCronDefaultRetryDelaySeconds,
    );
    expect(
      clampCronRetryDelaySeconds(kCronMaxRetryDelaySeconds + 1),
      kCronMaxRetryDelaySeconds,
    );
  });

  test('cron entry fromJson clamps runtime integer bounds', () {
    final entry = CronEntry.fromJson(<String, Object?>{
      'id': 'cron-1',
      'name': 'Cron',
      'retry_count': kCronMaxRetryCount + 100,
      'timeout_seconds': 0,
      'max_retry_delay_seconds': kCronMaxRetryDelaySeconds + 100,
      'consecutive_failures': -5,
    });

    expect(entry.retryCount, kCronMaxRetryCount);
    expect(entry.timeoutSeconds, kCronMinTimeoutSeconds);
    expect(entry.maxRetryDelaySeconds, kCronMaxRetryDelaySeconds);
    expect(entry.consecutiveFailures, 0);
  });

  test('cron execution record drops negative counters from json', () {
    final record = CronExecutionRecord.fromJson(<String, Object?>{
      'id': 'record-1',
      'cron_id': 'cron-1',
      'started_at': '2026-01-01T00:00:00.000Z',
      'elapsed_ms': -10,
      'retry_attempt': -2,
    });

    expect(record.elapsedMs, 0);
    expect(record.retryAttempt, 0);
  });
}

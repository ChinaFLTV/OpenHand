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
}

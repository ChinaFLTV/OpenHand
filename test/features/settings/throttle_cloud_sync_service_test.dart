import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/settings/service/throttle_cloud_sync_service.dart';

void main() {
  test('legacy or unknown providers fall back to custom HTTP', () {
    expect(
      ThrottleCloudSyncProvider.fromStorage('oauth'),
      ThrottleCloudSyncProvider.custom,
    );
    expect(
      ThrottleCloudSyncProvider.fromStorage('unknown'),
      ThrottleCloudSyncProvider.custom,
    );
  });

  test('supported provider storage values round trip', () {
    for (final provider in ThrottleCloudSyncProvider.values) {
      expect(
        ThrottleCloudSyncProvider.fromStorage(provider.storageValue),
        provider,
      );
    }
  });
}

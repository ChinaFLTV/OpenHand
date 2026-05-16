// 节流预设映射到 CDP Network.emulateNetworkConditions 参数。

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_session_controller.dart';

void main() {
  test('none：disable everything（offline=false / 各 throughput=-1）', () {
    final p = WebReverseThrottlePreset.none.cdpParams;
    expect(p['offline'], false);
    expect(p['latency'], 0);
    expect(p['downloadThroughput'], -1);
    expect(p['uploadThroughput'], -1);
  });

  test('offline：offline=true', () {
    final p = WebReverseThrottlePreset.offline.cdpParams;
    expect(p['offline'], true);
  });

  test('slow3g / fast3g 的 throughput 单位是 byte/s', () {
    final slow = WebReverseThrottlePreset.slow3g.cdpParams;
    // 500 kbps = 500*1024/8 byte/s
    expect(slow['downloadThroughput'], 500 * 1024 / 8);
    final fast = WebReverseThrottlePreset.fast3g.cdpParams;
    expect(fast['downloadThroughput'], 1500 * 1024 / 8);
    expect(fast['uploadThroughput'], 750 * 1024 / 8);
  });
}

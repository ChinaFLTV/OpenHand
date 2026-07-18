import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/shared/util/html_webview_mount_limiter.dart';

void main() {
  test('轻量统计响应不序列化缓存趋势点', () {
    final statistics = const AiSessionStatistics.initial().copyWith(
      totalPromptTokens: 200,
      cacheReadTokens: 120,
      cacheHitTrendPoints: const <AiSessionCacheHitTrendPoint>[
        AiSessionCacheHitTrendPoint(
          turnIndex: 1,
          hitRatio: 0.6,
          promptTokens: 200,
          cacheReadTokens: 120,
          cacheWriteTokens: 0,
          starterOrigin: 'explicit_user',
        ),
      ],
    );

    final lightweight = statistics.toJson(includeCacheHitTrendPoints: false);
    final complete = statistics.toJson();

    expect(lightweight, isNot(contains('cache_hit_trend_points')));
    expect(complete['cache_hit_trend_points'], hasLength(1));
  });

  test('HTML 平台视图许可保持并发上限并延迟授予回调', () {
    final scheduled = <void Function()>[];
    final limiter = HtmlWebViewMountLimiter(
      maxMounted: 1,
      scheduleGranted: scheduled.add,
    );
    var revoked = 0;
    var granted = 0;
    final first = limiter.request(() {}, onRevoked: () => revoked += 1);
    final second = limiter.request(() => granted += 1);

    expect(first.granted, isTrue);
    expect(second.granted, isFalse);

    limiter.revokeOldest();

    expect(revoked, 1);
    expect(second.granted, isTrue);
    expect(granted, 0);
    expect(scheduled, hasLength(1));

    scheduled.single();
    expect(granted, 1);
    second.release();
  });
}

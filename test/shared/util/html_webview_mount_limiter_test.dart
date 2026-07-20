import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/html_webview_mount_limiter.dart';

void main() {
  test('按优先级发放许可并拒绝超出上限的等待请求', () {
    final granted = <String>[];
    final limiter = HtmlWebViewMountLimiter(maxMounted: 1, maxWaiting: 2);
    final active = limiter.request(() => granted.add('活动'));
    final normal = limiter.request(() => granted.add('普通'));
    final priority = limiter.request(() => granted.add('优先'), priority: true);
    final rejected = limiter.request(() => granted.add('拒绝'));

    expect(active.granted, isTrue);
    expect(normal.granted, isFalse);
    expect(priority.granted, isFalse);
    expect(rejected.released, isTrue);

    active.release();
    expect(priority.granted, isTrue);
    expect(granted, <String>['优先']);

    priority.release();
    expect(normal.granted, isTrue);
    expect(granted, <String>['优先', '普通']);
  });

  test('清空时撤销活动许可并释放全部等待项', () {
    var revoked = 0;
    final limiter = HtmlWebViewMountLimiter(maxMounted: 1, maxWaiting: 2);
    final active = limiter.request(() {}, onRevoked: () => revoked += 1);
    final waiting = limiter.request(() {});

    limiter.clear();

    expect(active.released, isTrue);
    expect(active.granted, isFalse);
    expect(waiting.released, isTrue);
    expect(revoked, 1);
  });

  test('异常配置会归一化到安全范围', () {
    final limiter = HtmlWebViewMountLimiter(
      maxMounted: 0,
      maxWaiting: HtmlWebViewMountLimiter.maxAllowedWaiting + 1,
    );

    expect(limiter.maxMounted, 1);
    expect(limiter.maxWaiting, HtmlWebViewMountLimiter.maxAllowedWaiting);
  });
}

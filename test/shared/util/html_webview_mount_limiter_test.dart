import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/html_webview_mount_limiter.dart';

void main() {
  test('释放启动许可后依次唤醒等待者', () {
    final granted = <String>[];
    final limiter = HtmlWebViewMountLimiter();

    final first = limiter.request(() => granted.add('first'));
    final second = limiter.request(() => granted.add('second'));
    final third = limiter.request(() => granted.add('third'));
    final fourth = limiter.request(() => granted.add('fourth'));

    expect(first.granted, isTrue);
    expect(second.granted, isTrue);
    expect(third.granted, isFalse);
    expect(fourth.granted, isFalse);

    first.release();
    expect(third.granted, isTrue);
    expect(granted, <String>['third']);

    second.release();
    expect(fourth.granted, isTrue);
    expect(granted, <String>['third', 'fourth']);
  });

  test('优先等待者先获得许可且重复释放幂等', () {
    final granted = <String>[];
    final limiter = HtmlWebViewMountLimiter(maxMounted: 1);

    final active = limiter.request(() => granted.add('active'));
    final normal = limiter.request(() => granted.add('normal'));
    final priority = limiter.request(
      () => granted.add('priority'),
      priority: true,
    );

    active.release();
    active.release();

    expect(priority.granted, isTrue);
    expect(normal.granted, isFalse);
    expect(granted, <String>['priority']);

    priority.release();
    expect(normal.granted, isTrue);
    expect(granted, <String>['priority', 'normal']);
  });

  test('释放未授予的等待者不会消耗活动槽位', () {
    final limiter = HtmlWebViewMountLimiter(maxMounted: 1);
    final active = limiter.request(() {});
    final cancelled = limiter.request(() {});
    final next = limiter.request(() {});

    cancelled.release();
    active.release();

    expect(cancelled.released, isTrue);
    expect(next.granted, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/openhand_home_page.dart';
import 'package:openhand/shared/ui/rich_content_frame_scheduler.dart';

void main() {
  testWidgets('滚动间歇及时恢复渲染，连续输入重新计时', (tester) async {
    final activity = TranscriptScrollActivity();
    addTearDown(activity.dispose);
    final changes = <bool>[];
    activity.addListener(() => changes.add(activity.value));

    activity.markActive();
    await tester.pump(const Duration(milliseconds: 100));
    activity.markActive();
    await tester.pump(const Duration(milliseconds: 100));
    expect(activity.value, isTrue);
    await tester.pump(const Duration(milliseconds: 20));
    expect(activity.value, isFalse);
    expect(changes, <bool>[true, false]);
  });

  testWidgets('切换会话和销毁会取消滚动等待', (tester) async {
    final activity = TranscriptScrollActivity();
    activity.markActive();
    activity.markInactive();
    expect(activity.value, isFalse);
    activity.markActive();
    activity.dispose();
    await tester.pump(TranscriptScrollActivity.settleDelay);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可见正文先于预热且按入队顺序逐帧完成', (tester) async {
    final scheduler = RichContentFrameScheduler();
    addTearDown(scheduler.clear);
    final rendered = <String>[];
    scheduler.schedule(() => rendered.add('预热'));
    scheduler.schedule(() => rendered.add('历史正文'), priority: true);
    scheduler.schedule(() => rendered.add('新进入正文'), priority: true);

    await tester.pump();
    expect(rendered, <String>['历史正文']);
    scheduler.schedule(() => rendered.add('继续进入正文'), priority: true);
    await tester.pump();
    expect(rendered, <String>['历史正文', '新进入正文']);
    await tester.pump();
    await tester.pump();
    expect(rendered, <String>['历史正文', '新进入正文', '继续进入正文', '预热']);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('暂停平台视图不阻塞正文，各队列仍共用一帧额度', (tester) async {
    var scrolling = true;
    final platformViews = RichContentFrameScheduler(isPaused: () => scrolling);
    final markdown = RichContentFrameScheduler();
    addTearDown(platformViews.clear);
    addTearDown(markdown.clear);
    final rendered = <String>[];
    platformViews.schedule(() => rendered.add('平台视图'), priority: true);
    markdown.schedule(() => rendered.add('正文一'), priority: true);
    markdown.schedule(() => rendered.add('正文二'), priority: true);
    await tester.pump();
    expect(rendered, <String>['正文一']);
    await tester.pump();
    expect(rendered, <String>['正文一', '正文二']);
    scrolling = false;
    await tester.pump();
    expect(rendered, <String>['正文一', '正文二', '平台视图']);
  });

  testWidgets('失效任务及时丢弃，队列清空后不再执行', (tester) async {
    final scheduler = RichContentFrameScheduler(maxPending: 2);
    addTearDown(scheduler.clear);
    var dropped = 0;
    var rendered = 0;
    scheduler.schedule(() => rendered++, onDropped: () => dropped++);
    scheduler.schedule(
      () => rendered++,
      priority: true,
      isValid: () => false,
      onDropped: () => dropped++,
    );
    scheduler.schedule(() => rendered++, priority: true);
    expect(dropped, 1);
    await tester.pump();
    expect(dropped, 2);
    expect(rendered, 1);
    scheduler.schedule(() => rendered++, onDropped: () => dropped++);
    scheduler.clear();
    await tester.pump();
    expect(rendered, 1);
    expect(dropped, 3);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

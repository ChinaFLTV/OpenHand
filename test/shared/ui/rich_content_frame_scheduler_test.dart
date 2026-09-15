import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/rich_content_frame_scheduler.dart';

void main() {
  testWidgets('解析、高亮和平台挂载共用帧额度并轮流执行', (tester) async {
    final queues = List.generate(3, (_) => RichContentFrameScheduler());
    final completed = <int>[];
    for (var index = 0; index < queues.length; index++) {
      queues[index].schedule(() => completed.add(index));
      queues[index].schedule(() => completed.add(index));
    }
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
      expect(completed.length, frame + 1);
    }
    expect(completed, [0, 1, 2, 0, 1, 2]);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('可见任务优先于其他队列预热，嵌套任务留到下一帧', (tester) async {
    final warmup = RichContentFrameScheduler();
    final visible = RichContentFrameScheduler();
    final completed = <String>[];
    warmup.schedule(() => completed.add('预热'));
    visible.schedule(() {
      completed.add('正文');
      visible.schedule(() => completed.add('高亮'), priority: true);
    }, priority: true);
    await tester.pump();
    expect(completed, ['正文']);
    await tester.pump();
    expect(completed, ['正文', '高亮']);
    await tester.pump();
    expect(completed, ['正文', '高亮', '预热']);
  });

  testWidgets('切换会话清除两千条任务，滚动暂停不阻塞其他队列', (tester) async {
    var paused = true;
    var dropped = 0;
    var completed = 0;
    final old = RichContentFrameScheduler();
    final current = RichContentFrameScheduler(isPaused: () => paused);
    for (var index = 0; index < 2000; index++) {
      old.schedule(() => fail('旧会话任务不应执行'), onDropped: () => dropped++);
    }
    old.clear();
    current.schedule(() => completed++);
    old.schedule(() => completed++);
    await tester.pump();
    expect(dropped, 2000);
    expect(completed, 1);
    paused = false;
    await tester.pump();
    expect(completed, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('队列有界，过期任务分帧清理且异常不会堵塞后续任务', (tester) async {
    final queue = RichContentFrameScheduler(maxPending: 2);
    var dropped = 0;
    var completed = 0;
    queue.schedule(() {}, onDropped: () => dropped++);
    queue.schedule(() => throw StateError('模拟解析失败'));
    queue.schedule(() => completed++);
    expect(dropped, 1);
    await tester.pump();
    expect(tester.takeException(), isStateError);
    await tester.pump();
    expect(completed, 1);
    final expired = RichContentFrameScheduler();
    for (var index = 0; index < 1000; index++) {
      expired.schedule(
        () => fail('过期任务不应执行'),
        isValid: () => false,
        onDropped: () => dropped++,
      );
    }
    await tester.pump();
    expect(dropped, 65);
    expired.clear();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

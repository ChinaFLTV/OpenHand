import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/dingtalk_message_gateway_controller.dart';

void main() {
  group('钉钉响应队列恢复', () {
    test('指定消息优先且其余消息保持原顺序', () {
      final queue = Queue<int>.from(<int>[1, 2, 3, 4]);

      final found = prioritizeDingTalkQueuedResponse(
        queue,
        (item) => item == 3,
      );

      expect(found, isTrue);
      expect(queue.toList(), <int>[3, 1, 2, 4]);
    });

    test('目标不存在时不改变队列', () {
      final queue = Queue<int>.from(<int>[1, 2, 3]);

      final found = prioritizeDingTalkQueuedResponse(
        queue,
        (item) => item == 4,
      );

      expect(found, isFalse);
      expect(queue.toList(), <int>[1, 2, 3]);
    });

    test('仅允许空闲的暂停队列恢复一次', () {
      expect(
        canResumeDingTalkQueuedResponse(
          serviceEnabled: true,
          queuePaused: true,
          responseActive: false,
          itemExists: true,
        ),
        isTrue,
      );
      expect(
        canResumeDingTalkQueuedResponse(
          serviceEnabled: true,
          queuePaused: false,
          responseActive: false,
          itemExists: true,
        ),
        isFalse,
      );
      expect(
        canResumeDingTalkQueuedResponse(
          serviceEnabled: true,
          queuePaused: true,
          responseActive: true,
          itemExists: true,
        ),
        isFalse,
      );
    });
  });
}

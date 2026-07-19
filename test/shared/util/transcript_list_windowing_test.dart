import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/transcript_list_windowing.dart';

void main() {
  group('TranscriptListWindowing.windowStartAfterAppend', () {
    test('短会话追加消息不折叠首轮上下文', () {
      expect(
        TranscriptListWindowing.windowStartAfterAppend(
          previousWindowStart: 0,
          previousMessageCount: 1,
          messageCount: 2,
        ),
        0,
      );
      expect(
        TranscriptListWindowing.windowStartAfterAppend(
          previousWindowStart: 1,
          previousMessageCount: 2,
          messageCount: 3,
        ),
        0,
      );
    });

    test('从顶部跟随追加时只在超过物化上限后滑动', () {
      expect(
        TranscriptListWindowing.windowStartAfterAppend(
          previousWindowStart: 0,
          previousMessageCount: 4,
          messageCount: 5,
          maxMaterialized: 4,
        ),
        1,
      );
    });

    test('长历史阅读旧片段时不被新消息拉回底部', () {
      expect(
        TranscriptListWindowing.windowStartAfterAppend(
          previousWindowStart: 0,
          previousMessageCount: 60,
          messageCount: 61,
        ),
        0,
      );
    });
  });
}

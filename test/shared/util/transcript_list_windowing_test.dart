import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/transcript_list_windowing.dart';

void main() {
  test('初始窗口与首帧始终保留最新尾部', () {
    expect(TranscriptListWindowing.initialWindowStartIndex(0), 0);
    expect(TranscriptListWindowing.initialWindowStartIndex(12), 0);
    expect(TranscriptListWindowing.initialWindowStartIndex(13), 5);
    expect(TranscriptListWindowing.openFirstPaintStartIndex(8), 4);
  });

  test('物化范围在长会话中维持四十八条硬上限', () {
    expect(
      TranscriptListWindowing.boundedRange(
        preferredStart: 952,
        messageCount: 1000,
      ),
      (start: 952, end: 1000),
    );
    expect(
      TranscriptListWindowing.boundedRange(
        preferredStart: 946,
        messageCount: 1000,
      ),
      (start: 946, end: 994),
    );
    expect(
      TranscriptListWindowing.boundedRange(preferredStart: 0, messageCount: 49),
      (start: 0, end: 48),
    );
  });

  test('连续向前浏览时窗口滑动而非扩大', () {
    var start = TranscriptListWindowing.latestWindowStart(1000);
    expect(start, 952);
    for (var index = 0; index < 100; index += 1) {
      start = TranscriptListWindowing.revealOlderWindowStart(start);
      final range = TranscriptListWindowing.boundedRange(
        preferredStart: start,
        messageCount: 1000,
      );
      expect(range.end - range.start, lessThanOrEqualTo(48));
    }
    expect(start, 352);
  });

  test('实时追加仅在当前窗口贴着尾部时跟随最新消息且保持宽度', () {
    expect(
      TranscriptListWindowing.windowStartAfterAppend(
        previousWindowStart: 92,
        previousMessageCount: 100,
        messageCount: 101,
      ),
      93,
    );
    expect(
      TranscriptListWindowing.windowStartAfterAppend(
        previousWindowStart: 952,
        previousMessageCount: 1000,
        messageCount: 1001,
      ),
      953,
    );
    expect(
      TranscriptListWindowing.windowStartAfterAppend(
        previousWindowStart: 946,
        previousMessageCount: 1000,
        messageCount: 1001,
      ),
      946,
    );
  });

  test('prepend 与边界输入保持合法', () {
    expect(
      TranscriptListWindowing.windowStartAfterHistoryPrepend(
        previousWindowStart: 0,
        addedDisplayCount: 12,
      ),
      6,
    );
    expect(
      TranscriptListWindowing.boundedRange(
        preferredStart: -10,
        messageCount: 0,
      ),
      (start: 0, end: 0),
    );
    expect(TranscriptListWindowing.latestWindowStart(48), 0);
    expect(TranscriptListWindowing.latestWindowStart(49), 1);
  });
}

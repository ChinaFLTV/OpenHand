import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/transcript_list_windowing.dart';

void main() {
  group('长会话窗口', () {
    test('首次打开千条消息时只物化尾部窗口', () {
      expect(TranscriptListWindowing.initialWindowStartIndex(1000), 992);
    });

    test('物化范围始终受最大数量限制', () {
      final range = TranscriptListWindowing.boundedRange(
        preferredStart: 320,
        messageCount: 1000,
      );

      expect(range, (start: 320, end: 368));
      expect(
        range.end - range.start,
        lessThanOrEqualTo(TranscriptListWindowing.defaultMaxMaterializedWindow),
      );
    });
  });

  group('正文预览', () {
    test('短正文保持不变', () {
      const content = '简短正文';
      final preview = TranscriptListWindowing.boundedContentPreview(
        content,
        maxCharacters: 1200,
      );

      expect(preview, same(content));
    });

    test('长正文不超过上限', () {
      final content = List.filled(2000, 'a').join();
      final preview = TranscriptListWindowing.boundedContentPreview(
        content,
        maxCharacters: 1200,
      );

      expect(preview.length, 1200);
    });

    test('不会切断表情符号代理对', () {
      const content = 'a😀b';
      final preview = TranscriptListWindowing.boundedContentPreview(
        content,
        maxCharacters: 2,
      );

      expect(preview, 'a');
    });
  });
}

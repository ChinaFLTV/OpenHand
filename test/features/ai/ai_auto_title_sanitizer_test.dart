import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/ai_session_controller.dart';

void main() {
  group('自动标题清洗', () {
    test('多个标题候选只保留首个非空标题', () {
      expect(
        sanitizeAiGeneratedTitle(
          '<title>黑洞漫步科幻电影视频</title>\n'
          '<title>黑洞漫步科幻电影视频</title>',
        ),
        '黑洞漫步科幻电影视频',
      );
    });

    test('跳过空标题并移除候选内部标签', () {
      expect(
        sanitizeAiGeneratedTitle(
          '<title></title><title><b>黑洞漫步科幻电影视频</b></title>',
        ),
        '黑洞漫步科幻电影视频',
      );
    });

    test('继续兼容普通文本标题', () {
      expect(sanitizeAiGeneratedTitle('“黑洞漫步科幻电影视频”'), '黑洞漫步科幻电影视频');
    });
  });
}

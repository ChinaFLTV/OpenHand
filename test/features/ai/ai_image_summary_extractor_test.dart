import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/media/ai_image_summary_extractor.dart';
import 'package:openhand/shared/util/text_normalization.dart';

void main() {
  group('AiImageSummaryExtractor', () {
    test('提取摘要并清理完整标签', () {
      const content = '''回答正文

<image_summary attachment_id="img-1">
一只坐在草坪上的奶牛。
</image_summary>
结尾''';

      final result = AiImageSummaryExtractor.extractAndStrip(content);

      expect(result.summariesByAttachmentId, <String, String>{
        'img-1': '一只坐在草坪上的奶牛。',
      });
      expect(result.strippedContent, '回答正文\n\n结尾');
      expect(result.strippedContent, isNot(contains('image_summary')));
    });

    test('支持单引号和无引号属性值', () {
      const content =
          "<image_summary attachment_id='a'>甲</image_summary>\n"
          '<image_summary attachment_id=b>乙</image_summary>';

      final result = AiImageSummaryExtractor.extractAndStrip(content);

      expect(result.summariesByAttachmentId, <String, String>{
        'a': '甲',
        'b': '乙',
      });
      expect(result.strippedContent, isEmpty);
    });

    test('流式未闭合标签及其属性不会泄漏', () {
      expect(
        stripImageSummaryMarkup('回答\n<image_summary attachment_id="img-1">一只牛'),
        '回答',
      );
      expect(stripImageSummaryMarkup('回答\n<image_summ'), '回答');
    });

    test('没有摘要标签时保持正文内容', () {
      const content = '普通文本 <image> 图片占位符';
      expect(stripImageSummaryMarkup(content), content);
    });
  });
}

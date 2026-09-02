import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/model/assistant_response_completion.dart';

void main() {
  group('assistantResponseNeedsContinuation', () {
    test('识别历史会话中的突兀中断回复', () {
      const replies = <String>[
        '北京天气查询超时了，重试一次：',
        '调用音频生成工具生成中国古风音乐：',
        'mode 参数不接受，换成 `ti2vid` 重试：',
        '搜索没结果……直接调用：',
        '重新尝试一次：',
      ];

      for (final reply in replies) {
        expect(
          assistantResponseNeedsContinuation(reply),
          isTrue,
          reason: reply,
        );
      }
    });

    test('识别只声明下一步动作的中英文回复', () {
      const replies = <String>[
        '我会继续查询。',
        '正在重新查询中……',
        'Let me try again.',
        'Retrying now...',
      ];

      for (final reply in replies) {
        expect(
          assistantResponseNeedsContinuation(reply),
          isTrue,
          reason: reply,
        );
      }
    });

    test('识别未闭合的代码围栏和结构开头', () {
      expect(
        assistantResponseNeedsContinuation('结果如下：\n```dart\nvoid main() {}'),
        isTrue,
      );
      expect(assistantResponseNeedsContinuation('下一步（'), isTrue);
    });

    test('不误判完整结论、失败说明和闭合代码块', () {
      const replies = <String>[
        '北京今天晴，最高气温 28℃，出门注意防晒。',
        '天气服务暂时不可用，请稍后重试。',
        '已重新查询：北京当前气温 24℃。',
        '本功能支持天气查询。',
        '示例：\n```dart\nvoid main() {}\n```',
        '',
      ];

      for (final reply in replies) {
        expect(
          assistantResponseNeedsContinuation(reply),
          isFalse,
          reason: reply,
        );
      }
    });
  });
}

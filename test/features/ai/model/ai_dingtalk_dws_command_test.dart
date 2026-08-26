import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_dingtalk_dws_command.dart';

void main() {
  test('命令描述裁剪不会拆分表情字符', () {
    final prefix = List<String>.filled(399, 'a').join();
    final command = AiDingTalkDwsCommand.fromJson(<String, Object?>{
      'cli_path': 'calendar/event/list',
      'name': '查询日程',
      'description': '$prefix😀',
    });

    expect(command.description, '$prefix…');
    expect(command.description.length, 400);
  });
}

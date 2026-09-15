import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/widgets/dingtalk_conversation_detail_labels.dart';

void main() {
  test('strips duplicate numeric suffixes from labels', () {
    expect(dingTalkDetailLabelParts('部门资料 1'), (stem: '部门资料', suffix: '1'));
    expect(dingTalkDetailLabelParts('会话标识'), (stem: '会话标识', suffix: null));
  });

  test('treats 是否 and notification labels as flags', () {
    expect(dingTalkDetailIsFlagLabel('是否置顶'), isTrue);
    expect(dingTalkDetailIsFlagLabel('通知'), isTrue);
    expect(dingTalkDetailIsFlagLabel('管理员权限'), isTrue);
    expect(dingTalkDetailIsFlagLabel('企业名称'), isFalse);
  });

  test('parses 0/1 flag values', () {
    expect(dingTalkDetailBinaryFlag(0), isFalse);
    expect(dingTalkDetailBinaryFlag(1), isTrue);
    expect(dingTalkDetailBinaryFlag('0'), isFalse);
    expect(dingTalkDetailBinaryFlag('1'), isTrue);
    expect(dingTalkDetailBinaryFlag(2), isNull);
  });

  test('flattens single-item lists and wrapper settings maps', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '设置': <Object?>[
        <String, Object?>{'通知': 0, '是否置顶': 1},
      ],
    });
    expect(flattened, <String, Object?>{'通知': 0, '是否置顶': 1});
  });

  test('drops empty nested maps and lists', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '部门标识': 142720783,
      '部门资料': const <Object?>[],
    });
    expect(flattened, <String, Object?>{'部门标识': 142720783});
  });
}

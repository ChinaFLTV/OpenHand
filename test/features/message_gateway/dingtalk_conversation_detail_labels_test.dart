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

  test('maps numeric role types to localized role names', () {
    expect(dingTalkDetailRoleTypeZh(1), kDingTalkDetailOwnerRole);
    expect(dingTalkDetailRoleTypeZh('2'), kDingTalkDetailAdminRole);
    expect(dingTalkDetailRoleTypeZh(3), kDingTalkDetailMemberRole);
    expect(dingTalkDetailRoleTypeZh(9), isNull);
  });

  test('flattens single-item lists and wrapper settings maps', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '设置': <Object?>[
        <String, Object?>{'通知': 0, '是否置顶': 1},
      ],
    });
    expect(flattened, <String, Object?>{'通知': 0, '是否置顶': 1});
  });

  test('hoists extension and department wrappers then hides noise fields', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '企业名称': '学纳',
      '是否单聊': 0,
      '扩展属性': <String, Object?>{'钉盘空间标识': 28646723847},
      '部门资料': <String, Object?>{
        '部门标识': 142720783,
        '部门详情': <String, Object?>{'部门': 'D000320', '头像媒体标识': '@IQD'},
      },
    });
    expect(flattened, <String, Object?>{
      '企业名称': '学纳',
      '钉盘空间标识': 28646723847,
      '部门资料': <String, Object?>{'部门标识': 142720783, '部门': 'D000320'},
    });
  });

  test('promotes numeric role type into 群内角色 and drops the raw code', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '钉钉用户标识': 'user-1',
      '角色类型': 1,
      '头像媒体标识': '@media',
    });
    expect(flattened, <String, Object?>{
      '钉钉用户标识': 'user-1',
      '群内角色': kDingTalkDetailOwnerRole,
    });
  });

  test('keeps existing 群内角色 when both role fields are present', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      '群内角色': '群主',
      '角色类型': 3,
    });
    expect(flattened, <String, Object?>{'群内角色': '群主'});
  });

  test('unwraps a lone bots list wrapper', () {
    final flattened = dingTalkFlattenDetailValue(<String, Object?>{
      'bots': <Object?>[
        <String, Object?>{'botName': '助手', 'openBotId': 'bot-1'},
        <String, Object?>{'botName': '值班', 'openBotId': 'bot-2'},
      ],
    });
    expect(flattened, isA<List<Object?>>());
    expect((flattened as List<Object?>).length, 2);
  });

  test('omits identity echo that already appears in the header', () {
    final omitted = dingTalkDetailOmitIdentityEcho(
      <String, Object?>{
        '会话标识': 'cid-same',
        '名称': '阿Kei',
        '成员数量': 3,
        '钉盘空间标识': 12,
      },
      title: '阿Kei',
      conversationId: 'cid-same',
    );
    expect(omitted, <String, Object?>{'成员数量': 3, '钉盘空间标识': 12});
  });

  test('keeps a different conversation id in the overview', () {
    final omitted = dingTalkDetailOmitIdentityEcho(
      <String, Object?>{'会话标识': 'cid-open', '名称': '王秀杰', '成员数量': 2},
      title: '王秀杰',
      conversationId: '251548560029418107',
    );
    expect(omitted, <String, Object?>{'会话标识': 'cid-open', '成员数量': 2});
  });

  test('treats 可管理 as a flag label', () {
    expect(dingTalkDetailIsFlagLabel('可管理'), isTrue);
    expect(dingTalkDetailIsFlagLabel('是否创建者'), isTrue);
  });
}

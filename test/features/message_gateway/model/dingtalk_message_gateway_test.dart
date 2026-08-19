import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('钉钉贴表情解析', () {
    test('完整解析 emotionReplyList 中的多组贴表情', () {
      final reactions = parseDingTalkMessageReactions(<String, Object?>{
        'emotionReplyList': <Object?>[
          <String, Object?>{
            'emoji': 'OK',
            'replyUsers': <String>['唐皓伦'],
          },
          <String, Object?>{
            'emoji': '👍👍🏻👍🏽👍🏿',
            'replyUsers': <String>['唐皓伦'],
          },
          <String, Object?>{
            'emoji': '因吹斯汀',
            'replyUsers': <String>['唐皓伦'],
          },
        ],
      });

      expect(reactions, <String>['👌', '👍👍🏻👍🏽👍🏿', '因吹斯汀']);
    });

    test('合并新旧字段并去重', () {
      final reactions = parseDingTalkMessageReactions(<String, Object?>{
        'reactions': <String>['鼓掌'],
        'reactionList': <Object?>[
          <String, Object?>{'reactionName': '爱心'},
          <String, Object?>{'emoji': '鼓掌'},
        ],
        'reaction': 'OK',
      });

      expect(reactions, <String>['👏', '❤️', '👌']);
    });

    test('忽略互动用户并限制反应类型数量', () {
      final reactions = parseDingTalkMessageReactions(<String, Object?>{
        'emotionReplyList': List<Object?>.generate(
          kDingTalkMaxReactionTypes + 4,
          (index) => <String, Object?>{
            'emoji': '反应$index',
            'replyUsers': <String>['用户$index'],
          },
        ),
      });

      expect(reactions, hasLength(kDingTalkMaxReactionTypes));
      expect(reactions, isNot(contains('用户0')));
    });
  });
}

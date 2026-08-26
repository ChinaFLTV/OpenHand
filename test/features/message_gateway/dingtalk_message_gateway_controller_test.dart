import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/dingtalk_message_gateway_controller.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';

void main() {
  group('钉钉发送回显归属校验', () {
    test('他人媒体消息不能合并为己方回显', () {
      expect(
        canMergeDingTalkOutgoingEcho(
          incomingIsSelf: false,
          unresolvedOutgoing: true,
          sameContent: false,
          sameMedia: true,
        ),
        isFalse,
      );
    });

    test('仅合并当前账号的未解析回显', () {
      expect(
        canMergeDingTalkOutgoingEcho(
          incomingIsSelf: true,
          unresolvedOutgoing: true,
          sameContent: true,
          sameMedia: false,
        ),
        isTrue,
      );
      expect(
        canMergeDingTalkOutgoingEcho(
          incomingIsSelf: true,
          unresolvedOutgoing: false,
          sameContent: true,
          sameMedia: false,
        ),
        isFalse,
      );
    });
  });

  group('钉钉媒体回显匹配', () {
    test('同类型但无稳定证据的媒体不匹配', () {
      expect(
        matchesDingTalkOutgoingMedia(
          const <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: 'local-image',
              kind: DingTalkMediaKind.image,
            ),
          ],
          const <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: 'remote-image',
              kind: DingTalkMediaKind.image,
            ),
          ],
          '[图片]',
        ),
        isFalse,
      );
    });

    test('大小一致的同类型媒体可以匹配', () {
      expect(
        matchesDingTalkOutgoingMedia(
          const <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: 'local-image',
              kind: DingTalkMediaKind.image,
              sizeBytes: 1024,
            ),
          ],
          const <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: 'remote-image',
              kind: DingTalkMediaKind.image,
              sizeBytes: 1024,
            ),
          ],
          '[图片]',
        ),
        isTrue,
      );
    });
  });
}

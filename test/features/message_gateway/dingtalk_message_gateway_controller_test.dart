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

  group('钉钉媒体缓存合并', () {
    test('真实资源重复对账时保留用户已缓存路径', () {
      final merged = mergeDingTalkMediaCache(
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'remote-file-id',
            resourceType: DingTalkMediaResourceType.fileId,
            kind: DingTalkMediaKind.image,
            name: 'cached.png',
            sizeBytes: 2048,
            localPath: '/tmp/cached.png',
          ),
        ],
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'remote-file-id',
            resourceType: DingTalkMediaResourceType.fileId,
            kind: DingTalkMediaKind.image,
            name: 'cached.png',
          ),
        ],
      );

      expect(merged.single.localPath, '/tmp/cached.png');
      expect(merged.single.sizeBytes, 2048);
    });

    test('生成媒体回流为真实资源后保留本地缓存', () {
      final merged = mergeDingTalkMediaCache(
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'assistant-media-1',
            messageId: 'assistant-media-1',
            kind: DingTalkMediaKind.image,
            name: 'generated.png',
            sizeBytes: 2048,
            localPath: '/tmp/generated.png',
          ),
        ],
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'remote-file-id',
            messageId: 'remote-message-id',
            resourceType: DingTalkMediaResourceType.fileId,
            kind: DingTalkMediaKind.image,
            name: 'generated.png',
          ),
        ],
      );

      expect(merged.single.resourceId, 'remote-file-id');
      expect(merged.single.localPath, '/tmp/generated.png');
      expect(merged.single.sizeBytes, 2048);
    });

    test('无可靠匹配证据时不复用其他媒体缓存', () {
      final merged = mergeDingTalkMediaCache(
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'assistant-media-1',
            messageId: 'assistant-media-1',
            kind: DingTalkMediaKind.image,
            name: 'first.png',
            sizeBytes: 2048,
            localPath: '/tmp/first.png',
          ),
        ],
        const <DingTalkGatewayMedia>[
          DingTalkGatewayMedia(
            resourceId: 'remote-file-id',
            messageId: 'remote-message-id',
            resourceType: DingTalkMediaResourceType.fileId,
            kind: DingTalkMediaKind.image,
            name: 'second.png',
            sizeBytes: 4096,
          ),
        ],
      );

      expect(merged.single.localPath, isEmpty);
    });
  });
}

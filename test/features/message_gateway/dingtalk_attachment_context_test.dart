import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/message_gateway/model/dingtalk_message_gateway.dart';
import 'package:openhand/features/message_gateway/service/dingtalk_attachment_context.dart';

void main() {
  DingTalkGatewayMedia media(String id, DingTalkMediaKind kind) =>
      DingTalkGatewayMedia(resourceId: id, kind: kind);
  DingTalkGatewayMessage message(String id, List<DingTalkGatewayMedia> media) =>
      DingTalkGatewayMessage(
        id: id,
        conversationId: 'conversation',
        conversationType: DingTalkConversationType.direct,
        role: DingTalkGatewayMessageRole.user,
        content: '消息',
        createdAt: DateTime.utc(2026),
        media: media,
      );
  test('跨回复轮次选最近五图五文件，当前多附件全部保留', () {
    final messages = [
      for (var i = 0; i < 8; i++)
        message('m$i', [
          media('image$i', DingTalkMediaKind.image),
          media('audio$i', DingTalkMediaKind.audio),
        ]),
      DingTalkGatewayMessage(
        id: 'assistant',
        conversationId: 'conversation',
        conversationType: DingTalkConversationType.direct,
        role: DingTalkGatewayMessageRole.assistant,
        content: '回复',
        createdAt: DateTime.utc(2026),
      ),
      message('latest', [
        for (var i = 0; i < 8; i++) media('current$i', DingTalkMediaKind.file),
      ]),
    ];
    final selected = selectDingTalkContextMedia(messages, 'latest');
    expect(selected.current, hasLength(8));
    expect(selected.history.map((a) => a.media.resourceId), [
      for (var i = 3; i < 8; i++) ...['image$i', 'audio$i'],
    ]);
  });
  test('过滤撤回、忽略、失败及被引用的已排除消息；当前引用优先去重', () {
    final shared = media('shared', DingTalkMediaKind.audio);
    final recalled = media('recalled', DingTalkMediaKind.image);
    final messages = [
      message('old', [shared]),
      message('recalled', [recalled]).copyWith(recalled: true),
      message('ignored', [
        media('ignored', DingTalkMediaKind.audio),
      ]).copyWith(ignoredForAiContext: true),
      message('failed', [
        media('failed', DingTalkMediaKind.file),
      ]).copyWith(aiResponseState: DingTalkMessageAiResponseState.failed),
      message('quote-recalled', []).copyWith(
        quotedMessage: DingTalkQuotedMessage(
          id: 'recalled',
          content: '',
          createdAt: DateTime.utc(2026),
          media: [recalled],
        ),
      ),
      message('latest', []).copyWith(
        quotedMessage: DingTalkQuotedMessage(
          id: 'old',
          content: '',
          createdAt: DateTime.utc(2026),
          media: [shared],
        ),
      ),
    ];
    final selected = selectDingTalkContextMedia(messages, 'latest');
    expect(selected.history, isEmpty);
    expect(selected.current.single.media.resourceId, 'shared');
    expect(selected.current.single.sourceMessageId, 'old');
    expect(selectDingTalkContextMedia(messages, 'missing').current, isEmpty);
  });

  test('上下文快照不包含响应期间后到的附件', () {
    final messages = [
      message('earlier', [media('earlier-file', DingTalkMediaKind.file)]),
      message('source', [media('source-file', DingTalkMediaKind.file)]),
      message('later', [media('later-file', DingTalkMediaKind.file)]),
    ];

    final selected = selectDingTalkContextMedia(
      messages,
      'source',
      contextMessageIds: ['earlier', 'source'],
    );

    expect(selected.current.single.media.resourceId, 'source-file');
    expect(selected.history.single.media.resourceId, 'earlier-file');
  });
}

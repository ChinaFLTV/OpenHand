import '../../ai/index.dart' show selectAiHistoricalAttachments;
import '../model/dingtalk_message_gateway.dart';

typedef DingTalkContextMedia = ({
  DingTalkGatewayMedia media,
  String ownerMessageId,
  String sourceMessageId,
});

bool isDingTalkSkippedAiResponse(DingTalkGatewayMessage message) =>
    switch (message.aiResponseState) {
      DingTalkMessageAiResponseState.rejected ||
      DingTalkMessageAiResponseState.dropped ||
      DingTalkMessageAiResponseState.cancelled ||
      DingTalkMessageAiResponseState.failed => true,
      _ => false,
    };

({List<DingTalkContextMedia> current, List<DingTalkContextMedia> history})
selectDingTalkContextMedia(
  List<DingTalkGatewayMessage> messages,
  String sourceMessageId, {
  Iterable<String>? contextMessageIds,
}) {
  final contextIds = contextMessageIds
      ?.map(normalizeDingTalkMessageId)
      .where((id) => id.isNotEmpty)
      .toSet();
  final scopedMessages = contextIds == null
      ? messages
      : messages
            .where(
              (message) =>
                  contextIds.contains(normalizeDingTalkMessageId(message.id)),
            )
            .toList(growable: false);
  final end = scopedMessages.indexWhere((m) => m.id == sourceMessageId);
  if (end < 0) return (current: [], history: []);
  final excluded = scopedMessages
      .where((m) => m.isExcludedFromAiContext || isDingTalkSkippedAiResponse(m))
      .map((m) => normalizeDingTalkMessageId(m.id))
      .toSet();
  Iterable<DingTalkContextMedia> mediaFor(
    DingTalkGatewayMessage message,
  ) sync* {
    if (message.role != DingTalkGatewayMessageRole.user ||
        excluded.contains(normalizeDingTalkMessageId(message.id))) {
      return;
    }
    for (final media in message.media) {
      yield (
        media: media,
        ownerMessageId: message.id,
        sourceMessageId: message.id,
      );
    }
    final quoted = message.quotedMessage;
    if (quoted != null &&
        !excluded.contains(normalizeDingTalkMessageId(quoted.id))) {
      for (final media in quoted.media) {
        yield (
          media: media,
          ownerMessageId: message.id,
          sourceMessageId: quoted.id.isEmpty ? message.id : quoted.id,
        );
      }
    }
  }

  String identity(DingTalkContextMedia item) =>
      '${item.media.resourceType.name}:${item.media.resourceId}';
  final seen = <String>{};
  final current = mediaFor(
    scopedMessages[end],
  ).where((m) => seen.add(identity(m))).toList();
  final history = selectAiHistoricalAttachments(
    newestFirst: scopedMessages
        .take(end)
        .toList()
        .reversed
        .expand((m) => mediaFor(m).toList().reversed),
    currentKeys: current.map(identity),
    keyOf: identity,
    isImage: (m) => m.media.kind == DingTalkMediaKind.image,
  ).reversed.toList();
  return (current: current, history: history);
}

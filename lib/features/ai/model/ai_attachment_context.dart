import 'dart:convert';

import 'ai_attachment.dart';
import 'ai_session_message.dart';

const int aiHistoryImageAttachmentLimit = 5;
const int aiHistoryResourceAttachmentLimit = 5;
const String aiHistoricalAttachmentsMetadataKey = 'historical_attachments';
const aiAttachmentMetadataKeys = [
  aiSessionMessageAttachmentsMetadataKey,
  aiHistoricalAttachmentsMetadataKey,
];

/// 调用方提供的完整附件快照；历史资源与本条消息分别导入和计数。
class AiAttachmentContextInput {
  const AiAttachmentContextInput({
    required this.current,
    required this.history,
  });

  final List<AiAttachmentSource> current;
  final List<AiAttachmentSource> history;
}

class AiAttachmentSource {
  const AiAttachmentSource({
    required this.path,
    required this.name,
    required this.messageId,
  });

  final String path;
  final String name;
  final String messageId;
}

/// 按近到远输入，当前资源优先去重；两类历史配额互不占用。
List<T> selectAiHistoricalAttachments<T>({
  required Iterable<T> newestFirst,
  required Iterable<String> currentKeys,
  required String Function(T) keyOf,
  required bool Function(T) isImage,
}) {
  final seen = currentKeys.toSet();
  final selected = <T>[];
  var images = 0;
  var resources = 0;
  for (final item in newestFirst) {
    final image = isImage(item);
    if ((image && images >= aiHistoryImageAttachmentLimit) ||
        (!image && resources >= aiHistoryResourceAttachmentLimit)) {
      continue;
    }
    if (!seen.add(keyOf(item))) continue;
    selected.add(item);
    if (image) {
      images++;
    } else {
      resources++;
    }
    if (images >= aiHistoryImageAttachmentLimit &&
        resources >= aiHistoryResourceAttachmentLimit) {
      break;
    }
  }
  return selected;
}

class AiContextAttachment {
  const AiContextAttachment(this.attachment, this.messageId, this.isHistorical);

  final AiMessageAttachment attachment;
  final String messageId;
  final bool isHistorical;

  String get identity =>
      attachment.originalSourcePath ?? attachment.storagePath;

  String get label =>
      '[${isHistorical ? '历史附件' : '当前附件'}] '
      '${jsonEncode({'message_id': messageId, 'id': attachment.id, 'name': attachment.name, 'type': attachment.kind.storageValue, 'path': attachment.storagePath})}';
}

Map<String, List<AiContextAttachment>> selectAiSessionAttachments(
  List<AiSessionMessage> messages,
  AiSessionMessage? latest,
) {
  List<AiContextAttachment> read(
    AiSessionMessage message,
    bool historical, [
    String key = aiSessionMessageAttachmentsMetadataKey,
  ]) => AiMessageAttachment.listFromMetadata(message.metadata[key])
      .map(
        (a) => AiContextAttachment(
          a,
          a.sourceMessageId.isEmpty ? message.id : a.sourceMessageId,
          historical,
        ),
      )
      .toList();

  final current = latest == null
      ? <AiContextAttachment>[]
      : read(latest, false);
  final result = <String, List<AiContextAttachment>>{
    if (latest != null) latest.id: current,
  };
  // 网关快照已经过滤撤回和忽略消息，不能从旧轮次重新补入资源。
  if (latest != null &&
      latest.metadata.containsKey(aiHistoricalAttachmentsMetadataKey)) {
    result[latest.id] = [
      ...current,
      ...selectAiHistoricalAttachments(
        newestFirst: read(
          latest,
          true,
          aiHistoricalAttachmentsMetadataKey,
        ).reversed,
        currentKeys: current.map((a) => a.identity),
        keyOf: (a) => a.identity,
        isImage: (a) => a.attachment.isImage,
      ).reversed,
    ];
    return result;
  }
  final latestIndex = messages.indexWhere(
    (message) => message.id == latest?.id,
  );
  Iterable<(String, AiContextAttachment)> history() sync* {
    for (
      var index = (latestIndex < 0 ? messages.length : latestIndex) - 1;
      index >= 0;
      index--
    ) {
      final message = messages[index];
      if (message.id == latest?.id ||
          message.isDeleted ||
          message.kind != AiSessionMessageKind.user) {
        continue;
      }
      for (final item in read(message, true).reversed) {
        yield (message.id, item);
      }
    }
  }

  final selected = selectAiHistoricalAttachments(
    newestFirst: history(),
    currentKeys: current.map((a) => a.identity),
    keyOf: (a) => a.$2.identity,
    isImage: (a) => a.$2.attachment.isImage,
  );
  for (final item in selected.reversed) {
    result.putIfAbsent(item.$1, () => []).add(item.$2);
  }
  return result;
}

import '../model/knowledge_message_metadata.dart';

class KnowledgePromptAugmenter {
  const KnowledgePromptAugmenter();

  String appendFromMetadata({
    required String userContent,
    required Map<String, Object?> messageMetadata,
  }) {
    final kb = KnowledgeMessageMetadata.object(
      messageMetadata[knowledgeBaseMessageMetadataKey],
    );
    if (kb == null) return userContent.trim();
    final append = '${kb[knowledgeBasePromptAppendMetadataKey] ?? ''}'.trim();
    if (append.isEmpty) return userContent.trim();
    final base = userContent.trim();
    return base.isEmpty ? append : '$base\n\n$append';
  }
}

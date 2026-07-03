import '../../../shared/util/input_value_parsing.dart';
import 'ai_api_family.dart';

class AiOperationRouting {
  const AiOperationRouting({
    this.chatModelId,
    this.responsesModelId,
    this.completionModelId,
    this.embeddingModelId,
    this.moderationModelId,
    this.rerankModelId,
    this.imageModelId,
    this.imageEditModelId,
    this.videoModelId,
    this.speechModelId,
    this.transcriptionModelId,
    this.translationModelId,
    this.realtimeModelId,
    this.defaultVoice,
  });

  final String? chatModelId;
  final String? responsesModelId;
  final String? completionModelId;
  final String? embeddingModelId;
  final String? moderationModelId;
  final String? rerankModelId;
  final String? imageModelId;
  final String? imageEditModelId;
  final String? videoModelId;
  final String? speechModelId;
  final String? transcriptionModelId;
  final String? translationModelId;
  final String? realtimeModelId;
  final String? defaultVoice;

  bool get isEmpty =>
      _isBlank(chatModelId) &&
      _isBlank(responsesModelId) &&
      _isBlank(completionModelId) &&
      _isBlank(embeddingModelId) &&
      _isBlank(moderationModelId) &&
      _isBlank(rerankModelId) &&
      _isBlank(imageModelId) &&
      _isBlank(imageEditModelId) &&
      _isBlank(videoModelId) &&
      _isBlank(speechModelId) &&
      _isBlank(transcriptionModelId) &&
      _isBlank(translationModelId) &&
      _isBlank(realtimeModelId) &&
      _isBlank(defaultVoice);

  String? resolveModelId(AiApiFamily family, String fallbackModelId) {
    final resolved = switch (family) {
      AiApiFamily.responses => responsesModelId,
      AiApiFamily.chatCompletions => chatModelId,
      AiApiFamily.completions => completionModelId,
      AiApiFamily.embeddings => embeddingModelId,
      AiApiFamily.moderations => moderationModelId,
      AiApiFamily.rerank => rerankModelId,
      AiApiFamily.imageGeneration => imageModelId,
      AiApiFamily.imageEdit => imageEditModelId,
      AiApiFamily.audioSpeech => speechModelId,
      AiApiFamily.audioTranscription => transcriptionModelId,
      AiApiFamily.audioTranslation => translationModelId,
      AiApiFamily.videoGeneration => videoModelId,
      AiApiFamily.realtime => realtimeModelId,
      AiApiFamily.models ||
      AiApiFamily.files ||
      AiApiFamily.fineTunes ||
      AiApiFamily.vectorStores ||
      AiApiFamily.vectorStoreFiles ||
      AiApiFamily.tokenCount ||
      AiApiFamily.search ||
      AiApiFamily.audioVoices ||
      AiApiFamily.audioSystemVoices ||
      AiApiFamily.audioVoicePreview ||
      AiApiFamily.audioAsr ||
      AiApiFamily.audioAsrSse ||
      AiApiFamily.messages => null,
    };
    return nullIfBlank(resolved) ?? fallbackModelId.trim();
  }

  AiOperationRouting copyWith({
    String? chatModelId,
    String? responsesModelId,
    String? completionModelId,
    String? embeddingModelId,
    String? moderationModelId,
    String? rerankModelId,
    String? imageModelId,
    String? imageEditModelId,
    String? videoModelId,
    String? speechModelId,
    String? transcriptionModelId,
    String? translationModelId,
    String? realtimeModelId,
    String? defaultVoice,
    bool clearChatModelId = false,
    bool clearResponsesModelId = false,
    bool clearCompletionModelId = false,
    bool clearEmbeddingModelId = false,
    bool clearModerationModelId = false,
    bool clearRerankModelId = false,
    bool clearImageModelId = false,
    bool clearImageEditModelId = false,
    bool clearVideoModelId = false,
    bool clearSpeechModelId = false,
    bool clearTranscriptionModelId = false,
    bool clearTranslationModelId = false,
    bool clearRealtimeModelId = false,
    bool clearDefaultVoice = false,
  }) {
    return AiOperationRouting(
      chatModelId: clearChatModelId ? null : (chatModelId ?? this.chatModelId),
      responsesModelId: clearResponsesModelId
          ? null
          : (responsesModelId ?? this.responsesModelId),
      completionModelId: clearCompletionModelId
          ? null
          : (completionModelId ?? this.completionModelId),
      embeddingModelId: clearEmbeddingModelId
          ? null
          : (embeddingModelId ?? this.embeddingModelId),
      moderationModelId: clearModerationModelId
          ? null
          : (moderationModelId ?? this.moderationModelId),
      rerankModelId: clearRerankModelId
          ? null
          : (rerankModelId ?? this.rerankModelId),
      imageModelId: clearImageModelId
          ? null
          : (imageModelId ?? this.imageModelId),
      imageEditModelId: clearImageEditModelId
          ? null
          : (imageEditModelId ?? this.imageEditModelId),
      videoModelId: clearVideoModelId
          ? null
          : (videoModelId ?? this.videoModelId),
      speechModelId: clearSpeechModelId
          ? null
          : (speechModelId ?? this.speechModelId),
      transcriptionModelId: clearTranscriptionModelId
          ? null
          : (transcriptionModelId ?? this.transcriptionModelId),
      translationModelId: clearTranslationModelId
          ? null
          : (translationModelId ?? this.translationModelId),
      realtimeModelId: clearRealtimeModelId
          ? null
          : (realtimeModelId ?? this.realtimeModelId),
      defaultVoice: clearDefaultVoice
          ? null
          : (defaultVoice ?? this.defaultVoice),
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    putIfNotBlank(json, 'chat_model_id', chatModelId);
    putIfNotBlank(json, 'responses_model_id', responsesModelId);
    putIfNotBlank(json, 'completion_model_id', completionModelId);
    putIfNotBlank(json, 'embedding_model_id', embeddingModelId);
    putIfNotBlank(json, 'moderation_model_id', moderationModelId);
    putIfNotBlank(json, 'rerank_model_id', rerankModelId);
    putIfNotBlank(json, 'image_model_id', imageModelId);
    putIfNotBlank(json, 'image_edit_model_id', imageEditModelId);
    putIfNotBlank(json, 'video_model_id', videoModelId);
    putIfNotBlank(json, 'speech_model_id', speechModelId);
    putIfNotBlank(json, 'transcription_model_id', transcriptionModelId);
    putIfNotBlank(json, 'translation_model_id', translationModelId);
    putIfNotBlank(json, 'realtime_model_id', realtimeModelId);
    putIfNotBlank(json, 'default_voice', defaultVoice);
    return json;
  }

  static AiOperationRouting? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    return AiOperationRouting(
      chatModelId: optionalStringFromValue(json['chat_model_id']),
      responsesModelId: optionalStringFromValue(json['responses_model_id']),
      completionModelId: optionalStringFromValue(json['completion_model_id']),
      embeddingModelId: optionalStringFromValue(json['embedding_model_id']),
      moderationModelId: optionalStringFromValue(json['moderation_model_id']),
      rerankModelId: optionalStringFromValue(json['rerank_model_id']),
      imageModelId: optionalStringFromValue(json['image_model_id']),
      imageEditModelId: optionalStringFromValue(json['image_edit_model_id']),
      videoModelId: optionalStringFromValue(json['video_model_id']),
      speechModelId: optionalStringFromValue(json['speech_model_id']),
      transcriptionModelId: optionalStringFromValue(
        json['transcription_model_id'],
      ),
      translationModelId: optionalStringFromValue(json['translation_model_id']),
      realtimeModelId: optionalStringFromValue(json['realtime_model_id']),
      defaultVoice: optionalStringFromValue(json['default_voice']),
    );
  }

  static bool _isBlank(String? value) => nullIfBlank(value) == null;
}

import 'dart:convert';

import '../../../app/support/silent_log.dart';
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
      AiApiFamily.models || AiApiFamily.files || AiApiFamily.fineTunes => null,
    };
    final trimmed = resolved?.trim() ?? '';
    return trimmed.isEmpty ? fallbackModelId.trim() : trimmed;
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
    return <String, Object?>{
      if (!_isBlank(chatModelId)) 'chat_model_id': chatModelId,
      if (!_isBlank(responsesModelId)) 'responses_model_id': responsesModelId,
      if (!_isBlank(completionModelId))
        'completion_model_id': completionModelId,
      if (!_isBlank(embeddingModelId)) 'embedding_model_id': embeddingModelId,
      if (!_isBlank(moderationModelId))
        'moderation_model_id': moderationModelId,
      if (!_isBlank(rerankModelId)) 'rerank_model_id': rerankModelId,
      if (!_isBlank(imageModelId)) 'image_model_id': imageModelId,
      if (!_isBlank(imageEditModelId))
        'image_edit_model_id': imageEditModelId,
      if (!_isBlank(videoModelId)) 'video_model_id': videoModelId,
      if (!_isBlank(speechModelId)) 'speech_model_id': speechModelId,
      if (!_isBlank(transcriptionModelId))
        'transcription_model_id': transcriptionModelId,
      if (!_isBlank(translationModelId))
        'translation_model_id': translationModelId,
      if (!_isBlank(realtimeModelId)) 'realtime_model_id': realtimeModelId,
      if (!_isBlank(defaultVoice)) 'default_voice': defaultVoice,
    };
  }

  static AiOperationRouting? fromJson(Object? raw) {
    Map<String, Object?>? json;
    if (raw is Map) {
      json = Map<String, Object?>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          json = Map<String, Object?>.from(decoded);
        }
      } catch (error, stack) {
        silentLog('ai_operation_routing', 'decode JSON string', error, stack);
      }
    }
    if (json == null) return null;
    return AiOperationRouting(
      chatModelId: _parseString(json['chat_model_id']),
      responsesModelId: _parseString(json['responses_model_id']),
      completionModelId: _parseString(json['completion_model_id']),
      embeddingModelId: _parseString(json['embedding_model_id']),
      moderationModelId: _parseString(json['moderation_model_id']),
      rerankModelId: _parseString(json['rerank_model_id']),
      imageModelId: _parseString(json['image_model_id']),
      imageEditModelId: _parseString(json['image_edit_model_id']),
      videoModelId: _parseString(json['video_model_id']),
      speechModelId: _parseString(json['speech_model_id']),
      transcriptionModelId: _parseString(json['transcription_model_id']),
      translationModelId: _parseString(json['translation_model_id']),
      realtimeModelId: _parseString(json['realtime_model_id']),
      defaultVoice: _parseString(json['default_voice']),
    );
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  static String? _parseString(Object? raw) {
    final trimmed = '${raw ?? ''}'.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

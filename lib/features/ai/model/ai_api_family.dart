enum AiApiFamily {
  responses('responses'),
  chatCompletions('chat_completions'),
  completions('completions'),
  embeddings('embeddings'),
  moderations('moderations'),
  rerank('rerank'),
  models('models'),
  imageGeneration('image_generation'),
  imageEdit('image_edit'),
  audioSpeech('audio_speech'),
  audioTranscription('audio_transcription'),
  audioTranslation('audio_translation'),
  videoGeneration('video_generation'),
  realtime('realtime'),
  files('files'),
  fineTunes('fine_tunes');

  const AiApiFamily(this.storageValue);

  final String storageValue;

  static AiApiFamily? fromStorage(String? value) {
    if (value == null) return null;
    for (final family in AiApiFamily.values) {
      if (family.storageValue == value) return family;
    }
    return null;
  }
}

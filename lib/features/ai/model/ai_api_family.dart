import '../../../shared/util/input_value_parsing.dart';

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
  fineTunes('fine_tunes'),
  vectorStores('vector_stores'),
  vectorStoreFiles('vector_store_files'),
  tokenCount('token_count'),
  search('search'),
  audioVoices('audio_voices'),
  audioSystemVoices('audio_system_voices'),
  audioVoicePreview('audio_voice_preview'),
  audioAsr('audio_asr'),
  audioAsrSse('audio_asr_sse'),
  messages('messages');

  const AiApiFamily(this.storageValue);

  final String storageValue;

  static AiApiFamily? fromStorage(String? value) {
    return enumByStorageValue(values, value, (family) => family.storageValue);
  }
}

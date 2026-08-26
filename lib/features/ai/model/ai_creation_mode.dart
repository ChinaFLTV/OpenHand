/// Structured representation of a user-requested generative creation action
/// (e.g. image / video / audio / deep-research) initiated from the composer.
///
/// Centralising this data structure means every layer of the app — composer
/// UI, session controller, protocol adapter, message renderer and audit
/// surface — speaks the same vocabulary when describing a non-text request.
/// It also gives us a single place to attach per-provider routing hints and
/// to evolve future fields (size, aspect ratio, resolution, duration, …)
/// without breaking callers.
library;

import '../../../shared/util/input_value_parsing.dart';

enum AiCreationMode {
  none('none'),
  image('image'),
  video('video'),
  audio('audio'),
  deepResearch('deep_research');

  const AiCreationMode(this.storageValue);

  final String storageValue;

  bool get isActive => this != AiCreationMode.none;

  static AiCreationMode fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: AiCreationMode.none,
    );
  }
}

/// User-chosen options for a creation request. All fields are optional; the
/// adapter layer applies safe provider defaults when a value is absent.
class AiCreationOptions {
  const AiCreationOptions({
    this.size,
    this.aspectRatio,
    this.durationSeconds,
    this.count = defaultCount,
    this.quality,
    this.style,
    this.outputFormat,
    this.background,
    this.negativePrompt,
    this.promptEnhance,
    this.watermark,
    this.seed,
    this.resolution,
    this.frameRate,
    this.numFrames,
    this.mode,
    this.voice,
    this.omitVoice = false,
    this.speed,
    this.sampleRate,
    this.bitrate,
    this.volume,
    this.pitch,
    this.languageBoost,
    this.emotion,
    this.textNormalization,
    this.latexRead,
    this.channel,
    this.forceCbr,
    this.subtitleEnable,
    this.subtitleType,
    this.pronunciationTone = const <String>[],
    this.timbreWeights = const <Map<String, Object?>>[],
    this.voiceModify = const <String, Object?>{},
  });

  /// e.g. `"1024x1024"`, `"1024x1792"`. Leave `null` to let the provider pick.
  final String? size;

  /// e.g. `"1:1"`, `"16:9"`, `"9:16"`, `"4:3"`.
  final String? aspectRatio;

  /// Video/audio clip duration in seconds.
  final int? durationSeconds;

  /// Number of outputs to request (n).
  final int count;

  /// Provider-specific quality hint (e.g. `"standard"`, `"hd"`).
  final String? quality;

  /// Provider-specific style hint (e.g. `"vivid"`, `"natural"`).
  final String? style;

  /// Output container/codec hint (e.g. `"png"`, `"webp"`, `"mp3"`).
  final String? outputFormat;

  /// Image background hint (e.g. `"auto"`, `"transparent"`, `"opaque"`).
  final String? background;

  /// Negative prompt for providers that expose explicit avoidance guidance.
  final String? negativePrompt;

  /// Provider prompt rewriting flag (`prompt_extend` / `prompt_optimizer`).
  final bool? promptEnhance;

  /// Whether provider-side watermarking should be enabled.
  final bool? watermark;

  /// Deterministic generation seed where supported.
  final int? seed;

  /// Resolution preset for video providers (e.g. `"480p"`, `"720p"`).
  final String? resolution;

  /// Requested video frame rate.
  final int? frameRate;

  /// Requested video frame count.
  final int? numFrames;

  /// Provider-specific generation mode (e.g. `"keyframes"`).
  final String? mode;

  /// TTS voice identifier.
  final String? voice;

  /// 用户明确要求请求中不携带音色参数。
  final bool omitVoice;

  /// TTS speed multiplier.
  final double? speed;

  /// Audio sample rate in Hz.
  final int? sampleRate;

  /// Audio bitrate in bps.
  final int? bitrate;

  /// Audio volume multiplier where supported.
  final double? volume;

  /// Audio pitch offset where supported.
  final double? pitch;

  /// MiniMax language/dialect boost (`Chinese`, `English`, `auto`, ...).
  final String? languageBoost;

  /// Provider-supported speech emotion.
  final String? emotion;

  final bool? textNormalization;
  final bool? latexRead;
  final int? channel;
  final bool? forceCbr;
  final bool? subtitleEnable;
  final String? subtitleType;
  final List<String> pronunciationTone;
  final List<Map<String, Object?>> timbreWeights;
  final Map<String, Object?> voiceModify;

  static const AiCreationOptions empty = AiCreationOptions();

  AiCreationOptions copyWith({
    String? size,
    String? aspectRatio,
    int? durationSeconds,
    int? count,
    String? quality,
    String? style,
    String? outputFormat,
    String? background,
    String? negativePrompt,
    bool? promptEnhance,
    bool? watermark,
    int? seed,
    String? resolution,
    int? frameRate,
    int? numFrames,
    String? mode,
    String? voice,
    bool? omitVoice,
    double? speed,
    int? sampleRate,
    int? bitrate,
    double? volume,
    double? pitch,
    String? languageBoost,
    String? emotion,
    bool? textNormalization,
    bool? latexRead,
    int? channel,
    bool? forceCbr,
    bool? subtitleEnable,
    String? subtitleType,
    List<String>? pronunciationTone,
    List<Map<String, Object?>>? timbreWeights,
    Map<String, Object?>? voiceModify,
  }) {
    final resolvedOmitVoice = omitVoice ?? this.omitVoice;
    return AiCreationOptions(
      size: size ?? this.size,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      durationSeconds: normalizeDurationSeconds(
        durationSeconds ?? this.durationSeconds,
      ),
      count: normalizeCount(count ?? this.count),
      quality: quality ?? this.quality,
      style: style ?? this.style,
      outputFormat: outputFormat ?? this.outputFormat,
      background: background ?? this.background,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      promptEnhance: promptEnhance ?? this.promptEnhance,
      watermark: watermark ?? this.watermark,
      seed: seed ?? this.seed,
      resolution: resolution ?? this.resolution,
      frameRate: normalizeFrameRate(frameRate ?? this.frameRate),
      numFrames: normalizeNumFrames(numFrames ?? this.numFrames),
      mode: mode ?? this.mode,
      voice: resolvedOmitVoice ? null : voice ?? this.voice,
      omitVoice: resolvedOmitVoice,
      speed: normalizeSpeed(speed ?? this.speed),
      sampleRate: normalizeSampleRate(sampleRate ?? this.sampleRate),
      bitrate: normalizeBitrate(bitrate ?? this.bitrate),
      volume: normalizeVolume(volume ?? this.volume),
      pitch: normalizePitch(pitch ?? this.pitch),
      languageBoost: languageBoost ?? this.languageBoost,
      emotion: emotion ?? this.emotion,
      textNormalization: textNormalization ?? this.textNormalization,
      latexRead: latexRead ?? this.latexRead,
      channel: channel ?? this.channel,
      forceCbr: forceCbr ?? this.forceCbr,
      subtitleEnable: subtitleEnable ?? this.subtitleEnable,
      subtitleType: subtitleType ?? this.subtitleType,
      pronunciationTone: pronunciationTone ?? this.pronunciationTone,
      timbreWeights: timbreWeights ?? this.timbreWeights,
      voiceModify: voiceModify ?? this.voiceModify,
    );
  }

  bool get hasExplicitOptions => toMetadata().isNotEmpty;

  Map<String, Object?> toMetadata() {
    final normalizedDurationSeconds = normalizeDurationSeconds(durationSeconds);
    final normalizedCount = normalizeCount(count);
    final normalizedFrameRate = normalizeFrameRate(frameRate);
    final normalizedNumFrames = normalizeNumFrames(numFrames);
    final normalizedSpeed = normalizeSpeed(speed);
    final normalizedSampleRate = normalizeSampleRate(sampleRate);
    final normalizedBitrate = normalizeBitrate(bitrate);
    final normalizedVolume = normalizeVolume(volume);
    final normalizedPitch = normalizePitch(pitch);
    return <String, Object?>{
      if (size != null) 'size': size,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (normalizedDurationSeconds != null)
        'duration_seconds': normalizedDurationSeconds,
      if (normalizedCount != defaultCount) 'count': normalizedCount,
      if (quality != null) 'quality': quality,
      if (style != null) 'style': style,
      if (outputFormat != null) 'output_format': outputFormat,
      if (background != null) 'background': background,
      if (negativePrompt != null) 'negative_prompt': negativePrompt,
      if (promptEnhance != null) 'prompt_enhance': promptEnhance,
      if (watermark != null) 'watermark': watermark,
      if (seed != null) 'seed': seed,
      if (resolution != null) 'resolution': resolution,
      if (normalizedFrameRate != null) 'frame_rate': normalizedFrameRate,
      if (normalizedNumFrames != null) 'num_frames': normalizedNumFrames,
      if (mode != null) 'mode': mode,
      if (!omitVoice && voice != null) 'voice': voice,
      if (omitVoice) 'omit_voice': true,
      if (normalizedSpeed != null) 'speed': normalizedSpeed,
      if (normalizedSampleRate != null) 'sample_rate': normalizedSampleRate,
      if (normalizedBitrate != null) 'bitrate': normalizedBitrate,
      if (normalizedVolume != null) 'volume': normalizedVolume,
      if (normalizedPitch != null) 'pitch': normalizedPitch,
      if (languageBoost != null) 'language_boost': languageBoost,
      if (emotion != null) 'emotion': emotion,
      if (textNormalization != null) 'text_normalization': textNormalization,
      if (latexRead != null) 'latex_read': latexRead,
      if (channel != null) 'channel': channel,
      if (forceCbr != null) 'force_cbr': forceCbr,
      if (subtitleEnable != null) 'subtitle_enable': subtitleEnable,
      if (subtitleType != null) 'subtitle_type': subtitleType,
      if (pronunciationTone.isNotEmpty) 'pronunciation_tone': pronunciationTone,
      if (timbreWeights.isNotEmpty) 'timbre_weights': timbreWeights,
      if (voiceModify.isNotEmpty) 'voice_modify': voiceModify,
    };
  }

  static AiCreationOptions fromMetadata(Object? raw) {
    final map = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (map == null) return AiCreationOptions.empty;
    final omitVoice = optionalBoolFromValue(map['omit_voice']) ?? false;
    return AiCreationOptions(
      size: optionalStringFromValue(map['size']),
      aspectRatio: optionalStringFromValue(map['aspect_ratio']),
      durationSeconds: durationSecondsFromValue(map['duration_seconds']),
      count: countFromValue(map['count']),
      quality: optionalStringFromValue(map['quality']),
      style: optionalStringFromValue(map['style']),
      outputFormat: optionalStringFromValue(map['output_format']),
      background: optionalStringFromValue(map['background']),
      negativePrompt: optionalStringFromValue(map['negative_prompt']),
      promptEnhance:
          optionalBoolFromValue(map['prompt_enhance']) ??
          optionalBoolFromValue(map['prompt_extend']) ??
          optionalBoolFromValue(map['prompt_optimizer']),
      watermark: optionalBoolFromValue(map['watermark']),
      seed: optionalPositiveIntFromValue(map['seed']),
      resolution:
          optionalStringFromValue(map['resolution']) ??
          optionalStringFromValue(map['resolution_name']),
      frameRate:
          frameRateFromValue(map['frame_rate']) ??
          frameRateFromValue(map['fps']),
      numFrames: numFramesFromValue(map['num_frames']),
      mode: optionalStringFromValue(map['mode']),
      voice: omitVoice ? null : optionalStringFromValue(map['voice']),
      omitVoice: omitVoice,
      speed: speedFromValue(map['speed']),
      sampleRate: sampleRateFromValue(map['sample_rate']),
      bitrate: bitrateFromValue(map['bitrate']),
      volume: volumeFromValue(map['volume']) ?? volumeFromValue(map['vol']),
      pitch: pitchFromValue(map['pitch']),
      languageBoost: optionalStringFromValue(map['language_boost']),
      emotion: optionalStringFromValue(map['emotion']),
      textNormalization: optionalBoolFromValue(map['text_normalization']),
      latexRead: optionalBoolFromValue(map['latex_read']),
      channel: optionalPositiveIntFromValue(map['channel']),
      forceCbr: optionalBoolFromValue(map['force_cbr']),
      subtitleEnable: optionalBoolFromValue(map['subtitle_enable']),
      subtitleType: optionalStringFromValue(map['subtitle_type']),
      pronunciationTone: stringListFromListValue(map['pronunciation_tone']),
      timbreWeights: map['timbre_weights'] is List
          ? (map['timbre_weights'] as List)
                .whereType<Map>()
                .map(stringKeyedMapFromValue)
                .toList(growable: false)
          : const <Map<String, Object?>>[],
      voiceModify: map['voice_modify'] is Map
          ? stringKeyedMapFromValue(map['voice_modify'])
          : const <String, Object?>{},
    );
  }

  static const int defaultCount = 1;
  static const int minCount = 1;
  static const int maxCount = 4;
  static const int minDurationSeconds = 1;
  static const int maxDurationSeconds = 600;
  static const int minFrameRate = 1;
  static const int maxFrameRate = 60;
  static const int minNumFrames = 1;
  static const int maxNumFrames = 441;
  static const int minSampleRate = 8000;
  static const int maxSampleRate = 96000;
  static const int minBitrate = 8000;
  static const int maxBitrate = 512000;
  static const double defaultSpeed = 1.0;
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;
  static const double defaultVolume = 1.0;
  static const double minVolume = 0.0;
  static const double maxVolume = 10.0;
  static const double defaultPitch = 0.0;
  static const double minPitch = -20.0;
  static const double maxPitch = 20.0;

  static const IntValueRange _countRange = IntValueRange(
    fallback: defaultCount,
    min: minCount,
    max: maxCount,
  );
  static const IntValueRange _durationSecondsRange = IntValueRange(
    fallback: minDurationSeconds,
    min: minDurationSeconds,
    max: maxDurationSeconds,
  );
  static const IntValueRange _frameRateRange = IntValueRange(
    fallback: minFrameRate,
    min: minFrameRate,
    max: maxFrameRate,
  );
  static const IntValueRange _numFramesRange = IntValueRange(
    fallback: minNumFrames,
    min: minNumFrames,
    max: maxNumFrames,
  );
  static const IntValueRange _sampleRateRange = IntValueRange(
    fallback: minSampleRate,
    min: minSampleRate,
    max: maxSampleRate,
  );
  static const IntValueRange _bitrateRange = IntValueRange(
    fallback: minBitrate,
    min: minBitrate,
    max: maxBitrate,
  );
  static const DoubleValueRange _speedRange = DoubleValueRange(
    fallback: defaultSpeed,
    min: minSpeed,
    max: maxSpeed,
  );
  static const DoubleValueRange _volumeRange = DoubleValueRange(
    fallback: defaultVolume,
    min: minVolume,
    max: maxVolume,
  );
  static const DoubleValueRange _pitchRange = DoubleValueRange(
    fallback: defaultPitch,
    min: minPitch,
    max: maxPitch,
  );

  static int countFromValue(Object? value) => _countRange.fromValue(value);

  static int normalizeCount(int value) => _countRange.normalize(value);

  static int? durationSecondsFromValue(Object? value) {
    return _positiveIntInRangeFromValue(value, _durationSecondsRange);
  }

  static int? normalizeDurationSeconds(int? value) {
    return _positiveIntInRange(value, _durationSecondsRange);
  }

  static int? frameRateFromValue(Object? value) {
    return _positiveIntInRangeFromValue(value, _frameRateRange);
  }

  static int? normalizeFrameRate(int? value) {
    return _positiveIntInRange(value, _frameRateRange);
  }

  static int? numFramesFromValue(Object? value) {
    return _positiveIntInRangeFromValue(value, _numFramesRange);
  }

  static int? normalizeNumFrames(int? value) {
    return _positiveIntInRange(value, _numFramesRange);
  }

  static int? sampleRateFromValue(Object? value) {
    return _positiveIntInRangeFromValue(value, _sampleRateRange);
  }

  static int? normalizeSampleRate(int? value) {
    return _positiveIntInRange(value, _sampleRateRange);
  }

  static int? bitrateFromValue(Object? value) {
    return _positiveIntInRangeFromValue(value, _bitrateRange);
  }

  static int? normalizeBitrate(int? value) {
    return _positiveIntInRange(value, _bitrateRange);
  }

  static double? speedFromValue(Object? value) {
    return _doubleInRangeFromValue(value, _speedRange);
  }

  static double? normalizeSpeed(double? value) {
    return _doubleInRange(value, _speedRange);
  }

  static double? volumeFromValue(Object? value) {
    return _doubleInRangeFromValue(value, _volumeRange);
  }

  static double? normalizeVolume(double? value) {
    return _doubleInRange(value, _volumeRange);
  }

  static double? pitchFromValue(Object? value) {
    return _doubleInRangeFromValue(value, _pitchRange);
  }

  static double? normalizePitch(double? value) {
    return _doubleInRange(value, _pitchRange);
  }
}

int? _positiveIntInRangeFromValue(Object? value, IntValueRange range) {
  return _positiveIntInRange(optionalPositiveIntFromValue(value), range);
}

int? _positiveIntInRange(int? value, IntValueRange range) {
  return value == null || value <= 0 ? null : range.normalize(value);
}

double? _doubleInRangeFromValue(Object? value, DoubleValueRange range) {
  return _doubleInRange(optionalDoubleFromValue(value), range);
}

double? _doubleInRange(double? value, DoubleValueRange range) {
  if (value == null) return null;
  return range.normalize(value);
}

/// A fully-resolved creation request (mode + options) that can be serialised
/// into message metadata and passed to protocol adapters.
class AiCreationRequest {
  const AiCreationRequest({
    required this.mode,
    this.options = AiCreationOptions.empty,
  });

  final AiCreationMode mode;
  final AiCreationOptions options;

  bool get isActive => mode.isActive;

  /// Modalities expected by chat endpoints that return generated media inline.
  ///
  /// OpenAI-compatible media models are diverted to dedicated endpoints before
  /// this is used, but Gemini-style adapters need the same intent preserved
  /// when a turn is queued, edited, or regenerated.
  List<String> get responseModalities {
    return switch (mode) {
      AiCreationMode.image => const <String>['Text', 'Image'],
      AiCreationMode.video => const <String>['Text', 'Video'],
      AiCreationMode.audio => const <String>['Text', 'Audio'],
      AiCreationMode.none || AiCreationMode.deepResearch => const <String>[],
    };
  }

  bool get isGeneratedMediaRequest {
    return mode == AiCreationMode.image ||
        mode == AiCreationMode.video ||
        mode == AiCreationMode.audio;
  }

  static const AiCreationRequest none = AiCreationRequest(
    mode: AiCreationMode.none,
  );

  /// Metadata key used on [AiSessionMessage.metadata] to persist creation
  /// intent alongside a user message so downstream rendering (chips,
  /// placeholders) can reconstruct the state.
  static const String metadataKey = 'creation_request';

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      'mode': mode.storageValue,
      'options': options.toMetadata(),
    };
  }

  static AiCreationRequest fromMetadata(Object? raw) {
    final map = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (map == null) return AiCreationRequest.none;
    return AiCreationRequest(
      mode: AiCreationMode.fromStorage(optionalStringFromValue(map['mode'])),
      options: AiCreationOptions.fromMetadata(map['options']),
    );
  }

  /// Localised-agnostic, short identifier used in audit logs.
  String describe() {
    final parts = <String>[mode.storageValue];
    final optionsMeta = options.toMetadata();
    if (optionsMeta.isNotEmpty) {
      parts.add(
        optionsMeta.entries.map((e) => '${e.key}=${e.value}').join(','),
      );
    }
    return parts.join(' ');
  }
}

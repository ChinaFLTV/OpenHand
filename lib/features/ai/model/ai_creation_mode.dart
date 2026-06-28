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
    if (value == null) return AiCreationMode.none;
    for (final mode in AiCreationMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return AiCreationMode.none;
  }
}

/// User-chosen options for a creation request. All fields are optional; the
/// adapter layer applies safe provider defaults when a value is absent.
class AiCreationOptions {
  const AiCreationOptions({
    this.size,
    this.aspectRatio,
    this.durationSeconds,
    this.count = 1,
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
    this.speed,
    this.sampleRate,
    this.bitrate,
    this.volume,
    this.pitch,
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
    double? speed,
    int? sampleRate,
    int? bitrate,
    double? volume,
    double? pitch,
  }) {
    return AiCreationOptions(
      size: size ?? this.size,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      count: count ?? this.count,
      quality: quality ?? this.quality,
      style: style ?? this.style,
      outputFormat: outputFormat ?? this.outputFormat,
      background: background ?? this.background,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      promptEnhance: promptEnhance ?? this.promptEnhance,
      watermark: watermark ?? this.watermark,
      seed: seed ?? this.seed,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      numFrames: numFrames ?? this.numFrames,
      mode: mode ?? this.mode,
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      sampleRate: sampleRate ?? this.sampleRate,
      bitrate: bitrate ?? this.bitrate,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
    );
  }

  bool get hasExplicitOptions => toMetadata().isNotEmpty;

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      if (size != null) 'size': size,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (count != 1) 'count': count,
      if (quality != null) 'quality': quality,
      if (style != null) 'style': style,
      if (outputFormat != null) 'output_format': outputFormat,
      if (background != null) 'background': background,
      if (negativePrompt != null) 'negative_prompt': negativePrompt,
      if (promptEnhance != null) 'prompt_enhance': promptEnhance,
      if (watermark != null) 'watermark': watermark,
      if (seed != null) 'seed': seed,
      if (resolution != null) 'resolution': resolution,
      if (frameRate != null) 'frame_rate': frameRate,
      if (numFrames != null) 'num_frames': numFrames,
      if (mode != null) 'mode': mode,
      if (voice != null) 'voice': voice,
      if (speed != null) 'speed': speed,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (bitrate != null) 'bitrate': bitrate,
      if (volume != null) 'volume': volume,
      if (pitch != null) 'pitch': pitch,
    };
  }

  static AiCreationOptions fromMetadata(Object? raw) {
    final map = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (map == null) return AiCreationOptions.empty;
    return AiCreationOptions(
      size: optionalStringFromValue(map['size']),
      aspectRatio: optionalStringFromValue(map['aspect_ratio']),
      durationSeconds: optionalIntFromValue(map['duration_seconds']),
      count: optionalIntFromValue(map['count']) ?? 1,
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
      seed: optionalIntFromValue(map['seed']),
      resolution:
          optionalStringFromValue(map['resolution']) ??
          optionalStringFromValue(map['resolution_name']),
      frameRate:
          optionalIntFromValue(map['frame_rate']) ??
          optionalIntFromValue(map['fps']),
      numFrames: optionalIntFromValue(map['num_frames']),
      mode: optionalStringFromValue(map['mode']),
      voice: optionalStringFromValue(map['voice']),
      speed: optionalDoubleFromValue(map['speed']),
      sampleRate: optionalIntFromValue(map['sample_rate']),
      bitrate: optionalIntFromValue(map['bitrate']),
      volume:
          optionalDoubleFromValue(map['volume']) ??
          optionalDoubleFromValue(map['vol']),
      pitch: optionalDoubleFromValue(map['pitch']),
    );
  }
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

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

  static const AiCreationOptions empty = AiCreationOptions();

  AiCreationOptions copyWith({
    String? size,
    String? aspectRatio,
    int? durationSeconds,
    int? count,
    String? quality,
    String? style,
  }) {
    return AiCreationOptions(
      size: size ?? this.size,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      count: count ?? this.count,
      quality: quality ?? this.quality,
      style: style ?? this.style,
    );
  }

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      if (size != null) 'size': size,
      if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (count != 1) 'count': count,
      if (quality != null) 'quality': quality,
      if (style != null) 'style': style,
    };
  }

  static AiCreationOptions fromMetadata(Object? raw) {
    if (raw is! Map) return AiCreationOptions.empty;
    final map = raw.cast<String, Object?>();
    int? asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
    String? asString(Object? v) =>
        v is String && v.trim().isNotEmpty ? v : null;
    return AiCreationOptions(
      size: asString(map['size']),
      aspectRatio: asString(map['aspect_ratio']),
      durationSeconds: asInt(map['duration_seconds']),
      count: asInt(map['count']) ?? 1,
      quality: asString(map['quality']),
      style: asString(map['style']),
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
    if (raw is! Map) return AiCreationRequest.none;
    final map = raw.cast<String, Object?>();
    return AiCreationRequest(
      mode: AiCreationMode.fromStorage(map['mode'] as String?),
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

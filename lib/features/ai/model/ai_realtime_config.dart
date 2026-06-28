import '../../../shared/util/input_value_parsing.dart';

class AiRealtimeConfig {
  const AiRealtimeConfig({
    this.transport,
    this.urlOverride,
    this.voice,
    this.sampleRate,
    this.inputFormat,
    this.outputFormat,
    this.sessionDefaults = const <String, Object?>{},
  });

  final String? transport;
  final String? urlOverride;
  final String? voice;
  final int? sampleRate;
  final String? inputFormat;
  final String? outputFormat;
  final Map<String, Object?> sessionDefaults;

  bool get isEmpty =>
      (transport == null || transport!.trim().isEmpty) &&
      (urlOverride == null || urlOverride!.trim().isEmpty) &&
      (voice == null || voice!.trim().isEmpty) &&
      sampleRate == null &&
      (inputFormat == null || inputFormat!.trim().isEmpty) &&
      (outputFormat == null || outputFormat!.trim().isEmpty) &&
      sessionDefaults.isEmpty;

  AiRealtimeConfig copyWith({
    String? transport,
    String? urlOverride,
    String? voice,
    int? sampleRate,
    String? inputFormat,
    String? outputFormat,
    Map<String, Object?>? sessionDefaults,
    bool clearTransport = false,
    bool clearUrlOverride = false,
    bool clearVoice = false,
    bool clearSampleRate = false,
    bool clearInputFormat = false,
    bool clearOutputFormat = false,
    bool clearSessionDefaults = false,
  }) {
    return AiRealtimeConfig(
      transport: clearTransport ? null : (transport ?? this.transport),
      urlOverride: clearUrlOverride ? null : (urlOverride ?? this.urlOverride),
      voice: clearVoice ? null : (voice ?? this.voice),
      sampleRate: clearSampleRate ? null : (sampleRate ?? this.sampleRate),
      inputFormat: clearInputFormat ? null : (inputFormat ?? this.inputFormat),
      outputFormat: clearOutputFormat
          ? null
          : (outputFormat ?? this.outputFormat),
      sessionDefaults: clearSessionDefaults
          ? const <String, Object?>{}
          : (sessionDefaults ?? this.sessionDefaults),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (transport != null && transport!.trim().isNotEmpty)
        'transport': transport,
      if (urlOverride != null && urlOverride!.trim().isNotEmpty)
        'url_override': urlOverride,
      if (voice != null && voice!.trim().isNotEmpty) 'voice': voice,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (inputFormat != null && inputFormat!.trim().isNotEmpty)
        'input_format': inputFormat,
      if (outputFormat != null && outputFormat!.trim().isNotEmpty)
        'output_format': outputFormat,
      if (sessionDefaults.isNotEmpty) 'session_defaults': sessionDefaults,
    };
  }

  static AiRealtimeConfig? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    return AiRealtimeConfig(
      transport: optionalStringFromValue(json['transport']),
      urlOverride: optionalStringFromValue(json['url_override']),
      voice: optionalStringFromValue(json['voice']),
      sampleRate: _parseNullableInt(json['sample_rate']),
      inputFormat: optionalStringFromValue(json['input_format']),
      outputFormat: optionalStringFromValue(json['output_format']),
      sessionDefaults: stringKeyedMapFromValue(json['session_defaults']),
    );
  }

  static int? _parseNullableInt(Object? raw) {
    final parsed = optionalIntFromValue(raw);
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

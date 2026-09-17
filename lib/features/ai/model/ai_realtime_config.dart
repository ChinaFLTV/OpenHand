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
      nullIfBlank(transport) == null &&
      nullIfBlank(urlOverride) == null &&
      nullIfBlank(voice) == null &&
      sampleRate == null &&
      nullIfBlank(inputFormat) == null &&
      nullIfBlank(outputFormat) == null &&
      sessionDefaults.isEmpty;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{};
    putIfNotBlank(json, 'transport', transport);
    putIfNotBlank(json, 'url_override', urlOverride);
    putIfNotBlank(json, 'voice', voice);
    final normalizedSampleRate = normalizeSampleRate(sampleRate);
    if (normalizedSampleRate != null) {
      json['sample_rate'] = normalizedSampleRate;
    }
    putIfNotBlank(json, 'input_format', inputFormat);
    putIfNotBlank(json, 'output_format', outputFormat);
    if (sessionDefaults.isNotEmpty) {
      json['session_defaults'] = sessionDefaults;
    }
    return json;
  }

  static AiRealtimeConfig? fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return null;
    return AiRealtimeConfig(
      transport: optionalStringFromValue(json['transport']),
      urlOverride: optionalStringFromValue(json['url_override']),
      voice: optionalStringFromValue(json['voice']),
      sampleRate: sampleRateFromValue(json['sample_rate']),
      inputFormat: optionalStringFromValue(json['input_format']),
      outputFormat: optionalStringFromValue(json['output_format']),
      sessionDefaults: stringKeyedMapFromValue(json['session_defaults']),
    );
  }

  static const int minSampleRate = 8000;
  static const int maxSampleRate = 96000;
  static const IntValueRange _sampleRateRange = IntValueRange(
    fallback: minSampleRate,
    min: minSampleRate,
    max: maxSampleRate,
  );

  static int? sampleRateFromValue(Object? value) {
    final parsed = optionalPositiveIntFromValue(value);
    return normalizeSampleRate(parsed);
  }

  static int? normalizeSampleRate(int? value) {
    if (value == null || value <= 0) return null;
    return _sampleRateRange.normalize(value);
  }
}

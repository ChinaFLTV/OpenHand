import 'dart:convert';

import '../../../app/support/silent_log.dart';
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
        silentLog('ai_realtime_config', 'decode JSON string', error, stack);
      }
    }
    if (json == null) return null;
    return AiRealtimeConfig(
      transport: _parseString(json['transport']),
      urlOverride: _parseString(json['url_override']),
      voice: _parseString(json['voice']),
      sampleRate: _parseNullableInt(json['sample_rate']),
      inputFormat: _parseString(json['input_format']),
      outputFormat: _parseString(json['output_format']),
      sessionDefaults: _parseObjectMap(json['session_defaults']),
    );
  }

  static String? _parseString(Object? raw) {
    final trimmed = '${raw ?? ''}'.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _parseNullableInt(Object? raw) {
    final parsed = optionalIntFromValue(raw);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static Map<String, Object?> _parseObjectMap(Object? raw) {
    if (raw is Map<String, Object?>) return Map<String, Object?>.from(raw);
    if (raw is Map) return Map<String, Object?>.from(raw);
    return const <String, Object?>{};
  }
}

bool webReverseRuntimeBoolTrue(Object? raw) {
  if (raw is bool) return raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

bool webReverseRuntimeBoolFalse(Object? raw) {
  if (raw is bool) return !raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'false' || normalized == '0' || normalized == 'no';
}

bool webReverseCdpRuntimeHasLiveLocator(Map<Object?, Object?> value) {
  bool hasText(Object? raw) => raw is String && raw.trim().isNotEmpty;
  bool hasPort(Object? raw) {
    if (raw is num) return raw.toInt() > 0;
    final parsed = int.tryParse('${raw ?? ''}'.trim());
    return parsed != null && parsed > 0;
  }

  return hasPort(value['cdp_port']) ||
      hasText(value['cdp_http_endpoint']) ||
      hasText(value['json_version_url']) ||
      hasText(value['json_list_url']);
}

Map<String, Object?>? webReverseRuntimeObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  return <String, Object?>{
    for (final entry in raw.entries) '${entry.key}': entry.value,
  };
}

bool webReverseCdpRuntimeIsLive(Object? raw) {
  final value = webReverseRuntimeObjectMap(raw);
  if (value == null) return false;
  return webReverseRuntimeBoolTrue(value['browser_alive']) &&
      webReverseCdpRuntimeHasLiveLocator(value);
}

Object? webReverseCurrentCdpRuntimeMetadata(Map<Object?, Object?> metadata) {
  final currentRuntime = metadata['web_reverse_cdp_runtime'];
  if (currentRuntime != null) {
    return currentRuntime;
  }

  final runtime = metadata['web_reverse_runtime'];
  if (runtime is Map) {
    return runtime['cdp_runtime'];
  }
  return null;
}

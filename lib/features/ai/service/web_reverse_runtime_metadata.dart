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

bool webReverseCdpRuntimeHasLocator(Map<Object?, Object?> value) {
  bool hasText(Object? raw) => raw is String && raw.trim().isNotEmpty;
  bool hasPort(Object? raw) {
    if (raw is num) return raw.toInt() > 0;
    final parsed = int.tryParse('${raw ?? ''}'.trim());
    return parsed != null && parsed > 0;
  }

  return hasPort(value['cdp_port']) ||
      hasPort(value['last_cdp_port']) ||
      hasText(value['cdp_http_endpoint']) ||
      hasText(value['json_version_url']) ||
      hasText(value['json_list_url']);
}

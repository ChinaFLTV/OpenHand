// Android 逆向会话的运行时元数据辅助函数。
// 类比 web_reverse_runtime_metadata.dart，但面向 ADB / Frida 通道。

bool androidReverseRuntimeBoolTrue(Object? raw) {
  if (raw is bool) return raw;
  final normalized = '${raw ?? ''}'.trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

Map<String, Object?>? androidReverseRuntimeObjectMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is! Map) return null;
  return <String, Object?>{
    for (final entry in raw.entries) '${entry.key}': entry.value,
  };
}

/// 从 session metadata 中解析 android_reverse_config。
Map<String, Object?>? androidReverseConfigFromMetadata(
  Map<String, Object?>? metadata,
) {
  if (metadata == null) return null;
  return androidReverseRuntimeObjectMap(metadata['android_reverse_config']);
}

/// 从 session metadata 中解析 android_reverse_runtime。
Map<String, Object?>? androidReverseRuntimeFromMetadata(
  Map<String, Object?>? metadata,
) {
  if (metadata == null) return null;
  return androidReverseRuntimeObjectMap(metadata['android_reverse_runtime']);
}

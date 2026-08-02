import 'dart:io';

/// 读取平台环境变量；Windows 下兼容键名大小写差异。
String? platformEnvironmentValue(
  String name, {
  Map<String, String>? environment,
  bool? caseInsensitive,
}) {
  final values = environment ?? Platform.environment;
  final exact = values[name];
  if (exact != null) return exact;
  if (!(caseInsensitive ?? Platform.isWindows)) return null;

  final normalizedName = name.toLowerCase();
  for (final entry in values.entries) {
    if (entry.key.toLowerCase() == normalizedName) return entry.value;
  }
  return null;
}

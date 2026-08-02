import 'dart:io';

const String defaultPosixShellExecutable = '/bin/sh';
const String defaultMacOsShellExecutable = '/bin/zsh';

/// 解析稳定的 POSIX Shell；macOS 默认使用 zsh，其他平台使用 sh。
String preferredPosixShellExecutable({
  String? environmentShell,
  bool? isMacOS,
}) {
  final configured = (environmentShell ?? Platform.environment['SHELL'] ?? '')
      .trim();
  if (configured.isNotEmpty) return configured;
  return (isMacOS ?? Platform.isMacOS)
      ? defaultMacOsShellExecutable
      : defaultPosixShellExecutable;
}

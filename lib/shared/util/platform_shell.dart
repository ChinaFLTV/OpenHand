import 'dart:io';

const String defaultPosixShellExecutable = '/bin/sh';
const String defaultMacOsShellExecutable = '/bin/zsh';

/// Resolves a predictable POSIX shell without touching the filesystem.
/// macOS guarantees zsh at the system path; other POSIX systems guarantee sh.
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

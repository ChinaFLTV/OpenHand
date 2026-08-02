import 'dart:io';

import 'package:path/path.dart' as p;

const String defaultPosixShellExecutable = '/bin/sh';
const String defaultMacOsShellExecutable = '/bin/zsh';
const String defaultBashExecutable = '/bin/bash';

/// 解析可执行 POSIX 脚本的 Shell，拒绝相对路径及 fish 等不兼容 Shell。
String preferredPosixShellExecutable({
  String? environmentShell,
  bool? isMacOS,
  bool? isWindows,
  bool requireBashCompatible = false,
}) {
  final configured = (environmentShell ?? Platform.environment['SHELL'] ?? '')
      .trim();
  final shellName = p.basenameWithoutExtension(configured).toLowerCase();
  final supported = requireBashCompatible
      ? const <String>{'bash', 'zsh'}
      : const <String>{'sh', 'dash', 'bash', 'zsh', 'ksh'};
  if (p.isAbsolute(configured) && supported.contains(shellName)) {
    return p.normalize(configured);
  }
  if (isWindows ?? Platform.isWindows) return 'bash';
  if (isMacOS ?? Platform.isMacOS) return defaultMacOsShellExecutable;
  return requireBashCompatible
      ? defaultBashExecutable
      : defaultPosixShellExecutable;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const String defaultPosixShellExecutable = '/bin/sh';
const String defaultMacOsShellExecutable = '/bin/zsh';
const String defaultBashExecutable = '/bin/bash';
const String _powerShellEncodedCommandPrefix =
    'powershell.exe -NoProfile -NonInteractive -EncodedCommand';

/// 只由这些字符构成的实参交给 shell 不会触发任何展开（无空白、无引号、
/// 无 `$`/`*`/`;` 等元字符），可原样拼接，让命令行与日志保持可读。
final RegExp _posixShellSafeTokenPattern = RegExp(r'^[A-Za-z0-9_./:@%+=,-]+$');

/// 把实参包进 POSIX 单引号。单引号内除 `'` 自身外一切字符都是字面量，
/// 内部的 `'` 用 `'"'"'`（收单引号 → 双引号裹一个单引号 → 重开单引号）
/// 续接，因此这是拼 `sh -c` / `adb shell` 命令行时唯一可靠的转义方式。
/// 空串得到 `''`，不会退化成「消失的实参」。
///
/// 全库所有拼接 shell 命令行的位置都必须走这里，不要各自内联实现——
/// 转义写错一次就是一个命令注入漏洞。
String posixShellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

/// 仅在必要时加引号：[value] 只含无需转义的安全字符时原样返回，
/// 否则等价于 [posixShellQuote]。
String posixShellQuoteIfNeeded(String value) =>
    _posixShellSafeTokenPattern.hasMatch(value)
    ? value
    : posixShellQuote(value);

/// 转义 PowerShell 单引号字符串内部的内容；调用方负责添加外层单引号。
String escapePowerShellSingleQuotedString(String value) =>
    value.replaceAll("'", "''");

/// 构造使用 UTF-16LE `EncodedCommand` 参数的 PowerShell 命令行。
String powerShellEncodedCommand(String command) {
  final codeUnits = command.codeUnits;
  final bytes = Uint8List(codeUnits.length * 2);
  for (var index = 0; index < codeUnits.length; index++) {
    final codeUnit = codeUnits[index];
    bytes[index * 2] = codeUnit & 0xff;
    bytes[index * 2 + 1] = (codeUnit >> 8) & 0xff;
  }
  return '$_powerShellEncodedCommandPrefix ${base64Encode(bytes)}';
}

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

/// 当前进程是否运行在桌面平台（macOS / Windows / Linux）。
bool isDesktopPlatform() =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

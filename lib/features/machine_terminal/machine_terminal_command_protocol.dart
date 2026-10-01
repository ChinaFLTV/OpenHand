import 'dart:convert';
import 'dart:io';

import '../../shared/util/platform_shell.dart';

/// 宿主系统仅用于旧调用的默认值，远程运维始终显式指定目标 Shell。
enum MachineTerminalCommandShell { automatic, posix, powershell, cmd, probe }

MachineTerminalCommandShell resolveMachineTerminalShell(
  MachineTerminalCommandShell shell,
) => shell == MachineTerminalCommandShell.automatic
    ? (Platform.isWindows
          ? MachineTerminalCommandShell.cmd
          : MachineTerminalCommandShell.posix)
    : shell;

String machineTerminalCommandPayload({
  required String command,
  required String beginMarker,
  required String endMarker,
  MachineTerminalCommandShell shell = MachineTerminalCommandShell.automatic,
}) {
  switch (resolveMachineTerminalShell(shell)) {
    case MachineTerminalCommandShell.probe:
      return 'echo __${beginMarker}__\r\n${command.replaceAll('\n', '\r\n')}\r\necho __${endMarker}__:0\r\n';
    case MachineTerminalCommandShell.powershell:
      return "& { Write-Output ''; Write-Output '__${beginMarker}__'; "
          "\$ErrorActionPreference='Stop'; \$LASTEXITCODE=0; try { $command; "
          "if (-not \$?) { throw '命令执行失败。' }; "
          "Write-Output ''; Write-Output ('__${endMarker}__:' + \$LASTEXITCODE) "
          "} catch { Write-Output \$_; Write-Output ''; Write-Output '__${endMarker}__:1' } }\r\n";
    case MachineTerminalCommandShell.cmd:
      return 'echo. & echo __${beginMarker}__\r\n'
          '$command\r\n'
          'echo. & echo __${endMarker}__:%ERRORLEVEL%\r\n';
    default:
      // 整帧作为一个复合命令执行，避免旧版 Bash 的 PS1/PS2 混入采集结果。
      return "(\nprintf '\\n__%s__\\n' '$beginMarker'\n"
          '(\n$command\n)\n'
          '__openhand_status=\$?\n'
          'stty echo 2>/dev/null\n'
          "printf '\\n__%s__:%s\\n' '$endMarker' \"\$__openhand_status\"\n)\n";
  }
}

/// 独立跟踪输入模式，隐藏命令输出时也能识别交互编辑器是否就绪。
class MachineTerminalInputMode {
  static final _pattern = RegExp(r'\x1b\[\?2004([hl])');
  bool supported = false;
  bool enabled = false;
  String _tail = '';

  void add(String output) {
    final text = _tail + output;
    for (final match in _pattern.allMatches(text)) {
      enabled = match[1] == 'h';
      supported |= enabled;
    }
    _tail = text.substring((text.length - 7).clamp(0, text.length));
  }

  void reset() {
    supported = false;
    enabled = false;
    _tail = '';
  }

  String frame(String payload) =>
      enabled ? '\x1b[200~${payload.trimRight()}\x1b[201~\n' : payload;
}

/// 将一个参数拆成短物理行，避免 macOS 规范模式的行缓冲丢弃输入。
String machineTerminalPosixArgument(String value) {
  const runesPerLine = 64;
  final runes = value.runes.toList(growable: false);
  if (runes.isEmpty) return "''";
  return [
    for (var start = 0; start < runes.length; start += runesPerLine)
      posixShellQuote(
        String.fromCharCodes(
          runes.sublist(start, (start + runesPerLine).clamp(0, runes.length)),
        ),
      ),
  ].join('\\\n');
}

const machineTerminalShellProbe = r'''
echo OH_PS_$env:OS
echo OH_CMD_%OS%
uname -s
''';

// 探测阶段尚不知道 Shell 类型；关闭回显时输出可能紧跟交互提示符。
const _machineTerminalProbePrompt = r'(?:[^\r\n]*[>#$%❯➜][ \t]*)?';
final _machineTerminalProbePromptPattern = RegExp(
  '^$_machineTerminalProbePrompt',
);

({MachineTerminalCommandShell shell, String platform})
parseMachineTerminalShellProbe(String output) {
  final lines = output
      .replaceAll('\r', '')
      .split('\n')
      .map(
        (line) =>
            line.trim().replaceFirst(_machineTerminalProbePromptPattern, ''),
      )
      .toSet();
  if (lines.contains('OH_PS_Windows_NT')) {
    return (shell: MachineTerminalCommandShell.powershell, platform: 'Windows');
  }
  if (lines.contains('OH_CMD_Windows_NT')) {
    return (shell: MachineTerminalCommandShell.cmd, platform: 'Windows');
  }
  for (final platform in ['Linux', 'Darwin']) {
    if (lines.contains(platform)) {
      return (shell: MachineTerminalCommandShell.posix, platform: platform);
    }
  }
  throw UnsupportedError('无法识别当前终端；请确保终端处于系统命令提示符状态，且允许执行系统查询。');
}

/// 在已识别的交互终端内读取版本，避免把采集子进程的 Shell 当作当前 Shell。
String machineTerminalShellDetailsCommand(
  MachineTerminalCommandShell shell,
) => switch (shell) {
  MachineTerminalCommandShell.powershell =>
    r"Write-Output ('OH_SHELL_PowerShell ' + $PSVersionTable.PSVersion.ToString())",
  MachineTerminalCommandShell.cmd => 'ver',
  // 保持短命令，避免被暂存脚本转入 sh 后误报子进程版本。
  _ =>
    r'''printf '\nOH_SHELL_%s\n' "${ZSH_VERSION:+zsh }${ZSH_VERSION:-${BASH_VERSION:+bash }${BASH_VERSION:-${KSH_VERSION:+ksh }${KSH_VERSION:-${0##*/}}}}"''',
};

String? parseMachineTerminalShellDetails(
  String output,
  MachineTerminalCommandShell shell,
) {
  if (shell == MachineTerminalCommandShell.cmd) {
    final version = RegExp(r'\d+\.\d+\.\d+(?:\.\d+)?').firstMatch(output);
    return version == null ? null : 'CMD ${version[0]}';
  }
  final match = RegExp(
    r'^OH_SHELL_([^\r\n]+)$',
    multiLine: true,
  ).firstMatch(output.replaceAll('\r', ''));
  final value = match?[1]?.trim();
  return value == null || value.isEmpty
      ? null
      : value.replaceFirst(RegExp('^-'), '');
}

/// Windows 脚本分块只包含 Base64 与数字，不暴露 CMD 元字符。
class MachineTerminalWindowsScript {
  MachineTerminalWindowsScript(
    String script,
    String token,
    this.shell, {
    this.timeout = const Duration(seconds: 25),
  }) {
    if (timeout <= Duration.zero || timeout > const Duration(hours: 1)) {
      throw ArgumentError('脚本超时必须大于零且不超过一小时。');
    }
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(token) ||
        !const [
          MachineTerminalCommandShell.cmd,
          MachineTerminalCommandShell.powershell,
        ].contains(shell)) {
      throw ArgumentError('Windows 脚本传输参数无效。');
    }
    final name = 'openhand-ops-$token.js';
    path = powershell ? "(Join-Path \$env:TEMP '$name')" : '"%TEMP%\\$name"';
    final encoded = base64Encode(utf8.encode(script));
    commands = [write('var s=String();', append: false)];
    for (var offset = 0; offset < encoded.length; offset += chunkCharacters) {
      final end = (offset + chunkCharacters).clamp(0, encoded.length);
      commands.add(write("s+='${encoded.substring(offset, end)}';"));
    }
    commands.add(
      write('eval(String.fromCharCode(${decoder.codeUnits.join(',')}));'),
    );
  }
  static const chunkCharacters = 1024;
  static const decoder =
      "var a='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',b=0,n=0,t='';for(var i=0;i<s.length;i++){var v=a.indexOf(s.charAt(i));if(v<0)continue;b=(b<<6)|v;n+=6;if(n>=8){n-=8;t+=String.fromCharCode((b>>n)&255);}}eval(decodeURIComponent(escape(t)));";
  final MachineTerminalCommandShell shell;
  final Duration timeout;
  late final String path;
  late final List<String> commands;
  bool get powershell => shell == MachineTerminalCommandShell.powershell;
  String write(String text, {bool append = true}) => powershell
      ? "[IO.File]::${append ? 'AppendAllText' : 'WriteAllText'}($path, '${escapePowerShellSingleQuotedString(text)}' + [Environment]::NewLine, [Text.Encoding]::ASCII)"
      : 'cmd.exe /d /v:off /c echo $text ${append ? '^>^>' : '^>'} $path';
  String get execute =>
      '${powershell ? '& ' : ''}cscript.exe //nologo //B //T:${(timeout.inMilliseconds / 1000).ceil()} //E:JScript $path';
  String get cleanup => powershell
      ? 'Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue'
      : 'cmd.exe /d /v:off /c if exist $path del /q $path';
}

/// 只接受完整输出行，命令回显或尚未接收完的标记不能作为就绪确认。
bool machineTerminalHasOutputMarker(String output, String marker) => RegExp(
  '^${RegExp.escape(marker)}\\r?\\n',
  multiLine: true,
).hasMatch(output);

/// 普通命令只识别独占行；探测允许提示符前缀，但仍拒绝 echo 等命令回显。
class MachineTerminalCommandMarkers {
  MachineTerminalCommandMarkers(String begin, String end, {bool probe = false})
    : _begin = RegExp(
        '^${probe ? _machineTerminalProbePrompt : ''}${RegExp.escape(begin)}\\r?\$',
        multiLine: true,
      ),
      _end = RegExp(
        '^${probe ? _machineTerminalProbePrompt : ''}${RegExp.escape(end)}:',
        multiLine: true,
      ),
      _endLength = end.length + 1;
  final int _endLength;
  final RegExp _begin, _end;
  ({int outputStart, int endIndex}) locate(
    String text, {
    bool beginningDiscarded = false,
  }) {
    final start = _begin.firstMatch(text)?.end ?? (beginningDiscarded ? 0 : -1);
    final end = start < 0 ? null : _end.allMatches(text, start).firstOrNull;
    return (
      outputStart: start,
      endIndex: end == null ? -1 : end.end - _endLength,
    );
  }
}

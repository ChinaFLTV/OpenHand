import 'dart:io';

import '../../../app/support/safe_subprocess.dart';
import 'plugin_environment_probe.dart';

final RegExp _pythonVersionOutputPattern = RegExp(r'Python\s+(\d+\.\d+\.\d+)');
final RegExp _pipVersionOutputPattern = RegExp(r'pip\s+(\d+(?:\.\d+)+)');

/// 从 `python --version` 输出提取语义化版本。
String? extractPythonVersion(String output) {
  return _pythonVersionOutputPattern.firstMatch(output)?.group(1);
}

/// 从 `pip --version` 输出提取版本号。
String? extractPipVersion(String output) {
  return _pipVersionOutputPattern.firstMatch(output)?.group(1);
}

Future<ProcessResult> runPluginToolchainCommandOrFailed(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  String? tag,
  Map<String, String>? environment,
}) {
  return runTrackedProcessOrFailed(
    pluginShellExecutable(),
    ['-c', pluginToolchainManagedCommandScript(executable, arguments)],
    timeout: timeout,
    tag: tag ?? 'plugin_toolchain.command.$executable',
    environment: environment ?? pluginProxyEnvironment(),
  );
}

Future<TrackedProcessLineLogResult> runPluginToolchainCommandWithLineLogging(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  required String tag,
  ProcessLogLineHandler? onStdoutLine,
  ProcessLogLineHandler? onStderrLine,
  void Function()? onTimeout,
  Map<String, String>? environment,
}) {
  return runTrackedProcessWithLineLogging(
    pluginShellExecutable(),
    ['-c', pluginToolchainManagedCommandScript(executable, arguments)],
    environment: environment ?? pluginProxyEnvironment(),
    timeout: timeout,
    tag: tag,
    onStdoutLine: onStdoutLine,
    onStderrLine: onStderrLine,
    onTimeout: onTimeout,
  );
}

String pluginToolchainManagedCommandScript(
  String executable,
  List<String> arguments,
) {
  final command = pluginToolchainShellQuote(executable);
  final args = arguments.map(pluginToolchainShellQuote).join(' ');
  final invocation = args.isEmpty ? command : '$command $args';
  return '''
${pluginToolchainShellPrefix()}
${_pluginToolchainNpmGlobalBinFallbackScript(command)}
if ! command -v $command >/dev/null 2>&1; then
  printf '未找到命令：%s\\n' $command >&2
  exit 127
fi
exec $invocation
''';
}

String pluginToolchainExecutableAvailabilityScript(
  String executable, {
  bool includeNpmGlobalBinFallback = false,
}) {
  final command = pluginToolchainShellQuote(executable);
  final npmFallback = includeNpmGlobalBinFallback
      ? _pluginToolchainNpmGlobalBinFallbackScript(command)
      : '';
  return '''
${pluginToolchainShellPrefix()}
$npmFallback
command -v $command >/dev/null 2>&1
''';
}

String pluginToolchainCommandPathScript(
  String executable, {
  bool includeNpmGlobalBinFallback = false,
}) {
  final command = pluginToolchainShellQuote(executable);
  final npmFallback = includeNpmGlobalBinFallback
      ? _pluginToolchainNpmGlobalBinFallbackScript(command)
      : '';
  return '''
${pluginToolchainShellPrefix()}
$npmFallback
command -v $command
''';
}

String pluginToolchainShellPrefix() {
  final voltaHome = pluginToolchainShellQuote(pluginVoltaHomeDirectoryPath());
  final pyenvRoot = pluginToolchainShellQuote(pluginPyenvRootDirectoryPath());
  final nvmDirectory = pluginToolchainShellQuote(pluginNvmDirectoryPath());
  return '''
export VOLTA_HOME=$voltaHome
export PYENV_ROOT=$pyenvRoot
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$VOLTA_HOME/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
if command -v fnm >/dev/null 2>&1; then
  eval "\$(fnm env)"
fi
export NVM_DIR=$nvmDirectory
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
}

String _pluginToolchainNpmGlobalBinFallbackScript(String quotedCommand) {
  return '''
if ! command -v $quotedCommand >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    npm_prefix="\$(npm prefix -g 2>/dev/null || true)"
    if [ -n "\$npm_prefix" ]; then
      export PATH="\$npm_prefix/bin:\$PATH"
    fi
  fi
fi
''';
}

String pluginToolchainShellQuote(String value) {
  if (value.isEmpty) return "''";
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

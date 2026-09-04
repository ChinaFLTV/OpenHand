import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/platform_shell.dart';
import 'plugin_environment_probe.dart';

const String pluginDingtalkWorkspaceCliPackage = 'dingtalk-workspace-cli';
const String pluginDingtalkWorkspaceCliCommand = 'dws';
const String pluginDingtalkWorkspaceCliRepository =
    'https://github.com/DingTalk-Real-AI/dingtalk-workspace-cli';
const String pluginDingtalkWorkspaceCliDocumentation =
    'https://open.dingtalk.com/document/development/dingtalk-cli-performing-tasks-within';
const String pluginDingtalkWorkspaceCliInstallScriptBaseUrl =
    'https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts';

String pluginDingtalkWorkspaceCliInstallScriptUrl() {
  return Platform.isWindows
      ? '$pluginDingtalkWorkspaceCliInstallScriptBaseUrl/install.ps1'
      : '$pluginDingtalkWorkspaceCliInstallScriptBaseUrl/install.sh';
}

String pluginDesktopTargetLabel() {
  return switch (Abi.current()) {
    Abi.macosArm64 => 'macOS arm64',
    Abi.macosX64 => 'macOS amd64',
    Abi.linuxArm64 => 'Linux arm64',
    Abi.linuxX64 => 'Linux amd64',
    Abi.windowsArm64 => 'Windows arm64',
    Abi.windowsX64 => 'Windows amd64',
    _ => '${Platform.operatingSystem} ${Platform.version.split(' ').last}',
  };
}

String pluginDingtalkWorkspaceCliTargetOs() => pluginDesktopTargetLabel();

String pluginDingtalkWorkspaceCliDefaultExecutablePath() {
  return p.join(
    OpenHandPaths.homeDirectoryPath(),
    '.local',
    'bin',
    Platform.isWindows ? 'dws.exe' : 'dws',
  );
}

Future<String?> resolvePluginDingtalkWorkspaceCliExecutable({
  Duration timeout = const Duration(seconds: 5),
  Future<void>? cancelSignal,
  String tag = 'plugin_toolchain.dingtalk_workspace_cli_path',
}) async {
  final defaultPath = pluginDingtalkWorkspaceCliDefaultExecutablePath();
  if (await isRegularFilePath(defaultPath, followLinks: true)) {
    return defaultPath;
  }
  final result = Platform.isWindows
      ? await runTrackedProcessOrFailed(
          'where.exe',
          const <String>[pluginDingtalkWorkspaceCliCommand],
          timeout: timeout,
          cancelSignal: cancelSignal,
          tag: tag,
          environment: pluginProxyEnvironment(),
        )
      : await runTrackedProcessOrFailed(
          pluginShellExecutable(),
          <String>[
            '-c',
            pluginToolchainCommandPathScript(
              pluginDingtalkWorkspaceCliCommand,
              includeNpmGlobalBinFallback: true,
            ),
          ],
          timeout: timeout,
          cancelSignal: cancelSignal,
          tag: tag,
          environment: pluginProxyEnvironment(),
        );
  return result.exitCode == 0
      ? extractPluginAbsolutePath(result.stdout.toString())
      : null;
}

Future<PluginNpmPackageInstallation?>
resolvePluginDingtalkWorkspaceCliNpmPackage({
  Duration timeout = const Duration(seconds: 5),
  Future<void>? cancelSignal,
  String tag = 'plugin_toolchain.dingtalk_workspace_cli_npm_root',
}) async {
  final result = Platform.isWindows
      ? await runTrackedProcessOrFailed(
          'npm.cmd',
          const <String>['root', '-g'],
          timeout: timeout,
          cancelSignal: cancelSignal,
          tag: tag,
          environment: pluginProxyEnvironment(),
        )
      : await runPluginToolchainCommandOrFailed(
          'npm',
          const <String>['root', '-g'],
          timeout: timeout,
          cancelSignal: cancelSignal,
          tag: tag,
          environment: pluginProxyEnvironment(),
        );
  return resolvePluginGlobalNpmPackage(
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    packageName: pluginDingtalkWorkspaceCliPackage,
  );
}

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
  Future<void>? cancelSignal,
  String? tag,
  Map<String, String>? environment,
}) {
  return runTrackedProcessOrFailed(
    pluginShellExecutable(),
    ['-c', pluginToolchainManagedCommandScript(executable, arguments)],
    timeout: timeout,
    cancelSignal: cancelSignal,
    tag: tag ?? 'plugin_toolchain.command.$executable',
    environment: environment ?? pluginProxyEnvironment(),
  );
}

Future<TrackedProcessLineLogResult> runPluginToolchainCommandWithLineLogging(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  required String tag,
  Future<void>? cancelSignal,
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
    cancelSignal: cancelSignal,
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
  final command = posixShellQuote(executable);
  final args = arguments.map(posixShellQuote).join(' ');
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
  final command = posixShellQuote(executable);
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
  final command = posixShellQuote(executable);
  final npmFallback = includeNpmGlobalBinFallback
      ? _pluginToolchainNpmGlobalBinFallbackScript(command)
      : '';
  return '''
${pluginToolchainShellPrefix()}
$npmFallback
command -v $command
''';
}

String pluginPyenvShellPrefix() {
  final pyenvRoot = posixShellQuote(pluginPyenvRootDirectoryPath());
  return '''
export PYENV_ROOT=$pyenvRoot
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
''';
}

String pluginNvmShellPrefix() {
  final nvmDirectory = posixShellQuote(pluginNvmDirectoryPath());
  return '''
export NVM_DIR=$nvmDirectory
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
}

String pluginToolchainShellPrefix() {
  final voltaHome = posixShellQuote(pluginVoltaHomeDirectoryPath());
  final pyenvRoot = posixShellQuote(pluginPyenvRootDirectoryPath());
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
${pluginNvmShellPrefix()}
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

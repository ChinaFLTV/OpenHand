import 'dart:io';

final RegExp _pythonVersionOutputPattern = RegExp(r'Python\s+(\d+\.\d+\.\d+)');
final RegExp _pipVersionOutputPattern = RegExp(r'pip\s+(\d+(?:\.\d+)+)');

/// Extracts the semantic version from `python --version` output
/// (e.g. `Python 3.12.1` → `3.12.1`). Returns null when absent.
String? extractPythonVersion(String output) {
  return _pythonVersionOutputPattern.firstMatch(output)?.group(1);
}

/// Extracts the version from `pip --version` output
/// (e.g. `pip 24.0 from ...` → `24.0`). Returns null when absent.
String? extractPipVersion(String output) {
  return _pipVersionOutputPattern.firstMatch(output)?.group(1);
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
  printf '%s not found\\n' $command >&2
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
  final home = Platform.environment['HOME'] ?? '';
  return '''
export NVM_DIR="\${NVM_DIR:-$home/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
if command -v fnm >/dev/null 2>&1; then
  eval "\$(fnm env)"
fi
export VOLTA_HOME="\${VOLTA_HOME:-$home/.volta}"
export PYENV_ROOT="\${PYENV_ROOT:-$home/.pyenv}"
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$VOLTA_HOME/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
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

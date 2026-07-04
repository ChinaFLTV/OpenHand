import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/version_compare.dart';
import 'plugin_toolchain_shell.dart';

const Duration _pluginLifecycleDefaultTimeout = Duration(minutes: 3);
const Duration _pluginLifecycleProbeTimeout = Duration(seconds: 5);
const Duration _pluginLifecycleVerifyTimeout = Duration(seconds: 8);
const Duration _pluginLifecycleStreamDrainTimeout = Duration(milliseconds: 800);
const Duration _pluginLifecycleTerminateGrace = Duration(milliseconds: 500);
const int _pluginLifecycleMaxCapturedLines = 500;
const int _pluginLifecycleMaxProgressLineChars = 4000;
const int _pluginLifecycleMaxErrorMessageChars = 20000;
const String _hermesAgentNpmPackage = 'hermes-agent';
const String _hermesAgentPrimaryCommand = 'hermes-agent';
const String _hermesAgentFallbackCommand = 'hermes';
final RegExp _pluginLifecycleWhitespacePattern = RegExp(r'\s+');
final RegExp _pluginLifecyclePythonVersionPattern = RegExp(
  r'Python\s+(\d+\.\d+\.\d+)',
);
final RegExp _pluginLifecyclePipVersionPattern = RegExp(
  r'pip\s+(\d+(?:\.\d+)+)',
);
final RegExp _pluginLifecycleNodeVersionPattern = RegExp(
  r'(v\d+\.\d+(?:\.\d+)?)',
);
final RegExp _pluginLifecyclePlaywrightVersionPrefixPattern = RegExp(
  r'^Version\s+',
  caseSensitive: false,
);
final RegExp _pluginLifecycleSemverPattern = RegExp(r'(\d+\.\d+\.\d+)');
final RegExp _pluginLifecycleStablePyenvVersionLinePattern = RegExp(
  r'^\s*(\d+\.\d+\.\d+)\s*$',
);
final RegExp _pluginLifecyclePyenvVersionPathPattern = RegExp(
  r'/.pyenv/versions/([^/]+)/',
);
final RegExp _pluginLifecycleBrewPythonFormulaPathPattern = RegExp(
  r'/(python(?:@[\d.]+)?)(?:/|$)',
);

@visibleForTesting
String? homebrewStableVersionFromDecoded(Object? decoded) {
  final root = stringKeyedMapFromValue(decoded);
  final formulae = stringKeyedMapListFromValue(root['formulae']);
  if (formulae.isEmpty) return null;
  final versions = stringKeyedMapFromValue(formulae.first['versions']);
  final stable = '${versions['stable'] ?? ''}'.trim();
  return stable.isEmpty ? null : stable;
}

@visibleForTesting
bool pluginLifecycleOutputHasPyPiTlsFailure(String output) {
  final lower = output.toLowerCase();
  return lower.contains('certificate_verify_failed') ||
      (lower.contains('unable to get local issuer certificate') &&
          (lower.contains('pypi.org') || lower.contains('/simple/')));
}

@visibleForTesting
String hermesAgentNpmFailureMessage({
  required String label,
  required String output,
  bool tlsRetryAttempted = false,
  String? tlsBundle,
}) {
  final trimmed = output.trim();
  final lower = trimmed.toLowerCase();
  final hasTlsFailure = pluginLifecycleOutputHasPyPiTlsFailure(trimmed);
  final hasMetadataFailure =
      lower.contains('could not fetch url') || lower.contains('/simple/');
  final hasNoMatchingDistribution = lower.contains(
    'no matching distribution found',
  );
  final lines = <String>['npm 安装 $label 失败。'];
  if (hasTlsFailure) {
    lines.add('诊断：npm postinstall 调用 pip 访问 PyPI 时证书校验失败，导致 Python 包元数据无法获取。');
    if (tlsRetryAttempted && tlsBundle != null && tlsBundle.isNotEmpty) {
      lines.add('已使用 CA bundle 重试：$tlsBundle。');
    } else {
      lines.add('未找到可用 CA bundle，无法自动完成证书兜底重试。');
    }
    lines.add('请检查系统代理、企业根证书或 Python / Node.js 信任链，然后重试。');
  } else if (hasMetadataFailure) {
    lines.add('诊断：pip 无法从 PyPI 获取包元数据，请检查代理、DNS 与网络连通性。');
  } else if (hasNoMatchingDistribution) {
    lines.add('诊断：pip 未找到匹配的 Hermes Agent Python 包版本，请检查当前 Python 版本与包发布状态。');
  }
  if (trimmed.isNotEmpty) {
    lines.add(
      '原始输出：\n${clipTextWithEllipsis(trimmed, _pluginLifecycleMaxErrorMessageChars)}',
    );
  }
  return lines.join('\n');
}

@visibleForTesting
String pluginLifecycleManagedToolchainCommandScript(
  String executable,
  List<String> arguments,
) => pluginToolchainManagedCommandScript(executable, arguments);

@visibleForTesting
String pluginLifecycleExecutableAvailabilityScript(String executable) =>
    pluginToolchainExecutableAvailabilityScript(executable);

@visibleForTesting
String pluginLifecycleManagedCommandPathScript(String executable) =>
    pluginToolchainCommandPathScript(
      executable,
      includeNpmGlobalBinFallback: true,
    );

/// 插件生命周期操作结果。
class PluginOperationResult {
  const PluginOperationResult({
    required this.success,
    String? message,
    this.newVersion,
  }) : _message = message;

  final bool success;
  final String? _message;
  final String? newVersion;

  String? get message => _localizedPluginLifecycleMessage(_message);
}

String _pluginLifecycleText({
  required String zh,
  required String en,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedTextForLocaleName(
    Platform.localeName,
    zh: zh,
    zhHant: zhHant,
    en: en,
    fr: fr,
    de: de,
    ja: ja,
  );
}

String? _localizedPluginLifecycleMessage(String? message) {
  if (message == null || message.trim().isEmpty) {
    return message;
  }
  final locale = Platform.localeName;
  if (locale.toLowerCase().startsWith('zh')) {
    return message;
  }

  String text({required String en, String? fr, String? de, String? ja}) {
    return _pluginLifecycleText(zh: message, en: en, fr: fr, de: de, ja: ja);
  }

  Match? match;
  match = RegExp(
    r'^(.+?) 已通过 (nvm|fnm|pyenv|volta|Homebrew) 安装$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    return text(
      en: '$item was installed with $manager',
      fr: '$item a été installé avec $manager',
      de: '$item wurde mit $manager installiert',
      ja: '$item は $manager でインストールされました',
    );
  }
  match = RegExp(
    r'^(.+?) 已通过 (nvm|fnm|pyenv|volta|Homebrew) 更新(?:到 (.+))?$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    final version = match.group(3);
    final suffix = version == null ? '' : ' to $version';
    return text(
      en: '$item was updated$suffix with $manager',
      fr: '$item a été mis à jour$suffix avec $manager',
      de: '$item wurde$suffix mit $manager aktualisiert',
      ja: '$item は $manager で更新されました${version == null ? '' : ' ($version)'}',
    );
  }
  match = RegExp(r'^(.+?) 已通过 (pyenv|Homebrew) 卸载$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final manager = match.group(2)!;
    return text(
      en: '$item was uninstalled with $manager',
      fr: '$item a été désinstallé avec $manager',
      de: '$item wurde mit $manager deinstalliert',
      ja: '$item は $manager でアンインストールされました',
    );
  }
  match = RegExp(
    r'^(nvm|fnm|pyenv|volta|Homebrew) (安装|更新|卸载)失败: (.+)$',
  ).firstMatch(message);
  if (match != null) {
    final manager = match.group(1)!;
    final action = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: '$manager $actionEn failed: $detail',
      fr: 'Échec $actionEn de $manager : $detail',
      de: '$manager $actionEn fehlgeschlagen: $detail',
      ja: '$manager の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(r'^Homebrew (安装|更新|卸载) (.+?) 失败: (.+)$').firstMatch(message);
  if (match != null) {
    final action = match.group(1)!;
    final item = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: 'Homebrew $actionEn of $item failed: $detail',
      fr: 'Échec $actionEn de $item avec Homebrew : $detail',
      de: 'Homebrew $actionEn von $item fehlgeschlagen: $detail',
      ja: 'Homebrew による $item の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(r'^未找到 Homebrew，无法自动(安装|更新|卸载) (.+)。$').firstMatch(message);
  if (match != null) {
    final action = match.group(1)!;
    final item = match.group(2)!;
    final actionEn = switch (action) {
      '安装' => 'install',
      '更新' => 'update',
      _ => 'uninstall',
    };
    return text(
      en: 'Homebrew was not found, so $item cannot be $actionEn automatically.',
      fr: 'Homebrew est introuvable ; $item ne peut pas être traité automatiquement.',
      de: 'Homebrew wurde nicht gefunden; $item kann nicht automatisch verarbeitet werden.',
      ja: 'Homebrew が見つからないため、$item を自動処理できません。',
    );
  }
  match = RegExp(r'^(.+?) 已安装或更新(?::|：)?(.+)?$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final path = (match.group(2) ?? '').trim();
    final suffix = path.isEmpty ? '' : ': $path';
    return text(
      en: '$item installed or updated$suffix',
      fr: '$item installé ou mis à jour$suffix',
      de: '$item installiert oder aktualisiert$suffix',
      ja: '$item をインストールまたは更新しました$suffix',
    );
  }
  match = RegExp(r'^(.+?) 已更新(?:到 (.+))?$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final version = match.group(2);
    final suffix = version == null ? '' : ' to $version';
    return text(
      en: '$item updated$suffix',
      fr: '$item mis à jour$suffix',
      de: '$item aktualisiert$suffix',
      ja: '$item を更新しました${version == null ? '' : ' ($version)'}',
    );
  }
  match = RegExp(r'^(.+?) 已卸载$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    return text(
      en: '$item uninstalled',
      fr: '$item désinstallé',
      de: '$item deinstalliert',
      ja: '$item をアンインストールしました',
    );
  }
  match = RegExp(r'^(.+?) (安装|更新|卸载|安装/启动)失败: (.+)$').firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final action = match.group(2)!;
    final detail = match.group(3)!;
    final actionEn = switch (action) {
      '安装' => 'installation',
      '更新' => 'update',
      '卸载' => 'uninstall',
      _ => 'install/start',
    };
    return text(
      en: '$item $actionEn failed: $detail',
      fr: 'Échec $actionEn de $item : $detail',
      de: '$item $actionEn fehlgeschlagen: $detail',
      ja: '$item の $actionEn に失敗しました: $detail',
    );
  }
  match = RegExp(
    r'^(.+?) (依赖|需要) (Node\.js|npm|Python|pip)，(.+)$',
  ).firstMatch(message);
  if (match != null) {
    final item = match.group(1)!;
    final dependency = match.group(3)!;
    return text(
      en: '$item requires $dependency. Install $dependency first.',
      fr: '$item nécessite $dependency. Installez d’abord $dependency.',
      de: '$item benötigt $dependency. Installiere zuerst $dependency.',
      ja: '$item には $dependency が必要です。先にインストールしてください。',
    );
  }
  match = RegExp(r'^未检测到 (Python|npm)，无法(.+?) (.+)。$').firstMatch(message);
  if (match != null) {
    final dependency = match.group(1)!;
    final action = match.group(2)!;
    final item = match.group(3)!;
    return text(
      en: '$dependency was not detected, so $item cannot be $action.',
      fr: '$dependency est introuvable ; $item ne peut pas être traité.',
      de: '$dependency wurde nicht gefunden; $item kann nicht verarbeitet werden.',
      ja: '$dependency が見つからないため、$item を処理できません。',
    );
  }

  switch (message) {
    case '未检测到可用的 Python 运行时，请先安装 Python。':
    case '未检测到可用的 Python 运行时。':
      return text(
        en: 'No usable Python runtime was detected. Install Python first.',
        fr: 'Aucun runtime Python utilisable n’a été détecté. Installez Python d’abord.',
        de: 'Keine nutzbare Python-Laufzeit gefunden. Installiere zuerst Python.',
        ja: '利用可能な Python ランタイムが見つかりません。先に Python をインストールしてください。',
      );
    case '当前 pip 由 Homebrew Python 管理，请通过 Homebrew 更新对应 Python。':
      return text(
        en: 'The current pip is managed by Homebrew Python. Update the matching Python via Homebrew.',
        fr: 'Le pip actuel est géré par Homebrew Python. Mettez à jour le Python correspondant via Homebrew.',
        de: 'Das aktuelle pip wird von Homebrew Python verwaltet. Aktualisiere das passende Python über Homebrew.',
        ja: '現在の pip は Homebrew Python によって管理されています。対応する Python を Homebrew で更新してください。',
      );
    case 'pip 安装后验证失败':
      return text(
        en: 'pip verification failed after installation',
        fr: 'La vérification de pip a échoué après installation',
        de: 'pip-Verifizierung nach Installation fehlgeschlagen',
        ja: 'pip インストール後の検証に失敗しました',
      );
    case 'Playwright 依赖 Node.js，请先安装 Node.js':
    case 'Playwright 依赖 Node.js，请先卸载 Playwright':
      return text(
        en: 'Playwright requires Node.js. Install Node.js first.',
        fr: 'Playwright nécessite Node.js. Installez d’abord Node.js.',
        de: 'Playwright benötigt Node.js. Installiere zuerst Node.js.',
        ja: 'Playwright には Node.js が必要です。先に Node.js をインストールしてください。',
      );
    case 'Playwright 安装后验证失败':
      return text(
        en: 'Playwright verification failed after installation',
        fr: 'La vérification de Playwright a échoué après installation',
        de: 'Playwright-Verifizierung nach Installation fehlgeschlagen',
        ja: 'Playwright インストール後の検証に失敗しました',
      );
    case '当前平台不支持自动安装 Docker。':
      return text(
        en: 'Automatic Docker installation is not supported on this platform.',
        fr: 'L’installation automatique de Docker n’est pas prise en charge sur cette plateforme.',
        de: 'Automatische Docker-Installation wird auf dieser Plattform nicht unterstützt.',
        ja: 'このプラットフォームでは Docker の自動インストールに対応していません。',
      );
    case 'Docker daemon 未运行，请先启动 Docker。':
      return text(
        en: 'Docker daemon is not running. Start Docker first.',
        fr: 'Le daemon Docker ne fonctionne pas. Démarrez Docker d’abord.',
        de: 'Der Docker-Daemon läuft nicht. Starte zuerst Docker.',
        ja: 'Docker daemon が実行されていません。先に Docker を起動してください。',
      );
    case 'Docker CLI 与 daemon 已就绪。':
      return text(
        en: 'Docker CLI and daemon are ready.',
        fr: 'Docker CLI et daemon sont prêts.',
        de: 'Docker CLI und Daemon sind bereit.',
        ja: 'Docker CLI と daemon の準備ができました。',
      );
    case 'Docker Desktop 已安装。首次使用可能需要手动打开并完成授权。':
      return text(
        en: 'Docker Desktop is installed. First use may require opening it manually and completing authorization.',
        fr: 'Docker Desktop est installé. La première utilisation peut nécessiter une ouverture manuelle et une autorisation.',
        de: 'Docker Desktop ist installiert. Beim ersten Start kann manuelles Öffnen und Autorisierung nötig sein.',
        ja: 'Docker Desktop はインストール済みです。初回利用時は手動で開いて認証を完了する必要があります。',
      );
    case 'Docker Desktop 已启动，daemon 可用。':
      return text(
        en: 'Docker Desktop started and the daemon is available.',
        fr: 'Docker Desktop a démarré et le daemon est disponible.',
        de: 'Docker Desktop wurde gestartet und der Daemon ist verfügbar.',
        ja: 'Docker Desktop が起動し、daemon を利用できます。',
      );
    case 'pip 不支持卸载，仅支持安装与升级。':
      return text(
        en: 'pip cannot be uninstalled here. Only install and update are supported.',
        fr: 'pip ne peut pas être désinstallé ici. Seules installation et mise à jour sont prises en charge.',
        de: 'pip kann hier nicht deinstalliert werden. Nur Installation und Update werden unterstützt.',
        ja: 'ここでは pip をアンインストールできません。インストールと更新のみ対応しています。',
      );
  }
  return message;
}

/// 管理插件的安装、更新、卸载操作。
///
/// 处理依赖关系：
/// - 安装 Playwright 前自动检查 NodeJS 是否已安装
/// - 卸载 NodeJS 前检查 Playwright 是否仍在使用
/// - Python / pip 仅自动管理 pyenv 与 Homebrew 来源
class PluginLifecycleService {
  PluginLifecycleService();

  static const String _qdrantContainerName = 'openhand-qdrant';
  static const String _qdrantImage = 'qdrant/qdrant:latest';
  static const int _qdrantRestPort = 6333;
  static const int _qdrantGrpcPort = 6334;

  static String _pickShell() {
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) return shell;
    return '/bin/zsh';
  }

  /// 把 SystemProxyResolver 解析出的代理端点叠加到子进程环境。
  /// 任何需要访问外网（PyPI / npm / Homebrew bottles / Node release /
  /// ghcr.io 等）的子流程都必须走这条通道，否则在企业代理 / 内网
  /// 透明代理环境下 install / update 会因 TCP 握手失败而超时。
  static Map<String, String> _proxyEnv() {
    return SystemProxyResolver.instance.resolveSubprocessEnvironment();
  }

  static Map<String, String> _npmGlobalPackageEnv({String? tlsBundle}) {
    final proxy = _proxyEnv();
    final env = <String, String>{
      ...proxy,
      'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      'PIP_RETRIES': '2',
      'PIP_DEFAULT_TIMEOUT': '60',
      'npm_config_fetch_retries': '2',
      'npm_config_fetch_retry_maxtimeout': '30000',
      'npm_config_fetch_timeout': '120000',
    };

    final httpProxy = proxy['HTTP_PROXY'] ?? proxy['http_proxy'];
    final httpsProxy = proxy['HTTPS_PROXY'] ?? proxy['https_proxy'];
    final noProxy = proxy['NO_PROXY'] ?? proxy['no_proxy'];
    if (httpProxy != null && httpProxy.isNotEmpty) {
      env['npm_config_proxy'] = httpProxy;
    }
    if (httpsProxy != null && httpsProxy.isNotEmpty) {
      env['npm_config_https_proxy'] = httpsProxy;
    }
    if (noProxy != null && noProxy.isNotEmpty) {
      env['npm_config_noproxy'] = noProxy;
    }

    if (tlsBundle != null && tlsBundle.isNotEmpty) {
      env['PIP_CERT'] = tlsBundle;
      env['SSL_CERT_FILE'] = tlsBundle;
      env['REQUESTS_CA_BUNDLE'] = tlsBundle;
      env['CURL_CA_BUNDLE'] = tlsBundle;
      env['NODE_EXTRA_CA_CERTS'] = tlsBundle;
      env['npm_config_cafile'] = tlsBundle;
    }
    return env;
  }

  Future<ProcessResult> _runManagedToolchainCommand(
    String executable,
    List<String> arguments, {
    Duration timeout = _pluginLifecycleVerifyTimeout,
    String? tag,
    Map<String, String>? environment,
  }) {
    return runTrackedProcessOrFailed(
      _pickShell(),
      [
        '-c',
        pluginLifecycleManagedToolchainCommandScript(executable, arguments),
      ],
      timeout: timeout,
      tag: tag ?? 'plugin_lifecycle.command.$executable',
      environment: environment ?? _proxyEnv(),
    );
  }

  Future<_SimpleProcessResult> _runManagedToolchainCommandWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _pluginLifecycleDefaultTimeout,
    Map<String, String>? environment,
  }) {
    return _runWithProgress(
      _pickShell(),
      [
        '-c',
        pluginLifecycleManagedToolchainCommandScript(executable, arguments),
      ],
      onProgress: onProgress,
      timeout: timeout,
      environment: environment ?? _proxyEnv(),
    );
  }

  Future<String?> _resolveManagedToolchainCommandPath(
    String executable, {
    Map<String, String>? environment,
  }) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', pluginLifecycleManagedCommandPathScript(executable)],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.command_path.$executable',
      environment: environment ?? _proxyEnv(),
    );
    if (result.exitCode != 0) return null;
    return _extractAbsolutePathFromOutput(result.stdout.toString());
  }

  Future<bool> _isExecutableAvailable(String executable) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', pluginLifecycleExecutableAvailabilityScript(executable)],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.command_probe.$executable',
      environment: _proxyEnv(),
    );
    return result.exitCode == 0;
  }

  Future<bool> _isDockerDaemonAvailable() async {
    final result = await runTrackedProcessOrFailed(
      'docker',
      ['info'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.docker_info',
      environment: _proxyEnv(),
    );
    return result.exitCode == 0;
  }

  String _qdrantDataDirectory() {
    return '${OpenHandPaths.homeDirectoryPath()}/.openhand/knowledge/qdrant';
  }

  /// nvm 是 shell 函数而非可执行文件，需要先 source 初始化脚本。
  static String _nvmSourcePrefix() {
    final home = Platform.environment['HOME'] ?? '';
    return '''
export NVM_DIR="\${NVM_DIR:-$home/.nvm}"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
''';
  }

  static String _pythonShellPrefix() {
    final home = Platform.environment['HOME'] ?? '';
    return '''
export PYENV_ROOT="\${PYENV_ROOT:-$home/.pyenv}"
export PATH="\$PYENV_ROOT/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "\$(pyenv init -)"
fi
''';
  }

  Future<_SimpleProcessResult> _runNvmCommand(
    String nvmCommand, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_nvmSourcePrefix()}$nvmCommand';
    return _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<_SimpleProcessResult> _runPythonShellCommand(
    String command, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    final script = '${_pythonShellPrefix()}$command';
    return _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<_SimpleProcessResult> _runBoundPythonCommand(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) {
    return _runWithProgress(
      executable,
      arguments,
      onProgress: onProgress,
      timeout: timeout,
      environment: _proxyEnv(),
    );
  }

  Future<bool> _isNvmAvailable() async {
    final home = Platform.environment['HOME'] ?? '';
    final nvmSh = File('$home/.nvm/nvm.sh');
    return nvmSh.existsSync();
  }

  Future<bool> _isPyenvAvailable() async {
    final home = Platform.environment['HOME'] ?? '';
    if (File('$home/.pyenv/bin/pyenv').existsSync()) return true;
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}command -v pyenv'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.pyenv_check',
    );
    return result.exitCode == 0;
  }

  Future<_PythonRuntimeContext?> _detectPythonRuntimeContext() async {
    final pyenvContext = await _detectPyenvContext();
    if (pyenvContext != null) return pyenvContext;
    final brewContext = await _detectBrewPythonContext();
    if (brewContext != null) return brewContext;
    final pythonPath = await _resolveActivePythonPath();
    if (pythonPath == null) return null;
    return _PythonRuntimeContext(
      source: _looksLikeSystemPython(pythonPath)
          ? _PythonRuntimeSource.system
          : _PythonRuntimeSource.unknown,
      executablePath: pythonPath,
      version: await _readPythonVersion(pythonPath),
    );
  }

  Future<_PythonRuntimeContext?> _detectPyenvContext() async {
    if (!await _isPyenvAvailable()) return null;
    final versionNameResult = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv version-name'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.pyenv_version_name',
    );
    final selected = versionNameResult.exitCode == 0
        ? versionNameResult.stdout
              .toString()
              .trim()
              .split(_pluginLifecycleWhitespacePattern)
              .first
        : null;
    final executable = await _resolvePyenvPythonPath();
    if (executable == null) return null;
    final managedPyenvVersion =
        selected != null && isStrictSemanticVersionText(selected)
        ? selected
        : _extractPyenvVersionFromPath(executable);
    if (managedPyenvVersion == null) return null;
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.pyenv,
      executablePath: executable,
      version: version,
      pyenvVersion: managedPyenvVersion,
    );
  }

  Future<_PythonRuntimeContext?> _detectBrewPythonContext() async {
    final executable = await _resolveActivePythonPath();
    if (executable == null || !_looksLikeHomebrewPath(executable)) return null;
    final version = await _readPythonVersion(executable);
    return _PythonRuntimeContext(
      source: _PythonRuntimeSource.homebrew,
      executablePath: executable,
      version: version,
      brewFormula: _extractBrewPythonFormulaFromPath(executable) ?? 'python',
    );
  }

  Future<String?> _resolveActivePythonPath() async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}command -v python3 || command -v python'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.python_path',
    );
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/')) return trimmed;
    }
    return null;
  }

  Future<String?> _resolvePyenvPythonPath() async {
    for (final command in const ['python3', 'python']) {
      final result = await runTrackedProcessOrFailed(
        _pickShell(),
        ['-c', '${_pythonShellPrefix()}pyenv which $command'],
        timeout: _pluginLifecycleProbeTimeout,
        tag: 'plugin_lifecycle.pyenv_which',
      );
      if (result.exitCode != 0) continue;
      for (final line in result.stdout.toString().split('\n').reversed) {
        final trimmed = line.trim();
        if (trimmed.startsWith('/')) return trimmed;
      }
    }
    return null;
  }

  Future<String?> _readPythonVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['--version'],
      timeout: _pluginLifecycleProbeTimeout,
      tag: 'plugin_lifecycle.python_version',
    );
    if (result.exitCode != 0) return null;
    return _extractPythonVersion('${result.stdout}\n${result.stderr}');
  }

  Future<String?> _readPipVersion(String executable) async {
    final result = await runTrackedProcessOrFailed(
      executable,
      ['-m', 'pip', '--version'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pip_version',
    );
    if (result.exitCode != 0) return null;
    return _extractPipVersion('${result.stdout}\n${result.stderr}');
  }

  bool _isExternallyManagedPipError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('externally-managed-environment') ||
        normalized.contains('externally managed') ||
        normalized.contains('pep 668');
  }

  String _pipManagedEnvironmentMessage(_PythonRuntimeContext context) {
    return switch (context.source) {
      _PythonRuntimeSource.homebrew =>
        '当前 pip 由 Homebrew Python 管理，不能在插件中直接自升级。请通过 Homebrew 更新对应 Python。',
      _PythonRuntimeSource.system =>
        '当前 pip 绑定的是系统 Python，不能在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _PythonRuntimeSource.unknown =>
        '当前 pip 绑定的 Python 来源未知，不能安全地在插件中直接自升级。若需安装第三方库，请使用虚拟环境。',
      _ => '当前 pip 所在环境不支持在插件中直接自升级。',
    };
  }

  Future<String?> _queryLatestPyenvPatch(String currentVersion) async {
    final parts = currentVersion.split('.');
    if (parts.length < 2) return null;
    final majorMinor = '${parts[0]}.${parts[1]}';
    final proxyEnv = _proxyEnv();
    final latestResult = await runTrackedProcessOrFailed(
      _pickShell(),
      [
        '-c',
        '${_pythonShellPrefix()}pyenv latest -k $majorMinor 2>/dev/null || true',
      ],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pyenv_latest',
      environment: proxyEnv,
    );
    final quickVersion = _extractFirstSemver(
      '${latestResult.stdout}\n${latestResult.stderr}',
      prefix: '$majorMinor.',
    );
    if (quickVersion != null) return quickVersion;

    final listResult = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv install --list'],
      timeout: const Duration(seconds: 15),
      tag: 'plugin_lifecycle.pyenv_list',
      environment: proxyEnv,
    );
    if (listResult.exitCode != 0) return null;
    final versions = _extractStablePyenvVersions(
      listResult.stdout.toString(),
      prefix: '$majorMinor.',
    );
    if (versions.isEmpty) return null;
    versions.sort(compareSemanticVersions);
    return versions.last;
  }

  Future<String?> _queryLatestHomebrewVersion(String formula) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}brew info --json=v2 $formula'],
      timeout: const Duration(seconds: 10),
      tag: 'plugin_lifecycle.brew_info',
      environment: _proxyEnv(),
    );
    if (result.exitCode != 0) return null;
    try {
      final decoded = jsonDecode(result.stdout.toString());
      return homebrewStableVersionFromDecoded(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<PluginOperationResult> installNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测可用的包管理器…');

    if (await _isNvmAvailable()) {
      onProgress?.call('使用 nvm 安装 Node.js…');
      final result = await _runNvmCommand(
        'nvm install node && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final version = _extractNodeVersion(result.stdout);
        if (version != null) {
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 nvm 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('fnm')) {
      onProgress?.call('使用 fnm 安装 Node.js LTS…');
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 fnm 安装',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew 安装 Node.js…');
      final result = await _runWithProgress(
        'brew',
        ['install', 'node'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Node.js $version 已通过 Homebrew 安装',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Node.js 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器 (nvm / fnm / brew)。请手动安装 Node.js: https://nodejs.org',
    );
  }

  Future<PluginOperationResult> installPython({
    void Function(String line)? onProgress,
  }) async {
    if (await _isPyenvAvailable()) {
      onProgress?.call('检测到 pyenv，准备安装 Python…');
      final latest = await _queryLatestPyenvPatch('3.12.0') ?? '3.12.11';
      final result = await _runPythonShellCommand(
        'pyenv install -s $latest && pyenv global $latest && python3 --version',
        onProgress: onProgress,
        timeout: const Duration(minutes: 12),
      );
      if (result.exitCode == 0) {
        final version =
            _extractPythonVersion('${result.stdout}\n${result.stderr}') ??
            latest;
        onProgress?.call('Python $version 安装成功');
        return PluginOperationResult(
          success: true,
          message: 'Python $version 已通过 pyenv 安装',
          newVersion: version,
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pyenv 安装失败: ${result.stderr}',
      );
    }

    if (await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew 安装 Python…');
      final result = await _runWithProgress(
        'brew',
        ['install', 'python'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 8),
      );
      if (result.exitCode == 0) {
        final versionResult = await runTrackedProcessOrFailed(
          _pickShell(),
          ['-c', '${_pythonShellPrefix()}python3 --version'],
          timeout: _pluginLifecycleVerifyTimeout,
          tag: 'plugin_lifecycle.python_install_verify',
        );
        final version = _extractPythonVersion(
          '${versionResult.stdout}\n${versionResult.stderr}',
        );
        if (version != null) {
          onProgress?.call('Python $version 安装成功');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 Homebrew 安装',
            newVersion: version,
          );
        }
        return const PluginOperationResult(
          success: true,
          message: 'Python 已通过 Homebrew 安装',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 Python 失败: ${result.stderr}',
      );
    }

    return const PluginOperationResult(
      success: false,
      message:
          '未找到可自动管理 Python 的包管理器（pyenv / brew）。请先安装 pyenv 或 Homebrew，或手动安装 Python。',
    );
  }

  Future<PluginOperationResult> installPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时，请先安装 Python。',
      );
    }

    final existingVersion = await _readPipVersion(context.executablePath);
    if (existingVersion != null &&
        context.source == _PythonRuntimeSource.homebrew) {
      onProgress?.call('检测到 Homebrew 管理的 pip，跳过插件内自升级。');
      return PluginOperationResult(
        success: true,
        message: '当前 pip 由 Homebrew Python 管理，请通过 Homebrew 更新对应 Python。',
        newVersion: existingVersion,
      );
    }

    onProgress?.call('正在引导 pip…');
    final ensureResult = await _runBoundPythonCommand(
      context.executablePath,
      ['-m', 'ensurepip', '--upgrade'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (ensureResult.exitCode != 0) {
      final ensureMessage = ensureResult.stderr.isNotEmpty
          ? ensureResult.stderr
          : ensureResult.stdout;
      if (_isExternallyManagedPipError(ensureMessage)) {
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pip 引导失败: $ensureMessage',
      );
    }

    if (context.source == _PythonRuntimeSource.pyenv) {
      onProgress?.call('正在升级 pip…');
      final upgradeResult = await _runBoundPythonCommand(
        context.executablePath,
        ['-m', 'pip', 'install', '--upgrade', 'pip'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 8),
      );
      if (upgradeResult.exitCode != 0) {
        final upgradeMessage = upgradeResult.stderr.isNotEmpty
            ? upgradeResult.stderr
            : upgradeResult.stdout;
        if (_isExternallyManagedPipError(upgradeMessage)) {
          return PluginOperationResult(
            success: false,
            message: _pipManagedEnvironmentMessage(context),
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pip 升级失败: $upgradeMessage',
        );
      }
    }

    final version = await _readPipVersion(context.executablePath);
    if (version == null) {
      return const PluginOperationResult(
        success: false,
        message: 'pip 安装后验证失败',
      );
    }
    onProgress?.call('pip $version 安装成功');
    return PluginOperationResult(
      success: true,
      message: 'pip $version 已就绪',
      newVersion: version,
    );
  }

  Future<PluginOperationResult> installPlaywright({
    void Function(String line)? onProgress,
  }) async {
    final nodeCheck = await runTrackedProcessOrFailed('node', [
      '--version',
    ], timeout: _pluginLifecycleVerifyTimeout);
    if (nodeCheck.exitCode != 0) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先安装 Node.js',
      );
    }
    onProgress?.call('正在安装 Playwright…');
    final installResult = await _runWithProgress(
      'npm',
      ['install', '-g', 'playwright'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );
    if (installResult.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'npm install playwright 失败: ${installResult.stderr}',
      );
    }
    onProgress?.call('正在安装 Playwright 浏览器…');
    final browserInstall = await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    if (browserInstall.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Playwright 浏览器安装失败: ${_processErrorMessage(browserInstall)}',
      );
    }
    final verify = await runTrackedProcessOrFailed('npx', [
      'playwright',
      '--version',
    ], timeout: const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = _normalizePlaywrightVersion(verify.stdout);
      onProgress?.call('Playwright $version 安装成功');
      return PluginOperationResult(
        success: true,
        message: 'Playwright $version 已安装',
        newVersion: version,
      );
    }
    return const PluginOperationResult(
      success: false,
      message: 'Playwright 安装后验证失败',
    );
  }

  Future<PluginOperationResult> installHermesAgent({
    void Function(String line)? onProgress,
  }) => _installOrUpdateNpmGlobalPackage(
    packageName: _hermesAgentNpmPackage,
    label: 'Hermes Agent',
    verifyCommands: const <String>[
      _hermesAgentPrimaryCommand,
      _hermesAgentFallbackCommand,
    ],
    onProgress: onProgress,
  );

  Future<PluginOperationResult> _installBrewFormula({
    required String formula,
    required String label,
    required String verifyCommand,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动安装 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 安装 $label…');
    final result = await _runWithProgress(
      'brew',
      ['install', formula],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 安装 $label 失败: ${_processErrorMessage(result)}',
      );
    }
    final verify = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}command -v $verifyCommand'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.verify.$verifyCommand',
    );
    onProgress?.call('$label 安装完成');
    return PluginOperationResult(
      success: true,
      message: verify.exitCode == 0
          ? '$label 已安装：${verify.stdout.toString().trim()}'
          : '$label 已通过 Homebrew 安装；如命令不可见，请检查 shell PATH。',
    );
  }

  Future<PluginOperationResult> _updateBrewFormula({
    required String formula,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动更新 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 更新 $label…');
    final result = await _runWithProgress(
      'brew',
      ['upgrade', formula],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (result.exitCode == 0 ||
        _processErrorMessage(result).contains('already installed') ||
        _processErrorMessage(result).contains('not outdated')) {
      onProgress?.call('$label 更新完成');
      return PluginOperationResult(success: true, message: '$label 已更新');
    }
    return PluginOperationResult(
      success: false,
      message: 'Homebrew 更新 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _uninstallBrewFormula({
    required String formula,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('brew')) {
      return PluginOperationResult(
        success: false,
        message: '未找到 Homebrew，无法自动卸载 $label。',
      );
    }
    onProgress?.call('使用 Homebrew 卸载 $label…');
    final result = await _runWithProgress(
      'brew',
      ['uninstall', formula],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (result.exitCode == 0) {
      onProgress?.call('$label 已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: 'Homebrew 卸载 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _installOrUpdatePythonPackage({
    required String packageName,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python / pip 环境…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return PluginOperationResult(
        success: false,
        message: '$label 需要 Python，请先安装 Python。',
      );
    }
    final pipVersion = await _readPipVersion(context.executablePath);
    if (pipVersion == null) {
      return PluginOperationResult(
        success: false,
        message: '$label 需要 pip，请先安装 pip。',
      );
    }
    onProgress?.call('通过 pip 安装/更新 $label…');
    final result = await _runBoundPythonCommand(
      context.executablePath,
      ['-m', 'pip', 'install', '--upgrade', packageName],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
    );
    if (result.exitCode != 0) {
      final message = _processErrorMessage(result);
      if (_isExternallyManagedPipError(message)) {
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'pip 安装 $label 失败: $message',
      );
    }
    onProgress?.call('$label 已就绪');
    return PluginOperationResult(success: true, message: '$label 已安装或更新');
  }

  Future<PluginOperationResult> _uninstallPythonPackage({
    required String packageName,
    required String label,
    void Function(String line)? onProgress,
  }) async {
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return PluginOperationResult(
        success: false,
        message: '未检测到 Python，无法卸载 $label。',
      );
    }
    onProgress?.call('通过 pip 卸载 $label…');
    final result = await _runBoundPythonCommand(context.executablePath, [
      '-m',
      'pip',
      'uninstall',
      '-y',
      packageName,
    ], onProgress: onProgress);
    if (result.exitCode == 0) {
      onProgress?.call('$label 已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: 'pip 卸载 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _installOrUpdateNpmGlobalPackage({
    required String packageName,
    required String label,
    required List<String> verifyCommands,
    void Function(String line)? onProgress,
  }) async {
    final environment = _npmGlobalPackageEnv();
    final nodeCheck = await _runManagedToolchainCommand(
      'node',
      ['--version'],
      environment: environment,
      tag: 'plugin_lifecycle.node_check.$packageName',
    );
    if (nodeCheck.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: '$label 依赖 Node.js，请先安装 Node.js。',
      );
    }
    final npmCheck = await _runManagedToolchainCommand(
      'npm',
      ['--version'],
      environment: environment,
      tag: 'plugin_lifecycle.npm_check.$packageName',
    );
    if (npmCheck.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: '$label 依赖 npm，请先确认 npm 已随 Node.js 安装并可执行。',
      );
    }
    final preexisting = await _verifyAnyCommandVersion(
      verifyCommands,
      environment: environment,
    );
    onProgress?.call('通过 npm 安装/更新 $label…');
    var result = await _runManagedToolchainCommandWithProgress(
      'npm',
      ['install', '-g', '$packageName@latest'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 6),
      environment: environment,
    );
    String? tlsBundle;
    var tlsRetryAttempted = false;
    final firstOutput = _combinedProcessOutput(result);
    if (result.exitCode != 0 &&
        pluginLifecycleOutputHasPyPiTlsFailure(firstOutput)) {
      tlsBundle = await _detectTlsBundleAfterFailure(firstOutput);
      if (tlsBundle != null) {
        tlsRetryAttempted = true;
        onProgress?.call('检测到 PyPI TLS 证书校验失败，使用 CA bundle 重试：$tlsBundle');
        result = await _runManagedToolchainCommandWithProgress(
          'npm',
          ['install', '-g', '$packageName@latest'],
          onProgress: onProgress,
          timeout: const Duration(minutes: 6),
          environment: _npmGlobalPackageEnv(tlsBundle: tlsBundle),
        );
      }
    }
    if (result.exitCode != 0) {
      if (preexisting == null) {
        await _cleanupFailedNpmGlobalInstall(
          packageName: packageName,
          label: label,
          environment: _npmGlobalPackageEnv(tlsBundle: tlsBundle),
          onProgress: onProgress,
        );
      }
      final output = tlsRetryAttempted
          ? '首次输出：\n$firstOutput\n\n重试输出：\n${_combinedProcessOutput(result)}'
          : _combinedProcessOutput(result);
      return PluginOperationResult(
        success: false,
        message: packageName == _hermesAgentNpmPackage
            ? hermesAgentNpmFailureMessage(
                label: label,
                output: output,
                tlsRetryAttempted: tlsRetryAttempted,
                tlsBundle: tlsBundle,
              )
            : 'npm 安装 $label 失败: ${_processErrorMessage(result)}',
      );
    }

    final verified = await _verifyAnyCommandVersion(
      verifyCommands,
      environment: _npmGlobalPackageEnv(tlsBundle: tlsBundle),
    );
    if (verified == null) {
      return PluginOperationResult(
        success: false,
        message: '$label 安装后验证失败：未找到可执行命令。',
      );
    }
    final versionText = verified.version == null ? '' : ' ${verified.version}';
    onProgress?.call('$label$versionText 已就绪');
    return PluginOperationResult(
      success: true,
      message: '$label$versionText 已安装或更新',
      newVersion: verified.version,
    );
  }

  Future<PluginOperationResult> _uninstallNpmGlobalPackage({
    required String packageName,
    required String label,
    List<String> verifyCommands = const <String>[],
    void Function(String line)? onProgress,
  }) async {
    final environment = _npmGlobalPackageEnv();
    final npmCheck = await _runManagedToolchainCommand(
      'npm',
      ['--version'],
      environment: environment,
      tag: 'plugin_lifecycle.npm_check.$packageName',
    );
    if (npmCheck.exitCode != 0) {
      if (verifyCommands.isNotEmpty &&
          await _verifyAnyCommandVersion(
                verifyCommands,
                environment: environment,
              ) ==
              null) {
        return PluginOperationResult(
          success: true,
          message: '$label 未检测到可执行命令，无需卸载。',
        );
      }
      return PluginOperationResult(
        success: false,
        message: '未检测到 npm，无法安全卸载 $label。',
      );
    }
    onProgress?.call('通过 npm 卸载 $label…');
    final result = await _runManagedToolchainCommandWithProgress(
      'npm',
      ['uninstall', '-g', packageName],
      onProgress: onProgress,
      timeout: const Duration(minutes: 4),
      environment: environment,
    );
    if (result.exitCode == 0) {
      onProgress?.call('$label 已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    if (verifyCommands.isNotEmpty &&
        await _verifyAnyCommandVersion(
              verifyCommands,
              environment: environment,
            ) ==
            null) {
      onProgress?.call('$label 可执行命令已不存在，视为已卸载');
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: 'npm 卸载 $label 失败: ${_processErrorMessage(result)}',
    );
  }

  Future<({String command, String? version})?> _verifyAnyCommandVersion(
    List<String> commands, {
    Map<String, String>? environment,
  }) async {
    final effectiveEnvironment = environment ?? _proxyEnv();
    for (final command in commands) {
      final commandPath = await _resolveManagedToolchainCommandPath(
        command,
        environment: effectiveEnvironment,
      );
      if (commandPath == null) continue;
      final result = await _runManagedToolchainCommand(
        commandPath,
        ['--version'],
        environment: effectiveEnvironment,
        tag: 'plugin_lifecycle.verify.$command',
      );
      if (result.exitCode != 0) continue;
      return (
        command: command,
        version: _extractFirstSemver('${result.stdout}\n${result.stderr}'),
      );
    }
    return null;
  }

  Future<String?> _detectTlsBundleAfterFailure(String output) async {
    if (!pluginLifecycleOutputHasPyPiTlsFailure(output)) return null;
    final certifi = await _probeCertifiBundle();
    if (certifi != null && File(certifi).existsSync()) return certifi;
    for (final candidate in const <String>[
      '/etc/ssl/cert.pem',
      '/private/etc/ssl/cert.pem',
      '/etc/ssl/certs/ca-certificates.crt',
      '/opt/homebrew/etc/openssl@3/cert.pem',
      '/usr/local/etc/openssl@3/cert.pem',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<String?> _probeCertifiBundle() async {
    for (final executable in const <String>['python3', 'python']) {
      try {
        final result = await _runManagedToolchainCommand(
          executable,
          const <String>['-c', 'import certifi; print(certifi.where())'],
          timeout: const Duration(seconds: 2),
          environment: _proxyEnv(),
          tag: 'plugin_lifecycle.probe_certifi.$executable',
        );
        if (result.exitCode != 0) continue;
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty) return path;
      } catch (error, stack) {
        silentLog(
          'plugin_lifecycle',
          'probe certifi bundle $executable',
          error,
          stack,
        );
      }
    }
    return null;
  }

  Future<void> _cleanupFailedNpmGlobalInstall({
    required String packageName,
    required String label,
    required Map<String, String> environment,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('清理未完成的 $label npm 安装…');
    final cleanup = await _runManagedToolchainCommandWithProgress(
      'npm',
      ['uninstall', '-g', packageName],
      onProgress: onProgress,
      timeout: const Duration(minutes: 2),
      environment: environment,
    );
    if (cleanup.exitCode == 0) {
      onProgress?.call('$label 半安装残留已清理');
      return;
    }
    silentLog(
      'plugin_lifecycle',
      'cleanup failed npm install',
      _processErrorMessage(cleanup),
    );
  }

  String _androidReverseToolRoot() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.openhand/android_reverse_tools';
  }

  String _androidReverseToolBinDir() => '${_androidReverseToolRoot()}/bin';

  Future<PluginOperationResult> _installOrUpdateGitPythonTool({
    required String label,
    required String repoUrl,
    required String directoryName,
    required String shimName,
    required String entrypoint,
    required List<String> pipPackages,
    String? macosBrewPackages,
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在安装/更新 $label…');
    final root = _androidReverseToolRoot();
    final target = '$root/$directoryName';
    final binDir = _androidReverseToolBinDir();
    final shimPath = '$binDir/$shimName';
    final entrypointPath = '$target/$entrypoint';
    final shim =
        '#!/usr/bin/env bash\n'
        'exec python3 ${_pluginShellQuote(entrypointPath)} "\$@"\n';
    final brewStep = macosBrewPackages == null || macosBrewPackages.isEmpty
        ? ''
        : '''
if [ "\$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  brew install $macosBrewPackages || true
fi
''';
    final pipStep = pipPackages.isEmpty
        ? ''
        : 'python3 -m pip install --user --upgrade ${pipPackages.map(_pluginShellQuote).join(' ')}';
    final script =
        '''
set -euo pipefail
if ! command -v git >/dev/null 2>&1; then echo "git not found" >&2; exit 127; fi
if ! command -v python3 >/dev/null 2>&1; then echo "python3 not found" >&2; exit 127; fi
mkdir -p ${_pluginShellQuote(binDir)}
$brewStep
if [ -d ${_pluginShellQuote(target)}/.git ]; then
  git -C ${_pluginShellQuote(target)} pull --ff-only
else
  rm -rf ${_pluginShellQuote(target)}
  git clone --depth 1 ${_pluginShellQuote(repoUrl)} ${_pluginShellQuote(target)}
fi
$pipStep
printf %s ${_pluginShellQuote(shim)} > ${_pluginShellQuote(shimPath)}
chmod +x ${_pluginShellQuote(shimPath)}
printf '%s\\n' ${_pluginShellQuote('$label shim: $shimPath')}
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: const Duration(minutes: 12),
      environment: _proxyEnv(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: '$label 已安装或更新：$shimPath',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '$label 安装失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _uninstallOpenHandTool({
    required String label,
    required String directoryName,
    required String shimName,
    void Function(String line)? onProgress,
  }) async {
    final root = _androidReverseToolRoot();
    final script =
        '''
set -euo pipefail
rm -rf ${_pluginShellQuote('$root/$directoryName')}
rm -f ${_pluginShellQuote('${_androidReverseToolBinDir()}/$shimName')}
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: const Duration(seconds: 20),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(success: true, message: '$label 已卸载');
    }
    return PluginOperationResult(
      success: false,
      message: '$label 卸载失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> _installOrUpdateAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在下载 Anything Analyzer 最新发布包…');
    final root = _androidReverseToolRoot();
    final target = '$root/anything-analyzer';
    final binDir = _androidReverseToolBinDir();
    final shimPath = '$binDir/anything-analyzer';
    final script =
        '''
set -euo pipefail
if ! command -v curl >/dev/null 2>&1; then echo "curl not found" >&2; exit 127; fi
if ! command -v python3 >/dev/null 2>&1; then echo "python3 not found" >&2; exit 127; fi
mkdir -p ${_pluginShellQuote(target)} ${_pluginShellQuote(binDir)}
META="\$(curl -fsSL https://api.github.com/repos/Mouseww/anything-analyzer/releases/latest)"
ASSET="\$(printf '%s' "\$META" | python3 -c '
import json, platform, sys
data = json.load(sys.stdin)
assets = data.get("assets", [])
system = platform.system().lower()
machine = platform.machine().lower()
patterns = []
if system == "darwin":
    if "arm" in machine or "aarch" in machine:
        patterns += ["arm64.dmg", "arm64.zip"]
    patterns += ["x64.dmg", "x64.zip", "mac"]
elif system == "linux":
    patterns += [".AppImage", "linux"]
elif system == "windows":
    patterns += [".exe", "Setup"]
for pattern in patterns:
    for asset in assets:
        name = asset.get("name", "")
        if pattern.lower() in name.lower():
            print(asset.get("browser_download_url", ""))
            raise SystemExit(0)
raise SystemExit(3)
')"
if [ -z "\$ASSET" ]; then echo "No compatible Anything Analyzer release asset found" >&2; exit 3; fi
NAME="\${ASSET##*/}"
PKG="${_pluginShellQuote(target)}/\$NAME"
curl -fL "\$ASSET" -o "\$PKG"
rm -rf ${_pluginShellQuote(target)}/current
mkdir -p ${_pluginShellQuote(target)}/current
case "\$NAME" in
  *.dmg)
    MOUNT="\$(hdiutil attach -nobrowse -readonly "\$PKG" | awk '/\\/Volumes\\// {for (i=1;i<=NF;i++) if (\$i ~ /^\\/Volumes\\//) {print \$i; exit}}')"
    APP="\$(find "\$MOUNT" -maxdepth 2 -name '*.app' -type d | head -1)"
    cp -R "\$APP" ${_pluginShellQuote(target)}/current/
    hdiutil detach "\$MOUNT" >/dev/null
    ;;
  *.zip)
    if ! command -v unzip >/dev/null 2>&1; then echo "unzip not found" >&2; exit 127; fi
    unzip -q "\$PKG" -d ${_pluginShellQuote(target)}/current
    ;;
  *.AppImage)
    cp "\$PKG" ${_pluginShellQuote(target)}/current/Anything-Analyzer.AppImage
    chmod +x ${_pluginShellQuote(target)}/current/Anything-Analyzer.AppImage
    ;;
  *.exe)
    cp "\$PKG" ${_pluginShellQuote(target)}/current/
    ;;
  *)
    echo "Unsupported asset: \$NAME" >&2
    exit 4
    ;;
esac
cat > ${_pluginShellQuote(shimPath)} <<'SHIM'
#!/usr/bin/env bash
ROOT="\$HOME/.openhand/android_reverse_tools/anything-analyzer/current"
APP="\$(find "\$ROOT" -maxdepth 2 -name '*.app' -type d 2>/dev/null | head -1)"
if [ -n "\$APP" ]; then
  exec open -a "\$APP" --args "\$@"
fi
APPIMAGE="\$(find "\$ROOT" -maxdepth 2 -name '*.AppImage' -type f 2>/dev/null | head -1)"
if [ -n "\$APPIMAGE" ]; then
  exec "\$APPIMAGE" "\$@"
fi
echo "Anything Analyzer app bundle not found under \$ROOT" >&2
exit 2
SHIM
chmod +x ${_pluginShellQuote(shimPath)}
printf 'asset=%s\\nshim=%s\\n' "\$ASSET" ${_pluginShellQuote(shimPath)}
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
      environment: _proxyEnv(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: 'Anything Analyzer 已安装或更新：$shimPath',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Anything Analyzer 安装失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> installJava({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    verifyCommand: 'java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installFrida({
    void Function(String line)? onProgress,
  }) => _installOrUpdatePythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installMitmproxy({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    verifyCommand: 'mitmdump',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installApktool({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    verifyCommand: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installJadx({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    verifyCommand: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installRadare2({
    void Function(String line)? onProgress,
  }) => _installBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    verifyCommand: 'r2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installBlutter({
    void Function(String line)? onProgress,
  }) => _installOrUpdateGitPythonTool(
    label: 'blutter',
    repoUrl: 'https://github.com/worawit/blutter.git',
    directoryName: 'blutter',
    shimName: 'blutter',
    entrypoint: 'blutter.py',
    pipPackages: const <String>['pyelftools', 'requests'],
    macosBrewPackages: 'cmake ninja pkg-config icu4c capstone',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installDoldrums({
    void Function(String line)? onProgress,
  }) => _installOrUpdateGitPythonTool(
    label: 'Doldrums',
    repoUrl: 'https://github.com/rscloura/Doldrums.git',
    directoryName: 'doldrums',
    shimName: 'doldrums',
    entrypoint: 'src/main.py',
    pipPackages: const <String>['pyelftools'],
    onProgress: onProgress,
  );

  Future<PluginOperationResult> installAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _installOrUpdateAnythingAnalyzer(onProgress: onProgress);

  Future<PluginOperationResult> installDocker({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Docker…');
    if (await _isExecutableAvailable('docker')) {
      if (await _isDockerDaemonAvailable()) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker CLI 与 daemon 已就绪。',
        );
      }
      if (Platform.isMacOS &&
          (Directory('/Applications/Docker.app').existsSync() ||
              Directory(
                '${Platform.environment['HOME'] ?? ''}/Applications/Docker.app',
              ).existsSync())) {
        onProgress?.call('Docker Desktop 已安装，正在尝试启动…');
        await _runWithProgress(
          'open',
          ['-a', 'Docker'],
          onProgress: onProgress,
          timeout: const Duration(seconds: 20),
        );
        for (var attempt = 0; attempt < 24; attempt++) {
          if (await _isDockerDaemonAvailable()) {
            return const PluginOperationResult(
              success: true,
              message: 'Docker Desktop 已启动，daemon 可用。',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 5));
          onProgress?.call('等待 Docker daemon 启动… ${attempt + 1}/24');
        }
      }
      return const PluginOperationResult(
        success: false,
        message: 'docker CLI 已安装，但 daemon 未运行。请启动 Docker Desktop 后重新扫描。',
      );
    }

    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 安装 Docker Desktop…');
      final result = await _runWithProgress(
        'brew',
        ['install', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 15),
      );
      if (result.exitCode != 0) {
        return PluginOperationResult(
          success: false,
          message: 'Docker Desktop 安装失败: ${_processErrorMessage(result)}',
        );
      }
      onProgress?.call('Docker Desktop 已安装，请根据系统提示完成首次启动授权。');
      return const PluginOperationResult(
        success: true,
        message: 'Docker Desktop 已安装。首次使用可能需要手动打开并完成授权。',
      );
    }

    if (Platform.isWindows) {
      return const PluginOperationResult(
        success: false,
        message:
            'Windows 暂不支持静默安装 Docker。请安装 Docker Desktop: https://www.docker.com/products/docker-desktop/',
      );
    }
    if (Platform.isLinux) {
      return const PluginOperationResult(
        success: false,
        message:
            'Linux 暂不执行自动安装 Docker。请按发行版安装 docker engine 与 compose plugin，并确认当前用户可访问 docker daemon。',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '当前平台不支持自动安装 Docker。',
    );
  }

  Future<PluginOperationResult> installQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return const PluginOperationResult(
        success: false,
        message: 'Qdrant 依赖 Docker，请先安装 Docker。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
mkdir -p ${_pluginShellQuote(dataDir)}
docker pull ${_pluginShellQuote(_qdrantImage)}
if docker inspect ${_pluginShellQuote(_qdrantContainerName)} >/dev/null 2>&1; then
  LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' ${_pluginShellQuote(_qdrantContainerName)} 2>/dev/null || true)"
  if [ "\$LABEL" != "true" ]; then
    echo "Existing container $_qdrantContainerName is not managed by OpenHand" >&2
    exit 3
  fi
  docker start ${_pluginShellQuote(_qdrantContainerName)} >/dev/null
else
  docker run -d \\
    --name ${_pluginShellQuote(_qdrantContainerName)} \\
    --label openhand.managed=true \\
    --label com.openhand.managed=true \\
    --restart unless-stopped \\
    -p $_qdrantRestPort:6333 \\
    -p $_qdrantGrpcPort:6334 \\
    -v ${_pluginShellQuote(dataDir)}:/qdrant/storage \\
    ${_pluginShellQuote(_qdrantImage)}
fi
for i in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:$_qdrantRestPort/ >/dev/null 2>&1; then
    docker ps --filter name=^/$_qdrantContainerName\$ --format 'container={{.ID}} image={{.Image}} status={{.Status}}'
    exit 0
  fi
  sleep 1
done
echo "Qdrant health endpoint did not become ready" >&2
exit 4
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
      environment: _proxyEnv(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: 'Qdrant 已启动，数据目录：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 安装/启动失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> updateNodeJs({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Node.js 安装方式…');
    final whichResult = await runTrackedProcessOrFailed('which', [
      'node',
    ], timeout: _pluginLifecycleProbeTimeout);
    final nodePath = whichResult.exitCode == 0
        ? whichResult.stdout.toString().trim()
        : '';

    final isNvm = nodePath.contains('.nvm/');
    final isFnm = nodePath.contains('.fnm/') || nodePath.contains('/fnm/');
    final isVolta = nodePath.contains('.volta/');
    final isBrew =
        nodePath.contains('/homebrew/') ||
        nodePath.contains('/Cellar/') ||
        nodePath.startsWith('/opt/homebrew/') ||
        nodePath.startsWith('/usr/local/bin/');

    if (isNvm) {
      onProgress?.call('检测到 nvm 管理的 Node.js，使用 nvm 更新…');
      final result = await _runNvmCommand(
        'nvm install node --reinstall-packages-from=current && nvm alias default node && node --version',
        onProgress: onProgress,
      );
      if (result.exitCode == 0) {
        final version = _extractNodeVersion(result.stdout);
        if (version != null) {
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 nvm 更新到 $version',
            newVersion: version,
          );
        }
        onProgress?.call('Node.js 更新完成');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 nvm 更新',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'nvm 更新失败: ${result.stderr}',
      );
    }

    if (isFnm) {
      onProgress?.call('检测到 fnm 管理的 Node.js，使用 fnm 更新…');
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 fnm 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'fnm 更新失败: ${result.stderr}',
      );
    }

    if (isVolta) {
      onProgress?.call('检测到 volta 管理的 Node.js，使用 volta 更新…');
      final result = await _runWithProgress(
        'volta',
        ['install', 'node@latest'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 volta 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'volta 更新失败: ${result.stderr}',
      );
    }

    if (isBrew) {
      onProgress?.call('检测到 Homebrew 管理的 Node.js，使用 brew 更新…');
      final result = await _runWithProgress(
        'brew',
        ['upgrade', 'node'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          onProgress?.call('Node.js 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已通过 Homebrew 更新到 $version',
            newVersion: version,
          );
        }
      }
      return PluginOperationResult(
        success: false,
        message: 'Homebrew 更新失败: ${result.stderr}',
      );
    }

    onProgress?.call('未能确定安装方式，尝试可用的包管理器…');
    if (await _isExecutableAvailable('fnm')) {
      final result = await _runWithProgress(
        'fnm',
        ['install', '--lts'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) {
        await runTrackedProcessOrFailed('fnm', [
          'default',
          'lts-latest',
        ], timeout: const Duration(seconds: 10));
        final verify = await runTrackedProcessOrFailed('node', [
          '--version',
        ], timeout: _pluginLifecycleVerifyTimeout);
        if (verify.exitCode == 0) {
          final version = verify.stdout.toString().trim();
          return PluginOperationResult(
            success: true,
            message: 'Node.js 已更新到 $version',
            newVersion: version,
          );
        }
      }
    }
    return const PluginOperationResult(
      success: false,
      message:
          '未找到可用的包管理器来更新 Node.js。\n'
          '请根据您的安装方式手动更新：\n'
          '  · nvm: nvm install --lts\n'
          '  · fnm: fnm install --lts\n'
          '  · brew: brew upgrade node\n'
          '  · volta: volta install node@latest',
    );
  }

  Future<PluginOperationResult> updatePython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final currentVersion = context.version ?? context.pyenvVersion;
        if (currentVersion == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        final latest = await _queryLatestPyenvPatch(currentVersion);
        if (latest == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法查询 pyenv 的最新 Python 版本。',
          );
        }
        if (latest == currentVersion || latest == context.pyenvVersion) {
          return PluginOperationResult(
            success: true,
            message: 'Python 已是最新版本 $currentVersion',
            newVersion: currentVersion,
          );
        }
        onProgress?.call('使用 pyenv 将 Python 更新到 $latest…');
        final result = await _runPythonShellCommand(
          'pyenv install -s $latest && pyenv global $latest && python3 --version',
          onProgress: onProgress,
          timeout: const Duration(minutes: 12),
        );
        if (result.exitCode == 0) {
          final version =
              _extractPythonVersion('${result.stdout}\n${result.stderr}') ??
              latest;
          onProgress?.call('Python 已更新到 $version');
          return PluginOperationResult(
            success: true,
            message: 'Python 已通过 pyenv 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 更新失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        final targetVersion = await _queryLatestHomebrewVersion(formula);
        onProgress?.call('使用 Homebrew 更新 Python…');
        final result = await _runWithProgress(
          'brew',
          ['upgrade', formula],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          final version =
              await _readPythonVersion(context.executablePath) ?? targetVersion;
          onProgress?.call(
            version == null ? 'Python 更新完成' : 'Python 已更新到 $version',
          );
          return PluginOperationResult(
            success: true,
            message: version == null
                ? 'Python 已通过 Homebrew 更新'
                : 'Python 已通过 Homebrew 更新到 $version',
            newVersion: version,
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 更新 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动升级，请手动维护。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动升级，请手动维护。',
        );
    }
  }

  Future<PluginOperationResult> updatePip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 运行时…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        onProgress?.call('正在升级 pip…');
        final result = await _runBoundPythonCommand(
          context.executablePath,
          ['-m', 'pip', 'install', '--upgrade', 'pip'],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode != 0) {
          final updateMessage = result.stderr.isNotEmpty
              ? result.stderr
              : result.stdout;
          if (_isExternallyManagedPipError(updateMessage)) {
            return PluginOperationResult(
              success: false,
              message: _pipManagedEnvironmentMessage(context),
            );
          }
          return PluginOperationResult(
            success: false,
            message: 'pip 升级失败: $updateMessage',
          );
        }
        final version = await _readPipVersion(context.executablePath);
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: 'pip 升级后验证失败',
          );
        }
        onProgress?.call('pip 已更新到 $version');
        return PluginOperationResult(
          success: true,
          message: 'pip 已更新到 $version',
          newVersion: version,
        );
      case _PythonRuntimeSource.homebrew:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.system:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
      case _PythonRuntimeSource.unknown:
        return PluginOperationResult(
          success: false,
          message: _pipManagedEnvironmentMessage(context),
        );
    }
  }

  Future<PluginOperationResult> updatePlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在更新 Playwright…');
    final result = await _runWithProgress(
      'npm',
      ['update', '-g', 'playwright'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );
    if (result.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: '更新失败: ${result.stderr}',
      );
    }
    onProgress?.call('正在更新 Playwright 浏览器…');
    final browserInstall = await _runWithProgress(
      'npx',
      ['playwright', 'install'],
      onProgress: onProgress,
      timeout: const Duration(minutes: 10),
    );
    if (browserInstall.exitCode != 0) {
      return PluginOperationResult(
        success: false,
        message: 'Playwright 浏览器更新失败: ${_processErrorMessage(browserInstall)}',
      );
    }
    final verify = await runTrackedProcessOrFailed('npx', [
      'playwright',
      '--version',
    ], timeout: const Duration(seconds: 15));
    if (verify.exitCode == 0) {
      final version = _normalizePlaywrightVersion(verify.stdout);
      return PluginOperationResult(
        success: true,
        message: 'Playwright 已更新到 $version',
        newVersion: version,
      );
    }
    return const PluginOperationResult(
      success: false,
      message: 'Playwright 更新后验证失败',
    );
  }

  Future<PluginOperationResult> updateHermesAgent({
    void Function(String line)? onProgress,
  }) => _installOrUpdateNpmGlobalPackage(
    packageName: _hermesAgentNpmPackage,
    label: 'Hermes Agent',
    verifyCommands: const <String>[
      _hermesAgentPrimaryCommand,
      _hermesAgentFallbackCommand,
    ],
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateJava({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateFrida({
    void Function(String line)? onProgress,
  }) => _installOrUpdatePythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateMitmproxy({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateApktool({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateJadx({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateRadare2({
    void Function(String line)? onProgress,
  }) => _updateBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> updateBlutter({
    void Function(String line)? onProgress,
  }) => installBlutter(onProgress: onProgress);

  Future<PluginOperationResult> updateDoldrums({
    void Function(String line)? onProgress,
  }) => installDoldrums(onProgress: onProgress);

  Future<PluginOperationResult> updateAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _installOrUpdateAnythingAnalyzer(onProgress: onProgress);

  Future<PluginOperationResult> updateDocker({
    void Function(String line)? onProgress,
  }) async {
    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 更新 Docker Desktop…');
      final result = await _runWithProgress(
        'brew',
        ['upgrade', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 15),
      );
      final message = _processErrorMessage(result);
      if (result.exitCode == 0 ||
          message.contains('already installed') ||
          message.contains('not outdated')) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker Desktop 已更新或已经是最新版本。',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Docker Desktop 更新失败: $message',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '无法自动更新 Docker。请通过 Docker Desktop 或系统包管理器更新。',
    );
  }

  Future<PluginOperationResult> updateQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，请先启动 Docker。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
if docker inspect ${_pluginShellQuote(_qdrantContainerName)} >/dev/null 2>&1; then
  LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' ${_pluginShellQuote(_qdrantContainerName)} 2>/dev/null || true)"
  if [ "\$LABEL" != "true" ]; then
    echo "Existing container $_qdrantContainerName is not managed by OpenHand" >&2
    exit 3
  fi
  docker stop ${_pluginShellQuote(_qdrantContainerName)} >/dev/null || true
  docker rm ${_pluginShellQuote(_qdrantContainerName)} >/dev/null || true
fi
mkdir -p ${_pluginShellQuote(dataDir)}
docker pull ${_pluginShellQuote(_qdrantImage)}
docker run -d \\
  --name ${_pluginShellQuote(_qdrantContainerName)} \\
  --label openhand.managed=true \\
  --label com.openhand.managed=true \\
  --restart unless-stopped \\
  -p $_qdrantRestPort:6333 \\
  -p $_qdrantGrpcPort:6334 \\
  -v ${_pluginShellQuote(dataDir)}:/qdrant/storage \\
  ${_pluginShellQuote(_qdrantImage)}
for i in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:$_qdrantRestPort/ >/dev/null 2>&1; then
    docker ps --filter name=^/$_qdrantContainerName\$ --format 'container={{.ID}} image={{.Image}} status={{.Status}}'
    exit 0
  fi
  sleep 1
done
echo "Qdrant health endpoint did not become ready" >&2
exit 4
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      timeout: const Duration(minutes: 8),
      environment: _proxyEnv(),
    );
    if (result.exitCode == 0) {
      return const PluginOperationResult(
        success: true,
        message: 'Qdrant 镜像已更新，容器已安全重建并保留数据目录。',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 更新失败: ${_processErrorMessage(result)}',
    );
  }

  Future<PluginOperationResult> uninstallNodeJs({
    required bool playwrightInstalled,
    void Function(String line)? onProgress,
  }) async {
    if (playwrightInstalled) {
      return const PluginOperationResult(
        success: false,
        message: 'Playwright 依赖 Node.js，请先卸载 Playwright',
      );
    }
    onProgress?.call('正在卸载 Node.js…');
    if (await _isExecutableAvailable('brew')) {
      final result = await _runWithProgress('brew', [
        'uninstall',
        'node',
      ], onProgress: onProgress);
      if (result.exitCode == 0) {
        onProgress?.call('Node.js 已卸载');
        return const PluginOperationResult(
          success: true,
          message: 'Node.js 已通过 Homebrew 卸载',
        );
      }
      return PluginOperationResult(
        success: false,
        message: '卸载失败: ${result.stderr}',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '未找到可用的包管理器来卸载 Node.js，请手动卸载',
    );
  }

  Future<PluginOperationResult> uninstallPython({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在检测 Python 安装方式…');
    final context = await _detectPythonRuntimeContext();
    if (context == null) {
      return const PluginOperationResult(
        success: false,
        message: '未检测到可用的 Python 运行时。',
      );
    }

    switch (context.source) {
      case _PythonRuntimeSource.pyenv:
        final version = context.pyenvVersion ?? context.version;
        if (version == null) {
          return const PluginOperationResult(
            success: false,
            message: '无法识别当前 pyenv Python 版本。',
          );
        }
        onProgress?.call('使用 pyenv 卸载 Python $version…');
        final script = StringBuffer()..writeln('pyenv uninstall -f $version');
        final remaining = await _remainingPyenvVersions(excluding: version);
        if (remaining.isNotEmpty) {
          remaining.sort(compareSemanticVersions);
          script.writeln('pyenv global ${remaining.last}');
        } else {
          script.writeln('pyenv global system');
        }
        final result = await _runPythonShellCommand(
          script.toString(),
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python $version 已卸载');
          return PluginOperationResult(
            success: true,
            message: 'Python $version 已通过 pyenv 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'pyenv 卸载失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.homebrew:
        final formula = context.brewFormula ?? 'python';
        onProgress?.call('使用 Homebrew 卸载 Python…');
        final result = await _runWithProgress(
          'brew',
          ['uninstall', formula],
          onProgress: onProgress,
          timeout: const Duration(minutes: 8),
        );
        if (result.exitCode == 0) {
          onProgress?.call('Python 已卸载');
          return const PluginOperationResult(
            success: true,
            message: 'Python 已通过 Homebrew 卸载',
          );
        }
        return PluginOperationResult(
          success: false,
          message: 'Homebrew 卸载 Python 失败: ${result.stderr}',
        );
      case _PythonRuntimeSource.system:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 来自系统环境，暂不支持自动卸载。',
        );
      case _PythonRuntimeSource.unknown:
        return const PluginOperationResult(
          success: false,
          message: '当前 Python 安装来源未知，暂不支持自动卸载。',
        );
    }
  }

  Future<PluginOperationResult> uninstallPip({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('pip 不支持独立卸载');
    return const PluginOperationResult(
      success: false,
      message: 'pip 不支持卸载，仅支持安装与升级。',
    );
  }

  Future<PluginOperationResult> uninstallPlaywright({
    void Function(String line)? onProgress,
  }) async {
    onProgress?.call('正在卸载 Playwright…');
    final result = await _runWithProgress('npm', [
      'uninstall',
      '-g',
      'playwright',
    ], onProgress: onProgress);
    if (result.exitCode == 0) {
      onProgress?.call('Playwright 已卸载');
      return const PluginOperationResult(
        success: true,
        message: 'Playwright 已卸载',
      );
    }
    return PluginOperationResult(
      success: false,
      message: '卸载失败: ${result.stderr}',
    );
  }

  Future<PluginOperationResult> uninstallHermesAgent({
    void Function(String line)? onProgress,
  }) => _uninstallNpmGlobalPackage(
    packageName: _hermesAgentNpmPackage,
    label: 'Hermes Agent',
    verifyCommands: const <String>[
      _hermesAgentPrimaryCommand,
      _hermesAgentFallbackCommand,
    ],
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallJava({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'openjdk',
    label: 'Java',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallFrida({
    void Function(String line)? onProgress,
  }) => _uninstallPythonPackage(
    packageName: 'frida-tools',
    label: 'Frida',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallMitmproxy({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'mitmproxy',
    label: 'mitmproxy',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallApktool({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'apktool',
    label: 'apktool',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallJadx({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'jadx',
    label: 'jadx',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallRadare2({
    void Function(String line)? onProgress,
  }) => _uninstallBrewFormula(
    formula: 'radare2',
    label: 'radare2',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallBlutter({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'blutter',
    directoryName: 'blutter',
    shimName: 'blutter',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallDoldrums({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'Doldrums',
    directoryName: 'doldrums',
    shimName: 'doldrums',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallAnythingAnalyzer({
    void Function(String line)? onProgress,
  }) => _uninstallOpenHandTool(
    label: 'Anything Analyzer',
    directoryName: 'anything-analyzer',
    shimName: 'anything-analyzer',
    onProgress: onProgress,
  );

  Future<PluginOperationResult> uninstallDocker({
    void Function(String line)? onProgress,
  }) async {
    if (Platform.isMacOS && await _isExecutableAvailable('brew')) {
      onProgress?.call('使用 Homebrew Cask 卸载 Docker Desktop…');
      final result = await _runWithProgress(
        'brew',
        ['uninstall', '--cask', 'docker'],
        onProgress: onProgress,
        timeout: const Duration(minutes: 8),
      );
      if (result.exitCode == 0) {
        return const PluginOperationResult(
          success: true,
          message: 'Docker Desktop 已卸载。',
        );
      }
      return PluginOperationResult(
        success: false,
        message: 'Docker Desktop 卸载失败: ${_processErrorMessage(result)}',
      );
    }
    return const PluginOperationResult(
      success: false,
      message: '无法自动卸载 Docker。请通过 Docker Desktop 或系统包管理器卸载。',
    );
  }

  Future<PluginOperationResult> uninstallQdrant({
    void Function(String line)? onProgress,
  }) async {
    if (!await _isExecutableAvailable('docker')) {
      return const PluginOperationResult(
        success: true,
        message: 'docker CLI 不存在，Qdrant 容器无需卸载。',
      );
    }
    if (!await _isDockerDaemonAvailable()) {
      return const PluginOperationResult(
        success: false,
        message: 'Docker daemon 未运行，无法安全检查并卸载 Qdrant 容器。',
      );
    }
    final dataDir = _qdrantDataDirectory();
    final script =
        '''
set -euo pipefail
if ! docker inspect ${_pluginShellQuote(_qdrantContainerName)} >/dev/null 2>&1; then
  echo "Qdrant container not found"
  exit 0
fi
LABEL="\$(docker inspect -f '{{ index .Config.Labels "openhand.managed" }}' ${_pluginShellQuote(_qdrantContainerName)} 2>/dev/null || true)"
if [ "\$LABEL" != "true" ]; then
  echo "Existing container $_qdrantContainerName is not managed by OpenHand" >&2
  exit 3
fi
docker stop ${_pluginShellQuote(_qdrantContainerName)} >/dev/null || true
docker rm ${_pluginShellQuote(_qdrantContainerName)} >/dev/null || true
echo "Preserved Qdrant data directory: ${_pluginShellQuote(dataDir)}"
''';
    final result = await _runWithProgress(
      _pickShell(),
      ['-c', script],
      onProgress: onProgress,
      environment: _proxyEnv(),
    );
    if (result.exitCode == 0) {
      return PluginOperationResult(
        success: true,
        message: 'Qdrant 容器已移除，数据目录已保留：$dataDir',
      );
    }
    return PluginOperationResult(
      success: false,
      message: 'Qdrant 卸载失败: ${_processErrorMessage(result)}',
    );
  }

  Future<List<String>> _remainingPyenvVersions({
    required String excluding,
  }) async {
    final result = await runTrackedProcessOrFailed(
      _pickShell(),
      ['-c', '${_pythonShellPrefix()}pyenv versions --bare'],
      timeout: _pluginLifecycleVerifyTimeout,
      tag: 'plugin_lifecycle.pyenv_versions',
    );
    if (result.exitCode != 0) return const [];
    final versions = <String>[];
    for (final line in result.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == excluding) continue;
      if (isStrictSemanticVersionText(trimmed)) versions.add(trimmed);
    }
    return versions;
  }

  Future<_SimpleProcessResult> _runWithProgress(
    String executable,
    List<String> arguments, {
    void Function(String line)? onProgress,
    Duration timeout = _pluginLifecycleDefaultTimeout,
    Map<String, String>? environment,
  }) async {
    StreamSubscription<String>? stdoutSub;
    StreamSubscription<String>? stderrSub;
    try {
      final mergedEnv = <String, String>{...?environment, ..._proxyEnv()};
      final process = await startTrackedProcessInNewGroup(
        executable,
        arguments,
        environment: mergedEnv,
      );
      final stdoutLines = _ProgressLineCollector(onProgress: onProgress);
      final stderrLines = _ProgressLineCollector(onProgress: onProgress);
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      void complete(Completer<void> completer) {
        if (!completer.isCompleted) completer.complete();
      }

      stdoutSub = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen(
            stdoutLines.addChunk,
            onError: (Object error, StackTrace stack) {
              silentLog('plugin_lifecycle', 'stdout $executable', error, stack);
              stdoutLines.close();
              complete(stdoutDone);
            },
            onDone: () {
              stdoutLines.close();
              complete(stdoutDone);
            },
          );
      stderrSub = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(
            stderrLines.addChunk,
            onError: (Object error, StackTrace stack) {
              silentLog('plugin_lifecycle', 'stderr $executable', error, stack);
              stderrLines.close();
              complete(stderrDone);
            },
            onDone: () {
              stderrLines.close();
              complete(stderrDone);
            },
          );

      final effectiveTimeout = timeout <= Duration.zero
          ? _pluginLifecycleDefaultTimeout
          : timeout;
      var didTimeout = false;
      final exitCode = await process.exitCode.timeout(
        effectiveTimeout,
        onTimeout: () async {
          didTimeout = true;
          await terminateTrackedProcessTree(
            process,
            gracefulTimeout: _pluginLifecycleTerminateGrace,
          );
          return -1;
        },
      );
      try {
        await Future.wait<void>([
          stdoutDone.future,
          stderrDone.future,
        ]).timeout(_pluginLifecycleStreamDrainTimeout);
      } on TimeoutException {
        silentLog(
          'plugin_lifecycle',
          'drain output $executable',
          TimeoutException('output stream drain timed out'),
        );
      }

      return _SimpleProcessResult(
        exitCode: exitCode,
        stdout: stdoutLines.text,
        stderr: didTimeout && stderrLines.isEmpty
            ? _timeoutMessage(effectiveTimeout)
            : stderrLines.text,
      );
    } catch (error, stack) {
      silentLog(
        'plugin_lifecycle',
        'run $executable ${arguments.take(1).join(' ')}',
        error,
        stack,
      );
      return _SimpleProcessResult(exitCode: -1, stdout: '', stderr: '$error');
    } finally {
      await stdoutSub?.cancel();
      await stderrSub?.cancel();
    }
  }
}

class _ProgressLineCollector {
  _ProgressLineCollector({this.onProgress});

  final void Function(String line)? onProgress;
  final List<String> _lines = <String>[];
  String _pending = '';

  bool get isEmpty => _lines.isEmpty && _pending.trim().isEmpty;

  String get text => _lines.join('\n');

  void addChunk(String chunk) {
    if (chunk.isEmpty) return;
    final parts = (_pending + chunk).split('\n');
    _pending = parts.last;
    for (var index = 0; index < parts.length - 1; index++) {
      _addLine(parts[index]);
    }
  }

  void close() {
    if (_pending.isNotEmpty) {
      _addLine(_pending);
      _pending = '';
    }
  }

  void _addLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) return;
    final line = clipTextWithEllipsis(
      trimmed,
      _pluginLifecycleMaxProgressLineChars,
    );
    if (_lines.length >= _pluginLifecycleMaxCapturedLines) {
      _lines.removeAt(0);
    }
    _lines.add(line);
    onProgress?.call(line);
  }
}

String _pluginShellQuote(String value) {
  return pluginToolchainShellQuote(value);
}

String _timeoutMessage(Duration timeout) {
  final seconds = timeout.inSeconds;
  if (seconds > 0) {
    return '命令在 $seconds 秒内未完成，已终止子进程树。';
  }
  return '命令超时，已终止子进程树。';
}

String _processErrorMessage(_SimpleProcessResult result) {
  if (result.stderr.trim().isNotEmpty) return result.stderr.trim();
  if (result.stdout.trim().isNotEmpty) return result.stdout.trim();
  return '进程退出码 ${result.exitCode}';
}

String _combinedProcessOutput(_SimpleProcessResult result) {
  final output = '${result.stderr}\n${result.stdout}'.trim();
  if (output.isNotEmpty) return output;
  return '进程退出码 ${result.exitCode}';
}

class _SimpleProcessResult {
  const _SimpleProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

enum _PythonRuntimeSource { pyenv, homebrew, system, unknown }

class _PythonRuntimeContext {
  const _PythonRuntimeContext({
    required this.source,
    required this.executablePath,
    this.version,
    this.pyenvVersion,
    this.brewFormula,
  });

  final _PythonRuntimeSource source;
  final String executablePath;
  final String? version;
  final String? pyenvVersion;
  final String? brewFormula;
}

String? _extractPythonVersion(String output) {
  final match = _pluginLifecyclePythonVersionPattern.firstMatch(output);
  return match?.group(1);
}

String? _extractPipVersion(String output) {
  final match = _pluginLifecyclePipVersionPattern.firstMatch(output);
  return match?.group(1);
}

String? _extractNodeVersion(String output) {
  final matches = _pluginLifecycleNodeVersionPattern.allMatches(output);
  String? version;
  for (final match in matches) {
    version = match.group(1);
  }
  return version;
}

String _normalizePlaywrightVersion(Object? output) {
  return '$output'.trim().replaceFirst(
    _pluginLifecyclePlaywrightVersionPrefixPattern,
    '',
  );
}

String? _extractFirstSemver(String output, {String? prefix}) {
  final matches = _pluginLifecycleSemverPattern.allMatches(output);
  for (final match in matches) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix == null || value.startsWith(prefix)) return value;
  }
  return null;
}

String? _extractAbsolutePathFromOutput(String output) {
  for (final line in output.split('\n').reversed) {
    final trimmed = line.trim();
    if (trimmed.startsWith('/')) return trimmed;
  }
  return null;
}

List<String> _extractStablePyenvVersions(String output, {String? prefix}) {
  final versions = <String>{};
  for (final match in _pluginLifecycleStablePyenvVersionLinePattern.allMatches(
    output,
  )) {
    final value = match.group(1);
    if (value == null) continue;
    if (prefix != null && !value.startsWith(prefix)) continue;
    versions.add(value);
  }
  return versions.toList(growable: false);
}

String? _extractPyenvVersionFromPath(String path) {
  final match = _pluginLifecyclePyenvVersionPathPattern.firstMatch(path);
  final value = match?.group(1);
  if (value != null && isStrictSemanticVersionText(value)) return value;
  return null;
}

bool _looksLikeHomebrewPath(String path) {
  return path.contains('/Cellar/python') ||
      path.contains('/Homebrew/Cellar/python') ||
      path.contains('/opt/homebrew/') ||
      path.contains('/usr/local/opt/python') ||
      path.contains('/usr/local/bin/python');
}

bool _looksLikeSystemPython(String path) {
  return path.startsWith('/usr/bin/') ||
      path.startsWith('/Library/Developer/CommandLineTools/');
}

String? _extractBrewPythonFormulaFromPath(String path) {
  final matches = _pluginLifecycleBrewPythonFormulaPathPattern.allMatches(path);
  if (matches.isEmpty) return null;
  return matches.last.group(1);
}

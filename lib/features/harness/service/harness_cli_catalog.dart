import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/version_compare.dart';

enum HarnessCliAuthProbeMode { commandExitCode, localStateFile }

const int _localAuthStateMaxBytes = 2 * kBytesPerMiB;
const String _kDiagBeginMarker = '__OPENHAND_DIAG_BEGIN__';
const String _kDiagEndMarker = '__OPENHAND_DIAG_END__';
const BoundedDeletePolicy _localAuthStateDeletePolicy = BoundedDeletePolicy(
  maxEntries: 1,
  maxDepth: 0,
  operationTimeout: Duration(seconds: 3),
  totalTimeout: Duration(seconds: 5),
);

/// 直接执行 CLI 做能力探测，可能触发首次初始化。
const Duration _kHarnessCliProbeTimeout = Duration(seconds: 10);

/// 登录 shell 内的 which / 环境诊断，只读不初始化。
const Duration _kHarnessCliLookupTimeout = Duration(seconds: 5);
const Duration _kHarnessCliProcessStartTimeout = Duration(seconds: 10);
const int _harnessCliProbeConcurrency = 4;

/// Harness Engineering 支持的 AI CLI 定义。
class HarnessCli {
  const HarnessCli({
    required this.name,
    required this.executable,
    required this.knownModels,
    this.installCommand,
    this.installDocUrl,
    this.supportsHeadless = true,
    this.loginCheckArgs,
    this.loginCheckOutputHint,
    this.loginCheckMode = HarnessCliAuthProbeMode.commandExitCode,
    this.localAuthStateFilePath,
    this.localAuthStateJsonKey,
    this.loginArgs,
    this.logoutArgs,
    this.logoutLocalStateFilePaths,
  });

  final String name;
  final String executable;
  final List<String> knownModels;

  /// 安装命令及参数；为空表示不支持自动安装。
  final List<String>? installCommand;

  /// 安装文档地址。
  final String? installDocUrl;

  /// 是否支持无交互的无头调用。
  final bool supportsHeadless;

  /// 登录状态探测参数；为空表示没有可靠探测方式。
  final List<String>? loginCheckArgs;

  /// 登录探测成功时输出中必须包含的文本；为空时仅判断退出码。
  final String? loginCheckOutputHint;

  /// 登录状态探测方式。
  final HarnessCliAuthProbeMode loginCheckMode;

  /// 相对用户目录的登录状态文件。
  final String? localAuthStateFilePath;

  /// 登录状态文件中表示已登录的非空 JSON 字段。
  final String? localAuthStateJsonKey;

  /// 交互式登录参数；为空值表示不支持，空列表表示直接启动 CLI。
  final List<String>? loginArgs;

  /// 注销参数；为空表示没有 CLI 注销命令。
  final List<String>? logoutArgs;

  /// 基于本地状态注销时需要删除的用户目录相对路径。
  final List<String>? logoutLocalStateFilePaths;

  bool get isAutoInstallable => installCommand != null;

  /// 是否支持登录状态探测。
  bool get hasLoginCheck =>
      loginCheckArgs != null ||
      loginCheckMode == HarnessCliAuthProbeMode.localStateFile;

  /// 是否支持交互式登录。
  bool get hasLoginTrigger => loginArgs != null;

  /// 是否支持命令或本地状态注销。
  bool get hasLogoutTrigger =>
      logoutArgs != null || logoutLocalStateFilePaths != null;
}

/// 单个 CLI 的安装与登录探测结果。
typedef CliScanEntry = ({
  HarnessCli cli,
  bool installed,
  String? resolvedPath,

  /// 空值表示尚未探测或无法可靠判断。
  bool? isLoggedIn,
});

const String kHarnessGeminiDefaultModelId = '__gemini_cli_default__';

const List<HarnessCli> kHarnessCliCatalog = [
  // ── Anthropic ─────────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Claude Code',
    executable: 'claude',
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-haiku-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
      'claude-opus-4',
      'claude-sonnet-4',
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
    ],
    installCommand: ['npm', 'install', '-g', '@anthropic-ai/claude-code'],
    installDocUrl: 'https://docs.anthropic.com/claude-code',
    loginCheckArgs: ['auth', 'status'],
    loginArgs: ['login'],
    logoutArgs: ['auth', 'logout'],
  ),

  // ── OpenAI ────────────────────────────────────────────────────────────────
  HarnessCli(
    name: 'OpenAI Codex CLI',
    executable: 'codex',
    knownModels: [
      'gpt-5.4-codex',
      'gpt-5.3-codex',
      'gpt-5.2-codex',
      'gpt-5.1-codex',
      'gpt-5-codex',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-5.3',
      'gpt-5.3-mini',
      'gpt-5.2',
      'gpt-5.2-mini',
      'gpt-5.1',
      'gpt-5.1-mini',
      'gpt-5',
      'gpt-5-mini',
      'gpt-4.5-codex',
      'gpt-4.1-codex',
      'gpt-4o-codex',
      'gpt-4.5',
      'gpt-4.5-mini',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4.1-nano',
      'gpt-4o',
      'gpt-4o-mini',
      'o4-codex',
      'o4-mini-codex',
      'o3-codex',
      'o4',
      'o4-mini',
      'o3',
      'o3-mini',
      'o3-pro',
      'o1',
      'o1-mini',
      'o1-pro',
      'o1-preview',
      'codex-mini-latest',
      'codex-davinci-002',
    ],
    installCommand: ['npm', 'install', '-g', '@openai/codex'],
    installDocUrl: 'https://github.com/openai/codex',
    // Codex 使用浏览器 OAuth，没有独立的登录状态探测命令。
    loginArgs: ['login'],
    logoutArgs: ['logout'],
  ),

  // ── Google ────────────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Gemini CLI',
    executable: 'gemini',
    knownModels: [
      // CLI 托管默认模型，避免固定模型标识随版本失效。
      kHarnessGeminiDefaultModelId,
      'gemini-flash-latest',
      'gemini-3-flash-preview',
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.5-flash-lite',
      'gemini-3.1-pro-preview',
      'gemini-3.1-flash-lite-preview',
    ],
    installCommand: ['npm', 'install', '-g', '@google/gemini-cli'],
    installDocUrl: 'https://github.com/google-gemini/gemini-cli',
    // Gemini 没有稳定的登录状态命令，直接读取其本地账号状态。
    loginCheckMode: HarnessCliAuthProbeMode.localStateFile,
    localAuthStateFilePath: '.gemini/google_accounts.json',
    localAuthStateJsonKey: 'active',
    loginArgs: <String>[],
    // Gemini 没有独立注销命令，通过清理本地认证状态完成注销。
    logoutLocalStateFilePaths: [
      '.gemini/google_accounts.json',
      '.gemini/oauth_creds.json',
    ],
  ),

  // ── Aider (multi-provider) ────────────────────────────────────────────────
  HarnessCli(
    name: 'Aider',
    executable: 'aider',
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-haiku-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5.2',
      'gpt-5.1',
      'gpt-5',
      'gpt-4o',
      'o4',
      'o4-mini',
      'o3',
      'o3-mini',
      'gemini/gemini-2.5-pro',
      'gemini/gemini-2.5-flash',
      'gemini/gemini-2.5-flash-lite',
      'gemini/gemini-3.1-pro-preview',
      'gemini/gemini-3-flash-preview',
      'deepseek/deepseek-chat',
      'deepseek/deepseek-coder',
      'groq/llama-3.3-70b-versatile',
      'groq/mixtral-8x22b-32768',
      'ollama/llama3.1',
      'ollama/codestral',
      'ollama/deepseek-coder-v2',
      'ollama/qwen2.5-coder',
    ],
    installCommand: ['pipx', 'install', 'aider-chat'],
    installDocUrl: 'https://aider.chat/docs/install.html',
  ),

  // ── Codeium Windsurf ──────────────────────────────────────────────────────
  HarnessCli(
    name: 'Windsurf',
    executable: 'windsurf',
    supportsHeadless: false,
    knownModels: [
      'SWE-1',
      'SWE-1.5',
      'SWE-1-mini',
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4.1',
      'gemini-2.5-pro',
    ],
    installDocUrl: 'https://windsurf.ai/download',
  ),

  // ── Amazon Kiro ───────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Kiro',
    executable: 'kiro',
    supportsHeadless: false,
    knownModels: [
      'claude-sonnet-4-6',
      'claude-sonnet-4-5',
      'claude-opus-4-5',
      'amazon-nova-pro',
      'amazon-nova-lite',
      'amazon-nova-micro',
    ],
    installDocUrl: 'https://kiro.dev',
  ),

  // ── Block Goose ───────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Goose',
    executable: 'goose',
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4o',
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-3.1-pro-preview',
    ],
    installDocUrl: 'https://block.github.io/goose/docs/installation',
  ),

  // ── Cursor ────────────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Cursor',
    executable: 'cursor',
    supportsHeadless: false,
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4.1',
      'gemini-3.0-pro',
      'gemini-2.5-pro',
    ],
    installDocUrl: 'https://www.cursor.com',
  ),

  // ── Amazon Q Developer CLI ────────────────────────────────────────────────
  HarnessCli(
    name: 'Amazon Q',
    executable: 'q',
    knownModels: [
      'amazon-q-developer',
      'claude-sonnet-4-5',
      'amazon-nova-pro',
      'amazon-nova-lite',
    ],
    installCommand: ['brew', 'install', 'amazon-q'],
    installDocUrl: 'https://aws.amazon.com/q/developer/',
    loginCheckArgs: ['auth', 'status'],
    loginArgs: ['login'],
    logoutArgs: ['auth', 'logout'],
  ),

  // ── Plandex ───────────────────────────────────────────────────────────────
  HarnessCli(
    name: 'Plandex',
    executable: 'plandex',
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4o',
      'o4',
      'o4-mini',
      'o3',
      'gemini-2.5-pro',
    ],
    installDocUrl: 'https://docs.plandex.ai/install',
    loginArgs: ['sign-in'],
    logoutArgs: ['sign-out'],
  ),

  // ── Amp (Sourcegraph) ─────────────────────────────────────────────────────
  HarnessCli(
    name: 'Amp',
    executable: 'amp',
    knownModels: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-sonnet-4-5',
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4o',
      'gemini-2.5-pro',
    ],
    installCommand: ['npm', 'install', '-g', '@sourcegraph/amp'],
    installDocUrl: 'https://ampcode.com',
    loginCheckArgs: ['whoami'],
    loginArgs: ['auth', 'login'],
    logoutArgs: ['auth', 'logout'],
  ),
];

const String kHarnessGeminiModelsDocUrl =
    'https://ai.google.dev/gemini-api/docs/models';

bool isHarnessCliDefaultModel(HarnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  return cli.executable == 'gemini' &&
      normalizedModel == kHarnessGeminiDefaultModelId;
}

String resolveHarnessCliInvocationModelId(HarnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  if (isHarnessCliDefaultModel(cli, normalizedModel)) {
    return '';
  }
  return normalizedModel;
}

String describeHarnessCliModel(
  String modelId, {
  bool isZh = false,
  Locale? locale,
}) {
  final normalizedModel = modelId.trim();
  final Locale resolvedLocale;
  if (locale != null) {
    resolvedLocale = locale;
  } else if (isZh) {
    resolvedLocale = const Locale('zh');
  } else {
    resolvedLocale = const Locale('en');
  }
  if (normalizedModel == kHarnessGeminiDefaultModelId) {
    return openHandLocalizedTextForLocale(
      resolvedLocale,
      zh: 'Gemini CLI 默认（自动）',
      zhHant: 'Gemini CLI 預設（自動）',
      en: 'Gemini CLI default (auto)',
      fr: 'Gemini CLI par défaut (auto)',
      de: 'Gemini CLI Standard (automatisch)',
      ja: 'Gemini CLI デフォルト（自動）',
    );
  }
  if (normalizedModel.isEmpty) {
    return openHandLocalizedTextForLocale(
      resolvedLocale,
      zh: '默认',
      zhHant: '預設',
      en: 'Default',
      fr: 'Par défaut',
      de: 'Standard',
      ja: 'デフォルト',
    );
  }
  return normalizedModel;
}

List<String> suggestedHarnessCliModels(HarnessCli cli, {int max = 3}) {
  if (max <= 0 || cli.knownModels.isEmpty) {
    return const <String>[];
  }
  return cli.knownModels.take(max).toList(growable: false);
}

/// 有界并发扫描 CLI；已安装的无头 CLI 优先，未安装项置后。
Future<List<CliScanEntry>> scanInstalledClis() async {
  final results = await runOrderedWithConcurrencyLimit<CliScanEntry>(
    itemCount: kHarnessCliCatalog.length,
    maxConcurrency: _harnessCliProbeConcurrency,
    task: (index) => probeCliInstallation(kHarnessCliCatalog[index]),
  );
  final installedHeadless = results
      .where((r) => r.installed && r.cli.supportsHeadless)
      .toList();
  final installedGui = results
      .where((r) => r.installed && !r.cli.supportsHeadless)
      .toList();
  final notInstalled = results.where((r) => !r.installed).toList();
  return [...installedHeadless, ...installedGui, ...notInstalled];
}

Future<List<bool?>> probeCliAuthBatch(List<CliScanEntry> entries) {
  return runOrderedWithConcurrencyLimit<bool?>(
    itemCount: entries.length,
    maxConcurrency: _harnessCliProbeConcurrency,
    task: (index) => probeCliAuth(entries[index]),
  );
}

/// 在与编排器一致的登录 Shell 环境中探测 CLI。
Future<CliScanEntry> probeCliInstallation(HarnessCli cli) async {
  final whichResult = await _tryLoginShellWhich(cli.executable);
  if (whichResult != null) {
    return (
      cli: cli,
      installed: true,
      resolvedPath: whichResult,
      isLoggedIn: null,
    );
  }

  final execResult = await _tryLoginShellExec(cli.executable);
  if (execResult != null) {
    return (
      cli: cli,
      installed: true,
      resolvedPath: execResult,
      isLoggedIn: null,
    );
  }

  // 只以登录 Shell 可执行性为准，避免把同名系统程序误判为目标 CLI。
  return (cli: cli, installed: false, resolvedPath: null, isLoggedIn: null);
}

/// 返回 CLI 登录状态；空值表示无法判断。
Future<bool?> probeCliAuth(CliScanEntry entry) async {
  if (!entry.installed) return null;
  final cli = entry.cli;

  if (cli.loginCheckMode == HarnessCliAuthProbeMode.localStateFile) {
    return _probeCliAuthFromLocalState(cli);
  }

  if (cli.loginCheckArgs == null) return null;

  final executable = entry.resolvedPath ?? cli.executable;
  final args = cli.loginCheckArgs!;

  try {
    ProcessResult r;
    if (Platform.isWindows) {
      final result = await runProcessWithTimeout(
        executable,
        args,
        timeout: const Duration(seconds: 8),
        runInShell: true,
        tag: 'harness_cli_catalog',
      );
      if (result == null) return null;
      r = result;
    } else {
      final cmd = [executable, ...args].map(_q).join(' ');
      r = await runHarnessCliShellCommand(
        cmd,
        timeout: const Duration(seconds: 8),
      );
    }

    if (r.exitCode != 0) return false;

    if (cli.loginCheckOutputHint != null) {
      final out = '${r.stdout}${r.stderr}'.toLowerCase();
      return out.contains(cli.loginCheckOutputHint!.toLowerCase());
    }

    return true;
  } catch (_) {
    return null;
  }
}

Future<bool?> _probeCliAuthFromLocalState(HarnessCli cli) async {
  final relativePath = nullIfBlank(cli.localAuthStateFilePath);
  if (relativePath == null) return null;
  final homeDirectory = OpenHandPaths.environmentHomeDirectoryPath();
  if (homeDirectory == null) {
    return null;
  }
  try {
    final absolutePath = _resolveHomeRelativePath(homeDirectory, relativePath);
    if (absolutePath == null) return null;
    final file = File(absolutePath);
    if (!await regularFileExistsBounded(file, followLinks: false)) {
      return false;
    }
    final raw = await readBoundedFileString(
      file,
      maxBytes: _localAuthStateMaxBytes,
    );
    if (nullIfBlank(raw) == null) {
      return false;
    }
    final key = nullIfBlank(cli.localAuthStateJsonKey);
    if (key == null) {
      return true;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return false;
    }
    final value = stringKeyedMapFromValue(decoded)[key];
    if (value is String) {
      return nullIfBlank(value) != null;
    }
    if (value is List) {
      return value.isNotEmpty;
    }
    if (value is bool) {
      return value;
    }
    return value != null;
  } catch (_) {
    return false;
  }
}

/// 执行 CLI 注销并返回结果与可读说明。
Future<({bool success, String message})> performCliLogout(
  CliScanEntry entry,
) async {
  final cli = entry.cli;
  if (!cli.hasLogoutTrigger) {
    return (success: false, message: '${cli.name} 未配置登出方式。');
  }
  if (!entry.installed) {
    return (success: false, message: '尚未安装 ${cli.name}。');
  }

  if (cli.logoutLocalStateFilePaths != null) {
    return _performLocalStateLogout(cli);
  }

  if (cli.logoutArgs != null) {
    return _performCommandLogout(entry);
  }

  return (success: false, message: '${cli.name} 未配置登出方式。');
}

Future<({bool success, String message})> _performLocalStateLogout(
  HarnessCli cli,
) async {
  final paths = cli.logoutLocalStateFilePaths;
  if (paths == null || paths.isEmpty) {
    return (success: false, message: '未配置本地认证状态文件。');
  }

  final homeDirectory = OpenHandPaths.environmentHomeDirectoryPath();
  if (homeDirectory == null) {
    return (success: false, message: '无法确定用户目录。');
  }

  final deletedFiles = <String>[];
  final failedFiles = <String>[];

  for (final relativePath in paths) {
    final absolutePath = _resolveHomeRelativePath(homeDirectory, relativePath);
    if (absolutePath == null) {
      failedFiles.add(relativePath);
      continue;
    }
    try {
      final file = File(absolutePath);
      if (!await regularFileExistsBounded(file, followLinks: false)) continue;
      await deletePathBounded(
        absolutePath,
        policy: _localAuthStateDeletePolicy,
        allowedRoot: homeDirectory,
      );
      deletedFiles.add(relativePath);
    } catch (_) {
      failedFiles.add(relativePath);
    }
  }

  if (failedFiles.isNotEmpty) {
    return (success: false, message: '以下认证状态文件删除失败：${failedFiles.join('、')}');
  }

  if (deletedFiles.isEmpty) {
    return (success: true, message: '未发现认证状态文件，当前已处于登出状态。');
  }

  return (success: true, message: '已删除：${deletedFiles.join('、')}');
}

Future<({bool success, String message})> _performCommandLogout(
  CliScanEntry entry,
) async {
  final cli = entry.cli;
  final executable = entry.resolvedPath ?? cli.executable;
  final args = cli.logoutArgs!;

  try {
    ProcessResult r;
    if (Platform.isWindows) {
      final result = await runProcessWithTimeout(
        executable,
        args,
        timeout: _kHarnessCliProbeTimeout,
        runInShell: true,
        tag: 'harness_cli_catalog',
      );
      if (result == null) {
        return (success: false, message: '登出命令执行超时。');
      }
      r = result;
    } else {
      final cmd = [executable, ...args].map(_q).join(' ');
      r = await runHarnessCliShellCommand(
        cmd,
        timeout: _kHarnessCliProbeTimeout,
      );
    }

    final output = '${r.stdout}${r.stderr}'.trim();
    if (r.exitCode == 0) {
      return (success: true, message: output.isNotEmpty ? output : '登出成功。');
    }
    return (
      success: false,
      message: output.isNotEmpty ? output : '登出失败，退出码：${r.exitCode}。',
    );
  } on TimeoutException {
    return (success: false, message: '登出命令执行超时。');
  } catch (e) {
    return (success: false, message: '登出失败：$e');
  }
}

String resolveHarnessCliShellExecutable() =>
    preferredPosixShellExecutable(requireBashCompatible: true);

List<String> buildHarnessCliShellArgs(
  String command, {
  bool preferInteractiveEnvironment = true,
}) {
  final useInteractiveLogin =
      preferInteractiveEnvironment &&
      _shellSupportsInteractiveLogin(resolveHarnessCliShellExecutable());
  return <String>[if (useInteractiveLogin) '-i', '-l', '-c', command];
}

Future<ProcessResult> runHarnessCliShellCommand(
  String command, {
  Duration timeout = const Duration(seconds: 7),
}) async {
  // 统一使用有界进程封装，超时或启动失败时维持 TimeoutException 契约。
  final result = await runProcessWithTimeout(
    resolveHarnessCliShellExecutable(),
    buildHarnessCliShellArgs(command),
    timeout: timeout,
    tag: 'harness_cli_catalog',
  );
  if (result == null) {
    throw TimeoutException(
      'Harness CLI shell command timed out or failed to start.',
      timeout,
    );
  }
  return result;
}

Future<List<String>> collectHarnessCliFailureDiagnostics(
  String executable,
) async {
  if (Platform.isWindows) {
    return const <String>[];
  }

  try {
    final quotedExecutable = _q(executable);
    final result = await runHarnessCliShellCommand('''
printf '%s\\n' _kDiagBeginMarker
printf 'shell=%s\\n' "\${SHELL:-}"
if command -v $quotedExecutable >/dev/null 2>&1; then
  printf 'executable=%s\\n' "\$(command -v $quotedExecutable)"
else
  printf 'executable=\\n'
fi
if command -v node >/dev/null 2>&1; then
  printf 'node=%s\\n' "\$(command -v node)"
  printf 'node_version=%s\\n' "\$(node --version 2>/dev/null)"
else
  printf 'node=\\n'
  printf 'node_version=\\n'
fi
printf '%s\\n' _kDiagEndMarker
''', timeout: _kHarnessCliLookupTimeout);

    final diagnostics = _extractHarnessCliDiagnostics('${result.stdout}');
    final lines = <String>[];
    final shell = diagnostics['shell']?.trim();
    if (shell != null && shell.isNotEmpty) {
      lines.add('shell: $shell');
    }
    final executablePath = diagnostics['executable']?.trim();
    if (executablePath != null && executablePath.isNotEmpty) {
      lines.add('$executable path: $executablePath');
    }
    final nodePath = diagnostics['node']?.trim();
    if (nodePath != null && nodePath.isNotEmpty) {
      lines.add('node path: $nodePath');
    }
    final nodeVersion = diagnostics['node_version']?.trim();
    if (nodeVersion != null && nodeVersion.isNotEmpty) {
      lines.add('node version: $nodeVersion');
      final nodeMajor = _tryParseNodeMajorVersion(nodeVersion);
      if (executable == 'gemini' && nodeMajor != null && nodeMajor < 20) {
        lines.add(
          'Gemini CLI 可能需要 Node 20+；当前版本偏低，容易因 Unicode 正则 /v 标志不受支持而启动失败。',
        );
      }
    }
    return lines;
  } catch (_) {
    return const <String>[];
  }
}

Future<Process> startHarnessCliInteractiveProcess({
  required String executable,
  List<String> args = const <String>[],
  String? workingDirectory,
}) {
  final normalizedWorkingDirectory = workingDirectory?.trim();
  if (Platform.isWindows) {
    return startTrackedProcessBounded(
      executable,
      args,
      timeout: _kHarnessCliProcessStartTimeout,
      tag: 'harness_cli_catalog',
      startInNewProcessGroup: true,
      workingDirectory: normalizedWorkingDirectory?.isNotEmpty == true
          ? normalizedWorkingDirectory
          : null,
      runInShell: true,
    );
  }

  // 直接使用交互式登录 Shell；macOS 的 script PTY 封装在管道输入下可能挂起。
  final shell = resolveHarnessCliShellExecutable();
  final shellFragments = <String>[
    if (normalizedWorkingDirectory != null &&
        normalizedWorkingDirectory.isNotEmpty)
      'cd ${_q(normalizedWorkingDirectory)}',
    'exec ${formatHarnessCliCommandPreview(executable, args)}',
  ];
  return startTrackedProcessBounded(
    shell,
    buildHarnessCliShellArgs(shellFragments.join(' && ')),
    timeout: _kHarnessCliProcessStartTimeout,
    tag: 'harness_cli_catalog',
    startInNewProcessGroup: true,
    environment: <String, String>{
      // 非真实 PTY 下仍允许 CLI 输出颜色与交互提示。
      'FORCE_COLOR': '1',
      // 内置 CLI 经常需要触网（登录 / 同步 / 拉取包列表等），与全局代理
      // 保持一致可避免企业代理环境下的连接失败。
      ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
    },
  );
}

String formatHarnessCliCommandPreview(String executable, List<String> args) {
  return <String>[executable, ...args].map(_q).join(' ');
}

String stripHarnessCliTerminalSequences(String text) {
  return text.replaceAll(_terminalEscapePattern, '');
}

Future<String?> _tryLoginShellWhich(String executable) async {
  if (Platform.isWindows) {
    final r = await runProcessWithTimeout(
      'where',
      <String>[executable],
      timeout: _kHarnessCliLookupTimeout,
      tag: 'harness_cli_catalog',
    );
    if (r != null && r.exitCode == 0) {
      final p = (r.stdout as String).trim().split('\n').first.trim();
      return p.isNotEmpty ? p : null;
    }
    return null;
  }
  try {
    final quoted = _q(executable);
    final r = await runHarnessCliShellCommand('command -v $quoted');
    if (r.exitCode == 0) {
      final p = lastNonEmptyLine('${r.stdout}');
      return p.isNotEmpty ? p : null;
    }
  } catch (error, stack) {
    silentLog('harness_cli_catalog', '探测 POSIX 命令路径', error, stack);
  }
  return null;
}

Future<String?> _tryLoginShellExec(String executable) async {
  if (Platform.isWindows) {
    final r = await runProcessWithTimeout(
      executable,
      const <String>['--version'],
      timeout: _kHarnessCliLookupTimeout,
      runInShell: true,
      tag: 'harness_cli_catalog',
    );
    if (r != null && r.exitCode == 0) return executable;
    return null;
  }
  try {
    final quoted = _q(executable);
    final r = await runHarnessCliShellCommand('$quoted --version');
    // 部分工具执行 --version 时以 1 退出，但仍会输出有效版本信息。
    if (r.exitCode == 0 || r.exitCode == 1) {
      final out = '${r.stdout}${r.stderr}';
      if (out.isNotEmpty) return executable;
    }
  } catch (error, stack) {
    silentLog(
      'harness_cli_catalog',
      '探测 POSIX CLI 版本：$executable',
      error,
      stack,
    );
  }
  return null;
}

/// 移除终端输出中的 CSI、OSC 与双字节 ANSI/VT 转义序列。
final RegExp _terminalEscapePattern = RegExp(
  r'\x1B(?:'
  r'\[[0-?]*[ -/]*[@-~]' // CSI 控制序列
  r'|\][^\x07\x1B]*(?:\x07|\x1B\\)' // OSC 控制序列
  r'|[@-Z\\-_]' // 双字节转义
  r')',
);

bool _shellSupportsInteractiveLogin(String shellPath) {
  final shellName = shellPath
      .split(Platform.pathSeparator)
      .where((segment) => segment.isNotEmpty)
      .last
      .toLowerCase();
  return switch (shellName) {
    'bash' || 'zsh' || 'sh' || 'dash' || 'ksh' || 'fish' => true,
    _ => false,
  };
}

Map<String, String> _extractHarnessCliDiagnostics(String stdout) {
  final diagnostics = <String, String>{};
  var inBlock = false;
  for (final rawLine in const LineSplitter().convert(stdout)) {
    final line = rawLine.trim();
    if (line == _kDiagBeginMarker) {
      inBlock = true;
      continue;
    }
    if (line == _kDiagEndMarker) {
      break;
    }
    if (!inBlock) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    diagnostics[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return diagnostics;
}

int? _tryParseNodeMajorVersion(String version) {
  final normalized = nullIfBlank(version);
  return normalized == null ? null : versionMajorFromText(normalized);
}

String? _resolveHomeRelativePath(String homeDirectory, String relativePath) {
  final root = homeDirectory.trim();
  if (!p.isAbsolute(root) ||
      root.contains('\u0000') ||
      safeRelativePathError(relativePath) != null) {
    return null;
  }
  final normalizedRoot = p.normalize(root);
  final resolved = p.normalize(
    p.joinAll(<String>[normalizedRoot, ...p.url.split(relativePath)]),
  );
  return isPathWithinOrEqual(normalizedRoot, resolved) ? resolved : null;
}

/// 使用 POSIX 单引号转义 Shell 参数。
String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/support/silent_log.dart';

enum HardnessCliAuthProbeMode { commandExitCode, localStateFile }

/// Describes a known AI CLI client usable in Hardness Engineering.
class HardnessCli {
  const HardnessCli({
    required this.name,
    required this.executable,
    required this.knownModels,
    this.installCommand,
    this.installDocUrl,
    this.supportsHeadless = true,
    this.loginCheckArgs,
    this.loginCheckOutputHint,
    this.loginCheckMode = HardnessCliAuthProbeMode.commandExitCode,
    this.localAuthStateFilePath,
    this.localAuthStateJsonKey,
    this.loginArgs,
    this.logoutArgs,
    this.logoutLocalStateFilePaths,
  });

  final String name;
  final String executable;
  final List<String> knownModels;

  /// Install command+args. null = no auto-install support (e.g. GUI apps).
  final List<String>? installCommand;

  /// URL to installation documentation.
  final String? installDocUrl;

  /// Whether this CLI supports non-interactive headless invocation.
  /// GUI IDE launchers (Cursor, Windsurf, Kiro) set this to false.
  final bool supportsHeadless;

  /// Args to pass to the executable to probe login state.
  /// null = no reliable check available (e.g. API-key–only tools like Aider).
  /// Exit code 0 → logged in; non-zero → not logged in.
  final List<String>? loginCheckArgs;

  /// Optional substring that must appear (case-insensitive) in combined
  /// stdout+stderr for the login check to be considered successful.
  /// When null, exit code 0 alone is sufficient.
  final String? loginCheckOutputHint;

  /// Strategy used to determine whether the CLI is authenticated.
  final HardnessCliAuthProbeMode loginCheckMode;

  /// Home-relative state file used by [HardnessCliAuthProbeMode.localStateFile].
  final String? localAuthStateFilePath;

  /// JSON key inside [localAuthStateFilePath] whose non-empty value means the
  /// CLI is logged in.
  final String? localAuthStateJsonKey;

  /// Args to pass to the executable to trigger an interactive login flow.
  /// null = no login command available for this CLI.
  /// An empty list means "launch the CLI with no extra args".
  final List<String>? loginArgs;

  /// Args to pass to the executable to trigger a logout flow.
  /// null = no CLI-based logout command available.
  final List<String>? logoutArgs;

  /// Home-relative file paths to delete for local-state-based logout
  /// (e.g. Gemini CLI which stores auth in local JSON files).
  /// null = logout is handled via [logoutArgs] command instead.
  final List<String>? logoutLocalStateFilePaths;

  bool get isAutoInstallable => installCommand != null;

  /// Whether this CLI supports login-state probing.
  bool get hasLoginCheck =>
      loginCheckArgs != null ||
      loginCheckMode == HardnessCliAuthProbeMode.localStateFile;

  /// Whether this CLI supports a guided interactive login flow.
  bool get hasLoginTrigger => loginArgs != null;

  /// Whether this CLI supports a logout flow (command-based or file-based).
  bool get hasLogoutTrigger =>
      logoutArgs != null || logoutLocalStateFilePaths != null;
}

/// Result of probing a single CLI installation (and optionally login state).
typedef CliScanEntry = ({
  HardnessCli cli,
  bool installed,
  String? resolvedPath,

  /// null = not yet checked, or no login check defined for this CLI.
  bool? isLoggedIn,
});

const String kHardnessGeminiDefaultModelId = '__gemini_cli_default__';

const List<HardnessCli> kHardnessCliCatalog = [
  // ── Anthropic ─────────────────────────────────────────────────────────────
  HardnessCli(
    name: 'Claude Code',
    executable: 'claude',
    knownModels: [
      // 4.6 series
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-haiku-4-6',
      // 4.5 series
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
      // 4 series
      'claude-opus-4',
      'claude-sonnet-4',
      // 3.7 series
      'claude-3-7-sonnet-20250219',
      // 3.5 series
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      // 3 series
      'claude-3-opus-20240229',
    ],
    installCommand: ['npm', 'install', '-g', '@anthropic-ai/claude-code'],
    installDocUrl: 'https://docs.anthropic.com/claude-code',
    loginCheckArgs: ['auth', 'status'],
    loginArgs: ['login'],
    logoutArgs: ['auth', 'logout'],
  ),

  // ── OpenAI ────────────────────────────────────────────────────────────────
  HardnessCli(
    name: 'OpenAI Codex CLI',
    executable: 'codex',
    knownModels: [
      // GPT-5.x Codex variants
      'gpt-5.4-codex',
      'gpt-5.3-codex',
      'gpt-5.2-codex',
      'gpt-5.1-codex',
      'gpt-5-codex',
      // GPT-5.x base
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
      // GPT-4.x Codex variants
      'gpt-4.5-codex',
      'gpt-4.1-codex',
      'gpt-4o-codex',
      // GPT-4.x base
      'gpt-4.5',
      'gpt-4.5-mini',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4.1-nano',
      'gpt-4o',
      'gpt-4o-mini',
      // o-series Codex variants
      'o4-codex',
      'o4-mini-codex',
      'o3-codex',
      // o-series base
      'o4',
      'o4-mini',
      'o3',
      'o3-mini',
      'o3-pro',
      'o1',
      'o1-mini',
      'o1-pro',
      'o1-preview',
      // Codex-native models
      'codex-mini-latest',
      'codex-davinci-002',
    ],
    installCommand: ['npm', 'install', '-g', '@openai/codex'],
    installDocUrl: 'https://github.com/openai/codex',
    // Codex CLI uses browser-based OAuth; no dedicated auth-status probe.
    // loginArgs triggers `codex login` to guide the user through the flow.
    loginArgs: ['login'],
    logoutArgs: ['logout'],
  ),

  // ── Google ────────────────────────────────────────────────────────────────
  HardnessCli(
    name: 'Gemini CLI',
    executable: 'gemini',
    knownModels: [
      // CLI-managed default is the safest option against model drift.
      kHardnessGeminiDefaultModelId,
      'gemini-flash-latest',
      'gemini-3-flash-preview',
      // Stable generally available models
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.5-flash-lite',
      // Preview / rolling aliases
      'gemini-3.1-pro-preview',
      'gemini-3.1-flash-lite-preview',
    ],
    installCommand: ['npm', 'install', '-g', '@google/gemini-cli'],
    installDocUrl: 'https://github.com/google-gemini/gemini-cli',
    // Gemini CLI does not expose a stable `auth status` subcommand.
    // It persists the active Google account in ~/.gemini/google_accounts.json,
    // so probe that local state instead of launching an interactive session.
    loginCheckMode: HardnessCliAuthProbeMode.localStateFile,
    localAuthStateFilePath: '.gemini/google_accounts.json',
    localAuthStateJsonKey: 'active',
    // Launching bare `gemini` starts the interactive auth flow when needed.
    loginArgs: <String>[],
    // Gemini CLI has no dedicated logout command; clear local auth state files.
    logoutLocalStateFilePaths: [
      '.gemini/google_accounts.json',
      '.gemini/oauth_creds.json',
    ],
  ),

  // ── Aider (multi-provider) ────────────────────────────────────────────────
  HardnessCli(
    name: 'Aider',
    executable: 'aider',
    knownModels: [
      // Anthropic (litellm prefix optional)
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-haiku-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      // OpenAI
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
      // Google Gemini (litellm prefix required)
      'gemini/gemini-2.5-pro',
      'gemini/gemini-2.5-flash',
      'gemini/gemini-2.5-flash-lite',
      'gemini/gemini-3.1-pro-preview',
      'gemini/gemini-3-flash-preview',
      // DeepSeek
      'deepseek/deepseek-chat',
      'deepseek/deepseek-coder',
      // Groq
      'groq/llama-3.3-70b-versatile',
      'groq/mixtral-8x22b-32768',
      // Ollama (local)
      'ollama/llama3.1',
      'ollama/codestral',
      'ollama/deepseek-coder-v2',
      'ollama/qwen2.5-coder',
    ],
    installCommand: ['pipx', 'install', 'aider-chat'],
    installDocUrl: 'https://aider.chat/docs/install.html',
  ),

  // ── Codeium Windsurf ──────────────────────────────────────────────────────
  HardnessCli(
    name: 'Windsurf',
    executable: 'windsurf',
    supportsHeadless: false,
    knownModels: [
      // Windsurf-native SWE models
      'SWE-1',
      'SWE-1.5',
      'SWE-1-mini',
      // Claude via Windsurf
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-sonnet-4-5',
      // OpenAI via Windsurf
      'gpt-5.4',
      'gpt-5.3',
      'gpt-5',
      'gpt-4.1',
      // Gemini via Windsurf
      'gemini-2.5-pro',
    ],
    installDocUrl: 'https://windsurf.ai/download',
  ),

  // ── Amazon Kiro ───────────────────────────────────────────────────────────
  HardnessCli(
    name: 'Kiro',
    executable: 'kiro',
    supportsHeadless: false,
    knownModels: [
      // Claude via Amazon Bedrock
      'claude-sonnet-4-6',
      'claude-sonnet-4-5',
      'claude-opus-4-5',
      // Amazon Nova
      'amazon-nova-pro',
      'amazon-nova-lite',
      'amazon-nova-micro',
    ],
    installDocUrl: 'https://kiro.dev',
  ),

  // ── Block Goose ───────────────────────────────────────────────────────────
  HardnessCli(
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
  HardnessCli(
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
  HardnessCli(
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
  HardnessCli(
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
  HardnessCli(
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

const String kHardnessGeminiModelsDocUrl =
    'https://ai.google.dev/gemini-api/docs/models';

const Map<String, String> _hardnessGeminiDeprecatedModelSuggestions = {
  'gemini-1.5-flash': 'gemini-2.5-flash',
  'gemini-1.5-pro': 'gemini-2.5-pro',
  'gemini-2.0-flash': 'gemini-2.5-flash',
  'gemini-2.0-pro': 'gemini-2.5-pro',
  // Older Gemini 3 aliases drift frequently. Recommend the CLI-managed
  // default, but never auto-rewrite the user's configured model.
  'gemini-3-flash': kHardnessGeminiDefaultModelId,
  'gemini-3-pro-preview': kHardnessGeminiDefaultModelId,
  'gemini-3.0-flash': kHardnessGeminiDefaultModelId,
  'gemini-3.0-pro': kHardnessGeminiDefaultModelId,
  'gemini-3.1-flash': kHardnessGeminiDefaultModelId,
  'gemini-3.1-flash-lite': kHardnessGeminiDefaultModelId,
  'gemini-3.1-pro': kHardnessGeminiDefaultModelId,
};

HardnessCli? findHardnessCliByName(String cliName) {
  final normalized = cliName.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return kHardnessCliCatalog.where((cli) => cli.name == normalized).firstOrNull;
}

String normalizeHardnessCliModelId(HardnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  if (normalizedModel.isEmpty) {
    return '';
  }
  return normalizedModel;
}

String? recommendedHardnessCliModelForDeprecatedId(
  HardnessCli cli,
  String modelId,
) {
  final normalizedModel = modelId.trim();
  if (normalizedModel.isEmpty) {
    return null;
  }
  return switch (cli.executable) {
    'gemini' => _hardnessGeminiDeprecatedModelSuggestions[normalizedModel],
    _ => null,
  };
}

bool isHardnessCliDefaultModel(HardnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  return cli.executable == 'gemini' &&
      normalizedModel == kHardnessGeminiDefaultModelId;
}

String resolveHardnessCliInvocationModelId(HardnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  if (isHardnessCliDefaultModel(cli, normalizedModel)) {
    return '';
  }
  return normalizedModel;
}

String describeHardnessCliModel(
  HardnessCli? cli,
  String modelId, {
  bool isZh = false,
}) {
  final normalizedModel = modelId.trim();
  if (normalizedModel == kHardnessGeminiDefaultModelId) {
    return isZh ? 'Gemini CLI 默认（自动）' : 'Gemini CLI default (auto)';
  }
  if (normalizedModel.isEmpty) {
    return isZh ? '默认' : 'Default';
  }
  return normalizedModel;
}

bool isHardnessCliModelSupported(HardnessCli cli, String modelId) {
  final normalizedModel = modelId.trim();
  if (normalizedModel.isEmpty) {
    return false;
  }
  if (cli.knownModels.isEmpty) {
    return true;
  }
  return cli.knownModels.contains(normalizedModel);
}

List<String> suggestedHardnessCliModels(HardnessCli cli, {int max = 3}) {
  if (max <= 0 || cli.knownModels.isEmpty) {
    return const <String>[];
  }
  return cli.knownModels.take(max).toList(growable: false);
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Scans all known CLIs in parallel. Installed headless-capable CLIs appear
/// first; uninstalled ones last.
Future<List<CliScanEntry>> scanInstalledClis() async {
  final results = await Future.wait(
    kHardnessCliCatalog.map(probeCliInstallation),
  );
  // Installed & headless first; uninstalled last.
  final installedHeadless = results
      .where((r) => r.installed && r.cli.supportsHeadless)
      .toList();
  final installedGui = results
      .where((r) => r.installed && !r.cli.supportsHeadless)
      .toList();
  final notInstalled = results.where((r) => !r.installed).toList();
  return [...installedHeadless, ...installedGui, ...notInstalled];
}

/// Probes a single CLI installation.
/// Uses login-shell execution for accuracy (matches the environment the
/// orchestrator actually uses), then falls back to static file probing.
Future<CliScanEntry> probeCliInstallation(HardnessCli cli) async {
  // Strategy 1 (most reliable): login-shell `which`.
  final whichResult = await _tryLoginShellWhich(cli.executable);
  if (whichResult != null) {
    return (
      cli: cli,
      installed: true,
      resolvedPath: whichResult,
      isLoggedIn: null,
    );
  }

  // Strategy 2: login-shell direct execution.
  final execResult = await _tryLoginShellExec(cli.executable);
  if (execResult != null) {
    return (
      cli: cli,
      installed: true,
      resolvedPath: execResult,
      isLoggedIn: null,
    );
  }

  // NOTE: npm-prefix (Strategy 3) and static-filesystem (Strategy 4) probes
  // were intentionally removed. They only verify file existence, not shell
  // reachability. A concrete example of the false-positive they cause:
  // /usr/local/bin/codex exists on macOS as Apple's system CodeX tool, so
  // the OpenAI Codex CLI appears "installed" even when it is not. At runtime
  // the orchestrator runs all CLIs via the same login-shell context as
  // Strategies 1 & 2, so those two are the sole source of truth.
  return (cli: cli, installed: false, resolvedPath: null, isLoggedIn: null);
}

// ── Auth probing ──────────────────────────────────────────────────────────────

/// Probes whether an installed CLI is authenticated / logged in.
///
/// Returns:
///   `true`  — confirmed logged in
///   `false` — confirmed NOT logged in
///   `null`  — unknown (no check defined, timeout, or execution error)
Future<bool?> probeCliAuth(CliScanEntry entry) async {
  if (!entry.installed) return null;
  final cli = entry.cli;

  if (cli.loginCheckMode == HardnessCliAuthProbeMode.localStateFile) {
    return _probeCliAuthFromLocalState(cli);
  }

  if (cli.loginCheckArgs == null) return null;

  final executable = entry.resolvedPath ?? cli.executable;
  final args = cli.loginCheckArgs!;

  try {
    ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run(
        executable,
        args,
        runInShell: true,
      ).timeout(const Duration(seconds: 8));
    } else {
      final cmd = [executable, ...args].map(_q).join(' ');
      r = await runHardnessCliShellCommand(
        cmd,
        timeout: const Duration(seconds: 8),
      );
    }

    if (r.exitCode != 0) return false;

    // If an output hint is configured, verify it appears in combined output.
    if (cli.loginCheckOutputHint != null) {
      final out = '${r.stdout}${r.stderr}'.toLowerCase();
      return out.contains(cli.loginCheckOutputHint!.toLowerCase());
    }

    return true;
  } catch (_) {
    // Timeout or process error — login state unknown.
    return null;
  }
}

Future<bool?> _probeCliAuthFromLocalState(HardnessCli cli) async {
  final relativePath = cli.localAuthStateFilePath;
  if (relativePath == null || relativePath.trim().isEmpty) {
    return null;
  }
  final homeDirectory =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDirectory == null || homeDirectory.trim().isEmpty) {
    return null;
  }
  final absolutePath = _resolveHomeRelativePath(homeDirectory, relativePath);
  final file = File(absolutePath);
  if (!await file.exists()) {
    return false;
  }

  try {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return false;
    }
    final key = cli.localAuthStateJsonKey;
    if (key == null || key.trim().isEmpty) {
      return true;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return false;
    }
    final value = decoded[key];
    if (value is String) {
      return value.trim().isNotEmpty;
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

// ── Logout ────────────────────────────────────────────────────────────────────

/// Performs a CLI logout operation.
///
/// Returns a record with:
///   `success` — whether the logout completed without errors
///   `message` — human-readable status message (stdout/stderr or error detail)
Future<({bool success, String message})> performCliLogout(
  CliScanEntry entry,
) async {
  final cli = entry.cli;
  if (!cli.hasLogoutTrigger) {
    return (
      success: false,
      message: 'No logout method defined for ${cli.name}.',
    );
  }
  if (!entry.installed) {
    return (success: false, message: '${cli.name} is not installed.');
  }

  // Strategy 1: Local state file deletion (e.g. Gemini CLI).
  if (cli.logoutLocalStateFilePaths != null) {
    return _performLocalStateLogout(cli);
  }

  // Strategy 2: CLI command-based logout.
  if (cli.logoutArgs != null) {
    return _performCommandLogout(entry);
  }

  return (success: false, message: 'No logout method defined for ${cli.name}.');
}

Future<({bool success, String message})> _performLocalStateLogout(
  HardnessCli cli,
) async {
  final paths = cli.logoutLocalStateFilePaths;
  if (paths == null || paths.isEmpty) {
    return (success: false, message: 'No local auth state files configured.');
  }

  final homeDirectory =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (homeDirectory == null || homeDirectory.trim().isEmpty) {
    return (success: false, message: 'Cannot determine home directory.');
  }

  final deletedFiles = <String>[];
  final errors = <String>[];

  for (final relativePath in paths) {
    final absolutePath = _resolveHomeRelativePath(homeDirectory, relativePath);
    final file = File(absolutePath);
    try {
      if (await file.exists()) {
        await file.delete();
        deletedFiles.add(relativePath);
      }
    } catch (e) {
      errors.add('$relativePath: $e');
    }
  }

  if (errors.isNotEmpty) {
    return (
      success: false,
      message: 'Failed to remove auth files: ${errors.join('; ')}',
    );
  }

  if (deletedFiles.isEmpty) {
    return (
      success: true,
      message: 'No auth state files found (already logged out).',
    );
  }

  return (success: true, message: 'Removed: ${deletedFiles.join(', ')}');
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
      r = await Process.run(
        executable,
        args,
        runInShell: true,
      ).timeout(const Duration(seconds: 10));
    } else {
      final cmd = [executable, ...args].map(_q).join(' ');
      r = await runHardnessCliShellCommand(
        cmd,
        timeout: const Duration(seconds: 10),
      );
    }

    final output = '${r.stdout}${r.stderr}'.trim();
    if (r.exitCode == 0) {
      return (
        success: true,
        message: output.isNotEmpty ? output : 'Logged out successfully.',
      );
    }
    return (
      success: false,
      message: output.isNotEmpty
          ? output
          : 'Logout failed (exit code ${r.exitCode}).',
    );
  } on TimeoutException {
    return (success: false, message: 'Logout command timed out.');
  } catch (e) {
    return (success: false, message: 'Logout failed: $e');
  }
}

String resolveHardnessCliShellExecutable() =>
    Platform.environment['SHELL'] ?? '/bin/bash';

List<String> buildHardnessCliShellArgs(
  String command, {
  bool preferInteractiveEnvironment = true,
}) {
  final useInteractiveLogin =
      preferInteractiveEnvironment &&
      _shellSupportsInteractiveLogin(resolveHardnessCliShellExecutable());
  return <String>[if (useInteractiveLogin) '-i', '-l', '-c', command];
}

Future<ProcessResult> runHardnessCliShellCommand(
  String command, {
  Duration timeout = const Duration(seconds: 7),
}) {
  return Process.run(
    resolveHardnessCliShellExecutable(),
    buildHardnessCliShellArgs(command),
  ).timeout(timeout);
}

Future<List<String>> collectHardnessCliFailureDiagnostics(
  String executable,
) async {
  if (Platform.isWindows) {
    return const <String>[];
  }

  try {
    final quotedExecutable = _q(executable);
    final result = await runHardnessCliShellCommand('''
printf '%s\\n' '__OPENHAND_DIAG_BEGIN__'
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
printf '%s\\n' '__OPENHAND_DIAG_END__'
''', timeout: const Duration(seconds: 5));

    final diagnostics = _extractHardnessCliDiagnostics('${result.stdout}');
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

Future<Process> startHardnessCliInteractiveProcess({
  required String executable,
  List<String> args = const <String>[],
  String? workingDirectory,
}) {
  final normalizedWorkingDirectory = workingDirectory?.trim();
  if (Platform.isWindows) {
    return Process.start(
      executable,
      args,
      workingDirectory: normalizedWorkingDirectory?.isNotEmpty == true
          ? normalizedWorkingDirectory
          : null,
      runInShell: true,
    );
  }

  // Direct shell execution instead of `script` PTY wrapper.
  // `script -q /dev/null <shell> …` silently hangs when spawned from Dart's
  // Process.start() on macOS: Dart creates pipes for stdio and macOS's
  // `script` fails on tcgetattr() for non-TTY stdin, producing zero output
  // and never exiting.  Direct shell with `-i -l` still loads nvm / pyenv
  // paths from .zshrc / .bashrc, which is the critical requirement.
  final shell = resolveHardnessCliShellExecutable();
  final shellFragments = <String>[
    if (normalizedWorkingDirectory != null &&
        normalizedWorkingDirectory.isNotEmpty)
      'cd ${_q(normalizedWorkingDirectory)}',
    'exec ${formatHardnessCliCommandPreview(executable, args)}',
  ];
  return Process.start(
    shell,
    buildHardnessCliShellArgs(shellFragments.join(' && ')),
    environment: <String, String>{
      // Hint to CLIs that colour / interactive output is acceptable even
      // though stdout is not a real PTY.  Many Node-based tools (Ink, chalk)
      // check FORCE_COLOR before falling back to isatty().
      'FORCE_COLOR': '1',
    },
  );
}

String formatHardnessCliCommandPreview(String executable, List<String> args) {
  return <String>[executable, ...args].map(_q).join(' ');
}

String stripHardnessCliTerminalSequences(String text) {
  return text.replaceAll(_terminalEscapePattern, '');
}

// ── Strategy 1: login-shell which ────────────────────────────────────────────
// Runs `command -v` inside an interactive login shell so nvm / pyenv
// entries are visible, matching the environment the orchestrator uses.

Future<String?> _tryLoginShellWhich(String executable) async {
  if (Platform.isWindows) {
    // Windows: plain `where`
    try {
      final r = await Process.run('where', [
        executable,
      ]).timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) {
        final p = (r.stdout as String).trim().split('\n').first.trim();
        return p.isNotEmpty ? p : null;
      }
    } catch (error, stack) {
      silentLog('hardness_cli_catalog', 'where probe (Windows)', error, stack);
    }
    return null;
  }
  try {
    final quoted = _q(executable);
    final r = await runHardnessCliShellCommand('command -v $quoted');
    if (r.exitCode == 0) {
      final p = _lastNonEmptyLine('${r.stdout}');
      return p.isNotEmpty ? p : null;
    }
  } catch (error, stack) {
    silentLog('hardness_cli_catalog', 'command -v probe (POSIX)', error, stack);
  }
  return null;
}

// ── Strategy 2: login-shell direct execution ──────────────────────────────────
// Tries running `executable --version` in a login shell. Catches cases where
// the binary is callable but `which` doesn't return a path (e.g. shell funcs).

Future<String?> _tryLoginShellExec(String executable) async {
  if (Platform.isWindows) {
    try {
      final r = await Process.run(executable, [
        '--version',
      ], runInShell: true).timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) return executable;
    } catch (error, stack) {
      silentLog('hardness_cli_catalog', '$executable --version probe (Windows)', error, stack);
    }
    return null;
  }
  try {
    final quoted = _q(executable);
    final r = await runHardnessCliShellCommand('$quoted --version');
    // Accept exit 0 or 1 — some tools (aider) exit 1 for --version.
    if (r.exitCode == 0 || r.exitCode == 1) {
      final out = '${r.stdout}${r.stderr}';
      if (out.isNotEmpty) return executable;
    }
  } catch (error, stack) {
    silentLog('hardness_cli_catalog', '$executable --version probe (POSIX)', error, stack);
  }
  return null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Strips ANSI/VT escape sequences from terminal output.
///
/// Covers:
///   • CSI sequences  (ESC [ … final-byte)
///   • OSC sequences  (ESC ] … ST)  — used by Ink / hyperlinks
///   • Simple two-byte escapes  (ESC followed by a single char 0x40–0x5F)
final RegExp _terminalEscapePattern = RegExp(
  r'\x1B(?:'
  r'\[[0-?]*[ -/]*[@-~]' // CSI: ESC [ params intermediates final
  r'|\][^\x07\x1B]*(?:\x07|\x1B\\)' // OSC: ESC ] … BEL or ESC ] … ST
  r'|[@-Z\\-_]' // Two-byte: ESC + single 0x40–0x5F char
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

Map<String, String> _extractHardnessCliDiagnostics(String stdout) {
  final diagnostics = <String, String>{};
  var inBlock = false;
  for (final rawLine in const LineSplitter().convert(stdout)) {
    final line = rawLine.trim();
    if (line == '__OPENHAND_DIAG_BEGIN__') {
      inBlock = true;
      continue;
    }
    if (line == '__OPENHAND_DIAG_END__') {
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
  final match = RegExp(r'^v?(\d+)').firstMatch(version.trim());
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

String _lastNonEmptyLine(String value) {
  final lines = value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '' : lines.last;
}

String _resolveHomeRelativePath(String homeDirectory, String relativePath) {
  final normalizedSegments = relativePath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return <String>[
    homeDirectory,
    ...normalizedSegments,
  ].join(Platform.pathSeparator);
}

/// POSIX single-quote an executable name for embedding in shell -c strings.
String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";

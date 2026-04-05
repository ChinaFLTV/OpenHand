import 'dart:io';

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
    this.loginArgs,
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

  /// Args to pass to the executable to trigger an interactive login flow.
  /// null = no login command available for this CLI.
  final List<String>? loginArgs;

  bool get isAutoInstallable => installCommand != null;

  /// Whether this CLI supports login-state probing.
  bool get hasLoginCheck => loginCheckArgs != null;

  /// Whether this CLI supports a guided interactive login flow.
  bool get hasLoginTrigger => loginArgs != null;
}

/// Result of probing a single CLI installation (and optionally login state).
typedef CliScanEntry = ({
  HardnessCli cli,
  bool installed,
  String? resolvedPath,
  /// null = not yet checked, or no login check defined for this CLI.
  bool? isLoggedIn,
});

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
  ),

  // ── Google ────────────────────────────────────────────────────────────────
  HardnessCli(
    name: 'Gemini CLI',
    executable: 'gemini',
    knownModels: [
      // 3.x series
      'gemini-3.1-pro',
      'gemini-3.1-flash',
      'gemini-3.0-pro',
      'gemini-3.0-flash',
      // 2.x series
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.0-pro',
      'gemini-2.0-flash',
      // 1.5 series (long-context)
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ],
    installCommand: ['npm', 'install', '-g', '@google/gemini-cli'],
    installDocUrl: 'https://github.com/google-gemini/gemini-cli',
    loginCheckArgs: ['auth', 'status'],
    // Gemini CLI prompts for Google OAuth automatically on first run;
    // there is no separate login subcommand — do not set loginArgs.
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
      'gemini/gemini-3.1-pro',
      'gemini/gemini-2.5-pro',
      'gemini/gemini-2.5-flash',
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
      'gemini-3.0-pro',
      'gemini-2.5-pro',
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
  ),
];

// ── Public API ────────────────────────────────────────────────────────────────

/// Scans all known CLIs in parallel. Installed headless-capable CLIs appear
/// first; uninstalled ones last.
Future<List<CliScanEntry>> scanInstalledClis() async {
  final results = await Future.wait(
    kHardnessCliCatalog.map(probeCliInstallation),
  );
  // Installed & headless first; uninstalled last.
  final installedHeadless =
      results.where((r) => r.installed && r.cli.supportsHeadless).toList();
  final installedGui =
      results.where((r) => r.installed && !r.cli.supportsHeadless).toList();
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
    return (cli: cli, installed: true, resolvedPath: whichResult, isLoggedIn: null);
  }

  // Strategy 2: login-shell direct execution.
  final execResult = await _tryLoginShellExec(cli.executable);
  if (execResult != null) {
    return (cli: cli, installed: true, resolvedPath: execResult, isLoggedIn: null);
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
  if (cli.loginCheckArgs == null) return null;

  final executable = entry.resolvedPath ?? cli.executable;
  final args = cli.loginCheckArgs!;

  try {
    ProcessResult r;
    if (Platform.isWindows) {
      r = await Process.run(executable, args, runInShell: true)
          .timeout(const Duration(seconds: 8));
    } else {
      final shell = Platform.environment['SHELL'] ?? '/bin/bash';
      final cmd = [executable, ...args].map(_q).join(' ');
      r = await Process.run(shell, ['-l', '-c', cmd])
          .timeout(const Duration(seconds: 8));
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

// ── Strategy 1: login-shell which ────────────────────────────────────────────
// Runs `which` inside a login shell so nvm / pyenv / user-installed PATH
// entries are visible, matching the environment the orchestrator uses.

Future<String?> _tryLoginShellWhich(String executable) async {
  if (Platform.isWindows) {
    // Windows: plain `where`
    try {
      final r = await Process.run('where', [executable])
          .timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) {
        final p = (r.stdout as String).trim().split('\n').first.trim();
        return p.isNotEmpty ? p : null;
      }
    } catch (_) {}
    return null;
  }
  try {
    final shell = Platform.environment['SHELL'] ?? '/bin/bash';
    final quoted = _q(executable);
    final r = await Process.run(shell, ['-l', '-c', 'which $quoted'])
        .timeout(const Duration(seconds: 7));
    if (r.exitCode == 0) {
      final p = (r.stdout as String).trim().split('\n').first.trim();
      return p.isNotEmpty ? p : null;
    }
  } catch (_) {}
  return null;
}

// ── Strategy 2: login-shell direct execution ──────────────────────────────────
// Tries running `executable --version` in a login shell. Catches cases where
// the binary is callable but `which` doesn't return a path (e.g. shell funcs).

Future<String?> _tryLoginShellExec(String executable) async {
  if (Platform.isWindows) {
    try {
      final r = await Process.run(executable, ['--version'], runInShell: true)
          .timeout(const Duration(seconds: 5));
      if (r.exitCode == 0) return executable;
    } catch (_) {}
    return null;
  }
  try {
    final shell = Platform.environment['SHELL'] ?? '/bin/bash';
    final quoted = _q(executable);
    final r = await Process.run(shell, ['-l', '-c', '$quoted --version'])
        .timeout(const Duration(seconds: 7));
    // Accept exit 0 or 1 — some tools (aider) exit 1 for --version.
    if (r.exitCode == 0 || r.exitCode == 1) {
      final out = '${r.stdout}${r.stderr}';
      if (out.isNotEmpty) return executable;
    }
  } catch (_) {}
  return null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// POSIX single-quote an executable name for embedding in shell -c strings.
String _q(String s) => "'${s.replaceAll("'", "'\\''")}'";



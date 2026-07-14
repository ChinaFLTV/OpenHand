import 'dart:io';
import 'dart:ui' show Locale;

import '../../app/support/safe_subprocess.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';

const Duration _kToolchainProbeTimeout = Duration(seconds: 5);
const Duration _kToolchainCommandTimeout = Duration(minutes: 10);
const int _kToolchainProbeMaxConcurrency = 4;

const Map<String, String> androidReverseToolchainPluginIds = <String, String>{
  'keytool': 'java',
  'apktool': 'apktool',
  'jadx': 'jadx',
  'frida': 'frida',
  'mitmproxy': 'mitmproxy',
  'radare2': 'radare2',
  'blutter': 'blutter',
  'doldrums': 'doldrums',
  'anything_analyzer': 'anything_analyzer',
};

String? androidReverseToolchainPluginIdForProbe(String probeId) =>
    androidReverseToolchainPluginIds[probeId];

enum AndroidReverseToolchainCommandAction { install, update, uninstall }

class AndroidReverseToolchainCommandResult {
  const AndroidReverseToolchainCommandResult({
    required this.probe,
    required this.action,
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    required this.timedOut,
  });

  final AndroidReverseToolchainProbe probe;
  final AndroidReverseToolchainCommandAction action;
  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;
  bool get hasOutput =>
      nullIfBlank(stdout) != null || nullIfBlank(stderr) != null;
}

class AndroidReverseToolchainProbe {
  const AndroidReverseToolchainProbe({
    required this.id,
    required this.label,
    required this.script,
    required this.installHintZh,
    required this.installHintEn,
    this.required = false,
    this.installCommand,
    this.updateCommand,
    this.uninstallCommand,
    this.referenceUrl,
  });

  final String id;
  final String label;
  final String script;
  final String installHintZh;
  final String installHintEn;
  final bool required;
  final String? installCommand;
  final String? updateCommand;
  final String? uninstallCommand;
  final String? referenceUrl;

  String? commandFor(AndroidReverseToolchainCommandAction action) {
    return switch (action) {
      AndroidReverseToolchainCommandAction.install => installCommand,
      AndroidReverseToolchainCommandAction.update => updateCommand,
      AndroidReverseToolchainCommandAction.uninstall => uninstallCommand,
    };
  }
}

class AndroidReverseToolchainProbeResult {
  const AndroidReverseToolchainProbeResult({
    required this.probe,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  final AndroidReverseToolchainProbe probe;
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;

  bool get ok => exitCode == 0 && nullIfBlank(stdout) != null;

  String get displayValue {
    final text = nullIfBlank(stdout);
    if (text != null) return text;
    return nullIfBlank(stderr) ?? 'NOT_FOUND';
  }

  String installHint(bool isZh) {
    if (isZh) {
      return installHintForLocale(const Locale('zh'));
    }
    return installHintForLocale(const Locale('en'));
  }

  String installHintForLocale(Locale locale) => openHandLocalizedTextForLocale(
    locale,
    zh: probe.installHintZh,
    en: probe.installHintEn,
  );
}

const List<AndroidReverseToolchainProbe>
androidReverseToolchainProbes = <AndroidReverseToolchainProbe>[
  AndroidReverseToolchainProbe(
    id: 'adb',
    label: 'ADB',
    required: true,
    script:
        r'p="$(command -v adb || true)"; '
        r'[ -n "$p" ] || p="$ANDROID_HOME/platform-tools/adb"; '
        r'[ -x "$p" ] || p="$ANDROID_SDK_ROOT/platform-tools/adb"; '
        r'[ -x "$p" ] && { echo "$p"; adb version | head -1; }',
    installHintZh: '安装 Android SDK Platform Tools，并把 adb 加入 PATH。',
    installHintEn: 'Install Android SDK Platform Tools and add adb to PATH.',
    installCommand: 'sdkmanager "platform-tools"',
    updateCommand: 'sdkmanager --update',
    referenceUrl: 'https://developer.android.com/tools/sdkmanager',
  ),
  AndroidReverseToolchainProbe(
    id: 'aapt',
    label: 'aapt',
    required: true,
    script:
        r'p="$(command -v aapt || true)"; '
        r'[ -n "$p" ] || p="$(find "$HOME/Library/Android/sdk/build-tools" -name aapt -type f 2>/dev/null | sort -r | head -1)"; '
        r'[ -x "$p" ] && echo "$p"',
    installHintZh: '在 Android SDK Manager 安装 Build Tools。',
    installHintEn: 'Install Android SDK Build Tools.',
    installCommand: 'sdkmanager "build-tools;36.0.0"',
    updateCommand: 'sdkmanager --update',
    referenceUrl: 'https://developer.android.com/tools/sdkmanager',
  ),
  AndroidReverseToolchainProbe(
    id: 'apksigner',
    label: 'apksigner',
    script:
        r'p="$(command -v apksigner || true)"; '
        r'[ -n "$p" ] || p="$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner -type f 2>/dev/null | sort -r | head -1)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" --version 2>/dev/null | head -1; }',
    installHintZh: '在 Android SDK Manager 安装 Build Tools，用于 APK 签名证书检查。',
    installHintEn:
        'Install Android SDK Build Tools for APK signing certificate checks.',
    installCommand: 'sdkmanager "build-tools;36.0.0"',
    updateCommand: 'sdkmanager --update',
    referenceUrl: 'https://developer.android.com/tools/sdkmanager',
  ),
  AndroidReverseToolchainProbe(
    id: 'keytool',
    label: 'keytool',
    script:
        r'p="$(command -v keytool || true)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" -help 2>&1 | head -1; }',
    installHintZh: '安装 JDK，并把 keytool 加入 PATH，用于证书查看。',
    installHintEn:
        'Install a JDK and add keytool to PATH for certificate checks.',
    installCommand: 'brew install openjdk',
    updateCommand: 'brew upgrade openjdk',
    uninstallCommand: 'brew uninstall openjdk',
    referenceUrl: 'https://openjdk.org/',
  ),
  AndroidReverseToolchainProbe(
    id: 'strings',
    label: 'strings',
    script:
        r'p="$(command -v strings || xcrun -find strings 2>/dev/null || true)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" --version 2>/dev/null | head -1 || true; }',
    installHintZh: '安装系统开发者工具或 binutils，用于 dex/so/assets 字符串扫描。',
    installHintEn:
        'Install system developer tools or binutils for dex/so/assets string scans.',
    installCommand: 'xcode-select --install',
    referenceUrl: 'https://developer.apple.com/xcode/resources/',
  ),
  AndroidReverseToolchainProbe(
    id: 'readelf',
    label: 'readelf',
    script:
        r'p="$(command -v readelf || command -v llvm-readelf || true)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" --version 2>/dev/null | head -1 || true; }',
    installHintZh: '安装 binutils / LLVM / Android NDK，用于 so 符号与段信息分析。',
    installHintEn:
        'Install binutils, LLVM, or Android NDK for native symbol analysis.',
    installCommand: 'brew install binutils llvm',
    updateCommand: 'brew upgrade binutils llvm',
    uninstallCommand: 'brew uninstall binutils llvm',
  ),
  AndroidReverseToolchainProbe(
    id: 'apktool',
    label: 'apktool',
    script:
        r'p="$(command -v apktool || true)"; '
        r'[ -x "$p" ] && { echo "$p"; apktool --version 2>/dev/null | head -1; }',
    installHintZh: '可通过 Homebrew 安装：brew install apktool。',
    installHintEn: 'Install with Homebrew: brew install apktool.',
    installCommand: 'brew install apktool',
    updateCommand: 'brew upgrade apktool',
    uninstallCommand: 'brew uninstall apktool',
    referenceUrl: 'https://apktool.org/',
  ),
  AndroidReverseToolchainProbe(
    id: 'jadx',
    label: 'jadx',
    script:
        r'p="$(command -v jadx || true)"; '
        r'[ -x "$p" ] && { echo "$p"; jadx --version 2>/dev/null | head -1; }',
    installHintZh: '可通过 Homebrew 安装：brew install jadx。',
    installHintEn: 'Install with Homebrew: brew install jadx.',
    installCommand: 'brew install jadx',
    updateCommand: 'brew upgrade jadx',
    uninstallCommand: 'brew uninstall jadx',
    referenceUrl: 'https://github.com/skylot/jadx',
  ),
  AndroidReverseToolchainProbe(
    id: 'frida',
    label: 'Frida CLI',
    script:
        r'p="$(command -v frida || true)"; '
        r'[ -x "$p" ] && { echo "$p"; frida --version 2>/dev/null | head -1; }',
    installHintZh: '安装 frida-tools，并按设备架构准备 frida-server。',
    installHintEn:
        'Install frida-tools and prepare frida-server for the device ABI.',
    installCommand: 'python3 -m pip install -U frida-tools',
    updateCommand: 'python3 -m pip install -U frida-tools',
    uninstallCommand: 'python3 -m pip uninstall frida-tools',
    referenceUrl: 'https://frida.re/docs/installation/',
  ),
  AndroidReverseToolchainProbe(
    id: 'mitmproxy',
    label: 'mitmproxy',
    script:
        r'p="$(command -v mitmdump || command -v mitmproxy || true)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" --version 2>/dev/null | head -1; }',
    installHintZh: '可通过 Homebrew 安装：brew install mitmproxy。',
    installHintEn: 'Install with Homebrew: brew install mitmproxy.',
    installCommand: 'brew install mitmproxy',
    updateCommand: 'brew upgrade mitmproxy',
    uninstallCommand: 'brew uninstall mitmproxy',
    referenceUrl: 'https://docs.mitmproxy.org/',
  ),
  AndroidReverseToolchainProbe(
    id: 'radare2',
    label: 'radare2',
    script:
        r'p="$(command -v r2 || command -v radare2 || true)"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" -v 2>/dev/null | head -1; }',
    installHintZh: '可通过 Homebrew 安装：brew install radare2。',
    installHintEn: 'Install with Homebrew: brew install radare2.',
    installCommand: 'brew install radare2',
    updateCommand: 'brew upgrade radare2',
    uninstallCommand: 'brew uninstall radare2',
    referenceUrl: 'https://rada.re/n/',
  ),
  AndroidReverseToolchainProbe(
    id: 'blutter',
    label: 'blutter',
    script:
        r'p="$(command -v blutter || true)"; '
        r'[ -x "$p" ] || p="$HOME/.openhand/android_reverse_tools/bin/blutter"; '
        r'[ -x "$p" ] && echo "$p"',
    installHintZh: '可在插件板块直接安装 blutter，或按项目说明安装并加入 PATH。',
    installHintEn:
        'Install blutter from the Plugins tab, or from its project instructions and add it to PATH.',
    referenceUrl: 'https://github.com/worawit/blutter',
  ),
  AndroidReverseToolchainProbe(
    id: 'doldrums',
    label: 'Doldrums',
    script:
        r'p="$(command -v Doldrums || command -v doldrums || true)"; '
        r'[ -x "$p" ] || p="$HOME/.openhand/android_reverse_tools/bin/doldrums"; '
        r'[ -x "$p" ] && echo "$p"',
    installHintZh: '可在插件板块直接安装 Doldrums，或按项目说明安装并加入 PATH。',
    installHintEn:
        'Install Doldrums from the Plugins tab, or from its project instructions and add it to PATH.',
    referenceUrl: 'https://github.com/rscloura/Doldrums',
  ),
  AndroidReverseToolchainProbe(
    id: 'anything_analyzer',
    label: 'anything-analyzer',
    script:
        r'p="$(command -v anything-analyzer || true)"; '
        r'[ -x "$p" ] || p="$HOME/.openhand/android_reverse_tools/bin/anything-analyzer"; '
        r'[ -x "$p" ] && { echo "$p"; "$p" --version 2>/dev/null | head -1 || true; }',
    installHintZh: '可在插件板块直接安装 Anything Analyzer，并在 MCP 面板启用对应 server。',
    installHintEn:
        'Install Anything Analyzer from the Plugins tab and enable the corresponding server in the MCP panel.',
  ),
];

Future<List<AndroidReverseToolchainProbeResult>>
probeAndroidReverseToolchain() async {
  if (!androidReverseToolchainDiagnosticsSupported) {
    return androidReverseToolchainProbes
        .map(
          (probe) => AndroidReverseToolchainProbeResult(
            probe: probe,
            exitCode: -1,
            stdout: '',
            stderr: 'Toolchain diagnostics require /bin/sh on this platform.',
            durationMs: 0,
          ),
        )
        .toList(growable: false);
  }
  return runOrderedWithConcurrencyLimit<AndroidReverseToolchainProbeResult>(
    itemCount: androidReverseToolchainProbes.length,
    maxConcurrency: _kToolchainProbeMaxConcurrency,
    task: (index) => _runToolchainProbe(androidReverseToolchainProbes[index]),
  );
}

Future<AndroidReverseToolchainCommandResult> runAndroidReverseToolchainCommand(
  AndroidReverseToolchainProbe probe,
  AndroidReverseToolchainCommandAction action,
) async {
  final command = nullIfBlank(probe.commandFor(action));
  if (command == null) {
    return AndroidReverseToolchainCommandResult(
      probe: probe,
      action: action,
      command: '',
      exitCode: -1,
      stdout: '',
      stderr: 'No ${action.name} command is available for ${probe.label}.',
      durationMs: 0,
      timedOut: false,
    );
  }
  if (!androidReverseToolchainDiagnosticsSupported) {
    return AndroidReverseToolchainCommandResult(
      probe: probe,
      action: action,
      command: command,
      exitCode: -1,
      stdout: '',
      stderr: 'Toolchain commands require /bin/sh on this platform.',
      durationMs: 0,
      timedOut: false,
    );
  }
  final sw = Stopwatch()..start();
  try {
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', command],
      timeout: _kToolchainCommandTimeout,
      tag: 'android_reverse_toolchain_command',
    );
    sw.stop();
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();
    final timedOut =
        result.exitCode == -1 &&
        nullIfBlank(stdout) == null &&
        nullIfBlank(stderr) == null &&
        sw.elapsed >= _kToolchainCommandTimeout;
    return AndroidReverseToolchainCommandResult(
      probe: probe,
      action: action,
      command: command,
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: timedOut
          ? 'Toolchain command timed out after ${_kToolchainCommandTimeout.inMinutes} minutes.'
          : stderr,
      durationMs: sw.elapsedMilliseconds,
      timedOut: timedOut,
    );
  } catch (e) {
    sw.stop();
    return AndroidReverseToolchainCommandResult(
      probe: probe,
      action: action,
      command: command,
      exitCode: -1,
      stdout: '',
      stderr: '$e',
      durationMs: sw.elapsedMilliseconds,
      timedOut: false,
    );
  }
}

Future<AndroidReverseToolchainProbeResult> _runToolchainProbe(
  AndroidReverseToolchainProbe probe,
) async {
  final sw = Stopwatch()..start();
  try {
    final result = await runTrackedProcessOrFailed(
      '/bin/sh',
      <String>['-lc', probe.script],
      timeout: _kToolchainProbeTimeout,
      tag: 'android_reverse_toolchain',
    );
    sw.stop();
    return AndroidReverseToolchainProbeResult(
      probe: probe,
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
      durationMs: sw.elapsedMilliseconds,
    );
  } catch (e) {
    sw.stop();
    return AndroidReverseToolchainProbeResult(
      probe: probe,
      exitCode: -1,
      stdout: '',
      stderr: '$e',
      durationMs: sw.elapsedMilliseconds,
    );
  }
}

bool get androidReverseToolchainDiagnosticsSupported => !Platform.isWindows;

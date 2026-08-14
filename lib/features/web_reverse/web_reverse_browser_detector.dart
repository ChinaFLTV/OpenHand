import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/bounded_file_io.dart';
import 'web_reverse_browser_kind.dart';

const Duration _browserExecutableProbeTimeout = Duration(milliseconds: 500);

/// which / 版本探测等短命子进程。
const Duration _browserLookupTimeout = Duration(seconds: 2);

/// Spotlight (mdfind) 全盘检索，比逐个 which 慢。
const Duration _browserSpotlightTimeout = Duration(seconds: 3);

/// 探测结果：[browser] 命中即可启动；为 null 表示用户未安装任何同核浏览器。
class WebReverseBrowserProbeResult {
  const WebReverseBrowserProbeResult({
    required this.browser,
    required this.executablePath,
    required this.versionLine,
  });

  final WebReverseBrowserKind? browser;
  final String? executablePath;
  final String? versionLine;

  bool get isInstalled => browser != null && executablePath != null;
}

/// 探测系统是否安装了 Chrome 或同核 Chromium 浏览器。
///
/// 在 macOS 上按 [WebReverseBrowserKind] 顺序尝试三种探测方式，命中即停：
///   1. `mdfind kMDItemCFBundleIdentifier == '<bundle_id>'`
///   2. 默认安装目录 `/Applications/<App>.app/Contents/MacOS/<binary>`
///   3. `which <cli_name>`（chromium / google-chrome 等）
///
/// 返回值兼容"未安装"场景；UI 层据此弹引导对话框。
class WebReverseBrowserDetector {
  Future<WebReverseBrowserProbeResult> detect() async {
    final all = await detectAll();
    return all.isEmpty
        ? const WebReverseBrowserProbeResult(
            browser: null,
            executablePath: null,
            versionLine: null,
          )
        : all.first;
  }

  /// 探测所有已安装的同核浏览器（按 [WebReverseBrowserKind.values] 优先级排序），
  /// 找不到时返回空列表。UI 层据此填浏览器下拉。
  Future<List<WebReverseBrowserProbeResult>> detectAll() async {
    if (Platform.isMacOS) return _detectAllOn(_findExecutableMacOS);
    if (Platform.isWindows) return _detectAllOn(_findExecutableWindows);
    if (Platform.isLinux) return _detectAllOn(_findExecutableLinux);
    return const <WebReverseBrowserProbeResult>[];
  }

  Future<List<WebReverseBrowserProbeResult>> _detectAllOn(
    Future<String?> Function(WebReverseBrowserKind kind) resolver,
  ) async {
    final out = <WebReverseBrowserProbeResult>[];
    for (final kind in WebReverseBrowserKind.values) {
      final exe = await resolver(kind);
      if (exe == null) continue;
      final version = await _readVersion(exe);
      out.add(
        WebReverseBrowserProbeResult(
          browser: kind,
          executablePath: exe,
          versionLine: version,
        ),
      );
    }
    return out;
  }

  // ── macOS 单 kind 解析（mdfind → 默认路径 → which） ────────────────
  Future<String?> _findExecutableMacOS(WebReverseBrowserKind kind) async {
    // 1) mdfind 按 bundle id 查
    final mdfind = await runProcessWithTimeout(
      'mdfind',
      ['kMDItemCFBundleIdentifier == "${kind.macBundleId}"'],
      timeout: _browserSpotlightTimeout,
      tag: 'web_reverse_browser_detector',
    );
    final firstAppPath = mdfind?.stdout
        .toString()
        .split('\n')
        .firstWhere((line) => line.trim().endsWith('.app'), orElse: () => '');
    if (firstAppPath != null && firstAppPath.isNotEmpty) {
      final exe = _appPathToExecutable(firstAppPath.trim(), kind);
      if (exe != null && await _isExecutableFile(exe)) return exe;
    }
    // 2) 默认安装路径
    final defaultExe = _appPathToExecutable(kind.macAppPath, kind);
    if (defaultExe != null && await _isExecutableFile(defaultExe)) {
      return defaultExe;
    }
    // 3) PATH 上的 cli 入口（Chromium / google-chrome）
    final cliCandidate = switch (kind) {
      WebReverseBrowserKind.chromium => 'chromium',
      WebReverseBrowserKind.chrome => 'google-chrome',
      _ => null,
    };
    return cliCandidate == null
        ? null
        : _findExecutableOnPath(<String>[cliCandidate]);
  }

  String? _appPathToExecutable(String appPath, WebReverseBrowserKind kind) {
    final binaryName = switch (kind) {
      WebReverseBrowserKind.chrome => 'Google Chrome',
      WebReverseBrowserKind.chromeBeta => 'Google Chrome Beta',
      WebReverseBrowserKind.edge => 'Microsoft Edge',
      WebReverseBrowserKind.brave => 'Brave Browser',
      WebReverseBrowserKind.chromium => 'Chromium',
    };
    return '$appPath/Contents/MacOS/$binaryName';
  }

  // ── Windows 单 kind 解析（默认路径 → reg App Paths） ───────────────
  Future<String?> _findExecutableWindows(WebReverseBrowserKind kind) async {
    for (final candidate in kind.windowsExecutableCandidates) {
      if (await _isExecutableFile(candidate)) return candidate;
    }
    final exeName = switch (kind) {
      WebReverseBrowserKind.chrome ||
      WebReverseBrowserKind.chromeBeta => 'chrome.exe',
      WebReverseBrowserKind.edge => 'msedge.exe',
      WebReverseBrowserKind.brave => 'brave.exe',
      WebReverseBrowserKind.chromium => 'chromium.exe',
    };
    final reg = await runProcessWithTimeout(
      'reg.exe',
      [
        'query',
        'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\$exeName',
        '/ve',
      ],
      timeout: _browserLookupTimeout,
      tag: 'web_reverse_browser_detector',
    );
    final raw = reg?.stdout.toString() ?? '';
    final match = RegExp(
      r'REG_SZ\s+(.+\.exe)',
      caseSensitive: false,
    ).firstMatch(raw);
    final regPath = match?.group(1)?.trim();
    if (regPath != null &&
        regPath.isNotEmpty &&
        await _isExecutableFile(regPath)) {
      return regPath;
    }
    return null;
  }

  // ── Linux 单 kind 解析（which 多候选） ─────────────────────────────
  Future<String?> _findExecutableLinux(WebReverseBrowserKind kind) async {
    return _findExecutableOnPath(kind.cliCandidates);
  }

  Future<String?> _findExecutableOnPath(Iterable<String> candidates) async {
    for (final candidate in candidates) {
      final which = await runProcessWithTimeout(
        '/usr/bin/which',
        <String>[candidate],
        timeout: _browserLookupTimeout,
        tag: 'web_reverse_browser_detector',
      );
      final raw = which?.stdout.toString().trim();
      if (raw != null && raw.isNotEmpty && await _isExecutableFile(raw)) {
        return raw;
      }
    }
    return null;
  }

  Future<String?> _readVersion(String executable) async {
    try {
      final result = await runProcessWithTimeout(
        executable,
        const ['--version'],
        timeout: _browserLookupTimeout,
        tag: 'web_reverse_browser_detector',
      );
      final line = result?.stdout.toString().trim();
      if (line != null && line.isNotEmpty) return line;
    } catch (error, stack) {
      silentLog(
        'web_reverse_browser_detector',
        '读取 $executable 版本',
        error,
        stack,
      );
    }
    return null;
  }

  Future<bool> _isExecutableFile(String path) {
    return isRegularFilePath(
      path,
      timeout: _browserExecutableProbeTimeout,
      followLinks: true,
    );
  }
}

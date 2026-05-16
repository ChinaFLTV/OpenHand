import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import 'web_reverse_browser_kind.dart';

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
  WebReverseBrowserDetector();

  Future<WebReverseBrowserProbeResult> detect() async {
    if (!Platform.isMacOS) {
      // 当前阶段只全量适配 macOS；其他平台返回未安装让 UI 层提示用户切到 macOS。
      return const WebReverseBrowserProbeResult(
        browser: null,
        executablePath: null,
        versionLine: null,
      );
    }
    for (final kind in WebReverseBrowserKind.values) {
      final exe = await _findExecutable(kind);
      if (exe == null) continue;
      final version = await _readVersion(exe);
      return WebReverseBrowserProbeResult(
        browser: kind,
        executablePath: exe,
        versionLine: version,
      );
    }
    return const WebReverseBrowserProbeResult(
      browser: null,
      executablePath: null,
      versionLine: null,
    );
  }

  Future<String?> _findExecutable(WebReverseBrowserKind kind) async {
    // 1) mdfind 按 bundle id 查
    final mdfind = await runProcessWithTimeout(
      'mdfind',
      ['kMDItemCFBundleIdentifier == "${kind.macBundleId}"'],
      timeout: const Duration(seconds: 3),
      tag: 'web_reverse_browser_detector',
    );
    final firstAppPath = mdfind?.stdout.toString().split('\n').firstWhere(
      (line) => line.trim().endsWith('.app'),
      orElse: () => '',
    );
    if (firstAppPath != null && firstAppPath.isNotEmpty) {
      final exe = _appPathToExecutable(firstAppPath, kind);
      if (exe != null && File(exe).existsSync()) return exe;
    }
    // 2) 默认安装路径
    final defaultExe = _appPathToExecutable(kind.macAppPath, kind);
    if (defaultExe != null && File(defaultExe).existsSync()) return defaultExe;
    // 3) PATH 上的 cli 入口（Chromium / google-chrome）
    final cliCandidate = switch (kind) {
      WebReverseBrowserKind.chromium => 'chromium',
      WebReverseBrowserKind.chrome => 'google-chrome',
      _ => null,
    };
    if (cliCandidate != null) {
      final which = await runProcessWithTimeout(
        '/usr/bin/which',
        [cliCandidate],
        timeout: const Duration(seconds: 2),
        tag: 'web_reverse_browser_detector',
      );
      final raw = which?.stdout.toString().trim();
      if (raw != null && raw.isNotEmpty && File(raw).existsSync()) return raw;
    }
    return null;
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

  Future<String?> _readVersion(String executable) async {
    try {
      final result = await runProcessWithTimeout(
        executable,
        const ['--version'],
        timeout: const Duration(seconds: 2),
        tag: 'web_reverse_browser_detector',
      );
      final line = result?.stdout.toString().trim();
      if (line != null && line.isNotEmpty) return line;
    } catch (error, stack) {
      silentLog(
        'web_reverse_browser_detector',
        'read version of $executable',
        error,
        stack,
      );
    }
    return null;
  }
}

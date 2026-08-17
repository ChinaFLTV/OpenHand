import 'dart:io';

import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../util/bounded_file_io.dart';

const Duration _chromeFileProbeTimeout = Duration(milliseconds: 500);
const Duration _chromeProcessProbeTimeout = Duration(seconds: 2);
const Duration _chromeSpotlightTimeout = Duration(seconds: 3);

class GoogleChromeRuntimeProbe {
  const GoogleChromeRuntimeProbe({this.executablePath, this.versionLine});

  final String? executablePath;
  final String? versionLine;

  bool get isInstalled => executablePath != null;
}

class GoogleChromeRuntimeDetector {
  Future<GoogleChromeRuntimeProbe> detect() async {
    final executable = Platform.isMacOS
        ? await _detectMacOS()
        : Platform.isWindows
        ? await _detectWindows()
        : Platform.isLinux
        ? await _findOnPath(const <String>[
            'google-chrome',
            'google-chrome-stable',
            'chrome',
          ])
        : null;
    return GoogleChromeRuntimeProbe(
      executablePath: executable,
      versionLine: executable == null ? null : await _readVersion(executable),
    );
  }

  Future<String?> _detectMacOS() async {
    final spotlight = await runProcessWithTimeout(
      'mdfind',
      const <String>['kMDItemCFBundleIdentifier == "com.google.Chrome"'],
      timeout: _chromeSpotlightTimeout,
      tag: 'google_chrome_runtime_detector',
    );
    final app = spotlight?.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .firstWhere(
          (line) =>
              line.endsWith('.app') &&
              !line.contains('/.Trash/') &&
              !line.contains('/.Trashes/'),
          orElse: () => '',
        );
    for (final candidate in <String>[
      if (app?.isNotEmpty == true) '$app/Contents/MacOS/Google Chrome',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '${Platform.environment['HOME'] ?? ''}/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    ]) {
      if (await _isExecutable(candidate)) return candidate;
    }
    return _findOnPath(const <String>['google-chrome']);
  }

  Future<String?> _detectWindows() async {
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    for (final candidate in <String>[
      '$programFiles\\Google\\Chrome\\Application\\chrome.exe',
      '$programFilesX86\\Google\\Chrome\\Application\\chrome.exe',
      if (localAppData.isNotEmpty)
        '$localAppData\\Google\\Chrome\\Application\\chrome.exe',
    ]) {
      if (await _isExecutable(candidate)) return candidate;
    }
    final registry = await runProcessWithTimeout(
      'reg.exe',
      const <String>[
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        '/ve',
      ],
      timeout: _chromeProcessProbeTimeout,
      tag: 'google_chrome_runtime_detector',
    );
    final match = RegExp(
      r'REG_SZ\s+(.+\.exe)',
      caseSensitive: false,
    ).firstMatch(registry?.stdout.toString() ?? '');
    final path = match?.group(1)?.trim();
    return path != null && await _isExecutable(path) ? path : null;
  }

  Future<String?> _findOnPath(List<String> commands) async {
    for (final command in commands) {
      final result = await runProcessWithTimeout(
        Platform.isWindows ? 'where.exe' : '/usr/bin/which',
        <String>[command],
        timeout: _chromeProcessProbeTimeout,
        tag: 'google_chrome_runtime_detector',
      );
      final path = result?.stdout.toString().split('\n').first.trim();
      if (path != null && path.isNotEmpty && await _isExecutable(path)) {
        return path;
      }
    }
    return null;
  }

  Future<String?> _readVersion(String executable) async {
    try {
      final result = await runProcessWithTimeout(
        executable,
        const <String>['--version'],
        timeout: _chromeProcessProbeTimeout,
        tag: 'google_chrome_runtime_detector',
      );
      final version = result?.stdout.toString().trim();
      return version?.isNotEmpty == true ? version : null;
    } catch (error, stack) {
      silentLog('google_chrome_runtime_detector', '读取 Chrome 版本', error, stack);
      return null;
    }
  }

  Future<bool> _isExecutable(String path) => isRegularFilePath(
    path,
    timeout: _chromeFileProbeTimeout,
    followLinks: true,
  );
}

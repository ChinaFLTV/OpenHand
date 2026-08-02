import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/platform_environment.dart';

/// Web 逆向会话支持的 Chromium 同核浏览器候选清单。
///
/// Chrome 是首选；用户未安装 Chrome 时按下面顺序探测同核降级品。
/// 选定结果会写入会话 metadata `web_reverse_config.browser_kind`，复用
/// 时无需再次扫描。
enum WebReverseBrowserKind {
  /// Google Chrome 正式版（推荐）。
  chrome(
    'chrome',
    'Google Chrome',
    'com.google.Chrome',
    '/Applications/Google Chrome.app',
  ),

  /// Google Chrome Beta / Canary（同核，行为高度一致）。
  chromeBeta(
    'chrome_beta',
    'Google Chrome Beta',
    'com.google.Chrome.beta',
    '/Applications/Google Chrome Beta.app',
  ),

  /// Microsoft Edge（Chromium 内核，CDP 接口完全等价）。
  edge(
    'edge',
    'Microsoft Edge',
    'com.microsoft.edgemac',
    '/Applications/Microsoft Edge.app',
  ),

  /// Brave Browser（Chromium 内核）。
  brave(
    'brave',
    'Brave Browser',
    'com.brave.Browser',
    '/Applications/Brave Browser.app',
  ),

  /// 任意 Chromium 主线（社区构建）。
  chromium(
    'chromium',
    'Chromium',
    'org.chromium.Chromium',
    '/Applications/Chromium.app',
  );

  const WebReverseBrowserKind(
    this.id,
    this.displayName,
    this.macBundleId,
    this.macAppPath,
  );

  final String id;
  final String displayName;
  final String macBundleId;
  final String macAppPath;

  /// 在 PATH 上探测时使用的 CLI 名候选（按优先级排列）。
  /// 主要给 Linux / Windows 兜底。
  List<String> get cliCandidates => switch (this) {
    WebReverseBrowserKind.chrome => const [
      'google-chrome',
      'google-chrome-stable',
      'chrome',
    ],
    WebReverseBrowserKind.chromeBeta => const ['google-chrome-beta'],
    WebReverseBrowserKind.edge => const ['microsoft-edge', 'msedge'],
    WebReverseBrowserKind.brave => const ['brave-browser', 'brave'],
    WebReverseBrowserKind.chromium => const ['chromium', 'chromium-browser'],
  };

  /// Windows 下默认安装路径候选（绝对路径，支持 64-bit / 32-bit）。
  List<String> get windowsExecutableCandidates {
    final pf = platformEnvironmentValue('ProgramFiles') ?? r'C:\Program Files';
    final pfx86 =
        platformEnvironmentValue('ProgramFiles(x86)') ??
        r'C:\Program Files (x86)';
    final localApp = platformEnvironmentValue('LOCALAPPDATA') ?? '';
    return switch (this) {
      WebReverseBrowserKind.chrome => [
        '$pf\\Google\\Chrome\\Application\\chrome.exe',
        '$pfx86\\Google\\Chrome\\Application\\chrome.exe',
        if (localApp.isNotEmpty)
          '$localApp\\Google\\Chrome\\Application\\chrome.exe',
      ],
      WebReverseBrowserKind.chromeBeta => [
        '$pf\\Google\\Chrome Beta\\Application\\chrome.exe',
        '$pfx86\\Google\\Chrome Beta\\Application\\chrome.exe',
      ],
      WebReverseBrowserKind.edge => [
        '$pf\\Microsoft\\Edge\\Application\\msedge.exe',
        '$pfx86\\Microsoft\\Edge\\Application\\msedge.exe',
      ],
      WebReverseBrowserKind.brave => [
        '$pf\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
        '$pfx86\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
      ],
      WebReverseBrowserKind.chromium => const [],
    };
  }

  static WebReverseBrowserKind? fromId(String? id) {
    return enumByStorageValue(values, id, (kind) => kind.id);
  }
}

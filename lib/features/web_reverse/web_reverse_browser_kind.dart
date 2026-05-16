/// Web 逆向会话支持的 Chromium 同核浏览器候选清单。
///
/// Chrome 是首选；用户未安装 Chrome 时按下面顺序探测同核降级品。
/// 选定结果会写入会话 metadata `web_reverse_config.browser_kind`，复用
/// 时无需再次扫描。
enum WebReverseBrowserKind {
  /// Google Chrome 正式版（推荐）。
  chrome('chrome', 'Google Chrome', 'com.google.Chrome', '/Applications/Google Chrome.app'),

  /// Google Chrome Beta / Canary（同核，行为高度一致）。
  chromeBeta('chrome_beta', 'Google Chrome Beta', 'com.google.Chrome.beta', '/Applications/Google Chrome Beta.app'),

  /// Microsoft Edge（Chromium 内核，CDP 接口完全等价）。
  edge('edge', 'Microsoft Edge', 'com.microsoft.edgemac', '/Applications/Microsoft Edge.app'),

  /// Brave Browser（Chromium 内核）。
  brave('brave', 'Brave Browser', 'com.brave.Browser', '/Applications/Brave Browser.app'),

  /// 任意 Chromium 主线（社区构建）。
  chromium('chromium', 'Chromium', 'org.chromium.Chromium', '/Applications/Chromium.app');

  const WebReverseBrowserKind(this.id, this.displayName, this.macBundleId, this.macAppPath);

  final String id;
  final String displayName;
  final String macBundleId;
  final String macAppPath;

  static WebReverseBrowserKind? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

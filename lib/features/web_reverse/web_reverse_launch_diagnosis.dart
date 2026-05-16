/// 把 launcher 抛出的原始错误（标题 + stderr 摘要）解析成结构化诊断：
///   - 现象 phenomenon
///   - 根因 cause（可能多条命中）
///   - 建议 suggestion（针对每条 cause 的可操作建议）
///
/// 调用方拿到结构化结果后，可以渲染成"现象/原因/建议"三段式 UI，
/// 而不只是甩一段长 stderr 给用户。所有匹配规则都来自 Chromium
/// 源码里 stderr 高频字串，覆盖 macOS / Windows / Linux。
///
/// 如果没有任何规则命中，会回退到一条默认建议（关闭已开 Chrome、
/// 清理 SingletonLock 后重试），保证用户至少能拿到一条 next step。
class WebReverseLaunchDiagnosis {
  /// 把 launcher 抛出的 String 走规则匹配，返回结构化诊断。
  factory WebReverseLaunchDiagnosis.parse(String fullText) {
    final lower = fullText.toLowerCase();
    final matched = <WebReverseLaunchCause>[];
    bool has(List<String> needles) =>
        needles.any((n) => lower.contains(n.toLowerCase()));

    // ① profile 锁占用：另一个 Chrome 实例咬着同一个 user-data-dir。
    if (has(const [
      'profile is in use',
      'profile is locked',
      'singletonlock',
      'cannot create lock',
      'failed to create temp dir',
      'lock file is held by another process',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: 'Profile 锁被另一个 Chrome 实例占用',
        suggestion:
            '关闭所有 Chrome 进程后，点击"清理冲突 profile"按钮删除 SingletonLock 等残留锁文件，再重试。',
      ));
    }

    // ② 端口被占：另一个 CDP 实例在 9222-9322 区间。
    if (has(const [
      'address already in use',
      'failed to bind',
      'eaddrinuse',
      'already bound',
      'remote debugging port unavailable',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: '远端调试端口被占用',
        suggestion:
            '退出已存在的 Chrome / Edge / Brave 实例，或用 lsof / netstat 找到占用 9222-9322 的进程后再启动。',
      ));
    }

    // ③ 企业策略 / Origin 被拒：常见于公司机器。
    if (has(const [
      'remote-allow-origins',
      'devtools_remote_origin',
      'enterprise policy',
      'managed by your organization',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: '企业策略拒绝远端调试',
        suggestion:
            '检查 /Library/Managed Preferences/com.google.Chrome.plist（macOS）或注册表 HKLM\\Software\\Policies\\Google\\Chrome 是否禁用了 RemoteDebuggingAllowed；如确认无影响，可临时换一个个人浏览器（Brave / Chrome Beta）。',
      ));
    }

    // ④ 沙箱 / SUID 失败：典型 Linux 用户 + 部分 macOS 升级后的环境。
    if (has(const [
      'sandbox',
      'no usable sandbox',
      'suid sandbox',
      'failed to launch',
      'crash_handler',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: '沙箱初始化失败',
        suggestion:
            '在 Linux 上确保 /usr/lib/chromium-browser/chrome-sandbox 设置了 SUID；或临时使用 --no-sandbox 启动（仅作排错，正式使用务必恢复）。',
      ));
    }

    // ⑤ GPU / Metal 初始化崩溃：macOS 升级 / 显卡驱动差。
    if (has(const [
      'gpu process',
      'metal',
      'angle',
      'vulkan',
      'gpu init failed',
      'gl error',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: 'GPU 进程初始化失败',
        suggestion:
            '尝试加 --disable-gpu 启动（需要 launcher 配合开放 extra args），或更新显卡驱动 / 系统版本后重试。',
      ));
    }

    // ⑥ 安全软件拦截 127.0.0.1：常见于 360 / Norton / Kaspersky。
    if (has(const [
      'connection refused',
      'access denied',
      'permission denied',
      'firewall',
    ])) {
      matched.add(const WebReverseLaunchCause(
        title: '安全软件 / 防火墙拦截 127.0.0.1 监听',
        suggestion:
            '把 OpenHand.app 与浏览器可执行文件加入安全软件信任列表，并允许其监听 9222-9322 端口；macOS 上同时检查"系统设置 → 网络 → 防火墙"。',
      ));
    }

    // ⑦ 探测请求超时但 stderr 为空：纯网络/系统代理拦截。
    if (has(const [
      'cdp 握手超时',
      '握手超时',
      'http 4',
      'http 5',
    ]) &&
        matched.isEmpty) {
      matched.add(const WebReverseLaunchCause(
        title: '/json/version 探测请求被系统代理拦截',
        suggestion:
            '检查系统是否启用了透明代理 / VPN / Proxifier 等会拦 127.0.0.1 流量的工具；OpenHand 的探测走纯本地，请把 127.0.0.1 加入代理白名单。',
      ));
    }

    // 默认兜底：至少给一条可操作建议。
    if (matched.isEmpty) {
      matched.add(const WebReverseLaunchCause(
        title: '未匹配到具体子类型',
        suggestion:
            '请展开下方"原始报错"按钮把详情复制给开发者；可先尝试关闭所有 Chrome 实例 + 点"清理冲突 profile" + 重试。',
      ));
    }

    // 现象提取：取第一行（launcher 已经把"现象"放在标题）。
    final phenomenon = fullText.split('\n').first.trim();
    return WebReverseLaunchDiagnosis(
      phenomenon: phenomenon.isEmpty ? '浏览器启动失败' : phenomenon,
      causes: matched,
      fullText: fullText,
    );
  }

  const WebReverseLaunchDiagnosis({
    required this.phenomenon,
    required this.causes,
    required this.fullText,
  });

  /// 现象一句话，如「CDP 握手超时」。
  final String phenomenon;

  /// 命中的根因列表，按可能性从高到低排列；至少含一条兜底。
  final List<WebReverseLaunchCause> causes;

  /// 原始 launcher 抛出的完整错误文案，提供给"原始报错"折叠区。
  final String fullText;
}

class WebReverseLaunchCause {
  const WebReverseLaunchCause({required this.title, required this.suggestion});
  final String title;
  final String suggestion;
}

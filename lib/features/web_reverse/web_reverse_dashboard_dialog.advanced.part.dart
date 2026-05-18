part of 'web_reverse_dashboard_dialog.dart';

/// 高级工具弹窗：列出"持久化 Header / CDP 命令面板 / 体检报告 / 反向脚本 /
/// 调用图聚合 / 对比模式 / Service Worker 干预"等低频但有用的入口。
class _AdvancedMenuDialog extends StatelessWidget {
  const _AdvancedMenuDialog({required this.controller, required this.isZh});

  final WebReverseSessionController controller;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = <_AdvancedEntry>[
      _AdvancedEntry(
        icon: Icons.archive_rounded,
        title: isZh ? '导出会话体检报告' : 'Export session bundle',
        subtitle: isZh
            ? '一键打包 HAR + console + 截图 + recorder 为 .zip'
            : 'Bundle HAR + console + screenshots + recorder as .zip',
        onTap: () async {
          Navigator.of(context).pop();
          final messenger = ScaffoldMessenger.of(context);
          final path = await controller.exportSessionBundle();
          if (!context.mounted) return;
          if (path == null) {
            OpenHandSnackBar.showErrorOn(
              context,
              messenger,
              isZh ? '导出失败' : 'Export failed',
              duration: const Duration(seconds: 3),
            );
          } else {
            OpenHandSnackBar.showSuccessOn(
              context,
              messenger,
              isZh ? '已导出到 $path' : 'Exported to $path',
              duration: const Duration(seconds: 3),
            );
          }
        },
      ),      _AdvancedEntry(
        icon: Icons.add_link_rounded,
        title: isZh ? '持久注入 Headers' : 'Persistent Headers',
        subtitle: isZh
            ? '所有请求自动追加 Header（X-Debug 等场景）'
            : 'Auto-append headers on every request',
        onTap: () async {
          Navigator.of(context).pop();
          await _showExtraHeadersDialog(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: isZh ? '网络拦截规则' : 'Network intercept rules',
        subtitle: isZh
            ? 'URL 通配 → block / 重写 URL / 追加 Header；命中即自动放行'
            : 'URL pattern → block / rewrite URL / inject headers',
        onTap: () async {
          Navigator.of(context).pop();
          await _showInterceptRulesDialog(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.code_rounded,
        title: isZh ? 'CDP 命令面板' : 'CDP Command Palette',
        subtitle: isZh
            ? '原始 CDP method + JSON params；power-user 逃生通道'
            : 'Raw CDP method + JSON params; power-user escape hatch',
        onTap: () async {
          Navigator.of(context).pop();
          await _showCdpPaletteDialog(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.auto_awesome_rounded,
        title: isZh ? 'AI 分析最近请求' : 'AI analyse latest requests',
        subtitle: isZh
            ? '把最近 10 条请求摘要复制到剪贴板，粘贴回会话即由 AI 解读'
            : 'Copy last 10 request summaries; paste into chat for AI analysis',
        onTap: () async {
          Navigator.of(context).pop();
          await _copyRecentRequestsForAi(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.compare_arrows_rounded,
        title: isZh ? '对比两个请求' : 'Diff two requests',
        subtitle: isZh
            ? '选两条请求查 headers / body / response 字段差异'
            : 'Pick two requests to diff headers / body / response',
        onTap: () async {
          Navigator.of(context).pop();
          await _showDiffPicker(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.cloud_off_rounded,
        title: isZh ? 'Service Worker 列表' : 'Service Workers',
        subtitle: isZh
            ? '查看注册的 SW + 一键 unregister'
            : 'Inspect registered SWs and unregister',
        onTap: () async {
          Navigator.of(context).pop();
          await _showServiceWorkersDialog(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.dns_rounded,
        title: isZh ? '启动 HAR 重放服务器' : 'Start HAR replay server',
        subtitle: isZh
            ? '把当前 HAR 跑成本地 mock，复现脚本走 127.0.0.1:N'
            : 'Mock current HAR on localhost; reproduce scripts can hit 127.0.0.1:N',
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleHarReplayServer(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.swap_calls_rounded,
        title: controller.mitmproxyBridge == null
            ? (isZh ? '启动 mitmproxy 桥接' : 'Start mitmproxy bridge')
            : (isZh
                ? '停止 mitmproxy 桥接（已抓 ${controller.mitmproxyCount}）'
                : 'Stop mitmproxy bridge (${controller.mitmproxyCount})'),
        subtitle: isZh
            ? '系统级抓包：把 App 内嵌 webview / 第三方应用流量也接入 dashboard'
            : 'System-wide capture via mitmdump; routes 3rd-party app traffic into dashboard',
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleMitmproxyBridge(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.video_camera_back_rounded,
        title: isZh ? 'WebRTC 资源捕获' : 'WebRTC capture',
        subtitle: isZh
            ? '注入 RTCPeerConnection hook，抓 SDP / ICE / Track 事件'
            : 'Hook RTCPeerConnection to capture SDP / ICE / Track events',
        onTap: () async {
          Navigator.of(context).pop();
          await _toggleWebRtcCapture(context, controller, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.code_off_rounded,
        title: isZh ? 'JS 反混淆（webcrack）' : 'JS deobfuscate (webcrack)',
        subtitle: isZh
            ? '用 npx webcrack 把粘贴的 JS 还原成可读形式（需 Node.js）'
            : 'Run npx webcrack on pasted JS (Node.js required)',
        onTap: () async {
          Navigator.of(context).pop();
          await _showWebcrackDialog(context, isZh);
        },
      ),
      _AdvancedEntry(
        icon: Icons.fingerprint_rounded,
        title: isZh ? '签名字段变量定位器' : 'Signature Field Locator',
        subtitle: isZh
            ? '同 endpoint 多次抓包后自动识别动态字段（sign / ts / nonce）'
            : 'Identify dynamic fields (sign / ts / nonce) across repeated captures',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSignatureDiffDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.notifications_active_rounded,
        title: isZh ? '报文条件断点' : 'Request Breakpoints',
        subtitle: isZh
            ? 'URL/Body 子串命中 → 记录命中事件 + 可选触发 JS 表达式'
            : 'URL/body substring match → log hits + optional JS eval',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseRequestBreakpointsDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.switch_account_rounded,
        title: isZh ? '多账号会话快照' : 'Account Snapshots',
        subtitle: isZh
            ? '保存 cookies + storage → 一键在不同账号间切换'
            : 'Save cookies + storage → one-click switch between accounts',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseAccountSnapshotsDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.bar_chart_rounded,
        title: isZh ? '代码覆盖率面板' : 'JS Coverage',
        subtitle: isZh
            ? 'Start → 操作页面 → Take 查看哪些脚本被执行'
            : 'Start → use the page → Take to see which scripts ran',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCoverageDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.ios_share_rounded,
        title: isZh ? 'API 集合导出' : 'Export Collection',
        subtitle: isZh
            ? 'Postman / Insomnia / Bruno / cURL / HAR 一键复制'
            : 'Postman / Insomnia / Bruno / cURL / HAR — copy to clipboard',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCollectionExportDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.wifi_tethering_rounded,
        title: isZh ? 'WebSocket 主动注入' : 'WebSocket Inject',
        subtitle: isZh
            ? '代理 window.WebSocket → 选中连接 → 注入任意文本帧'
            : 'Proxy window.WebSocket → pick a socket → inject any text frame',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWsInjectDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: isZh ? '本地 Mock 拦截' : 'Local Mock',
        subtitle: isZh
            ? 'URL 通配命中 → 自定义 status/headers/body 直接返回'
            : 'URL match → return canned status/headers/body',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseMockRulesDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.visibility_rounded,
        title: isZh ? '变量监视器' : 'Watch Expressions',
        subtitle: isZh
            ? '定时 Runtime.evaluate 任意 JS 表达式，记录历史采样'
            : 'Periodic Runtime.evaluate on JS expressions, history tracked',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWatchDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: isZh ? 'DOM Mutation 录制' : 'DOM Mutation Recorder',
        subtitle: isZh
            ? '注入 MutationObserver → attributes/characterData/childList 时间线'
            : 'Inject MutationObserver → timeline of all DOM changes',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDomMutationDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.public_rounded,
        title: isZh ? '地理 / 时区 / 语言覆盖' : 'Geo / TZ / Locale Override',
        subtitle: isZh
            ? '一键伪装当前 target 的 GPS / timezone / navigator.language'
            : 'Spoof current target GPS / timezone / navigator.language',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseGeoOverrideDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.fingerprint_rounded,
        title: isZh ? 'WebAuthn 虚拟认证器' : 'WebAuthn Virtual Authenticator',
        subtitle: isZh
            ? '注入虚拟 FIDO2 设备，无物理密钥完成 navigator.credentials 流程'
            : 'Inject virtual FIDO2 device, complete navigator.credentials without hardware',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWebAuthnDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.vpn_key_rounded,
        title: isZh ? 'JWT 自动续期' : 'JWT Auto Refresh',
        subtitle: isZh
            ? '扫描 cookies/localStorage/sessionStorage 中的 JWT，临近过期自动跰刷新脚本'
            : 'Scan JWT in cookies/storage, run refresh JS near expiry',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseJwtRefreshDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.lock_open_rounded,
        title: isZh ? 'AI 加密参数还原' : 'AI Crypto Param Recover',
        subtitle: isZh
            ? '同 endpoint 多次 diff + JS 全文搜索命中，复制成 AI 可吃的提示词'
            : 'Diff repeated endpoint hits + search JS, copy as AI-ready prompt',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseAiCryptoDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.swap_horiz_rounded,
        title: isZh ? 'postMessage 追踪' : 'postMessage Trace',
        subtitle: isZh
            ? '注入 hook 收录跨窗口消息，含发送方向与 iframe'
            : 'Inject hook to capture cross-window messages incl. iframe',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReversePostMessageDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: isZh ? '请求瀑布图' : 'Network Waterfall',
        subtitle: isZh
            ? 'TTFB / 下载两段可视化，按耗时/大小/时间排序'
            : 'Visualize TTFB / download segments, sort by time/size/duration',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseWaterfallDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.account_tree_rounded,
        title: isZh ? 'JS 调用图' : 'JS Callgraph',
        subtitle: isZh
            ? '启发式正则解析所有 frame 脚本，构造 caller→callees 邻接表'
            : 'Heuristic regex parsing of frame scripts; build caller→callees graph',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCallgraphDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.network_check_rounded,
        title: isZh ? '网络限速模拟' : 'Network Throttle',
        subtitle: isZh
            ? 'Network.emulateNetworkConditions 预设/自定义 kbps + 延迟 + 离线 + 禁用缓存'
            : 'Network.emulateNetworkConditions presets/custom kbps + latency + offline + cache off',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseThrottleDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.save_as_rounded,
        title: isZh ? 'HAR 全量持久化' : 'HAR Persistence',
        subtitle: isZh
            ? '立即落盘 / 反向加载 / 周期自动轮转'
            : 'Save now / Load back / Periodic rotation',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseHarPersistenceDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.cookie_rounded,
        title: isZh ? 'Cookie 编辑器' : 'Cookie Editor',
        subtitle: isZh
            ? 'Network.getCookies / setCookie / deleteCookies 精修级 CRUD'
            : 'Network.getCookies / setCookie / deleteCookies — fine CRUD',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCookieEditorDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.miscellaneous_services_rounded,
        title: isZh ? 'Service Worker 调试' : 'Service Worker Debug',
        subtitle: isZh
            ? '启停 / 强制更新 / 注销 / 触发 sync / 送 push'
            : 'Start/stop, force-update, unregister, dispatch sync, push',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSwDebugDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.timeline_rounded,
        title: isZh ? 'Performance Trace' : 'Performance Trace',
        subtitle: isZh
            ? '录制 Tracing → chrome-trace JSON（Perfetto 可加载）'
            : 'Record Tracing → chrome-trace JSON',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReversePerfTraceDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.memory_rounded,
        title: isZh ? 'Heap Snapshot' : 'Heap Snapshot',
        subtitle: isZh
            ? 'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可加载）'
            : 'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseHeapSnapshotDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.terminal_rounded,
        title: isZh ? 'Console REPL' : 'Console REPL',
        subtitle: isZh
            ? 'Runtime.evaluate · 多行 JS · 历史记录 + 快捷键'
            : 'Runtime.evaluate · multi-line JS · history + shortcuts',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseReplDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.account_tree_rounded,
        title: isZh ? 'Frame 树查看器' : 'Frame Tree',
        subtitle: isZh
            ? 'Page.getFrameTree · 主框架 + 嵌套 iframe 递归'
            : 'Page.getFrameTree · main + nested iframes',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseFrameTreeDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.style_rounded,
        title: isZh ? 'CSS 规则使用率' : 'CSS Rule Coverage',
        subtitle: isZh
            ? 'CSS.startRuleUsageTracking · 找出未命中的死代码'
            : 'CSS.startRuleUsageTracking · find dead rules',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCssCoverageDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.replay_circle_filled_rounded,
        title: isZh ? '网络请求重放器' : 'Network Replayer',
        subtitle: isZh
            ? '多选请求 · 顺序重发 · 对比状态'
            : 'multi-select · sequential replay · status diff',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseReplayDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.ads_click_rounded,
        title: isZh ? '输入事件模拟' : 'Input Simulator',
        subtitle: isZh
            ? 'dispatchMouseEvent / dispatchKeyEvent / insertText'
            : 'dispatchMouseEvent / dispatchKeyEvent / insertText',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseInputSimDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.devices_other_rounded,
        title: isZh ? '设备模拟' : 'Device Emulation',
        subtitle: isZh
            ? '尺寸 / DPR / mobile flag / UA 覆写'
            : 'metrics / DPR / mobile / UA override',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDeviceEmulationDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.speed_rounded,
        title: isZh ? 'CPU 限速' : 'CPU Throttling',
        subtitle: isZh
            ? 'Emulation.setCPUThrottlingRate · 1×–20×'
            : 'Emulation.setCPUThrottlingRate · 1×–20×',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseCpuThrottleDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.travel_explore_rounded,
        title: isZh ? 'DOM 选择器搜索' : 'DOM Selector Search',
        subtitle: isZh
            ? 'DOM.performSearch · CSS / text / XPath · 高亮'
            : 'DOM.performSearch · CSS / text / XPath · highlight',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseDomSearchDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
      _AdvancedEntry(
        icon: Icons.alt_route_rounded,
        title: isZh ? 'SourceMap 反解析' : 'SourceMap Resolver',
        subtitle: isZh
            ? 'min file:line:col → 原始 source:line:col'
            : 'min file:line:col → original source:line:col',
        onTap: () async {
          Navigator.of(context).pop();
          await showWebReverseSourceMapDialog(
            context,
            controller: controller,
            isZh: isZh,
          );
        },
      ),
    ];
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isZh ? '高级工具' : 'Advanced tools',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, idx) {
                  final e = entries[idx];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: e.onTap,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(e.icon, size: 20, color: cs.primary),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.title,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.subtitle,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvancedEntry {
  _AdvancedEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

Future<void> _showExtraHeadersDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final ctrlText = TextEditingController(
    text: ctrl.extraHeaders.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n'),
  );
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? '持久注入 Headers' : 'Persistent Headers'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh
                  ? '每行一个 Key: Value；保存后所有请求自动附带，留空则清空。'
                  : 'One header per line in `Key: Value` form; empty to clear.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrlText,
              maxLines: 10,
              minLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: isZh ? '保存' : 'Save',
        ),
      ],
    ),
  );
  if (ok != true) return;
  final headers = <String, String>{};
  for (final line in ctrlText.text.split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
  }
  final saved = await ctrl.setExtraHttpHeaders(headers);
  if (!context.mounted) return;
  if (saved) {
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      isZh ? '已注入 ${headers.length} 个 Header' : 'Injected ${headers.length} headers',
    );
  } else {
    OpenHandSnackBar.showErrorOn(
      context,
      messenger,
      isZh ? '保存失败' : 'Save failed',
      duration: const Duration(seconds: 2),
    );
  }
}

Future<void> _showCdpPaletteDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final method = TextEditingController();
  final params = TextEditingController(text: '{}');
  final result = ValueNotifier<String?>(null);
  final useSession = ValueNotifier<bool>(true);
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? 'CDP 命令面板' : 'CDP Command Palette'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: method,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  hintText: 'Network.getAllCookies / DOM.querySelector',
                  border: OutlineInputBorder(),
                ),
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: params,
                maxLines: 8,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Params (JSON)',
                  border: OutlineInputBorder(),
                ),
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder(
                valueListenable: useSession,
                builder: (_, v, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    isZh
                        ? '在当前 Page 会话内执行（关掉则用 Browser 根 session）'
                        : 'Use current page session (off = browser root session)',
                  ),
                  value: v,
                  onChanged: (n) => useSession.value = n,
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder(
                valueListenable: result,
                builder: (_, v, _) => v == null
                    ? const SizedBox.shrink()
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .outlineVariant),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            v,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () async {
            final m = method.text.trim();
            if (m.isEmpty) return;
            final r = await ctrl.sendRawCdp(
              method: m,
              paramsJson: params.text,
              useSession: useSession.value,
            );
            result.value =
                r == null ? '(null)' : const JsonEncoder.withIndent('  ').convert(r);
          },
          label: isZh ? '执行' : 'Run',
        ),
      ],
    ),
  );
}

Future<void> _copyRecentRequestsForAi(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final entries = ctrl.networkRequests.reversed.take(10).toList();
  if (entries.isEmpty) {
    OpenHandSnackBar.showInfoOn(
      context,
      messenger,
      isZh ? '当前无请求可分析' : 'No requests yet',
      duration: const Duration(seconds: 2),
    );
    return;
  }
  final buf = StringBuffer()
    ..writeln(isZh
        ? '请帮我分析这 ${entries.length} 条请求里哪些是关键加密参数（sign / token / encrypt 等），并指出可能的算法与种子。'
        : 'Please identify the encryption-relevant fields (sign / token / encrypt) in these ${entries.length} requests and guess the algorithm.')
    ..writeln('---');
  for (final e in entries) {
    buf
      ..writeln('[${e.method}] ${e.url}')
      ..writeln('Status: ${e.statusCode ?? '-'}  Type: ${e.resourceType}');
    if (e.requestPostData != null && e.requestPostData!.isNotEmpty) {
      var body = e.requestPostData!;
      if (body.length > 1024) body = '${body.substring(0, 1024)}…';
      buf.writeln('Body: $body');
    }
    if (e.requestHeaders.isNotEmpty) {
      final keys = e.requestHeaders.keys
          .where((k) =>
              k.toLowerCase().contains('sign') ||
              k.toLowerCase().contains('token') ||
              k.toLowerCase().contains('auth') ||
              k.toLowerCase().contains('x-'))
          .toList();
      if (keys.isNotEmpty) {
        for (final k in keys) {
          buf.writeln('  $k: ${e.requestHeaders[k]}');
        }
      }
    }
    buf.writeln('---');
  }
  await Clipboard.setData(ClipboardData(text: buf.toString()));
  if (!context.mounted) return;
  OpenHandSnackBar.showSuccessOn(
    context,
    messenger,
    isZh ? '请求摘要已复制，回到会话粘贴即可让 AI 分析' : 'Summary copied; paste in chat',
    duration: const Duration(seconds: 3),
  );
}

Future<void> _showDiffPicker(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final all = ctrl.networkRequests;
  if (all.length < 2) {
    OpenHandSnackBar.showInfo(
      context,
      isZh ? '请求数不足，无法对比' : 'Need at least 2 requests',
      duration: const Duration(seconds: 2),
    );
    return;
  }
  CdpNetworkEntry? a;
  CdpNetworkEntry? b;
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AlertDialog(
        title: Text(isZh ? '选择两个请求对比' : 'Pick two requests'),
        content: SizedBox(
          width: 640,
          height: 460,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: all.length,
                  itemBuilder: (_, idx) {
                    final e = all[all.length - 1 - idx];
                    final selectedAs = identical(e, a)
                        ? 'A'
                        : (identical(e, b) ? 'B' : null);
                    return ListTile(
                      dense: true,
                      title: Text('${e.method} ${e.url}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                      subtitle: Text('${e.statusCode ?? '-'} · ${e.resourceType}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: selectedAs == null
                          ? null
                          : Text(selectedAs,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          if (a == null) {
                            a = e;
                          } else if (b == null && !identical(e, a)) {
                            b = e;
                          } else {
                            a = e;
                            b = null;
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: (a == null || b == null)
                ? null
                : () {
                    Navigator.of(dialogContext).pop();
                    showAnimatedDialog<void>(
                      context: context,
                      builder: (_) =>
                          _DiffViewerDialog(a: a!, b: b!, isZh: isZh),
                    );
                  },
            label: isZh ? '对比' : 'Diff',
          ),
        ],
      ),
    ),
  );
}

class _DiffViewerDialog extends StatelessWidget {
  const _DiffViewerDialog({
    required this.a,
    required this.b,
    required this.isZh,
  });

  final CdpNetworkEntry a;
  final CdpNetworkEntry b;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget col(String label, CdpNetworkEntry e) => Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label: ${e.method} ${e.url}',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(
                    'status=${e.statusCode ?? '-'} mime=${e.mimeType ?? '-'}'),
                const Divider(),
                const Text('Request headers:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      e.requestHeaders.entries
                          .map((kv) => '${kv.key}: ${kv.value}')
                          .join('\n'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  children: [
                    col('A', a),
                    const SizedBox(width: 12),
                    col('B', b),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showServiceWorkersDialog(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final list = await ctrl.listServiceWorkers();
  if (!context.mounted) return;
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? 'Service Workers' : 'Service Workers'),
      content: SizedBox(
        width: 560,
        child: list.isEmpty
            ? Text(isZh ? '当前 origin 无 SW 注册' : 'No service workers')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final w in list)
                    ListTile(
                      dense: true,
                      title: Text('${w['scriptURL'] ?? w['url'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                      subtitle: Text(
                          'state=${w['runningStatus'] ?? w['status'] ?? '-'}'),
                    ),
                ],
              ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
        if (list.isNotEmpty)
          OpenHandDialogActionButton.destructive(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // 用 Runtime.evaluate 调 navigator.serviceWorker.getRegistrations 一键 unregister。
              final r = await ctrl.runReplExpression(
                'navigator.serviceWorker.getRegistrations().then(rs => Promise.all(rs.map(r => r.unregister()))).then(rs => rs.length)',
              );
              if (!context.mounted) return;
              if (r == null) {
                OpenHandSnackBar.showErrorOn(
                  context,
                  messenger,
                  isZh ? '反注册失败' : 'Unregister failed',
                  duration: const Duration(seconds: 2),
                );
              } else {
                OpenHandSnackBar.showSuccessOn(
                  context,
                  messenger,
                  isZh ? '已反注册 $r 个 SW' : 'Unregistered $r SWs',
                );
              }
            },
            label: isZh ? '全部反注册' : 'Unregister all',
          ),
      ],
    ),
  );
}


Future<void> _toggleHarReplayServer(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final running = ctrl.harReplayServer;
  if (running != null) {
    await ctrl.stopHarReplayServer();
    if (!context.mounted) return;
    OpenHandSnackBar.showInfoOn(
      context,
      messenger,
      isZh ? '已停止 HAR 重放服务器' : 'HAR replay server stopped',
      duration: const Duration(seconds: 2),
    );
    return;
  }
  final r = await ctrl.startHarReplayServer();
  if (!context.mounted) return;
  if (r == null) {
    OpenHandSnackBar.showErrorOn(
      context,
      messenger,
      isZh ? '启动失败：HAR 不可用或端口被占' : 'Failed to start',
      duration: const Duration(seconds: 3),
    );
    return;
  }
  OpenHandSnackBar.show(
    context,
    messenger,
    OpenHandSnackBar.info(
      context,
      isZh
          ? 'HAR 重放服务器已启动：http://127.0.0.1:${r.port}/  · 已加载 ${r.entryCount} 条'
          : 'Replay server up at http://127.0.0.1:${r.port}/  · ${r.entryCount} entries',
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: isZh ? '复制端口' : 'Copy port',
        onPressed: () =>
            Clipboard.setData(ClipboardData(text: '${r.port}')),
      ),
    ),
  );
}


Future<void> _toggleMitmproxyBridge(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (ctrl.mitmproxyBridge != null) {
    await ctrl.stopMitmproxyBridge();
    if (!context.mounted) return;
    OpenHandSnackBar.showInfoOn(
      context,
      messenger,
      isZh ? '已停止 mitmproxy 桥接' : 'mitmproxy bridge stopped',
      duration: const Duration(seconds: 2),
    );
    return;
  }
  // 先确认 mitmdump 在 PATH。
  final exe = await WebReverseMitmproxyBridge.detectMitmdump();
  if (exe == null) {
    if (!context.mounted) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isZh ? '未检测到 mitmdump' : 'mitmdump not found'),
        content: Text(
          isZh
              ? '请先安装 mitmproxy（macOS：brew install mitmproxy；Linux：sudo apt install mitmproxy；Windows：从 https://mitmproxy.org 下载），'
                  '并把 mitmdump 加入 PATH。\n\n'
                  '装好后在客户端把代理指向 127.0.0.1:8080，并访问 http://mitm.it 安装根证书。'
              : 'Install mitmproxy (macOS: brew install mitmproxy; Linux: sudo apt install mitmproxy; Windows: https://mitmproxy.org), '
                  'then set client proxy to 127.0.0.1:8080 and trust the root cert via http://mitm.it.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: isZh ? '关闭' : 'Close',
          ),
        ],
      ),
    );
    return;
  }
  // 提示用户配置代理。
  if (!context.mounted) return;
  final go = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? '即将启动 mitmproxy 桥接' : 'Start mitmproxy bridge'),
      content: Text(
        isZh
            ? '将以 mitmdump -p 8080 启动；启动后请把目标客户端代理指向 127.0.0.1:8080。\n\n'
                '首次使用须信任根证书：访问 http://mitm.it 按平台说明安装。\n\n'
                '所有抓到的请求会以 mitmproxy 资源类型出现在 Network 列表。'
            : 'Will run mitmdump -p 8080; route your client proxy to 127.0.0.1:8080.\n\n'
                'First time? Trust the CA via http://mitm.it.\n\n'
                'Captured traffic shows up under the mitmproxy resource type.',
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: isZh ? '取消' : 'Cancel',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: isZh ? '启动' : 'Start',
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final r = await ctrl.startMitmproxyBridge();
  if (!context.mounted) return;
  if (r == null) {
    OpenHandSnackBar.showErrorOn(
      context,
      messenger,
      isZh ? '启动失败（端口 8080 可能已被占）' : 'Failed (port 8080 in use?)',
      duration: const Duration(seconds: 3),
    );
    return;
  }
  OpenHandSnackBar.showSuccessOn(
    context,
    messenger,
    isZh
        ? 'mitmproxy 桥接已启动：客户端代理 127.0.0.1:${r.mitmPort}（回调 :${r.callbackPort}）'
        : 'mitmproxy up: proxy via 127.0.0.1:${r.mitmPort} (callback :${r.callbackPort})',
    duration: const Duration(seconds: 6),
  );
}


Future<void> _toggleWebRtcCapture(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await ctrl.installWebRtcCapture();
  if (!context.mounted) return;
  if (!ok) {
    OpenHandSnackBar.showErrorOn(
      context,
      messenger,
      isZh ? '注入失败（page 可能尚未就绪）' : 'Install failed',
      duration: const Duration(seconds: 2),
    );
    return;
  }
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WebRtcLiveDialog(controller: ctrl, isZh: isZh),
  );
}

/// WebRTC 实时调试面板：每秒 poll readWebRtcLog 拉新增日志，分两个 tab：
/// ① 实时图表：按 PeerConnection id 维护 _RtcSeries（最近 60 个采样的
///    bytesSent / bytesReceived / packetsLost / rtt），用 _RtcChart 渲染
///    四条折线 + 当前值 chip；② 事件流：完整 JSON 日志 SelectableText。
class _WebRtcLiveDialog extends StatefulWidget {
  const _WebRtcLiveDialog({required this.controller, required this.isZh});

  final WebReverseSessionController controller;
  final bool isZh;

  @override
  State<_WebRtcLiveDialog> createState() => _WebRtcLiveDialogState();
}

class _WebRtcLiveDialogState extends State<_WebRtcLiveDialog> {
  Timer? _pollTimer;
  final Map<int, _RtcSeries> _series = <int, _RtcSeries>{};
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  static const int _maxEvents = 200;
  bool _disposed = false;
  int _selected = 0;
  // 0 = 图表，1 = ICE 拓扑，2 = SDP Diff，3 = 事件流。
  int _tab = 0;
  // 2026-05-24 Stage C 增强：ICE 候选项 + 连接状态历史，按 PC 维护。
  final Map<int, List<_IceEntry>> _iceLog = <int, List<_IceEntry>>{};
  // SDP 历史：每个 PC 维护 local / remote 各两份（最新 + 上一份），用于 diff。
  final Map<int, _SdpPair> _sdps = <int, _SdpPair>{};
  // 2026-05-24 — ICE tab 的「时序 / 图」视图切换。默认时序列表，用户切到
  // 图模式后用 _IceTopologyGraph 渲染当前 PC 的有向拓扑。
  bool _iceGraphMode = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final entries = await widget.controller.readWebRtcLog();
    if (_disposed || !mounted || entries.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      for (final e in entries) {
        final kind = '${e['kind'] ?? ''}';
        if (kind == 'stats') {
          final id = (e['id'] as num?)?.toInt() ?? 0;
          final s = _series.putIfAbsent(id, () => _RtcSeries());
          s.push(
            bytesSent: (e['bytesSent'] as num?)?.toDouble() ?? 0,
            bytesReceived: (e['bytesReceived'] as num?)?.toDouble() ?? 0,
            packetsLost: (e['packetsLost'] as num?)?.toDouble() ?? 0,
            rttMs: ((e['rtt'] as num?)?.toDouble() ?? 0) * 1000.0,
          );
          if (_selected == 0 && _series.isNotEmpty) {
            _selected = _series.keys.first;
          }
        } else {
          // 2026-05-24 Stage C：把控制平面事件（pc.create / track /
          // datachannel / icecandidate / connectionstatechange / SDP
          // result）分类塞进 _iceLog 与 _sdps；原始 JSON 仍保留事件
          // 流 tab 用。
          final id = (e['id'] as num?)?.toInt() ?? 0;
          if (id > 0) {
            if (kind == 'icecandidate' ||
                kind == 'pc.create' ||
                kind == 'track' ||
                kind == 'datachannel' ||
                kind == 'connectionstatechange' ||
                kind == 'iceconnectionstatechange') {
              _iceLog.putIfAbsent(id, () => <_IceEntry>[]).add(_IceEntry(
                    kind: kind,
                    payload: e,
                  ));
            }
            if (kind == 'setLocalDescription:result' ||
                kind == 'setRemoteDescription:result') {
              final sdp = e['sdp'] is String ? e['sdp'] as String : '';
              final type = '${e['type'] ?? ''}';
              final pair = _sdps.putIfAbsent(id, () => _SdpPair());
              if (kind == 'setLocalDescription:result') {
                pair.prevLocal = pair.local;
                pair.local = _SdpVersion(type: type, sdp: sdp);
              } else {
                pair.prevRemote = pair.remote;
                pair.remote = _SdpVersion(type: type, sdp: sdp);
              }
            }
          }
          _events.add(e);
          if (_events.length > _maxEvents) {
            _events.removeRange(0, _events.length - _maxEvents);
          }
        }
      }
    });
  }

  /// 把当前 _series 的全部 PC 拼成 CSV 并交给 file_selector 落盘。
  /// CSV schema：pc_id,bucket_seconds_ago,bytes_sent,bytes_received,
  /// packets_lost,rtt_ms。每行一个 sample，buckets 0 = 当前秒。
  Future<void> _exportSeriesCsv() async {
    if (_series.isEmpty) return;
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    final buf = StringBuffer()
      ..writeln('pc_id,bucket_seconds_ago,bytes_sent,bytes_received,'
          'packets_lost,rtt_ms');
    final ids = _series.keys.toList()..sort();
    for (final id in ids) {
      final samples = _series[id]!.samples;
      // samples[i] 表示第 i 次采集（按 push 顺序，最后一次是最新）。
      // bucket_seconds_ago = (n - 1 - i)，让最新一行 = 0。
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        buf.writeln(
          '$id,${samples.length - 1 - i},${s.bytesSent.toStringAsFixed(0)},'
          '${s.bytesReceived.toStringAsFixed(0)},'
          '${s.packetsLost.toStringAsFixed(0)},'
          '${s.rttMs.toStringAsFixed(2)}',
        );
      }
    }
    const typeGroup = XTypeGroup(label: 'CSV', extensions: <String>['csv']);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    FileSaveLocation? loc;
    try {
      loc = await getSaveLocation(
        suggestedName: 'webrtc-stats-$ts.csv',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard', 'rtc csv save', error, stack);
    }
    if (loc == null) return;
    try {
      await File(loc.path).writeAsString(buf.toString());
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? 'CSV 已保存' : 'CSV saved',
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard', 'rtc csv write', error, stack);
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '保存失败' : 'Save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.video_camera_back_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    isZh ? 'WebRTC 实时面板' : 'WebRTC live panel',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isZh
                          ? '${_series.length} 连接 · 1s 采样'
                          : '${_series.length} pc · 1s sample',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  _RtcTab(
                    label: isZh ? '实时图表' : 'Live charts',
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                  const SizedBox(width: 8),
                  _RtcTab(
                    label: isZh ? 'ICE 拓扑' : 'ICE topology',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                  const SizedBox(width: 8),
                  _RtcTab(
                    label: isZh ? 'SDP Diff' : 'SDP diff',
                    selected: _tab == 2,
                    onTap: () => setState(() => _tab = 2),
                  ),
                  const SizedBox(width: 8),
                  _RtcTab(
                    label: isZh ? '事件流' : 'Events',
                    selected: _tab == 3,
                    onTap: () => setState(() => _tab = 3),
                  ),
                  const Spacer(),
                  if (_tab == 0 && _series.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _exportSeriesCsv,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(isZh ? '导出 CSV' : 'Export CSV'),
                    ),
                  if (_tab == 3 && _events.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(_events),
                        ));
                        if (!mounted) return;
                        OpenHandSnackBar.showSuccessOn(
                          context,
                          messenger,
                          isZh ? '已复制' : 'Copied',
                          duration: const Duration(seconds: 1),
                        );
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: Text(isZh ? '复制事件' : 'Copy events'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_tab) {
                  0 => _buildChartsTab(theme),
                  1 => _buildIceTab(theme),
                  2 => _buildSdpDiffTab(theme),
                  _ => _buildEventsTab(theme),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    if (_series.isEmpty) {
      return Padding(
        key: const ValueKey('empty-charts'),
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Text(
            isZh
                ? '当前页面尚未发起 WebRTC。\n触发音视频通话或 datachannel 后会自动出现采样曲线。'
                : 'No WebRTC yet. Trigger a call/datachannel; samples will appear automatically.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final ids = _series.keys.toList()..sort();
    final selectedId = _series.containsKey(_selected) ? _selected : ids.first;
    final s = _series[selectedId]!;
    final last = s.last;
    return Padding(
      key: const ValueKey('charts'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                ChoiceChip(
                  label: Text('PC #$id'),
                  selected: id == selectedId,
                  onSelected: (_) => setState(() => _selected = id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _RtcStatChip(
                label: isZh ? '已发送' : 'Sent',
                value: _formatBytes(last?.bytesSent ?? 0),
                color: cs.primary,
              ),
              _RtcStatChip(
                label: isZh ? '已接收' : 'Recv',
                value: _formatBytes(last?.bytesReceived ?? 0),
                color: cs.tertiary,
              ),
              _RtcStatChip(
                label: isZh ? '丢包' : 'Lost',
                value: '${(last?.packetsLost ?? 0).toInt()}',
                color: cs.error,
              ),
              _RtcStatChip(
                label: 'RTT',
                value:
                    '${(last?.rttMs ?? 0).toStringAsFixed(0)} ms',
                color: cs.secondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: CustomPaint(
              painter: _RtcChartPainter(
                series: s,
                primary: cs.primary,
                tertiary: cs.tertiary,
                error: cs.error,
                secondary: cs.secondary,
                grid: cs.outlineVariant.withValues(alpha: 0.45),
                onSurface: cs.onSurfaceVariant,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  /// ICE 拓扑 tab：把每个 PC 的 pc.create / track / datachannel /
  /// icecandidate / connectionstatechange / iceconnectionstatechange 事件按
  /// 时间序列垂直列出来；左侧是 ChoiceChip 切 PC，右侧滚动列。本地候选
  /// （typ host）用 primary 色点；srflx / relay 用 tertiary；远端候选不
  /// 区分单独标 secondary。datachannel / track 单列前缀图标。
  ///
  /// 2026-05-24 — 顶部加「时序 / 图」切换：图模式用 CustomPainter 把
  /// candidate / track / datachannel 节点按 typ 分组围着 PC 节点展开成有
  /// 向图，箭头由 candidate 指向 PC、track 由 PC 指向 stream，让用户一眼
  /// 看清拓扑。
  Widget _buildIceTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final ids = _iceLog.keys.toList()..sort();
    if (ids.isEmpty) {
      return Padding(
        key: const ValueKey('empty-ice'),
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Text(
            isZh ? '暂无 ICE 事件' : 'No ICE events',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final selectedId =
        _iceLog.containsKey(_selected) ? _selected : ids.first;
    final entries = _iceLog[selectedId] ?? const <_IceEntry>[];
    return Padding(
      key: const ValueKey('ice'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final id in ids)
                    ChoiceChip(
                      label: Text('PC #$id · ${_iceLog[id]!.length}'),
                      selected: id == selectedId,
                      onSelected: (_) => setState(() => _selected = id),
                    ),
                ],
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.list_rounded, size: 14),
                    label: Text(isZh ? '时序' : 'List'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.hub_rounded, size: 14),
                    label: Text(isZh ? '图' : 'Graph'),
                  ),
                ],
                selected: {_iceGraphMode},
                onSelectionChanged: (s) =>
                    setState(() => _iceGraphMode = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _iceGraphMode
                ? _IceTopologyGraph(
                    pcId: selectedId,
                    entries: entries,
                    primary: cs.primary,
                    tertiary: cs.tertiary,
                    secondary: cs.secondary,
                    error: cs.error,
                    onSurface: cs.onSurface,
                    surfaceContainer: cs.surfaceContainerHigh,
                    isZh: isZh,
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      // 倒序展示：最新事件在顶部更易观察。
                      final entry = entries[entries.length - 1 - i];
                      final summary = _summarizeIce(entry, isZh);
                      final color = _iceTone(entry.kind, cs);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 5, right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                summary,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _iceTone(String kind, ColorScheme cs) {
    switch (kind) {
      case 'icecandidate':
        return cs.tertiary;
      case 'track':
      case 'datachannel':
        return cs.primary;
      case 'pc.create':
        return cs.secondary;
      case 'connectionstatechange':
      case 'iceconnectionstatechange':
        return cs.error;
    }
    return cs.onSurfaceVariant;
  }

  String _summarizeIce(_IceEntry entry, bool isZh) {
    final p = entry.payload;
    switch (entry.kind) {
      case 'pc.create':
        return 'pc.create · cfg=${jsonEncode(p['config'])}';
      case 'track':
        return 'track · ${p['kind']} state=${p['readyState']} '
            'streams=${p['streamIds']}';
      case 'datachannel':
        return 'datachannel · label=${p['label']} ordered=${p['ordered']}';
      case 'icecandidate':
        final cand = '${p['candidate'] ?? ''}';
        // candidate 字符串通常是 "candidate:foundation comp transport prio
        //  ip port typ <type> ..."；提取 typ 后单字。
        final m = RegExp(r'\btyp (\w+)').firstMatch(cand);
        final typ = m?.group(1) ?? '?';
        return 'icecandidate · typ=$typ · ${cand.length > 100 ? "${cand.substring(0, 100)}…" : cand}';
      case 'connectionstatechange':
        return 'connection → ${p['state']}';
      case 'iceconnectionstatechange':
        return 'ice → ${p['state']}';
    }
    return '${entry.kind} · ${jsonEncode(p)}';
  }

  /// SDP Diff tab：左右双列展示当前 PC 的 local SDP / remote SDP。每列
  /// 头部还显示 type（offer/answer），下方按"上一份 vs 当前"做行级 diff
  /// （绿 = 新增，红 = 删除，灰 = 不变）。第一次接到 SDP 时只渲染单列。
  Widget _buildSdpDiffTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final ids = _sdps.keys.toList()..sort();
    if (ids.isEmpty) {
      return Padding(
        key: const ValueKey('empty-sdp'),
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Text(
            isZh
                ? '暂无 SDP。\n触发 setLocalDescription / setRemoteDescription 后会出现。'
                : 'No SDP yet.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final selectedId =
        _sdps.containsKey(_selected) ? _selected : ids.first;
    final pair = _sdps[selectedId]!;
    return Padding(
      key: const ValueKey('sdp'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                ChoiceChip(
                  label: Text('PC #$id'),
                  selected: id == selectedId,
                  onSelected: (_) => setState(() => _selected = id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SdpDiffColumn(
                    title: isZh ? '本地 SDP' : 'Local SDP',
                    current: pair.local,
                    previous: pair.prevLocal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SdpDiffColumn(
                    title: isZh ? '远端 SDP' : 'Remote SDP',
                    current: pair.remote,
                    previous: pair.prevRemote,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    if (_events.isEmpty) {
      return Padding(
        key: const ValueKey('empty-events'),
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Text(
            isZh ? '暂无事件' : 'No events',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return Padding(
      key: const ValueKey('events'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: ListView.builder(
        reverse: true,
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[_events.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: SelectableText(
              '[${e['kind']}] ${jsonEncode(e)}',
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          );
        },
      ),
    );
  }

  static String _formatBytes(double v) {
    if (v < 1024) return '${v.toStringAsFixed(0)} B';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
    if (v < 1024 * 1024 * 1024) {
      return '${(v / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(v / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _RtcSeries {
  static const int _capacity = 60;
  final List<_RtcSample> samples = <_RtcSample>[];

  _RtcSample? get last => samples.isEmpty ? null : samples.last;

  void push({
    required double bytesSent,
    required double bytesReceived,
    required double packetsLost,
    required double rttMs,
  }) {
    samples.add(_RtcSample(
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
      packetsLost: packetsLost,
      rttMs: rttMs,
    ));
    if (samples.length > _capacity) {
      samples.removeRange(0, samples.length - _capacity);
    }
  }
}

class _RtcSample {
  const _RtcSample({
    required this.bytesSent,
    required this.bytesReceived,
    required this.packetsLost,
    required this.rttMs,
  });

  final double bytesSent;
  final double bytesReceived;
  final double packetsLost;
  final double rttMs;
}

class _RtcTab extends StatelessWidget {
  const _RtcTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontSize: 13,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _RtcStatChip extends StatelessWidget {
  const _RtcStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _RtcChartPainter extends CustomPainter {
  _RtcChartPainter({
    required this.series,
    required this.primary,
    required this.tertiary,
    required this.error,
    required this.secondary,
    required this.grid,
    required this.onSurface,
  });

  final _RtcSeries series;
  final Color primary;
  final Color tertiary;
  final Color error;
  final Color secondary;
  final Color grid;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.samples.isEmpty) return;
    // 留 28px 左侧给 y 轴标签，14px 底部给 x 轴。
    const left = 28.0, bottom = 18.0;
    final w = size.width - left, h = size.height - bottom;
    const origin = Offset(left, 0);
    // 网格。
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = h * i / 4;
      canvas.drawLine(
          Offset(origin.dx, y), Offset(origin.dx + w, y), gp);
    }
    // 计算两组 axis：bytes 和 rtt/packets。
    var maxBytes = 1.0;
    var maxRtt = 1.0;
    var maxLost = 1.0;
    for (final s in series.samples) {
      if (s.bytesSent > maxBytes) maxBytes = s.bytesSent;
      if (s.bytesReceived > maxBytes) maxBytes = s.bytesReceived;
      if (s.rttMs > maxRtt) maxRtt = s.rttMs;
      if (s.packetsLost > maxLost) maxLost = s.packetsLost;
    }
    final n = series.samples.length;
    Offset xy(int i, double v, double maxV) {
      final x = origin.dx + (n == 1 ? w / 2 : w * i / (n - 1));
      final y = h - (v / maxV) * h;
      return Offset(x, y);
    }

    void drawLine(List<Offset> pts, Color c, {double sw = 1.6}) {
      if (pts.isEmpty) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, p);
    }

    drawLine([
      for (var i = 0; i < n; i++)
        xy(i, series.samples[i].bytesSent, maxBytes),
    ], primary);
    drawLine([
      for (var i = 0; i < n; i++)
        xy(i, series.samples[i].bytesReceived, maxBytes),
    ], tertiary);
    drawLine([
      for (var i = 0; i < n; i++) xy(i, series.samples[i].rttMs, maxRtt),
    ], secondary);
    drawLine([
      for (var i = 0; i < n; i++)
        xy(i, series.samples[i].packetsLost, maxLost),
    ], error, sw: 1.2);

    // 左侧 y 轴最大值标签。
    final tp = TextPainter(
      text: TextSpan(
        text: '${(maxBytes / 1024).toStringAsFixed(1)} KB',
        style: TextStyle(color: onSurface, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(2, 0));
  }

  @override
  bool shouldRepaint(covariant _RtcChartPainter old) =>
      old.series != series;
}

Future<void> _showWebcrackDialog(
  BuildContext context,
  bool isZh,
) async {
  final input = TextEditingController();
  final output = ValueNotifier<String?>(null);
  final running = ValueNotifier<bool>(false);
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? 'JS 反混淆（webcrack）' : 'JS deobfuscate (webcrack)'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          children: [
            Text(
              isZh
                  ? '把混淆后的 JS 粘到这里 → 点"反混淆"将自动写到 /tmp 并跑 npx webcrack。需要本机已装 Node.js 与 npm。'
                  : 'Paste obfuscated JS, then click Deobfuscate. Requires Node.js + npm; uses npx webcrack.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: input,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'paste obfuscated js…',
                ),
                style:
                    const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<String?>(
                valueListenable: output,
                builder: (_, v, _) => Container(
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .outlineVariant,
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      v ??
                          (isZh
                              ? '反混淆结果会显示在这里。'
                              : 'Deobfuscated result appears here.'),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
        ValueListenableBuilder<bool>(
          valueListenable: running,
          builder: (_, busy, _) => OpenHandDialogActionButton.primary(
            onPressed: busy
                ? null
                : () async {
                    if (input.text.trim().isEmpty) return;
                    running.value = true;
                    final r = await _runWebcrack(input.text);
                    running.value = false;
                    output.value = r;
                  },
            label: busy
                ? (isZh ? '处理中…' : 'Working…')
                : (isZh ? '反混淆' : 'Deobfuscate'),
          ),
        ),
      ],
    ),
  );
}

Future<String> _runWebcrack(String src) async {
  // 写入 temp 文件 + 跑 `npx -y webcrack@latest -o <outDir> <inFile>`，
  // 完成后读 outDir/deobfuscated.js（或 webcrack 默认输出）回显。
  final tmpDir = await Directory.systemTemp.createTemp('oh-webcrack-');
  final input = File('${tmpDir.path}/input.js');
  await input.writeAsString(src);
  try {
    // npx 第一次需要联网拉包；--yes 跳过提示。
    final result = await Process.run(
      'npx',
      <String>[
        '--yes',
        'webcrack@latest',
        input.path,
        '-o',
        tmpDir.path,
      ],
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      return '[webcrack 失败 exit=${result.exitCode}]\n${result.stderr}';
    }
    // webcrack 默认输出 deobfuscated.js + 其他文件；优先取它。
    final out = File('${tmpDir.path}/deobfuscated.js');
    if (await out.exists()) {
      return await out.readAsString();
    }
    // 兜底：把整个 outDir 下所有 .js 拼起来。
    final buf = StringBuffer();
    for (final entity in tmpDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.js')) {
        buf
          ..writeln('// ─── ${entity.path} ───')
          ..writeln(await entity.readAsString())
          ..writeln();
      }
    }
    final s = buf.toString();
    return s.isEmpty ? '[webcrack 无输出]' : s;
  } catch (error, stack) {
    silentLog('web_reverse_dashboard_dialog', 'webcrack', error, stack);
    return '[执行异常]\n$error';
  } finally {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  }
}


Future<void> _showInterceptRulesDialog(
  BuildContext context,
  WebReverseSessionController controller,
  bool isZh,
) async {
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => _InterceptRulesDialog(controller: controller, isZh: isZh),
  );
}

class _InterceptRulesDialog extends StatefulWidget {
  const _InterceptRulesDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;

  @override
  State<_InterceptRulesDialog> createState() => _InterceptRulesDialogState();
}

class _InterceptRulesDialogState extends State<_InterceptRulesDialog> {
  late List<WebReverseInterceptRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = [...widget.controller.interceptRules];
  }

  void _save() {
    widget.controller.setInterceptRules(_rules);
    context
        .findAncestorStateOfType<_WebReverseDashboardDialogState>()
        ?.persistInterceptRules();
    Navigator.of(context).pop();
  }

  Future<void> _editRule(int? index) async {
    final initial = index == null
        ? const WebReverseInterceptRule(urlPattern: '')
        : _rules[index];
    final updated = await showAnimatedDialog<WebReverseInterceptRule>(
      context: context,
      builder: (_) => _InterceptRuleEditor(
        initial: initial,
        isZh: widget.isZh,
      ),
    );
    if (updated == null) return;
    setState(() {
      if (index == null) {
        _rules.add(updated);
      } else {
        _rules[index] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isZh ? '网络拦截规则' : 'Network intercept rules',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _editRule(null),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(isZh ? '新增规则' : 'Add rule'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _rules.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isZh
                            ? '无规则。点「新增规则」开始：URL 通配 → block / 改写。\n命中规则的请求会自动放行/改写，不再走拦截队列。'
                            : 'No rules. Click Add rule to start: URL pattern → block / rewrite.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _rules.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final r = _rules[i];
                        return ListTile(
                          dense: true,
                          leading: Switch(
                            value: r.enabled,
                            onChanged: (v) {
                              setState(() {
                                _rules[i] = r.copyWith(enabled: v);
                              });
                            },
                          ),
                          title: Text(
                            r.urlPattern,
                            style: const TextStyle(fontFamily: 'monospace'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            r.block
                                ? (isZh ? '动作: 屏蔽' : 'Action: block')
                                : r.replaceUrl != null &&
                                        r.replaceUrl!.isNotEmpty
                                    ? (isZh
                                        ? '动作: 重定向到 ${r.replaceUrl}'
                                        : 'Action: redirect → ${r.replaceUrl}')
                                    : r.headerOverrides.isEmpty
                                        ? (isZh ? '动作: 仅标记' : 'Action: tag only')
                                        : (isZh
                                            ? '动作: 注入 ${r.headerOverrides.length} 个 header'
                                            : 'Action: inject ${r.headerOverrides.length} headers'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: isZh ? '编辑' : 'Edit',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                                icon: const Icon(Icons.edit_rounded),
                                onPressed: () => _editRule(i),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: isZh ? '删除' : 'Delete',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                  minWidth: 30,
                                  minHeight: 30,
                                ),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                ),
                                onPressed: () {
                                  setState(() => _rules.removeAt(i));
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(isZh ? '取消' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text(isZh ? '保存' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterceptRuleEditor extends StatefulWidget {
  const _InterceptRuleEditor({required this.initial, required this.isZh});
  final WebReverseInterceptRule initial;
  final bool isZh;

  @override
  State<_InterceptRuleEditor> createState() => _InterceptRuleEditorState();
}

class _InterceptRuleEditorState extends State<_InterceptRuleEditor> {
  late TextEditingController _patternCtrl;
  late TextEditingController _replaceCtrl;
  late TextEditingController _headersCtrl;
  late bool _enabled;
  late bool _block;

  @override
  void initState() {
    super.initState();
    _patternCtrl = TextEditingController(text: widget.initial.urlPattern);
    _replaceCtrl = TextEditingController(text: widget.initial.replaceUrl ?? '');
    _headersCtrl = TextEditingController(
      text: widget.initial.headerOverrides.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n'),
    );
    _enabled = widget.initial.enabled;
    _block = widget.initial.block;
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _replaceCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = widget.isZh;
    return AlertDialog(
      title: Text(isZh ? '编辑规则' : 'Edit rule'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _patternCtrl,
                decoration: InputDecoration(
                  labelText: isZh ? 'URL 通配（* / ?）' : 'URL pattern (* / ?)',
                  hintText: '*://api.example.com/v1/*',
                ),
              ),
              SwitchListTile(
                title: Text(isZh ? '启用' : 'Enabled'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              SwitchListTile(
                title: Text(isZh ? '屏蔽请求 (Block)' : 'Block request'),
                value: _block,
                onChanged: (v) => setState(() => _block = v),
              ),
              TextField(
                controller: _replaceCtrl,
                decoration: InputDecoration(
                  labelText:
                      isZh ? '重写 URL（可选）' : 'Replace URL (optional)',
                  hintText: 'https://mock.local/v1/',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _headersCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: isZh
                      ? 'Header 覆盖（每行 Key: Value）'
                      : 'Header overrides (Key: Value per line)',
                  hintText: 'X-Debug: 1\nAuthorization: Bearer xxx',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final headers = <String, String>{};
            for (final line in _headersCtrl.text.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final idx = trimmed.indexOf(':');
              if (idx <= 0) continue;
              headers[trimmed.substring(0, idx).trim()] =
                  trimmed.substring(idx + 1).trim();
            }
            Navigator.of(context).pop(
              WebReverseInterceptRule(
                urlPattern: _patternCtrl.text.trim(),
                enabled: _enabled,
                block: _block,
                replaceUrl: _replaceCtrl.text.trim().isEmpty
                    ? null
                    : _replaceCtrl.text.trim(),
                headerOverrides: headers,
              ),
            );
          },
          child: Text(isZh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}


/// 单条 ICE 控制平面事件。kind = pc.create / track / datachannel /
/// icecandidate / (ice)connectionstatechange，payload 是原始 JSON 行。
class _IceEntry {
  const _IceEntry({required this.kind, required this.payload});
  final String kind;
  final Map<String, Object?> payload;
}

/// 一个 PeerConnection 的 local + remote SDP 当前 / 上一版本。Diff tab
/// 拿来做行级对比。
class _SdpPair {
  _SdpVersion? local;
  _SdpVersion? prevLocal;
  _SdpVersion? remote;
  _SdpVersion? prevRemote;
}

class _SdpVersion {
  const _SdpVersion({required this.type, required this.sdp});
  final String type;
  final String sdp;
}

/// SDP Diff 单列：上方标题 + 类型徽标，下方按行 diff 展示。
/// previous 为 null 时按全行"=="渲染，避免初次握手就一片绿洪水。
class _SdpDiffColumn extends StatelessWidget {
  const _SdpDiffColumn({
    required this.title,
    required this.current,
    required this.previous,
  });

  final String title;
  final _SdpVersion? current;
  final _SdpVersion? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (current == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          title,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    final cur = current!;
    final prev = previous;
    final curLines = cur.sdp.split('\n');
    final prevLines = prev?.sdp.split('\n') ?? const <String>[];
    // 简化 diff：行级集合差。复杂度 O(n+m)，对 SDP 这种 ~50 行内容够用。
    final prevSet = prevLines.toSet();
    final curSet = curLines.toSet();
    final rows = <_SdpDiffRow>[];
    for (final ln in curLines) {
      rows.add(_SdpDiffRow(
        line: ln,
        kind: prevSet.contains(ln) ? _DiffKind.same : _DiffKind.added,
      ));
    }
    if (prev != null) {
      for (final ln in prevLines) {
        if (!curSet.contains(ln)) {
          rows.add(_SdpDiffRow(line: ln, kind: _DiffKind.removed));
        }
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  cur.type,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final color = switch (r.kind) {
                  _DiffKind.added =>
                    Colors.green.withValues(alpha: 0.18),
                  _DiffKind.removed => cs.error.withValues(alpha: 0.18),
                  _DiffKind.same => Colors.transparent,
                };
                final prefix = switch (r.kind) {
                  _DiffKind.added => '+ ',
                  _DiffKind.removed => '- ',
                  _DiffKind.same => '  ',
                };
                return Container(
                  color: color,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  child: SelectableText(
                    '$prefix${r.line}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiffKind { added, removed, same }

class _SdpDiffRow {
  const _SdpDiffRow({required this.line, required this.kind});
  final String line;
  final _DiffKind kind;
}


/// ICE 拓扑有向图：把当前 PC 收到的 candidate / track / datachannel 节
/// 点围着 PC 中心节点摆成放射状，根据来源画箭头。candidate 按 typ
/// 分组（host / srflx / relay / 其它）；track 按 media kind（audio /
/// video）；datachannel 单独一组。
/// 性能上限：candidate 取最近 12 条；track / datachannel 全量但通常不
/// 多，可放心整体绘制。InteractiveViewer 包外面，鼠标可缩放拖动查看。
class _IceTopologyGraph extends StatelessWidget {
  const _IceTopologyGraph({
    required this.pcId,
    required this.entries,
    required this.primary,
    required this.tertiary,
    required this.secondary,
    required this.error,
    required this.onSurface,
    required this.surfaceContainer,
    required this.isZh,
  });

  final int pcId;
  final List<_IceEntry> entries;
  final Color primary;
  final Color tertiary;
  final Color secondary;
  final Color error;
  final Color onSurface;
  final Color surfaceContainer;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final nodes = _layoutNodes();
    return Container(
      decoration: BoxDecoration(
        color: surfaceContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InteractiveViewer(
          maxScale: 4,
          minScale: 0.5,
          child: SizedBox(
            width: 720,
            height: 420,
            child: CustomPaint(
              painter: _IceTopologyPainter(
                pcId: pcId,
                nodes: nodes,
                primary: primary,
                tertiary: tertiary,
                secondary: secondary,
                error: error,
                onSurface: onSurface,
                surfaceContainer: surfaceContainer,
                isZh: isZh,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把 entries 折叠成 _IceGraphNode 列表，附上分组信息让 painter 决定
  /// 角度 / 半径。candidate 取最近 12 条避免拥挤；同类型按时序排列。
  List<_IceGraphNode> _layoutNodes() {
    final out = <_IceGraphNode>[];
    final candidates = <_IceGraphNode>[];
    final tracks = <_IceGraphNode>[];
    final datachannels = <_IceGraphNode>[];
    String? lastConnState;
    for (final e in entries) {
      final p = e.payload;
      switch (e.kind) {
        case 'icecandidate':
          final cand = '${p['candidate'] ?? ''}';
          final m = RegExp(r'\btyp (\w+)').firstMatch(cand);
          final typ = m?.group(1) ?? '?';
          final m2 = RegExp(r'\b(udp|tcp)\s+\d+\s+(\S+)\s+(\d+)',
              caseSensitive: false).firstMatch(cand);
          final ip = m2?.group(2) ?? '?';
          final port = m2?.group(3) ?? '';
          candidates.add(_IceGraphNode(
            kind: _IceNodeKind.candidate,
            label: '$typ\n$ip:$port',
            typ: typ,
          ));
          break;
        case 'track':
          tracks.add(_IceGraphNode(
            kind: _IceNodeKind.track,
            label: 'track\n${p['kind'] ?? '?'}',
            typ: '${p['kind'] ?? ''}',
          ));
          break;
        case 'datachannel':
          datachannels.add(_IceGraphNode(
            kind: _IceNodeKind.datachannel,
            label: 'dc\n${p['label'] ?? ''}',
            typ: '',
          ));
          break;
        case 'connectionstatechange':
        case 'iceconnectionstatechange':
          lastConnState = '${p['state'] ?? ''}';
          break;
      }
    }
    // 取最近 12 条 candidate 防图爆炸。
    final tail = candidates.length > 12
        ? candidates.sublist(candidates.length - 12)
        : candidates;
    out.addAll(tail);
    out.addAll(tracks);
    out.addAll(datachannels);
    return [
      _IceGraphNode(
        kind: _IceNodeKind.pc,
        label: 'PC #$pcId\n${lastConnState ?? "?"}',
        typ: lastConnState ?? '',
      ),
      ...out,
    ];
  }
}

enum _IceNodeKind { pc, candidate, track, datachannel }

class _IceGraphNode {
  const _IceGraphNode({
    required this.kind,
    required this.label,
    required this.typ,
  });
  final _IceNodeKind kind;
  final String label;
  final String typ;
}

class _IceTopologyPainter extends CustomPainter {
  _IceTopologyPainter({
    required this.pcId,
    required this.nodes,
    required this.primary,
    required this.tertiary,
    required this.secondary,
    required this.error,
    required this.onSurface,
    required this.surfaceContainer,
    required this.isZh,
  });

  final int pcId;
  final List<_IceGraphNode> nodes;
  final Color primary;
  final Color tertiary;
  final Color secondary;
  final Color error;
  final Color onSurface;
  final Color surfaceContainer;
  final bool isZh;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final pc = nodes.first;
    final others = nodes.skip(1).toList();
    final center = Offset(size.width / 2, size.height / 2);
    // 分组排布：candidate / track / datachannel 各自一段角度区间。
    final candidates =
        others.where((n) => n.kind == _IceNodeKind.candidate).toList();
    final tracks =
        others.where((n) => n.kind == _IceNodeKind.track).toList();
    final datachannels =
        others.where((n) => n.kind == _IceNodeKind.datachannel).toList();
    final positions = <_IceGraphNode, Offset>{};
    final radius = math.min(size.width, size.height) * 0.4;
    void place(List<_IceGraphNode> g, double startAngle, double endAngle) {
      if (g.isEmpty) return;
      if (g.length == 1) {
        final ang = (startAngle + endAngle) / 2;
        positions[g.first] = center +
            Offset(math.cos(ang) * radius, math.sin(ang) * radius);
        return;
      }
      final span = endAngle - startAngle;
      for (var i = 0; i < g.length; i++) {
        final ang = startAngle + span * i / (g.length - 1);
        positions[g[i]] = center +
            Offset(math.cos(ang) * radius, math.sin(ang) * radius);
      }
    }

    place(candidates, math.pi * 0.6, math.pi * 1.4);
    place(tracks, -math.pi * 0.45, math.pi * 0.45);
    place(datachannels, math.pi * 0.45, math.pi * 0.55);

    // 1) 先画连线：candidate → PC（蓝），PC → track / datachannel（橙 / 紫）。
    for (final entry in positions.entries) {
      final node = entry.key;
      final pos = entry.value;
      final color = switch (node.kind) {
        _IceNodeKind.candidate => primary.withValues(alpha: 0.7),
        _IceNodeKind.track => tertiary.withValues(alpha: 0.85),
        _IceNodeKind.datachannel => secondary.withValues(alpha: 0.85),
        _ => onSurface,
      };
      final from = node.kind == _IceNodeKind.candidate ? pos : center;
      final to = node.kind == _IceNodeKind.candidate ? center : pos;
      _drawArrow(canvas, from, to, color);
    }
    // 2) 画 PC 中心节点（圆形）。
    _drawPcNode(canvas, center, pc);
    // 3) 画外围节点。
    for (final entry in positions.entries) {
      final node = entry.key;
      final pos = entry.value;
      _drawNode(canvas, pos, node);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dir = to - from;
    final dist = dir.distance;
    if (dist <= 1) return;
    // 箭头从节点边缘起，避免被节点 box 盖住。两端各留 26px。
    final unit = dir / dist;
    final start = from + unit * 26;
    final end = to - unit * 26;
    canvas.drawLine(start, end, paint);
    // 箭头三角。
    final ang = math.atan2(unit.dy, unit.dx);
    const arrowLen = 8.0;
    const arrowAng = 0.5;
    final p1 = end -
        Offset(math.cos(ang - arrowAng), math.sin(ang - arrowAng)) * arrowLen;
    final p2 = end -
        Offset(math.cos(ang + arrowAng), math.sin(ang + arrowAng)) * arrowLen;
    final tri = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(tri, Paint()..color = color);
  }

  void _drawPcNode(Canvas canvas, Offset center, _IceGraphNode node) {
    const r = 38.0;
    canvas.drawCircle(
      center,
      r,
      Paint()..color = primary.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = primary
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: node.label,
        style: TextStyle(
          color: onSurface,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          fontFamily: 'monospace',
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 2 - 6);
    tp.paint(canvas, center + Offset(-tp.width / 2, -tp.height / 2));
  }

  void _drawNode(Canvas canvas, Offset pos, _IceGraphNode node) {
    final color = switch (node.kind) {
      _IceNodeKind.candidate => switch (node.typ) {
          'host' => primary,
          'srflx' => tertiary,
          'relay' => error,
          _ => secondary,
        },
      _IceNodeKind.track => tertiary,
      _IceNodeKind.datachannel => secondary,
      _ => onSurface,
    };
    final box = Rect.fromCenter(center: pos, width: 110, height: 36);
    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(8));
    canvas.drawRRect(
      rrect,
      Paint()..color = color.withValues(alpha: 0.22),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: node.label,
        style: TextStyle(
          color: onSurface,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    tp.paint(canvas, pos + Offset(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _IceTopologyPainter old) =>
      old.nodes != nodes || old.pcId != pcId;
}

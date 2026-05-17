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
  final ok = await showDialog<bool>(
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
  await showDialog<void>(
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
  await showDialog<void>(
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
  await showDialog<void>(
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
    SnackBar(
      content: Text(
        isZh
            ? 'HAR 重放服务器已启动：http://127.0.0.1:${r.port}/  · 已加载 ${r.entryCount} 条'
            : 'Replay server up at http://127.0.0.1:${r.port}/  · ${r.entryCount} entries',
      ),
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
    await showDialog<void>(
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
  final go = await showDialog<bool>(
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
  await showDialog<void>(
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
  // 0 = 图表，1 = 事件流。
  int _tab = 0;

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
          _events.add(e);
          if (_events.length > _maxEvents) {
            _events.removeRange(0, _events.length - _maxEvents);
          }
        }
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
                  const SizedBox(width: 10),
                  _RtcTab(
                    label: isZh ? '事件流' : 'Events',
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                  const Spacer(),
                  if (_tab == 1 && _events.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(_events),
                        ));
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(
                          content: Text(isZh ? '已复制' : 'Copied'),
                          duration: const Duration(seconds: 1),
                        ));
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
                child: _tab == 0 ? _buildChartsTab(theme) : _buildEventsTab(theme),
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
  await showDialog<void>(
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
  await showDialog<void>(
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
    final updated = await showDialog<WebReverseInterceptRule>(
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

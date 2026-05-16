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
          messenger.showSnackBar(SnackBar(
            content: Text(
              path == null
                  ? (isZh ? '导出失败' : 'Export failed')
                  : (isZh ? '已导出到 $path' : 'Exported to $path'),
            ),
            duration: const Duration(seconds: 3),
          ));
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
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(isZh ? '保存' : 'Save'),
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
  messenger.showSnackBar(SnackBar(
    content: Text(
      saved
          ? (isZh ? '已注入 ${headers.length} 个 Header' : 'Injected ${headers.length} headers')
          : (isZh ? '保存失败' : 'Save failed'),
    ),
    duration: const Duration(seconds: 2),
  ));
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
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(isZh ? '关闭' : 'Close'),
        ),
        FilledButton(
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
          child: Text(isZh ? '执行' : 'Run'),
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
    messenger.showSnackBar(SnackBar(
      content: Text(isZh ? '当前无请求可分析' : 'No requests yet'),
      duration: const Duration(seconds: 2),
    ));
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
  messenger.showSnackBar(SnackBar(
    content: Text(
      isZh ? '请求摘要已复制，回到会话粘贴即可让 AI 分析' : 'Summary copied; paste in chat',
    ),
    duration: const Duration(seconds: 3),
  ));
}

Future<void> _showDiffPicker(
  BuildContext context,
  WebReverseSessionController ctrl,
  bool isZh,
) async {
  final all = ctrl.networkRequests;
  if (all.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isZh ? '请求数不足，无法对比' : 'Need at least 2 requests'),
      duration: const Duration(seconds: 2),
    ));
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
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
            child: Text(isZh ? '对比' : 'Diff'),
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
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(isZh ? '关闭' : 'Close'),
        ),
        if (list.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // 用 Runtime.evaluate 调 navigator.serviceWorker.getRegistrations 一键 unregister。
              final r = await ctrl.runReplExpression(
                'navigator.serviceWorker.getRegistrations().then(rs => Promise.all(rs.map(r => r.unregister()))).then(rs => rs.length)',
              );
              if (!context.mounted) return;
              messenger.showSnackBar(SnackBar(
                content: Text(
                  r == null
                      ? (isZh ? '反注册失败' : 'Unregister failed')
                      : (isZh ? '已反注册 $r 个 SW' : 'Unregistered $r SWs'),
                ),
                duration: const Duration(seconds: 2),
              ));
            },
            child: Text(isZh ? '全部反注册' : 'Unregister all'),
          ),
      ],
    ),
  );
}

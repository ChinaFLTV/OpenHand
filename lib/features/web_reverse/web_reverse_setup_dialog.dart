import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import 'web_reverse_browser_detector.dart';
import 'web_reverse_install_guide_dialog.dart';
import 'web_reverse_profile_cleaner.dart';
import 'web_reverse_session_config.dart';

/// 弹出 Web 逆向会话创建表单。返回 null 表示用户取消；返回 result 后
/// 上层负责真正去启动 controller、创建会话。
///
/// 在弹表单之前会先做一次浏览器探测：未装的话自动弹引导，引导后允许
/// 重新检测；最终通过的浏览器写入 result.executablePath / browserKind。
Future<WebReverseSetupResult?> showWebReverseSetupDialog(
  BuildContext context, {
  String? initialTargetUrl,
  required String userDataDirRoot,
}) async {
  final detector = WebReverseBrowserDetector();

  Future<List<WebReverseBrowserProbeResult>?> ensureBrowserInstalled() async {
    while (true) {
      final all = await detector.detectAll();
      if (all.isNotEmpty) return all;
      if (!context.mounted) return null;
      final decision = await showWebReverseInstallGuideDialog(context);
      if (decision == null ||
          decision == WebReverseInstallGuideDecision.cancelled) {
        return null;
      }
      // openedDownloadPage / rechecked 都重新探测一次。
    }
  }

  final probes = await ensureBrowserInstalled();
  if (probes == null || probes.isEmpty || !context.mounted) return null;

  return showAnimatedDialog<WebReverseSetupResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WebReverseSetupDialog(
      probes: probes,
      initialTargetUrl: initialTargetUrl,
      userDataDirRoot: userDataDirRoot,
    ),
  );
}

class WebReverseSetupResult {
  const WebReverseSetupResult({
    required this.config,
    required this.executablePath,
  });

  final WebReverseSessionConfig config;
  final String executablePath;
}

class _WebReverseSetupDialog extends StatefulWidget {
  const _WebReverseSetupDialog({
    required this.probes,
    required this.initialTargetUrl,
    required this.userDataDirRoot,
  });

  final List<WebReverseBrowserProbeResult> probes;
  final String? initialTargetUrl;
  final String userDataDirRoot;

  @override
  State<_WebReverseSetupDialog> createState() => _WebReverseSetupDialogState();
}

class _WebReverseSetupDialogState extends State<_WebReverseSetupDialog> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _objectiveCtrl;
  late final TextEditingController _triggerCtrl;
  late final TextEditingController _proxyCtrl;
  late final TextEditingController _keywordsCtrl;
  WebReverseLoginMode _loginMode = WebReverseLoginMode.none;
  late WebReverseBrowserProbeResult _selectedProbe;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialTargetUrl ?? '');
    _objectiveCtrl = TextEditingController();
    _triggerCtrl = TextEditingController();
    _proxyCtrl = TextEditingController();
    _keywordsCtrl = TextEditingController();
    _selectedProbe = widget.probes.first;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _objectiveCtrl.dispose();
    _triggerCtrl.dispose();
    _proxyCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  bool _isZh() =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  /// 预览的 user-data-dir：与 [_submit] 中拼装一致，仅用于 UI 展示与
  /// "清理冲突 profile"按钮。注意真实启动时 home page 还会再追加 sessionId
  /// 后缀（防多会话锁占用），所以这里仅清理浏览器粒度的"模板锁"。
  String get _previewUserDataDir {
    final id = _selectedProbe.browser?.id ?? 'chrome';
    return '${widget.userDataDirRoot}/profile_$id';
  }

  bool get _canSubmit {
    final url = _urlCtrl.text.trim();
    final obj = _objectiveCtrl.text.trim();
    if (url.isEmpty || obj.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    return true;
  }

  void _submit() {
    final keywords = _keywordsCtrl.text
        .split(RegExp(r'[,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final config = WebReverseSessionConfig(
      targetUrl: _urlCtrl.text.trim(),
      objective: _objectiveCtrl.text.trim(),
      cdpPort: 9222,
      userDataDir:
          '${widget.userDataDirRoot}/profile_${_selectedProbe.browser!.id}',
      browserKind: _selectedProbe.browser!,
      triggerActions: _triggerCtrl.text.trim().isEmpty
          ? null
          : _triggerCtrl.text.trim(),
      loginMode: _loginMode,
      proxy: _proxyCtrl.text.trim().isEmpty ? null : _proxyCtrl.text.trim(),
      keywords: keywords,
    );
    Navigator.of(context).pop(
      WebReverseSetupResult(
        config: config,
        executablePath: _selectedProbe.executablePath!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = _isZh();
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LabelText(isZh ? '目标 URL *' : 'Target URL *'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'https://example.com/page',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '逆向目标 *' : 'Objective *'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _objectiveCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isZh
                            ? '例如：复现壁纸下载接口，输出 curl 脚本'
                            : 'e.g. reverse the wallpaper download API into a curl script',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '触发动作（可选）' : 'Trigger actions (optional)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _triggerCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isZh
                            ? '例如：登录后点击"下载原图"按钮'
                            : 'e.g. log in then click "Download Original"',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '登录态' : 'Login mode'),
                    const SizedBox(height: 4),
                    SegmentedButton<WebReverseLoginMode>(
                      segments: WebReverseLoginMode.values
                          .map(
                            (m) => ButtonSegment(
                              value: m,
                              label: Text(_loginModeLabel(m, isZh)),
                            ),
                          )
                          .toList(growable: false),
                      selected: <WebReverseLoginMode>{_loginMode},
                      onSelectionChanged: (s) =>
                          setState(() => _loginMode = s.first),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '浏览器（已检测）' : 'Browser (detected)'),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<WebReverseBrowserProbeResult>(
                      initialValue: _selectedProbe,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: widget.probes
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.versionLine == null
                                    ? p.browser!.displayName
                                    : '${p.browser!.displayName}  ·  ${p.versionLine}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: widget.probes.length <= 1
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _selectedProbe = v);
                            },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedProbe.executablePath ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '代理（可选）' : 'Proxy (optional)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _proxyCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'http://127.0.0.1:7890',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabelText(isZh ? '关键关键字（可选，逗号分隔）' : 'Keywords (optional, comma-separated)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _keywordsCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isZh ? 'sign, encrypt, _0x' : 'sign, encrypt, _0x',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ProfileDirRow(
                      userDataDir: _previewUserDataDir,
                      isZh: isZh,
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: AppLocalizations.of(context)?.commonCancel ??
                        (isZh ? '取消' : 'Cancel'),
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: _canSubmit ? _submit : null,
                    label: isZh ? '创建线程' : 'Create Thread',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.travel_explore_rounded,
              color: cs.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '新建 Web 逆向会话' : 'New Web Reverse Session',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isZh
                      ? '会话启动后会拉起浏览器并吸附在主窗口右侧'
                      : 'Browser will dock to the right of the main window after start',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isZh ? '关闭' : 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  String _loginModeLabel(WebReverseLoginMode m, bool isZh) {
    if (!isZh) {
      return switch (m) {
        WebReverseLoginMode.none => 'None',
        WebReverseLoginMode.manual => 'Manual',
        WebReverseLoginMode.storageState => 'Storage state',
      };
    }
    return m.label;
  }
}

class _LabelText extends StatelessWidget {
  const _LabelText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 设置弹窗里展示的"Profile 目录"行：左侧带说明 + 右侧"清理冲突 profile"按钮。
/// 点击按钮 → 探测目录是否存在 SingletonLock 等锁文件 → 询问确认 →
/// 调用 [cleanWebReverseProfileLocks] 删除 → 用 SnackBar 反馈 (deleted, messages)。
class _ProfileDirRow extends StatefulWidget {
  const _ProfileDirRow({required this.userDataDir, required this.isZh});

  final String userDataDir;
  final bool isZh;

  @override
  State<_ProfileDirRow> createState() => _ProfileDirRowState();
}

class _ProfileDirRowState extends State<_ProfileDirRow> {
  bool _busy = false;
  bool? _hasLock;

  @override
  void initState() {
    super.initState();
    _refreshLockState();
  }

  @override
  void didUpdateWidget(covariant _ProfileDirRow old) {
    super.didUpdateWidget(old);
    if (old.userDataDir != widget.userDataDir) {
      _refreshLockState();
    }
  }

  Future<void> _refreshLockState() async {
    final has = await hasWebReverseProfileLocks(widget.userDataDir);
    if (!mounted) return;
    setState(() => _hasLock = has);
  }

  Future<void> _onCleanPressed() async {
    final isZh = widget.isZh;
    final messenger = ScaffoldMessenger.of(context);
    // 先确认浏览器已关：清理时浏览器还在跑会造成更隐蔽的损坏。
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isZh ? '清理冲突 profile' : 'Clean conflicting profile'),
        content: Text(
          isZh
              ? '此操作会删除 profile 目录里的 SingletonLock / lockfile 等残留锁文件，'
                  '不会动 Cookies / Login Data 等真实数据。\n\n'
                  '请先关闭所有 ${widget.userDataDir.split('/').last.replaceFirst('profile_', '')} 浏览器实例后再执行。'
              : 'This will remove SingletonLock / lockfile residues inside the profile dir.'
                  ' Cookies / Login Data are NOT affected.\n\n'
                  'Close all related browser instances first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isZh ? '确认清理' : 'Clean now'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final result = await cleanWebReverseProfileLocks(widget.userDataDir);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _hasLock = false; // 清理后即刻更新 UI；下次构建会再 refresh。
    });
    messenger.showSnackBar(SnackBar(
      content: Text(
        isZh
            ? '已清理 ${result.deleted} 个锁文件'
            : 'Removed ${result.deleted} lock file(s)',
      ),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: isZh ? '查看' : 'View',
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(isZh ? '清理详情' : 'Clean details'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.messages.join('\n'),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isZh ? '关闭' : 'Close'),
                ),
              ],
            ),
          );
        },
      ),
    ));
    await _refreshLockState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final hasLock = _hasLock == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: hasLock ? cs.errorContainer.withValues(alpha: 0.4) : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasLock ? cs.error : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasLock ? Icons.lock_clock_rounded : Icons.folder_rounded,
            size: 18,
            color: hasLock ? cs.error : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isZh ? 'Profile 目录' : 'User Data Dir',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.userDataDir,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasLock) ...[
                  const SizedBox(height: 4),
                  Text(
                    isZh
                        ? '检测到 SingletonLock / lockfile 残留，可能阻止浏览器再次启动。'
                        : 'Stale SingletonLock / lockfile detected — may block next launch.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _onCleanPressed,
            icon: Icon(
              _busy ? Icons.hourglass_top_rounded : Icons.cleaning_services_rounded,
              size: 16,
            ),
            label: Text(
              _busy
                  ? (isZh ? '清理中…' : 'Cleaning…')
                  : (isZh ? '清理冲突 profile' : 'Clean profile locks'),
            ),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

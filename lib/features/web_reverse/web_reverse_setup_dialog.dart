import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/timer_safety.dart';
import 'web_reverse_browser_detector.dart';
import 'web_reverse_install_guide_dialog.dart';
import 'web_reverse_profile_actions.dart';
import 'web_reverse_profile_cleaner.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_config.dart';

const int _kWebReverseBrowserDetectionMaxAttempts = 3;

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
    var attempts = 0;
    while (attempts < _kWebReverseBrowserDetectionMaxAttempts) {
      attempts += 1;
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
    if (context.mounted) {
      final isZh = openHandIsChineseLocale(context);
      await showOpenHandInfoDialog(
        context: context,
        title: isZh ? '未检测到浏览器' : 'Browser not detected',
        message: isZh
            ? '已连续重检 $_kWebReverseBrowserDetectionMaxAttempts 次。请确认 Chrome / Edge / Brave / Chromium 已安装并可启动后再重试。'
            : 'Checked $_kWebReverseBrowserDetectionMaxAttempts times. Make sure Chrome, Edge, Brave, or Chromium is installed and can launch, then retry.',
      );
    }
    return null;
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

  bool _isZh() => openHandIsChineseLocale(context);

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
    final loc = AppLocalizations.of(context);
    final isZh = _isZh();
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 620,
      insetPadding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.travel_explore_rounded,
            title: loc?.webReverseSetupHeaderTitle ?? 'New Web Reverse Session',
            subtitle:
                loc?.webReverseSetupHeaderSubtitle ??
                'Browser will dock to the right of the main window after start',
            closeTooltip: loc?.webReverseSetupClose ?? 'Close',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LabelText(loc?.webReverseSetupTargetUrl ?? 'Target URL *'),
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
                  _LabelText(loc?.webReverseSetupObjective ?? 'Objective *'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _objectiveCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          loc?.webReverseSetupObjectiveHint ??
                          'e.g. reverse the wallpaper download API into a curl script',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(
                    loc?.webReverseSetupTriggerActions ??
                        'Trigger actions (optional)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _triggerCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText:
                          loc?.webReverseSetupTriggerHint ??
                          'e.g. log in then click "Download Original"',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LabelText(loc?.webReverseSetupLoginMode ?? 'Login mode'),
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
                  _LabelText(
                    loc?.webReverseSetupBrowser ?? 'Browser (detected)',
                  ),
                  const SizedBox(height: 4),
                  WebReverseSelectFormField<WebReverseBrowserProbeResult>(
                    initialValue: _selectedProbe,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    options: widget.probes
                        .map(
                          (p) => WebReverseSelectOption(
                            value: p,
                            label: p.versionLine == null
                                ? p.browser!.displayName
                                : '${p.browser!.displayName}  ·  ${p.versionLine}',
                          ),
                        )
                        .toList(growable: false),
                    tooltip: loc?.webReverseSetupBrowser ?? 'Browser',
                    onChanged: widget.probes.length <= 1
                        ? null
                        : (v) => setState(() => _selectedProbe = v),
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
                  _LabelText(loc?.webReverseSetupProxy ?? 'Proxy (optional)'),
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
                  _LabelText(
                    loc?.webReverseSetupKeywords ??
                        'Keywords (optional, comma-separated)',
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _keywordsCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'sign, encrypt, _0x',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ProfileDirRow(userDataDir: _previewUserDataDir, isZh: isZh),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(),
                label: AppLocalizations.of(context)?.commonCancel ?? 'Cancel',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _canSubmit ? _submit : null,
                label: loc?.webReverseSetupCreateThread ?? 'Create Thread',
              ),
            ],
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
  // 重置后 60s 冷却：避免误连击两次造成"刚建好的空 profile 又被删"。
  Timer? _cooldownTimer;
  int _cooldownLeftSec = 0;
  bool get _onCooldown => _cooldownLeftSec > 0;

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

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeftSec = 60);
    _cooldownTimer = startSafePeriodicTimer(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldownLeftSec--);
      if (_cooldownLeftSec <= 0) {
        t.cancel();
      }
    });
  }

  Future<void> _refreshLockState() async {
    final has = await hasWebReverseProfileLocks(widget.userDataDir);
    if (!mounted) return;
    setState(() => _hasLock = has);
  }

  Future<void> _runProgressive() async {
    setState(() => _busy = true);
    final outcome = await runProgressiveProfileResolve(
      context,
      userDataDir: widget.userDataDir,
      isZh: widget.isZh,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == ProgressiveProfileOutcome.reset) {
      _startCooldown();
    }
    await _refreshLockState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final hasLock = _hasLock == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: hasLock
            ? cs.errorContainer.withValues(alpha: 0.4)
            : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasLock ? cs.error : cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      loc?.webReverseSetupProfileDir ?? 'User Data Dir',
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
                        loc?.webReverseSetupLockDetected ??
                            'Stale SingletonLock / lockfile detected — may block next launch.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 渐进式单按钮：先清理 → 仍有锁就引导用户重置；重置成功后 60s 冷却
          // 防止误连击两次。
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: (_busy || _onCooldown) ? null : _runProgressive,
              icon: Icon(
                _busy
                    ? Icons.hourglass_top_rounded
                    : (_onCooldown
                          ? Icons.timer_rounded
                          : Icons.auto_fix_high_rounded),
                size: 16,
              ),
              label: Text(
                _busy
                    ? (loc?.webReverseSetupWorking ?? 'Working…')
                    : _onCooldown
                    ? (loc?.webReverseSetupCooldown(_cooldownLeftSec) ??
                          'Cool-down ${_cooldownLeftSec}s')
                    : (loc?.webReverseSetupResolveLock ??
                          'Resolve profile lock'),
              ),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

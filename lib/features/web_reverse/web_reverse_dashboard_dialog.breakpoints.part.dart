// 「断点」独立面板：
//
// 三段式：
//   1) Source breakpoints —— controller.userBreakpoints 列出，每条带「跳到 Sources」+ 删除。
//   2) Pause on exceptions —— 三态 SegmentedButton: 关 / 仅未捕获 / 全部抛出。
//   3) XHR / fetch breakpoints —— 子串匹配的 URL 列表 + 新增输入框 + 删除按钮。
//
// 风格：圆角胶囊 + 220ms easeOutCubic 切换 + Q弹 AnimatedSize/Switcher，
// 遵守 MediaQuery.disableAnimationsOf。

part of 'web_reverse_dashboard_dialog.dart';

class _BreakpointsBody extends StatefulWidget {
  const _BreakpointsBody({
    required this.controller,
    required this.isZh,
    required this.onPersist,
    required this.onJumpToSource,
  });
  final WebReverseSessionController controller;
  final bool isZh;
  final VoidCallback onPersist;
  final void Function(String url, int line) onJumpToSource;

  @override
  State<_BreakpointsBody> createState() => _BreakpointsBodyState();
}

class _BreakpointsBodyState extends State<_BreakpointsBody> {
  final TextEditingController _xhrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _xhrCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _removeSourceBp(({String url, int line}) b) async {
    final ok = await widget.controller
        .removeBreakpointAt(url: b.url, line: b.line);
    if (!mounted) return;
    if (ok) {
      widget.onPersist();
    } else {
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '取消断点失败' : 'Failed to remove breakpoint',
      );
    }
  }

  Future<void> _addXhr() async {
    final v = _xhrCtrl.text.trim();
    final ok = await widget.controller.addXhrBreakpoint(v);
    if (!mounted) return;
    if (ok) {
      _xhrCtrl.clear();
    } else {
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '添加 XHR 断点失败' : 'Failed to add XHR breakpoint',
      );
    }
  }

  Future<void> _removeXhr(String s) async {
    await widget.controller.removeXhrBreakpoint(s);
  }

  Future<void> _setPause(String state) async {
    final ok = await widget.controller.setPauseOnExceptions(state);
    if (!mounted) return;
    if (!ok) {
      OpenHandSnackBar.showError(
        context,
        widget.isZh ? '设置失败（页面未在调试态）' : 'Set failed (page not attached)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sourceBps = widget.controller.userBreakpoints.toList()
      ..sort((a, b) {
        final c = a.url.compareTo(b.url);
        return c != 0 ? c : a.line.compareTo(b.line);
      });
    final xhrBps = widget.controller.xhrBreakpoints.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListView(
        children: [
          _SectionCard(
            icon: Icons.location_on_rounded,
            title: isZh ? '代码断点' : 'Source breakpoints',
            child: AnimatedSize(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: _kSwitchInCurve,
              child: sourceBps.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          isZh
                              ? '到 Sources 面板点击行号下断点。'
                              : 'Toggle breakpoints by clicking line numbers in Sources.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final b in sourceBps)
                          _BpRow(
                            icon: Icons.circle,
                            iconColor: cs.primary,
                            title: _shortUrl(b.url),
                            subtitle: 'line ${b.line + 1}',
                            tooltip: b.url,
                            onTap: () => widget.onJumpToSource(b.url, b.line),
                            onDelete: () => _removeSourceBp(b),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.error_outline_rounded,
            title: isZh ? '抛出异常时暂停' : 'Pause on exceptions',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'none',
                    label: Text(isZh ? '关' : 'Off'),
                    icon: const Icon(Icons.do_disturb_alt_rounded),
                  ),
                  ButtonSegment(
                    value: 'uncaught',
                    label: Text(isZh ? '仅未捕获' : 'Uncaught only'),
                    icon: const Icon(Icons.report_problem_outlined),
                  ),
                  ButtonSegment(
                    value: 'all',
                    label: Text(isZh ? '全部' : 'All'),
                    icon: const Icon(Icons.bug_report_rounded),
                  ),
                ],
                selected: {widget.controller.pauseOnExceptions},
                onSelectionChanged: (s) {
                  if (s.isNotEmpty) _setPause(s.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            icon: Icons.cloud_download_outlined,
            title: isZh ? 'XHR / fetch 断点（URL 子串匹配）' : 'XHR / fetch breakpoints (URL substring)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xhrCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: isZh
                              ? 'URL 子串（留空 = 拦截全部）'
                              : 'URL substring (empty = all)',
                        ),
                        onSubmitted: (_) => _addXhr(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addXhr,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(isZh ? '添加' : 'Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedSize(
                  duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                  curve: _kSwitchInCurve,
                  child: xhrBps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            isZh ? '尚未添加。' : 'None yet.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      : Column(
                          children: [
                            for (final s in xhrBps)
                              _BpRow(
                                icon: Icons.link_rounded,
                                iconColor: cs.tertiary,
                                title: s.isEmpty
                                    ? (isZh ? '<全部 XHR>' : '<any XHR>')
                                    : s,
                                subtitle: null,
                                tooltip: null,
                                onTap: null,
                                onDelete: () => _removeXhr(s),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortUrl(String u) {
    final lastSlash = u.lastIndexOf('/');
    if (lastSlash < 0 || lastSlash == u.length - 1) return u;
    return u.substring(lastSlash + 1);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _BpRow extends StatelessWidget {
  const _BpRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onTap,
    required this.onDelete,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 10, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.close_rounded, size: 16, color: cs.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
    Widget content = onTap == null
        ? row
        : InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: row,
          );
    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}

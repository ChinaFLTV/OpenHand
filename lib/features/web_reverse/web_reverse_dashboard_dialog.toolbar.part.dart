part of 'web_reverse_dashboard_dialog.dart';

extension _WebReverseDashboardToolbar on _WebReverseDashboardDialogState {
  Widget _buildToolbar(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
    bool reduceMotion,
  ) {
    // 工具条结构：
    //   行 1：8 个 tab 胶囊（计数 badge 自动 cross-fade），可水平滚动避免溢出
    //   行 2：搜索框 + 切换胶囊 + 节流下拉 + 图标按钮 + Primary，可水平滚动
    // 两行布局保证 1024 宽度下不被挤变形（之前单行 8 tabs + 6+ 控件 必溢出）。
    const tabs = _Tab.values;
    final showNetworkControls = _tab == _Tab.network;
    final showSearch = _tab == _Tab.network || _tab == _Tab.console;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _kToolbarHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    _ToolbarTabPill(
                      label: _tabLabel(tabs[i], isZh),
                      icon: _tabIcon(tabs[i]),
                      count: _tabBadgeCount(tabs[i]),
                      active: _tab == tabs[i],
                      onTap: () =>
                          rebuildFromExternal(() => _tab = tabs[i]),
                      reduceMotion: reduceMotion,
                    ),
                    if (i != tabs.length - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          if (showSearch || showNetworkControls) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: _kToolbarHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    if (showSearch) ...[
                      _ToolbarSearchField(
                        controller: _filterCtrl,
                        hint: _tab == _Tab.network
                            ? (isZh ? '搜索 URL / 文本' : 'Search URL / text')
                            : (isZh ? '搜索控制台' : 'Search console'),
                        onChanged: (v) => rebuildFromExternal(
                            () => _networkFilter = v.trim()),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showNetworkControls) ...[
                      _ToolbarTogglePill(
                        label: isZh ? '禁用缓存' : 'Disable cache',
                        icon: Icons.no_drinks_rounded,
                        selected: _cacheDisabled,
                        onChanged: (v) async {
                          rebuildFromExternal(() => _cacheDisabled = v);
                          await ctrl.setCacheDisabled(v);
                        },
                        reduceMotion: reduceMotion,
                      ),
                      const SizedBox(width: 8),
                      _ToolbarTogglePill(
                        label: isZh ? '保留日志' : 'Preserve log',
                        icon: Icons.history_toggle_off_rounded,
                        selected: ctrl.preserveLog,
                        onChanged: (v) => ctrl.preserveLog = v,
                        reduceMotion: reduceMotion,
                      ),
                      const SizedBox(width: 8),
                      _ToolbarThrottleButton(
                        value: _throttle,
                        isZh: isZh,
                        onChanged: (preset) async {
                          rebuildFromExternal(() => _throttle = preset);
                          final ok = await ctrl.setNetworkThrottling(preset);
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isZh
                                    ? '节流设置失败'
                                    : 'Failed to set throttling'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    _ToolbarIconButton(
                      tooltip: isZh ? '清空当前缓冲' : 'Clear buffers',
                      icon: Icons.cleaning_services_rounded,
                      onPressed: () {
                        ctrl.clearBuffers();
                        final st = _networkListKey.currentState;
                        if (st != null) rebuildFromExternal(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    _ToolbarIconButton(
                      tooltip: isZh ? '导出 HAR 到本地文件' : 'Save HAR to file',
                      icon: Icons.archive_rounded,
                      onPressed: () => _saveHarToFile(ctrl, isZh),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarPrimaryPill(
                      icon: Icons.open_in_new_rounded,
                      label: isZh ? '打开官方 DevTools' : 'Open DevTools',
                      onPressed: () => _openOfficialDevTools(ctrl),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _tabLabel(_Tab t, bool isZh) => switch (t) {
        _Tab.overview => isZh ? '概览' : 'Overview',
        _Tab.network => isZh ? '网络' : 'Network',
        _Tab.console => isZh ? '控制台' : 'Console',
        _Tab.performance => isZh ? '性能' : 'Performance',
        _Tab.memory => isZh ? '内存' : 'Memory',
        _Tab.application => isZh ? '应用' : 'Application',
        _Tab.security => isZh ? '安全' : 'Security',
        _Tab.recorder => isZh ? '记录器' : 'Recorder',
      };

  IconData _tabIcon(_Tab t) => switch (t) {
        _Tab.overview => Icons.dashboard_rounded,
        _Tab.network => Icons.swap_horiz_rounded,
        _Tab.console => Icons.terminal_rounded,
        _Tab.performance => Icons.speed_rounded,
        _Tab.memory => Icons.memory_rounded,
        _Tab.application => Icons.apps_rounded,
        _Tab.security => Icons.shield_outlined,
        _Tab.recorder => Icons.fiber_manual_record_rounded,
      };

  int? _tabBadgeCount(_Tab t) {
    final c = widget.controller;
    return switch (t) {
      _Tab.overview => null,
      _Tab.network => c.networkRequests.length,
      _Tab.console => c.consoleMessages.length,
      _ => null,
    };
  }

  Future<void> _saveHarToFile(
    WebReverseSessionController ctrl,
    bool isZh,
  ) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(label: 'HAR', extensions: <String>['har']);
    // 在任何 await 之前缓存 messenger，避免 context 跨 async gap 警告。
    final messenger = ScaffoldMessenger.of(context);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'web-reverse-$ts.har',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'getSaveLocation HAR',
        error,
        stack,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(isZh ? '打开保存对话框失败' : 'Failed to open save dialog'),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    if (location == null) return; // 用户取消
    String? written;
    try {
      written = await ctrl
          .exportHarToPath(location.path)
          .timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'exportHarToPath',
        error,
        stack,
      );
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(written == null
          ? (isZh ? 'HAR 保存失败或超时' : 'HAR save failed or timed out')
          : (isZh ? 'HAR 已保存到 $written' : 'HAR saved to $written')),
      duration: const Duration(seconds: 3),
    ));
  }
}

/// 工具栏的 tab 胶囊：高度 36，圆角 999，激活态填 primary container。
/// 计数角标自动 cross-fade。
class _ToolbarTabPill extends StatelessWidget {
  const _ToolbarTabPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.reduceMotion,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool reduceMotion;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: Container(
                        key: ValueKey<int>(count!),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarSearchField extends StatefulWidget {
  const _ToolbarSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_ToolbarSearchField> createState() => _ToolbarSearchFieldState();
}

class _ToolbarSearchFieldState extends State<_ToolbarSearchField> {
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocus);
    widget.controller.addListener(_onText);
    _hasText = widget.controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  void _onText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 260,
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _focused
              ? cs.surface
              : cs.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: _focused ? cs.primary : cs.outlineVariant,
            width: _focused ? 1.4 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.search_rounded,
                size: 16,
                color: _focused ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: widget.onChanged,
                cursorColor: cs.primary,
                cursorWidth: 1.4,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              transitionBuilder: (c, a) =>
                  FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
              child: _hasText
                  ? IconButton(
                      key: const ValueKey('clear'),
                      tooltip: 'Clear',
                      onPressed: () {
                        widget.controller.clear();
                        widget.onChanged('');
                      },
                      icon: const Icon(Icons.cancel_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      visualDensity: VisualDensity.compact,
                      color: cs.onSurfaceVariant,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarTogglePill extends StatelessWidget {
  const _ToolbarTogglePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onChanged,
    required this.reduceMotion,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: selected
                ? cs.secondary.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!selected),
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: _kToolbarHeight,
        width: _kToolbarHeight,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Center(
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarPrimaryPill extends StatelessWidget {
  const _ToolbarPrimaryPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: Material(
        color: cs.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kToolbarRadius),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: cs.onPrimary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarThrottleButton extends StatelessWidget {
  const _ToolbarThrottleButton({
    required this.value,
    required this.isZh,
    required this.onChanged,
  });

  final WebReverseThrottlePreset value;
  final bool isZh;
  final ValueChanged<WebReverseThrottlePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: PopupMenuButton<WebReverseThrottlePreset>(
        tooltip: isZh ? '网络节流' : 'Throttling',
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => WebReverseThrottlePreset.values
            .map((p) => PopupMenuItem(value: p, child: Text(p.label)))
            .toList(growable: false),
        child: Container(
          decoration: BoxDecoration(
            color: value == WebReverseThrottlePreset.none
                ? Colors.transparent
                : cs.tertiaryContainer,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            border: Border.all(
              color: value == WebReverseThrottlePreset.none
                  ? cs.outlineVariant
                  : cs.tertiary.withValues(alpha: 0.4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_rounded,
                size: 14,
                color: value == WebReverseThrottlePreset.none
                    ? cs.onSurfaceVariant
                    : cs.onTertiaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                value.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: value == WebReverseThrottlePreset.none
                      ? cs.onSurface
                      : cs.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                            OpenHandSnackBar.showError(
                              context,
                              isZh
                                  ? '节流设置失败'
                                  : 'Failed to set throttling',
                              duration: const Duration(seconds: 2),
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
                    _ToolbarIconButton(
                      tooltip: isZh ? '导入 HAR 反向加载' : 'Load HAR file',
                      icon: Icons.unarchive_rounded,
                      onPressed: () => _loadHarFromFile(ctrl, isZh),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarIconButton(
                      tooltip: isZh
                          ? '截图（当前可视区）'
                          : 'Screenshot (viewport)',
                      icon: Icons.photo_camera_outlined,
                      onPressed: () =>
                          _saveScreenshot(ctrl, isZh, fullPage: false),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarIconButton(
                      tooltip: isZh
                          ? '截图（整页滚动拼接）'
                          : 'Screenshot (full page)',
                      icon: Icons.picture_in_picture_rounded,
                      onPressed: () =>
                          _saveScreenshot(ctrl, isZh, fullPage: true),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarTogglePill(
                      label: isZh ? '请求拦截' : 'Intercept',
                      icon: Icons.block_rounded,
                      selected: ctrl.isFetchInterceptEnabled,
                      onChanged: (v) async {
                        await ctrl.setFetchInterceptEnabled(v);
                      },
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(width: 8),
                    // 高级菜单：把"持久 Header / 体检报告 / 原生 CDP / 反向脚本"
                    // 等低频但威力强的功能合到一颗按钮，避免 Toolbar 二行膨胀。
                    _ToolbarIconButton(
                      tooltip: isZh ? '高级工具' : 'Advanced',
                      icon: Icons.tune_rounded,
                      onPressed: () => _showAdvancedMenu(context, ctrl, isZh),
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
        _Tab.sources => isZh ? '源码' : 'Sources',
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
        _Tab.sources => Icons.source_rounded,
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
      _Tab.sources =>
        c.parsedScripts.isEmpty ? null : c.parsedScripts.length,
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
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '打开保存对话框失败' : 'Failed to open save dialog',
        duration: const Duration(seconds: 2),
      );
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
    if (written == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'HAR 保存失败或超时' : 'HAR save failed or timed out',
        duration: const Duration(seconds: 3),
      );
    } else {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? 'HAR 已保存到 $written' : 'HAR saved to $written',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _saveScreenshot(
    WebReverseSessionController ctrl,
    bool isZh, {
    required bool fullPage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final bytes = fullPage
        ? await ctrl.captureFullPageScreenshot()
        : await ctrl.captureScreenshot();
    if (!mounted) return;
    if (bytes == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '截图失败' : 'Screenshot failed',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    // 让用户在导出前先标注（涂鸦 / 矩形 / 文字）。
    final marked = await showScreenshotMarkupDialog(context, image: bytes);
    if (!mounted || marked == null) return;
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(label: 'PNG', extensions: <String>['png']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'screenshot-${fullPage ? "full" : "viewport"}-$ts.png',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'getSaveLocation screenshot',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '打开保存对话框失败' : 'Failed to open save dialog',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    if (location == null) return;
    try {
      await File(location.path).writeAsBytes(marked, flush: true);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh ? '已保存到 ${location.path}' : 'Saved to ${location.path}',
        duration: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'write screenshot',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? '截图保存失败' : 'Screenshot save failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _loadHarFromFile(
    WebReverseSessionController ctrl,
    bool isZh,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(label: 'HAR', extensions: <String>['har', 'json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'openFile har',
        error,
        stack,
      );
    }
    if (file == null) return;
    // 当前缓冲非空时让用户选「替换」or「合并」；否则直接替换。
    bool merge = false;
    if (ctrl.networkRequests.isNotEmpty) {
      if (!mounted) return;
      final mode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isZh ? '加载 HAR' : 'Load HAR'),
          content: Text(
            isZh
                ? '当前网络列表已有 ${ctrl.networkRequests.length} 条记录，选择加载方式：'
                : 'Network list has ${ctrl.networkRequests.length} entries. Choose load mode:',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: Text(isZh ? '取消' : 'Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('merge'),
              child: Text(isZh ? '合并' : 'Merge'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('replace'),
              child: Text(isZh ? '替换' : 'Replace'),
            ),
          ],
        ),
      );
      if (mode == null || mode == 'cancel') return;
      merge = mode == 'merge';
    }
    try {
      final bytes = await file.readAsBytes();
      final r = ctrl.loadHarBytes(bytes, merge: merge);
      if (!mounted) return;
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        isZh
            ? '${merge ? "合并" : "替换"}加载 ${r.loaded} 条；跳过 ${r.skipped} 条无效条目'
            : '${merge ? "Merged" : "Replaced"}: ${r.loaded}; skipped ${r.skipped}',
        duration: const Duration(seconds: 3),
      );
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        'parse har',
        error,
        stack,
      );
      if (!mounted) return;
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        isZh ? 'HAR 解析失败' : 'HAR parse failed',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// 高级工具菜单：聚合体检报告 / 持久化 Header / CDP 命令面板 /
  /// 反向脚本一键导出 / AI 接口分析。这些都是低频但杠杆很大的入口，
  /// 合成一颗 Toolbar 图标按钮的弹窗里，避免污染主 toolbar 视觉。
  void _showAdvancedMenu(
    BuildContext context,
    WebReverseSessionController ctrl,
    bool isZh,
  ) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _AdvancedMenuDialog(controller: ctrl, isZh: isZh),
    );
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
                  // 2026-05-17 — 全局 InputDecorationTheme 默认 filled:true
                  // 会让搜索胶囊内部再叠一层 fill，看起来像「胶囊里又套
                  // 一只胶囊」。这里强制 filled:false + border:none，让
                  // 文本输入区与外层 AnimatedContainer 的圆角胶囊融为一
                  // 体，视觉上只保留最外层一道边。
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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
                  ? InkResponse(
                      key: const ValueKey('clear'),
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged('');
                      },
                      radius: 14,
                      // 用极简的圆形点击响应替代 IconButton：原 IconButton 自带
                      // 36×36 命中圈在胶囊里会形成"胶囊里又套一个圆"的视觉，
                      // 这里仅保留图标本体并通过 InkResponse 给一个无 fill 的
                      // 圆形 ripple，外形与外层胶囊浑然一体。
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
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
          // 2026-05-17 — 与全局主色保持一致：选中态用 primaryContainer
          // (而不是 secondaryContainer)，避免和会话顶部胶囊 / 设置项中
          // "已启用并注入" 的绿调风格出现两套主题。
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.36)
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
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
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
                : cs.primaryContainer,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            border: Border.all(
              color: value == WebReverseThrottlePreset.none
                  ? cs.outlineVariant
                  : cs.primary.withValues(alpha: 0.36),
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
                    : cs.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                value.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: value == WebReverseThrottlePreset.none
                      ? cs.onSurface
                      : cs.onPrimaryContainer,
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

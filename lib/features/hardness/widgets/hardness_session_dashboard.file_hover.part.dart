part of 'hardness_session_dashboard.dart';

class _HeFileHoverPopup extends StatefulWidget {
  const _HeFileHoverPopup({
    required this.resolvedPath,
    required this.child,
    this.isUnresolved = false,
  });

  final String resolvedPath;
  final Widget child;
  final bool isUnresolved;

  @override
  State<_HeFileHoverPopup> createState() => _HeFileHoverPopupState();
}

class _HeFileHoverPopupState extends State<_HeFileHoverPopup> {
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;
  bool _showScheduled = false;
  bool _hideScheduled = false;

  bool get _isModifierPressed {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return pressed.contains(PhysicalKeyboardKey.controlLeft) ||
        pressed.contains(PhysicalKeyboardKey.controlRight) ||
        pressed.contains(PhysicalKeyboardKey.metaLeft) ||
        pressed.contains(PhysicalKeyboardKey.metaRight);
  }

  void _showOverlay() {
    if (widget.isUnresolved || _overlayEntry != null || _showScheduled) return;
    // Defer overlay insertion to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase, which triggers the
    // !_debugDuringDeviceUpdate re-entrancy assertion.
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlayEntry != null) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    var targetLeft = offset.dx;
    if (targetLeft + 320 > screenSize.width - 16) {
      targetLeft = screenSize.width - 320 - 16;
      if (targetLeft < 8) targetLeft = 8;
    }

    var targetTop = offset.dy + size.height + 6;
    const estimatedHeight = 140.0;
    if (targetTop + estimatedHeight > screenSize.height - 16) {
      targetTop = offset.dy - estimatedHeight - 6;
    }

    final resolvedPath = widget.resolvedPath;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: targetLeft,
        top: targetTop,
        child: IgnorePointer(
          child: AnimatedOverlayContent(
            useMenuSettings: true,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    overlayContext,
                  ).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(overlayContext).dividerColor,
                  ),
                ),
                width: 320,
                child: FutureBuilder<FileStat>(
                  future: FileStat.stat(resolvedPath),
                  builder: (ctx, snapshot) {
                    final theme = Theme.of(ctx);
                    final colorScheme = theme.colorScheme;
                    final isZhLocale =
                        Localizations.localeOf(ctx).languageCode == 'zh';

                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final stat = snapshot.data!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolvedPath,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _HeStatRow(
                          isZhLocale ? '类型' : 'Type',
                          stat.type.toString(),
                        ),
                        _HeStatRow(
                          isZhLocale ? '大小' : 'Size',
                          '${stat.size} bytes',
                        ),
                        _HeStatRow(
                          isZhLocale ? '修改于' : 'Modified',
                          '${stat.modified}',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    } catch (_) {
      _overlayEntry = null;
    }
  }

  void _hideOverlay() {
    if (_overlayEntry == null && !_showScheduled) return;
    _showScheduled = false;
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    // Defer overlay removal to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase.
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      entry.remove();
    });
  }

  @override
  void didUpdateWidget(_HeFileHoverPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.isUnresolved != widget.isUnresolved) {
      _hideOverlay();
    }
  }

  @override
  void deactivate() {
    // Synchronous removal since the widget is leaving the tree.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isHovered = false;
    super.deactivate();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || !_isHovered || widget.isUnresolved) return false;
    if (_isModifierPressed) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    _hideOverlay();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        if (!widget.isUnresolved && _isModifierPressed) _showOverlay();
      },
      onHover: (_) {
        if (!widget.isUnresolved) {
          if (_isModifierPressed) {
            _showOverlay();
          } else {
            _hideOverlay();
          }
        }
      },
      onExit: (_) {
        _isHovered = false;
        _hideOverlay();
      },
      child: widget.child,
    );
  }
}

class _HeStatRow extends StatelessWidget {
  const _HeStatRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Top-level helper — opens a path in the system file browser (Finder / Explorer
// / Nautilus), mirroring _openResolvedMessagePath from openhand_home_page.dart.
// =============================================================================

Future<void> _heOpenPathInFileBrowser(
  BuildContext context,
  String path, {
  required bool isDirectory,
}) async {
  try {
    final bool launched;
    if (Platform.isMacOS) {
      // `-R` reveals the file in its parent Finder window; for directories
      // just open the directory itself.
      launched = await runDetachedSystemOpen(
        'open',
        isDirectory ? <String>[path] : <String>['-R', path],
      );
    } else if (Platform.isWindows) {
      launched = await runDetachedSystemOpen(
        'explorer',
        isDirectory ? <String>[path] : <String>['/select,$path'],
      );
    } else if (Platform.isLinux) {
      launched = await runDetachedSystemOpen('xdg-open', <String>[
        isDirectory ? path : File(path).parent.path,
      ]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (launched) return;
    throw const FileSystemException('Unable to open file location.');
  } catch (error) {
    if (!context.mounted) return;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    showFriendlyErrorSnackBar(
      context,
      message: '$error',
      fallback: isZh ? '打开文件位置失败' : 'Failed to open file location',
    );
  }
}

// =============================================================================
// _HeSteeringAssetsDialog — breadcrumb directory browser for steering files
// =============================================================================

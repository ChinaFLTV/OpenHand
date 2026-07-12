part of 'harness_session_dashboard.dart';

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
  final AnimatedOverlayEntryController _overlay =
      AnimatedOverlayEntryController();
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
    if (widget.isUnresolved || _showScheduled) return;
    if (_overlay.hasEntry) {
      _hideScheduled = false;
      _overlay.reopen();
      return;
    }
    // Defer overlay insertion to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase, which triggers the
    // !_debugDuringDeviceUpdate re-entrancy assertion.
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlay.hasEntry) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlay.hasEntry) return;
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

    try {
      _overlay.show(
        overlay: Overlay.of(context, rootOverlay: true),
        builder: (overlayContext, visibility, onExitCompleted) => Positioned(
          left: targetLeft,
          top: targetTop,
          child: IgnorePointer(
            child: AnimatedOverlayContent(
              useMenuSettings: true,
              visibility: visibility,
              onExitCompleted: onExitCompleted,
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
                            openHandLocalizedText(
                              ctx,
                              zh: '类型',
                              en: 'Type',
                              zhHant: '類型',
                              fr: 'Type',
                              de: 'Typ',
                              ja: '種類',
                            ),
                            stat.type.toString(),
                          ),
                          _HeStatRow(
                            openHandLocalizedText(
                              ctx,
                              zh: '大小',
                              en: 'Size',
                              zhHant: '大小',
                              fr: 'Taille',
                              de: 'Größe',
                              ja: 'サイズ',
                            ),
                            '${stat.size} bytes',
                          ),
                          _HeStatRow(
                            openHandLocalizedText(
                              ctx,
                              zh: '修改于',
                              en: 'Modified',
                              zhHant: '修改於',
                              fr: 'Modifié',
                              de: 'Geändert',
                              ja: '更新日時',
                            ),
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
    } catch (_) {
      // The owner may be deactivating while the deferred show callback runs.
    }
  }

  void _hideOverlay() {
    if (!_overlay.hasEntry && !_showScheduled) return;
    _showScheduled = false;
    if (!_overlay.hasEntry) return;
    // Defer the visibility mutation to avoid rebuilding the overlay during
    // MouseTracker._deviceUpdatePhase. The shared overlay transition removes
    // the entry only after its globally configured reverse motion completes.
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hideScheduled) return;
      _hideScheduled = false;
      if (!mounted) {
        _removeOverlayImmediately();
        return;
      }
      _overlay.close();
    });
  }

  void _removeOverlayImmediately() {
    _showScheduled = false;
    _hideScheduled = false;
    _overlay.close(immediately: true);
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
    _removeOverlayImmediately();
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
    _showScheduled = false;
    _hideScheduled = false;
    _overlay.dispose();
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

// Top-level helper — opens a path in the system file browser (Finder / Explorer
// / Nautilus), mirroring _openResolvedMessagePath from openhand_home_page.dart.
Future<void> _heOpenPathInFileBrowser(BuildContext context, String path) async {
  try {
    final launched = await revealLocalPathInSystemFileManager(
      path,
      tag: 'harness_session_dashboard.file_hover.reveal',
    );
    if (launched) return;
    throw const FileSystemException('Unable to open file location.');
  } catch (error) {
    if (!context.mounted) return;
    showFriendlyErrorSnackBar(
      context,
      message: '$error',
      fallback: openHandLocalizedText(
        context,
        zh: '打开文件位置失败',
        en: 'Failed to open file location',
        zhHant: '打開檔案位置失敗',
        fr: 'Impossible d’ouvrir l’emplacement du fichier',
        de: 'Dateispeicherort konnte nicht geöffnet werden',
        ja: 'ファイルの場所を開けませんでした',
      ),
    );
  }
}

// _HeSteeringAssetsDialog — breadcrumb directory browser for steering files

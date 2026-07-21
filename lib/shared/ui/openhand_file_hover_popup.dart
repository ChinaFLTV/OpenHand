import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/localized_text.dart';
import 'animated_overlay.dart';
import 'motion_preference.dart';

const double _popupWidth = 320;
const double _popupHorizontalMargin = 8;
const double _popupVerticalGap = 6;
const double _estimatedPopupHeight = 140;
const Duration _contentResizeDuration = Duration(milliseconds: 200);
const Duration _contentSwitchDuration = Duration(milliseconds: 220);
const Curve _contentMotionCurve = Curves.easeOutCubic;

class OpenHandFileHoverPopup extends StatefulWidget {
  const OpenHandFileHoverPopup({
    required this.resolvedPath,
    required this.child,
    this.isUnresolved = false,
    super.key,
  });

  final String resolvedPath;
  final Widget child;
  final bool isUnresolved;

  @override
  State<OpenHandFileHoverPopup> createState() => _OpenHandFileHoverPopupState();
}

class _OpenHandFileHoverPopupState extends State<OpenHandFileHoverPopup> {
  final AnimatedOverlayEntryController _overlay =
      AnimatedOverlayEntryController();
  bool _isHovered = false;
  bool _isListening = false;
  bool _showScheduled = false;
  bool _hideScheduled = false;

  bool get _isControlOrMetaPressed {
    final pressedKeys = HardwareKeyboard.instance.physicalKeysPressed;
    return pressedKeys.contains(PhysicalKeyboardKey.controlLeft) ||
        pressedKeys.contains(PhysicalKeyboardKey.controlRight) ||
        pressedKeys.contains(PhysicalKeyboardKey.metaLeft) ||
        pressedKeys.contains(PhysicalKeyboardKey.metaRight);
  }

  void _startListening() {
    if (_isListening || widget.isUnresolved) return;
    HardwareKeyboard.instance.addHandler(_handleKey);
    _isListening = true;
  }

  void _stopListening() {
    if (!_isListening) return;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _isListening = false;
  }

  void _showOverlay() {
    if (widget.isUnresolved || _showScheduled) return;
    if (_overlay.hasEntry) {
      _hideScheduled = false;
      _overlay.reopen();
      return;
    }
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlay.hasEntry) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlay.hasEntry) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    final screenSize = MediaQuery.sizeOf(context);
    final availableWidth = screenSize.width - _popupHorizontalMargin * 2;
    if (availableWidth <= 0) return;
    final popupWidth = math.min(_popupWidth, availableWidth);
    final offset = renderObject.localToGlobal(Offset.zero);
    final maxLeft = math.max(
      _popupHorizontalMargin,
      screenSize.width - popupWidth - _popupHorizontalMargin,
    );
    final targetLeft = offset.dx.clamp(_popupHorizontalMargin, maxLeft);

    var targetTop = offset.dy + renderObject.size.height + _popupVerticalGap;
    if (targetTop + _estimatedPopupHeight >
        screenSize.height - _popupHorizontalMargin) {
      targetTop = offset.dy - _estimatedPopupHeight - _popupVerticalGap;
    }
    targetTop = math.max(_popupHorizontalMargin, targetTop);

    final resolvedPath = widget.resolvedPath;
    final statFuture = FileStat.stat(resolvedPath);
    _overlay.show(
      overlay: overlayState,
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
                width: popupWidth,
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
                child: FutureBuilder<FileStat>(
                  future: statFuture,
                  builder: (context, snapshot) =>
                      _buildMetadata(context, snapshot, resolvedPath),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadata(
    BuildContext context,
    AsyncSnapshot<FileStat> snapshot,
    String resolvedPath,
  ) {
    final theme = Theme.of(context);
    final stat = snapshot.data;
    return AnimatedSize(
      duration: openHandMotionDuration(context, _contentResizeDuration),
      curve: _contentMotionCurve,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: openHandMotionDuration(context, _contentSwitchDuration),
        switchInCurve: _contentMotionCurve,
        switchOutCurve: Curves.easeInCubic,
        child: stat == null && !snapshot.hasError
            ? const SizedBox(
                key: ValueKey<String>('loading'),
                height: 40,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : stat == null
            ? Text(
                openHandLocalizedText(
                  context,
                  zh: '无法读取文件信息',
                  en: 'Unable to read file metadata',
                  zhHant: '無法讀取檔案資訊',
                  fr: 'Impossible de lire les informations du fichier',
                  de: 'Dateiinformationen konnten nicht gelesen werden',
                  ja: 'ファイル情報を読み取れません',
                ),
                key: const ValueKey<String>('error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              )
            : Column(
                key: const ValueKey<String>('loaded'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resolvedPath,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MetadataRow(
                    openHandLocalizedText(
                      context,
                      zh: '类型',
                      en: 'Type',
                      zhHant: '類型',
                      fr: 'Type',
                      de: 'Typ',
                      ja: '種類',
                    ),
                    stat.type.toString(),
                  ),
                  _MetadataRow(
                    openHandLocalizedText(
                      context,
                      zh: '大小',
                      en: 'Size',
                      zhHant: '大小',
                      fr: 'Taille',
                      de: 'Größe',
                      ja: 'サイズ',
                    ),
                    '${stat.size} bytes',
                  ),
                  _MetadataRow(
                    openHandLocalizedText(
                      context,
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
              ),
      ),
    );
  }

  void _hideOverlay() {
    if (!_overlay.hasEntry && !_showScheduled) return;
    _showScheduled = false;
    if (!_overlay.hasEntry || _hideScheduled) return;
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

  bool _handleKey(KeyEvent event) {
    if (!mounted || !_isHovered || widget.isUnresolved) return false;
    if (_isControlOrMetaPressed) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    return false;
  }

  @override
  void didUpdateWidget(OpenHandFileHoverPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.isUnresolved != widget.isUnresolved) {
      _hideOverlay();
    }
    if (!_isHovered || widget.isUnresolved) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  @override
  void deactivate() {
    _stopListening();
    _removeOverlayImmediately();
    _isHovered = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _stopListening();
    _overlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        _startListening();
        if (!widget.isUnresolved && _isControlOrMetaPressed) {
          _showOverlay();
        }
      },
      onHover: (_) {
        if (widget.isUnresolved) return;
        if (_isControlOrMetaPressed) {
          _showOverlay();
        } else {
          _hideOverlay();
        }
      },
      onExit: (_) {
        _isHovered = false;
        _stopListening();
        _hideOverlay();
      },
      child: widget.child,
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

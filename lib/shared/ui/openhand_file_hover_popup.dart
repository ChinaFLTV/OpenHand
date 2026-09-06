import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../util/localized_text.dart';
import 'animated_overlay.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';

const double _popupWidth = 320;
const double _popupHorizontalMargin = 8;
const double _popupVerticalGap = 6;
const Duration _contentResizeDuration = kOpenHandMotion200;
const Duration _contentSwitchDuration = kOpenHandMotion220;
const Duration _fileStatTimeout = Duration(seconds: 2);
const Curve _contentMotionCurve = kOpenHandSwitchInCurve;

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
  String? _overlayPath;
  Future<FileStat>? _overlayStatFuture;

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
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;
    if (_overlay.hasEntry) {
      _hideScheduled = false;
      _prepareOverlayContent();
      _overlay.show(overlay: overlayState, builder: _buildOverlayEntry);
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
    _prepareOverlayContent();
    _overlay.show(overlay: overlayState, builder: _buildOverlayEntry);
  }

  void _prepareOverlayContent() {
    if (_overlayPath == widget.resolvedPath && _overlayStatFuture != null) {
      return;
    }
    _overlayPath = widget.resolvedPath;
    _overlayStatFuture = FileStat.stat(
      widget.resolvedPath,
    ).timeout(_fileStatTimeout);
  }

  Widget _buildOverlayEntry(
    BuildContext overlayContext,
    ValueListenable<bool> visibility,
    VoidCallback onExitCompleted,
  ) {
    Widget animatedContent(
      Widget child, {
      Alignment alignment = Alignment.center,
    }) {
      return AnimatedOverlayContent(
        visibility: visibility,
        onExitCompleted: onExitCompleted,
        alignment: alignment,
        child: child,
      );
    }

    final renderObject = context.findRenderObject();
    final overlayObject = Overlay.of(overlayContext).context.findRenderObject();
    if (renderObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !renderObject.hasSize ||
        !overlayObject.hasSize ||
        !renderObject.attached ||
        !overlayObject.attached) {
      return animatedContent(const SizedBox.shrink());
    }
    final mediaSize = MediaQuery.sizeOf(overlayContext);
    final screenSize = overlayObject.size.isEmpty
        ? mediaSize
        : overlayObject.size;
    final availableWidth = screenSize.width - _popupHorizontalMargin * 2;
    if (availableWidth <= 0 || screenSize.height <= 0) {
      return animatedContent(const SizedBox.shrink());
    }
    final popupWidth = math.min(_popupWidth, availableWidth);
    final offset = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final maxLeft = math.max(
      _popupHorizontalMargin,
      screenSize.width - popupWidth - _popupHorizontalMargin,
    );
    final targetLeft = offset.dx.clamp(_popupHorizontalMargin, maxLeft);
    final belowSpace = math.max(
      0.0,
      screenSize.height -
          offset.dy -
          renderObject.size.height -
          _popupVerticalGap -
          _popupHorizontalMargin,
    );
    final aboveSpace = math.max(
      0.0,
      offset.dy - _popupVerticalGap - _popupHorizontalMargin,
    );
    final showAbove = aboveSpace > belowSpace;
    final availableHeight = math.max(1.0, showAbove ? aboveSpace : belowSpace);
    final resolvedPath = _overlayPath ?? widget.resolvedPath;
    final statFuture =
        _overlayStatFuture ??
        FileStat.stat(resolvedPath).timeout(_fileStatTimeout);
    final child = IgnorePointer(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: animatedContent(
          Material(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(kOpenHandRadius8),
            child: Container(
              width: popupWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  overlayContext,
                ).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
                border: Border.all(
                  color: Theme.of(overlayContext).dividerColor,
                ),
              ),
              child: SingleChildScrollView(
                primary: false,
                child: FutureBuilder<FileStat>(
                  future: statFuture,
                  builder: (context, snapshot) =>
                      _buildMetadata(context, snapshot, resolvedPath),
                ),
              ),
            ),
          ),
          alignment: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
        ),
      ),
    );
    if (showAbove) {
      return Positioned(
        left: targetLeft,
        bottom: screenSize.height - offset.dy + _popupVerticalGap,
        child: child,
      );
    }
    return Positioned(
      left: targetLeft,
      top: offset.dy + renderObject.size.height + _popupVerticalGap,
      child: child,
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
        switchOutCurve: kOpenHandSwitchOutCurve,
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
                    softWrap: true,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  kOpenHandGap12,
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
      _overlayPath = null;
      _overlayStatFuture = null;
      if (_isHovered && !widget.isUnresolved && _isControlOrMetaPressed) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
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
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _overlay.markNeedsBuild();
        return false;
      },
      child: MouseRegion(
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
      ),
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

/// 路径胶囊的固定尺寸：圆角、内边距、图标边长与文本上限宽度。
const EdgeInsets _kFilePathChipPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 5,
);
const double _kFilePathChipIconSize = 14;
const double _kFilePathChipMaxTextWidth = 340;

/// 消息正文里的文件路径胶囊：悬停出预览、点击打开，未解析时降级为灰态且不可点。
///
/// 主会话工具卡片与 Harness 流式视图此前各写了一份逐字节相同的实现，只有
/// "打开"这一步的落点不同。
class OpenHandFilePathChip extends StatelessWidget {
  const OpenHandFilePathChip({
    super.key,
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
    required this.textColor,
    required this.onOpen,
    this.isUnresolved = false,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
  final Color textColor;

  /// 点击后的打开动作；[isUnresolved] 为 true 时不会被调用。
  final VoidCallback onOpen;

  /// 路径未能在磁盘上定位；此时只做灰态展示。
  final bool isUnresolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);

    return OpenHandFileHoverPopup(
      resolvedPath: resolvedPath,
      isUnresolved: isUnresolved,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: kOpenHandPillBorderRadius,
          onTap: isUnresolved ? null : onOpen,
          child: Ink(
            padding: _kFilePathChipPadding,
            decoration: BoxDecoration(
              color: isUnresolved
                  ? chipColor.withValues(alpha: 0.3)
                  : chipColor,
              borderRadius: kOpenHandPillBorderRadius,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnresolved
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: _kFilePathChipIconSize,
                  color: isUnresolved
                      ? textColor.withValues(alpha: 0.5)
                      : textColor.withValues(alpha: 0.9),
                ),
                kOpenHandHGap6,
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kFilePathChipMaxTextWidth,
                    ),
                    child: Text(
                      displayPath,
                      overflow: TextOverflow.ellipsis,
                      style: isUnresolved
                          ? labelStyle.copyWith(
                              color: textColor.withValues(alpha: 0.5),
                            )
                          : labelStyle,
                    ),
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

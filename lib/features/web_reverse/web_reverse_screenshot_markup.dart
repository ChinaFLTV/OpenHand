import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_tap_region.dart';
import 'web_reverse_dialog_utils.dart';

/// 截图导出前的注释面板。支持五种笔刷：
///   - draw：自由涂鸦
///   - rect：矩形框
///   - arrow：箭头（直线 + 末端两条 30° 斜线）
///   - blur：模糊遮挡（对原图局部区域做高斯模糊，用于隐私马赛克）
///   - text：文字标签（点空白位置插入）
/// 用户点"完成"后用 RepaintBoundary.toImage 导出 PNG 字节。
/// 取消则返回原图字节。
Future<Uint8List?> showScreenshotMarkupDialog(
  BuildContext context, {
  required Uint8List image,
}) {
  return webReverseToolDialogs.show<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScreenshotMarkupDialog(image: image),
  );
}

enum _MarkupTool { draw, rect, arrow, blur, text }

class _Stroke {
  _Stroke({required this.tool, required this.color, required this.thickness});
  final _MarkupTool tool;
  final Color color;
  final double thickness;
  final List<Offset> points = <Offset>[];
}

/// 兼具矩形 / 箭头 / 模糊三种语义：用 [tool] 区分。
/// - [_MarkupTool.rect]：以 start-end 对角线绘制描边矩形。
/// - [_MarkupTool.arrow]：从 start 画到 end 的箭头。
/// - [_MarkupTool.blur]：对 start-end 包围矩形内的原图做高斯模糊。
class _RectShape {
  _RectShape({
    required this.tool,
    required this.color,
    required this.thickness,
  });
  final _MarkupTool tool;
  final Color color;
  final double thickness;
  Offset start = Offset.zero;
  Offset end = Offset.zero;
}

class _TextLabel {
  _TextLabel({required this.position, required this.text, required this.color});
  final Offset position;
  final String text;
  final Color color;
}

class _ScreenshotMarkupDialog extends StatefulWidget {
  const _ScreenshotMarkupDialog({required this.image});
  final Uint8List image;

  @override
  State<_ScreenshotMarkupDialog> createState() =>
      _ScreenshotMarkupDialogState();
}

class _ScreenshotMarkupDialogState extends State<_ScreenshotMarkupDialog> {
  final GlobalKey _boundary = GlobalKey();
  ui.Image? _decoded;
  _MarkupTool _tool = _MarkupTool.draw;
  Color _color = Colors.redAccent;
  double _thickness = 4;
  final List<_Stroke> _strokes = <_Stroke>[];
  final List<_RectShape> _rects = <_RectShape>[];
  final List<_TextLabel> _texts = <_TextLabel>[];
  _Stroke? _activeStroke;
  _RectShape? _activeRect;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.image);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _decoded = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final img = _decoded;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthFull,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Divider(height: 1, color: cs.outlineVariant),
          _buildToolbar(theme, cs),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: Container(
              color: const Color(0xFF1E1E1E),
              alignment: Alignment.center,
              child: img == null
                  ? const CircularProgressIndicator()
                  : InteractiveViewer(
                      maxScale: 4,
                      child: RepaintBoundary(
                        key: _boundary,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          onTapUp: (d) {
                            if (_tool == _MarkupTool.text) {
                              _addText(d.localPosition);
                            }
                          },
                          child: SizedBox(
                            width: img.width.toDouble(),
                            height: img.height.toDouble(),
                            child: CustomPaint(
                              painter: _MarkupPainter(
                                baseImage: img,
                                strokes: _strokes,
                                rects: _rects,
                                texts: _texts,
                                activeStroke: _activeStroke,
                                activeRect: _activeRect,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogHeader(
      context: context,
      icon: Icons.draw_rounded,
      iconSize: 22,
      title: loc?.webReverseMarkupTitle ?? 'Screenshot Markup',
      closeTooltip: loc?.commonCancel ?? 'Cancel',
      onClose: () => Navigator.of(context).pop(),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(widget.image),
          label: loc?.webReverseMarkupSaveWithout ?? 'Save without markup',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _exporting ? null : _export,
          icon: _exporting ? Icons.hourglass_top_rounded : Icons.check_rounded,
          label: _exporting
              ? (loc?.webReverseMarkupExporting ?? 'Exporting…')
              : (loc?.webReverseMarkupDone ?? 'Done'),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme cs) {
    // 使用高层级表面与分割线增强工具栏对比度。
    final loc = AppLocalizations.of(context);
    return Material(
      color: cs.surfaceContainerHighest,
      shape: Border(bottom: BorderSide(color: cs.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            for (final t in const [
              (_MarkupTool.draw, Icons.edit_rounded),
              (_MarkupTool.rect, Icons.crop_square_rounded),
              (_MarkupTool.arrow, Icons.north_east_rounded),
              (_MarkupTool.blur, Icons.blur_on_rounded),
              (_MarkupTool.text, Icons.text_fields_rounded),
            ]) ...[
              _ToolButton(
                icon: t.$2,
                active: _tool == t.$1,
                onTap: () => setState(() => _tool = t.$1),
              ),
              kOpenHandHGap6,
            ],
            kOpenHandHGap12,
            // 颜色选择
            for (final c in const [
              Colors.redAccent,
              Colors.amber,
              Colors.lightGreenAccent,
              Colors.cyanAccent,
              Colors.white,
            ]) ...[
              OpenHandTapRegion(
                onTap: () => setState(() => _color = c),
                child: AnimatedContainer(
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 150),
                  ),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      // 深色模式下 outlineVariant 与小色块边缘融化，改用
                      // outline 提升识别度。
                      color: _color == c ? cs.primary : cs.outline,
                      width: _color == c ? 2.4 : 1.2,
                    ),
                  ),
                ),
              ),
              kOpenHandHGap6,
            ],
            kOpenHandHGap12,
            SizedBox(
              width: 140,
              child: Row(
                children: [
                  Icon(
                    Icons.line_weight_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  kOpenHandHGap4,
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 16,
                      divisions: 15,
                      value: _thickness,
                      onChanged: (v) => setState(() => _thickness = v),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: loc?.webReverseMarkupUndo ?? 'Undo',
              onPressed: _undo,
              icon: const Icon(Icons.undo_rounded, size: 18),
            ),
            IconButton(
              tooltip: loc?.webReverseMarkupClear ?? 'Clear',
              onPressed: () => setState(() {
                _strokes.clear();
                _rects.clear();
                _texts.clear();
              }),
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  void _undo() {
    setState(() {
      // 按时间顺序撤销最后一项；这里没维护统一栈，简单处理：
      // 优先撤销 text > rect > stroke。
      if (_texts.isNotEmpty) {
        _texts.removeLast();
      } else if (_rects.isNotEmpty) {
        _rects.removeLast();
      } else if (_strokes.isNotEmpty) {
        _strokes.removeLast();
      }
    });
  }

  void _onPanStart(DragStartDetails d) {
    if (_tool == _MarkupTool.draw) {
      final s = _Stroke(tool: _tool, color: _color, thickness: _thickness)
        ..points.add(d.localPosition);
      setState(() => _activeStroke = s);
    } else if (_tool == _MarkupTool.rect ||
        _tool == _MarkupTool.arrow ||
        _tool == _MarkupTool.blur) {
      final r = _RectShape(tool: _tool, color: _color, thickness: _thickness)
        ..start = d.localPosition
        ..end = d.localPosition;
      setState(() => _activeRect = r);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_activeStroke != null) {
      setState(() => _activeStroke!.points.add(d.localPosition));
    } else if (_activeRect != null) {
      setState(() => _activeRect!.end = d.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_activeStroke != null) {
      setState(() {
        _strokes.add(_activeStroke!);
        _activeStroke = null;
      });
    } else if (_activeRect != null) {
      setState(() {
        _rects.add(_activeRect!);
        _activeRect = null;
      });
    }
  }

  Future<void> _addText(Offset position) async {
    final loc = AppLocalizations.of(context);
    final text = await showOpenHandTextInputDialog(
      context: context,
      title: loc?.webReverseMarkupAddTextTitle ?? 'Add text label',
      hintText: loc?.webReverseMarkupLabelHint ?? 'Label',
      cancelLabel: loc?.commonCancel ?? 'Cancel',
      confirmLabel: loc?.webReverseMarkupAdd ?? 'Add',
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _texts.add(_TextLabel(position: position, text: text, color: _color));
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop(widget.image);
        return;
      }
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (mounted) Navigator.of(context).pop(bytes ?? widget.image);
    } catch (_) {
      if (mounted) Navigator.of(context).pop(widget.image);
    }
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.primaryContainer : cs.surface.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandPillBorderRadius,
        side: BorderSide(
          color: active ? cs.primary.withValues(alpha: 0.4) : cs.outline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandPillBorderRadius,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 16,
            color: active ? cs.onPrimaryContainer : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  _MarkupPainter({
    required this.baseImage,
    required this.strokes,
    required this.rects,
    required this.texts,
    this.activeStroke,
    this.activeRect,
  });

  final ui.Image baseImage;
  final List<_Stroke> strokes;
  final List<_RectShape> rects;
  final List<_TextLabel> texts;
  final _Stroke? activeStroke;
  final _RectShape? activeRect;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: baseImage,
      fit: BoxFit.fill,
    );

    // ── 模糊层先画：对原图的指定矩形区域用 ImageFilter.blur 单独渲染。
    // 这样后续的 stroke / rect / arrow / text 都能叠加在模糊层之上。
    void paintBlur(_RectShape r) {
      final rect = Rect.fromPoints(
        r.start,
        r.end,
      ).intersect(Rect.fromLTWH(0, 0, size.width, size.height));
      if (rect.isEmpty) return;
      // saveLayer + ImageFilter 让模糊只作用于该 rect 范围内重新绘制的图。
      canvas.saveLayer(
        rect,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      );
      // 在模糊层中再画一次原图，限定 rect 内可见。
      canvas.clipRect(rect);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: baseImage,
        fit: BoxFit.fill,
      );
      canvas.restore();
      // 模糊区域加一个低对比的描边方便定位。
      final stroke = Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(rect, stroke);
    }

    for (final r in rects) {
      if (r.tool == _MarkupTool.blur) paintBlur(r);
    }
    if (activeRect != null && activeRect!.tool == _MarkupTool.blur) {
      paintBlur(activeRect!);
    }

    void paintStroke(_Stroke s) {
      if (s.points.length < 2) return;
      final p = Paint()
        ..color = s.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.thickness;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, p);
    }

    for (final s in strokes) {
      paintStroke(s);
    }
    if (activeStroke != null) paintStroke(activeStroke!);

    void paintRect(_RectShape r) {
      final p = Paint()
        ..color = r.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.thickness;
      canvas.drawRect(Rect.fromPoints(r.start, r.end), p);
    }

    void paintArrow(_RectShape r) {
      // 直线主体。
      final p = Paint()
        ..color = r.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.thickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawLine(r.start, r.end, p);
      // 末端两条 30° 斜线。线段长度按主线长度的 22% 适配，最低 14px、最高 36px。
      final dx = r.end.dx - r.start.dx;
      final dy = r.end.dy - r.start.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 4) return;
      final headLen = math.max(14.0, math.min(36.0, len * 0.22));
      final angle = math.atan2(dy, dx);
      const spread = math.pi / 6; // 30°
      final left = Offset(
        r.end.dx - headLen * math.cos(angle - spread),
        r.end.dy - headLen * math.sin(angle - spread),
      );
      final right = Offset(
        r.end.dx - headLen * math.cos(angle + spread),
        r.end.dy - headLen * math.sin(angle + spread),
      );
      canvas.drawLine(r.end, left, p);
      canvas.drawLine(r.end, right, p);
    }

    for (final r in rects) {
      switch (r.tool) {
        case _MarkupTool.rect:
          paintRect(r);
        case _MarkupTool.arrow:
          paintArrow(r);
        case _MarkupTool.blur:
          // 模糊区域已在前一阶段绘制。
          break;
        case _MarkupTool.draw:
        case _MarkupTool.text:
          break;
      }
    }
    if (activeRect != null) {
      switch (activeRect!.tool) {
        case _MarkupTool.rect:
          paintRect(activeRect!);
        case _MarkupTool.arrow:
          paintArrow(activeRect!);
        case _MarkupTool.blur:
        case _MarkupTool.draw:
        case _MarkupTool.text:
          break;
      }
    }

    for (final t in texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(
                color: Colors.black87,
                offset: Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, t.position);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkupPainter old) =>
      old.strokes != strokes ||
      old.rects != rects ||
      old.texts != texts ||
      old.activeStroke != activeStroke ||
      old.activeRect != activeRect;
}

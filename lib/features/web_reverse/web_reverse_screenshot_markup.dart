import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../shared/ui/animated_dialog.dart';

/// 截图导出前的注释面板。支持三种笔刷：
///   - draw：自由涂鸦
///   - rect：矩形框
///   - text：文字标签（双击或点空白处插入）
/// 用户点"完成"后用 RepaintBoundary.toImage 导出 PNG 字节。
/// 取消则返回原图字节。
Future<Uint8List?> showScreenshotMarkupDialog(
  BuildContext context, {
  required Uint8List image,
}) {
  return showAnimatedDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScreenshotMarkupDialog(image: image),
  );
}

enum _MarkupTool { draw, rect, text }

class _Stroke {
  _Stroke({required this.tool, required this.color, required this.thickness});
  final _MarkupTool tool;
  final Color color;
  final double thickness;
  final List<Offset> points = <Offset>[];
}

class _RectShape {
  _RectShape({required this.color, required this.thickness});
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

  bool _isZh() =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = _isZh();
    final img = _decoded;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            _buildToolbar(theme, cs, isZh),
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.draw_rounded, size: 22, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isZh ? '截图标注' : 'Screenshot Markup',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(widget.image),
            child: Text(isZh ? '不标注直接保存' : 'Save without markup'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: Icon(
              _exporting ? Icons.hourglass_top_rounded : Icons.check_rounded,
              size: 18,
            ),
            label: Text(_exporting
                ? (isZh ? '导出中…' : 'Exporting…')
                : (isZh ? '完成' : 'Done')),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: isZh ? '取消' : 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          for (final t in const [
            (_MarkupTool.draw, Icons.edit_rounded),
            (_MarkupTool.rect, Icons.crop_square_rounded),
            (_MarkupTool.text, Icons.text_fields_rounded),
          ]) ...[
            _ToolButton(
              icon: t.$2,
              active: _tool == t.$1,
              onTap: () => setState(() => _tool = t.$1),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          // 颜色选择
          for (final c in const [
            Colors.redAccent,
            Colors.amber,
            Colors.lightGreenAccent,
            Colors.cyanAccent,
            Colors.white,
          ]) ...[
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == c ? cs.primary : cs.outlineVariant,
                    width: _color == c ? 2.4 : 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Row(
              children: [
                Icon(Icons.line_weight_rounded,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
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
            tooltip: isZh ? '撤销' : 'Undo',
            onPressed: _undo,
            icon: const Icon(Icons.undo_rounded, size: 18),
          ),
          IconButton(
            tooltip: isZh ? '清空' : 'Clear',
            onPressed: () => setState(() {
              _strokes.clear();
              _rects.clear();
              _texts.clear();
            }),
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
          ),
        ],
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
      final s = _Stroke(
        tool: _tool,
        color: _color,
        thickness: _thickness,
      )..points.add(d.localPosition);
      setState(() => _activeStroke = s);
    } else if (_tool == _MarkupTool.rect) {
      final r = _RectShape(color: _color, thickness: _thickness)
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
    final isZh = _isZh();
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isZh ? '添加文字注释' : 'Add text label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: isZh ? '输入标注文字' : 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text.trim()),
            child: Text(isZh ? '添加' : 'Add'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _texts.add(_TextLabel(position: position, text: text, color: _color));
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final boundary = _boundary.currentContext?.findRenderObject()
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
      color: active ? cs.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: active ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
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

    for (final r in rects) {
      paintRect(r);
    }
    if (activeRect != null) paintRect(activeRect!);
    for (final t in texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            shadows: const [
              Shadow(color: Colors.black87, offset: Offset(1, 1), blurRadius: 2),
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

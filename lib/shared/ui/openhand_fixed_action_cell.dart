import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 将内容最右侧的操作单元格固定在视口右侧，保留原有行高及按钮状态。
class OpenHandFixedActionCell extends SingleChildRenderObjectWidget {
  const OpenHandFixedActionCell({
    super.key,
    required this.controller,
    required this.viewportWidth,
    required this.contentWidth,
    required this.backgroundColor,
    required this.borderColor,
    required super.child,
  });

  final ScrollController controller;
  final double viewportWidth;
  final double contentWidth;
  final Color backgroundColor;
  final Color borderColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFixedActionCell(
        controller,
        viewportWidth,
        contentWidth,
        backgroundColor,
        borderColor,
        Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderFixedActionCell).configure(
      controller: controller,
      viewportWidth: viewportWidth,
      contentWidth: contentWidth,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      direction: Directionality.of(context),
    );
  }
}

class _RenderFixedActionCell extends RenderProxyBox {
  _RenderFixedActionCell(
    this._controller,
    this._viewportWidth,
    this._contentWidth,
    this._backgroundColor,
    this._borderColor,
    this._direction,
  );

  ScrollController _controller;
  double _viewportWidth;
  double _contentWidth;
  Color _backgroundColor;
  Color _borderColor;
  TextDirection _direction;

  void configure({
    required ScrollController controller,
    required double viewportWidth,
    required double contentWidth,
    required Color backgroundColor,
    required Color borderColor,
    required TextDirection direction,
  }) {
    if (_controller != controller) {
      if (attached) _controller.removeListener(_onScroll);
      _controller = controller;
      if (attached) _controller.addListener(_onScroll);
    }
    _viewportWidth = viewportWidth;
    _contentWidth = contentWidth;
    _backgroundColor = backgroundColor;
    _borderColor = borderColor;
    _direction = direction;
    _onScroll();
  }

  // 绘制时读取真实偏移，窗口缩放时的静默滚动修正也能立即保持对齐。
  Offset get _translation {
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    final rtl = _controller.hasClients
        ? _controller.position.axisDirection == AxisDirection.left
        : _direction == TextDirection.rtl;
    return Offset(rtl ? -offset : offset + _viewportWidth - _contentWidth, 0);
  }

  void _onScroll() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onScroll);
  }

  @override
  void detach() {
    _controller.removeListener(_onScroll);
    super.detach();
  }

  @override
  Rect get paintBounds => super.paintBounds.shift(_translation);

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + _translation;
    final rect = origin & size;
    context.canvas.drawRect(rect, Paint()..color = _backgroundColor);
    context.canvas.drawLine(
      rect.topLeft,
      rect.bottomLeft,
      Paint()
        ..color = _borderColor
        ..strokeWidth = 0.7,
    );
    if (child != null) context.paintChild(child!, origin);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final translation = _translation;
    if (!size.contains(position - translation)) return false;
    if (child != null) {
      result.addWithPaintOffset(
        offset: translation,
        position: position,
        hitTest: (result, position) =>
            child!.hitTest(result, position: position),
      );
    }
    // 固定列的空白区域也应阻挡被遮住的数据控件。
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _translation;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}

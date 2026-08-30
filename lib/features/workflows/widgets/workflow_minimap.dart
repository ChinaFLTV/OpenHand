import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/ui/openhand_spacing.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_auto_layout.dart';

const double _contentPadding = 10;

class WorkflowMiniMap extends StatefulWidget {
  const WorkflowMiniMap({
    super.key,
    required this.nodes,
    required this.connections,
    this.canvasSize,
    this.viewportRect,
    this.selectedNodeId,
    this.onNavigate,
    this.onZoomFactor,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final Size? canvasSize;
  final Rect? viewportRect;
  final String? selectedNodeId;
  final ValueChanged<Offset>? onNavigate;
  final ValueChanged<double>? onZoomFactor;

  @override
  State<WorkflowMiniMap> createState() => _WorkflowMiniMapState();
}

class _WorkflowMiniMapState extends State<WorkflowMiniMap> {
  Offset _dragAnchor = Offset.zero;
  double _previousGestureScale = 1;

  bool get _interactive =>
      widget.onNavigate != null || widget.onZoomFactor != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final worldBounds = _worldBounds(widget.nodes, widget.canvasSize);
    return Semantics(
      label: _interactive ? '工作流缩略导航图' : '工作流全貌缩略图',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(color: colors.outlineVariant),
          boxShadow: _interactive
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: kOpenHandBorderRadius14,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final geometry = _MiniMapGeometry(size, worldBounds);
              final content = Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _WorkflowMiniMapGraphPainter(
                        nodes: widget.nodes,
                        connections: widget.connections,
                        selectedNodeId: widget.selectedNodeId,
                        geometry: geometry,
                        colors: colors,
                      ),
                    ),
                  ),
                  if (widget.viewportRect case final viewport?)
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _WorkflowMiniMapViewportPainter(
                          viewportRect: viewport,
                          geometry: geometry,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  if (widget.nodes.isEmpty)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_tree_outlined,
                            size: 17,
                            color: colors.onSurfaceVariant,
                          ),
                          kOpenHandHGap6,
                          Text(
                            '尚未添加节点',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              );
              return MouseRegion(
                cursor: _interactive
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                child: IgnorePointer(
                  ignoring: !_interactive,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent ||
                          widget.onZoomFactor == null) {
                        return;
                      }
                      widget.onZoomFactor!(
                        math.exp(-event.scrollDelta.dy / 600),
                      );
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: widget.onNavigate == null
                          ? null
                          : (details) => widget.onNavigate!(
                              geometry.localToCanvas(details.localPosition),
                            ),
                      onScaleStart: _interactive
                          ? (details) {
                              _previousGestureScale = 1;
                              final canvasPoint = geometry.localToCanvas(
                                details.localFocalPoint,
                              );
                              final viewport = widget.viewportRect;
                              _dragAnchor =
                                  viewport != null &&
                                      viewport.contains(canvasPoint)
                                  ? canvasPoint - viewport.center
                                  : Offset.zero;
                            }
                          : null,
                      onScaleUpdate: _interactive
                          ? (details) {
                              final navigate = widget.onNavigate;
                              if (navigate != null) {
                                navigate(
                                  geometry.localToCanvas(
                                        details.localFocalPoint,
                                      ) -
                                      _dragAnchor,
                                );
                              }
                              final zoom = widget.onZoomFactor;
                              if (zoom != null &&
                                  details.scale != _previousGestureScale) {
                                zoom(details.scale / _previousGestureScale);
                                _previousGestureScale = details.scale;
                              }
                            }
                          : null,
                      child: content,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkflowMiniMapGraphPainter extends CustomPainter {
  const _WorkflowMiniMapGraphPainter({
    required this.nodes,
    required this.connections,
    required this.selectedNodeId,
    required this.geometry,
    required this.colors,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final String? selectedNodeId;
  final _MiniMapGeometry geometry;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final nodesById = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    final connectionPaint = Paint()
      ..color = colors.outline.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    for (final connection in connections) {
      final source = nodesById[connection.sourceNodeId];
      final target = nodesById[connection.targetNodeId];
      if (source == null || target == null) continue;
      final sourceRect = geometry.canvasRectToLocal(_nodeBounds(source));
      final targetRect = geometry.canvasRectToLocal(_nodeBounds(target));
      final start = sourceRect.centerRight;
      final end = targetRect.centerLeft;
      final controlDistance = math.max(8.0, (end.dx - start.dx).abs() * 0.42);
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + controlDistance,
            start.dy,
            end.dx - controlDistance,
            end.dy,
            end.dx,
            end.dy,
          ),
        connectionPaint,
      );
    }

    for (final node in nodes.where((item) => item.isContainer)) {
      _paintNode(canvas, node);
    }
    for (final node in nodes.where((item) => !item.isContainer)) {
      _paintNode(canvas, node);
    }
  }

  void _paintNode(Canvas canvas, WorkflowNode node) {
    var rect = geometry.canvasRectToLocal(_nodeBounds(node));
    if (!node.isContainer) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: math.max(5, rect.width),
        height: math.max(4, rect.height),
      );
    }
    final radius = Radius.circular(math.min(3.5, rect.shortestSide / 3));
    final selected = node.id == selectedNodeId;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = node.isContainer
            ? _nodeColor(node.kind, colors).withValues(alpha: 0.18)
            : _nodeColor(node.kind, colors).withValues(alpha: 0.86)
        ..style = PaintingStyle.fill,
    );
    if (node.isContainer || selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..color = selected
              ? colors.primary
              : _nodeColor(node.kind, colors).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WorkflowMiniMapGraphPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.connections != connections ||
      oldDelegate.selectedNodeId != selectedNodeId ||
      oldDelegate.geometry != geometry ||
      oldDelegate.colors != colors;
}

class _WorkflowMiniMapViewportPainter extends CustomPainter {
  const _WorkflowMiniMapViewportPainter({
    required this.viewportRect,
    required this.geometry,
    required this.color,
  });

  final Rect viewportRect;
  final _MiniMapGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewportRect.isEmpty) return;
    final visibleRect = geometry
        .canvasRectToLocal(viewportRect)
        .intersect(geometry.plotRect);
    if (visibleRect.isEmpty) return;
    final shape = RRect.fromRectAndRadius(
      visibleRect,
      const Radius.circular(3),
    );
    canvas.drawRRect(shape, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(
      shape,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _WorkflowMiniMapViewportPainter oldDelegate) =>
      oldDelegate.viewportRect != viewportRect ||
      oldDelegate.geometry != geometry ||
      oldDelegate.color != color;
}

class _MiniMapGeometry {
  const _MiniMapGeometry(this.size, this.worldBounds);

  final Size size;
  final Rect worldBounds;

  double get scale => math.min(
    math.max(1, size.width - _contentPadding * 2) / worldBounds.width,
    math.max(1, size.height - _contentPadding * 2) / worldBounds.height,
  );

  Rect get plotRect {
    final fittedSize = Size(
      worldBounds.width * scale,
      worldBounds.height * scale,
    );
    return Alignment.center.inscribe(fittedSize, Offset.zero & size);
  }

  Rect canvasRectToLocal(Rect rect) => Rect.fromLTWH(
    plotRect.left + (rect.left - worldBounds.left) * scale,
    plotRect.top + (rect.top - worldBounds.top) * scale,
    rect.width * scale,
    rect.height * scale,
  );

  Offset localToCanvas(Offset point) {
    final plot = plotRect;
    final bounded = Offset(
      point.dx.clamp(plot.left, plot.right),
      point.dy.clamp(plot.top, plot.bottom),
    );
    return Offset(
      worldBounds.left + (bounded.dx - plot.left) / scale,
      worldBounds.top + (bounded.dy - plot.top) / scale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _MiniMapGeometry &&
      other.size == size &&
      other.worldBounds == worldBounds;

  @override
  int get hashCode => Object.hash(size, worldBounds);
}

Rect _worldBounds(List<WorkflowNode> nodes, Size? canvasSize) {
  if (canvasSize != null &&
      canvasSize.width.isFinite &&
      canvasSize.height.isFinite &&
      canvasSize.width > 0 &&
      canvasSize.height > 0) {
    return Offset.zero & canvasSize;
  }
  if (nodes.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
  var bounds = _nodeBounds(nodes.first);
  for (final node in nodes.skip(1)) {
    bounds = bounds.expandToInclude(_nodeBounds(node));
  }
  final padding = math.max(56.0, math.max(bounds.width, bounds.height) * 0.08);
  return bounds.inflate(padding);
}

Rect _nodeBounds(WorkflowNode node) => Rect.fromLTWH(
  node.x,
  node.y,
  node.isContainer
      ? math.max(
          kWorkflowContainerMinWidth,
          node.doubleSetting(
            WorkflowSettingKeys.containerWidth,
            kWorkflowContainerMinWidth,
          ),
        )
      : kWorkflowNodeWidth,
  node.isContainer
      ? math.max(
          kWorkflowContainerMinHeight,
          node.doubleSetting(
            WorkflowSettingKeys.containerHeight,
            kWorkflowContainerMinHeight,
          ),
        )
      : kWorkflowNodeHeight,
);

Color _nodeColor(WorkflowNodeKind kind, ColorScheme colors) => switch (kind) {
  WorkflowNodeKind.start => colors.primary,
  WorkflowNodeKind.end => colors.tertiary,
  WorkflowNodeKind.condition ||
  WorkflowNodeKind.humanIntervention => colors.secondary,
  WorkflowNodeKind.loop || WorkflowNodeKind.iteration => colors.tertiary,
  WorkflowNodeKind.loopExit => colors.error,
  WorkflowNodeKind.llm => colors.primary,
  WorkflowNodeKind.httpRequest => colors.secondary,
  WorkflowNodeKind.parameterAssignment ||
  WorkflowNodeKind.listOperation ||
  WorkflowNodeKind.codeExecution => colors.primary,
};

import 'dart:math' as math;

import '../model/workflow_definition.dart';

const double kWorkflowCanvasWidth = 2400;
const double kWorkflowCanvasHeight = 1600;
const double kWorkflowNodeWidth = 246;
const double kWorkflowNodeHeight = 130;
const double kWorkflowContainerMinWidth = 360;
const double kWorkflowContainerMinHeight = 196;
const double kWorkflowContainerChildLeft = 132;
const double kWorkflowContainerChildTop = 96;
const double kWorkflowContainerPadding = 34;
const double _workflowAnnotationCanvasPadding = 16;
const double _workflowAnnotationLayoutGap = 24;
const double _workflowConnectionStrokeClearance = 4;
const int _workflowAnnotationPlacementAttempts = 32;
const int _workflowConnectionCurveSegments = 24;

typedef WorkflowNodeSizeResolver =
    ({double width, double height}) Function(WorkflowNode node);

class WorkflowAutoLayoutConfig {
  const WorkflowAutoLayoutConfig({
    this.canvasWidth = kWorkflowCanvasWidth,
    this.canvasHeight = kWorkflowCanvasHeight,
    this.canvasPadding = 48,
    this.horizontalGap = 110,
    this.verticalGap = 64,
    this.minimumHorizontalGap = 42,
    this.minimumVerticalGap = 28,
    this.containerChildLeft = kWorkflowContainerChildLeft,
    this.containerChildTop = kWorkflowContainerChildTop,
    this.containerPadding = kWorkflowContainerPadding,
    this.containerMinWidth = kWorkflowContainerMinWidth,
    this.containerMinHeight = kWorkflowContainerMinHeight,
  });

  final double canvasWidth;
  final double canvasHeight;
  final double canvasPadding;
  final double horizontalGap;
  final double verticalGap;
  final double minimumHorizontalGap;
  final double minimumVerticalGap;
  final double containerChildLeft;
  final double containerChildTop;
  final double containerPadding;
  final double containerMinWidth;
  final double containerMinHeight;
}

class WorkflowAutoLayoutResult {
  const WorkflowAutoLayoutResult({
    required this.nodes,
    required this.annotations,
    required this.fitsCanvas,
    required this.changed,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final List<WorkflowNode> nodes;
  final List<WorkflowAnnotation> annotations;
  final bool fitsCanvas;
  final bool changed;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

WorkflowAutoLayoutResult arrangeWorkflowNodes({
  required List<WorkflowNode> nodes,
  required List<WorkflowConnection> connections,
  required WorkflowNodeSizeResolver sizeOf,
  List<WorkflowAnnotation> annotations = const <WorkflowAnnotation>[],
  WorkflowAutoLayoutConfig config = const WorkflowAutoLayoutConfig(),
}) {
  if (nodes.isEmpty) {
    return WorkflowAutoLayoutResult(
      nodes: <WorkflowNode>[],
      annotations: List<WorkflowAnnotation>.unmodifiable(annotations),
      fitsCanvas: true,
      changed: false,
      left: 0,
      top: 0,
      right: 0,
      bottom: 0,
    );
  }

  final working = <String, WorkflowNode>{
    for (final node in nodes) node.id: node,
  };
  final childLayouts = <String, _ScopeLayout>{};
  var fitsCanvas = true;
  for (final container in nodes.where((node) => node.isContainer)) {
    final children = nodes
        .where((node) => node.parentNodeId == container.id)
        .toList(growable: false);
    if (children.isEmpty) continue;
    final childIds = children.map((node) => node.id).toSet();
    final childEdges = connections
        .where(
          (edge) =>
              childIds.contains(edge.sourceNodeId) &&
              childIds.contains(edge.targetNodeId),
        )
        .toList(growable: false);
    final preferredRoots = connections
        .where(
          (edge) =>
              edge.sourceNodeId == container.id &&
              edge.sourceHandleId == workflowContainerStartHandleId &&
              childIds.contains(edge.targetNodeId),
        )
        .map((edge) => edge.targetNodeId)
        .toList(growable: false);
    final layout = _layoutScope(
      children,
      childEdges,
      sizeOf,
      preferredRoots: preferredRoots,
      availableWidth:
          config.canvasWidth -
          config.canvasPadding * 2 -
          config.containerChildLeft -
          config.containerPadding,
      availableHeight:
          config.canvasHeight -
          config.canvasPadding * 2 -
          config.containerChildTop -
          config.containerPadding,
      config: config,
    );
    childLayouts[container.id] = layout;
    fitsCanvas = fitsCanvas && layout.fits;
    final width = math.max(
      config.containerMinWidth,
      config.containerChildLeft + layout.width + config.containerPadding,
    );
    final height = math.max(
      config.containerMinHeight,
      config.containerChildTop + layout.height + config.containerPadding,
    );
    working[container.id] = container.copyWith(
      settings: Map<String, Object?>.unmodifiable(<String, Object?>{
        ...container.settings,
        WorkflowSettingKeys.containerWidth: width,
        WorkflowSettingKeys.containerHeight: height,
      }),
    );
  }

  final rootNodes = nodes
      .where((node) => node.parentNodeId == null)
      .map((node) => working[node.id]!)
      .toList(growable: false);
  final rootIds = rootNodes.map((node) => node.id).toSet();
  final rootEdges = connections
      .where(
        (edge) =>
            rootIds.contains(edge.sourceNodeId) &&
            rootIds.contains(edge.targetNodeId) &&
            edge.sourceHandleId != workflowContainerStartHandleId,
      )
      .toList(growable: false);
  final preferredRoots = <String>[
    ...rootNodes
        .where((node) => node.kind == WorkflowNodeKind.start)
        .map((node) => node.id),
  ];
  final rootLayout = _layoutScope(
    rootNodes,
    rootEdges,
    sizeOf,
    preferredRoots: preferredRoots,
    availableWidth: config.canvasWidth - config.canvasPadding * 2,
    availableHeight: config.canvasHeight - config.canvasPadding * 2,
    config: config,
  );
  fitsCanvas = fitsCanvas && rootLayout.fits;

  for (final node in rootNodes) {
    final position = rootLayout.positions[node.id]!;
    working[node.id] = node.copyWith(
      x: config.canvasPadding + position.x,
      y: config.canvasPadding + position.y,
    );
  }
  for (final entry in childLayouts.entries) {
    final parent = working[entry.key]!;
    for (final position in entry.value.positions.entries) {
      final child = working[position.key]!;
      working[position.key] = child.copyWith(
        x: parent.x + config.containerChildLeft + position.value.x,
        y: parent.y + config.containerChildTop + position.value.y,
      );
    }
  }

  final arranged = nodes
      .map((node) => working[node.id]!)
      .toList(growable: false);
  final annotationLayout = _arrangeWorkflowAnnotations(
    annotations: annotations,
    arrangedNodes: arranged,
    connections: connections,
    sizeOf: sizeOf,
    config: config,
  );
  final arrangedAnnotations = annotationLayout.annotations;
  fitsCanvas = fitsCanvas && annotationLayout.fits;
  var changed = false;
  for (var index = 0; index < nodes.length; index++) {
    final before = nodes[index];
    final after = arranged[index];
    if ((before.x - after.x).abs() > 0.01 ||
        (before.y - after.y).abs() > 0.01 ||
        before.settings[WorkflowSettingKeys.containerWidth] !=
            after.settings[WorkflowSettingKeys.containerWidth] ||
        before.settings[WorkflowSettingKeys.containerHeight] !=
            after.settings[WorkflowSettingKeys.containerHeight]) {
      changed = true;
      break;
    }
  }

  if (!changed) {
    for (var index = 0; index < annotations.length; index++) {
      final before = annotations[index];
      final after = arrangedAnnotations[index];
      if ((before.x - after.x).abs() > 0.01 ||
          (before.y - after.y).abs() > 0.01) {
        changed = true;
        break;
      }
    }
  }

  var left = config.canvasPadding;
  var top = config.canvasPadding;
  var right = left + rootLayout.width;
  var bottom = top + rootLayout.height;
  for (final annotation in arrangedAnnotations) {
    left = math.min(left, annotation.x);
    top = math.min(top, annotation.y);
    right = math.max(right, annotation.x + annotation.width);
    bottom = math.max(bottom, annotation.y + annotation.height);
  }
  fitsCanvas =
      fitsCanvas &&
      left >= -0.01 &&
      top >= -0.01 &&
      right <= config.canvasWidth + 0.01 &&
      bottom <= config.canvasHeight + 0.01;
  return WorkflowAutoLayoutResult(
    nodes: List<WorkflowNode>.unmodifiable(arranged),
    annotations: List<WorkflowAnnotation>.unmodifiable(arrangedAnnotations),
    fitsCanvas: fitsCanvas,
    changed: changed,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

({List<WorkflowAnnotation> annotations, bool fits})
_arrangeWorkflowAnnotations({
  required List<WorkflowAnnotation> annotations,
  required List<WorkflowNode> arrangedNodes,
  required List<WorkflowConnection> connections,
  required WorkflowNodeSizeResolver sizeOf,
  required WorkflowAutoLayoutConfig config,
}) {
  if (annotations.isEmpty) {
    return (annotations: annotations, fits: true);
  }
  final nodeBounds = <_WorkflowLayoutRect>[
    for (final node in arrangedNodes)
      _WorkflowLayoutRect(
        x: node.x,
        y: node.y,
        width: sizeOf(node).width,
        height: sizeOf(node).height,
      ),
  ];
  final occupied = List<_WorkflowLayoutRect>.of(nodeBounds);
  final connectionsToAvoid = _workflowConnectionSegments(
    connections,
    arrangedNodes,
    sizeOf,
  );
  final preserved = <String, WorkflowAnnotation>{};
  for (final annotation in annotations) {
    final position = _clampAnnotationPosition(
      annotation,
      annotation.x,
      annotation.y,
      config,
    );
    final bounds = _WorkflowLayoutRect(
      x: position.x,
      y: position.y,
      width: annotation.width,
      height: annotation.height,
    );
    if (_firstStaticAnnotationObstacle(
          bounds,
          nodeBounds,
          connectionsToAvoid,
        ) !=
        null) {
      continue;
    }
    final unchanged = annotation.copyWith(x: position.x, y: position.y);
    preserved[annotation.id] = unchanged;
    occupied.add(bounds);
  }

  final arrangedAnnotations = <WorkflowAnnotation>[];
  for (final annotation in annotations) {
    final unchanged = preserved[annotation.id];
    if (unchanged != null) {
      arrangedAnnotations.add(unchanged);
      continue;
    }
    final position = _findAvailableAnnotationPosition(
      annotation: annotation,
      x: annotation.x,
      y: annotation.y,
      occupied: occupied,
      connections: connectionsToAvoid,
      config: config,
    );
    if (position == null) return (annotations: annotations, fits: false);
    final arranged = annotation.copyWith(x: position.x, y: position.y);
    arrangedAnnotations.add(arranged);
    occupied.add(
      _WorkflowLayoutRect(
        x: arranged.x,
        y: arranged.y,
        width: arranged.width,
        height: arranged.height,
      ),
    );
  }
  return (annotations: arrangedAnnotations, fits: true);
}

({double x, double y})? _findAvailableAnnotationPosition({
  required WorkflowAnnotation annotation,
  required double x,
  required double y,
  required List<_WorkflowLayoutRect> occupied,
  required List<_WorkflowConnectionSegment> connections,
  required WorkflowAutoLayoutConfig config,
}) {
  final preferred = _clampAnnotationPosition(annotation, x, y, config);
  var candidate = preferred;
  final visited = <String>{_annotationPositionKey(candidate)};
  for (
    var attempt = 0;
    attempt < _workflowAnnotationPlacementAttempts;
    attempt++
  ) {
    final bounds = _WorkflowLayoutRect(
      x: candidate.x,
      y: candidate.y,
      width: annotation.width,
      height: annotation.height,
    );
    final obstacle = _firstAnnotationObstacle(bounds, occupied, connections);
    if (obstacle == null) return candidate;
    final alternatives = <({double x, double y})>[
      (
        x: candidate.x,
        y: obstacle.y - annotation.height - _workflowAnnotationLayoutGap,
      ),
      (x: candidate.x, y: obstacle.bottom + _workflowAnnotationLayoutGap),
      (
        x: obstacle.x - annotation.width - _workflowAnnotationLayoutGap,
        y: candidate.y,
      ),
      (x: obstacle.right + _workflowAnnotationLayoutGap, y: candidate.y),
      (
        x: obstacle.x - annotation.width - _workflowAnnotationLayoutGap,
        y: obstacle.y - annotation.height - _workflowAnnotationLayoutGap,
      ),
      (
        x: obstacle.right + _workflowAnnotationLayoutGap,
        y: obstacle.y - annotation.height - _workflowAnnotationLayoutGap,
      ),
      (
        x: obstacle.x - annotation.width - _workflowAnnotationLayoutGap,
        y: obstacle.bottom + _workflowAnnotationLayoutGap,
      ),
      (
        x: obstacle.right + _workflowAnnotationLayoutGap,
        y: obstacle.bottom + _workflowAnnotationLayoutGap,
      ),
    ];
    final considered = <String>{};
    ({double x, double y})? next;
    for (final alternative in alternatives) {
      final clamped = _clampAnnotationPosition(
        annotation,
        alternative.x,
        alternative.y,
        config,
      );
      final key = _annotationPositionKey(clamped);
      if (visited.contains(key) || !considered.add(key)) continue;
      if (next == null ||
          _annotationPositionDistanceSquared(clamped, preferred) <
              _annotationPositionDistanceSquared(next, preferred)) {
        next = clamped;
      }
    }
    if (next == null) return null;
    candidate = next;
    visited.add(_annotationPositionKey(candidate));
  }
  return null;
}

({double x, double y}) _clampAnnotationPosition(
  WorkflowAnnotation annotation,
  double x,
  double y,
  WorkflowAutoLayoutConfig config,
) => (
  x: _clampAnnotationCoordinate(
    x.isFinite ? x : _workflowAnnotationCanvasPadding,
    annotation.width,
    config.canvasWidth,
  ),
  y: _clampAnnotationCoordinate(
    y.isFinite ? y : _workflowAnnotationCanvasPadding,
    annotation.height,
    config.canvasHeight,
  ),
);

_WorkflowLayoutRect? _firstStaticAnnotationObstacle(
  _WorkflowLayoutRect bounds,
  List<_WorkflowLayoutRect> occupied,
  List<_WorkflowConnectionSegment> connections,
) {
  for (final item in occupied) {
    if (bounds.overlaps(item, gap: 0)) return item;
  }
  for (final connection in connections) {
    final obstacle = connection.obstacleFor(
      bounds,
      clearance: _workflowConnectionStrokeClearance,
    );
    if (obstacle != null) return obstacle;
  }
  return null;
}

_WorkflowLayoutRect? _firstAnnotationObstacle(
  _WorkflowLayoutRect bounds,
  List<_WorkflowLayoutRect> occupied,
  List<_WorkflowConnectionSegment> connections,
) {
  for (final item in occupied) {
    if (bounds.overlaps(item, gap: _workflowAnnotationLayoutGap)) return item;
  }
  for (final connection in connections) {
    final obstacle = connection.obstacleFor(
      bounds,
      clearance: _workflowAnnotationLayoutGap,
    );
    if (obstacle != null) return obstacle;
  }
  return null;
}

double _annotationPositionDistanceSquared(
  ({double x, double y}) left,
  ({double x, double y}) right,
) {
  final horizontal = left.x - right.x;
  final vertical = left.y - right.y;
  return horizontal * horizontal + vertical * vertical;
}

String _annotationPositionKey(({double x, double y}) position) =>
    '${position.x.round()}:${position.y.round()}';

double _clampAnnotationCoordinate(
  double value,
  double size,
  double canvasSize,
) {
  final maximum = math.max(
    _workflowAnnotationCanvasPadding,
    canvasSize - size - _workflowAnnotationCanvasPadding,
  );
  return value.clamp(_workflowAnnotationCanvasPadding, maximum);
}

class _WorkflowLayoutRect {
  const _WorkflowLayoutRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool overlaps(_WorkflowLayoutRect other, {required double gap}) =>
      x - gap < other.right &&
      right + gap > other.x &&
      y - gap < other.bottom &&
      bottom + gap > other.y;
}

List<_WorkflowConnectionSegment> _workflowConnectionSegments(
  List<WorkflowConnection> connections,
  List<WorkflowNode> nodes,
  WorkflowNodeSizeResolver sizeOf,
) {
  final nodesById = <String, WorkflowNode>{
    for (final node in nodes) node.id: node,
  };
  final segments = <_WorkflowConnectionSegment>[];
  for (final connection in connections) {
    final source = nodesById[connection.sourceNodeId];
    final target = nodesById[connection.targetNodeId];
    if (source == null || target == null) continue;
    final sourceSize = sizeOf(source);
    final targetSize = sizeOf(target);
    final start = (
      x: source.x + sourceSize.width,
      y: source.y + sourceSize.height / 2,
    );
    final end = (x: target.x, y: target.y + targetSize.height / 2);
    final distance = math.max(70, (end.x - start.x).abs() * 0.46);
    var previous = start;
    for (var index = 1; index <= _workflowConnectionCurveSegments; index++) {
      final point = _cubicConnectionPoint(
        start: start,
        firstControl: (x: start.x + distance, y: start.y),
        secondControl: (x: end.x - distance, y: end.y),
        end: end,
        t: index / _workflowConnectionCurveSegments,
      );
      segments.add(
        _WorkflowConnectionSegment(
          startX: previous.x,
          startY: previous.y,
          endX: point.x,
          endY: point.y,
        ),
      );
      previous = point;
    }
  }
  return segments;
}

({double x, double y}) _cubicConnectionPoint({
  required ({double x, double y}) start,
  required ({double x, double y}) firstControl,
  required ({double x, double y}) secondControl,
  required ({double x, double y}) end,
  required double t,
}) {
  final inverse = 1 - t;
  return (
    x:
        inverse * inverse * inverse * start.x +
        3 * inverse * inverse * t * firstControl.x +
        3 * inverse * t * t * secondControl.x +
        t * t * t * end.x,
    y:
        inverse * inverse * inverse * start.y +
        3 * inverse * inverse * t * firstControl.y +
        3 * inverse * t * t * secondControl.y +
        t * t * t * end.y,
  );
}

class _WorkflowConnectionSegment {
  const _WorkflowConnectionSegment({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  final double startX;
  final double startY;
  final double endX;
  final double endY;

  _WorkflowLayoutRect? obstacleFor(
    _WorkflowLayoutRect bounds, {
    required double clearance,
  }) {
    final expanded = _WorkflowLayoutRect(
      x: bounds.x - clearance,
      y: bounds.y - clearance,
      width: bounds.width + clearance * 2,
      height: bounds.height + clearance * 2,
    );
    if (!_intersects(expanded)) return null;
    return _WorkflowLayoutRect(
      x: math.min(startX, endX),
      y: math.min(startY, endY),
      width: (startX - endX).abs(),
      height: (startY - endY).abs(),
    );
  }

  bool _intersects(_WorkflowLayoutRect bounds) {
    if (_contains(bounds, startX, startY) || _contains(bounds, endX, endY)) {
      return true;
    }
    return _segmentsIntersect(
          startX,
          startY,
          endX,
          endY,
          bounds.x,
          bounds.y,
          bounds.right,
          bounds.y,
        ) ||
        _segmentsIntersect(
          startX,
          startY,
          endX,
          endY,
          bounds.right,
          bounds.y,
          bounds.right,
          bounds.bottom,
        ) ||
        _segmentsIntersect(
          startX,
          startY,
          endX,
          endY,
          bounds.right,
          bounds.bottom,
          bounds.x,
          bounds.bottom,
        ) ||
        _segmentsIntersect(
          startX,
          startY,
          endX,
          endY,
          bounds.x,
          bounds.bottom,
          bounds.x,
          bounds.y,
        );
  }
}

bool _contains(_WorkflowLayoutRect bounds, double x, double y) =>
    x >= bounds.x && x <= bounds.right && y >= bounds.y && y <= bounds.bottom;

bool _segmentsIntersect(
  double firstStartX,
  double firstStartY,
  double firstEndX,
  double firstEndY,
  double secondStartX,
  double secondStartY,
  double secondEndX,
  double secondEndY,
) {
  final firstDeltaX = firstEndX - firstStartX;
  final firstDeltaY = firstEndY - firstStartY;
  final secondDeltaX = secondEndX - secondStartX;
  final secondDeltaY = secondEndY - secondStartY;
  final denominator = firstDeltaX * secondDeltaY - firstDeltaY * secondDeltaX;
  if (denominator.abs() < 0.000001) return false;
  final deltaX = secondStartX - firstStartX;
  final deltaY = secondStartY - firstStartY;
  final firstFactor =
      (deltaX * secondDeltaY - deltaY * secondDeltaX) / denominator;
  final secondFactor =
      (deltaX * firstDeltaY - deltaY * firstDeltaX) / denominator;
  return firstFactor >= 0 &&
      firstFactor <= 1 &&
      secondFactor >= 0 &&
      secondFactor <= 1;
}

class _ScopeLayout {
  const _ScopeLayout({
    required this.positions,
    required this.width,
    required this.height,
    required this.fits,
  });

  final Map<String, ({double x, double y})> positions;
  final double width;
  final double height;
  final bool fits;
}

_ScopeLayout _layoutScope(
  List<WorkflowNode> nodes,
  List<WorkflowConnection> edges,
  WorkflowNodeSizeResolver sizeOf, {
  required List<String> preferredRoots,
  required double availableWidth,
  required double availableHeight,
  required WorkflowAutoLayoutConfig config,
}) {
  if (nodes.isEmpty) {
    return const _ScopeLayout(
      positions: <String, ({double x, double y})>{},
      width: 0,
      height: 0,
      fits: true,
    );
  }
  final nodesById = <String, WorkflowNode>{
    for (final node in nodes) node.id: node,
  };
  final validEdges = edges
      .where(
        (edge) =>
            nodesById.containsKey(edge.sourceNodeId) &&
            nodesById.containsKey(edge.targetNodeId) &&
            edge.sourceNodeId != edge.targetNodeId,
      )
      .toList(growable: false);
  final outgoing = <String, List<WorkflowConnection>>{
    for (final node in nodes) node.id: <WorkflowConnection>[],
  };
  final incoming = <String, int>{for (final node in nodes) node.id: 0};
  for (final edge in validEdges) {
    outgoing[edge.sourceNodeId]!.add(edge);
    incoming[edge.targetNodeId] = incoming[edge.targetNodeId]! + 1;
  }
  for (final entry in outgoing.entries) {
    final source = nodesById[entry.key]!;
    final indexed = entry.value.indexed.toList(growable: false);
    indexed.sort((left, right) {
      final priority = _branchPriority(
        source,
        left.$2.sourceHandleId,
      ).compareTo(_branchPriority(source, right.$2.sourceHandleId));
      return priority != 0 ? priority : left.$1.compareTo(right.$1);
    });
    outgoing[entry.key] = indexed
        .map((item) => item.$2)
        .toList(growable: false);
  }

  final spatialOrder = nodes.toList(growable: false)
    ..sort((left, right) {
      final y = left.y.compareTo(right.y);
      if (y != 0) return y;
      final x = left.x.compareTo(right.x);
      return x != 0 ? x : left.id.compareTo(right.id);
    });
  final traversalOrder = <String>[];
  final visited = <String>{};
  void visit(String nodeId) {
    if (!nodesById.containsKey(nodeId) || !visited.add(nodeId)) return;
    traversalOrder.add(nodeId);
    for (final edge in outgoing[nodeId]!) {
      visit(edge.targetNodeId);
    }
  }

  for (final id in preferredRoots) {
    visit(id);
  }
  for (final node in spatialOrder.where((node) => incoming[node.id] == 0)) {
    visit(node.id);
  }
  for (final node in spatialOrder) {
    visit(node.id);
  }
  final rank = <String, int>{
    for (final entry in traversalOrder.indexed) entry.$2: entry.$1,
  };

  final remainingIncoming = Map<String, int>.of(incoming);
  final ready =
      nodes
          .where((node) => remainingIncoming[node.id] == 0)
          .map((node) => node.id)
          .toList(growable: true)
        ..sort((left, right) => rank[left]!.compareTo(rank[right]!));
  final layers = <String, int>{for (final id in ready) id: 0};
  final sorted = <String>[];
  while (ready.isNotEmpty) {
    final nodeId = ready.removeAt(0);
    sorted.add(nodeId);
    for (final edge in outgoing[nodeId]!) {
      final targetId = edge.targetNodeId;
      layers[targetId] = math.max(layers[targetId] ?? 0, layers[nodeId]! + 1);
      final count = remainingIncoming[targetId]! - 1;
      remainingIncoming[targetId] = count;
      if (count == 0) {
        ready.add(targetId);
        ready.sort((left, right) => rank[left]!.compareTo(rank[right]!));
      }
    }
  }
  var fallbackLayer = layers.values.fold<int>(0, math.max) + 1;
  final sortedIds = sorted.toSet();
  for (final id in traversalOrder.where((id) => !sortedIds.contains(id))) {
    layers[id] = fallbackLayer++;
  }

  final nodesByLayer = <int, List<WorkflowNode>>{};
  for (final node in nodes) {
    (nodesByLayer[layers[node.id] ?? 0] ??= <WorkflowNode>[]).add(node);
  }
  final orderedLayers = nodesByLayer.keys.toList(growable: false)..sort();
  for (final layer in orderedLayers) {
    nodesByLayer[layer]!.sort(
      (left, right) => rank[left.id]!.compareTo(rank[right.id]!),
    );
  }
  final layerWidths = <int, double>{
    for (final layer in orderedLayers)
      layer: nodesByLayer[layer]!
          .map((node) => sizeOf(node).width)
          .fold<double>(0, math.max),
  };
  final summedWidth = layerWidths.values.fold<double>(
    0,
    (sum, width) => sum + width,
  );
  final horizontalGap = orderedLayers.length < 2
      ? 0.0
      : math.max(
          config.minimumHorizontalGap,
          math.min(
            config.horizontalGap,
            (availableWidth - summedWidth) / (orderedLayers.length - 1),
          ),
        );
  var verticalGap = config.verticalGap;
  for (final layer in orderedLayers) {
    final layerNodes = nodesByLayer[layer]!;
    if (layerNodes.length < 2) continue;
    final summedHeight = layerNodes
        .map((node) => sizeOf(node).height)
        .fold<double>(0, (sum, height) => sum + height);
    verticalGap = math.min(
      verticalGap,
      math.max(
        config.minimumVerticalGap,
        (availableHeight - summedHeight) / (layerNodes.length - 1),
      ),
    );
  }
  final layerHeights = <int, double>{
    for (final layer in orderedLayers)
      layer: nodesByLayer[layer]!.fold<double>(
        verticalGap * (nodesByLayer[layer]!.length - 1),
        (sum, node) => sum + sizeOf(node).height,
      ),
  };
  final height = layerHeights.values.fold<double>(0, math.max);
  final positions = <String, ({double x, double y})>{};
  var x = 0.0;
  for (final layer in orderedLayers) {
    var y = (height - layerHeights[layer]!) / 2;
    for (final node in nodesByLayer[layer]!) {
      positions[node.id] = (x: x, y: y);
      y += sizeOf(node).height + verticalGap;
    }
    x += layerWidths[layer]! + horizontalGap;
  }
  final width = x - horizontalGap;
  return _ScopeLayout(
    positions: Map<String, ({double x, double y})>.unmodifiable(positions),
    width: width,
    height: height,
    fits: width <= availableWidth + 0.01 && height <= availableHeight + 0.01,
  );
}

int _branchPriority(WorkflowNode node, String? handleId) {
  if (handleId == null || handleId == workflowContainerStartHandleId) return 0;
  if (node.kind == WorkflowNodeKind.condition) {
    final cases = node.conditionCases();
    final index = cases.indexWhere((item) => item.id == handleId);
    if (index >= 0) return index;
    return handleId == 'else' ? cases.length + 1 : cases.length + 2;
  }
  if (node.kind == WorkflowNodeKind.humanIntervention) {
    final actions = node.humanActions();
    final index = actions.indexWhere((item) => item.id == handleId);
    if (index >= 0) return index;
    return handleId == workflowHumanTimeoutHandleId
        ? actions.length + 1
        : actions.length + 2;
  }
  if (handleId == workflowSuccessHandleId) return 0;
  if (handleId == workflowFailureHandleId) return 1;
  return 2;
}

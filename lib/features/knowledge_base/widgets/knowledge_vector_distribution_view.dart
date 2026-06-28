import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/util/localized_text.dart';
import '../model/knowledge_vector_distribution.dart';

const double _kVectorSceneMinHeight = 320;
const double _kVectorPointHitRadius = 18;

class KnowledgeVectorDistributionView extends StatefulWidget {
  const KnowledgeVectorDistributionView({
    super.key,
    required this.distribution,
    this.height = 420,
    this.compact = false,
  });

  final KnowledgeVectorDistribution distribution;
  final double height;
  final bool compact;

  @override
  State<KnowledgeVectorDistributionView> createState() =>
      _KnowledgeVectorDistributionViewState();
}

class _KnowledgeVectorDistributionViewState
    extends State<KnowledgeVectorDistributionView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );
  double _yaw = -0.62;
  double _pitch = -0.34;
  double _zoom = 1.0;
  KnowledgeVectorDistributionPoint? _selected;

  @override
  void initState() {
    super.initState();
    _revealController.forward();
  }

  @override
  void didUpdateWidget(KnowledgeVectorDistributionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDistribution(oldWidget.distribution, widget.distribution)) {
      _selected = null;
      _revealController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.distribution.points;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    if (points.isEmpty) {
      return Container(
        height: math.max(_kVectorSceneMinHeight, widget.height),
        alignment: Alignment.center,
        decoration: _sceneDecoration(context),
        child: Text(
          isZh ? '没有可展示的向量点。' : 'No vector points to display.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final visibleKinds = points.map((point) => point.kind).toSet();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(
          _kVectorSceneMinHeight,
          widget.height.isFinite ? widget.height : _kVectorSceneMinHeight,
        );
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 720,
          height,
        );
        final projected = _projectPoints(
          points: points,
          size: size,
          yaw: _yaw,
          pitch: _pitch,
          zoom: _zoom,
        );
        final selectedProjection = _selected == null
            ? null
            : projected
                  .where((item) => item.point.id == _selected!.id)
                  .firstOrNull;
        return Container(
          height: height,
          decoration: _sceneDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent) return;
                    final next = (_zoom - event.scrollDelta.dy * 0.0014)
                        .clamp(0.62, 2.4)
                        .toDouble();
                    if (next == _zoom) return;
                    setState(() => _zoom = next);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        setState(() {
                          _yaw += details.delta.dx * 0.010;
                          _pitch = (_pitch + details.delta.dy * 0.008)
                              .clamp(-1.18, 1.18)
                              .toDouble();
                        });
                      },
                      onTapDown: (details) {
                        final nearest = _nearestPoint(
                          projected,
                          details.localPosition,
                        );
                        setState(() => _selected = nearest?.point);
                      },
                      child: AnimatedBuilder(
                        animation: _revealController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _KnowledgeVectorScenePainter(
                              projected: projected,
                              revealProgress: _revealController.value,
                              colors: _KnowledgeVectorSceneColors.resolve(
                                context,
                              ),
                              selectedId: _selected?.id,
                              compact: widget.compact,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 14,
                top: 12,
                child: _VectorSceneStats(distribution: widget.distribution),
              ),
              PositionedDirectional(
                start: 14,
                bottom: 12,
                child: _VectorLegend(visibleKinds: visibleKinds),
              ),
              if (selectedProjection != null)
                _VectorPointPopover(
                  projection: selectedProjection,
                  sceneSize: size,
                  onClose: () => setState(() => _selected = null),
                ),
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _sceneDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.70),
      ),
      boxShadow: [
        BoxShadow(
          color: colorScheme.shadow.withValues(alpha: 0.08),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  bool _sameDistribution(
    KnowledgeVectorDistribution a,
    KnowledgeVectorDistribution b,
  ) {
    if (identical(a, b)) return true;
    if (a.points.length != b.points.length) return false;
    if (a.points.isEmpty && b.points.isEmpty) return true;
    return a.points.first.id == b.points.first.id &&
        a.points.last.id == b.points.last.id &&
        a.generatedAt == b.generatedAt;
  }
}

class _VectorSceneStats extends StatelessWidget {
  const _VectorSceneStats({required this.distribution});

  final KnowledgeVectorDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final text = isZh
        ? '投影 ${distribution.points.length} 点 · ${distribution.originalDimensions} 维'
        : '${distribution.points.length} points · ${distribution.originalDimensions}D';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Text(
          distribution.hasMore ? '$text · ${isZh ? '已采样' : 'sampled'}' : text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _VectorLegend extends StatelessWidget {
  const _VectorLegend({required this.visibleKinds});

  final Set<String> visibleKinds;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final items = <({String kind, Color color, String label})>[
      (
        kind: KnowledgeVectorPointKind.corpus,
        color: _KnowledgeVectorSceneColors.corpus,
        label: isZh ? '全量' : 'Corpus',
      ),
      (
        kind: KnowledgeVectorPointKind.match,
        color: _KnowledgeVectorSceneColors.match,
        label: isZh ? '匹配' : 'Matches',
      ),
      (
        kind: KnowledgeVectorPointKind.query,
        color: _KnowledgeVectorSceneColors.query,
        label: isZh ? '查询' : 'Query',
      ),
    ].where((item) => visibleKinds.contains(item.kind)).toList(growable: false);
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final item in items)
          _VectorLegendPill(color: item.color, label: item.label),
      ],
    );
  }
}

class _VectorLegendPill extends StatelessWidget {
  const _VectorLegendPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VectorPointPopover extends StatelessWidget {
  const _VectorPointPopover({
    required this.projection,
    required this.sceneSize,
    required this.onClose,
  });

  final _ProjectedVectorPoint projection;
  final Size sceneSize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const width = 260.0;
    final left = (projection.offset.dx + 14)
        .clamp(12.0, math.max(12, sceneSize.width - width - 12))
        .toDouble();
    final top = (projection.offset.dy - 86)
        .clamp(12.0, math.max(12, sceneSize.height - 132))
        .toDouble();
    final score = projection.point.score;
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.88, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            alignment: Alignment.bottomLeft,
            child: Opacity(
              opacity: scale.clamp(0.0, 1.0).toDouble(),
              child: child,
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: projection.color.withValues(alpha: 0.44)),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: projection.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        projection.point.title.isEmpty
                            ? projection.point.id
                            : projection.point.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 17),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ],
                ),
                if (projection.point.preview.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    projection.point.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
                if (score != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'score ${score.toStringAsFixed(4)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: projection.color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeVectorScenePainter extends CustomPainter {
  const _KnowledgeVectorScenePainter({
    required this.projected,
    required this.revealProgress,
    required this.colors,
    required this.selectedId,
    required this.compact,
  });

  final List<_ProjectedVectorPoint> projected;
  final double revealProgress;
  final _KnowledgeVectorSceneColors colors;
  final String? selectedId;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintAxes(canvas, size);
    final sorted = List<_ProjectedVectorPoint>.of(projected)
      ..sort((a, b) => a.depth.compareTo(b.depth));
    final revealWindow = revealProgress * sorted.length;
    for (var i = 0; i < sorted.length; i++) {
      final localProgress = (revealWindow - i).clamp(0.0, 1.0).toDouble();
      if (localProgress <= 0) continue;
      final point = sorted[i];
      final selected = point.point.id == selectedId;
      final radius =
          point.radius *
          Curves.easeOutBack.transform(localProgress) *
          (selected ? 1.45 : 1);
      final alpha = (0.18 + 0.82 * localProgress).clamp(0.0, 1.0);
      final shadowPaint = Paint()
        ..color = point.color.withValues(alpha: selected ? 0.28 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(point.offset, radius * 1.8, shadowPaint);
      final paint = Paint()
        ..color = point.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point.offset, radius, paint);
      if (selected) {
        final ringPaint = Paint()
          ..color = point.color.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawCircle(point.offset, radius + 5, ringPaint);
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final gridPaint = Paint()
      ..color = colors.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, gridPaint);
    }
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.18,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        gridPaint,
      );
    }
  }

  void _paintAxes(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    final axes = <({Offset end, Color color})>[
      (end: Offset(radius, 0), color: colors.axisX),
      (end: Offset(0, -radius), color: colors.axisY),
      (end: Offset(-radius * 0.62, radius * 0.42), color: colors.axisZ),
    ];
    for (final axis in axes) {
      final paint = Paint()
        ..color = axis.color
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, center + axis.end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeVectorScenePainter oldDelegate) {
    return oldDelegate.projected != projected ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.colors != colors ||
        oldDelegate.compact != compact;
  }
}

class _KnowledgeVectorSceneColors {
  const _KnowledgeVectorSceneColors({
    required this.grid,
    required this.axisX,
    required this.axisY,
    required this.axisZ,
  });

  static const corpus = Color(0xFF38BDF8);
  static const match = Color(0xFFF59E0B);
  static const query = Color(0xFFEF4444);

  final Color grid;
  final Color axisX;
  final Color axisY;
  final Color axisZ;

  static _KnowledgeVectorSceneColors resolve(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _KnowledgeVectorSceneColors(
      grid: colorScheme.outlineVariant.withValues(alpha: 0.34),
      axisX: colorScheme.primary.withValues(alpha: 0.48),
      axisY: colorScheme.tertiary.withValues(alpha: 0.45),
      axisZ: colorScheme.secondary.withValues(alpha: 0.45),
    );
  }
}

class _ProjectedVectorPoint {
  const _ProjectedVectorPoint({
    required this.point,
    required this.offset,
    required this.depth,
    required this.radius,
    required this.color,
  });

  final KnowledgeVectorDistributionPoint point;
  final Offset offset;
  final double depth;
  final double radius;
  final Color color;
}

List<_ProjectedVectorPoint> _projectPoints({
  required List<KnowledgeVectorDistributionPoint> points,
  required Size size,
  required double yaw,
  required double pitch,
  required double zoom,
}) {
  final center = Offset(size.width / 2, size.height / 2);
  final radius = math.min(size.width, size.height) * 0.34 * zoom;
  final cosY = math.cos(yaw);
  final sinY = math.sin(yaw);
  final cosP = math.cos(pitch);
  final sinP = math.sin(pitch);
  return points
      .map((point) {
        final x1 = point.x * cosY + point.z * sinY;
        final z1 = -point.x * sinY + point.z * cosY;
        final y1 = point.y * cosP - z1 * sinP;
        final z2 = point.y * sinP + z1 * cosP;
        final perspective = (1 / (1.9 - z2 * 0.46))
            .clamp(0.42, 1.35)
            .toDouble();
        final offset = center + Offset(x1 * radius, -y1 * radius) * perspective;
        final baseRadius = switch (point.kind) {
          KnowledgeVectorPointKind.query => 8.5,
          KnowledgeVectorPointKind.match => 6.7,
          _ => 4.7,
        };
        final color = switch (point.kind) {
          KnowledgeVectorPointKind.query => _KnowledgeVectorSceneColors.query,
          KnowledgeVectorPointKind.match => _KnowledgeVectorSceneColors.match,
          _ => _KnowledgeVectorSceneColors.corpus,
        };
        return _ProjectedVectorPoint(
          point: point,
          offset: offset,
          depth: z2,
          radius: baseRadius * perspective,
          color: color,
        );
      })
      .toList(growable: false);
}

_ProjectedVectorPoint? _nearestPoint(
  List<_ProjectedVectorPoint> projected,
  Offset offset,
) {
  _ProjectedVectorPoint? nearest;
  var bestDistance = double.infinity;
  for (final point in projected) {
    final distance = (point.offset - offset).distance;
    if (distance < bestDistance) {
      bestDistance = distance;
      nearest = point;
    }
  }
  return bestDistance <= _kVectorPointHitRadius ? nearest : null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

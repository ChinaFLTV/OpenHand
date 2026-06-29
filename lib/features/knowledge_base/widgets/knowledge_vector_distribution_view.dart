import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/util/localized_text.dart';
import '../model/knowledge_vector_distribution.dart';

const double _kVectorSceneMinHeight = 320;
const double _kVectorPointHitRadius = 18;
const double _kVectorSceneMinZoom = 0.62;
const double _kVectorSceneMaxZoom = 10.0;
const double _kVectorSceneZoomButtonFactor = 1.18;
const double _kVectorSceneScrollZoomSensitivity = 0.0012;
const double _kVectorAxisExtent = 1.18;
const double _kVectorAxisTickScreenLength = 8;
const double _kVectorAxisMinorTickScreenLength = 5;
const double _kVectorAxisTargetTickGap = 62;
const double _kVectorAxisCompactTargetTickGap = 54;
const double _kVectorPopoverMinWidth = 282;
const double _kVectorPopoverMaxWidth = 342;

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
  double _gestureStartZoom = 1.0;
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
        final axisScale = _VectorAxisScale.resolve(
          size: size,
          zoom: _zoom,
          compact: widget.compact,
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
                    final factor = math.exp(
                      -event.scrollDelta.dy *
                          _kVectorSceneScrollZoomSensitivity,
                    );
                    _setZoom(_zoom * factor);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) {
                        _gestureStartZoom = _zoom;
                      },
                      onScaleUpdate: (details) {
                        final gestureScale =
                            details.scale.isFinite && details.scale > 0
                            ? details.scale
                            : 1.0;
                        final dx = details.focalPointDelta.dx.isFinite
                            ? details.focalPointDelta.dx
                            : 0.0;
                        final dy = details.focalPointDelta.dy.isFinite
                            ? details.focalPointDelta.dy
                            : 0.0;
                        setState(() {
                          _yaw += dx * 0.010;
                          _pitch = (_pitch + dy * 0.008)
                              .clamp(-1.18, 1.18)
                              .toDouble();
                          _zoom = _clampZoom(_gestureStartZoom * gestureScale);
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
                              yaw: _yaw,
                              pitch: _pitch,
                              zoom: _zoom,
                              axisScale: axisScale,
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
                end: 14,
                top: 12,
                child: _VectorViewportControls(
                  zoom: _zoom,
                  tickStep: axisScale.step,
                  onZoomIn: _zoom >= _kVectorSceneMaxZoom
                      ? null
                      : () => _setZoom(_zoom * _kVectorSceneZoomButtonFactor),
                  onZoomOut: _zoom <= _kVectorSceneMinZoom
                      ? null
                      : () => _setZoom(_zoom / _kVectorSceneZoomButtonFactor),
                  onReset: _resetViewport,
                ),
              ),
              PositionedDirectional(
                start: 14,
                bottom: 12,
                child: _VectorLegend(visibleKinds: visibleKinds),
              ),
              IgnorePointer(
                ignoring: selectedProjection == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  reverseDuration: const Duration(milliseconds: 210),
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeInCubic,
                    );
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.90,
                          end: 1.0,
                        ).animate(curved),
                        alignment: Alignment.bottomLeft,
                        child: child,
                      ),
                    );
                  },
                  child: selectedProjection == null
                      ? const SizedBox.expand(key: ValueKey('popover-empty'))
                      : SizedBox.expand(
                          key: ValueKey<String>(
                            'popover-${selectedProjection.point.id}',
                          ),
                          child: Stack(
                            children: [
                              _VectorPointPopover(
                                projection: selectedProjection,
                                sceneSize: size,
                                onClose: () => setState(() => _selected = null),
                              ),
                            ],
                          ),
                        ),
                ),
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

  void _setZoom(double zoom) {
    final next = _clampZoom(zoom);
    if ((next - _zoom).abs() < 0.001) return;
    setState(() => _zoom = next);
  }

  void _resetViewport() {
    setState(() {
      _yaw = -0.62;
      _pitch = -0.34;
      _zoom = 1.0;
    });
  }

  double _clampZoom(double zoom) {
    return zoom.clamp(_kVectorSceneMinZoom, _kVectorSceneMaxZoom).toDouble();
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

class _VectorViewportControls extends StatelessWidget {
  const _VectorViewportControls({
    required this.zoom,
    required this.tickStep,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final double zoom;
  final double tickStep;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VectorViewportIconButton(
              tooltip: isZh ? '缩小' : 'Zoom out',
              icon: Icons.remove_rounded,
              onPressed: onZoomOut,
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${(zoom * 100).round()}% · ${isZh ? '刻度' : 'tick'} ${_formatAxisValue(tickStep)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _VectorViewportIconButton(
              tooltip: isZh ? '放大' : 'Zoom in',
              icon: Icons.add_rounded,
              onPressed: onZoomIn,
            ),
            const SizedBox(width: 4),
            _VectorViewportIconButton(
              tooltip: isZh ? '重置视角' : 'Reset view',
              icon: Icons.center_focus_strong_rounded,
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _VectorViewportIconButton extends StatelessWidget {
  const _VectorViewportIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
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
    final isZh = openHandIsChineseLocale(context);
    final axisColors = _KnowledgeVectorSceneColors.resolve(context);
    final availableWidth = math.max(180.0, sceneSize.width - 24);
    final width = availableWidth < _kVectorPopoverMinWidth
        ? availableWidth
        : math.min(_kVectorPopoverMaxWidth, availableWidth);
    final maxHeight = math.max(160.0, sceneSize.height - 24);
    final estimatedHeight = _estimatedVectorPopoverHeight(projection.point);
    final visibleHeight = math.min(estimatedHeight, maxHeight);
    final preferAbove = projection.offset.dy > sceneSize.height * 0.52;
    final left = (projection.offset.dx + 14)
        .clamp(12.0, math.max(12.0, sceneSize.width - width - 12))
        .toDouble();
    final preferredTop = preferAbove
        ? projection.offset.dy - estimatedHeight - 14
        : projection.offset.dy + 14;
    final top = preferredTop
        .clamp(12.0, math.max(12.0, sceneSize.height - visibleHeight - 12))
        .toDouble();
    final score = projection.point.score;
    final rerankScore = projection.point.rerankScore;
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
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: projection.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: projection.color.withValues(alpha: 0.32),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                projection.point.title.isEmpty
                                    ? projection.point.id
                                    : projection.point.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.18,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _VectorPopoverPill(
                                    color: projection.color,
                                    label: _vectorKindLabel(
                                      projection.point.kind,
                                      isZh,
                                    ),
                                  ),
                                  _VectorPopoverPill(
                                    color: colorScheme.outline,
                                    label: isZh
                                        ? '投影深度 ${_formatCoordinate(projection.depth)}'
                                        : 'depth ${_formatCoordinate(projection.depth)}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: isZh ? '关闭详情' : 'Close details',
                          child: IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _VectorPopoverSection(
                      title: isZh ? '空间坐标' : 'Projected Coordinates',
                      child: Row(
                        children: [
                          Expanded(
                            child: _VectorMetricTile(
                              label: 'X',
                              value: _formatCoordinate(projection.point.x),
                              color: axisColors.axisX,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: _VectorMetricTile(
                              label: 'Y',
                              value: _formatCoordinate(projection.point.y),
                              color: axisColors.axisY,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: _VectorMetricTile(
                              label: 'Z',
                              value: _formatCoordinate(projection.point.z),
                              color: axisColors.axisZ,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (score != null || rerankScore != null) ...[
                      const SizedBox(height: 10),
                      _VectorPopoverSection(
                        title: isZh ? '检索指标' : 'Retrieval Metrics',
                        child: Row(
                          children: [
                            if (score != null)
                              Expanded(
                                child: _VectorMetricTile(
                                  label: isZh ? '召回' : 'Score',
                                  value: _formatScore(score),
                                  color: projection.color,
                                ),
                              ),
                            if (score != null && rerankScore != null)
                              const SizedBox(width: 7),
                            if (rerankScore != null)
                              Expanded(
                                child: _VectorMetricTile(
                                  label: isZh ? '重排' : 'Rerank',
                                  value: _formatScore(rerankScore),
                                  color: colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (projection.point.preview.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _VectorPopoverSection(
                        title: isZh ? '内容预览' : 'Preview',
                        child: Text(
                          projection.point.preview,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.38,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _VectorPopoverSection(
                      title: isZh ? '向量标识' : 'Vector ID',
                      child: Text(
                        projection.point.id,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VectorPopoverSection extends StatelessWidget {
  const _VectorPopoverSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _VectorMetricTile extends StatelessWidget {
  const _VectorMetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VectorPopoverPill extends StatelessWidget {
  const _VectorPopoverPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            height: 1,
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
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.axisScale,
    required this.colors,
    required this.selectedId,
    required this.compact,
  });

  final List<_ProjectedVectorPoint> projected;
  final double revealProgress;
  final double yaw;
  final double pitch;
  final double zoom;
  final _VectorAxisScale axisScale;
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
    final gridPaint = Paint()
      ..color = colors.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final ringCount = (_kVectorAxisExtent / axisScale.gridStep).floor();
    for (var i = 1; i <= ringCount; i++) {
      final radius = i * axisScale.gridStep;
      if (radius <= 1.02) {
        canvas.drawPath(_projectCirclePath(size, radius), gridPaint);
      }
    }
    final spokes = zoom >= 5 ? 12 : 8;
    for (var i = 0; i < spokes; i++) {
      final angle = i * math.pi * 2 / spokes;
      final inner = _projectSceneCoordinate(
        x: math.cos(angle) * 0.18,
        y: math.sin(angle) * 0.18,
        z: 0,
        size: size,
        yaw: yaw,
        pitch: pitch,
        zoom: zoom,
      );
      final outer = _projectSceneCoordinate(
        x: math.cos(angle),
        y: math.sin(angle),
        z: 0,
        size: size,
        yaw: yaw,
        pitch: pitch,
        zoom: zoom,
      );
      canvas.drawLine(inner.offset, outer.offset, gridPaint);
    }
  }

  void _paintAxes(Canvas canvas, Size size) {
    final axes = <_VectorAxisSpec>[
      const _VectorAxisSpec(
        label: 'X',
        x: 1,
        y: 0,
        z: 0,
        tickX: 0,
        tickY: 0,
        tickZ: 1,
      ),
      const _VectorAxisSpec(
        label: 'Y',
        x: 0,
        y: 1,
        z: 0,
        tickX: 1,
        tickY: 0,
        tickZ: 0,
      ),
      const _VectorAxisSpec(
        label: 'Z',
        x: 0,
        y: 0,
        z: 1,
        tickX: 1,
        tickY: 0,
        tickZ: 0,
      ),
    ];
    for (final axis in axes) {
      _paintAxis(canvas, size, axis, _axisColor(axis.label));
    }
  }

  void _paintAxis(Canvas canvas, Size size, _VectorAxisSpec axis, Color color) {
    final start = _projectSceneCoordinate(
      x: -axis.x * _kVectorAxisExtent,
      y: -axis.y * _kVectorAxisExtent,
      z: -axis.z * _kVectorAxisExtent,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final origin = _projectSceneCoordinate(
      x: 0,
      y: 0,
      z: 0,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final end = _projectSceneCoordinate(
      x: axis.x * _kVectorAxisExtent,
      y: axis.y * _kVectorAxisExtent,
      z: axis.z * _kVectorAxisExtent,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final negativePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final positivePaint = Paint()
      ..color = color.withValues(alpha: 0.70)
      ..strokeWidth = 1.55
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start.offset, origin.offset, negativePaint);
    canvas.drawLine(origin.offset, end.offset, positivePaint);

    final tickCount = (_kVectorAxisExtent / axisScale.step).floor();
    for (var index = -tickCount; index <= tickCount; index++) {
      if (index == 0) continue;
      final value = index * axisScale.step;
      if (value.abs() > _kVectorAxisExtent + 1e-6) continue;
      final tick = _projectSceneCoordinate(
        x: axis.x * value,
        y: axis.y * value,
        z: axis.z * value,
        size: size,
        yaw: yaw,
        pitch: pitch,
        zoom: zoom,
      );
      final major = _isAxisStepMultiple(value, axisScale.labelStep);
      final tickDirection = _axisTickDirection(size, axis, value);
      final length = major
          ? _kVectorAxisTickScreenLength
          : _kVectorAxisMinorTickScreenLength;
      final tickPaint = Paint()
        ..color = color.withValues(alpha: major ? 0.58 : 0.36)
        ..strokeWidth = major ? 1.15 : 0.9
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        tick.offset - tickDirection * (length / 2),
        tick.offset + tickDirection * (length / 2),
        tickPaint,
      );
      if (major && _isVisibleLabelAnchor(tick.offset, size)) {
        _paintTickLabel(
          canvas,
          axis: axis,
          value: value,
          anchor: tick.offset + tickDirection * (length + 5),
          color: color,
        );
      }
    }

    if (_isVisibleLabelAnchor(end.offset, size, padding: 26)) {
      _paintAxisEndLabel(canvas, axis.label, end.offset, color);
    }
  }

  Offset _axisTickDirection(Size size, _VectorAxisSpec axis, double value) {
    final center = _projectSceneCoordinate(
      x: axis.x * value,
      y: axis.y * value,
      z: axis.z * value,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final side = _projectSceneCoordinate(
      x: axis.x * value + axis.tickX * 0.08,
      y: axis.y * value + axis.tickY * 0.08,
      z: axis.z * value + axis.tickZ * 0.08,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final direct = _normalizedOffset(side.offset - center.offset, Offset.zero);
    if (direct != Offset.zero) return direct;
    final start = _projectSceneCoordinate(
      x: -axis.x,
      y: -axis.y,
      z: -axis.z,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    final end = _projectSceneCoordinate(
      x: axis.x,
      y: axis.y,
      z: axis.z,
      size: size,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    );
    return _normalizedOffset(
      Offset(
        -(end.offset.dy - start.offset.dy),
        end.offset.dx - start.offset.dx,
      ),
      const Offset(0, -1),
    );
  }

  void _paintTickLabel(
    Canvas canvas, {
    required _VectorAxisSpec axis,
    required double value,
    required Offset anchor,
    required Color color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${axis.label} ${_formatAxisValue(value)}',
        style: TextStyle(
          color: color.withValues(alpha: 0.72),
          fontSize: compact ? 8.5 : 9.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      anchor - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintAxisEndLabel(
    Canvas canvas,
    String label,
    Offset anchor,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: 0.88),
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, anchor + const Offset(8, -8));
  }

  Color _axisColor(String label) {
    return switch (label) {
      'X' => colors.axisX,
      'Y' => colors.axisY,
      'Z' => colors.axisZ,
      _ => colors.axisX,
    };
  }

  Path _projectCirclePath(Size size, double radius) {
    final path = Path();
    const segments = 72;
    for (var i = 0; i <= segments; i++) {
      final angle = math.pi * 2 * i / segments;
      final projected = _projectSceneCoordinate(
        x: math.cos(angle) * radius,
        y: math.sin(angle) * radius,
        z: 0,
        size: size,
        yaw: yaw,
        pitch: pitch,
        zoom: zoom,
      );
      if (i == 0) {
        path.moveTo(projected.offset.dx, projected.offset.dy);
      } else {
        path.lineTo(projected.offset.dx, projected.offset.dy);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _KnowledgeVectorScenePainter oldDelegate) {
    return oldDelegate.projected != projected ||
        oldDelegate.revealProgress != revealProgress ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.zoom != zoom ||
        oldDelegate.axisScale != axisScale ||
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

@immutable
class _VectorAxisScale {
  const _VectorAxisScale({
    required this.step,
    required this.labelStep,
    required this.gridStep,
  });

  final double step;
  final double labelStep;
  final double gridStep;

  static _VectorAxisScale resolve({
    required Size size,
    required double zoom,
    required bool compact,
  }) {
    final baseRadius = math.min(size.width, size.height) * 0.34;
    final pixelsPerUnit = math.max(1.0, baseRadius * zoom);
    final targetGap = compact
        ? _kVectorAxisCompactTargetTickGap
        : _kVectorAxisTargetTickGap;
    final step = _closestNiceAxisStep(targetGap / pixelsPerUnit);
    final labelStep = switch (step) {
      <= 0.05 => 0.10,
      <= 0.10 => 0.20,
      <= 0.25 => 0.50,
      _ => step,
    };
    final gridStep = math.max(0.10, labelStep);
    return _VectorAxisScale(
      step: step,
      labelStep: labelStep,
      gridStep: gridStep,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _VectorAxisScale &&
          step == other.step &&
          labelStep == other.labelStep &&
          gridStep == other.gridStep;

  @override
  int get hashCode => Object.hash(step, labelStep, gridStep);
}

class _VectorAxisSpec {
  const _VectorAxisSpec({
    required this.label,
    required this.x,
    required this.y,
    required this.z,
    required this.tickX,
    required this.tickY,
    required this.tickZ,
  });

  final String label;
  final double x;
  final double y;
  final double z;
  final double tickX;
  final double tickY;
  final double tickZ;
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

class _VectorSceneProjection {
  const _VectorSceneProjection({
    required this.offset,
    required this.depth,
    required this.perspective,
  });

  final Offset offset;
  final double depth;
  final double perspective;
}

_VectorSceneProjection _projectSceneCoordinate({
  required double x,
  required double y,
  required double z,
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
  final x1 = x * cosY + z * sinY;
  final z1 = -x * sinY + z * cosY;
  final y1 = y * cosP - z1 * sinP;
  final z2 = y * sinP + z1 * cosP;
  final perspective = (1 / (1.9 - z2 * 0.46)).clamp(0.42, 1.35).toDouble();
  return _VectorSceneProjection(
    offset: center + Offset(x1 * radius, -y1 * radius) * perspective,
    depth: z2,
    perspective: perspective,
  );
}

List<_ProjectedVectorPoint> _projectPoints({
  required List<KnowledgeVectorDistributionPoint> points,
  required Size size,
  required double yaw,
  required double pitch,
  required double zoom,
}) {
  return points
      .map((point) {
        final projected = _projectSceneCoordinate(
          x: point.x,
          y: point.y,
          z: point.z,
          size: size,
          yaw: yaw,
          pitch: pitch,
          zoom: zoom,
        );
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
          offset: projected.offset,
          depth: projected.depth,
          radius: baseRadius * projected.perspective,
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

double _closestNiceAxisStep(double rawStep) {
  final target = rawStep.clamp(0.05, 1.0).toDouble();
  const steps = <double>[0.05, 0.10, 0.20, 0.25, 0.50, 1.0];
  var best = steps.first;
  var bestScore = double.infinity;
  for (final step in steps) {
    final score = (math.log(target / step)).abs();
    if (score < bestScore) {
      best = step;
      bestScore = score;
    }
  }
  return best;
}

bool _isAxisStepMultiple(double value, double step) {
  if (!value.isFinite || !step.isFinite || step <= 0) return false;
  final scaled = value / step;
  return (scaled - scaled.roundToDouble()).abs() < 1e-6;
}

bool _isVisibleLabelAnchor(Offset offset, Size size, {double padding = 52}) {
  return offset.dx >= -padding &&
      offset.dy >= -padding &&
      offset.dx <= size.width + padding &&
      offset.dy <= size.height + padding;
}

Offset _normalizedOffset(Offset value, Offset fallback) {
  final distance = value.distance;
  if (!distance.isFinite || distance <= 1e-4) return fallback;
  return value / distance;
}

String _formatAxisValue(double value) {
  final normalized = value.abs() < 1e-9 ? 0.0 : value;
  if (normalized.abs() >= 1) return normalized.toStringAsFixed(1);
  return normalized.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

String _formatCoordinate(double value) {
  if (!value.isFinite) return '-';
  final normalized = value.abs() < 1e-9 ? 0.0 : value;
  return normalized.abs() < 0.1
      ? normalized.toStringAsFixed(3)
      : normalized.toStringAsFixed(2);
}

String _formatScore(double value) {
  if (!value.isFinite) return '-';
  final normalized = value.abs() < 1e-9 ? 0.0 : value;
  return normalized.toStringAsFixed(4);
}

String _vectorKindLabel(String kind, bool isZh) {
  return switch (kind) {
    KnowledgeVectorPointKind.query => isZh ? '查询向量' : 'Query vector',
    KnowledgeVectorPointKind.match => isZh ? '命中结果' : 'Matched chunk',
    KnowledgeVectorPointKind.corpus => isZh ? '全量采样' : 'Corpus sample',
    _ => kind.trim().isEmpty ? (isZh ? '向量点' : 'Vector point') : kind,
  };
}

double _estimatedVectorPopoverHeight(KnowledgeVectorDistributionPoint point) {
  var height = 216.0;
  if (point.preview.isNotEmpty) height += 86;
  if (point.score != null || point.rerankScore != null) height += 82;
  if (point.title.length > 38) height += 18;
  return height;
}

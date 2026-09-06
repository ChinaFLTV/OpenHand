// 缓存候选位置控件（结构条 + 可拖拽插桩）。
// 顶部展示一条对照当前 prompt 实际结构的彩色分段条：稳定前缀
// （[0]/[1]/[2]/[4]/[4.5]/[5]/history）后接易变尾部
// （[3s]/[3d]/[5.5]/reminders/latest-turn payload 的合并示意）。
// 鼠标悬停显示该段概述与缓存稳定性提示；上方铺有 N-1 个历史候选插桩
// （用户可拖动），尾部固定当前请求尾锚。协议层会先保留稳定锚和连续尾锚，
// 剩余预算再采用这些候选位置。
// 拖拽实时更新本地草稿，松手时提交持久化。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/interaction_timings.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/input_value_parsing.dart';

class PromptCacheBreakpointBar extends StatefulWidget {
  const PromptCacheBreakpointBar({
    super.key,
    required this.initialValues,
    required this.thumbCount,
    required this.onCommit,
    required this.onReset,
  });

  final List<double> initialValues;
  final int thumbCount;
  final Future<void> Function(List<double>) onCommit;
  final VoidCallback onReset;

  @override
  State<PromptCacheBreakpointBar> createState() =>
      _PromptCacheBreakpointBarState();
}

class _PromptCacheBreakpointBarState extends State<PromptCacheBreakpointBar> {
  late List<double> _draft;
  int? _draggingIndex;

  static const double _barHeight = 26;
  static const double _pegHeadWidth = 22;
  static const double _pegHeadHeight = 18;
  static const double _pegHeadTopGap = 2;
  static const double _topReserve = _pegHeadHeight + _pegHeadTopGap;

  @override
  void initState() {
    super.initState();
    _draft = List<double>.from(widget.initialValues);
  }

  @override
  void didUpdateWidget(covariant PromptCacheBreakpointBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValues != widget.initialValues &&
        !listEquals(oldWidget.initialValues, widget.initialValues)) {
      _draft = List<double>.from(widget.initialValues);
    }
  }

  // 与 ai_prompt_builder.dart 中实际编排一一对应；权重为视觉占比（不是
  // 真实 token 占比，仅作示意，便于一眼看清是哪一段）。配色采用低饱和
  // 调色板，深浅模式下都可读。每段附带 cacheHint，提示该段对缓存命中
  // 的稳定性影响。
  // Session State 位于尾部，与 prompt builder 一致；
  // 这样 [0..5] + history 形成稳定可缓存的长前缀。
  static const List<_PromptStructureSpec> _specs = <_PromptStructureSpec>[
    _PromptStructureSpec('sys', Color(0xFF6F4FB4), 1.2),
    _PromptStructureSpec('dev', Color(0xFF4955A6), 1.0),
    _PromptStructureSpec('tools', Color(0xFF2D6FA4), 1.5),
    _PromptStructureSpec('memory', Color(0xFF4F8C50), 1.0),
    _PromptStructureSpec('user_inst', Color(0xFF84A03A), 0.8),
    _PromptStructureSpec('summary', Color(0xFFB07B2C), 0.7),
    _PromptStructureSpec('history', Color(0xFFB85549), 2.5),
    _PromptStructureSpec('state', Color(0xFF3E847B), 0.75),
    _PromptStructureSpec('latest', Color(0xFFA04079), 0.55),
  ];

  List<_PromptStructureSegment> _segments(AppLocalizations l10n) {
    return _specs
        .map(
          (spec) => _PromptStructureSegment(
            id: spec.id,
            label: _labelFor(spec.id, l10n),
            summary: _summaryFor(spec.id, l10n),
            cacheHint: _cacheHintFor(spec.id, l10n),
            color: spec.color,
            weight: spec.weight,
          ),
        )
        .toList(growable: false);
  }

  String _labelFor(String id, AppLocalizations l10n) => switch (id) {
    'sys' => l10n.cacheBarSectionSysLabel,
    'dev' => l10n.cacheBarSectionDevLabel,
    'tools' => l10n.cacheBarSectionToolsLabel,
    'memory' => l10n.cacheBarSectionMemoryLabel,
    'user_inst' => l10n.cacheBarSectionUserInstLabel,
    'summary' => l10n.cacheBarSectionSummaryLabel,
    'history' => l10n.cacheBarSectionHistoryLabel,
    'state' => l10n.cacheBarSectionStateLabel,
    'latest' => l10n.cacheBarSectionLatestLabel,
    _ => id,
  };

  String _summaryFor(String id, AppLocalizations l10n) => switch (id) {
    'sys' => l10n.cacheBarSectionSysSummary,
    'dev' => l10n.cacheBarSectionDevSummary,
    'tools' => l10n.cacheBarSectionToolsSummary,
    'memory' => l10n.cacheBarSectionMemorySummary,
    'user_inst' => l10n.cacheBarSectionUserInstSummary,
    'summary' => l10n.cacheBarSectionSummarySummary,
    'history' => l10n.cacheBarSectionHistorySummary,
    'state' => l10n.cacheBarSectionStateSummary,
    'latest' => l10n.cacheBarSectionLatestSummary,
    _ => '',
  };

  String _cacheHintFor(String id, AppLocalizations l10n) => switch (id) {
    'sys' => l10n.cacheBarSectionSysCacheHint,
    'dev' => l10n.cacheBarSectionDevCacheHint,
    'tools' => l10n.cacheBarSectionToolsCacheHint,
    'memory' => l10n.cacheBarSectionMemoryCacheHint,
    'user_inst' => l10n.cacheBarSectionUserInstCacheHint,
    'summary' => l10n.cacheBarSectionSummaryCacheHint,
    'history' => l10n.cacheBarSectionHistoryCacheHint,
    'state' => l10n.cacheBarSectionStateCacheHint,
    'latest' => l10n.cacheBarSectionLatestCacheHint,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final segments = _segments(l10n);
    final percentLabel = _draft
        .map((v) => '${(v * 100).round()}%')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.cacheBarTopDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (width <= 0) {
              return const SizedBox(height: _topReserve + _barHeight);
            }
            return SizedBox(
              height: _topReserve + _barHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _onPanStart(d.localPosition.dx, width),
                onPanUpdate: (d) => _onPanUpdate(d.localPosition.dx, width),
                onPanEnd: (_) => _onPanEnd(),
                onTapDown: (d) => _onTap(d.localPosition.dx, width),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _topReserve,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(kOpenHandRadius8),
                        child: Row(
                          children: [
                            for (final seg in segments)
                              Expanded(
                                flex: (seg.weight * 100).round(),
                                child: _StructureSegmentTile(
                                  segment: seg,
                                  height: _barHeight,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    for (var i = 0; i < _draft.length; i++)
                      Positioned(
                        left:
                            (clampUnitInterval(_draft[i]) * width) -
                            _pegHeadWidth / 2,
                        top: 0,
                        child: _StaticPegHandle(
                          index: i,
                          active: _draggingIndex == i,
                          accent: cs.primary,
                          totalHeight: _topReserve + _barHeight,
                        ),
                      ),
                    Positioned(
                      left: width - _pegHeadWidth / 2,
                      top: 0,
                      child: _DynamicPegHandle(
                        accent: cs.tertiary,
                        totalHeight: _topReserve + _barHeight,
                        tooltip: l10n.cacheBarDynamicTooltip,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (final seg in segments) _SegmentLegendChip(segment: seg),
          ],
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < percentLabel.length; i++)
              Text(
                'P${i + 1}: ${percentLabel[i]}',
                style: theme.textTheme.bodySmall,
              ),
            Text(
              'P${percentLabel.length + 1}: 100% ${l10n.cacheBarDynamicSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: widget.onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.cacheBarResetEven),
          ),
        ),
      ],
    );
  }

  void _onPanStart(double dx, double width) {
    if (_draft.isEmpty) return;
    final v = unitRatio(dx, width);
    final idx = _nearestPegIndex(v);
    setState(() => _draggingIndex = idx);
    _movePeg(idx, v);
  }

  void _onPanUpdate(double dx, double width) {
    final idx = _draggingIndex;
    if (idx == null) return;
    final v = unitRatio(dx, width);
    _movePeg(idx, v);
  }

  void _onPanEnd() {
    final wasDragging = _draggingIndex != null;
    setState(() => _draggingIndex = null);
    if (wasDragging) widget.onCommit(_draft);
  }

  void _onTap(double dx, double width) {
    if (_draft.isEmpty) return;
    final v = unitRatio(dx, width);
    final idx = _nearestPegIndex(v);
    _movePeg(idx, v);
    widget.onCommit(_draft);
  }

  int _nearestPegIndex(double v) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _draft.length; i++) {
      final d = (_draft[i] - v).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _movePeg(int idx, double next) {
    final clone = List<double>.from(_draft);
    final lower = idx == 0 ? 0.0 : clone[idx - 1];
    final upper = idx == clone.length - 1 ? 1.0 : clone[idx + 1];
    clone[idx] = next.clamp(lower, upper);
    setState(() => _draft = clone);
  }
}

/// 静态段定义：id + 颜色 + 视觉权重。与 [AppLocalizations] 中具体文案的
/// 映射在 [_PromptCacheBreakpointBarState] 内通过 switch 完成，避免在常量
/// 列表中混入 BuildContext / 本地化依赖。
class _PromptStructureSpec {
  const _PromptStructureSpec(this.id, this.color, this.weight);

  final String id;
  final Color color;
  final double weight;
}

class _PromptStructureSegment {
  const _PromptStructureSegment({
    required this.id,
    required this.label,
    required this.summary,
    required this.cacheHint,
    required this.color,
    required this.weight,
  });

  final String id;
  final String label;
  final String summary;
  final String cacheHint;
  final Color color;
  final double weight;
}

TextSpan _promptSegmentTooltip(_PromptStructureSegment segment) {
  return TextSpan(
    children: [
      TextSpan(
        text: '${segment.label}\n',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      TextSpan(text: '${segment.summary}\n\n'),
      TextSpan(
        text: segment.cacheHint,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
    ],
  );
}

class _StructureSegmentTile extends StatelessWidget {
  const _StructureSegmentTile({required this.segment, required this.height});

  final _PromptStructureSegment segment;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      richMessage: _promptSegmentTooltip(segment),
      waitDuration: kOpenHandDenseTooltipWait,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: segment.color.withValues(alpha: 0.88),
            border: Border(right: BorderSide(color: theme.colorScheme.surface)),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              segment.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticPegHandle extends StatelessWidget {
  const _StaticPegHandle({
    required this.index,
    required this.active,
    required this.accent,
    required this.totalHeight,
  });

  final int index;
  final bool active;
  final Color accent;
  final double totalHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: totalHeight,
      child: Column(
        children: [
          Container(
            width: 22,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(kOpenHandRadius4),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              'P${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Center(child: Container(width: 2, color: accent)),
                Positioned(
                  bottom: 0,
                  child: CustomPaint(
                    size: const Size(10, 6),
                    painter: _DownTrianglePainter(color: accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownTrianglePainter extends CustomPainter {
  _DownTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DownTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DynamicPegHandle extends StatefulWidget {
  const _DynamicPegHandle({
    required this.accent,
    required this.totalHeight,
    required this.tooltip,
  });

  final Color accent;
  final double totalHeight;
  final String tooltip;

  @override
  State<_DynamicPegHandle> createState() => _DynamicPegHandleState();
}

class _DynamicPegHandleState extends State<_DynamicPegHandle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: kOpenHandMotion1400,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulseEnabled = openHandTickerMotionEnabled(context);
    _syncPulseController(pulseEnabled);
    final icon = Icon(Icons.bolt_rounded, size: 12, color: widget.accent);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: kOpenHandDenseTooltipWait,
      child: SizedBox(
        width: 22,
        height: widget.totalHeight,
        child: Column(
          children: [
            if (pulseEnabled)
              AnimatedBuilder(
                animation: _pulseController,
                child: icon,
                builder: (context, child) =>
                    _buildHead(_pulseController.value, child),
              )
            else
              _buildHead(0.5, icon),
            Expanded(
              child: CustomPaint(
                size: const Size(22, double.infinity),
                painter: _DashedLinePainter(color: widget.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncPulseController(bool enabled) {
    if (enabled) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      return;
    }
    _pulseController.stop();
  }

  Widget _buildHead(double t, Widget? child) {
    return Container(
      width: 22,
      height: 18,
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.18 + 0.18 * t),
        borderRadius: BorderRadius.circular(kOpenHandRadius4),
        border: Border.all(color: widget.accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: widget.accent.withValues(alpha: 0.15 + 0.25 * t),
            blurRadius: 4 + 6 * t,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 4.0;
    const gap = 3.0;
    var y = 0.0;
    final cx = size.width / 2;
    while (y < size.height) {
      final end = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(cx, y), Offset(cx, end), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SegmentLegendChip extends StatelessWidget {
  const _SegmentLegendChip({required this.segment});

  final _PromptStructureSegment segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      richMessage: _promptSegmentTooltip(segment),
      waitDuration: kOpenHandDenseTooltipWait,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: segment.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
          border: Border.all(color: segment.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: segment.color,
                shape: BoxShape.circle,
              ),
            ),
            kOpenHandHGap5,
            Text(
              segment.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

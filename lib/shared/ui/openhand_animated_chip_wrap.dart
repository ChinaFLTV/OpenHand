import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'animated_appearance.dart';
import 'motion_preference.dart';

/// 按稳定键保留退场胶囊，同时平滑调整换行位置和整组高度。
class OpenHandAnimatedChipWrap extends StatefulWidget {
  const OpenHandAnimatedChipWrap({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.topSpacing = 0,
    this.crossAxisAlignment = WrapCrossAlignment.start,
    this.settings,
  });

  /// 每项必须提供稳定的业务键；内容变化时保留原键。
  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double topSpacing;
  final WrapCrossAlignment crossAxisAlignment;
  final DialogAnimationSettings? settings;

  @override
  State<OpenHandAnimatedChipWrap> createState() =>
      _OpenHandAnimatedChipWrapState();
}

class _OpenHandAnimatedChipWrapState extends State<OpenHandAnimatedChipWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reflow = AnimationController(vsync: this);
  late List<Widget> _displayed;
  bool _readyForItemTransitions = false;

  @override
  void initState() {
    super.initState();
    _displayed = List.of(widget.children);
    // 列表卡本身已有首屏入场动效。首帧不再叠加每个胶囊的进场，避免刷新和
    // 网格复用时因多层透明度、缩放同时变化而闪烁。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _readyForItemTransitions = true);
    });
  }

  @override
  void didUpdateWidget(covariant OpenHandAnimatedChipWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = {for (final child in widget.children) child.key: child};
    final merged = List<Widget>.of(widget.children);
    // 保留离场项的原位置；新项无需等待其他项退场。
    for (var index = 0; index < _displayed.length; index++) {
      final child = _displayed[index];
      if (!next.containsKey(child.key)) {
        merged.insert(index.clamp(0, merged.length), child);
      }
    }
    _displayed = merged;
  }

  void _removeDismissed(Key key) {
    if (!mounted || widget.children.any((child) => child.key == key)) return;
    setState(() => _displayed.removeWhere((child) => child.key == key));
  }

  @override
  void dispose() {
    _reflow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.children.every((child) => child.key != null));
    assert(
      widget.children.map((child) => child.key).toSet().length ==
          widget.children.length,
    );
    final preference = context
        .select<SettingsController?, DialogAnimationSettings?>(
          (controller) => controller?.chipAnimationSettings,
        );
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.chip,
      override: widget.settings ?? preference,
    );
    final currentKeys = widget.children.map((child) => child.key).toSet();
    return _ChipWrapLayout(
      topSpacing: widget.topSpacing,
      controller: _reflow,
      settings: settings,
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      crossAxisAlignment: widget.crossAxisAlignment,
      textDirection: Directionality.of(context),
      children: [
        for (final child in _displayed)
          // 固定布局节点，切换进退场样式时保留当前位置。
          Padding(
            key: child.key,
            padding: EdgeInsets.zero,
            child: AnimatedAppearance(
              settings: settings,
              present: currentKeys.contains(child.key),
              animateInitialAppearance: _readyForItemTransitions,
              collapseSize: false,
              onDismissed: () => _removeDismissed(child.key!),
              child: ExcludeSemantics(
                excluding: !currentKeys.contains(child.key),
                child: ExcludeFocus(
                  excluding: !currentKeys.contains(child.key),
                  child: IgnorePointer(
                    ignoring: !currentKeys.contains(child.key),
                    child: TooltipVisibility(
                      visible: currentKeys.contains(child.key),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 复用 Wrap 的约束和换行，用同一时钟插值尺寸与偏移，不逐帧重建胶囊。
class _ChipWrapLayout extends MultiChildRenderObjectWidget {
  const _ChipWrapLayout({
    required this.controller,
    required this.settings,
    required this.spacing,
    required this.runSpacing,
    required this.topSpacing,
    required this.crossAxisAlignment,
    required this.textDirection,
    required super.children,
  });

  final AnimationController controller;
  final DialogAnimationSettings settings;
  final double spacing;
  final double runSpacing;
  final double topSpacing;
  final WrapCrossAlignment crossAxisAlignment;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderChipWrap(
    controller: controller,
    settings: settings,
    spacing: spacing,
    runSpacing: runSpacing,
    topSpacing: topSpacing,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderChipWrap renderObject) {
    renderObject
      ..settings = settings
      ..topSpacing = topSpacing
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = textDirection
      ..markNeedsLayout();
  }
}

class _RenderChipWrap extends RenderWrap {
  _RenderChipWrap({
    required this.controller,
    required this.settings,
    required super.spacing,
    required super.runSpacing,
    required this.topSpacing,
    required super.crossAxisAlignment,
    required super.textDirection,
  });

  final AnimationController controller;
  DialogAnimationSettings settings;
  DialogAnimationSettings? _previousSettings;
  bool _exiting = false;
  double topSpacing;
  Size? _startSize;
  Size? _targetSize;
  double _lastValue = 0;
  Map<RenderBox, Offset> _starts = {};
  Map<RenderBox, Offset> _targets = {};

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.addListener(_tick);
  }

  @override
  void detach() {
    controller.removeListener(_tick);
    super.detach();
  }

  void _tick() {
    if (controller.value != _lastValue) markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final measured = super.computeDryLayout(constraints);
    return constraints.constrain(
      Size(
        measured.width,
        measured.height + (childCount == 0 ? 0 : topSpacing),
      ),
    );
  }

  @override
  void performLayout() {
    _lastValue = controller.value;
    final previousSize = hasSize ? size : null;
    final previous = <RenderBox, Offset>{};
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as WrapParentData;
      if (_targets.containsKey(child)) previous[child] = data.offset;
      child = data.nextSibling;
    }
    super.performLayout();
    final inset = childCount == 0 ? 0.0 : topSpacing;
    final targetSize = constraints.constrain(
      Size(size.width, size.height + inset),
    );
    final targets = <RenderBox, Offset>{};
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as WrapParentData;
      targets[child] = data.offset + Offset(0, inset);
      child = data.nextSibling;
    }
    final changed =
        targetSize != _targetSize ||
        targets.length != _targets.length ||
        targets.entries.any((entry) => _targets[entry.key] != entry.value);
    if (changed) {
      _exiting =
          targets.length < _targets.length ||
          (targets.length == _targets.length &&
              _targetSize != null &&
              targetSize.height < _targetSize!.height);
    }
    controller.duration = _exiting
        ? settings.exitDuration
        : settings.entranceDuration;
    if (changed || (settings != _previousSettings && controller.isAnimating)) {
      _starts = previous;
      _targets = targets;
      _startSize = previousSize ?? targetSize;
      _targetSize = targetSize;
      final moving =
          _startSize != targetSize ||
          targets.entries.any(
            (entry) =>
                previous.containsKey(entry.key) &&
                previous[entry.key] != entry.value,
          );
      if (controller.duration == Duration.zero || !moving) {
        controller.stop();
        _lastValue = 1;
        controller.value = 1;
      } else {
        _lastValue = 0;
        controller.forward(from: 0);
      }
    } else if (controller.duration == Duration.zero) {
      controller.stop();
      _lastValue = 1;
      controller.value = 1;
    }
    _previousSettings = settings;
    final curve = _exiting ? settings.curve.reverseCurve : settings.curve.curve;
    final progress = curve.transform(controller.value).clamp(0.0, 1.0);
    size = constraints.constrain(Size.lerp(_startSize, targetSize, progress)!);
    for (final entry in targets.entries) {
      (entry.key.parentData! as WrapParentData).offset = Offset.lerp(
        _starts[entry.key] ?? entry.value,
        entry.value,
        progress,
      )!;
    }
  }
}

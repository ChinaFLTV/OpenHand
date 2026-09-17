import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'rich_content_frame_scheduler.dart';

/// 仅在接近所有祖先视口时申请构建额度；已显示的正文不退回占位。
class DeferredRichContent extends StatefulWidget {
  const DeferredRichContent({
    super.key,
    required this.builder,
    required this.placeholder,
    this.enabled = true,
  });

  final WidgetBuilder builder;
  final Widget placeholder;
  final bool enabled;

  @override
  State<DeferredRichContent> createState() => _DeferredRichContentState();
}

class _DeferredRichContentState extends State<DeferredRichContent> {
  static const double _preloadExtent = 120;
  static final _scheduler = RichContentFrameScheduler();
  final _positions = <ScrollPosition>[];
  late bool _ready = !widget.enabled;
  bool _checkQueued = false;
  VoidCallback? _cancelBuild;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stopWatching();
    if (_ready) return;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        _positions.add(position);
        position.addListener(_scheduleCheck);
      }
      return true;
    });
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(covariant DeferredRichContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _ready = true;
      _cancelBuild?.call();
      _cancelBuild = null;
      _stopWatching();
    }
  }

  bool _nearViewport() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    for (
      var ancestor = box.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is! RenderAbstractViewport) continue;
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(ancestor),
        Offset.zero & box.size,
      );
      if (!bounds.overlaps(ancestor.paintBounds.inflate(_preloadExtent))) {
        return false;
      }
    }
    return true;
  }

  void _scheduleCheck() {
    if (_ready || _checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (!mounted || _ready) return;
      if (!_nearViewport()) {
        _cancelBuild?.call();
        _cancelBuild = null;
        return;
      }
      _cancelBuild ??= _scheduler.schedule(
        () {
          _cancelBuild = null;
          if (!mounted || !_nearViewport()) return;
          _stopWatching();
          setState(() => _ready = true);
        },
        priority: true,
        onDropped: () => _cancelBuild = null,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _stopWatching() {
    for (final position in _positions) {
      position.removeListener(_scheduleCheck);
    }
    _positions.clear();
  }

  @override
  void dispose() {
    _cancelBuild?.call();
    _stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready
      ? widget.builder(context)
      : _RichContentLayoutProbe(
          onLayout: _scheduleCheck,
          child: widget.placeholder,
        );
}

class _RichContentLayoutProbe extends SingleChildRenderObjectWidget {
  const _RichContentLayoutProbe({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRichContentLayoutProbe(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRichContentLayoutProbe renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderRichContentLayoutProbe extends RenderProxyBox {
  _RenderRichContentLayoutProbe(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}

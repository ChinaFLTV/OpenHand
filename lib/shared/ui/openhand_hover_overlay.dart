import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../util/timer_safety.dart';
import 'animated_overlay.dart';
import 'interaction_timings.dart';
import 'motion_preference.dart';

const double kOpenHandHoverOverlayDefaultWidth = 400;
const double kOpenHandHoverOverlayDefaultMaxHeight = 420;
const double kOpenHandHoverOverlayGap = 8;

typedef OpenHandHoverOverlayBuilder =
    Widget Function(BuildContext context, BoxConstraints constraints);

/// 锚定到子组件的悬停浮层：进出场走全局动画设置，滚动时跟随锚点。
///
/// 浮层默认不参与命中测试，避免盖住相邻胶囊后悬停状态卡住；移出锚点即收起。
class OpenHandHoverOverlay extends StatefulWidget {
  const OpenHandHoverOverlay({
    super.key,
    required this.child,
    required this.builder,
    this.enabled = true,
    this.showDelay = kOpenHandHoverOverlayShowDelay,
    this.hideDelay = kOpenHandHoverOverlayHideDelay,
    this.motionScope = OpenHandMotionSettingsScope.chip,
    this.maxWidth = kOpenHandHoverOverlayDefaultWidth,
    this.maxHeight = kOpenHandHoverOverlayDefaultMaxHeight,
  });

  final Widget child;
  final OpenHandHoverOverlayBuilder builder;
  final bool enabled;
  final Duration showDelay;
  final Duration hideDelay;
  final OpenHandMotionSettingsScope motionScope;
  final double maxWidth;
  final double maxHeight;

  @override
  State<OpenHandHoverOverlay> createState() => _OpenHandHoverOverlayState();
}

class _OpenHandHoverOverlayState extends State<OpenHandHoverOverlay> {
  final LayerLink _link = LayerLink();
  final AnimatedOverlayEntryController _overlay =
      AnimatedOverlayEntryController();
  late final OpenHandDebouncer _showDebouncer;
  late final OpenHandDebouncer _hideDebouncer;
  bool _anchorHovered = false;
  bool _showAbove = false;

  @override
  void initState() {
    super.initState();
    _showDebouncer = OpenHandDebouncer(delay: widget.showDelay);
    _hideDebouncer = OpenHandDebouncer(delay: widget.hideDelay);
  }

  @override
  void didUpdateWidget(covariant OpenHandHoverOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _hideImmediately();
      return;
    }
    if (_overlay.hasEntry &&
        (oldWidget.maxWidth != widget.maxWidth ||
            oldWidget.maxHeight != widget.maxHeight ||
            oldWidget.motionScope != widget.motionScope)) {
      _overlay.markNeedsBuild();
    }
  }

  @override
  void deactivate() {
    _hideImmediately();
    super.deactivate();
  }

  @override
  void dispose() {
    _showDebouncer.dispose();
    _hideDebouncer.dispose();
    _overlay.dispose();
    super.dispose();
  }

  Duration get _showDelay {
    final delay = widget.showDelay;
    return delay < Duration.zero ? kOpenHandHoverOverlayShowDelay : delay;
  }

  Duration get _hideDelay {
    final delay = widget.hideDelay;
    return delay < Duration.zero ? kOpenHandHoverOverlayHideDelay : delay;
  }

  void _onAnchorEnter() {
    if (!widget.enabled) return;
    _anchorHovered = true;
    _hideDebouncer.cancel();
    if (_overlay.hasEntry) {
      _overlay.reopen();
      return;
    }
    if (_showDelay <= Duration.zero) {
      _showNow();
      return;
    }
    _showDebouncer.schedule(_showNow, delay: _showDelay);
  }

  void _onAnchorExit() {
    _anchorHovered = false;
    _showDebouncer.cancel();
    _scheduleHide();
  }

  void _scheduleHide() {
    if (_anchorHovered) return;
    if (_hideDelay <= Duration.zero) {
      _overlay.close();
      return;
    }
    _hideDebouncer.schedule(() {
      if (!mounted || _anchorHovered) return;
      _overlay.close();
    }, delay: _hideDelay);
  }

  void _hideImmediately() {
    _anchorHovered = false;
    _showDebouncer.cancel();
    _hideDebouncer.cancel();
    _overlay.close(immediately: true);
  }

  void _showNow() {
    if (!mounted || !widget.enabled || !_anchorHovered) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !renderObject.attached) {
      return;
    }
    final overlayState = Overlay.maybeOf(context);
    if (overlayState == null) return;
    final overlayBox = overlayState.context.findRenderObject();
    if (overlayBox is! RenderBox ||
        !overlayBox.hasSize ||
        !overlayBox.attached) {
      return;
    }
    final offset = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final chipCenterY = offset.dy + renderObject.size.height / 2;
    _showAbove = chipCenterY > overlayBox.size.height * 0.58;
    _overlay.show(overlay: overlayState, builder: _buildOverlay);
  }

  Widget _buildOverlay(
    BuildContext overlayContext,
    ValueListenable<bool> visibility,
    VoidCallback onExitCompleted,
  ) {
    if (!mounted) return const SizedBox.shrink();
    final settings = openHandMotionSettingsOf(
      overlayContext,
      widget.motionScope,
    );
    final maxWidth = widget.maxWidth.isFinite && widget.maxWidth > 0
        ? widget.maxWidth
        : kOpenHandHoverOverlayDefaultWidth;
    final maxHeight = widget.maxHeight.isFinite && widget.maxHeight > 0
        ? widget.maxHeight
        : kOpenHandHoverOverlayDefaultMaxHeight;
    final constraints = BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    final overlayAlignment = _showAbove
        ? Alignment.bottomCenter
        : Alignment.topCenter;
    return IgnorePointer(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _showAbove ? Alignment.topCenter : Alignment.bottomCenter,
        followerAnchor: overlayAlignment,
        offset: Offset(
          0,
          _showAbove ? -kOpenHandHoverOverlayGap : kOpenHandHoverOverlayGap,
        ),
        child: AnimatedOverlayContent(
          customSettings: settings,
          visibility: visibility,
          onExitCompleted: onExitCompleted,
          alignment: overlayAlignment,
          child: UnconstrainedBox(
            alignment: overlayAlignment,
            child: ConstrainedBox(
              constraints: constraints,
              child: widget.builder(overlayContext, constraints),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _onAnchorEnter(),
        onExit: (_) => _onAnchorExit(),
        child: widget.child,
      ),
    );
  }
}

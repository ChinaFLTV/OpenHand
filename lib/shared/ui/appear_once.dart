import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const Duration _kDefaultAppearDuration = kOpenHandMotion320;
const double _kDefaultAppearSlideOffset = 12.0;

/// One-shot, ticker-self-disposing entrance animation wrapper.
///
/// Wrap a list item (or any widget that newly enters the tree) with
/// [AppearOnce] to give it a gentle fade + upward slide on first build.
/// After the animation completes the internal [AnimationController] is
/// disposed and subsequent rebuilds fall through to a static fast path —
/// so a sidebar / list with hundreds of items pays no per-frame ticker
/// cost once they have settled.
///
/// This intentionally mirrors the entrance pattern already used by the
/// transcript bubble (`_TranscriptAnimatedMessageEntry`) and the
/// `_PaintOffsetTransition` family in `openhand_home_page.dart`: it only
/// uses `FadeTransition` + a paint-time translate, never an
/// `AnimatedWidget` subclass that would assert under `LayoutBuilder`.
class AppearOnce extends StatefulWidget {
  const AppearOnce({
    super.key,
    required this.child,
    // Keep compact chips and tiles aligned with the softer transcript
    // message entrance.
    this.duration = _kDefaultAppearDuration,
    this.slideOffset = _kDefaultAppearSlideOffset,
  });

  final Widget child;
  final Duration duration;

  /// Pixels of vertical translation at animation start (`offset.dy`).
  /// Always animates from `slideOffset` (down) up to `0`.
  final double slideOffset;

  @override
  State<AppearOnce> createState() => _AppearOnceState();
}

class _AppearOnceState extends State<AppearOnce>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _opacity;
  Animation<double>? _translate;
  bool _deferredControllerCleanup = false;

  @override
  void initState() {
    super.initState();
    final ctrl = AnimationController(
      duration: _safeAppearDuration(widget.duration),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    // Match the Material 3 emphasized motion used by transcript bubbles and
    // panel transitions.
    _translate = CurvedAnimation(
      parent: ctrl,
      curve: Curves.easeInOutCubicEmphasized,
    );
    ctrl.addStatusListener(_onStatus);
    _ctrl = ctrl;
    ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant AppearOnce oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _ctrl;
    if (ctrl != null && widget.duration != oldWidget.duration) {
      ctrl.duration = _safeAppearDuration(widget.duration);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _disposeCompletedController();
  }

  void _disposeCompletedController() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    ctrl.removeStatusListener(_onStatus);
    ctrl.dispose();
    _ctrl = null;
    _opacity = null;
    _translate = null;
    _deferredControllerCleanup = false;
    if (mounted) setState(() {});
  }

  void _disposeControllerAfterBuild() {
    if (_deferredControllerCleanup) return;
    _deferredControllerCleanup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _disposeCompletedController();
    });
  }

  @override
  void dispose() {
    _ctrl?.removeStatusListener(_onStatus);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _opacity;
    final translate = _translate;
    if (opacity == null || translate == null) {
      // Animation already finished — return the child directly so we add
      // zero overhead per frame from here on out.
      return widget.child;
    }
    if (!openHandTickerMotionEnabled(context)) {
      // Honor user / OS reduce-motion without mutating the controller during
      // build; cleanup is deferred to avoid build-phase setState hazards.
      // TickerMode-off subtrees use the same fast path so content never stays
      // invisible at the animation's first frame while tickers are muted.
      _disposeControllerAfterBuild();
      return widget.child;
    }
    return FadeTransition(
      opacity: opacity,
      child: _AppearTranslate(
        animation: translate,
        slideOffset: _safeAppearSlideOffset(widget.slideOffset),
        child: widget.child,
      ),
    );
  }
}

/// Paint-time vertical translation (no setState per tick).
///
/// Mirrors the safe pattern from `_PaintOffsetTransition` in
/// `openhand_home_page.dart` so this wrapper composes safely inside
/// `LayoutBuilder` / `SliverList` contexts where `SlideTransition` would
/// trip the `BuildScope` assertion.
class _AppearTranslate extends SingleChildRenderObjectWidget {
  const _AppearTranslate({
    required this.animation,
    required this.slideOffset,
    required Widget super.child,
  });

  final Animation<double> animation;
  final double slideOffset;

  @override
  _AppearTranslateRender createRenderObject(BuildContext context) {
    return _AppearTranslateRender(
      animation: animation,
      slideOffset: slideOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _AppearTranslateRender renderObject,
  ) {
    renderObject
      ..animation = animation
      ..slideOffset = slideOffset;
  }
}

class _AppearTranslateRender extends RenderProxyBox {
  _AppearTranslateRender({
    required Animation<double> animation,
    required double slideOffset,
  }) : _animation = animation,
       _slideOffset = _safeAppearSlideOffset(slideOffset);

  Animation<double> _animation;
  double _slideOffset;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  set slideOffset(double value) {
    final safeValue = _safeAppearSlideOffset(value);
    if (_slideOffset == safeValue) return;
    _slideOffset = safeValue;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final value = _animation.value.clamp(0.0, 1.0);
    final dy = (1 - value) * _slideOffset;
    super.paint(context, offset + Offset(0, dy));
  }
}

Duration _safeAppearDuration(Duration duration) {
  if (duration <= Duration.zero) return _kDefaultAppearDuration;
  return duration;
}

double _safeAppearSlideOffset(double value) {
  if (!value.isFinite) return _kDefaultAppearSlideOffset;
  return value;
}

/// Lightweight wrapper that reads the global
/// `listItemAnimationSettings` from [SettingsController] and either
/// passes [child] through (if the user has set the channel's entrance
/// style to `none`) or wraps it with an [AppearOnce] using the
/// configured duration.
///
/// The slide direction is also inferred from the channel's entrance
/// style: `slideUp` (default) keeps the existing 12px translate-from-
/// below feel; `slideDown` flips to translate-from-above; any other
/// style falls back to a pure fade (no translate).
///
/// Use this around list-item subtrees that should benefit from the
/// "List Item Animation" panel in Settings.
class SettingsAwareAppearOnce extends StatelessWidget {
  const SettingsAwareAppearOnce({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.listItemAnimationSettings,
        );
    if (settings.entranceStyle == DialogAnimationStyle.none) {
      return child;
    }
    final double slide;
    switch (settings.entranceStyle) {
      case DialogAnimationStyle.slideUp:
        slide = 12.0;
      case DialogAnimationStyle.slideDown:
        slide = -12.0;
      case DialogAnimationStyle.fade:
      case DialogAnimationStyle.fadeScale:
      case DialogAnimationStyle.expand:
      case DialogAnimationStyle.elastic:
      case DialogAnimationStyle.springScale:
      case DialogAnimationStyle.flipX:
      case DialogAnimationStyle.rotateScale:
      case DialogAnimationStyle.slideLeft:
      case DialogAnimationStyle.slideRight:
        slide = 0.0;
      case DialogAnimationStyle.none:
        return child;
    }
    return AppearOnce(
      duration: settings.entranceDuration,
      slideOffset: slide,
      child: child,
    );
  }
}

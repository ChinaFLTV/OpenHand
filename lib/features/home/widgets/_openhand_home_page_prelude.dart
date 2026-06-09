part of '../openhand_home_page.dart';

enum AppSection {
  workspace,
  automations,
  skills,
  memory,
  mcp,
  hooks,
  crons,
  instructions,
  messageGateway,
  pluginService,
  settings,
  hardnessSession,
}

// 2026-05-01: Narrowed the default desktop navigation pane by 25%
// (352 -> 264). This keeps the pane clearly subordinate to the main
// workspace while preserving the independent 20 px inter-pane gutter.
const double _desktopNavigationWidth = 264;
// Equalised with the SafeArea outer inset (20 px) so the horizontal gutter
// between the navigation pane and the workspace pane visually matches the
// padding to the window's top / bottom / left / right edges.
const double _contentPaneGap = 20;
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;
// 2026-05-01: Tightened from 96 → 32 px so the "user is at bottom" detector
// only fires when the viewport is genuinely pinned to the latest message.
// 96 px caused subtle resume-on-glance regressions: a single accidental wheel
// tick that left the user 60 px above bottom would still be treated as "at
// bottom", silently re-arming auto-follow against the user's intent. 32 px
// is small enough to require a deliberate scroll-to-bottom gesture but large
// enough to absorb sub-pixel rounding from animated layout settles.
const double _autoFollowDistanceThreshold = 32;
// 2026-05-24 引入「暂停判定」滞回阈值：用户加载更多历史消息后，被
// prepend 的旧消息会在随后多帧里继续异步解析 markdown / 代码高亮，
// `maxScrollExtent` 会在数十像素范围内反复抖动。若仍沿用 32 px 的
// `_autoFollowDistanceThreshold` 同时判定「靠近底部」与「已离开底部」，
// `distanceToBottom` 的微小波动会让 `_shouldAutoFollowMessages` 高频翻
// 转，进而让 composer 上的「跳到最新」按钮形态、消息列表的边距贴底
// 决策反复刷新 — 用户在屏幕上看到的就是「消息盒子持续上下抽搐 / 鬼
// 畜」。把暂停阈值放宽到 96 px 形成滞回：只有真的离开底部 96 px 以
// 上才算「主动暂停跟随」，恢复时仍走 32 px 紧贴底部，避免抖动 ↔ 暂停
// 形成闭环。
const double _autoFollowPauseHysteresis = 96;
const String _detachedComposerDraftSessionKey = '__detached_composer_draft__';
// First-open jank mitigation: mount only the latest handful of message bubbles
// and let older history expand on demand. The transcript stays complete in
// memory; this only limits initial widget materialisation.
const int _transcriptInitialWindowSize = 6;
const int _transcriptFirstFrameWindowSize = 3;
const int _transcriptWindowIncrement = 18;
const int _transcriptWindowingThreshold = 8;
const int _transcriptPreparationThreshold = 12;
const int _transcriptStagedMaterializationThreshold = 24;
const double _transcriptListCacheExtent = 240;
const int _resumeAutoFollowStabilizationFrameCount = 2;
// Number of post-layout frames to wait before revealing the freshly switched
// transcript. Frame-driven gating replaces the former fixed 750 ms wall-clock
// delay so the overlay only stays up as long as the UI actually needs to
// finish first layout + scroll-to-bottom — preventing the "long blank"
// window that was previously forced regardless of how fast the real list
// rendered.
// 长会话切换时给底部小窗口、scroll-to-bottom 和 markdown 延迟解析留出
// 少量帧预算，避免真实 transcript reveal 与首批气泡挂载挤在同一帧。
const int _transcriptPreparationFrameBudget = 10;
// Hard cap so a single problematic session (e.g. huge transcript) never
// leaves the user staring at the placeholder indefinitely. If real layout
// has not finished within this window we reveal the transcript anyway.
// 阶段㉒ — 320 → 480 ms：与 6 帧预算相匹配，给慢机器留出更多 buffer。
// 2026-06-07 — 480 → 640 ms：与 10 帧预算（160ms）相匹配，给慢机器
// 留出更多 buffer；480ms 下偶尔出现 reveal 后仍可见 1-2 帧 placeholder
// 残留闪烁。
const Duration _transcriptPreparationMaxWait = Duration(milliseconds: 640);
const Duration _hardnessSessionPersistenceDebounce = Duration(
  milliseconds: 320,
);
final RegExp _markdownStructuralPattern = RegExp(
  r'[`*_#>\[\]|~]|(^|\n)\s{0,3}([-+*]|\d+\.)\s|(^|\n)\s{0,3}>|(^|\n)\s{0,3}#{1,6}\s|(^|\n)\s*([-*_]\s*){3,}(?=\n|$)|(^|\n)\s*\|.+\||!?\[[^\]]*\]\([^)]+\)|(^|\n)\s{4,}\S',
  multiLine: true,
);
final RegExp _trailingNewlineCodeBlockPattern = RegExp(r'\n$');

// Pre-compiled RegExp patterns used in render-path utility functions.
// Hoisted from inline allocations to avoid re-compilation per call.
final RegExp _planTimelineStepPrefixPattern = RegExp(
  r'^(?:[-*+•]\s+(?:\[[ xX]\]\s*)?|\d+[\.\):、]\s+|步骤\s*\d+\s*[:：.\-、)]\s+)',
);
final RegExp _toolLoopLimitPattern = RegExp(r'limit=(\d+)');
final RegExp _xmlStartTagProbePattern = RegExp(r'^<[\w!?]');
final RegExp _yamlKeyPrefixPattern = RegExp(r'^[\w./-]+:\s');
final RegExp _tomlSectionPattern = RegExp(r'^\[[^\]]+\]$');
final RegExp _tomlKeyValuePattern = RegExp(r'^[A-Za-z0-9_.-]+\s*=');
final RegExp _tomlBareKeyPattern = RegExp(r'^[A-Za-z0-9_.-]+$');

// Shared BorderRadius constants — avoid allocating new instances on every build.
const BorderRadius _borderRadius18 = BorderRadius.all(Radius.circular(18));
// 外层 clip 容器专用：比 _borderRadius18 大 1px，补偿 Border.all 的
// 外溢像素，防止 flutter_markdown_plus 的 Clip.hardEdge 裁掉圆角边框。
const BorderRadius _borderRadius19 = BorderRadius.all(Radius.circular(19));
const BorderRadius _borderRadius999 = BorderRadius.all(Radius.circular(999));

Widget _buildWorkspaceSidebarTransition({
  required Widget child,
  required Animation<double> animation,
  DialogAnimationSettings settings = const DialogAnimationSettings(),
}) {
  final safeAnimation = OpenHandBoundedDoubleAnimation(animation);
  final isFileExplorerPane =
      child.key == const ValueKey<String>('file-explorer-pane');
  final isNavigationPane =
      child.key == const ValueKey<String>('navigation-pane');
  final horizontalOffset = isFileExplorerPane
      ? 32.0
      : isNavigationPane
      ? -32.0
      : 0.0;
  return _buildWorkspaceSettingsAwareTransition(
    child: child,
    animation: safeAnimation,
    settings: settings,
    slideX: horizontalOffset,
    slideY: 10.0,
  );
}

Widget _buildWorkspaceContentTransition({
  required Widget child,
  required Animation<double> animation,
  DialogAnimationSettings settings = const DialogAnimationSettings(),
}) {
  final safeAnimation = OpenHandBoundedDoubleAnimation(animation);
  final childKey = switch (child.key) {
    ValueKey<String>(:final value) => value,
    _ => null,
  };
  final isEditorPane = childKey == 'editor-pane';
  final isSectionPane = childKey?.startsWith('section-') ?? false;
  final horizontalOffset = isEditorPane
      ? 34.0
      : isSectionPane
      ? -18.0
      : 0.0;
  final verticalOffset = isEditorPane ? 12.0 : 8.0;
  return _buildWorkspaceSettingsAwareTransition(
    child: child,
    animation: safeAnimation,
    settings: settings,
    slideX: horizontalOffset,
    slideY: verticalOffset,
  );
}

Widget _buildWorkspaceSettingsAwareTransition({
  required Widget child,
  required Animation<double> animation,
  required DialogAnimationSettings settings,
  required double slideX,
  required double slideY,
}) {
  final forward =
      animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.completed;
  final style = forward ? settings.entranceStyle : settings.exitStyle;
  final curveData = settings.curve;
  final safeAnimation = OpenHandBoundedDoubleAnimation(animation);
  final motion = openHandCurveAnimation(
    parent: safeAnimation,
    curve: curveData.curve,
    reverseCurve: curveData.reverseCurve,
  );
  final boundedMotion = OpenHandBoundedDoubleAnimation(motion);
  final offsetMotion = openHandCurveAnimation(
    parent: safeAnimation,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  Widget fadeChild(Widget child) =>
      FadeTransition(opacity: boundedMotion, child: child);
  Widget slideChild({required double dx, required double dy}) {
    return FadeTransition(
      opacity: boundedMotion,
      child: _PaintOffsetTransition(
        animation: offsetMotion,
        maxXOffset: dx,
        maxYOffset: dy,
        child: child,
      ),
    );
  }

  return switch (style) {
    DialogAnimationStyle.none => child,
    DialogAnimationStyle.fade => fadeChild(child),
    DialogAnimationStyle.fadeScale => FadeTransition(
      opacity: boundedMotion,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1.0).animate(motion),
        alignment: Alignment.topCenter,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideUp => slideChild(dx: 0.0, dy: slideY.abs()),
    DialogAnimationStyle.slideDown => slideChild(dx: 0.0, dy: -slideY.abs()),
    DialogAnimationStyle.slideLeft => slideChild(dx: -slideX.abs(), dy: 0.0),
    DialogAnimationStyle.slideRight => slideChild(dx: slideX.abs(), dy: 0.0),
    DialogAnimationStyle.expand => FadeTransition(
      opacity: openHandBoundedCurveAnimation(
        parent: safeAnimation,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(motion),
        alignment: Alignment.topCenter,
        child: child,
      ),
    ),
    DialogAnimationStyle.rotateScale => FadeTransition(
      opacity: boundedMotion,
      child: RotationTransition(
        turns: Tween<double>(begin: -0.015, end: 0.0).animate(motion),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(motion),
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    ),
    DialogAnimationStyle.elastic ||
    DialogAnimationStyle.springScale => FadeTransition(
      opacity: openHandBoundedCurveAnimation(
        parent: safeAnimation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(
          openHandCurveAnimation(
            parent: safeAnimation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInBack,
          ),
        ),
        alignment: Alignment.topCenter,
        child: child,
      ),
    ),
    DialogAnimationStyle.flipX => FadeTransition(
      opacity: boundedMotion,
      child: AnimatedBuilder(
        animation: motion,
        child: child,
        builder: (context, child) {
          final t = motion.value.clamp(0.0, 1.0);
          final tilt = (1.0 - t) * 0.015;
          final angle = (1.0 - t) * 0.25;
          final matrix = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(angle)
            ..rotateZ(tilt);
          return Transform(
            alignment: Alignment.topCenter,
            transform: matrix,
            child: child,
          );
        },
      ),
    ),
  };
}

Duration _effectiveSwitchDuration(DialogAnimationSettings settings) {
  // Keep switcher bookkeeping stable while clamping persisted or user-entered
  // values to a responsive range for page and panel transitions.
  final clamped = settings.durationMs.clamp(80, 800).toInt();
  final minMs =
      (settings.entranceStyle == DialogAnimationStyle.none &&
          settings.exitStyle == DialogAnimationStyle.none)
      ? 200
      : clamped;
  return Duration(milliseconds: clamped < minMs ? minMs : clamped);
}

/// Layout-safe paint-time vertical translation driven by an [Animation].
///
/// Implemented as a [SingleChildRenderObjectWidget] whose render object only
/// shifts the paint offset on each animation tick via [markNeedsPaint] — it
/// never allocates or holds onto any [Layer], so it cannot run into the
/// "disposed layer" assertions that handwritten `pushOpacity` paths can
/// trigger. Pair it with a [FadeTransition] (which manages its own
/// [OpacityLayer] correctly through [RenderAnimatedOpacity]) when you also
/// need an opacity animation.
class _PaintOffsetTransition extends SingleChildRenderObjectWidget {
  const _PaintOffsetTransition({
    required this.animation,
    required this.maxYOffset,
    this.maxXOffset = 0,
    required Widget super.child,
  });

  final Animation<double> animation;
  final double maxYOffset;
  final double maxXOffset;

  @override
  _PaintOffsetRenderObject createRenderObject(BuildContext context) {
    final disable = MediaQuery.disableAnimationsOf(context);
    return _PaintOffsetRenderObject(
      animation: animation,
      maxYOffset: disable ? 0.0 : maxYOffset,
      maxXOffset: disable ? 0.0 : maxXOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _PaintOffsetRenderObject renderObject,
  ) {
    final disable = MediaQuery.disableAnimationsOf(context);
    renderObject
      ..animation = animation
      ..maxYOffset = disable ? 0.0 : maxYOffset
      ..maxXOffset = disable ? 0.0 : maxXOffset;
  }
}

class _PaintOffsetRenderObject extends RenderProxyBox {
  _PaintOffsetRenderObject({
    required Animation<double> animation,
    required double maxYOffset,
    double maxXOffset = 0,
  }) : _animation = animation,
       _maxYOffset = maxYOffset,
       _maxXOffset = maxXOffset;

  Animation<double> _animation;
  double _maxYOffset;
  double _maxXOffset;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  set maxYOffset(double value) {
    if (_maxYOffset == value) return;
    _maxYOffset = value;
    markNeedsPaint();
  }

  set maxXOffset(double value) {
    if (_maxXOffset == value) return;
    _maxXOffset = value;
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
    final value = _animation.value;
    final dy = (1 - value) * _maxYOffset;
    final dx = (1 - value) * _maxXOffset;
    super.paint(context, offset + Offset(dx, dy));
  }
}

void _scheduleOverlayActionAfterMenuDismissal(
  BuildContext context,
  VoidCallback action,
) {
  // showMenu resolves before the popup route is fully torn down. Defer the
  // follow-up dialog to the next frame so two overlay routes do not overlap
  // during teardown/build-scope transitions.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      return;
    }
    action();
  });
}

Future<void> _awaitEndOfFrame() async {
  await WidgetsBinding.instance.endOfFrame;
  // One extra event-loop turn is required to fully escape the handleDrawFrame
  // call stack on desktop.  Flutter's endOfFrame future uses a sync Completer,
  // so its continuations execute synchronously inside the post-frame callback
  // chain — still within MouseTracker._deviceUpdatePhase — and any setState /
  // notifyListeners triggered there causes a !_debugDuringDeviceUpdate
  // assertion.  The delayed(Duration.zero) hop pushes us past the end of
  // handleDrawFrame into the next microtask-free event-loop cycle.
  await Future<void>.delayed(Duration.zero);
}

void _showHomeSnackBar(BuildContext context, SnackBar snackBar) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  OpenHandSnackBar.show(context, messenger, snackBar);
}

void _showHomeSnackBarWithMessenger(
  BuildContext context,
  ScaffoldMessengerState messenger,
  SnackBar snackBar,
) {
  OpenHandSnackBar.show(context, messenger, snackBar);
}

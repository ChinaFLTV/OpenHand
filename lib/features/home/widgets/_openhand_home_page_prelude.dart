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
const double _autoFollowAnimatedDistanceThreshold = 8;
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
// First-open jank mitigation: when a session is freshly opened we only
// materialise the most recent N display messages instead of the previous 30.
// Each bubble triggers a synchronous markdown parse + (potentially) code
// highlighting on its first build, so halving the eager window roughly
// halves the worst-case first-frame cost. Older messages remain a single
// scroll/tap away via the "load earlier" affordance.
// 阶段㉒ — 14 → 8：用户反馈 60+ 条会话首次打开仍卡；视窗高度内可见
// 气泡通常仅 3-5 张，14 个 render entries 中绝大多数都在 cacheExtent
// 之外被 ListView 立即 build (cacheExtent 320 px ≈ 1-2 张额外气泡)。
// 把窗口收缩到 8 让首屏物化的 _MessageBubble 数量与真正可见的数量
// 接近，markdown 帧节流的「待解析队列」深度减半，「Load earlier」
// 按钮一击即可向前展开 25 条。
const int _transcriptInitialWindowSize = 8;
const int _transcriptWindowIncrement = 25;
// Kick windowing in earlier so medium-sized sessions (20-40 msgs) also get
// the cheap first-paint path; the user can expand on demand.
// 阶段㉒ — 20 → 12：让任何超过一屏的会话都启用 windowing，避免小会话
// 也因 displayMessages.length ≥ 20 才触发缓存策略。
const int _transcriptWindowingThreshold = 12;
const int _resumeAutoFollowStabilizationFrameCount = 2;
// Number of post-layout frames to wait before revealing the freshly switched
// transcript. Frame-driven gating replaces the former fixed 750 ms wall-clock
// delay so the overlay only stays up as long as the UI actually needs to
// finish first layout + scroll-to-bottom — preventing the "long blank"
// window that was previously forced regardless of how fast the real list
// rendered.
// 阶段㉒ — 3 → 6：placeholder 多停留几帧让 SizedBox.expand 替换前
// 「老 transcript dispose + 新 placeholder mount + 首次绘制 + scroll-to-bottom」
// 全链路有充裕时间收敛；否则 reveal 触发与气泡 mount 撞在同一帧，
// drip 来不及把 markdown 解析摊开，仍然会触发首帧 jank。
const int _transcriptPreparationFrameBudget = 6;
// Hard cap so a single problematic session (e.g. huge transcript) never
// leaves the user staring at the placeholder indefinitely. If real layout
// has not finished within this window we reveal the transcript anyway.
// 阶段㉒ — 320 → 480 ms：与 6 帧预算相匹配，给慢机器留出更多 buffer。
const Duration _transcriptPreparationMaxWait = Duration(milliseconds: 480);
const Duration _transcriptMessageDeleteAnimationDuration = Duration(
  // 2026-05-01: Bumped 220 → 320 ms so the collapse + fade can use the
  // Material 3 emphasized curve without feeling clipped. Pairs with the
  // softer scale-shrink + larger upward translate inside the exit
  // builder for a cohesive "settle out" feel.
  // 2026-05-04: 320 → 440 ms to give the new Q弹 anticipation phase
  // (brief scale-up before collapse) the runway it needs without
  // feeling rushed.
  milliseconds: 440,
);
const Duration _sessionTitleRevealAnimationDuration = Duration(
  milliseconds: 720,
);
const Duration _planTimelineRevealAnimationDuration = Duration(
  milliseconds: 260,
);
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

void _disposeTextEditingControllerAfterCurrentFrame(
  TextEditingController controller,
) {
  // The dialog route may still be in its exit animation when showDialog
  // completes. Dispose the controller on the next frame so EditableText
  // can detach cleanly before the controller goes away.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.dispose();
  });
}

/// Builds a panel-switch transition that is safe to use inside a
/// [LayoutBuilder] subtree.
///
/// In Flutter 3.11+, [LayoutBuilder] has its own [BuildScope].  Any
/// [AnimatedWidget] subclass ([ScaleTransition], [SlideTransition],
/// [SizeTransition], [RotationTransition]) calls [setState] on every
/// animation tick in [handleBeginFrame].  That [setState] propagates through
/// `BuildScope._scheduleBuildFor` → `_LayoutBuilderElement._scheduleRebuild`
/// → `RenderObject.scheduleLayoutCallback`, which asserts
/// `debugNeedsLayout`.  During [handleBeginFrame] the render object has not
/// yet been marked as needing layout, so the assertion fires.
///
/// [FadeTransition] is the only safe transition widget — it extends
/// [SingleChildRenderObjectWidget] and drives opacity via
/// [RenderAnimatedOpacity.markNeedsPaint], never calling [setState].
///
/// All panel styles therefore use [FadeTransition] with varying curves to
/// maintain visual distinction.
Widget _buildPanelTransition({
  required Widget child,
  required Animation<double> animation,
  required DialogAnimationStyle entranceStyle,
  required DialogAnimationStyle exitStyle,
}) {
  final safeAnimation = _ClampedDoubleAnimation(animation);
  final isEntering =
      animation.status == AnimationStatus.forward ||
      animation.status == AnimationStatus.completed;
  final effectiveStyle = isEntering ? entranceStyle : exitStyle;
  return switch (effectiveStyle) {
    DialogAnimationStyle.none => FadeTransition(
      opacity: safeAnimation,
      child: child,
    ),
    DialogAnimationStyle.fade => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 14,
        child: child,
      ),
    ),
    // All variants use FadeTransition only — different curves give subtle
    // personality without resorting to AnimatedWidget subclasses.
    // Where motion is desired, we layer a paint-time `_PaintOffsetTransition`
    // (X and/or Y) so each style has a recognisable, optionally Q-bouncy feel
    // without ever calling setState during a frame tick.
    DialogAnimationStyle.fadeScale => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 8,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideUp => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 36,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideDown => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: -36,
        child: child,
      ),
    ),
    DialogAnimationStyle.expand => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeInOutCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 10,
        child: child,
      ),
    ),
    DialogAnimationStyle.rotateScale => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        ),
        maxXOffset: 12,
        maxYOffset: 12,
        child: child,
      ),
    ),
    DialogAnimationStyle.elastic => FadeTransition(
      opacity: CurvedAnimation(parent: safeAnimation, curve: Curves.easeOut),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.elasticOut,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 24,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideLeft => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 0,
        maxXOffset: -28,
        child: child,
      ),
    ),
    DialogAnimationStyle.slideRight => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: 0,
        maxXOffset: 28,
        child: child,
      ),
    ),
    DialogAnimationStyle.springScale => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInCubic),
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInBack,
        ),
        maxYOffset: 16,
        child: child,
      ),
    ),
    DialogAnimationStyle.flipX => FadeTransition(
      opacity: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: _PaintOffsetTransition(
        animation: CurvedAnimation(
          parent: safeAnimation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        maxYOffset: -18,
        child: child,
      ),
    ),
  };
}

Widget _buildWorkspaceSidebarTransition({
  required Widget child,
  required Animation<double> animation,
}) {
  final safeAnimation = _ClampedDoubleAnimation(animation);
  final isFileExplorerPane =
      child.key == const ValueKey<String>('file-explorer-pane');
  final isNavigationPane =
      child.key == const ValueKey<String>('navigation-pane');
  final horizontalOffset = isFileExplorerPane
      ? 32.0
      : isNavigationPane
      ? -32.0
      : 0.0;
  return FadeTransition(
    opacity: CurvedAnimation(
      parent: safeAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    child: _PaintOffsetTransition(
      animation: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
      maxXOffset: horizontalOffset,
      maxYOffset: 10,
      child: child,
    ),
  );
}

Widget _buildWorkspaceContentTransition({
  required Widget child,
  required Animation<double> animation,
}) {
  final safeAnimation = _ClampedDoubleAnimation(animation);
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
  return FadeTransition(
    opacity: CurvedAnimation(
      parent: safeAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    child: _PaintOffsetTransition(
      animation: CurvedAnimation(
        parent: safeAnimation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
      maxXOffset: horizontalOffset,
      maxYOffset: verticalOffset,
      child: child,
    ),
  );
}

Duration _effectiveSwitchDuration(DialogAnimationSettings settings) {
  // Always return a non-zero duration so page / panel switches are visibly
  // animated even when the user (or stale persisted settings) selected the
  // `none` style. The `none` style itself is rendered as a plain
  // FadeTransition in `_buildPanelTransition`, so giving it a real duration
  // produces a subtle, fast fade rather than an instant cut.
  final clamped = settings.durationMs.clamp(80, 800).toInt();
  final minMs =
      (settings.entranceStyle == DialogAnimationStyle.none &&
          settings.exitStyle == DialogAnimationStyle.none)
      ? 200
      : clamped;
  return Duration(milliseconds: clamped < minMs ? minMs : clamped);
}

class _ClampedDoubleAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  const _ClampedDoubleAnimation(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value.clamp(0.0, 1.0).toDouble();
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
    // NOTE: do NOT clamp the value to [0,1] — elastic / back curves emit
    // values <0 or >1 to produce overshoot, which is exactly the
    // “Q弹” feel we want when the style asks for it.
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

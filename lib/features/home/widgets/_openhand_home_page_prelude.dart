part of '../openhand_home_page.dart';

enum AppSection {
  workspace,
  skills,
  memory,
  mcp,
  hooks,
  crons,
  instructions,
  messageGateway,
  pluginService,
  knowledgeBase,
  workflows,
  services,
  settings,
  harnessSession,
}

const double _desktopNavigationWidth = 264;
const double _contentPaneGap = 20;
const EdgeInsets _homeContentSafeAreaMinimum = EdgeInsets.all(20);
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;
// 远离底部时的兜底阈值；明确向上输入立即暂停跟随。
const double _autoFollowPauseHysteresis = 96;
const String _detachedComposerDraftSessionKey = '__detached_composer_draft__';
// 长会话先显示最新窗口，按需展开旧记录，保持当前滚动范围稳定。
const int _transcriptWindowIncrement =
    TranscriptListWindowing.defaultWindowIncrement;
const Duration _htmlWebViewColdMountDelay = Duration(milliseconds: 220);
const Duration _htmlWebViewPermitWaitTimeout = Duration(seconds: 3);
const Duration _htmlWebViewPermitRetryDelay = Duration(milliseconds: 480);
const Duration _htmlWebViewBootstrapTimeout = Duration(seconds: 4);
const int _transcriptPrependAnchorSettleFrameCount = 6;
const int _responseVariantAnchorSettleFrameCount = 18;
const int _postScrollContentAnchorSettleFrameCount = 18;
const double _transcriptPrependAnchorMinCorrection = 0.75;

/// 锚点修正循环的静默提前退出阈值：连续该数量的帧无需修正即认定内容
/// 高度已收敛，提前结束逐帧测量，避免异步测高结束后仍空跑满帧预算。
const int _transcriptPrependAnchorStableFrameLimit = 2;

/// 只订阅 size / padding / viewInsets 三项：整份 MediaQuery 里还有文字缩放、
/// 无障碍开关等无关属性，任一变化都会白白重建整棵首页内容树。
Size _homeContentViewportSize(BuildContext context) {
  final viewport = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
  final horizontalInsets =
      math.max(_homeContentSafeAreaMinimum.left, padding.left) +
      math.max(_homeContentSafeAreaMinimum.right, padding.right);
  final verticalInsets =
      math.max(_homeContentSafeAreaMinimum.top, padding.top) +
      math.max(_homeContentSafeAreaMinimum.bottom, padding.bottom) +
      keyboardInset;
  return Size(
    math.max(0, viewport.width - horizontalInsets),
    math.max(0, viewport.height - verticalInsets),
  );
}

@immutable
class _WorkspaceSessionSnapshot {
  const _WorkspaceSessionSnapshot({
    required this.session,
    required this.sendPhase,
    required this.hydrating,
    required this.loadError,
    required this.canStop,
    required this.editingMessageId,
  });

  final AiSession? session;
  final AiSendPhase sendPhase;
  final bool hydrating;
  final String? loadError;
  final bool canStop;
  final String? editingMessageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _WorkspaceSessionSnapshot &&
          identical(session, other.session) &&
          sendPhase == other.sendPhase &&
          hydrating == other.hydrating &&
          loadError == other.loadError &&
          canStop == other.canStop &&
          editingMessageId == other.editingMessageId;

  @override
  int get hashCode => Object.hash(
    identityHashCode(session),
    sendPhase,
    hydrating,
    loadError,
    canStop,
    editingMessageId,
  );
}

const Duration _transcriptHistoryRevealCooldown = Duration(milliseconds: 120);
const int _scrollToBottomPositionRetryLimit = 16;
const int _scrollToBottomSettleFrameLimit = 36;
const int _scrollToBottomSettleStableFrameLimit = 4;
const int _transcriptInitialRevealMaxFrameCount = 8;
const int _transcriptInitialRevealMinimumFrameCount = 2;

/// 首屏至少完成初始布局再揭示；占位等待有时长和帧数上限，
/// 延迟正文的尺寸变化在绘制前保持底部位置。
const Duration _transcriptInitialRevealMaxDuration = Duration(
  milliseconds: 240,
);

/// 富文本卡片逐帧挂载会持续改变 maxScrollExtent。超过该宽限帧数后，只有
/// 「距离底部仍有偏差」才继续判定为不稳定，避免自激循环永远跑满帧预算。
const int _transcriptInitialRevealExtentGraceFrameCount = 4;
const double _scrollToBottomSettleTolerance = 0.75;
const double _messageScrollActivityDeltaThreshold = 0.05;
const double _messageDistanceToBottomDeltaThreshold = 0.15;
const int _resumeAutoFollowStabilizationFrameCount = 2;
const double _autoFollowResumeDistance = 1;
const Duration _editorTabsPersistenceDebounce = Duration(milliseconds: 500);
const Duration _harnessSessionPersistenceDebounce = Duration(milliseconds: 320);
const Duration _webReverseRuntimeMetadataDebounce = Duration(milliseconds: 500);
const int _workspaceSwitchMaxDurationMs = 800;
const int _sessionSwitchMaxDurationMs = 360;
const double _sessionSwitchInitialProgress = 0.45;
const double _workspaceSidebarPaneSlideDistance = 38;
const double _workspaceSidebarPaneScaleBegin = 0.974;
const double _workspacePaneFadeScaleBegin = 0.985;
const double _workspacePaneExpandScaleBegin = 0.96;
const double _workspacePaneRotateScaleBegin = 0.96;
const double _workspacePaneRotateTurnsBegin = -0.015;
const double _workspacePaneFlipMaxAngle = 0.25;
const double _workspacePaneFlipMaxTilt = 0.015;
const double _workspacePaneFlipPerspective = 0.001;
final RegExp _markdownStructuralPattern = RegExp(
  r'[`*_#>\[\]|~]|(^|\n)\s{0,3}([-+*]|\d+\.)\s|(^|\n)\s{0,3}>|(^|\n)\s{0,3}#{1,6}\s|(^|\n)\s*([-*_]\s*){3,}(?=\n|$)|(^|\n)\s*\|.+\||!?\[[^\]]*\]\([^)]+\)|(^|\n)\s{4,}\S',
  multiLine: true,
);
final RegExp _trailingNewlineCodeBlockPattern = RegExp(r'\n$');

// 渲染路径共用的预编译正则，避免每次调用重复创建。
final RegExp _planTimelineStepPrefixPattern = RegExp(
  r'^(?:[-*+•]\s+(?:\[[ xX]\]\s*)?|\d+[\.\):、]\s+|步骤\s*\d+\s*[:：.\-、)]\s+)',
);
final RegExp _toolLoopLimitPattern = RegExp(r'limit=(\d+)');
final RegExp _xmlStartTagProbePattern = RegExp(r'^<[\w!?]');
final RegExp _yamlKeyPrefixPattern = RegExp(r'^[\w./-]+:\s');
final RegExp _tomlSectionPattern = RegExp(r'^\[[^\]]+\]$');
final RegExp _tomlKeyValuePattern = RegExp(r'^[A-Za-z0-9_.-]+\s*=');
final RegExp _tomlBareKeyPattern = RegExp(r'^[A-Za-z0-9_.-]+$');

// 共用圆角常量，避免每次构建重复分配对象。
const BorderRadius _markdownCodeBlockRadius = BorderRadius.all(
  Radius.circular(kOpenHandRadius14),
);

bool _transcriptRenderPaused() =>
    _OpenHandHomePageState._activeHomeState?._transcriptScrollActivity.value ??
    false;

Widget _buildWorkspaceSidebarTransition({
  required Widget child,
  required Animation<double> animation,
  DialogAnimationSettings settings = const DialogAnimationSettings(),
}) {
  return buildAnimationStyleTransition(
    animation: animation,
    settings: settings,
    profile: const OpenHandAnimationTransitionProfile(
      alignment: Alignment.topCenter,
      fadeScaleBegin: _workspaceSidebarPaneScaleBegin,
      expandScaleBegin: _workspaceSidebarPaneScaleBegin,
      slideMode: OpenHandSlideTransitionMode.paintOffset,
      slideUpOffset: Offset(0, 8),
      slideDownOffset: Offset(0, -8),
      slideLeftOffset: Offset(-_workspaceSidebarPaneSlideDistance, 0),
      slideRightOffset: Offset(_workspaceSidebarPaneSlideDistance, 0),
    ),
    child: child,
  );
}

Widget _buildWorkspaceContentTransition({
  required Widget child,
  required Animation<double> animation,
  DialogAnimationSettings settings = const DialogAnimationSettings(),
}) {
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
    animation: animation,
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
  final slideDistanceX = slideX.abs();
  final slideDistanceY = slideY.abs();
  return buildAnimationStyleTransition(
    animation: animation,
    settings: settings,
    profile: OpenHandAnimationTransitionProfile(
      alignment: Alignment.topCenter,
      fadeScaleBegin: _workspacePaneFadeScaleBegin,
      expandScaleBegin: _workspacePaneExpandScaleBegin,
      rotateScaleBegin: _workspacePaneRotateScaleBegin,
      rotateTurnsBegin: _workspacePaneRotateTurnsBegin,
      flipMaxAngle: _workspacePaneFlipMaxAngle,
      flipMaxTilt: _workspacePaneFlipMaxTilt,
      flipPerspective: _workspacePaneFlipPerspective,
      slideMode: OpenHandSlideTransitionMode.paintOffset,
      slideUpOffset: Offset(0, slideDistanceY),
      slideDownOffset: Offset(0, -slideDistanceY),
      slideLeftOffset: Offset(-slideDistanceX, 0),
      slideRightOffset: Offset(slideDistanceX, 0),
    ),
    child: child,
  );
}

Duration _effectiveSwitchDuration(
  Duration duration, {
  int minimumAnimatedDurationMs = 0,
  int maximumAnimatedDurationMs = _workspaceSwitchMaxDurationMs,
}) {
  if (duration <= Duration.zero) return Duration.zero;
  final maximumDurationMs = math.max(
    DialogAnimationSettings.minAnimatedDurationMs,
    maximumAnimatedDurationMs,
  );
  final clamped = duration.inMilliseconds.clamp(
    DialogAnimationSettings.minAnimatedDurationMs,
    maximumDurationMs,
  );
  return Duration(milliseconds: math.max(clamped, minimumAnimatedDurationMs));
}

const Duration _endOfFrameWaitTimeout = Duration(milliseconds: 250);

Future<void> _awaitEndOfFrameBounded() {
  return WidgetsBinding.instance.endOfFrame.timeout(
    _endOfFrameWaitTimeout,
    onTimeout: () {},
  );
}

Future<void> _awaitEndOfFrame() async {
  await _awaitEndOfFrameBounded();
  // 桌面端需额外跨过一个事件循环，彻底离开 handleDrawFrame 调用栈，
  // 避免同步的 endOfFrame 回调在 MouseTracker 更新阶段触发状态变更断言。
  await Future<void>.delayed(Duration.zero);
}

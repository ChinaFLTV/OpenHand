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
  settings,
  hardnessSession,
}

const double _desktopNavigationWidth = 264;
const double _contentPaneGap = 20;
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;
// Auto-follow pauses only after a clearer user scroll away. This avoids
// repeated layout jitter when older markdown/code blocks finish measuring
// after history prepend.
const double _autoFollowPauseHysteresis = 96;
const String _detachedComposerDraftSessionKey = '__detached_composer_draft__';
// First-open jank mitigation: mount only the latest handful of message bubbles
// and let older history expand on demand. The transcript stays complete in
// memory; this only limits initial widget materialisation.
const int _transcriptInitialWindowSize = 6;
const int _transcriptFirstFrameWindowSize = 3;
const int _transcriptWindowIncrement = 6;
const int _transcriptWindowingThreshold = 8;
const int _transcriptPreparationThreshold = 8;
const int _transcriptStagedMaterializationThreshold = 24;
const int _transcriptWarmupMaxPerFrame = 1;
const int _transcriptWarmupSignatureCacheLimit = 256;
const int _transcriptWarmupCharacterBudget = 24000;
const int _transcriptHtmlWarmupMaxPerPass = 1;
const double _transcriptListCacheExtent = 120;
const double _transcriptHistoryRevealListCacheExtent = 900;
const int _htmlWebViewMaxMountedCount = 3;
const Duration _htmlWebViewColdMountDelay = Duration(milliseconds: 180);
const Duration _htmlWebViewPermitWaitTimeout = Duration(seconds: 3);
const Duration _htmlWebViewPermitRetryDelay = Duration(milliseconds: 420);
const int _transcriptPrependAnchorSettleFrameCount = 6;
const int _responseVariantAnchorSettleFrameCount = 18;
const double _transcriptPrependAnchorMinCorrection = 0.75;
const Duration _transcriptHistoryRevealCooldown = Duration(milliseconds: 120);
const int _scrollToBottomPositionRetryLimit = 16;
const int _resumeAutoFollowStabilizationFrameCount = 2;
// Frame-driven reveal keeps long transcript switches smooth without a fixed
// blank delay.
const int _transcriptPreparationFrameBudget = 6;
const Duration _transcriptPreparationHardTimeout = Duration(milliseconds: 1600);
const Duration _editorTabsPersistenceDebounce = Duration(milliseconds: 500);
const Duration _hardnessSessionPersistenceDebounce = Duration(
  milliseconds: 320,
);
const Duration _webReverseRuntimeMetadataDebounce = Duration(milliseconds: 500);
const int _workspaceSwitchMaxDurationMs = 800;
const int _disabledSwitchBookkeepingDurationMs = 200;
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

int _boundedTextFingerprint(String value, {int edgeLength = 128}) {
  final length = value.length;
  if (length <= edgeLength * 3) {
    return Object.hash(length, value);
  }
  final middle = length ~/ 2;
  final halfEdge = edgeLength ~/ 2;
  return Object.hash(
    length,
    value.substring(0, edgeLength),
    value.substring(middle - halfEdge, middle + halfEdge),
    value.substring(length - edgeLength),
  );
}

/// Tiny frame-budgeted task queue used by transcript render warmups.
///
/// Markdown parsing, syntax highlighting and platform-view mounting are all
/// UI-thread work.  Keeping their schedulers on one implementation avoids
/// each feature accidentally draining several tasks in the same frame.
class _FrameTaskScheduler {
  _FrameTaskScheduler({required this.maxPerFrame});

  final int maxPerFrame;
  final List<VoidCallback> _pending = <VoidCallback>[];
  bool _draining = false;
  int _generation = 0;

  void schedule(VoidCallback task) {
    _pending.add(task);
    if (_draining) {
      return;
    }
    _draining = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback(
      (timestamp) => _drain(timestamp, generation),
    );
  }

  void clear() {
    _pending.clear();
    _draining = false;
    _generation += 1;
  }

  void _drain(Duration _, int generation) {
    if (generation != _generation) {
      return;
    }
    if (_pending.isEmpty) {
      _draining = false;
      return;
    }
    final batchSize = math.min(_pending.length, math.max(1, maxPerFrame));
    final batch = _pending.sublist(0, batchSize);
    _pending.removeRange(0, batchSize);
    for (final task in batch) {
      task();
    }
    if (_pending.isEmpty) {
      _draining = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (timestamp) => _drain(timestamp, generation),
    );
  }
}

Widget _buildWorkspaceSidebarTransition({
  required Widget child,
  required Animation<double> animation,
  DialogAnimationSettings settings = const DialogAnimationSettings(),
}) {
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
    animation: animation,
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

Duration _effectiveSwitchDuration(DialogAnimationSettings settings) {
  // Keep switcher bookkeeping stable while clamping persisted or user-entered
  // values to a responsive range for page and panel transitions.
  final clamped = settings.durationMs
      .clamp(
        DialogAnimationSettings.minAnimatedDurationMs,
        _workspaceSwitchMaxDurationMs,
      )
      .toInt();
  final minMs =
      (settings.entranceStyle == DialogAnimationStyle.none &&
          settings.exitStyle == DialogAnimationStyle.none)
      ? _disabledSwitchBookkeepingDurationMs
      : clamped;
  return Duration(milliseconds: clamped < minMs ? minMs : clamped);
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
  OpenHandSnackBar.showInContext(context, snackBar);
}

void _showHomeSnackBarWithMessenger(
  BuildContext context,
  ScaffoldMessengerState messenger,
  SnackBar snackBar,
) {
  OpenHandSnackBar.show(context, messenger, snackBar);
}

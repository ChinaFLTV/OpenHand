import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart' as xml;
import 'package:yaml/yaml.dart';

import '../../app/model/app_info.dart';
import '../../app/model/app_settings_snapshot.dart';
import '../../app/model/dialog_animation_settings.dart';
import '../../app/model/editor_code_theme.dart';
import '../../app/model/editor_shortcut.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/openhand_scroll_physics.dart';
import '../../app/support/silent_log.dart';
import '../../app/theme/openhand_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/data/database_service.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/animated_menu.dart';
import '../../shared/widgets/animated_overlay.dart';
import '../../shared/widgets/appear_once.dart';
import '../../shared/widgets/appear_tracker.dart';
import '../../shared/widgets/choice_input_dialog.dart';
import '../../shared/widgets/export_config_dialog.dart';
import '../../shared/widgets/export_progress_dialog.dart';
import '../../shared/widgets/image_editor_dialog.dart';
import '../../shared/widgets/model_search_selector.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_allow_command_rule.dart';
import '../ai/model/ai_attachment.dart';
import '../ai/model/ai_builtin_tool_config.dart';
import '../ai/model/ai_creation_mode.dart';
import '../ai/model/ai_lsp_backend_catalog.dart';
import '../ai/model/ai_lsp_language_settings.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session.dart';
import '../ai/model/ai_session_message.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/model/ai_thread_template.dart';
import '../ai/service/ai_bash_tool_service.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_claude_hook_service.dart';
import '../ai/service/ai_file_history_service.dart';
import '../ai/service/ai_git_snapshot_service.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_session_jsonl_exporter.dart';
import '../ai/service/ai_workspace_instruction_service.dart';
import '../ai/service/lsp_client_service.dart';
import '../ai/tools/ai_ask_user_choice_tool.dart';
import '../crons/crons_controller.dart';
import '../crons/crons_view.dart';
import '../hardness/hardness_api_phase_runner.dart';
import '../hardness/hardness_cli_catalog.dart';
import '../hardness/hardness_engineering_dialog.dart';
import '../hardness/hardness_orchestrator.dart';
import '../hardness/hardness_session_dashboard.dart';
import '../hardness/hardness_session_store.dart';
import '../hardness/model/hardness_phase.dart';
import '../hardness/model/hardness_role_config.dart';
import '../hardness/model/hardness_session_config.dart';
import '../hardness/model/hardness_session_record.dart';
import '../hooks/hooks_view.dart';
import '../instructions/instructions_controller.dart';
import '../instructions/instructions_view.dart';
import '../instructions/model/user_instruction_entry.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_view.dart';
import '../mcp/model/mcp_server.dart';
import '../mcp/model/mcp_tool.dart';
import '../memory/memory_controller.dart';
import '../memory/memory_view.dart';
import '../message_gateway/message_gateway_view.dart';
import '../settings/settings_view.dart';
import '../skills/model/local_skill.dart';
import '../skills/skills_controller.dart';
import '../skills/skills_view.dart';
import 'editor_indentation.dart';
import 'machine_expert_dialog.dart';
import 'message_path_linking.dart';
import 'slash_command_parser.dart';
import 'tool_call_argument_parser.dart';

part '_home_navigation.dart';
part '_home_write_command_dialog.dart';
part '_home_workspace_view.dart';
part '_home_transcript.dart';
part '_home_session_toolbar.dart';
part '_home_session_metadata_dialog.dart';
part '_home_message_bubble.dart';
part '_home_audit_dialog.dart';
part '_home_message_content.dart';
part '_home_tool_call_widgets.dart';
part '_home_composer.dart';
part '_home_sidebar_tiles.dart';
part '_home_message_meta_rows.dart';
part '_home_code_highlighting.dart';
part '_home_token_dial.dart';
part '_home_thread_template_dialog.dart';
part '_home_programming_expert_project_dialog.dart';
part '_home_programming_expert_file_explorer.dart';
part '_home_hardness_annotations.dart';

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
  settings,
  hardnessSession,
}

const double _desktopNavigationWidth = 352;
const double _contentPaneGap = 18;
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;
const double _autoFollowDistanceThreshold = 96;
const double _autoFollowAnimatedDistanceThreshold = 8;
const String _detachedComposerDraftSessionKey = '__detached_composer_draft__';
const int _transcriptInitialWindowSize = 30;
const int _transcriptWindowIncrement = 25;
const int _transcriptWindowingThreshold = 40;
const int _resumeAutoFollowStabilizationFrameCount = 2;
// Number of post-layout frames to wait before revealing the freshly switched
// transcript. Frame-driven gating replaces the former fixed 750 ms wall-clock
// delay so the overlay only stays up as long as the UI actually needs to
// finish first layout + scroll-to-bottom — preventing the "long blank"
// window that was previously forced regardless of how fast the real list
// rendered.
const int _transcriptPreparationFrameBudget = 3;
// Hard cap so a single problematic session (e.g. huge transcript) never
// leaves the user staring at the placeholder indefinitely. If real layout
// has not finished within this window we reveal the transcript anyway.
const Duration _transcriptPreparationMaxWait = Duration(milliseconds: 320);
const Duration _transcriptMessageDeleteAnimationDuration = Duration(
  milliseconds: 220,
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
  };
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
    return _PaintOffsetRenderObject(
      animation: animation,
      maxYOffset: maxYOffset,
      maxXOffset: maxXOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _PaintOffsetRenderObject renderObject,
  ) {
    renderObject
      ..animation = animation
      ..maxYOffset = maxYOffset
      ..maxXOffset = maxXOffset;
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

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage>
    with WidgetsBindingObserver {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  final FocusNode _globalShortcutFocusNode = FocusNode();
  final FocusNode _composerFocusNode = FocusNode();
  final GlobalKey<_ComposerPanelState> _composerPanelKey =
      GlobalKey<_ComposerPanelState>();
  final AiWorkspaceInstructionService _workspaceInstructionService =
      AiWorkspaceInstructionService();
  final AiGitSnapshotService _gitSnapshotService = AiGitSnapshotService();

  AppSection _selectedSection = AppSection.workspace;
  _CreationMode _creationMode = _CreationMode.none;
  // macOS native menu bridge — see [_initNativeMenuChannel]. Only initialised
  // on macOS, where the system menu bar's "Settings…" item should drive the
  // in-app navigation to the Settings pane.
  MethodChannel? _macosMenuChannel;
  // 2026-04-25 — 当前会话窗口下，本轮临时取消的【指令】ID 集合。
  // 切换会话或发送完成后通常重置；UI 上用胶囊条配合 X / + 切换。
  final Set<String> _skippedInstructionIds = <String>{};
  AiCreationOptions _creationOptions = AiCreationOptions.empty;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  // True when auto-follow mode is ON but the user has scrolled away from the
  // bottom, so auto-scrolling is temporarily paused until the user scrolls
  // back near the bottom or presses the button to resume. Kept in sync via
  // _syncAutoFollowPausedState() so the composer button can surface a
  // distinct "paused" visual state and offer a "resume & jump to bottom"
  // tap action instead of toggling the mode off.
  bool _autoFollowPaused = false;
  String? _submittingSessionId;
  bool _shouldAutoFollowMessages = true;
  bool _pendingForcedScrollToBottom = false;
  bool _queuedForcedScrollToBottom = false;
  bool _scrollToBottomCallbackQueued = false;
  bool _processingQueueInProgress = false;
  bool _pendingAnimatedScrollToBottom = false;
  bool _programmaticAutoFollowScrollInProgress = false;
  bool _userScrollInProgress = false;
  int _pendingScrollToBottomSettlePasses = 0;
  String? _lastAutoScrollSignature;
  List<_ComposerAttachmentDraft> _pendingAttachments =
      const <_ComposerAttachmentDraft>[];
  final Map<String, List<_QueuedMessage>> _queuedMessagesBySessionId =
      <String, List<_QueuedMessage>>{};
  final Map<String, _ComposerDraftState> _composerDraftsBySessionId =
      <String, _ComposerDraftState>{};
  final Map<String, bool> _collapsedPlanTimelinesBySessionId = <String, bool>{};
  int? _runtimeToolPreviewCacheKey;
  AiRuntimeToolPreview? _runtimeToolPreviewCacheValue;
  AiSessionController? _observedSessionController;
  AiSessionMode _detachedComposerMode = AiSessionMode.chat;
  bool _detachedFullAccessPermission = false;
  String? _activeComposerSessionId;
  String? _activeTranscriptSessionId;
  String? _preparingTranscriptSessionId;
  int _transcriptPreparationGeneration = 0;
  bool _sessionControllerUiSyncQueued = false;
  int _sessionActivationGeneration = 0;
  AppLifecycleState? _appLifecycleState;
  void Function()? _disposeAskUserChoicePresenter;
  int _resumeAutoFollowSuppressionFrames = 0;
  bool _resumeAutoFollowSyncQueued = false;
  final ValueNotifier<double> _navigationWidthNotifier = ValueNotifier<double>(
    _desktopNavigationWidth,
  );

  // Active Hardness Engineering session (null when no HE session is running).
  HardnessOrchestrator? _activeHardnessOrchestrator;
  HardnessSessionConfig? _activeHardnessConfig;
  bool _heFullAccessPermission = false;
  final HardnessSessionPaneController _hardnessSessionPaneController =
      HardnessSessionPaneController();

  // Persisted record for the last HE session (survives app restarts).
  final HardnessSessionStore _hardnessSessionStore = HardnessSessionStore();
  HardnessSessionRecord? _persistedHardnessSession;
  Timer? _hardnessSessionSaveTimer;
  HardnessPhase? _lastHardnessAwaitingApprovalPhase;

  // Programming Expert: file explorer & inline editor state.
  bool _fileExplorerVisible = false;
  final List<String> _openFilePaths = [];
  String? _activeFilePath;
  String? _editorTabsSessionId;
  Timer? _editorTabsSaveTimer;

  void _toggleFileExplorer() {
    setState(() => _fileExplorerVisible = !_fileExplorerVisible);
  }

  void _openFileInEditor(String filePath) {
    setState(() {
      if (!_openFilePaths.contains(filePath)) {
        _openFilePaths.add(filePath);
      }
      _activeFilePath = filePath;
    });
    _scheduleEditorTabsPersistence();
  }

  void _selectFileTab(String filePath) {
    setState(() => _activeFilePath = filePath);
    _scheduleEditorTabsPersistence();
  }

  void _closeFileTab(String filePath) {
    setState(() {
      _openFilePaths.remove(filePath);
      if (_activeFilePath == filePath) {
        _activeFilePath = _openFilePaths.isNotEmpty
            ? _openFilePaths.last
            : null;
      }
    });
    _scheduleEditorTabsPersistence();
  }

  void _closeAllFileTabs() {
    setState(() {
      _openFilePaths.clear();
      _activeFilePath = null;
    });
    _scheduleEditorTabsPersistence();
  }

  void _reorderFileTabs(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _openFilePaths.removeAt(oldIndex);
      _openFilePaths.insert(newIndex, item);
    });
    _scheduleEditorTabsPersistence();
  }

  void _scheduleEditorTabsPersistence() {
    _editorTabsSaveTimer?.cancel();
    _editorTabsSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _persistEditorTabs();
    });
  }

  Future<void> _persistEditorTabs() async {
    final sessionId = _editorTabsSessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return;
    try {
      final db = DatabaseService.instance.database;
      final payload = jsonEncode(<String, Object?>{
        'open_files': _openFilePaths,
        'active_file': _activeFilePath,
      });
      await db.insert('app_settings', <String, Object?>{
        'key': 'editor_tabs_$sessionId',
        'value': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (error, stack) {
      silentLog('openhand_home_page', 'persist editor tabs', error, stack);
    }
  }

  Future<void> _restoreEditorTabs(String sessionId) async {
    try {
      final db = DatabaseService.instance.database;
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>['editor_tabs_$sessionId'],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final jsonStr = rows.first['value'] as String?;
      if (jsonStr == null || jsonStr.isEmpty) return;
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, Object?>) return;
      final openFiles = decoded['open_files'];
      final activeFile = decoded['active_file'] as String?;
      if (openFiles is List) {
        final validFiles = <String>[];
        for (final item in openFiles) {
          if (item is String && item.isNotEmpty) {
            validFiles.add(item);
          }
        }
        if (validFiles.isNotEmpty) {
          setState(() {
            _openFilePaths.clear();
            _openFilePaths.addAll(validFiles);
            _activeFilePath =
                activeFile != null && validFiles.contains(activeFile)
                ? activeFile
                : validFiles.last;
          });
        }
      }
    } catch (error, stack) {
      silentLog('openhand_home_page', 'restore editor tabs', error, stack);
    }
  }

  void _syncEditorTabsForSession(String? sessionId) {
    if (_editorTabsSessionId == sessionId) return;
    // Persist current tabs before switching.
    _editorTabsSaveTimer?.cancel();
    if (_editorTabsSessionId != null) {
      unawaited(_persistEditorTabs());
    }
    _editorTabsSessionId = sessionId;
    // Clear and restore.
    setState(() {
      _openFilePaths.clear();
      _activeFilePath = null;
    });
    if (sessionId != null && sessionId.isNotEmpty) {
      _restoreEditorTabs(sessionId);
    }
  }

  String? _programmingExpertProjectRoot(AiSession? session) {
    final config = _programmingExpertConfigMap(session);
    if (config == null) {
      return null;
    }
    final projectRoot = OpenHandPaths.normalizeOptionalPath(
      '${config['project_root'] ?? ''}',
    );
    return projectRoot.isEmpty ? null : projectRoot;
  }

  String _programmingExpertLanguage(AiSession? session) {
    final config = _programmingExpertConfigMap(session);
    if (config == null) {
      return 'mixed';
    }
    return normalizeAiLspLanguage('${config['language'] ?? 'mixed'}');
  }

  String _programmingExpertSdkPath(AiSession? session) {
    final config = _programmingExpertConfigMap(session);
    if (config == null) {
      return '';
    }
    return OpenHandPaths.normalizeOptionalPath('${config['sdk_path'] ?? ''}');
  }

  String _programmingExpertLspPath(AiSession? session) {
    final config = _programmingExpertConfigMap(session);
    if (config == null) {
      return '';
    }
    return OpenHandPaths.normalizeOptionalPath('${config['lsp_path'] ?? ''}');
  }

  String? _preferredProgrammingExpertProjectRootCandidate({
    required AiSessionController sessionController,
    AiSessionRuntimeContext? runtimeContext,
  }) {
    String? normalizeCandidate(String? value) {
      final normalized = OpenHandPaths.normalizeOptionalPath(value ?? '');
      return normalized.isEmpty ? null : normalized;
    }

    final currentProgrammingProject = _programmingExpertProjectRoot(
      sessionController.currentSession,
    );
    if (currentProgrammingProject != null) {
      return currentProgrammingProject;
    }
    return normalizeCandidate(
          runtimeContext?.repositorySnapshot?.repositoryRootPath,
        ) ??
        normalizeCandidate(runtimeContext?.workingDirectory);
  }

  Map<String, Object?>? _programmingExpertConfigMap(AiSession? session) {
    if (session == null || session.templateId != 'programming_expert') {
      return null;
    }
    final config = session.metadata['programming_expert_config'];
    if (config is Map<String, Object?>) {
      return config;
    }
    if (config is Map) {
      return Map<String, Object?>.from(config);
    }
    return null;
  }

  void _cacheHardnessShellState(HardnessOrchestrator? orchestrator) {
    _lastHardnessAwaitingApprovalPhase = orchestrator?.awaitingApprovalPhase;
  }

  AiSessionMode _effectiveComposerMode(AiSessionController sessionController) {
    return sessionController.currentSession?.mode ?? _detachedComposerMode;
  }

  AiSendPhase _displaySendPhaseForSession(
    AiSessionController sessionController,
    String? sessionId,
  ) {
    if (sessionId == null) {
      return AiSendPhase.idle;
    }
    final controllerPhase = sessionController.sendPhaseForSession(sessionId);
    if (controllerPhase != AiSendPhase.idle) {
      return controllerPhase;
    }
    return _submittingSessionId == sessionId
        ? AiSendPhase.sendingMessage
        : AiSendPhase.idle;
  }

  AiSendPhase _effectiveSendPhase(AiSessionController sessionController) {
    return _displaySendPhaseForSession(
      sessionController,
      sessionController.currentSessionId,
    );
  }

  bool _canStopCurrentSessionResponse(AiSessionController sessionController) {
    return sessionController.canStopResponding(
      sessionController.currentSessionId,
    );
  }

  Map<String, AiSendPhase> _navigationSendPhases(
    AiSessionController sessionController,
  ) {
    return <String, AiSendPhase>{
      for (final session in sessionController.sessions)
        session.id: _displaySendPhaseForSession(sessionController, session.id),
    };
  }

  bool _isPlanTimelineCollapsed(String? sessionId) {
    if (sessionId == null) {
      return false;
    }
    return _collapsedPlanTimelinesBySessionId[sessionId] ?? false;
  }

  void _setPlanTimelineCollapsed(String sessionId, bool collapsed) {
    if ((_collapsedPlanTimelinesBySessionId[sessionId] ?? false) == collapsed) {
      return;
    }
    setState(() {
      _collapsedPlanTimelinesBySessionId[sessionId] = collapsed;
    });
  }

  void _setComposerCollapsedState(
    bool collapsed, {
    bool requestFocusWhenExpanded = false,
  }) {
    if (_composerCollapsed != collapsed) {
      setState(() {
        _composerCollapsed = collapsed;
      });
    }
    if (collapsed) {
      if (_composerFocusNode.hasFocus) {
        _composerFocusNode.unfocus();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _globalShortcutFocusNode.hasFocus) {
          return;
        }
        _globalShortcutFocusNode.requestFocus();
      });
      return;
    }
    if (!requestFocusWhenExpanded) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _composerFocusNode.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    _composerFocusNode.onKeyEvent = _handleComposerFocusNodeKeyEvent;
    _messageScrollController.addListener(_handleMessageScroll);
    // Register a platform-level keyboard handler so shortcuts fire regardless
    // of which widget currently holds keyboard focus (Focus.onKeyEvent bubbling
    // is unreliable when the focus tree is not rooted at _globalShortcutFocusNode).
    HardwareKeyboard.instance.addHandler(_handleGlobalShortcutKeyEvent);
    _disposeAskUserChoicePresenter = AiAskUserChoiceTool.registerPresenter(
      _presentAskUserChoiceDialog,
    );
    _loadPersistedHardnessSession();
    _initNativeMenuChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    // 2026-04-13: Flush pending Hardness session state to disk whenever the
    // app enters background / inactive states. This ensures the session record
    // survives if the OS terminates the process before dispose() runs.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final pendingHardnessRecord = _persistedHardnessSession;
      if (pendingHardnessRecord != null) {
        // Cancel debounced timer and flush immediately.
        _hardnessSessionSaveTimer?.cancel();
        _hardnessSessionSaveTimer = null;
        unawaited(
          _hardnessSessionStore.save(pendingHardnessRecord).catchError((_) {}),
        );
      }
    }
    if (state != AppLifecycleState.resumed) {
      return;
    }
    _resumeAutoFollowSuppressionFrames =
        _resumeAutoFollowStabilizationFrameCount;
    _scheduleResumeAutoFollowSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessionController = context.read<AiSessionController>();
    if (identical(_observedSessionController, sessionController)) {
      return;
    }
    _observedSessionController?.removeListener(_handleSessionControllerChanged);
    _observedSessionController = sessionController;
    _observedSessionController?.addListener(_handleSessionControllerChanged);
    _activeComposerSessionId = sessionController.currentSessionId;
    _activeTranscriptSessionId = sessionController.currentSessionId;
  }

  @override
  void dispose() {
    _activeHardnessOrchestrator?.removeListener(_onHardnessOrchestratorChanged);
    _activeHardnessOrchestrator?.cancel();
    _activeHardnessOrchestrator?.dispose();
    _hardnessSessionSaveTimer?.cancel();
    _editorTabsSaveTimer?.cancel();
    // Flush pending editor tabs before disposal.
    if (_editorTabsSessionId != null) {
      unawaited(_persistEditorTabs().catchError((_) {}));
    }
    final pendingHardnessRecord = _persistedHardnessSession;
    if (pendingHardnessRecord != null) {
      unawaited(
        _hardnessSessionStore.save(pendingHardnessRecord).catchError((_) {}),
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    _observedSessionController?.removeListener(_handleSessionControllerChanged);
    _messageScrollController.removeListener(_handleMessageScroll);
    HardwareKeyboard.instance.removeHandler(_handleGlobalShortcutKeyEvent);
    _disposeAskUserChoicePresenter?.call();
    _disposeAskUserChoicePresenter = null;
    _macosMenuChannel?.setMethodCallHandler(null);
    _macosMenuChannel = null;
    _globalShortcutFocusNode.dispose();
    _composerFocusNode.dispose();
    _composerController.dispose();
    _messageScrollController.dispose();
    _navigationWidthNotifier.dispose();
    super.dispose();
  }

  void _clearPendingAutoFollowState() {
    _pendingForcedScrollToBottom = false;
    _queuedForcedScrollToBottom = false;
    _pendingAnimatedScrollToBottom = false;
    _pendingScrollToBottomSettlePasses = 0;
  }

  /// Presents the AskUserChoice dialog on behalf of the AI tool.
  ///
  /// Registered once in [initState] and unregistered in [dispose]. Guarded
  /// with `mounted` checks so background tool calls arriving after navigation
  /// don't attempt to push a dialog onto a disposed route.
  Future<AskUserChoiceResponse?> _presentAskUserChoiceDialog(
    AskUserChoiceRequest request,
  ) async {
    if (!mounted) return null;
    final result = await showChoiceInputDialog(
      context: context,
      title: request.title,
      description: request.description,
      options: request.options
          .map(
            (option) => ChoiceInputOption(
              value: option.value,
              label: option.label,
              description: option.description,
            ),
          )
          .toList(growable: false),
      allowCustomInput: request.allowCustomInput,
      confirmLabel: request.confirmLabel,
      cancelLabel: request.cancelLabel,
      customOptionLabel: request.customOptionLabel,
      customInputHint: request.customInputHint,
    );
    if (result == null) return null;
    return AskUserChoiceResponse(
      value: result.value,
      isCustom: result.isCustom,
    );
  }

  void _handleSessionControllerChanged() {
    if (!mounted) {
      return;
    }
    final sessionController = _observedSessionController;
    _scheduleSessionControllerUiSync();
    _processMessageQueueIfNeeded(sessionController);
  }

  void _scheduleSessionControllerUiSync() {
    if (_sessionControllerUiSyncQueued) {
      return;
    }
    _sessionControllerUiSyncQueued = true;
    unawaited(
      _awaitEndOfFrame().then((_) {
        _sessionControllerUiSyncQueued = false;
        if (!mounted) {
          return;
        }
        final sessionController = _observedSessionController;
        _syncComposerDraftForSession(sessionController?.currentSessionId);
        _syncTranscriptPreparation(sessionController?.currentSession);
        _syncEditorTabsForSession(sessionController?.currentSessionId);
      }),
    );
  }

  Future<void> _processMessageQueueIfNeeded(
    AiSessionController? sessionController,
  ) async {
    if (sessionController == null || _submittingSessionId != null) return;
    // Reentrancy guard: prevent overlapping async invocations caused by
    // multiple rapid _handleSessionControllerChanged calls during the
    // debounce window.
    if (_processingQueueInProgress) return;
    _processingQueueInProgress = true;
    try {
      // Add a small delay to debounce execution in case the AI phase is settling
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || _submittingSessionId != null) return;

      for (final session in sessionController.sessions) {
        final sessionId = session.id;
        final phase = _displaySendPhaseForSession(sessionController, sessionId);
        if (phase == AiSendPhase.idle && _submittingSessionId != sessionId) {
          final q = _queuedMessagesBySessionId[sessionId];
          if (q != null && q.isNotEmpty) {
            final nextMessage = q.removeAt(0);
            if (q.isEmpty) {
              _queuedMessagesBySessionId.remove(sessionId);
            }
            // Re-check guards after dequeue to avoid double-submit when
            // another concurrent path has already started a submission.
            if (_submittingSessionId != null) break;
            final nextPhase = _displaySendPhaseForSession(
              sessionController,
              sessionId,
            );
            if (nextPhase == AiSendPhase.idle) {
              _submitTextToSession(
                sessionId,
                nextMessage.text,
                nextMessage.attachments,
                additionalSystemReminders: nextMessage.systemReminders,
                selectedSkillMetadata: nextMessage.skillMetadata,
              );
            }
            break; // Process one at a time across all sessions
          }
        }
      }
    } finally {
      _processingQueueInProgress = false;
    }
  }

  bool _shouldPrepareTranscript(AiSession? session) {
    // Only trigger the elegant transition overlay for medium-to-large transcripts.
    // For small chats (< 15 messages), the layout jump is non-existent to minimal,
    // so we skip the overlay entirely to avoid "flash" (一闪而过) effects.
    return session != null && session.messages.length >= 15;
  }

  bool _isPreparingTranscriptForSession(AiSession? session) {
    return session != null && _preparingTranscriptSessionId == session.id;
  }

  void _syncTranscriptPreparation(AiSession? session) {
    final nextSessionId = session?.id;
    if (_activeTranscriptSessionId == nextSessionId) {
      return;
    }
    _activeTranscriptSessionId = nextSessionId;
    _transcriptPreparationGeneration += 1;
    final generation = _transcriptPreparationGeneration;
    if (!_shouldPrepareTranscript(session) || nextSessionId == null) {
      if (_preparingTranscriptSessionId == null) {
        return;
      }
      setState(() {
        _preparingTranscriptSessionId = null;
      });
      return;
    }
    setState(() {
      _preparingTranscriptSessionId = nextSessionId;
    });
    _scheduleTranscriptReveal(
      generation: generation,
      expectedSessionId: nextSessionId,
    );
  }

  // Frame-driven placeholder dismissal. Instead of a wall-clock delay we
  // wait for [_transcriptPreparationFrameBudget] consecutive post-frame
  // callbacks — by that point the ListView has completed its first layout
  // and the forced scroll-to-bottom has executed, so the transition fades
  // exactly when there is something real to reveal. A hard timeout still
  // forces the reveal after [_transcriptPreparationMaxWait] to guarantee
  // the UI never hangs in the placeholder state.
  void _scheduleTranscriptReveal({
    required int generation,
    required String expectedSessionId,
  }) {
    final stopwatch = Stopwatch()..start();

    void finish() {
      if (!mounted ||
          generation != _transcriptPreparationGeneration ||
          _preparingTranscriptSessionId != expectedSessionId) {
        return;
      }
      setState(() {
        if (_preparingTranscriptSessionId == expectedSessionId) {
          _preparingTranscriptSessionId = null;
        }
      });
    }

    void scheduleNextFrame(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _transcriptPreparationGeneration ||
            _preparingTranscriptSessionId != expectedSessionId) {
          return;
        }
        if (remainingFrames <= 0 ||
            stopwatch.elapsed >= _transcriptPreparationMaxWait) {
          finish();
          return;
        }
        scheduleNextFrame(remainingFrames - 1);
      });
    }

    scheduleNextFrame(_transcriptPreparationFrameBudget);

    // Safety net in case post-frame callbacks stop firing (e.g. the route
    // is in the background). Use the scheduler's timeout guarantees via a
    // microtask-driven timer. This never fires before the frame callbacks
    // unless the frame pipeline truly stalls.
    Future<void>.delayed(_transcriptPreparationMaxWait, finish);
  }

  String _composerDraftKeyForSessionId(String? sessionId) {
    final normalized = sessionId?.trim() ?? '';
    return normalized.isEmpty ? _detachedComposerDraftSessionKey : normalized;
  }

  void _removeComposerDraftForSession(String? sessionId) {
    _composerDraftsBySessionId.remove(_composerDraftKeyForSessionId(sessionId));
  }

  void _storeComposerDraftForSession(
    String? sessionId, {
    String? text,
    List<_ComposerAttachmentDraft>? attachments,
  }) {
    final resolvedText = text ?? _composerController.text;
    final resolvedAttachments = List<_ComposerAttachmentDraft>.from(
      attachments ?? _pendingAttachments,
    );
    if (resolvedText.trim().isEmpty && resolvedAttachments.isEmpty) {
      _removeComposerDraftForSession(sessionId);
      return;
    }
    _composerDraftsBySessionId[_composerDraftKeyForSessionId(
      sessionId,
    )] = _ComposerDraftState(
      text: resolvedText,
      attachments: resolvedAttachments,
    );
  }

  bool _sameComposerAttachments(
    List<_ComposerAttachmentDraft> left,
    List<_ComposerAttachmentDraft> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].filePath != right[index].filePath ||
          left[index].sizeBytes != right[index].sizeBytes) {
        return false;
      }
    }
    return true;
  }

  void _syncComposerDraftForSession(String? nextSessionId) {
    if (_activeComposerSessionId == nextSessionId) {
      return;
    }
    final previousSessionId = _activeComposerSessionId;
    final currentText = _composerController.text;
    final currentAttachments = List<_ComposerAttachmentDraft>.from(
      _pendingAttachments,
    );
    final shouldTransferDetachedDraft =
        (previousSessionId?.trim().isEmpty ?? true) &&
        (nextSessionId?.trim().isNotEmpty ?? false) &&
        !_composerDraftsBySessionId.containsKey(
          _composerDraftKeyForSessionId(nextSessionId),
        );
    final shouldPreserveSubmittingDraft =
        previousSessionId != null &&
        previousSessionId == _submittingSessionId &&
        currentText.trim().isEmpty &&
        currentAttachments.isEmpty;
    if (shouldTransferDetachedDraft) {
      _storeComposerDraftForSession(
        nextSessionId,
        text: currentText,
        attachments: currentAttachments,
      );
      _removeComposerDraftForSession(null);
    } else if (!shouldPreserveSubmittingDraft) {
      _storeComposerDraftForSession(
        previousSessionId,
        text: currentText,
        attachments: currentAttachments,
      );
    }
    _activeComposerSessionId = nextSessionId;

    // 2026-04-13 BUG FIX: 当目标会话正在发送消息时，不要恢复草稿内容。
    // 草稿是在 _submitTextToSession 中保存的，用于发送失败后恢复用户输入。
    // 但在正常发送过程中，AiSessionController 状态变化会触发本方法被调用，
    // 如果此时恢复草稿，就会出现消息已发送但输入框仍显示消息内容的问题。
    final isTargetSessionSubmitting =
        nextSessionId != null && _submittingSessionId == nextSessionId;
    if (isTargetSessionSubmitting) {
      return;
    }

    final nextDraft =
        _composerDraftsBySessionId[_composerDraftKeyForSessionId(
          nextSessionId,
        )];
    final nextText = nextDraft?.text ?? '';
    final nextAttachments =
        nextDraft?.attachments ?? const <_ComposerAttachmentDraft>[];
    final attachmentsChanged = !_sameComposerAttachments(
      _pendingAttachments,
      nextAttachments,
    );
    if (_composerController.text != nextText) {
      _replaceComposerText(nextText);
    }
    if (!attachmentsChanged &&
        (!(nextText.trim().isNotEmpty || nextAttachments.isNotEmpty) ||
            !_composerCollapsed)) {
      return;
    }
    setState(() {
      _pendingAttachments = List<_ComposerAttachmentDraft>.from(
        nextAttachments,
      );
      if (nextText.trim().isNotEmpty || nextAttachments.isNotEmpty) {
        _composerCollapsed = false;
      }
    });
  }

  void _armAutoFollowToBottom({bool notifyPausedState = true}) {
    final previousPaused = _autoFollowPaused;
    _shouldAutoFollowMessages = true;
    _pendingForcedScrollToBottom = true;
    _autoFollowPaused = false;
    if (!notifyPausedState || !mounted || previousPaused == _autoFollowPaused) {
      return;
    }
    setState(() {});
  }

  /// Recomputes [_autoFollowPaused] = enabled && !following-bottom and
  /// triggers a rebuild only when the value actually changes, so the
  /// composer button visuals stay consistent with the underlying state
  /// without spamming setState on every scroll tick.
  void _syncAutoFollowPausedState() {
    if (!mounted) {
      return;
    }
    final nextPaused = _autoFollowEnabled && !_shouldAutoFollowMessages;
    if (nextPaused == _autoFollowPaused) {
      return;
    }
    // 2026-04-27 (修复): 滚动通知有时会在 ListView 的 performLayout 阶段
    // 派发（例如 viewport 在 layout 中调用 applyContentDimensions →
    // dispatchScrollStartNotification）。此时直接 setState 会触发
    // "Build scheduled during frame" 断言。当当前正处于 layout / paint /
    // 持久回调阶段时，把状态变更推迟到本帧结束后的 post-frame 回调里。
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    if (inFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final latestPaused =
            _autoFollowEnabled && !_shouldAutoFollowMessages;
        if (latestPaused == _autoFollowPaused) {
          return;
        }
        setState(() {
          _autoFollowPaused = latestPaused;
        });
      });
      return;
    }
    setState(() {
      _autoFollowPaused = nextPaused;
    });
  }

  bool _consumePendingAutoFollowRequest() {
    final shouldForce = _pendingForcedScrollToBottom;
    _pendingForcedScrollToBottom = false;
    return shouldForce;
  }

  bool _isAppLifecycleActive() {
    final lifecycleState =
        _appLifecycleState ?? WidgetsBinding.instance.lifecycleState;
    return lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed;
  }

  bool _shouldDeferAutoFollowScheduling() {
    return !_isAppLifecycleActive() || _resumeAutoFollowSuppressionFrames > 0;
  }

  void _scheduleResumeAutoFollowSync() {
    if (_resumeAutoFollowSyncQueued) {
      return;
    }
    _resumeAutoFollowSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeAutoFollowSyncQueued = false;
      if (!mounted) {
        return;
      }
      if (_resumeAutoFollowSuppressionFrames > 0) {
        _resumeAutoFollowSuppressionFrames -= 1;
        _scheduleResumeAutoFollowSync();
        return;
      }
      if (!_isAppLifecycleActive()) {
        return;
      }
      _scheduleScrollToBottom(
        force: _pendingForcedScrollToBottom,
        allowSettlePasses: false,
      );
    });
  }

  void _scheduleAutoFollowIfNeeded({
    bool consumePendingRequest = false,
    bool animated = true,
    bool allowSettlePasses = true,
  }) {
    if (_shouldDeferAutoFollowScheduling()) {
      return;
    }
    final shouldForce = consumePendingRequest
        ? _consumePendingAutoFollowRequest()
        : _pendingForcedScrollToBottom;
    if (!_autoFollowEnabled && !shouldForce) {
      return;
    }
    if (!_shouldAutoFollowMessages && !shouldForce) {
      return;
    }
    _scheduleScrollToBottom(
      force: shouldForce,
      animated: animated,
      allowSettlePasses: allowSettlePasses,
    );
  }

  void _handleMessageScroll() {
    final nextValue = _isNearBottom();
    if (!nextValue) {
      return;
    }
    if (!_autoFollowEnabled) {
      return;
    }
    if (!_shouldAutoFollowMessages) {
      _shouldAutoFollowMessages = true;
    }
    if (_pendingForcedScrollToBottom) {
      _pendingForcedScrollToBottom = false;
    }
    _syncAutoFollowPausedState();
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    if (!mounted) {
      return false;
    }
    final explicitUserScrollStart =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final explicitUserScrollUpdate =
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    final explicitUserOverscroll =
        notification is OverscrollNotification &&
        notification.dragDetails != null;
    final explicitUserDirectionChange =
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    final explicitUserScroll =
        explicitUserScrollStart ||
        explicitUserScrollUpdate ||
        explicitUserOverscroll ||
        explicitUserDirectionChange;
    final userScrollEnded =
        notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);
    if (explicitUserScroll) {
      _userScrollInProgress = true;
    } else if (userScrollEnded) {
      _userScrollInProgress = false;
    }
    if (_programmaticAutoFollowScrollInProgress) {
      if (!explicitUserScroll) {
        return false;
      }
      _cancelProgrammaticAutoFollowScroll(
        keepPixels: notification.metrics.pixels,
      );
    }
    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final isNearBottom = distanceToBottom <= _autoFollowDistanceThreshold;
    if (!_autoFollowEnabled && explicitUserScroll) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    final userScrolledAwayFromBottom = !isNearBottom && explicitUserScroll;
    if (userScrolledAwayFromBottom) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    if (userScrollEnded &&
        _autoFollowEnabled &&
        (_pendingForcedScrollToBottom || _queuedForcedScrollToBottom)) {
      _scheduleScrollToBottom(force: true, animated: true);
    }
    if (isNearBottom && _autoFollowEnabled) {
      _shouldAutoFollowMessages = true;
    }
    _syncAutoFollowPausedState();
    return false;
  }

  void _selectSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
  }

  /// Wires the macOS application menu's "Settings…" item to the in-app
  /// navigation. On non-macOS platforms this is a no-op.
  ///
  /// The Swift side (`AppDelegate.openSettings:`) invokes a single method
  /// `openSettings` on this channel. We respond by selecting the Settings
  /// pane, which also updates the left navigation rail because the rail is
  /// driven by `_selectedSection`.
  void _initNativeMenuChannel() {
    if (!Platform.isMacOS) return;
    const channel = MethodChannel('openhand/menu');
    _macosMenuChannel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openSettings':
          if (mounted) {
            _selectSection(AppSection.settings);
          }
          return null;
        default:
          return null;
      }
    });
  }

  void _toggleAutoFollow() {
    // When auto-follow is ON but paused (user scrolled up so new messages
    // stop following), a tap should RESUME — re-arm following and jump to
    // bottom — instead of turning the mode off. Turning the mode off in
    // this state is almost always unintended and would lose the user's
    // preference. Only a second tap (while actively following at the
    // bottom) actually disables the mode.
    if (_autoFollowEnabled && _autoFollowPaused) {
      setState(() {
        _autoFollowPaused = false;
      });
      _armAutoFollowToBottom(notifyPausedState: false);
      _scheduleScrollToBottom(force: true, animated: true);
      return;
    }
    final nextValue = !_autoFollowEnabled;
    setState(() {
      _autoFollowEnabled = nextValue;
      if (!nextValue) {
        _clearPendingAutoFollowState();
        _autoFollowPaused = false;
      } else {
        _armAutoFollowToBottom(notifyPausedState: false);
      }
    });
    if (nextValue) {
      _scheduleScrollToBottom(force: true, animated: true);
    }
  }

  bool _handleGlobalShortcutKeyEvent(KeyEvent event) {
    if (!mounted ||
        (_selectedSection != AppSection.workspace &&
            _selectedSection != AppSection.hardnessSession) ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    // 2026-04-26: Removed the previous `currentRoute != focusedRoute` check.
    // It silently swallowed shortcuts whenever the focused widget lived in
    // an overlay (e.g. @-mention, skill picker) or a child Navigator, which
    // surfaced as the composer "border flash and nothing happens" bug. We
    // now rely solely on section + editable-focus gating, which is enough
    // because we only act on shortcuts that explicitly target the composer
    // (sendMessage / toggleComposer) when an editable widget has focus.
    final isEditableFocused = _isEditableTextFocused(focusContext);
    final settingsController = context.read<SettingsController>();
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    final shortcutAction = _matchShortcutAction(
      settingsController.shortcutBindings,
      pressedKeyIds,
    );
    if (shortcutAction == null) {
      return false;
    }
    if (isEditableFocused) {
      final composerShortcutAllowed =
          _composerFocusNode.hasFocus &&
          (shortcutAction == OpenHandShortcutAction.sendMessage ||
              shortcutAction == OpenHandShortcutAction.toggleComposer);
      final hardnessComposerShortcutAllowed =
          _selectedSection == AppSection.hardnessSession &&
          _hardnessSessionPaneController.shouldAllowEditableShortcut(
            shortcutAction,
          );
      if (!composerShortcutAllowed && !hardnessComposerShortcutAllowed) {
        return false;
      }
      // 2026-04-28: Single-source-of-truth dispatch.
      //
      // Returning true from a HardwareKeyboard handler does NOT skip the
      // focus-tree dispatch in the current Flutter pipeline – BOTH this
      // HW handler AND the focused FocusNode.onKeyEvent fire for the
      // same key press.  Previously each path *also* performed the
      // action, so the composer toggle ran twice and visually cancelled
      // out (the recurring "press Ctrl+P, border flashes, nothing
      // happens" bug).  The fix:
      //
      //   * This HW handler always performs the action exactly once and
      //     returns true (which is enough to suppress macOS'
      //     DefaultTextEditingShortcuts at the platform layer).
      //   * The composer FocusNode.onKeyEvent merely returns
      //     KeyEventResult.handled to swallow the event in the focus
      //     tree without re-running the action.
      unawaited(_performShortcutAction(shortcutAction));
      return true;
    }
    unawaited(_performShortcutAction(shortcutAction));
    return true;
  }

  KeyEventResult _handleComposerFocusNodeKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (!mounted ||
        _selectedSection != AppSection.workspace ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    // Cmd/Ctrl+V image paste: probe the OS clipboard for image bytes in
    // parallel with the platform's text-paste path. If image bytes are
    // present we add them as an attachment; if only text is on the
    // clipboard the TextField's normal paste continues unaffected.
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      final hw = HardwareKeyboard.instance;
      final hasModifier = Platform.isMacOS
          ? hw.isMetaPressed
          : hw.isControlPressed;
      if (hasModifier &&
          !hw.isShiftPressed &&
          !hw.isAltPressed) {
        unawaited(_tryPasteImageFromClipboard());
        // Intentionally fall through (return ignored) so the TextField can
        // still paste text if the clipboard happens to carry both.
      }
    }
    // Escape dismisses the @ mention overlay if it is showing.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final composerState = _composerPanelKey.currentState;
      if (composerState != null && composerState._atMentionOverlay != null) {
        composerState._userDismissAtMentionOverlay();
        return KeyEventResult.handled;
      }
      if (composerState != null && composerState._skillPickerOverlay != null) {
        composerState._userDismissSkillPickerOverlay();
        return KeyEventResult.handled;
      }
    }
    // When the skill picker overlay is visible, let Up/Down move the
    // selection highlight and Enter commit the current selection.  This
    // mirrors Codex / GitHub Copilot Chat behaviour and makes skill lookup
    // an efficient keyboard-only workflow.
    final composerState = _composerPanelKey.currentState;
    if (composerState != null && composerState._skillPickerOverlay != null) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        composerState._moveSkillPickerSelection(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        composerState._moveSkillPickerSelection(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (composerState._commitSkillPickerSelection()) {
          return KeyEventResult.handled;
        }
      }
    }
    // 2026-04-28: Composer shortcut consumption (no action).
    //
    // _handleGlobalShortcutKeyEvent (HardwareKeyboard) is the sole
    // executor of send-message / toggle-composer.  Here we only need to
    // CONSUME the matching keystroke in the focus tree so that
    // DefaultTextEditingShortcuts (which maps Ctrl+P to MoveSelectionUp
    // on macOS and was the cause of the visible "border flash") cannot
    // fire.  Returning KeyEventResult.handled stops focus-tree dispatch
    // without invoking the action a second time.
    final settingsController = context.read<SettingsController>();
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    final shortcutAction = _matchShortcutAction(
      settingsController.shortcutBindings,
      pressedKeyIds,
    );
    if (shortcutAction == OpenHandShortcutAction.sendMessage ||
        shortcutAction == OpenHandShortcutAction.toggleComposer) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isEditableTextFocused(BuildContext? focusContext) {
    if (focusContext == null) {
      return false;
    }
    try {
      // Check the focused widget itself.
      if (focusContext.widget is EditableText ||
          focusContext.widget is TextField ||
          focusContext.widget is TextFormField) {
        return true;
      }
      // Check whether the focused widget lives inside an editable text widget
      // (e.g. the internal Focus node created by EditableText).
      if (focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
          focusContext.findAncestorWidgetOfExactType<TextField>() != null) {
        return true;
      }
      // NOTE: Do NOT walk child elements here.  The previous recursive visitor
      // found TextField / EditableText widgets that merely *exist* in the
      // subtree (e.g. the composer sitting inside the Scaffold) even when they
      // do not hold focus, causing false positives that silently block all
      // shortcuts when focus is on the global shortcut node or any other
      // non-editable widget.
    } catch (_) {
      // If any error occurs during focus context inspection, assume focus
      // is on an editable field to avoid blocking text input.
      return true;
    }
    return false;
  }

  OpenHandShortcutAction? _matchShortcutAction(
    Map<OpenHandShortcutAction, List<int>> bindings,
    Set<int> pressedKeyIds,
  ) {
    if (pressedKeyIds.isEmpty) {
      return null;
    }
    for (final action in OpenHandShortcutAction.values) {
      final shortcutKeyIds = normalizeShortcutKeyIds(
        bindings[action] ?? const <int>[],
      );
      if (shortcutKeyIds.isEmpty) {
        continue;
      }
      if (shortcutKeyIds.length != pressedKeyIds.length) {
        continue;
      }
      if (pressedKeyIds.containsAll(shortcutKeyIds)) {
        return action;
      }
    }
    return null;
  }

  Future<void> _performShortcutAction(OpenHandShortcutAction action) async {
    final sessionController = context.read<AiSessionController>();
    if (_selectedSection == AppSection.hardnessSession) {
      switch (action) {
        case OpenHandShortcutAction.sendMessage:
        case OpenHandShortcutAction.toggleComposer:
        case OpenHandShortcutAction.toggleAutoFollow:
          await _hardnessSessionPaneController.invokeShortcut(action);
          return;
        case OpenHandShortcutAction.selectPreviousSession:
          await _cycleSessionSelection(-1);
          return;
        case OpenHandShortcutAction.selectNextSession:
          await _cycleSessionSelection(1);
          return;
        case OpenHandShortcutAction.selectPreviousModel:
        case OpenHandShortcutAction.selectNextModel:
          return;
      }
    }

    switch (action) {
      case OpenHandShortcutAction.sendMessage:
        if (_canStopCurrentSessionResponse(sessionController)) {
          await _stopResponding();
          return;
        }
        _composerPanelKey.currentState?._injectReferencesIntoText();
        await _sendMessage();
        return;
      case OpenHandShortcutAction.toggleComposer:
        _setComposerCollapsedState(
          !_composerCollapsed,
          requestFocusWhenExpanded: _composerCollapsed,
        );
        return;
      case OpenHandShortcutAction.selectPreviousModel:
        _cycleSelectedModel(-1);
        return;
      case OpenHandShortcutAction.selectNextModel:
        _cycleSelectedModel(1);
        return;
      case OpenHandShortcutAction.toggleAutoFollow:
        _toggleAutoFollow();
        return;
      case OpenHandShortcutAction.selectPreviousSession:
        await _cycleSessionSelection(-1);
        return;
      case OpenHandShortcutAction.selectNextSession:
        await _cycleSessionSelection(1);
        return;
    }
  }

  void _cycleSelectedModel(int delta) {
    final settingsController = context.read<SettingsController>();
    final entries = settingsController.flatModelEntries;
    if (entries.isEmpty) return;

    final currentProvider = settingsController.selectedAiModel;
    final currentProviderId = currentProvider?.id;
    final currentModelId = currentProvider?.modelId;

    var currentIndex = -1;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].providerConfigId == currentProviderId &&
          entries[i].modelId == currentModelId) {
        currentIndex = i;
        break;
      }
    }
    final baseIndex = currentIndex >= 0 ? currentIndex : 0;
    final nextIndex = (baseIndex + delta + entries.length) % entries.length;
    final next = entries[nextIndex];
    unawaited(
      settingsController.updateProviderActiveModel(
        next.providerConfigId,
        next.modelId,
      ),
    );
  }

  Future<void> _cycleSessionSelection(int delta) async {
    final sessionController = context.read<AiSessionController>();
    final sessions = sessionController.sessions;
    if (sessions.isEmpty) {
      return;
    }
    final currentSessionId = sessionController.currentSessionId;
    final currentIndex = sessions.indexWhere(
      (item) => item.id == currentSessionId,
    );
    final baseIndex = currentIndex >= 0 ? currentIndex : 0;
    final nextIndex = (baseIndex + delta + sessions.length) % sessions.length;
    await _activateSession(sessions[nextIndex].id);
  }

  Future<void> _activateSession(String sessionId) async {
    final sessionController = context.read<AiSessionController>();
    if (sessionController.currentSessionId == sessionId &&
        _selectedSection == AppSection.workspace) {
      return;
    }
    final activationGeneration = ++_sessionActivationGeneration;
    await _awaitEndOfFrame();
    if (!mounted || activationGeneration != _sessionActivationGeneration) {
      return;
    }
    await sessionController.selectSession(sessionId);
    if (!mounted || activationGeneration != _sessionActivationGeneration) {
      return;
    }
    await _awaitEndOfFrame();
    if (!mounted || activationGeneration != _sessionActivationGeneration) {
      return;
    }
    if (sessionController.currentSessionId != sessionId) {
      return;
    }
    final session = sessionController.currentSession;
    if (session != null) {
      _tryRestoreSessionModel(session);
    }
    if (_selectedSection != AppSection.workspace) {
      setState(() {
        _selectedSection = AppSection.workspace;
      });
    }
    _clearPendingAutoFollowState();
    _armAutoFollowToBottom();
    _scheduleScrollToBottom(force: true);
  }

  /// Attempts to restore the model selection from the session's persisted
  /// [AiSession.lastUsedModelId] and [AiSession.lastUsedModelLabel].
  /// Falls back to the global default if the stored model is no longer available.
  void _tryRestoreSessionModel(AiSession session) {
    final storedProviderId = session.lastUsedModelId;
    final storedModelId = session.lastUsedModelLabel;
    if (storedProviderId == null ||
        storedProviderId.isEmpty ||
        storedModelId == null ||
        storedModelId.isEmpty) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final providers = settingsController.aiModels;
    // Find the provider config that matches storedProviderId.
    final provider = providers.cast<AiModelConfig?>().firstWhere(
      (p) => p!.id == storedProviderId,
      orElse: () => null,
    );
    if (provider == null) {
      // Provider no longer exists — keep the current global default.
      return;
    }
    // Check if the stored model ID is still in the provider's known models.
    final allIds = provider.allModelIds;
    if (allIds.isNotEmpty && !allIds.contains(storedModelId)) {
      // Model was removed; just select the provider (uses its current modelId).
      settingsController.updateSelectedAiModel(storedProviderId);
      return;
    }
    // Restore both the provider selection and the specific model.
    settingsController.updateProviderActiveModel(
      storedProviderId,
      storedModelId,
    );
  }

  Future<String?> _showThreadTemplateDialog() async {
    return showAnimatedDialog<String>(
      context: context,
      builder: (dialogContext) {
        final sessionController = dialogContext.read<AiSessionController>();
        return _ThreadTemplateDialog(templates: sessionController.templates);
      },
    );
  }

  Future<MachineExpertDialogResult?> _showMachineExpertDialog({
    String? initialTask,
  }) async {
    final settingsController = context.read<SettingsController>();
    final selectedModel = settingsController.selectedAiModel;
    return showAnimatedDialog<MachineExpertDialogResult>(
      context: context,
      builder: (context) => MachineExpertDialog(
        initialTask: initialTask,
        availableModels: settingsController.aiModels,
        recentModelSelections: settingsController.recentModelSelections,
        initialSelectedModelConfigId: selectedModel?.id,
        initialSelectedModelId: selectedModel?.modelId,
      ),
    );
  }

  Future<void> _applyMachineExpertModelSelection(
    MachineExpertDialogResult result,
  ) async {
    final providerConfigId = result.selectedModelConfigId?.trim();
    final modelId = result.selectedModelId?.trim();
    if (providerConfigId == null ||
        providerConfigId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final providerExists = settingsController.aiModels.any(
      (item) =>
          item.id == providerConfigId && item.allModelIds.contains(modelId),
    );
    if (!providerExists) {
      return;
    }
    await settingsController.updateProviderActiveModel(
      providerConfigId,
      modelId,
    );
    await settingsController.addRecentModelSelection(providerConfigId, modelId);
    final currentSessionId = sessionController.currentSessionId;
    if (currentSessionId != null) {
      await sessionController.updateSessionLastUsedModel(
        currentSessionId,
        providerConfigId: providerConfigId,
        modelId: modelId,
      );
    }
  }

  Future<bool> _createSession({
    required String templateId,
    AiSessionRuntimeContext? runtimeContext,
    AiSessionMode initialMode = AiSessionMode.chat,
    bool initialFullAccessPermission = false,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final resolvedRuntimeContext =
        runtimeContext ?? await _buildRuntimeContext();
    if (!mounted) {
      return false;
    }
    final created = await sessionController.createSession(
      templateId: templateId,
      runtimeContext: resolvedRuntimeContext,
      mode: initialMode,
      fullAccessPermission: initialFullAccessPermission,
    );
    if (!mounted) {
      return false;
    }
    if (!created) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = sessionController.lastErrorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
      );
      return false;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    return true;
  }

  Future<bool> _createSessionFromDialog({
    AiSessionRuntimeContext? runtimeContext,
  }) async {
    final templateId = await _showThreadTemplateDialog();
    if (!mounted || templateId == null) {
      return false;
    }
    if (templateId == 'machine_expert') {
      final result = await _showMachineExpertDialog();
      if (!mounted || result == null) {
        return false;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
      );
      if (created && mounted) {
        await _applyMachineExpertModelSelection(result);
        _replaceComposerText(result.toPrompt());
        await _sendMessage();
      }
      return created;
    }
    if (templateId == 'programming_expert') {
      final sessionController = context.read<AiSessionController>();
      if (kDebugMode) {
        debugPrint(
          '[pe.recents] dialog-open#A sessions=${sessionController.sessions.length}',
        );
      }
      final recentPathCache = _collectProgrammingExpertRecentPaths(
        sessionController.sessions,
      );
      final settingsController = context.read<SettingsController>();
      final currentWorkspacePath =
          _preferredProgrammingExpertProjectRootCandidate(
            sessionController: sessionController,
            runtimeContext: runtimeContext,
          ) ??
          '';
      final peConfig = await showAnimatedDialog<_ProgrammingExpertConfig>(
        context: context,
        builder: (context) => _ProgrammingExpertProjectDialog(
          settingsController: settingsController,
          recentPathCache: recentPathCache,
          currentWorkspacePath: currentWorkspacePath,
        ),
      );
      if (!mounted || peConfig == null) {
        return false;
      }
      // Build runtime context with the PE project root as the working
      // directory so the AI's tool calls (Read, Glob, Grep, Bash, etc.)
      // resolve relative paths against the user's project, not the
      // OpenHand application directory.
      final peRuntimeContext = await _buildRuntimeContext(
        workingDirectory: peConfig.projectRoot,
      );
      if (!mounted) {
        return false;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: peRuntimeContext,
      );
      if (created && mounted) {
        final currentSession = sessionController.currentSession;
        if (currentSession != null) {
          final ok = await sessionController.updateSessionMetadata(
            currentSession.id,
            <String, Object?>{
              'programming_expert_config': <String, Object?>{
                'project_root': peConfig.projectRoot,
                'language': peConfig.language,
                'sdk_path': peConfig.sdkPath,
                'lsp_path': peConfig.lspPath,
              },
            },
          );
          if (kDebugMode) {
            debugPrint(
              '[pe.recents] metadata-saved#A session=${currentSession.id} ok=$ok '
              'projectRoot=${peConfig.projectRoot}',
            );
          }
        }
      }
      return created;
    }
    if (templateId == 'hardness_engineering') {
      final settingsCtrl = context.read<SettingsController>();
      final config = await showAnimatedDialog<HardnessSessionConfig>(
        context: context,
        builder: (context) =>
            HardnessEngineeringDialog(settingsController: settingsCtrl),
      );
      if (!mounted || config == null) {
        return false;
      }
      // Initialize persistence directory structure (non-blocking on error).
      try {
        await config.initializePersistenceDirectories();
      } catch (error, stack) {
        silentLog('openhand_home_page', 'initialize HE persistence directories', error, stack);
      }
      if (!mounted) return false;
      // Launch the program-driven HE session inside the app's content pane
      // instead of a full-screen modal, so the navigation sidebar stays
      // visible and the user can switch between sections freely.
      _activeHardnessOrchestrator?.removeListener(
        _onHardnessOrchestratorChanged,
      );
      _activeHardnessOrchestrator?.cancel();
      _activeHardnessOrchestrator?.dispose();
      final orchestrator = HardnessOrchestrator(config);
      orchestrator.fullAccessPermission = _heFullAccessPermission;
      orchestrator.onPhaseApprovalRequired = _handlePhaseApprovalRequired;
      _wireHardnessApiMode(orchestrator);
      final now = DateTime.now().toUtc();
      final record = HardnessSessionRecord(
        id: const Uuid().v4(),
        title: _hardnessTitleFromTask(config.task),
        config: config,
        statusValue: HardnessOrchestratorStatus.running.name,
        createdAt: now,
        updatedAt: now,
      );
      // 2026-04-13: Await initial save to ensure the record is persisted
      // before starting the orchestrator, preventing data loss if the app
      // closes before the async save completes.
      try {
        await _hardnessSessionStore.save(record);
      } catch (_) {
        // Log but continue - failing to persist should not block execution.
      }
      orchestrator.addListener(_onHardnessOrchestratorChanged);
      _cacheHardnessShellState(orchestrator);
      setState(() {
        _activeHardnessOrchestrator = orchestrator;
        _activeHardnessConfig = config;
        _persistedHardnessSession = record;
        _selectedSection = AppSection.hardnessSession;
      });
      unawaited(orchestrator.start());
      unawaited(_generateHardnessAutoTitle(record.id, config.task));
      return true;
    }
    return _createSession(
      templateId: templateId,
      runtimeContext: runtimeContext,
      initialMode: AiSessionMode.fromStorage(
        context.read<SettingsController>().aiDefaultSessionMode,
      ),
      initialFullAccessPermission: context
          .read<SettingsController>()
          .aiDefaultFullAccessPermission,
    );
  }

  HardnessSessionRecord _snapshotHardnessRecord(
    HardnessSessionRecord base,
    HardnessOrchestrator orchestrator,
  ) {
    return base.copyWith(
      config: orchestrator.config,
      statusValue: orchestrator.status.name,
      updatedAt: DateTime.now().toUtc(),
      phaseLogs: orchestrator.phaseLogSnapshots,
      errorMessage: orchestrator.errorMessage,
      currentPhaseValue: orchestrator.currentPhase?.storageValue,
      manualPhaseInputRequested: orchestrator.manualPhaseInputRequested,
      queuedManualPhaseInput: orchestrator.queuedManualPhaseInput,
      queuedManualPhaseInputPhaseValue:
          orchestrator.queuedManualPhaseInputPhase?.storageValue,
    );
  }

  void _scheduleHardnessSessionSave(
    HardnessSessionRecord record, {
    bool immediate = false,
  }) {
    _hardnessSessionSaveTimer?.cancel();
    if (immediate) {
      unawaited(_hardnessSessionStore.save(record).catchError((_) {}));
      return;
    }
    _hardnessSessionSaveTimer = Timer(_hardnessSessionPersistenceDebounce, () {
      _hardnessSessionSaveTimer = null;
      unawaited(_hardnessSessionStore.save(record).catchError((_) {}));
    });
  }

  HardnessSessionRecord _normalizeRestoredHardnessRecord(
    HardnessSessionRecord record,
  ) {
    final interruptedByAppClose =
        record.status == HardnessOrchestratorStatus.running ||
        (record.status == HardnessOrchestratorStatus.cancelled &&
            record.errorMessage ==
                'Session was interrupted because the app closed.');
    if (!interruptedByAppClose) {
      return record;
    }

    HardnessPhase? resumePhase;
    final normalizedPhaseLogs = record.phaseLogs
        .map((entry) {
          final isInterruptedPhase =
              entry.status == HardnessPhaseStatus.running ||
              entry.status == HardnessPhaseStatus.paused ||
              (resumePhase == null &&
                  entry.status == HardnessPhaseStatus.pending);
          if (!isInterruptedPhase) {
            return entry;
          }
          final nextLines = List<String>.from(entry.lines);
          final restoreMessage = entry.status == HardnessPhaseStatus.running
              ? '⚠ 应用关闭后，该阶段已暂停；恢复执行前需要重新审批。'
              : '⚠ 应用关闭后，会话已恢复；继续执行前需要重新审批。';
          if (!nextLines.contains(restoreMessage)) {
            if (nextLines.isNotEmpty && nextLines.last.isNotEmpty) {
              nextLines.add('');
            }
            nextLines.add(restoreMessage);
          }
          resumePhase ??= entry.phase;
          return entry.copyWith(
            statusValue: HardnessPhaseStatus.paused.name,
            lines: nextLines,
          );
        })
        .toList(growable: false);

    return record.copyWith(
      statusValue: HardnessOrchestratorStatus.idle.name,
      updatedAt: DateTime.now().toUtc(),
      phaseLogs: normalizedPhaseLogs,
      errorMessage: null,
      currentPhaseValue: resumePhase?.storageValue,
    );
  }

  /// Wires API-mode (URL) support on a [HardnessOrchestrator] so that phases
  /// configured with [HardnessExecutionMode.url] can run through the AI
  /// chat infrastructure instead of a CLI tool.
  void _wireHardnessApiMode(HardnessOrchestrator orchestrator) {
    final aiCtrl = context.read<AiSessionController>();
    orchestrator.apiPhaseRunner = HardnessApiPhaseRunner(
      chatClient: aiCtrl.chatClient,
      toolRuntimeService: aiCtrl.toolRuntimeService,
      templateRepository: aiCtrl.templateRepository,
      confirmWriteCommand: _confirmHardnessApiWriteCommand,
    );
    orchestrator.resolveAiModelConfig = (String configId) {
      final settingsCtrl = context.read<SettingsController>();
      try {
        return settingsCtrl.aiModels.firstWhere((m) => m.id == configId);
      } catch (_) {
        return null;
      }
    };
    orchestrator.buildApiRuntimeContext = (String workingDirectory) {
      return _buildRuntimeContext(workingDirectory: workingDirectory);
    };
  }

  /// Loads the last-persisted Hardness Engineering session record from disk
  /// and displays it in the navigation sidebar.
  Future<void> _loadPersistedHardnessSession() async {
    try {
      final record = await _hardnessSessionStore.load();
      if (!mounted || record == null) {
        return;
      }
      final migratedRecord = _migrateLegacyHardnessAutoRewrittenModels(record);
      final effectiveRecord = _normalizeRestoredHardnessRecord(migratedRecord);
      if (effectiveRecord != record) {
        _scheduleHardnessSessionSave(effectiveRecord, immediate: true);
      }
      _activeHardnessOrchestrator?.removeListener(
        _onHardnessOrchestratorChanged,
      );
      final restoredOrchestrator = HardnessOrchestrator(effectiveRecord.config);
      restoredOrchestrator.fullAccessPermission = _heFullAccessPermission;
      restoredOrchestrator.onPhaseApprovalRequired =
          _handlePhaseApprovalRequired;
      _wireHardnessApiMode(restoredOrchestrator);
      restoredOrchestrator.restoreSnapshot(
        status: effectiveRecord.status,
        phaseLogs: effectiveRecord.phaseLogs,
        errorMessage: effectiveRecord.errorMessage,
        currentPhase: effectiveRecord.currentPhase,
        manualPhaseInputRequested: effectiveRecord.manualPhaseInputRequested,
        queuedManualPhaseInput: effectiveRecord.queuedManualPhaseInput,
        queuedManualPhaseInputPhase:
            effectiveRecord.queuedManualPhaseInputPhase,
      );
      restoredOrchestrator.addListener(_onHardnessOrchestratorChanged);
      _cacheHardnessShellState(restoredOrchestrator);
      setState(() {
        _persistedHardnessSession = effectiveRecord;
        _activeHardnessConfig = effectiveRecord.config;
        _activeHardnessOrchestrator = restoredOrchestrator;
      });
    } catch (e) {
      // Silently fail on restore errors
    }
  }

  /// Called whenever the active [HardnessOrchestrator] notifies listeners.
  /// Propagates status changes to the navigation tile and persisted record.
  void _onHardnessOrchestratorChanged() {
    if (!mounted) return;
    final orchestrator = _activeHardnessOrchestrator;
    final currentRecord = _persistedHardnessSession;
    if (orchestrator == null || currentRecord == null) return;
    final updatedRecord = _snapshotHardnessRecord(currentRecord, orchestrator);
    final statusChanged =
        updatedRecord.statusValue != currentRecord.statusValue;
    final awaitingApprovalChanged =
        _lastHardnessAwaitingApprovalPhase !=
        orchestrator.awaitingApprovalPhase;
    _persistedHardnessSession = updatedRecord;
    _lastHardnessAwaitingApprovalPhase = orchestrator.awaitingApprovalPhase;
    _scheduleHardnessSessionSave(
      updatedRecord,
      immediate: orchestrator.status != HardnessOrchestratorStatus.running,
    );
    if (statusChanged || awaitingApprovalChanged) {
      setState(() {});
    }
  }

  void _handleHeFullAccessToggle(bool enabled) {
    if (!mounted) return;
    if (enabled) {
      // Show confirmation dialog before enabling full access.
      _showFullAccessConfirmationDialog().then((confirmed) {
        if (confirmed && mounted) {
          setState(() {
            _heFullAccessPermission = true;
            _activeHardnessOrchestrator?.fullAccessPermission = true;
          });
        }
      });
    } else {
      setState(() {
        _heFullAccessPermission = false;
        _activeHardnessOrchestrator?.fullAccessPermission = false;
      });
    }
  }

  void _handleHeConfigChanged(HardnessSessionConfig newConfig) {
    if (!mounted) return;
    final currentRecord = _persistedHardnessSession;
    final updatedRecord = currentRecord?.copyWith(
      config: newConfig,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() {
      _activeHardnessConfig = newConfig;
      if (updatedRecord != null) {
        _persistedHardnessSession = updatedRecord;
      }
    });
    _activeHardnessOrchestrator?.updateConfig(newConfig);
    if (updatedRecord != null) {
      _scheduleHardnessSessionSave(updatedRecord);
    }
    unawaited(newConfig.initializePersistenceDirectories().catchError((_) {}));
  }

  static final RegExp _legacyHeAutoModelRewritePattern = RegExp(
    r'^ℹ 检测到旧模型标识 "([^"]+)"，已自动改用 ',
  );

  HardnessSessionRecord _migrateLegacyHardnessAutoRewrittenModels(
    HardnessSessionRecord record,
  ) {
    final recoveredModels = <HardnessPhase, String>{};
    for (final snapshot in record.phaseLogs) {
      for (final rawLine in snapshot.lines.reversed) {
        final match = _legacyHeAutoModelRewritePattern.firstMatch(
          rawLine.trim(),
        );
        if (match == null) {
          continue;
        }
        final restoredModel = match.group(1)?.trim();
        if (restoredModel == null || restoredModel.isEmpty) {
          continue;
        }
        recoveredModels[snapshot.phase] = restoredModel;
        break;
      }
    }

    if (recoveredModels.isEmpty) {
      return record;
    }

    HardnessRoleConfig restoreRoleConfig(
      HardnessRoleConfig roleConfig,
      HardnessPhase phase,
    ) {
      final restoredModel = recoveredModels[phase];
      if (restoredModel == null || restoredModel.isEmpty) {
        return roleConfig;
      }
      if (roleConfig.cliName.trim() != 'Gemini CLI') {
        return roleConfig;
      }
      if (roleConfig.modelId.trim() == restoredModel) {
        return roleConfig;
      }
      return roleConfig.copyWith(modelId: restoredModel);
    }

    final updatedConfig = record.config.copyWith(
      profilerConfig: restoreRoleConfig(
        record.config.profilerConfig,
        HardnessPhase.metaCollection,
      ),
      readerConfig: restoreRoleConfig(
        record.config.readerConfig,
        HardnessPhase.reading,
      ),
      plannerConfig: restoreRoleConfig(
        record.config.plannerConfig,
        HardnessPhase.planning,
      ),
      implementerConfig: restoreRoleConfig(
        record.config.implementerConfig,
        HardnessPhase.implementing,
      ),
      reviewerConfig: restoreRoleConfig(
        record.config.reviewerConfig,
        HardnessPhase.reviewing,
      ),
    );

    if (updatedConfig.profilerConfig == record.config.profilerConfig &&
        updatedConfig.readerConfig == record.config.readerConfig &&
        updatedConfig.plannerConfig == record.config.plannerConfig &&
        updatedConfig.implementerConfig == record.config.implementerConfig &&
        updatedConfig.reviewerConfig == record.config.reviewerConfig) {
      return record;
    }

    return record.copyWith(
      config: updatedConfig,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _handlePhaseApprovalRequired(HardnessPhase nextPhase) {
    // The orchestrator pauses, creates a completer, and sets awaitingApprovalPhase.
    // The UI banner (_HePhaseApprovalBanner) handles user interaction.
    // resolvePhaseApproval() is called from the banner's approve/reject buttons,
    // which completes the orchestrator's internal completer and unblocks the
    // pipeline. This callback only triggers a rebuild so the banner appears.
    if (mounted) setState(() {});
  }

  /// Extracts a short display title from the raw task text.
  static String _hardnessTitleFromTask(String task) {
    final firstLine = task
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => task.trim());
    if (firstLine.length <= 45) return firstLine;
    return '${firstLine.substring(0, 45)}…';
  }

  /// Asynchronously generates a concise AI title (≤20 chars) for the
  /// Hardness Engineering session and refreshes the navigation tile.
  static const String _hardnessAutoTitleSystemPrompt =
      'Generate a concise title for a software engineering task. '
      'Return a single title only. Keep it within 20 characters. '
      'No quotes. No markdown. No punctuation at the end.\n'
      'Summarize the task into a specific, human-friendly thread title.\n'
      'Prefer concrete task names over vague summaries.\n'
      'Avoid generic labels like "任务", "工程", "优化", "Task", "Engineering".';

  Future<void> _generateHardnessAutoTitle(String sessionId, String task) async {
    final settingsController = context.read<SettingsController>();
    final model = settingsController.selectedAiModel;
    if (model == null) return;

    final client = AiChatService();
    try {
      final completion = await client.sendMessage(
        model: model,
        messages: <AiChatTurn>[
          const AiChatTurn(
            role: AiChatRole.system,
            content: _hardnessAutoTitleSystemPrompt,
          ),
          AiChatTurn(role: AiChatRole.user, content: 'Task:\n$task'),
        ],
        timeout: const Duration(seconds: 20),
      );
      if (!mounted) return;
      final current = _persistedHardnessSession;
      if (current == null || current.id != sessionId) return;

      final rawTitle = completion.reply.trim();
      if (rawTitle.isEmpty) return;
      // Truncate to 20 characters maximum.
      final sanitized = rawTitle.characters.take(20).toString();
      final updated = current.copyWith(title: sanitized);
      unawaited(_hardnessSessionStore.save(updated).catchError((_) {}));
      setState(() {
        _persistedHardnessSession = updated;
      });
    } catch (_) {
      // Silent fail — title generation is non-critical.
    } finally {
      client.dispose();
    }
  }

  void _toggleInstructionSkip(String id) {
    setState(() {
      if (!_skippedInstructionIds.add(id)) {
        _skippedInstructionIds.remove(id);
      }
    });
  }

  Future<AiSessionRuntimeContext> _buildRuntimeContext({
    String? workingDirectory,
    Set<String> skippedInstructionIds = const <String>{},
  }) async {
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    final skillsController = context.read<SkillsController>();
    final mcpController = context.read<McpController>();
    final instructionsController = context.read<InstructionsController>();
    final appInfo = context.read<AppInfo>();
    final effectiveWorkingDirectory =
        workingDirectory ?? OpenHandPaths.applicationDirectoryPath();
    final gitSnapshot = await _gitSnapshotService.loadSnapshot(
      workingDirectory: effectiveWorkingDirectory,
    );
    final now = DateTime.now().toLocal();
    return AiSessionRuntimeContext(
      localeTag: settingsController.locale.toLanguageTag(),
      appVersion: appInfo.version,
      appBuildNumber: appInfo.buildNumber,
      settingsFilePath: settingsController.settingsFilePath,
      skillsStoragePath: settingsController.skillsStoragePath,
      mcpServersFilePath: settingsController.mcpServersFilePath,
      userMemoryFilePath: settingsController.userMemoryFilePath,
      compressionThresholdChars:
          settingsController.aiMessageCompressionThresholdChars,
      toolResultCompressionThresholdChars:
          settingsController.aiToolResultCompressionThresholdChars,
      toolResultCompressionEnabled:
          settingsController.aiToolResultCompressionEnabled,
      toolResultCompressionHeadTailWindowChars:
          settingsController.aiToolResultCompressionHeadTailWindowChars,
      toolResultCompressionMaxPathHits:
          settingsController.aiToolResultCompressionMaxPathHits,
      writeToolSummaryMaxChars: settingsController.aiWriteToolSummaryMaxChars,
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      maxRecentErrors: settingsController.aiMaxRecentErrors,
      maxPlanHistoryEntries: settingsController.aiMaxPlanHistoryEntries,
      maxTruncationContinuations: settingsController.aiMaxTruncationContinuations,
      estimatedCharactersPerToken: settingsController.aiEstimatedCharactersPerToken,
      maxToolOutputChars: settingsController.aiMaxToolOutputChars,
      writeConfirmationTimeoutMs: settingsController.aiWriteConfirmationTimeoutMs,
      fastPathWriteAnalysisThreshold:
          settingsController.aiFastPathWriteAnalysisThreshold,
      maxHookTextCharacters: settingsController.aiMaxHookTextCharacters,
      webFetchMaxResponseBytes: settingsController.aiWebFetchMaxResponseBytes,
      webFetchMaxRedirects: settingsController.aiWebFetchMaxRedirects,
      webFetchMaxCacheEntries: settingsController.aiWebFetchMaxCacheEntries,
      attachmentMaxInlineImageDimension:
          settingsController.aiAttachmentMaxInlineImageDimension,
      attachmentMaxTextRawBytes:
          settingsController.aiAttachmentMaxTextRawBytes,
      attachmentMaxPdfRawBytes: settingsController.aiAttachmentMaxPdfRawBytes,
      attachmentMaxImageRawBytes:
          settingsController.aiAttachmentMaxImageRawBytes,
      chatMaxStreamLineBufferBytes:
          settingsController.aiChatMaxStreamLineBufferBytes,
      imageSizeLimitBytes: settingsController.aiImageSizeLimitBytes,
      memoryEnabled: settingsController.memoryEnabled,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      connectTimeoutSeconds: settingsController.aiConnectTimeoutSeconds,
      responseTimeoutSeconds: settingsController.aiResponseTimeoutSeconds,
      streamIdleTimeoutSeconds: settingsController.aiStreamIdleTimeoutSeconds,
      autoTitleEnabled: settingsController.aiAutoTitleEnabled,
      telemetryDebugEnabled: settingsController.telemetryDebugEnabled,
      telemetryCaptureRawPayload: settingsController.telemetryCaptureRawPayload,
      telemetryCaptureEnvironment:
          settingsController.telemetryCaptureEnvironment,
      telemetryMaxPayloadChars: settingsController.telemetryMaxPayloadChars,
      platformName: Platform.operatingSystem,
      workingDirectory: effectiveWorkingDirectory,
      todayLocalDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      timeZoneName: now.timeZoneName,
      repositorySnapshot: gitSnapshot,
      memoryEntries: settingsController.memoryEnabled
          ? memoryController.entries
          : const [],
      allowCommandRules: settingsController.aiAllowCommandRules,
      availableSkills: skillsController.skills,
      availableMcpServers: mcpController.servers,
      builtinToolConfigs: settingsController.builtinToolConfigs,
      workspaceInstructionDocuments: (() {
        // Group E: 同步工作区指令文档字符上限。
        _workspaceInstructionService.maxDocumentCharacters =
            settingsController.aiMaxWorkspaceDocumentCharacters;
        return _workspaceInstructionService.loadDocuments(
          startDirectory: OpenHandPaths.applicationDirectoryPath(),
          homeDirectory: OpenHandPaths.homeDirectoryPath(),
        );
      })(),
      userInstructions: instructionsController.entries,
      skippedInstructionIds: skippedInstructionIds,
    );
  }

  AiRuntimeToolPreview? _previewRuntimeToolCatalogForWorkspace({
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required AiSessionController sessionController,
    required AppInfo appInfo,
    required AiSession? session,
  }) {
    final model = settingsController.selectedAiModel;
    if (session == null || model == null) {
      _runtimeToolPreviewCacheKey = null;
      _runtimeToolPreviewCacheValue = null;
      return null;
    }

    final allowCommandRules = settingsController.aiAllowCommandRules;
    final builtinToolConfigs = settingsController.builtinToolConfigs;
    final availableSkills = skillsController.skills;
    final availableMcpServers = mcpController.servers;
    final now = DateTime.now().toLocal();
    final todayLocalDate = _formatLocalDate(now);
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{};
    final mcpCatalogKeyParts = <Object?>[];
    for (final server in availableMcpServers) {
      final catalog = mcpController.toolCatalogFor(server.name);
      mcpToolCatalogsByServerName[server.name] = catalog;
      mcpCatalogKeyParts.addAll(<Object?>[
        server.name,
        identityHashCode(server),
        catalog.status,
        catalog.tools.length,
        identityHashCode(catalog.tools),
        catalog.errorMessage,
        catalog.warningMessage,
        catalog.lastScannedAt?.microsecondsSinceEpoch,
      ]);
    }

    final cacheKey = Object.hashAll(<Object?>[
      identityHashCode(session),
      session.id,
      session.mode,
      session.awaitingPlanApproval,
      session.messages.length,
      session.planHistory.length,
      session.templateId,
      model.id,
      model.modelId,
      model.protocolType,
      settingsController.locale.toLanguageTag(),
      appInfo.version,
      appInfo.buildNumber,
      settingsController.settingsFilePath,
      settingsController.skillsStoragePath,
      settingsController.mcpServersFilePath,
      settingsController.userMemoryFilePath,
      settingsController.aiMessageCompressionThresholdChars,
      settingsController.aiToolResultCompressionThresholdChars,
      settingsController.aiToolResultCompressionEnabled,
      settingsController.aiToolResultCompressionHeadTailWindowChars,
      settingsController.aiToolResultCompressionMaxPathHits,
      settingsController.aiWriteToolSummaryMaxChars,
      settingsController.aiSingleRoundToolCallLimit,
      settingsController.aiSequentialToolRoundLimit,
      settingsController.aiMaxRecentErrors,
      settingsController.aiMaxPlanHistoryEntries,
      settingsController.aiMaxTruncationContinuations,
      settingsController.aiEstimatedCharactersPerToken,
      settingsController.aiMaxToolOutputChars,
      settingsController.aiWriteConfirmationTimeoutMs,
      settingsController.aiFastPathWriteAnalysisThreshold,
      settingsController.aiMaxHookTextCharacters,
      settingsController.aiWebFetchMaxResponseBytes,
      settingsController.aiWebFetchMaxRedirects,
      settingsController.aiWebFetchMaxCacheEntries,
      settingsController.aiAttachmentMaxInlineImageDimension,
      settingsController.aiAttachmentMaxTextRawBytes,
      settingsController.aiAttachmentMaxPdfRawBytes,
      settingsController.aiAttachmentMaxImageRawBytes,
      settingsController.aiChatMaxStreamLineBufferBytes,
      settingsController.aiImageSizeLimitBytes,
      settingsController.memoryEnabled,
      settingsController.aiWriteCommandConfirmationEnabled,
      settingsController.aiConnectTimeoutSeconds,
      settingsController.aiResponseTimeoutSeconds,
      settingsController.aiStreamIdleTimeoutSeconds,
      settingsController.aiAutoTitleEnabled,
      settingsController.telemetryDebugEnabled,
      settingsController.telemetryCaptureRawPayload,
      settingsController.telemetryCaptureEnvironment,
      settingsController.telemetryMaxPayloadChars,
      _identityHashAll(allowCommandRules),
      allowCommandRules.length,
      _identityHashAll(builtinToolConfigs),
      builtinToolConfigs.length,
      _identityHashAll(availableSkills),
      availableSkills.length,
      identityHashCode(availableMcpServers),
      availableMcpServers.length,
      todayLocalDate,
      now.timeZoneName,
      ...mcpCatalogKeyParts,
    ]);
    if (_runtimeToolPreviewCacheKey == cacheKey) {
      return _runtimeToolPreviewCacheValue;
    }

    final runtimeCatalogPreviewContext = _buildRuntimeCatalogPreviewContext(
      settingsController: settingsController,
      skillsController: skillsController,
      mcpController: mcpController,
      appInfo: appInfo,
      now: now,
      allowCommandRules: allowCommandRules,
      availableSkills: availableSkills,
      availableMcpServers: availableMcpServers,
      builtinToolConfigs: builtinToolConfigs,
    );
    final preview = sessionController.previewRuntimeToolCatalog(
      session: session,
      model: model,
      runtimeContext: runtimeCatalogPreviewContext,
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
    );
    _runtimeToolPreviewCacheKey = cacheKey;
    _runtimeToolPreviewCacheValue = preview;
    return preview;
  }

  String _formatLocalDate(DateTime now) {
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int _identityHashAll(Iterable<Object?> values) {
    return Object.hashAll(values.map(identityHashCode));
  }

  AiSessionRuntimeContext _buildRuntimeCatalogPreviewContext({
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required AppInfo appInfo,
    DateTime? now,
    List<AiAllowCommandRule>? allowCommandRules,
    List<LocalSkill>? availableSkills,
    List<McpServer>? availableMcpServers,
    List<AiBuiltinToolConfig>? builtinToolConfigs,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    return AiSessionRuntimeContext(
      localeTag: settingsController.locale.toLanguageTag(),
      appVersion: appInfo.version,
      appBuildNumber: appInfo.buildNumber,
      settingsFilePath: settingsController.settingsFilePath,
      skillsStoragePath: settingsController.skillsStoragePath,
      mcpServersFilePath: settingsController.mcpServersFilePath,
      userMemoryFilePath: settingsController.userMemoryFilePath,
      compressionThresholdChars:
          settingsController.aiMessageCompressionThresholdChars,
      toolResultCompressionThresholdChars:
          settingsController.aiToolResultCompressionThresholdChars,
      toolResultCompressionEnabled:
          settingsController.aiToolResultCompressionEnabled,
      toolResultCompressionHeadTailWindowChars:
          settingsController.aiToolResultCompressionHeadTailWindowChars,
      toolResultCompressionMaxPathHits:
          settingsController.aiToolResultCompressionMaxPathHits,
      writeToolSummaryMaxChars: settingsController.aiWriteToolSummaryMaxChars,
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      maxRecentErrors: settingsController.aiMaxRecentErrors,
      maxPlanHistoryEntries: settingsController.aiMaxPlanHistoryEntries,
      maxTruncationContinuations: settingsController.aiMaxTruncationContinuations,
      estimatedCharactersPerToken: settingsController.aiEstimatedCharactersPerToken,
      maxToolOutputChars: settingsController.aiMaxToolOutputChars,
      writeConfirmationTimeoutMs: settingsController.aiWriteConfirmationTimeoutMs,
      fastPathWriteAnalysisThreshold:
          settingsController.aiFastPathWriteAnalysisThreshold,
      maxHookTextCharacters: settingsController.aiMaxHookTextCharacters,
      webFetchMaxResponseBytes: settingsController.aiWebFetchMaxResponseBytes,
      webFetchMaxRedirects: settingsController.aiWebFetchMaxRedirects,
      webFetchMaxCacheEntries: settingsController.aiWebFetchMaxCacheEntries,
      attachmentMaxInlineImageDimension:
          settingsController.aiAttachmentMaxInlineImageDimension,
      attachmentMaxTextRawBytes:
          settingsController.aiAttachmentMaxTextRawBytes,
      attachmentMaxPdfRawBytes: settingsController.aiAttachmentMaxPdfRawBytes,
      attachmentMaxImageRawBytes:
          settingsController.aiAttachmentMaxImageRawBytes,
      chatMaxStreamLineBufferBytes:
          settingsController.aiChatMaxStreamLineBufferBytes,
      imageSizeLimitBytes: settingsController.aiImageSizeLimitBytes,
      memoryEnabled: settingsController.memoryEnabled,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      connectTimeoutSeconds: settingsController.aiConnectTimeoutSeconds,
      responseTimeoutSeconds: settingsController.aiResponseTimeoutSeconds,
      streamIdleTimeoutSeconds: settingsController.aiStreamIdleTimeoutSeconds,
      autoTitleEnabled: settingsController.aiAutoTitleEnabled,
      telemetryDebugEnabled: settingsController.telemetryDebugEnabled,
      telemetryCaptureRawPayload: settingsController.telemetryCaptureRawPayload,
      telemetryCaptureEnvironment:
          settingsController.telemetryCaptureEnvironment,
      telemetryMaxPayloadChars: settingsController.telemetryMaxPayloadChars,
      platformName: Platform.operatingSystem,
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      todayLocalDate: _formatLocalDate(localNow),
      timeZoneName: localNow.timeZoneName,
      memoryEntries: const [],
      allowCommandRules:
          allowCommandRules ?? settingsController.aiAllowCommandRules,
      availableSkills: availableSkills ?? skillsController.skills,
      availableMcpServers: availableMcpServers ?? mcpController.servers,
      builtinToolConfigs:
          builtinToolConfigs ?? settingsController.builtinToolConfigs,
    );
  }

  Future<void> _setComposerMode(AiSessionMode mode) async {
    final sessionController = context.read<AiSessionController>();
    final currentSession = sessionController.currentSession;
    if (currentSession == null) {
      if (_detachedComposerMode == mode) {
        return;
      }
      setState(() {
        _detachedComposerMode = mode;
      });
      return;
    }
    if (currentSession.mode == mode) {
      return;
    }
    final updated = await sessionController.updateSessionMode(
      currentSession.id,
      mode,
    );
    if (!mounted || updated) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = sessionController.lastErrorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
    );
  }

  Future<void> _handleFullAccessPermissionToggle(bool enable) async {
    final sessionController = context.read<AiSessionController>();
    final currentSession = sessionController.currentSession;
    if (currentSession == null) {
      if (_detachedFullAccessPermission == enable) {
        return;
      }
      if (enable) {
        final confirmed = await _showFullAccessConfirmationDialog();
        if (!confirmed || !mounted) {
          return;
        }
      }
      setState(() {
        _detachedFullAccessPermission = enable;
      });
      return;
    }
    if (currentSession.fullAccessPermission == enable) {
      return;
    }
    if (enable) {
      final confirmed = await _showFullAccessConfirmationDialog();
      if (!confirmed || !mounted) {
        return;
      }
    }
    final updated = await sessionController.updateSessionFullAccessPermission(
      currentSession.id,
      enable,
    );
    if (!mounted || updated) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = sessionController.lastErrorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
    );
  }

  Future<bool> _showFullAccessConfirmationDialog() async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(
            _localizedText(context, zh: '启用完全访问权限？', en: 'Enable Full Access?'),
          ),
          content: Text(
            _localizedText(
              context,
              zh: '在完全访问权限模式下，OpenHand 可无需审批直接编辑计算机上的任意文件并运行网络命令。\n\n启用完全访问权限前请谨慎评估。此操作将显著增加数据丢失、泄露或异常行为的风险。',
              en: 'With Full Access enabled, OpenHand can edit any file and run commands without requiring your explicit approval.\n\nPlease evaluate carefully before enabling. This action significantly increases the risk of data loss, leakage, or unexpected behavior.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_localizedText(context, zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: Text(
                _localizedText(context, zh: '是，仍然继续', en: 'Yes, Continue'),
              ),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    var prompt = _composerController.text.trim();
    final pendingAttachments = List<_ComposerAttachmentDraft>.from(
      _pendingAttachments,
    );
    if (prompt.isEmpty && pendingAttachments.isEmpty) {
      return;
    }
    final slashCommand = parseOpenHandSlashCommand(prompt);
    if (slashCommand != null) {
      if (pendingAttachments.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(
                context,
                zh: '本地斜杠命令不支持携带附件。',
                en: 'Local slash commands do not accept attachments.',
              ),
            ),
          ),
        );
        return;
      }
      _replaceComposerText('');
      await _handleSlashCommand(slashCommand);
      return;
    }

    final settingsController = context.read<SettingsController>();
    final selectedModel = settingsController.selectedAiModel;
    if (selectedModel == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiModelSelectionRequired)));
      return;
    }
    if (pendingAttachments.isNotEmpty &&
        !_selectedModelSupportsAttachments(selectedModel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '当前模型不支持附件。',
              en: 'The selected model does not support attachments.',
            ),
          ),
        ),
      );
      return;
    }
    // Warn (non-blocking) when the user attaches images but the model is
    // not detected as supporting inline image content.
    if (pendingAttachments.any(
          (a) => aiAttachmentKindForPath(a.filePath) == AiAttachmentKind.image,
        ) &&
        !AiProtocolRegistry.supportsInlineImages(selectedModel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '⚠️ 当前模型可能不支持直接查看图片，图片将以文字描述形式发送。建议切换到多模态模型。',
              en: '⚠️ The selected model may not support image viewing. Images will be sent as text descriptions.',
            ),
          ),
        ),
      );
    }

    final sessionController = context.read<AiSessionController>();
    MachineExpertDialogResult? machineExpertConfig;
    AiSessionRuntimeContext? runtimeContext;
    if (sessionController.currentSession == null) {
      final templateId = await _showThreadTemplateDialog();
      if (!mounted || templateId == null) {
        return;
      }
      if (templateId == 'machine_expert') {
        machineExpertConfig = await _showMachineExpertDialog(
          initialTask: prompt,
        );
        if (!mounted || machineExpertConfig == null) {
          return;
        }
        prompt = machineExpertConfig.toPrompt();
        _replaceComposerText(prompt);
      }
      // Programming Expert: show project config dialog so the AI knows
      // the correct working directory and project context.
      _ProgrammingExpertConfig? peConfig;
      if (templateId == 'programming_expert') {
        if (kDebugMode) {
          debugPrint(
            '[pe.recents] dialog-open#B sessions=${sessionController.sessions.length}',
          );
        }
        final recentPathCache = _collectProgrammingExpertRecentPaths(
          sessionController.sessions,
        );
        final settingsController2 = context.read<SettingsController>();
        final currentWorkspacePath =
            _preferredProgrammingExpertProjectRootCandidate(
              sessionController: sessionController,
            ) ??
            '';
        peConfig = await showAnimatedDialog<_ProgrammingExpertConfig>(
          context: context,
          builder: (context) => _ProgrammingExpertProjectDialog(
            settingsController: settingsController2,
            recentPathCache: recentPathCache,
            currentWorkspacePath: currentWorkspacePath,
          ),
        );
        if (!mounted || peConfig == null) {
          return;
        }
      }
      runtimeContext = await _buildRuntimeContext(
        workingDirectory: peConfig?.projectRoot,
        skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
      );
      if (!mounted) {
        return;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
        initialMode: _detachedComposerMode,
        initialFullAccessPermission: _detachedFullAccessPermission,
      );
      if (!mounted || !created || sessionController.currentSession == null) {
        return;
      }
      if (machineExpertConfig != null) {
        await _applyMachineExpertModelSelection(machineExpertConfig);
      }
      // After creating a PE session, persist the project config into metadata.
      if (peConfig != null) {
        final currentSession = sessionController.currentSession;
        if (currentSession != null) {
          final ok = await sessionController.updateSessionMetadata(
            currentSession.id,
            <String, Object?>{
              'programming_expert_config': <String, Object?>{
                'project_root': peConfig.projectRoot,
                'language': peConfig.language,
                'sdk_path': peConfig.sdkPath,
                'lsp_path': peConfig.lspPath,
              },
            },
          );
          if (kDebugMode) {
            debugPrint(
              '[pe.recents] metadata-saved#B session=${currentSession.id} ok=$ok '
              'projectRoot=${peConfig.projectRoot}',
            );
          }
        }
        if (!mounted) {
          return;
        }
      }
    }
    final targetSessionId = sessionController.currentSessionId;
    if (targetSessionId == null) {
      return;
    }
    // Consume any pending skill selection from the composer.  The reminder is
    // carried as hidden metadata on the outgoing LLM turn (via the existing
    // `aiHookSystemRemindersMetadataKey` channel) so the stored user message
    // content shown in the transcript bubble remains exactly what the user
    // typed, without leaking the `<skill-manifest>` XML block.
    final composerState = _composerPanelKey.currentState;
    final skillDisplayMetadata = composerState?.peekPendingSkillMetadata();
    final skillReminder = composerState?.consumePendingSkillReminder();
    final additionalSystemReminders = <String>[
      if (skillReminder != null && skillReminder.trim().isNotEmpty)
        skillReminder,
    ];
    final isProcessing =
        _displaySendPhaseForSession(sessionController, targetSessionId) !=
        AiSendPhase.idle;
    if (isProcessing) {
      final queued = _QueuedMessage(
        text: prompt,
        attachments: pendingAttachments,
        systemReminders: additionalSystemReminders,
        skillMetadata: skillDisplayMetadata,
      );
      setState(() {
        final q =
            _queuedMessagesBySessionId[targetSessionId] ?? <_QueuedMessage>[];
        q.add(queued);
        _queuedMessagesBySessionId[targetSessionId] = q;
        _replaceComposerText('');
        _pendingAttachments = const <_ComposerAttachmentDraft>[];
        if (!_composerCollapsed) {
          _composerFocusNode.requestFocus();
        }
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '消息已暂存，将在当前回答完成后自动发送。',
              en: 'Message queued and will be sent automatically.',
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _replaceComposerText('');
    // Capture the creation mode and reset it before sending.
    final creationMode = _creationMode;
    final responseModalities = switch (creationMode) {
      _CreationMode.image => const <String>['Text', 'Image'],
      _CreationMode.video => const <String>['Text', 'Video'],
      _CreationMode.audio => const <String>['Text', 'Audio'],
      _CreationMode.none || _CreationMode.deepResearch => const <String>[],
    };
    final creationRequest = _creationRequestFromComposer(creationMode);
    setState(() {
      _pendingAttachments = const <_ComposerAttachmentDraft>[];
      _creationMode = _CreationMode.none;
      _creationOptions = AiCreationOptions.empty;
    });

    await _submitTextToSession(
      targetSessionId,
      prompt,
      pendingAttachments,
      runtimeContext: runtimeContext,
      responseModalities: responseModalities,
      creationRequest: creationRequest,
      additionalSystemReminders: additionalSystemReminders,
      selectedSkillMetadata: skillDisplayMetadata,
    );
  }

  /// Translates the composer-private [_CreationMode] enum into the public
  /// [AiCreationRequest] model that the controller/adapter layers speak.
  AiCreationRequest _creationRequestFromComposer(_CreationMode mode) {
    switch (mode) {
      case _CreationMode.none:
        return AiCreationRequest.none;
      case _CreationMode.image:
        final options =
            _creationOptions.size != null ||
                _creationOptions.aspectRatio != null ||
                _creationOptions.count != 1
            ? _creationOptions
            : const AiCreationOptions(size: '1024x1024', aspectRatio: '1:1');
        return AiCreationRequest(mode: AiCreationMode.image, options: options);
      case _CreationMode.video:
        return AiCreationRequest(
          mode: AiCreationMode.video,
          options: _creationOptions,
        );
      case _CreationMode.audio:
        return AiCreationRequest(
          mode: AiCreationMode.audio,
          options: _creationOptions,
        );
      case _CreationMode.deepResearch:
        return const AiCreationRequest(mode: AiCreationMode.deepResearch);
    }
  }

  /// Returns a mode-appropriate default [AiCreationOptions] blob, used as a
  /// starting point when the user first switches into a given creation mode.
  AiCreationOptions _defaultOptionsForComposerMode(_CreationMode mode) {
    switch (mode) {
      case _CreationMode.image:
        return const AiCreationOptions(size: '1024x1024', aspectRatio: '1:1');
      case _CreationMode.video:
        return const AiCreationOptions(aspectRatio: '16:9', durationSeconds: 5);
      case _CreationMode.audio:
        return const AiCreationOptions(durationSeconds: 10);
      case _CreationMode.deepResearch:
      case _CreationMode.none:
        return AiCreationOptions.empty;
    }
  }

  /// Shows a bottom sheet that lets the user refine the creation options for
  /// the currently selected mode. Returns the picked options or `null` if the
  /// user dismissed the sheet without committing a change.
  Future<AiCreationOptions?> _showCreationOptionsSheet(
    _CreationMode mode,
    AiCreationOptions initial,
  ) async {
    if (mode == _CreationMode.none || mode == _CreationMode.deepResearch) {
      return null;
    }
    final menuAnimationSettings = context
        .read<SettingsController>()
        .menuAnimationSettings;
    final colorScheme = Theme.of(context).colorScheme;
    return showAnimatedDialog<AiCreationOptions>(
      context: context,
      settings: menuAnimationSettings,
      barrierColor: colorScheme.scrim.withValues(alpha: 0.38),
      builder: (dialogContext) {
        final dialogColorScheme = Theme.of(dialogContext).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Material(
                elevation: 14,
                clipBehavior: Clip.antiAlias,
                color: dialogColorScheme.surfaceContainerHigh,
                surfaceTintColor: dialogColorScheme.surfaceTint,
                borderRadius: BorderRadius.circular(28),
                child: _CreationOptionsSheet(mode: mode, initial: initial),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitTextToSession(
    String targetSessionId,
    String prompt,
    List<_ComposerAttachmentDraft> pendingAttachments, {
    AiSessionRuntimeContext? runtimeContext,
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    List<String> additionalSystemReminders = const <String>[],
    Map<String, Object?>? selectedSkillMetadata,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final selectedModel = settingsController.selectedAiModel;
    if (selectedModel == null) return;

    final l10n = AppLocalizations.of(context)!;
    final initialSession = sessionController.sessions
        .cast<AiSession?>()
        .firstWhere((s) => s?.id == targetSessionId, orElse: () => null);
    final initialUserMessageCount = initialSession != null
        ? _visibleUserMessageCount(initialSession)
        : 0;
    final editingMessageIdBeforeSend = sessionController.editingMessageId;

    _storeComposerDraftForSession(
      targetSessionId,
      text: prompt,
      attachments: pendingAttachments,
    );

    setState(() {
      _submittingSessionId = targetSessionId;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    _scheduleScrollToBottom(force: true);
    try {
      if (runtimeContext == null) {
        // For Programming Expert sessions, use the project root as the
        // working directory so tool calls resolve against the loaded project.
        final peProjectRoot = _programmingExpertProjectRoot(initialSession);
        runtimeContext = await _buildRuntimeContext(
          workingDirectory: peProjectRoot,
          skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
        );
      }
      if (!mounted) {
        return;
      }
      final sent = await sessionController.sendMessage(
        sessionId: targetSessionId,
        content: prompt,
        model: selectedModel,
        runtimeContext: runtimeContext,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        attachmentFilePaths: pendingAttachments
            .map((item) => item.filePath)
            .toList(growable: false),
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation:
            sessionController.sessions
                    .cast<AiSession?>()
                    .firstWhere(
                      (s) => s?.id == targetSessionId,
                      orElse: () => null,
                    )
                    ?.fullAccessPermission ==
                true
            ? false
            : settingsController.aiWriteCommandConfirmationEnabled,
        confirmWriteCommand: (request) =>
            _confirmWriteCommand(request, sessionId: targetSessionId),
        additionalSystemReminders: additionalSystemReminders,
        selectedSkillMetadata: selectedSkillMetadata,
      );
      if (!mounted) {
        return;
      }
      if (!sent) {
        if (_shouldRestoreSubmittedPrompt(
          sessionController: sessionController,
          sessionId: targetSessionId,
          prompt: prompt,
          initialUserMessageCount: initialUserMessageCount,
          editingMessageId: editingMessageIdBeforeSend,
        )) {
          _restoreSubmittedDraft(
            sessionController,
            sessionId: targetSessionId,
            prompt: prompt,
            attachments: pendingAttachments,
          );
        }
        final errorMessage = sessionController.lastErrorMessageForSession(
          targetSessionId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
        );
        return;
      }
      _removeComposerDraftForSession(targetSessionId);
      await sessionController.completeEditingMessage();
      if (!mounted) {
        return;
      }
      if (sessionController.didCompressInLastSendForSession(targetSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.threadCompressionNotice)));
      }
      _scheduleScrollToBottom(force: true, animated: true);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'openhand_home_page',
          context: ErrorDescription('while sending a chat message'),
        ),
      );
      if (mounted &&
          _shouldRestoreSubmittedPrompt(
            sessionController: sessionController,
            sessionId: targetSessionId,
            prompt: prompt,
            initialUserMessageCount: initialUserMessageCount,
            editingMessageId: editingMessageIdBeforeSend,
          )) {
        _restoreSubmittedDraft(
          sessionController,
          sessionId: targetSessionId,
          prompt: prompt,
          attachments: pendingAttachments,
        );
      }
      if (mounted) {
        final errorMessage = '$error'.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage.isEmpty ? l10n.chatRequestFailed : errorMessage,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_submittingSessionId == targetSessionId) {
            _submittingSessionId = null;
          }
        });
        _processMessageQueueIfNeeded(sessionController);
      } else if (_submittingSessionId == targetSessionId) {
        _submittingSessionId = null;
      }
    }
  }

  void _replaceComposerText(String value) {
    _composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  bool _selectedModelSupportsAttachments(AiModelConfig? model) {
    if (model == null) return false;
    return model.resolvedSupportsAttachments;
  }

  /// Attempts to pull an image off the OS clipboard (Cmd/Ctrl+V) and add it
  /// to the composer's pending attachments. Silently no-ops if the clipboard
  /// holds no image, the active model rejects attachments, the 20-slot or
  /// 10MB caps are exhausted, or the platform plugin is unavailable.
  Future<void> _tryPasteImageFromClipboard() async {
    if (!mounted) {
      return;
    }
    final selectedModel = context.read<SettingsController>().selectedAiModel;
    if (selectedModel == null ||
        !_selectedModelSupportsAttachments(selectedModel)) {
      return;
    }
    if (_pendingAttachments.length >= aiMessageAttachmentLimit) {
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await Pasteboard.image;
    } catch (error, stack) {
      silentLog('home', 'pasteboard.image', error, stack);
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    if (bytes.lengthInBytes > aiMessageAttachmentMaxFileBytes) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '剪贴板图片超出 10MB 单文件上限，已忽略。',
              en:
                  'Clipboard image exceeds the 10MB per-attachment limit and was ignored.',
            ),
          ),
        ),
      );
      return;
    }
    String tempPath;
    try {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_paste_',
      );
      final ts = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final tempFile = File(p.join(tempDir.path, 'pasted_$ts.png'));
      await tempFile.writeAsBytes(bytes, flush: true);
      tempPath = tempFile.path;
    } catch (error, stack) {
      silentLog('home', 'pasteboard.write_temp', error, stack);
      return;
    }
    if (!mounted) {
      return;
    }
    _ComposerAttachmentDraft draft;
    try {
      draft = await _ComposerAttachmentDraft.fromPath(tempPath);
    } catch (error, stack) {
      silentLog('home', 'pasteboard.draft', error, stack);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingAttachments = List<_ComposerAttachmentDraft>.from(
        _pendingAttachments,
      )..add(draft);
      _composerCollapsed = false;
    });
  }

  Future<void> _pickComposerAttachments() async {
    final l10n = AppLocalizations.of(context)!;
    final selectedModel = context.read<SettingsController>().selectedAiModel;
    if (selectedModel == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiModelSelectionRequired)));
      return;
    }
    if (!_selectedModelSupportsAttachments(selectedModel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '当前模型不支持附件。',
              en: 'The selected model does not support attachments.',
            ),
          ),
        ),
      );
      return;
    }
    final remainingSlots =
        aiMessageAttachmentLimit - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '单条消息最多携带 20 个附件。',
              en: 'A single message supports at most 20 attachments.',
            ),
          ),
        ),
      );
      return;
    }
    final pickedFiles = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: 'Attachments',
          extensions: aiAttachmentPickerExtensions(),
        ),
      ],
    );
    if (!mounted || pickedFiles.isEmpty) {
      return;
    }
    final existingPaths = _pendingAttachments
        .map((item) => item.filePath)
        .toSet();
    final nextAttachments = List<_ComposerAttachmentDraft>.from(
      _pendingAttachments,
    );
    final imageSizeLimitBytes = context
        .read<SettingsController>()
        .aiImageSizeLimitBytes;
    var addedCount = 0;
    var oversizedCount = 0;
    for (final file in pickedFiles) {
      final path = file.path.trim();
      if (path.isEmpty || existingPaths.contains(path)) {
        continue;
      }
      if (nextAttachments.length >= aiMessageAttachmentLimit) {
        break;
      }
      // Hard 10MB per-file cap (raw on-disk bytes). Enforced before any
      // image-editor or temp-file step so we never copy oversize files.
      try {
        final stat = await File(path).stat();
        if (stat.size > aiMessageAttachmentMaxFileBytes) {
          oversizedCount += 1;
          continue;
        }
      } catch (_) {
        // Couldn't stat — skip silently, the downstream service will
        // surface a clearer error if it cannot read the file at all.
        continue;
      }
      var resolvedPath = path;
      if (aiAttachmentKindForPath(path) == AiAttachmentKind.image) {
        try {
          final bytes = await File(path).readAsBytes();
          if (!mounted) {
            return;
          }
          final editorResult = await showImageEditorDialog(
            context,
            imageBytes: bytes,
            imageSizeLimitBytes: imageSizeLimitBytes,
          );
          if (!mounted) {
            return;
          }
          if (editorResult == null) {
            // User cancelled — drop this image entirely.
            continue;
          }
          // Persist edited bytes to a temp file so the rest of the
          // attachment pipeline can treat it like any other picked file.
          final tempDir = await Directory.systemTemp.createTemp(
            'openhand_edit_',
          );
          final ext = editorResult.format;
          final basename = p.basenameWithoutExtension(path);
          final tempFile = File(p.join(tempDir.path, '$basename.$ext'));
          await tempFile.writeAsBytes(editorResult.bytes, flush: true);
          resolvedPath = tempFile.path;
        } catch (_) {
          // Reading or editing failed — fall back to the original picked path.
          resolvedPath = path;
        }
      }
      if (existingPaths.contains(resolvedPath)) {
        continue;
      }
      nextAttachments.add(
        await _ComposerAttachmentDraft.fromPath(resolvedPath),
      );
      existingPaths.add(resolvedPath);
      addedCount += 1;
    }
    if (!mounted) {
      return;
    }
    if (oversizedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '已忽略 $oversizedCount 个超出 10MB 单文件上限的附件。',
              en: 'Ignored $oversizedCount file(s) exceeding the 10MB per-attachment limit.',
            ),
          ),
        ),
      );
    }
    if (addedCount == 0) {
      return;
    }
    setState(() {
      _pendingAttachments = nextAttachments;
      _composerCollapsed = false;
    });
  }

  void _removePendingAttachment(String filePath) {
    setState(() {
      _pendingAttachments = _pendingAttachments
          .where((item) => item.filePath != filePath)
          .toList(growable: false);
    });
  }

  void _reorderPendingAttachments(int oldIndex, int newIndex) {
    setState(() {
      final list = List<_ComposerAttachmentDraft>.from(_pendingAttachments);
      final item = list.removeAt(oldIndex);
      list.insert(newIndex.clamp(0, list.length), item);
      _pendingAttachments = list;
    });
  }

  void _restoreSubmittedDraft(
    AiSessionController sessionController, {
    required String sessionId,
    required String prompt,
    required List<_ComposerAttachmentDraft> attachments,
  }) {
    _storeComposerDraftForSession(
      sessionId,
      text: prompt,
      attachments: attachments,
    );
    if (sessionController.currentSessionId != sessionId) {
      return;
    }
    _replaceComposerText(prompt);
    setState(() {
      _pendingAttachments = List<_ComposerAttachmentDraft>.from(attachments);
      _composerCollapsed = false;
    });
  }

  int _visibleUserMessageCount(AiSession? session) {
    if (session == null) {
      return 0;
    }
    return session.messages
        .where(
          (message) =>
              !message.isDeleted && message.kind == AiSessionMessageKind.user,
        )
        .length;
  }

  AiSession? _sessionForId(
    AiSessionController sessionController,
    String sessionId,
  ) {
    for (final session in sessionController.sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  bool _shouldRestoreSubmittedPrompt({
    required AiSessionController sessionController,
    required String sessionId,
    required String prompt,
    required int initialUserMessageCount,
    required String? editingMessageId,
  }) {
    if (_composerController.text.trim().isNotEmpty) {
      return false;
    }
    final targetSession = _sessionForId(sessionController, sessionId);
    if (targetSession == null) {
      return false;
    }
    if (_visibleUserMessageCount(targetSession) > initialUserMessageCount) {
      return false;
    }
    if (editingMessageId != null) {
      for (final message in targetSession.messages) {
        if (message.id == editingMessageId &&
            !message.isDeleted &&
            message.content.trim() == prompt) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _stopResponding() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) {
      return;
    }
    await sessionController.stopResponding(sessionId);
  }

  void _scheduleScrollToBottom({
    bool force = false,
    bool animated = false,
    bool allowSettlePasses = true,
  }) {
    if (!force &&
        (!_autoFollowEnabled ||
            !_shouldAutoFollowMessages ||
            _userScrollInProgress)) {
      return;
    }
    if (force) {
      _shouldAutoFollowMessages = true;
      _queuedForcedScrollToBottom = true;
    }
    _pendingAnimatedScrollToBottom = _pendingAnimatedScrollToBottom || animated;
    if (allowSettlePasses) {
      // 2026-04-29: 之前 force 路径用 30 次 settle pass，与流式中的
      // 自主学习卡片（位于消息列表中段、随 token 持续增高）叠加时会导致
      // 滚动反复触底→重排→再触底的"抽搐"。将 force 上限收紧到 8 已经
      // 足以覆盖一次用户消息发出后的 1–2 帧 layout settle，避免与中段
      // 流式卡片的高度增长产生共振。
      _pendingScrollToBottomSettlePasses = math.max(
        _pendingScrollToBottomSettlePasses,
        force ? 8 : (animated ? 4 : 3),
      );
    }
    if (_programmaticAutoFollowScrollInProgress) {
      return;
    }
    if (_userScrollInProgress) {
      return;
    }
    if (_scrollToBottomCallbackQueued) {
      return;
    }
    _scrollToBottomCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomCallbackQueued = false;
      if (!mounted) {
        _queuedForcedScrollToBottom = false;
        _pendingAnimatedScrollToBottom = false;
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      if (_userScrollInProgress) {
        return;
      }
      final shouldForce = _queuedForcedScrollToBottom;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      _queuedForcedScrollToBottom = false;
      _pendingAnimatedScrollToBottom = false;
      if (!shouldForce &&
          (!_autoFollowEnabled ||
              !_shouldAutoFollowMessages ||
              _userScrollInProgress)) {
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      final activePosition = _activeMessageScrollPosition();
      if (activePosition == null) {
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      final targetOffset = activePosition.maxScrollExtent
          .clamp(activePosition.minScrollExtent, activePosition.maxScrollExtent)
          .toDouble();
      final distance = (targetOffset - activePosition.pixels).abs();
      void clearProgrammaticScrollFlag() {
        _programmaticAutoFollowScrollInProgress = false;
      }

      void scheduleSettlePass() {
        if (!mounted) {
          return;
        }
        if (_pendingScrollToBottomSettlePasses <= 0) {
          return;
        }
        _pendingScrollToBottomSettlePasses -= 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _userScrollInProgress) {
            _pendingScrollToBottomSettlePasses = 0;
            return;
          }
          _scheduleScrollToBottom(allowSettlePasses: false);
        });
      }

      if (distance >= 1 &&
          shouldAnimate &&
          distance > _autoFollowAnimatedDistanceThreshold) {
        _programmaticAutoFollowScrollInProgress = true;
        // Animate on the specific active `ScrollPosition` rather than the
        // controller so a transient second attached position (e.g. during a
        // session swap's AnimatedOpacity cross-fade) does not trip the
        // `Scrollbar` assertion that its `ScrollController` has a single
        // `ScrollPosition`.  `ScrollController.animateTo` fans out to every
        // attached position, which emits scroll notifications from the stale
        // position as well and surfaces as `RawScrollbar` validation crashes.
        unawaited(
          activePosition
              .animateTo(
                targetOffset,
                duration: _scrollToBottomAnimationDuration(distance),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() {
                clearProgrammaticScrollFlag();
                scheduleSettlePass();
              }),
        );
        return;
      }
      if (distance >= 1) {
        _programmaticAutoFollowScrollInProgress = true;
        activePosition.jumpTo(targetOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          clearProgrammaticScrollFlag();
          scheduleSettlePass();
        });
        return;
      }
      scheduleSettlePass();
    });
  }

  void _cancelProgrammaticAutoFollowScroll({double? keepPixels}) {
    _programmaticAutoFollowScrollInProgress = false;
  }

  Duration _scrollToBottomAnimationDuration(double distance) {
    final clampedDistance = distance.clamp(24, 520).toDouble();
    final milliseconds = (110 + clampedDistance * 0.24).round().clamp(110, 280);
    return Duration(milliseconds: milliseconds);
  }

  bool _isNearBottom() {
    final activePosition = _activeMessageScrollPosition();
    if (activePosition == null) {
      return true;
    }
    return activePosition.maxScrollExtent - activePosition.pixels <=
        _autoFollowDistanceThreshold;
  }

  void _maybeAutoFollowSession(AiSession? session) {
    final nextSignature = _sessionAutoScrollSignature(session);
    if (_lastAutoScrollSignature == nextSignature) {
      return;
    }
    _lastAutoScrollSignature = nextSignature;
    if (nextSignature == null) {
      return;
    }
    if (_autoFollowEnabled) {
      _armAutoFollowToBottom(notifyPausedState: false);
    }
    _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
  }

  void _handleComposerLayoutChanged() {
    if (_shouldDeferAutoFollowScheduling()) {
      return;
    }
    _scheduleAutoFollowIfNeeded(animated: false, allowSettlePasses: false);
  }

  void _handleTranscriptLayoutChanged() {
    if (_shouldDeferAutoFollowScheduling()) {
      return;
    }
    _scheduleAutoFollowIfNeeded(animated: false, allowSettlePasses: false);
  }

  void _handleRevealOlderMessages() {
    if (_autoFollowEnabled) {
      return;
    }
    _shouldAutoFollowMessages = false;
    _clearPendingAutoFollowState();
  }

  String? _sessionAutoScrollSignature(AiSession? session) {
    final currentSession = session;
    if (currentSession == null) {
      return null;
    }
    final displayMessages = currentSession.displayMessages;
    if (displayMessages.isEmpty) {
      return null;
    }
    final lastMessage = displayMessages.last;
    return [
      currentSession.id,
      displayMessages.length,
      lastMessage.id,
      lastMessage.kind.storageValue,
      lastMessage.characterCount,
      _toolExecutionStatus(lastMessage),
      '${_toolExecutionStdout(lastMessage).length}',
      '${_toolExecutionStderr(lastMessage).length}',
      '${_toolExecutionResult(lastMessage).length}',
    ].join('|');
  }

  ScrollPosition? _activeMessageScrollPosition() {
    if (!_messageScrollController.hasClients) {
      return null;
    }
    final positions = _messageScrollController.positions.toList(
      growable: false,
    );
    if (positions.isEmpty) {
      return null;
    }
    return positions.last;
  }

  Future<bool> _confirmWriteCommand(
    BashCommandApprovalRequest request, {
    String? sessionId,
    bool trackSessionBadge = true,
  }) async {
    final settingsController = context.read<SettingsController>();
    for (final rule in settingsController.aiAllowCommandRules) {
      if (rule.matches(request.command)) {
        return true;
      }
    }
    final sessionController = context.read<AiSessionController>();
    // Use the explicitly provided sessionId so the correct session badge
    // is updated even when the user has navigated to a different session.
    final effectiveSessionId = trackSessionBadge
        ? (sessionId ?? sessionController.currentSessionId)
        : null;
    if (effectiveSessionId != null) {
      sessionController.setSessionAwaitingApproval(effectiveSessionId);
    }
    try {
      final confirmed = await showWriteCommandConfirmationDialog(
        context,
        request: request,
      );
      return confirmed == true;
    } finally {
      if (effectiveSessionId != null) {
        sessionController.clearSessionAwaitingApproval(effectiveSessionId);
      }
    }
  }

  Future<bool> _confirmHardnessApiWriteCommand(
    BashCommandApprovalRequest request,
  ) {
    return _confirmWriteCommand(request, trackSessionBadge: false);
  }

  Future<void> _handleSlashCommand(OpenHandSlashCommand command) async {
    switch (command.kind) {
      case OpenHandSlashCommandKind.help:
        setState(() {
          _selectedSection = AppSection.settings;
        });
        await _showSlashHelpDialog();
        return;
      case OpenHandSlashCommandKind.feedback:
        setState(() {
          _selectedSection = AppSection.settings;
        });
        await _showFeedbackDialog(command.argument);
        return;
      case OpenHandSlashCommandKind.newSession:
        await _createSessionFromDialog();
        return;
      case OpenHandSlashCommandKind.status:
        final session = context.read<AiSessionController>().currentSession;
        if (session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '当前没有活动会话。',
                  en: 'There is no active session.',
                ),
              ),
            ),
          );
          return;
        }
        await _showSessionMetadataDialog(context, session);
        return;
      case OpenHandSlashCommandKind.stop:
        final sessionController = context.read<AiSessionController>();
        final currentSessionId = sessionController.currentSessionId;
        final hasActiveResponse =
            currentSessionId != null &&
            sessionController.canStopResponding(currentSessionId);
        if (!hasActiveResponse) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '当前没有正在进行的响应。',
                  en: 'There is no active response to stop.',
                ),
              ),
            ),
          );
          return;
        }
        await _stopResponding();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '已请求当前会话停止继续响应。',
                  en: 'Requested the current session to stop responding.',
                ),
              ),
            ),
          );
        }
        return;
      case OpenHandSlashCommandKind.settings:
        _activateSlashCommandSection(AppSection.settings);
        return;
      case OpenHandSlashCommandKind.workspace:
        _activateSlashCommandSection(AppSection.workspace);
        return;
      case OpenHandSlashCommandKind.automations:
        _activateSlashCommandSection(AppSection.automations);
        return;
      case OpenHandSlashCommandKind.skills:
        _activateSlashCommandSection(AppSection.skills);
        return;
      case OpenHandSlashCommandKind.memory:
        _activateSlashCommandSection(AppSection.memory);
        return;
      case OpenHandSlashCommandKind.mcp:
        _activateSlashCommandSection(AppSection.mcp);
        return;
      case OpenHandSlashCommandKind.crons:
        _activateSlashCommandSection(AppSection.crons);
        return;
    }
  }

  void _activateSlashCommandSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
    final label = switch (section) {
      AppSection.workspace => _localizedText(
        context,
        zh: '工作区',
        en: 'Workspace',
      ),
      AppSection.automations => _localizedText(
        context,
        zh: '自动化',
        en: 'Automations',
      ),
      AppSection.skills => _localizedText(context, zh: '技能', en: 'Skills'),
      AppSection.memory => _localizedText(context, zh: '记忆', en: 'Memory'),
      AppSection.mcp => _localizedText(context, zh: 'MCP', en: 'MCP'),
      AppSection.hooks => _localizedText(context, zh: 'Hooks', en: 'Hooks'),
      AppSection.crons => 'Crons',
      AppSection.instructions => _localizedText(
        context,
        zh: '指令',
        en: 'Instructions',
      ),
      AppSection.messageGateway => _localizedText(
        context,
        zh: '消息网关',
        en: 'Message Gateway',
      ),
      AppSection.settings => _localizedText(context, zh: '设置', en: 'Settings'),
      AppSection.hardnessSession => _localizedText(
        context,
        zh: 'HE 会话',
        en: 'HE Session',
      ),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '已切换到 $label。',
            en: 'Switched to $label.',
          ),
        ),
      ),
    );
  }

  Future<void> _showSlashHelpDialog() {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final closeLabel = _localizedText(context, zh: '关闭', en: 'Close');
    final allowRulePreview = settingsController.aiAllowCommandRules
        .take(4)
        .map((item) => '- ${item.pattern}')
        .join('\n');
    final commandList = <String>[
      '/help',
      '/commands',
      '/feedback [note]',
      '/new',
      '/status',
      '/stop',
      '/settings',
      '/config',
      '/workspace',
      '/sessions',
      '/chat',
      '/automations',
      '/skills',
      '/memory',
      '/mcp',
    ].join('\n');
    final detail = _localizedText(
      context,
      zh: '可用本地命令：\n$commandList\n\n`/help`、`/commands`、`/feedback`、`/new`、`/status`、`/stop` 不会发给模型，而是由 OpenHand 本地处理。\n\n写命令确认：${settingsController.aiWriteCommandConfirmationEnabled ? '开启' : '关闭'}\n允许命令规则：${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\n设置文件：${settingsController.displaySettingsFilePath}\n会话目录：${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
      en: 'Available local commands:\n$commandList\n\n`/help`, `/commands`, `/feedback`, `/new`, `/status`, and `/stop` are handled locally by OpenHand instead of being sent to the model.\n\nWrite command confirmation: ${settingsController.aiWriteCommandConfirmationEnabled ? 'enabled' : 'disabled'}\nAllow command rules: ${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\nSettings file: ${settingsController.displaySettingsFilePath}\nSession directory: ${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
    );
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(context, zh: 'Slash Commands', en: 'Slash Commands'),
          ),
          content: SelectableText(detail),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: closeLabel,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFeedbackDialog(String note) {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final closeLabel = _localizedText(context, zh: '关闭', en: 'Close');
    final copiedLabel = _localizedText(
      context,
      zh: '反馈模板已复制。',
      en: 'Feedback template copied.',
    );
    final trimmedNote = note.trim();
    final feedbackTemplate = _localizedText(
      context,
      zh: 'OpenHand 反馈\n备注：${trimmedNote.isEmpty ? '请在这里补充问题描述。' : trimmedNote}\n设置文件：${settingsController.settingsFilePath}\n会话目录：${sessionController.sessionsDirectoryPath}',
      en: 'OpenHand Feedback\nNote: ${trimmedNote.isEmpty ? 'Add your issue details here.' : trimmedNote}\nSettings file: ${settingsController.settingsFilePath}\nSession directory: ${sessionController.sessionsDirectoryPath}',
    );
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_localizedText(context, zh: '反馈信息', en: 'Feedback Info')),
          content: SelectableText(
            _localizedText(
              context,
              zh: '该命令不会发送给模型。你可以把下面这段信息复制出去提交反馈：\n\n$feedbackTemplate',
              en: 'This command is handled locally and is not sent to the model. You can copy the following report template for feedback:\n\n$feedbackTemplate',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: closeLabel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: feedbackTemplate));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text(copiedLabel)),
                );
              },
              label: _localizedText(context, zh: '复制模板', en: 'Copy Template'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final titleController = TextEditingController(text: session.title);
    String? submitted;
    try {
      submitted = await showAnimatedDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              _localizedText(dialogContext, zh: '重命名线程', en: 'Rename Thread'),
            ),
            content: TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _localizedText(
                  dialogContext,
                  zh: '输入线程标题',
                  en: 'Enter a thread title',
                ),
              ),
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value.trim());
              },
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: AppLocalizations.of(dialogContext)!.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () {
                  Navigator.of(dialogContext).pop(titleController.text.trim());
                },
                label: AppLocalizations.of(dialogContext)!.commonSave,
              ),
            ],
          );
        },
      );
    } finally {
      _disposeTextEditingControllerAfterCurrentFrame(titleController);
    }
    if (!mounted || submitted == null || submitted.isEmpty) {
      return;
    }
    final renamed = await controller.renameSession(session.id, submitted);
    if (!mounted || renamed) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '线程重命名失败。', en: 'Rename failed.'),
        ),
      ),
    );
  }

  Future<void> _deleteSession(AiSession session) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(dialogContext, zh: '删除线程', en: 'Delete Thread'),
          ),
          content: Text(session.title),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(dialogContext)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(dialogContext)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteSession(session.id);
    if (!mounted || deleted) {
      if (deleted) {
        _removeComposerDraftForSession(session.id);
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '线程删除失败。', en: 'Delete failed.'),
        ),
      ),
    );
  }

  Future<void> _renameHardnessSession() async {
    final record = _persistedHardnessSession;
    if (record == null) return;
    final titleController = TextEditingController(text: record.title);
    String? submitted;
    try {
      submitted = await showAnimatedDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              _localizedText(
                dialogContext,
                zh: '重命名 Hardness Engineering 会话',
                en: 'Rename HE Session',
              ),
            ),
            content: TextField(
              controller: titleController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _localizedText(
                  dialogContext,
                  zh: '输入会话标题',
                  en: 'Enter a session title',
                ),
              ),
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value.trim());
              },
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop(),
                label: AppLocalizations.of(dialogContext)!.commonCancel,
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () {
                  Navigator.of(dialogContext).pop(titleController.text.trim());
                },
                label: AppLocalizations.of(dialogContext)!.commonSave,
              ),
            ],
          );
        },
      );
    } finally {
      _disposeTextEditingControllerAfterCurrentFrame(titleController);
    }
    if (!mounted || submitted == null || submitted.isEmpty) {
      return;
    }
    final updated = record.copyWith(
      title: submitted,
      updatedAt: DateTime.now(),
    );
    setState(() => _persistedHardnessSession = updated);
    unawaited(_hardnessSessionStore.save(updated).catchError((_) {}));
  }

  Future<void> _deleteHardnessSession() async {
    final record = _persistedHardnessSession;
    if (record == null) return;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(
              dialogContext,
              zh: '删除 Hardness Engineering 会话',
              en: 'Delete HE Session',
            ),
          ),
          content: Text(record.title),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(dialogContext)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(dialogContext)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _activeHardnessOrchestrator?.removeListener(_onHardnessOrchestratorChanged);
    _activeHardnessOrchestrator?.dispose();
    _hardnessSessionSaveTimer?.cancel();
    setState(() {
      _activeHardnessOrchestrator = null;
      _activeHardnessConfig = null;
      _persistedHardnessSession = null;
      if (_selectedSection == AppSection.hardnessSession) {
        _selectedSection = AppSection.workspace;
      }
    });
    unawaited(_hardnessSessionStore.clear().catchError((_) {}));
  }

  /// Sanitises a session title for use in a default filename. Strips path
  /// separators, control chars, and trims to a reasonable length.
  String _sanitizeFileBasename(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'session';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  /// Hard cap on a single export operation so a corrupt session can never
  /// hang the UI indefinitely.
  static const Duration _exportTimeout = Duration(minutes: 5);

  Future<void> _exportSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final messenger = ScaffoldMessenger.of(context);

    // Step 1: load the full session up-front so the config dialog can show
    // an accurate message count for range validation.
    AiSession? loaded;
    try {
      loaded = await controller.store.loadSession(session.id);
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '_exportSession.loadSession',
        error,
        stack,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context,
                zh: '加载会话失败：$error',
                en: 'Failed to load session: $error'),
          ),
        ),
      );
      return;
    }
    if (loaded == null || !mounted) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(context,
                  zh: '会话不存在或已被删除。',
                  en: 'Session is missing or has been deleted.'),
            ),
          ),
        );
      }
      return;
    }

    // Step 2: collect the export configuration from the user.
    final config = await showAiSessionExportConfigDialog(
      context: context,
      totalMessages: loaded.messages.length,
    );
    if (config == null || !mounted) return;

    // Step 3: pick the destination file.
    const typeGroup = XTypeGroup(
      label: 'JSONL',
      extensions: <String>['jsonl'],
    );
    final suggested =
        '${_sanitizeFileBasename(loaded.title)}_${loaded.id}.jsonl';
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '_exportSession.getSaveLocation', error,
          stack);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context,
                zh: '无法打开保存对话框：$error',
                en: 'Unable to open save dialog: $error'),
          ),
        ),
      );
      return;
    }
    if (location == null || !mounted) return;

    // Step 4: kick off the streamed export with progress UI.
    final cancelToken = ExportCancelToken();
    final progressController =
        ExportProgressController(cancelToken: cancelToken);

    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context,
          zh: '导出会话数据', en: 'Export Session Data'),
      subtitle: _localizedText(context,
          zh: '正在导出 “${loaded.title}”…',
          en: 'Exporting "${loaded.title}"…'),
      cancelLabel:
          _localizedText(context, zh: '取消', en: 'Cancel'),
    );

    ExportResult result;
    try {
      result = await exportAiSessionToJsonl(
        session: loaded,
        destinationPath: location.path,
        cancelToken: cancelToken,
        config: config,
        onProgress: progressController.updateProgress,
      ).timeout(_exportTimeout, onTimeout: () {
        cancelToken.cancel();
        return const ExportResult(kind: ExportResultKind.failure);
      });
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '_exportSession.runExport',
        error,
        stack,
      );
      result = ExportResult(kind: ExportResultKind.failure, error: error);
    }
    progressController.markFinished();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    progressController.dispose();

    if (!mounted) return;
    _showExportResultSnackBar(messenger, result, location.path);
  }

  Future<void> _exportHardnessSession() async {
    final record = _persistedHardnessSession;
    if (record == null) return;
    final messenger = ScaffoldMessenger.of(context);

    // Step 1: collect the export configuration from the user.
    final config = await showHardnessSessionExportConfigDialog(
      context: context,
      totalPhaseLogs: record.phaseLogs.length,
    );
    if (config == null || !mounted) return;

    // Step 2: pick the destination file.
    const typeGroup = XTypeGroup(
      label: 'JSONL',
      extensions: <String>['jsonl'],
    );
    final suggested =
        '${_sanitizeFileBasename(record.title)}_${record.id}.jsonl';
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page',
          '_exportHardnessSession.getSaveLocation', error, stack);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context,
                zh: '无法打开保存对话框：$error',
                en: 'Unable to open save dialog: $error'),
          ),
        ),
      );
      return;
    }
    if (location == null || !mounted) return;

    final cancelToken = ExportCancelToken();
    final progressController =
        ExportProgressController(cancelToken: cancelToken);

    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context,
          zh: '导出会话数据', en: 'Export Session Data'),
      subtitle: _localizedText(context,
          zh: '正在导出 “${record.title}”…',
          en: 'Exporting "${record.title}"…'),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
    );

    ExportResult result;
    try {
      result = await exportHardnessSessionToJsonl(
        record: record,
        destinationPath: location.path,
        cancelToken: cancelToken,
        config: config,
        onProgress: progressController.updateProgress,
      ).timeout(_exportTimeout, onTimeout: () {
        cancelToken.cancel();
        return const ExportResult(kind: ExportResultKind.failure);
      });
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '_exportHardnessSession.run',
        error,
        stack,
      );
      result = ExportResult(kind: ExportResultKind.failure, error: error);
    }
    progressController.markFinished();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    progressController.dispose();

    if (!mounted) return;
    _showExportResultSnackBar(messenger, result, location.path);
  }

  void _showExportResultSnackBar(
    ScaffoldMessengerState messenger,
    ExportResult result,
    String destinationPath,
  ) {
    final ctx = context;
    final String message;
    switch (result.kind) {
      case ExportResultKind.success:
        message = _localizedText(ctx,
            zh: '导出成功：$destinationPath',
            en: 'Export succeeded: $destinationPath');
        break;
      case ExportResultKind.cancelled:
        message =
            _localizedText(ctx, zh: '已取消导出。', en: 'Export cancelled.');
        break;
      case ExportResultKind.failure:
        final reason = result.error?.toString() ?? 'unknown error';
        message = _localizedText(ctx,
            zh: '导出失败：$reason', en: 'Export failed: $reason');
        break;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editMessage(AiSessionMessage message) async {
    final result = await context
        .read<AiSessionController>()
        .beginEditingMessage(message.id);
    if (!mounted || result == null) {
      return;
    }
    _replaceComposerText(result.content);

    // Restore attachments from the original message so the user can
    // keep, remove, or add more attachments while editing.
    final restoredAttachments = <_ComposerAttachmentDraft>[];
    for (final attachment in result.attachments) {
      final path = attachment.storagePath.trim();
      if (path.isNotEmpty && File(path).existsSync()) {
        restoredAttachments.add(
          _ComposerAttachmentDraft(
            filePath: path,
            name: attachment.name,
            kind: attachment.kind,
            sizeBytes: attachment.sizeBytes,
          ),
        );
      }
    }

    setState(() {
      _selectedSection = AppSection.workspace;
      _composerCollapsed = false;
      _pendingAttachments = restoredAttachments;
    });
    _scheduleScrollToBottom();
  }

  Future<void> _copyMessage(AiSessionMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(context, zh: '消息内容已复制。', en: 'Message copied.'),
        ),
      ),
    );
  }

  Future<bool> _deleteMessage(AiSessionMessage message) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(dialogContext, zh: '删除消息', en: 'Delete Message'),
          ),
          content: Text(
            _localizedText(
              dialogContext,
              zh: '删除后，这条消息将不再显示。',
              en: 'This message will no longer be shown.',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteMessages(<String>[message.id]);
    if (!mounted || deleted) {
      return deleted;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '消息删除失败。', en: 'Delete failed.'),
        ),
      ),
    );
    return false;
  }

  Future<bool> _deleteMessageFromHere(AiSessionMessage message) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(
              dialogContext,
              zh: '删除此条及后续消息',
              en: 'Delete From Here',
            ),
          ),
          content: Text(
            _localizedText(
              dialogContext,
              zh: '删除后，这条消息及其后续消息将不再显示。',
              en: 'This message and the later messages will no longer be shown.',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteMessagesFrom(message.id);
    if (!mounted || deleted) {
      return deleted;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '批量删除消息失败。', en: 'Delete failed.'),
        ),
      ),
    );
    return false;
  }

  Future<void> _cancelEditingMessage() async {
    final controller = context.read<AiSessionController>();
    final cancelled = await controller.cancelEditingMessage();
    if (!mounted || cancelled) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(
                context,
                zh: '恢复编辑前的会话状态失败。',
                en: 'Failed to restore the previous conversation state.',
              ),
        ),
      ),
    );
  }

  Future<void> _dismissSessionError(AiSessionErrorRecord error) async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) {
      return;
    }
    await sessionController.markErrorAsPresented(
      sessionId: sessionId,
      errorId: error.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<OpenHandPalette>()!;
    final sessionController = context.watch<AiSessionController>();
    final panelAnimationSettings = context
        .select<SettingsController, DialogAnimationSettings>((controller) {
          return controller.panelAnimationSettings;
        });
    final pageAnimationSettings = context
        .select<SettingsController, DialogAnimationSettings>((controller) {
          return controller.pageAnimationSettings;
        });

    return Focus(
      focusNode: _globalShortcutFocusNode,
      autofocus: true,
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.canvasStart, palette.canvasEnd],
            ),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackedLayout =
                    constraints.maxWidth < _sideBySideLayoutMinWidth;
                final stackedNavigationHeight = (constraints.maxHeight * 0.34)
                    .clamp(
                      _stackedNavigationMinHeight,
                      _stackedNavigationMaxHeight,
                    )
                    .toDouble();
                final sessionSendPhases = _navigationSendPhases(
                  sessionController,
                );
                final navigationPane = _NavigationPane(
                  selectedSection: _selectedSection,
                  sessions: sessionController.sessions,
                  sessionSendPhases: sessionSendPhases,
                  currentSessionId: sessionController.currentSessionId,
                  onCreateThreadRequested: _createSessionFromDialog,
                  onSessionSelected: _activateSession,
                  onRenameSession: _renameSession,
                  onDeleteSession: _deleteSession,
                  onExportSession: _exportSession,
                  onSectionSelected: _selectSection,
                  activeHardnessOrchestrator: _activeHardnessOrchestrator,
                  hardnessSessionRecord: _persistedHardnessSession,
                  onHardnessSessionSelected:
                      _persistedHardnessSession != null ||
                          _activeHardnessOrchestrator != null
                      ? () => _selectSection(AppSection.hardnessSession)
                      : null,
                  onRenameHardnessSession: _persistedHardnessSession != null
                      ? _renameHardnessSession
                      : null,
                  onDeleteHardnessSession: _persistedHardnessSession != null
                      ? _deleteHardnessSession
                      : null,
                  onExportHardnessSession: _persistedHardnessSession != null
                      ? _exportHardnessSession
                      : null,
                );

                // Swap left pane to file explorer when toggled for
                // programming_expert sessions.
                final currentSession = sessionController.currentSession;
                final projectRoot = _programmingExpertProjectRoot(
                  currentSession,
                );
                final showFileExplorer =
                    _fileExplorerVisible &&
                    projectRoot != null &&
                    _selectedSection == AppSection.workspace;
                final panelAnim = panelAnimationSettings;
                final panelDuration = _effectiveSwitchDuration(panelAnim);
                final panelCurve = panelAnim.curve.curve;
                final panelReverseCurve = panelAnim.curve.reverseCurve;
                final Widget leftPaneContent = showFileExplorer
                    ? _ContentPane(
                        key: const ValueKey<String>('file-explorer-pane'),
                        child: _FileExplorerPanel(
                          rootPath: projectRoot,
                          onFileSelected: _openFileInEditor,
                          activeFilePath: _activeFilePath,
                        ),
                      )
                    : KeyedSubtree(
                        key: const ValueKey<String>('navigation-pane'),
                        child: navigationPane,
                      );
                final Widget leftPane = AnimatedSwitcher(
                  duration: panelDuration,
                  switchInCurve: panelCurve,
                  switchOutCurve: panelReverseCurve,
                  transitionBuilder: (child, animation) {
                    return _buildPanelTransition(
                      child: child,
                      animation: animation,
                      entranceStyle: panelAnim.entranceStyle,
                      exitStyle: panelAnim.exitStyle,
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: leftPaneContent,
                );

                // Swap right pane to code editor when files are open.
                final showEditor =
                    _selectedSection == AppSection.workspace &&
                    _activeFilePath != null &&
                    _openFilePaths.isNotEmpty;
                // Fallback: if the user explicitly set page animation to
                // none/none we still want section→section to feel alive when
                // panel animation is enabled, so use panel settings as a
                // backstop. This keeps Settings/MCP/Memory/Hooks/Crons/Skills
                // switches visibly animated even with a misconfigured page
                // animation preset.
                final effectiveSectionAnim =
                    (pageAnimationSettings.entranceStyle ==
                            DialogAnimationStyle.none &&
                        pageAnimationSettings.exitStyle ==
                            DialogAnimationStyle.none &&
                        !(panelAnim.entranceStyle ==
                                DialogAnimationStyle.none &&
                            panelAnim.exitStyle == DialogAnimationStyle.none))
                    ? panelAnim
                    : pageAnimationSettings;
                // Single right-pane AnimatedSwitcher keyed by full identity
                // (`editor-pane` vs `section-<name>`). This guarantees every
                // page-level swap — both editor↔section and section↔section
                // — is detected as a child change and triggers the configured
                // page transition. Previously a nested inner switcher was
                // used, but the outer switcher saw the wrapper widget as
                // unchanged and the inner one's state could be elided,
                // making the cross-fade invisible in some rebuild paths.
                final Widget rightPaneContent = showEditor
                    ? Padding(
                        key: const ValueKey<String>('editor-pane'),
                        padding: const EdgeInsets.all(4),
                        child: _CodeEditorView(
                          openFiles: _openFilePaths,
                          activeFilePath: _activeFilePath!,
                          projectLanguage: _programmingExpertLanguage(
                            currentSession,
                          ),
                          projectSdkPath: _programmingExpertSdkPath(
                            currentSession,
                          ),
                          projectLspPath: _programmingExpertLspPath(
                            currentSession,
                          ),
                          onOpenFile: _openFileInEditor,
                          onTabSelected: _selectFileTab,
                          onTabClosed: _closeFileTab,
                          onCloseAll: _closeAllFileTabs,
                          onReorderTabs: _reorderFileTabs,
                          fileExplorerVisible: _fileExplorerVisible,
                          onToggleFileExplorer: _toggleFileExplorer,
                        ),
                      )
                    : _ContentPane(
                        key: ValueKey<String>(
                          'section-${_selectedSection.name}',
                        ),
                        child: _buildSectionContent(context),
                      );
                final rightPaneDuration = _effectiveSwitchDuration(
                  effectiveSectionAnim,
                );
                final rightPaneCurve = effectiveSectionAnim.curve.curve;
                final rightPaneReverseCurve =
                    effectiveSectionAnim.curve.reverseCurve;
                final Widget rightPane = AnimatedSwitcher(
                  duration: rightPaneDuration,
                  switchInCurve: rightPaneCurve,
                  switchOutCurve: rightPaneReverseCurve,
                  transitionBuilder: (child, animation) {
                    return _buildPanelTransition(
                      child: child,
                      animation: animation,
                      entranceStyle: effectiveSectionAnim.entranceStyle,
                      exitStyle: effectiveSectionAnim.exitStyle,
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: rightPaneContent,
                );

                if (stackedLayout) {
                  return Column(
                    children: [
                      SizedBox(
                        height: stackedNavigationHeight,
                        child: leftPane,
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: rightPane),
                    ],
                  );
                }

                return ValueListenableBuilder<double>(
                  valueListenable: _navigationWidthNotifier,
                  builder: (context, navWidth, _) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: navWidth, child: leftPane),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              var nextWidth = navWidth + details.delta.dx;
                              const minWidth = 240.0;
                              final maxWidth = constraints.maxWidth * 0.7;
                              if (nextWidth < minWidth) {
                                nextWidth = minWidth;
                              } else if (nextWidth > maxWidth) {
                                nextWidth = maxWidth;
                              }
                              if (nextWidth != navWidth) {
                                _navigationWidthNotifier.value = nextWidth;
                              }
                            },
                            child: const SizedBox(
                              width: _contentPaneGap,
                              height: double.infinity,
                            ),
                          ),
                        ),
                        Expanded(child: rightPane),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final workspaceSelected = _selectedSection == AppSection.workspace;
    final settingsController = workspaceSelected
        ? context.watch<SettingsController>()
        : context.read<SettingsController>();
    final skillsController = workspaceSelected
        ? context.watch<SkillsController>()
        : context.read<SkillsController>();
    final mcpController = workspaceSelected
        ? context.watch<McpController>()
        : context.read<McpController>();
    final sessionController = workspaceSelected
        ? context.watch<AiSessionController>()
        : context.read<AiSessionController>();
    final appInfo = context.read<AppInfo>();
    final currentSession = sessionController.currentSession;
    final transcriptPreparing = _isPreparingTranscriptForSession(
      currentSession,
    );
    // Defer runtime catalog preview work to the workspace section — these
    // computations involve DateTime.now(), object allocation, and tool catalog
    // resolution that are wasted when viewing other sections.
    AiRuntimeToolPreview? liveRuntimeToolPreview;
    if (workspaceSelected) {
      liveRuntimeToolPreview = _previewRuntimeToolCatalogForWorkspace(
        settingsController: settingsController,
        skillsController: skillsController,
        mcpController: mcpController,
        sessionController: sessionController,
        appInfo: appInfo,
        session: currentSession,
      );
      if (!transcriptPreparing) {
        _maybeAutoFollowSession(currentSession);
      }
    }

    return switch (_selectedSection) {
      AppSection.workspace => _WorkspaceView(
        draftController: _composerController,
        messageScrollController: _messageScrollController,
        onMessageScrollNotification: _handleMessageScrollNotification,
        currentSession: currentSession,
        liveRuntimeToolPreview: liveRuntimeToolPreview,
        transcriptPreparing: transcriptPreparing,
        selectedModel: settingsController.selectedAiModel,
        availableModels: settingsController.aiModels,
        recentModelSelections: settingsController.recentModelSelections,
        onModelSelected: (providerConfigId, modelId) {
          settingsController.updateProviderActiveModel(
            providerConfigId,
            modelId,
          );
          settingsController.addRecentModelSelection(providerConfigId, modelId);
          // Persist the model selection to the current session.
          final session = sessionController.currentSession;
          if (session != null) {
            sessionController.updateSessionLastUsedModel(
              session.id,
              providerConfigId: providerConfigId,
              modelId: modelId,
            );
          }
        },
        composerFocusNode: _composerFocusNode,
        composerHeight: _composerHeight,
        composerCollapsed: _composerCollapsed,
        onComposerHeightChanged: (nextHeight) {
          setState(() {
            _composerHeight = nextHeight;
          });
        },
        onComposerCollapsedChanged: _setComposerCollapsedState,
        onComposerLayoutChanged: _handleComposerLayoutChanged,
        onTranscriptLayoutChanged: _handleTranscriptLayoutChanged,
        onRevealOlderMessages: _handleRevealOlderMessages,
        autoFollowEnabled: _autoFollowEnabled,
        autoFollowPaused: _autoFollowPaused,
        onToggleAutoFollow: _toggleAutoFollow,
        sendPhase: _effectiveSendPhase(sessionController),
        canStopSending: _canStopCurrentSessionResponse(sessionController),
        planTimelineCollapsed: _isPlanTimelineCollapsed(currentSession?.id),
        onPlanTimelineCollapsedChanged: currentSession == null
            ? null
            : (collapsed) {
                _setPlanTimelineCollapsed(currentSession.id, collapsed);
              },
        sessionMode: _effectiveComposerMode(sessionController),
        onSessionModeChanged: _setComposerMode,
        fullAccessPermission:
            currentSession?.fullAccessPermission ??
            _detachedFullAccessPermission,
        onToggleFullAccessPermission: _handleFullAccessPermissionToggle,
        queuedMessages: currentSession != null
            ? (_queuedMessagesBySessionId[currentSession.id] ?? const [])
            : const [],
        onRemoveQueuedMessage: (index) {
          if (currentSession != null) {
            setState(() {
              final q = _queuedMessagesBySessionId[currentSession.id];
              if (q != null && index >= 0 && index < q.length) {
                q.removeAt(index);
                if (q.isEmpty) {
                  _queuedMessagesBySessionId.remove(currentSession.id);
                }
              }
            });
          }
        },
        onMoveQueuedMessage: (from, to) {
          if (currentSession != null) {
            setState(() {
              final q = _queuedMessagesBySessionId[currentSession.id];
              if (q != null &&
                  from >= 0 &&
                  from < q.length &&
                  to >= 0 &&
                  to < q.length &&
                  from != to) {
                final item = q.removeAt(from);
                q.insert(to, item);
              }
            });
          }
        },
        onEditQueuedMessage: (index, newText) {
          if (currentSession != null) {
            final trimmed = newText.trim();
            if (trimmed.isEmpty) return;
            setState(() {
              final q = _queuedMessagesBySessionId[currentSession.id];
              if (q != null && index >= 0 && index < q.length) {
                q[index] = _QueuedMessage(
                  text: trimmed,
                  attachments: q[index].attachments,
                  systemReminders: q[index].systemReminders,
                  skillMetadata: q[index].skillMetadata,
                );
              }
            });
          }
        },
        pendingAttachments: _pendingAttachments,
        attachmentsEnabled: _selectedModelSupportsAttachments(
          settingsController.selectedAiModel,
        ),
        onPickAttachments: _pickComposerAttachments,
        onRemoveAttachment: _removePendingAttachment,
        onReorderAttachments: _reorderPendingAttachments,
        onSend: _sendMessage,
        onStop: _stopResponding,
        onCreateThreadRequested: _createSessionFromDialog,
        creationMode: _creationMode,
        creationOptions: _creationOptions,
        onCreationModeChanged: (mode) async {
          // Drop any leftover options from a previous mode when the user
          // clears or switches to a mode whose options differ materially.
          final previousMode = _creationMode;
          setState(() {
            _creationMode = mode;
            if (mode == _CreationMode.none) {
              _creationOptions = AiCreationOptions.empty;
            } else if (mode != previousMode) {
              _creationOptions = _defaultOptionsForComposerMode(mode);
            }
          });
          // When the user just enabled a media-producing mode, open the
          // options sheet so they can pick size / aspect ratio / duration
          // without hunting through a settings screen.
          if ((mode == _CreationMode.image ||
                  mode == _CreationMode.video ||
                  mode == _CreationMode.audio) &&
              previousMode != mode) {
            // Push the overlay route after the current frame has fully
            // settled to avoid LayoutBuilder callback assertions.
            await _awaitEndOfFrame();
            if (!mounted || _creationMode != mode) return;
            final picked = await _showCreationOptionsSheet(
              mode,
              _creationOptions,
            );
            // Wait for the dialog's closing animation to finish before
            // calling setState.  The dialog's future resolves immediately
            // when Navigator.pop is called, while the route's animation is
            // still running.  Calling setState here (while the animation is
            // mid-frame) can restart AnimatedSwitcher animations, which
            // trigger scheduleLayoutCallback assertions in LayoutBuilder.
            await _awaitEndOfFrame();
            if (!mounted || _creationMode != mode) return;
            if (picked != null) {
              setState(() => _creationOptions = picked);
            }
          }
        },
        onCreationOptionsChanged: (options) {
          setState(() => _creationOptions = options);
        },
        onEditOptionsRequested: () async {
          if (_creationMode == _CreationMode.none) return;
          setState(() {
            _creationMode = _CreationMode.none;
            _creationOptions = AiCreationOptions.empty;
          });
        },
        editingMessageId: sessionController.editingMessageId,
        onCancelEditing: _cancelEditingMessage,
        onEditMessage: _editMessage,
        onCopyMessage: _copyMessage,
        onDeleteMessage: _deleteMessage,
        onDeleteMessageFromHere: _deleteMessageFromHere,
        onDismissError: _dismissSessionError,
        // Signal the transcript list to jump to the bottom on its first frame
        // whenever a forced-scroll-to-bottom is pending (i.e. a session was
        // just activated). This eliminates the visible animate-from-top jank.
        jumpToBottomOnInit: _pendingForcedScrollToBottom,
        fileExplorerVisible: _fileExplorerVisible,
        onFileExplorerToggled:
            _programmingExpertProjectRoot(currentSession) != null
            ? _toggleFileExplorer
            : null,
        projectRoot: _programmingExpertProjectRoot(currentSession),
        composerPanelKey: _composerPanelKey,
        skippedInstructionIds: _skippedInstructionIds,
        onToggleInstructionSkip: _toggleInstructionSkip,
      ),
      AppSection.automations => SectionPlaceholder(
        icon: Icons.schedule_send_outlined,
        title: l10n.automationHeadline,
        body: l10n.automationBody,
        footer: l10n.placeholderComingSoon,
        actionLabel: l10n.newThread,
        onAction: _createSessionFromDialog,
      ),
      AppSection.skills => const SkillsView(),
      AppSection.memory => const MemoryView(),
      AppSection.mcp => const McpView(),
      AppSection.hooks => const HooksView(),
      AppSection.crons => const CronsView(),
      AppSection.instructions => const InstructionsView(),
      AppSection.messageGateway => const MessageGatewayView(),
      AppSection.settings => const SettingsView(),
      AppSection.hardnessSession =>
        _activeHardnessOrchestrator != null && _activeHardnessConfig != null
            ? HardnessSessionPane(
                controller: _hardnessSessionPaneController,
                config: _activeHardnessConfig!,
                orchestrator: _activeHardnessOrchestrator!,
                isZh: Localizations.localeOf(
                  context,
                ).languageCode.startsWith('zh'),
                sessionTitle: _persistedHardnessSession?.title,
                updatedAtLabel: _persistedHardnessSession == null
                    ? null
                    : _formatDateTime(_persistedHardnessSession!.updatedAt),
                sessionId: _persistedHardnessSession?.id,
                createdAtLabel: _persistedHardnessSession == null
                    ? null
                    : _formatDateTime(_persistedHardnessSession!.createdAt),
                fullAccessPermission: _heFullAccessPermission,
                onToggleFullAccessPermission: _handleHeFullAccessToggle,
                onConfigChanged: _handleHeConfigChanged,
                filePathRoots: [
                  if ((_activeHardnessConfig?.workingDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    _activeHardnessConfig!.workingDirectory,
                  if ((_activeHardnessConfig?.persistenceDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    _activeHardnessConfig!.persistenceDirectory,
                  if ((_activeHardnessConfig?.persistenceDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    p.join(
                      _activeHardnessConfig!.persistenceDirectory,
                      'steering',
                    ),
                ],
                onRestart: () {
                  setState(() => _selectedSection = AppSection.hardnessSession);
                  _activeHardnessOrchestrator?.startOrResume();
                },
              )
            : SectionPlaceholder(
                icon: Icons.construction_rounded,
                title: 'Hardness Engineering',
                body: l10n.threadsEmptyBody,
                footer: l10n.placeholderComingSoon,
                actionLabel: l10n.newThread,
                onAction: _createSessionFromDialog,
              ),
    };
  }
}

class _ComposerDraftState {
  const _ComposerDraftState({required this.text, required this.attachments});

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
}

class _QueuedMessage {
  const _QueuedMessage({
    required this.text,
    required this.attachments,
    this.systemReminders = const <String>[],
    this.skillMetadata,
  });

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
  final List<String> systemReminders;
  final Map<String, Object?>? skillMetadata;
}

// ignore: unused_element
class _EditorPaneFrame extends StatelessWidget {
  // ignore: unused_element_parameter
  const _EditorPaneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Hot reload can leave an outgoing AnimatedSwitcher child alive for a
    // frame even after the wrapper was removed from the active tree. Keep this
    // shim so stale elements rebuild safely without altering the current UI.
    return child;
  }
}

extension on AppSection {
  /// Returns the drawer index for this section, or -1 if this section
  /// does not correspond to a NavigationDrawerDestination (e.g. workspace
  /// or hardnessSession which are displayed as thread tiles instead).
  /// Using -1 instead of null ensures NavigationDrawer deselects all
  /// destinations when switching to a thread.
  int get drawerIndex {
    return switch (this) {
      AppSection.workspace => -1,
      AppSection.hardnessSession => -1,
      AppSection.automations => 0,
      AppSection.skills => 1,
      AppSection.memory => 2,
      AppSection.mcp => 3,
      AppSection.hooks => 4,
      AppSection.crons => 5,
      AppSection.instructions => 6,
      AppSection.messageGateway => 7,
      AppSection.settings => 8,
    };
  }
}

AppSection _sectionFromDrawerIndex(int index) {
  return switch (index) {
    0 => AppSection.automations,
    1 => AppSection.skills,
    2 => AppSection.memory,
    3 => AppSection.mcp,
    4 => AppSection.hooks,
    5 => AppSection.crons,
    6 => AppSection.instructions,
    7 => AppSection.messageGateway,
    8 => AppSection.settings,
    _ => AppSection.workspace,
  };
}

/// Modal bottom sheet that lets users tweak [AiCreationOptions] for the
/// currently active creation mode. Returns the updated options or null if the
/// user dismissed without confirming.
class _CreationOptionsSheet extends StatefulWidget {
  const _CreationOptionsSheet({required this.mode, required this.initial});

  final _CreationMode mode;
  final AiCreationOptions initial;

  @override
  State<_CreationOptionsSheet> createState() => _CreationOptionsSheetState();
}

class _CreationOptionsSheetState extends State<_CreationOptionsSheet> {
  late String? _aspectRatio = widget.initial.aspectRatio;
  late String? _size = widget.initial.size;
  late int? _duration = widget.initial.durationSeconds;
  late int _count = widget.initial.count;

  // Mode-specific aspect ratio presets with matching pixel sizes. The 1024
  // baseline is used for image generation; video keeps the aspect strings
  // only (pixel sizes are provider-dependent).
  static const List<({String ratio, String size})> _imageRatios = [
    (ratio: '1:1', size: '1024x1024'),
    (ratio: '16:9', size: '1792x1024'),
    (ratio: '9:16', size: '1024x1792'),
    (ratio: '4:3', size: '1280x960'),
    (ratio: '3:4', size: '960x1280'),
  ];

  static const List<String> _videoRatios = ['16:9', '9:16', '1:1', '4:3'];
  static const List<int> _videoDurations = [3, 5, 8, 10];
  static const List<int> _audioDurations = [5, 10, 20, 30, 60];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isImage = widget.mode == _CreationMode.image;
    final isVideo = widget.mode == _CreationMode.video;
    final isAudio = widget.mode == _CreationMode.audio;
    final title = switch (widget.mode) {
      _CreationMode.image => _localizedText(
        context,
        zh: '图像生成选项',
        en: 'Image options',
      ),
      _CreationMode.video => _localizedText(
        context,
        zh: '视频生成选项',
        en: 'Video options',
      ),
      _CreationMode.audio => _localizedText(
        context,
        zh: '音频生成选项',
        en: 'Audio options',
      ),
      _ => _localizedText(context, zh: '生成选项', en: 'Options'),
    };
    final sectionStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final actionTextStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (isImage || isVideo) ...[
            Text(
              _localizedText(context, zh: '宽高比', en: 'Aspect ratio'),
              style: sectionStyle,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isImage)
                  for (final preset in _imageRatios)
                    ChoiceChip(
                      label: Text(preset.ratio),
                      selected: _aspectRatio == preset.ratio,
                      onSelected: (_) => setState(() {
                        _aspectRatio = preset.ratio;
                        _size = preset.size;
                      }),
                    ),
                if (isVideo)
                  for (final ratio in _videoRatios)
                    ChoiceChip(
                      label: Text(ratio),
                      selected: _aspectRatio == ratio,
                      onSelected: (_) => setState(() => _aspectRatio = ratio),
                    ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (isVideo || isAudio) ...[
            Text(
              _localizedText(context, zh: '时长 (秒)', en: 'Duration (s)'),
              style: sectionStyle,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in (isVideo ? _videoDurations : _audioDurations))
                  ChoiceChip(
                    label: Text('${d}s'),
                    selected: _duration == d,
                    onSelected: (_) => setState(() => _duration = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text(
            _localizedText(context, zh: '数量', en: 'Count'),
            style: sectionStyle,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton(
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_count',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton(
                  onPressed: _count < 4 ? () => setState(() => _count++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: cs.outlineVariant),
                                textStyle: actionTextStyle,
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              child: Text(
                                _localizedText(context, zh: '取消', en: 'Cancel'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop(
                                  AiCreationOptions(
                                    size: _size,
                                    aspectRatio: _aspectRatio,
                                    durationSeconds: _duration,
                                    count: _count,
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                textStyle: actionTextStyle,
                                minimumSize: const Size(0, 46),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              child: Text(
                                _localizedText(
                                  context,
                                  zh: '确认',
                                  en: 'Confirm',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

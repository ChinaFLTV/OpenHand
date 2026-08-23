import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xterm/xterm.dart';
import 'package:yaml/yaml.dart';

import '../../app/model/app_info.dart';
import '../../app/model/app_settings_snapshot.dart';
import '../../app/model/dialog_animation_settings.dart';
import '../../app/model/editor_code_theme.dart';
import '../../app/model/editor_shortcut.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/input_repair_service.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/openhand_scroll_physics.dart';
import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../app/support/url_validation.dart';
import '../../app/theme/openhand_palette.dart';
import '../../app/theme/openhand_status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/db/database_service.dart';
import '../../shared/net/bounded_http_request.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/net/http_status_utils.dart';
import '../../shared/ui/animated_appearance.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_expandable.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/animated_overlay.dart';
import '../../shared/ui/appear_once.dart';
import '../../shared/ui/appear_tracker.dart';
import '../../shared/ui/auto_follow_scroll_guard.dart';
import '../../shared/ui/bounded_animation.dart';
import '../../shared/ui/choice_input_dialog.dart';
import '../../shared/ui/collision_safe_animated_switcher.dart';
import '../../shared/ui/dialog_motion_css.dart';
import '../../shared/ui/error_snackbar.dart';
import '../../shared/ui/export_config_dialog.dart';
import '../../shared/ui/export_progress_dialog.dart';
import '../../shared/ui/highlight_pulse.dart';
import '../../shared/ui/hover_lift.dart';
import '../../shared/ui/image_editor_dialog.dart';
import '../../shared/ui/interaction_timings.dart';
import '../../shared/ui/interactive_image_preview.dart';
import '../../shared/ui/markdown_ast_sanitizer.dart';
import '../../shared/ui/markdown_inline_code.dart';
import '../../shared/ui/markdown_math.dart';
import '../../shared/ui/markdown_surface_tones.dart';
import '../../shared/ui/media_preview_dialog.dart';
import '../../shared/ui/micro_press_feedback.dart';
import '../../shared/ui/model_search_selector.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/native_audio_preview.dart';
import '../../shared/ui/natural_image_size_resolver.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_animated_title_text.dart';
import '../../shared/ui/openhand_approval_chip.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_clipboard.dart';
import '../../shared/ui/openhand_console_log_panel.dart';
import '../../shared/ui/openhand_countdown_progress_bar.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_file_hover_popup.dart';
import '../../shared/ui/openhand_form_fields.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_metadata_tiles.dart';
import '../../shared/ui/openhand_model_selector_field.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_safe_markdown_body.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_scroll_behaviors.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_sweep_shimmer.dart';
import '../../shared/ui/openhand_tap_region.dart';
import '../../shared/ui/openhand_token_usage_capsule.dart';
import '../../shared/ui/openhand_tooltip_dismissal.dart';
import '../../shared/ui/openhand_trailing_toolbar.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/ui/openhand_video_player_web_styles.dart';
import '../../shared/ui/reasoning_effort_selector.dart';
import '../../shared/ui/rolling_text.dart';
import '../../shared/ui/section_placeholder.dart';
import '../../shared/ui/streaming_text_reveal.dart';
import '../../shared/ui/structured_error_text.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_base64.dart';
import '../../shared/util/bounded_copy.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/bounded_directory_io.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/duration_bounds.dart';
import '../../shared/util/hex_encoding.dart';
import '../../shared/util/html_webview_mount_limiter.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/lifecycle_cache.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/path_safety.dart';
import '../../shared/util/physical_path_safety.dart';
import '../../shared/util/platform_shell.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/text_fingerprint.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/text_search.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/tool_name_normalization.dart';
import '../../shared/util/transcript_list_windowing.dart';
import '../../shared/util/unified_diff.dart'
    show unifiedDiffLines, unifiedDiffLinesFromText;
import '../../shared/util/user_failure_message.dart';
import '../../shared/util/workspace_root_resolver.dart';
import '../agents/index.dart';
import '../ai/index.dart';
import '../android_reverse/index.dart';
import '../crons/index.dart';
import '../harness/index.dart';
import '../hooks/index.dart';
import '../instructions/index.dart';
import '../knowledge_base/index.dart';
import '../machine_terminal/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../message_gateway/index.dart';
import '../plugin_service/index.dart';
import '../services/index.dart';
import '../settings/index.dart';
import '../skills/index.dart';
import '../thread_template_runtime/index.dart';
import '../web_reverse/index.dart';
import 'model/session_cache_hit_trend.dart';
import 'util/editor_indentation.dart';
import 'util/message_path_linking.dart';
import 'util/slash_command_parser.dart';
import 'util/tool_call_argument_parser.dart';
import 'widgets/html_selection_bridge_clipboard.dart';
import 'widgets/token_popup_cache_hit_trend_chart.dart';
part 'widgets/_home_navigation.dart';
part 'widgets/_home_write_command_dialog.dart';
part 'widgets/_home_workspace_view.dart';
part 'widgets/_home_transcript.dart';
part 'widgets/_home_session_toolbar.dart';
part 'widgets/_home_session_metadata_dialog.dart';
part 'widgets/_home_message_bubble.dart';
part 'widgets/_home_audit_dialog.dart';
part 'widgets/_home_message_content.dart';
part 'widgets/_home_tool_call_widgets.dart';
part 'widgets/_home_file_mutation_widgets.dart';
part 'widgets/_home_composer.dart';
part 'widgets/_home_sidebar_tiles.dart';
part 'widgets/_home_message_meta_rows.dart';
part 'widgets/_home_code_highlighting.dart';
part 'widgets/_home_token_dial.dart';
part 'widgets/_home_thread_template_dialog.dart';
part 'widgets/_home_programming_expert_project_dialog.dart';
part 'widgets/_home_programming_expert_file_explorer.dart';
part 'widgets/_home_machine_terminal_panel.dart';
part 'widgets/_home_machine_terminal_file_manager.dart';
part 'widgets/_home_harness_annotations.dart';
part 'widgets/_home_trajectory_dialog.dart';
part 'widgets/_home_motion_tokens.dart';
part 'widgets/_openhand_home_page_helpers.dart';
part 'widgets/_openhand_home_page_prelude.dart';

/// HTML WebView 抽搐 bug 真凶的关键协调信号。
/// 外层 ListView 检测到"用户正在主动滚动"时标记 active，滚动结束（含
/// 宽限期）后标记 inactive。`_HtmlBubbleWebView` 订阅此信号：
/// active 期间只缓存最新高度、不调用 setState，避免平台视图异步测高
/// 反复修改 `maxScrollExtent` 把视口拽回底部；inactive 后才一次性应用
/// 滚动期间累积的最新高度。
class TranscriptScrollActivity extends ValueNotifier<bool> {
  TranscriptScrollActivity() : super(false);

  void markActive() {
    if (!value) value = true;
  }

  void markInactive() {
    if (value) value = false;
  }
}

TranscriptScrollActivity? _maybeTranscriptScrollActivityOf(
  BuildContext context,
) {
  try {
    return context.read<TranscriptScrollActivity>();
  } on ProviderNotFoundException {
    return null;
  }
}

bool _isTranscriptScrollActive(BuildContext context) {
  return _maybeTranscriptScrollActivityOf(context)?.value ?? false;
}

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage>
    with WidgetsBindingObserver {
  /// 当前活跃的 home state 实例引用——`part of` 文件需要通过它取到
  /// [_buildRuntimeContext]、[AiSessionController] 等私有 API。
  /// 同一时刻只会存在一个 OpenHand home page。
  static _OpenHandHomePageState? _activeHomeState;
  static const int _navigationSessionPageSize = 64;
  static const int _androidReverseMcpToolSearchLimit = 8;
  static const List<String> _androidReverseMcpKeywords = <String>[
    ...TemplateRuntimeDependencyRegistry.androidReverseMcpKeywords,
  ];
  static const String _androidReverseMcpFallbackToolSearchQuery =
      TemplateRuntimeDependencyRegistry.androidReverseToolSearchFallbackQuery;
  static const List<String> _androidReverseToolchainRecommendationIds =
      <String>[
        'adb',
        'aapt',
        'apksigner',
        'keytool',
        'apktool',
        'jadx',
        'frida',
        'mitmproxy',
        'radare2',
        'blutter',
        'doldrums',
        'anything_analyzer',
      ];

  final TextEditingController _composerController = SafeTextEditingController();
  // HTML WebView 异步测高协调信号——见 [TranscriptScrollActivity] 注释。
  // 在 ListView build 树顶层用 ListenableProvider 注入，供深层的
  // `_HtmlBubbleWebView` 订阅，实现"用户滚动期间冻结高度应用"。
  final TranscriptScrollActivity _transcriptScrollActivity =
      TranscriptScrollActivity();
  late final ScrollController _messageScrollController =
      OpenHandStableScrollController();
  final AutoFollowProgrammaticScrollWindow _messageProgrammaticScrollWindow =
      AutoFollowProgrammaticScrollWindow();
  final FocusNode _globalShortcutFocusNode = FocusNode();
  final FocusNode _composerFocusNode = FocusNode();
  _ComposerPanelState? _composerPanelState; // 直接引用，替代 GlobalKey.currentState
  final AiWorkspaceInstructionService _workspaceInstructionService =
      AiWorkspaceInstructionService();
  final AiGitSnapshotService _gitSnapshotService = AiGitSnapshotService();
  final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  final AiTranslationService _translationService = AiTranslationService();
  final WebReverseCdpMcpBridge _webReverseCdpMcpBridge =
      WebReverseCdpMcpBridge();

  AppSection _selectedSection = AppSection.workspace;
  int _navigationSessionLimit = _navigationSessionPageSize;
  _CreationMode _creationMode = _CreationMode.none;
  // macOS native menu bridge — see [_initNativeMenuChannel]. Only initialised
  // on macOS, where the system menu bar's "Settings…" item should drive the
  // in-app navigation to the Settings pane.
  MethodChannel? _macosMenuChannel;
  // 当前会话窗口下，本轮临时取消的【指令】ID 集合。
  // 切换会话或发送完成后通常重置；UI 上用胶囊条配合 X / + 切换。
  final Set<String> _skippedInstructionIds = <String>{};
  AiCreationOptions _creationOptions = AiCreationOptions.empty;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;

  /// 最近一次量到的 composer panel 高度，供折叠/展开时反向补偿 transcript scroll。
  double? _lastComposerHeight;
  bool _composerLayoutMeasureScheduled = false;
  bool _autoFollowEnabled = true;
  // True when auto-follow mode is ON but the user has scrolled away from the
  // bottom, so auto-scrolling is temporarily paused until the user scrolls
  // back near the bottom or presses the button to resume. Kept in sync via
  // _syncAutoFollowPausedState() so the composer button can surface a
  // distinct "paused" visual state and offer a "resume & jump to bottom"
  // tap action instead of toggling the mode off.
  bool _autoFollowPaused = false;
  String? _submittingSessionId;
  int _submissionSerial = 0;
  int _queuedMessageSerial = 0;
  final Map<String, int> _activeSubmissionSerialsBySessionId = <String, int>{};
  final Map<String, int> _locallyStoppedSubmissionSerialsBySessionId =
      <String, int>{};
  final Set<String> _locallyStoppedPendingSubmissionSessionIds = <String>{};
  bool _shouldAutoFollowMessages = true;
  bool _pendingForcedScrollToBottom = false;
  bool _queuedForcedScrollToBottom = false;
  bool _scrollToBottomCallbackQueued = false;
  bool _processingQueueInProgress = false;
  bool _pendingAnimatedScrollToBottom = false;
  int _programmaticTranscriptScrollCorrectionDepth = 0;
  bool _userScrollInProgress = false;
  bool _userDragActive = false;
  bool _transcriptLayoutAutoFollowQueued = false;
  bool _scrollToBottomAwaitingPosition = false;
  int _scrollToBottomPositionRetryCounter = 0;
  bool _scrollToBottomSettleQueued = false;
  int _scrollToBottomSettleFramesRemaining = 0;
  int _scrollToBottomStableFrames = 0;
  bool _composerScrollCompensationInProgress = false;
  final Stopwatch _scrollActivityStopwatch = Stopwatch()..start();
  Duration? _lastPointerSignalScrollAt;
  // Pointer-signal scrolling emits a complete start/update/end sequence per
  // tick. Keep a grace window between slow ticks so layout updates cannot
  // re-arm auto-follow while the user is still reading history.
  late final OpenHandDebouncer _userScrollGraceDebouncer = OpenHandDebouncer(
    delay: _userScrollEndGraceDuration,
  );
  static const Duration _userScrollEndGraceDuration = Duration(
    milliseconds: 1800,
  );
  static const Duration _pointerSignalScrollActivityWindow =
      kAutoFollowPointerSignalActivityWindow;
  static const Duration _queuedGuidanceStopSettleTimeout = Duration(
    milliseconds: 1800,
  );
  static const Duration _queuedGuidanceStopSettlePollInterval = Duration(
    milliseconds: 60,
  );
  static const Duration _queuedMessageDispatchDebounce = Duration(
    milliseconds: 600,
  );
  static const int _maxQueuedMessagesPerSession = 32;
  static const Duration _composerClipboardReadTimeout = Duration(seconds: 2);
  static const Duration _composerAttachmentReadIdleTimeout = Duration(
    seconds: 10,
  );
  static const Duration _composerAttachmentReadTotalTimeout = Duration(
    seconds: 30,
  );
  static const Duration _composerAttachmentWriteTimeout = Duration(seconds: 30);
  static const BoundedDeletePolicy _composerTempDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: 4,
        maxDepth: 2,
        operationTimeout: Duration(seconds: 3),
        totalTimeout: Duration(seconds: 8),
      );
  int _composerTransitionMeasurePassesRemaining = 0;
  bool _composerTransitionMeasureQueued = false;
  // 桌面端 WebView 平台视图可能吞掉 PointerScrollEvent，
  // 导致 _userScrollInProgress 未被置位。用 _lastScrollActivityAt 兜底记录
  // 外层 ListView 的 ScrollUpdateNotification，作为独立的后备检测源。
  Duration? _lastScrollActivityAt;
  double? _lastMessageDistanceToBottom;
  static const Duration _scrollActivityWindow = Duration(milliseconds: 1800);
  String? _lastAutoScrollSignature;
  List<_ComposerAttachmentDraft> _pendingAttachments =
      const <_ComposerAttachmentDraft>[];
  final Set<String> _ownedComposerTempPaths = <String>{};
  bool _clipboardAttachmentPasteInProgress = false;
  final Map<String, List<_QueuedMessage>> _queuedMessagesBySessionId =
      <String, List<_QueuedMessage>>{};
  final Set<String> _autoQueuedMessageDispatchSessionIds = <String>{};
  final Set<String> _queuedGuidanceSessionIds = <String>{};
  final Set<String> _queuedGoalResumeSessionIds = <String>{};
  final Map<String, String> _failedQueuedMessageIdsBySessionId =
      <String, String>{};
  final Map<String, _ComposerDraftState> _composerDraftsBySessionId =
      <String, _ComposerDraftState>{};
  final Map<String, AiSessionGoalStartOptions>
  _pendingGoalStartOptionsBySessionId = <String, AiSessionGoalStartOptions>{};
  final Map<String, bool> _collapsedPlanTimelinesBySessionId = <String, bool>{};
  AiSessionDeletionNotice? _handledSessionDeletionNotice;
  int? _runtimeToolPreviewCacheKey;
  AiRuntimeToolPreview? _runtimeToolPreviewCacheValue;
  AiSessionController? _observedSessionController;
  AiGoalContinuationYieldPredicate? _goalContinuationYieldPredicate;
  MessageGatewayController? _observedMessageGatewayController;
  TemplateRuntimeLinkageController? _templateRuntimeLinkageController;
  StreamSubscription<List<WebWriteApprovalRequest>>? _writeApprovalSubscription;
  final Set<String> _handledWriteApprovalDialogIds = <String>{};
  String? _scheduledWriteApprovalDialogId;
  String? _presentingWriteApprovalDialogId;
  String? _presentingWriteApprovalSessionId;
  String? _presentingWriteApprovalSource;
  OpenHandDialogSession<BashCommandApprovalDecision>? _writeApprovalSession;
  bool _suppressWriteApprovalDialogResponse = false;
  AiSessionMode _detachedComposerMode = AiSessionMode.chat;
  bool _detachedFullAccessPermission = false;
  String? _activeComposerSessionId;
  bool _sessionControllerUiSyncQueued = false;
  int _sessionActivationGeneration = 0;
  AppLifecycleState? _appLifecycleState;
  void Function()? _disposeAskUserChoicePresenter;
  InputRepairParticipantToken? _inputRepairParticipantToken;
  int _resumeAutoFollowSuppressionFrames = 0;
  bool _resumeAutoFollowSyncQueued = false;
  final ValueNotifier<double> _navigationWidthNotifier = ValueNotifier<double>(
    _desktopNavigationWidth,
  );

  // 当前运行的 Harness 工程会话；没有运行中会话时为空。
  HarnessOrchestrator? _activeHarnessOrchestrator;
  HarnessSessionConfig? _activeHarnessConfig;
  bool _heFullAccessPermission = false;
  final HarnessSessionPaneController _harnessSessionPaneController =
      HarnessSessionPaneController();

  // 最近一次 Harness 会话的持久化快照，用于应用重启后恢复。
  final HarnessSessionStore _harnessSessionStore = HarnessSessionStore();
  HarnessSessionRecord? _persistedHarnessSession;
  late final OpenHandDebouncer _harnessSessionSaveDebouncer = OpenHandDebouncer(
    delay: _harnessSessionPersistenceDebounce,
  );
  HarnessPhase? _lastHarnessAwaitingApprovalPhase;

  // Web 逆向控制器按会话保存，每个运行中的控制器管理一个浏览器进程和 CDP 通道。
  static const int _maxActiveReverseRuntimes = 4;
  static const int _maxRetainedReverseControllersPerType =
      _maxActiveReverseRuntimes;
  static const int _maxWebReverseRestoreDetectionAttempts = 3;
  final Map<String, WebReverseSessionController> _webReverseControllers =
      <String, WebReverseSessionController>{};
  final Map<String, Future<WebReverseSessionController?>>
  _webReverseRestoreTasks = <String, Future<WebReverseSessionController?>>{};
  final Map<String, String> _webReverseRuntimeMetadataSignatures =
      <String, String>{};
  late final OpenHandDebouncer _webReverseRuntimeMetadataDebouncer =
      OpenHandDebouncer(delay: _webReverseRuntimeMetadataDebounce);

  // Android 逆向控制器按会话保存。
  final Map<String, AndroidReverseSessionController>
  _androidReverseControllers = <String, AndroidReverseSessionController>{};
  final Map<String, String> _androidReverseRuntimeMetadataSignatures =
      <String, String>{};
  final Set<Object> _reverseRuntimeLeases = <Object>{};
  final Map<String, Object> _reverseRuntimeLeasesBySessionId =
      <String, Object>{};
  final Map<String, int> _reverseRuntimeOperationCounts = <String, int>{};
  final Map<String, Future<void>> _reverseRuntimeStopTasks =
      <String, Future<void>>{};
  final Map<String, Future<void>> _reverseControllerDisposalTasks =
      <String, Future<void>>{};

  // Programming Expert: file explorer & inline editor state.
  bool _fileExplorerVisible = false;
  final Set<String> _visibleMachineTerminalPanelSessionIds = <String>{};
  final List<String> _openFilePaths = [];
  static const int _maxOpenEditorTabs = 24;
  String? _activeFilePath;
  String? _editorTabsSessionId;
  late final OpenHandDebouncer _editorTabsSaveDebouncer = OpenHandDebouncer(
    delay: _editorTabsPersistenceDebounce,
  );

  void _toggleFileExplorer() {
    setState(() => _fileExplorerVisible = !_fileExplorerVisible);
  }

  bool _machineTerminalPanelVisibleFor(AiSession? session) {
    if (session == null || session.templateId != kMachineExpertTemplateId) {
      return false;
    }
    return _visibleMachineTerminalPanelSessionIds.contains(session.id);
  }

  void _toggleMachineTerminalPanel(String sessionId) {
    setState(() {
      if (!_visibleMachineTerminalPanelSessionIds.remove(sessionId)) {
        _visibleMachineTerminalPanelSessionIds.add(sessionId);
      }
    });
  }

  void _hideMachineTerminalPanel(String sessionId) {
    if (!_visibleMachineTerminalPanelSessionIds.contains(sessionId)) {
      return;
    }
    setState(() {
      _visibleMachineTerminalPanelSessionIds.remove(sessionId);
    });
  }

  void _showMachineTerminalPanel(String sessionId) {
    if (_visibleMachineTerminalPanelSessionIds.contains(sessionId)) {
      return;
    }
    setState(() {
      _visibleMachineTerminalPanelSessionIds.add(sessionId);
    });
  }

  void _openFileInEditor(String filePath) {
    if (!_openFilePaths.contains(filePath) &&
        _openFilePaths.length >= _maxOpenEditorTabs) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '编辑器最多同时打开 $_maxOpenEditorTabs 个文件，请先关闭一个标签页。',
          en: 'The editor can keep up to $_maxOpenEditorTabs files open. Close a tab first.',
        ),
      );
      return;
    }
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
    _editorTabsSaveDebouncer.schedule(_persistEditorTabs);
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
      silentLog('openhand_home_page', '保存编辑器标签页', error, stack);
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
      if (!mounted || _editorTabsSessionId != sessionId) return;
      if (rows.isEmpty) return;
      final jsonStr = rows.first['value'] as String?;
      if (jsonStr == null || jsonStr.isEmpty) return;
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, Object?>) return;
      final openFiles = decoded['open_files'];
      final activeFile = decoded['active_file'] as String?;
      if (openFiles is List) {
        final validFiles = <String>[];
        final seenFiles = <String>{};
        for (final item in openFiles) {
          if (item is String && item.isNotEmpty && seenFiles.add(item)) {
            validFiles.add(item);
          }
        }
        if (validFiles.length > _maxOpenEditorTabs) {
          validFiles.removeRange(0, validFiles.length - _maxOpenEditorTabs);
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
      silentLog('openhand_home_page', '恢复编辑器标签页', error, stack);
    }
  }

  void _syncEditorTabsForSession(String? sessionId) {
    if (_editorTabsSessionId == sessionId) return;
    // Persist current tabs before switching.
    _editorTabsSaveDebouncer.cancel();
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

  void _cacheHarnessShellState(HarnessOrchestrator? orchestrator) {
    _lastHarnessAwaitingApprovalPhase = orchestrator?.awaitingApprovalPhase;
  }

  AiSessionMode _effectiveComposerMode(AiSessionController sessionController) {
    final session = sessionController.currentSession;
    if (_goalPausedForQueuedMessages(session)) {
      return AiSessionMode.chat;
    }
    return session?.mode ?? _detachedComposerMode;
  }

  AiSendPhase _displaySendPhaseForSession(
    AiSessionController sessionController,
    String? sessionId,
  ) {
    if (sessionId == null) {
      return AiSendPhase.idle;
    }
    final activeSubmissionSerial =
        _activeSubmissionSerialsBySessionId[sessionId];
    if (_locallyStoppedPendingSubmissionSessionIds.contains(sessionId)) {
      return AiSendPhase.idle;
    }
    if (activeSubmissionSerial != null &&
        _locallyStoppedSubmissionSerialsBySessionId[sessionId] ==
            activeSubmissionSerial) {
      return AiSendPhase.idle;
    }
    final controllerPhase = sessionController.sendPhaseForSession(sessionId);
    if (controllerPhase != AiSendPhase.idle) {
      return controllerPhase;
    }
    if (sessionController.canStopResponding(sessionId)) {
      return AiSendPhase.responding;
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
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) {
      return false;
    }
    return sessionController.canStopResponding(sessionId) ||
        _submittingSessionId == sessionId ||
        _activeSubmissionSerialsBySessionId.containsKey(sessionId);
  }

  _WorkspaceSessionSnapshot _workspaceSessionSnapshot(
    AiSessionController controller,
  ) {
    final session = controller.currentSession;
    return _WorkspaceSessionSnapshot(
      session: session,
      sendPhase: _effectiveSendPhase(controller),
      hydrating:
          session != null && controller.isSessionMessagesHydrating(session.id),
      loadError: session == null
          ? null
          : controller.sessionMessageWindowLoadErrorFor(session.id),
      canStop: _canStopCurrentSessionResponse(controller),
      editingMessageId: controller.editingMessageId,
    );
  }

  List<AiSession> _navigationSessions(AiSessionController sessionController) {
    final sessions = sessionController.sessions
        .where((session) => session.isPrimaryWorkspaceSession)
        .toList(growable: false);
    if (sessions.length <= _navigationSessionLimit) {
      return sessions;
    }
    final visible = sessions
        .take(_navigationSessionLimit)
        .toList(growable: true);
    final visibleIds = visible.map((session) => session.id).toSet();
    final retainedIds = <String>{
      ...sessionController.activeSessionIds,
      ..._activeSubmissionSerialsBySessionId.keys,
      if (_submittingSessionId case final sessionId?) sessionId,
      if (sessionController.currentSessionId case final sessionId?) sessionId,
    };
    final retained = <AiSession>[];
    for (final sessionId in retainedIds) {
      if (visibleIds.contains(sessionId)) continue;
      final session = sessionController.sessionById(sessionId);
      if (session == null || !session.isPrimaryWorkspaceSession) continue;
      final isCurrent = sessionId == sessionController.currentSessionId;
      if (isCurrent ||
          _displaySendPhaseForSession(sessionController, sessionId) !=
              AiSendPhase.idle) {
        retained.add(session);
      }
    }
    retained.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<AiSession>.unmodifiable(<AiSession>[...visible, ...retained]);
  }

  Map<String, AiSendPhase> _navigationSendPhases(
    AiSessionController sessionController,
    List<AiSession> sessions,
  ) {
    return <String, AiSendPhase>{
      for (final session in sessions)
        session.id: _displaySendPhaseForSession(sessionController, session.id),
    };
  }

  int _navigationHarnessInsertionIndex(List<AiSession> sessions) {
    final harnessUpdatedAt = _persistedHarnessSession?.updatedAt;
    if (harnessUpdatedAt == null) return -1;
    for (var index = 0; index < sessions.length; index++) {
      if (!sessions[index].updatedAt.isAfter(harnessUpdatedAt)) return index;
    }
    return sessions.length;
  }

  void _loadMoreNavigationSessions() {
    final sessionCount = context
        .read<AiSessionController>()
        .sessions
        .where((session) => session.isPrimaryWorkspaceSession)
        .length;
    if (_navigationSessionLimit >= sessionCount) return;
    setState(() {
      _navigationSessionLimit = math.min(
        sessionCount,
        _navigationSessionLimit + _navigationSessionPageSize,
      );
    });
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

  String _nextQueuedMessageId() {
    _queuedMessageSerial += 1;
    return 'queued-${DateTime.now().microsecondsSinceEpoch}-$_queuedMessageSerial';
  }

  bool _hasRunnableQueuedMessagesForSession(String sessionId) {
    final queue = _queuedMessagesBySessionId[sessionId];
    if (queue == null || queue.isEmpty) {
      return false;
    }
    return _failedQueuedMessageIdsBySessionId[sessionId] != queue.first.id;
  }

  bool _goalPausedForQueuedMessages(AiSession? session) {
    final goal = session?.activeGoal;
    return goal?.status == AiSessionGoalStatus.paused &&
        goal?.statusReason == aiSessionGoalPausedForQueueStatusReason;
  }

  bool _hasQueuedMessageDispatchInFlight(String sessionId) {
    return _autoQueuedMessageDispatchSessionIds.contains(sessionId) ||
        _queuedGuidanceSessionIds.contains(sessionId) ||
        _queuedGoalResumeSessionIds.contains(sessionId);
  }

  Future<bool> _stopCurrentResponseBeforeQueuedGuidance(
    AiSessionController sessionController,
    String sessionId,
  ) async {
    if (!_canStopCurrentSessionResponse(sessionController) || !mounted) {
      return true;
    }
    final stoppedSubmissionSerial =
        _activeSubmissionSerialsBySessionId[sessionId];
    await _stopResponding();

    final deadline = MonotonicDeadline(_queuedGuidanceStopSettleTimeout);
    try {
      while (mounted && !deadline.isExpired) {
        await _awaitEndOfFrame();
        if (!mounted) {
          return false;
        }
        final phase = sessionController.sendPhaseForSession(sessionId);
        final stillStoppingLocalSubmit =
            stoppedSubmissionSerial != null &&
            _activeSubmissionSerialsBySessionId[sessionId] ==
                stoppedSubmissionSerial;
        if (!stillStoppingLocalSubmit) {
          _locallyStoppedPendingSubmissionSessionIds.remove(sessionId);
          if (_locallyStoppedSubmissionSerialsBySessionId[sessionId] ==
              stoppedSubmissionSerial) {
            _locallyStoppedSubmissionSerialsBySessionId.remove(sessionId);
          }
        }
        if (phase == AiSendPhase.idle &&
            !sessionController.canStopResponding(sessionId) &&
            !stillStoppingLocalSubmit) {
          return true;
        }
        await Future.delayed(_queuedGuidanceStopSettlePollInterval);
      }
    } finally {
      deadline.stop();
    }
    return stoppedSubmissionSerial == null ||
        _activeSubmissionSerialsBySessionId[sessionId] !=
            stoppedSubmissionSerial;
  }

  void _setComposerCollapsedState(
    bool collapsed, {
    bool requestFocusWhenExpanded = false,
  }) {
    final changed = _composerCollapsed != collapsed;
    if (changed) {
      setState(() {
        _composerCollapsed = collapsed;
      });
      _scheduleComposerTransitionMeasurements();
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
    _activeHomeState = this;
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
    _inputRepairParticipantToken = InputRepairService.instance
        .registerParticipant(
          debugLabel: '首页',
          onRepair: (phase) async {
            _composerFocusNode.unfocus();
            _globalShortcutFocusNode.unfocus();
            HtmlSelectionBridgeClipboard.clear();
            if (phase == InputRepairParticipantPhase.afterTextInputReset) {
              _composerPanelState?._userDismissAtMentionOverlay();
              _composerPanelState?._userDismissSkillPickerOverlay();
            }
            return const InputRepairParticipantResult.success();
          },
        );
    // 当平台 IME 反向回调 `updateEditingState` 触发
    // `Range start ... is out of text of length ...` 断言时，由
    // `FlutterError.onError` 摘调这个轻量钩子做一次 composer 焦点重置，
    // 避免每次都把完整的 `repair()` 全套（killTrackedChildren +
    // clearTextInputClient + hideTextInput）跑一遍而强行关掉键盘。
    InputRepairService.instance.registerSoftRecoveryHook(
      _runComposerImeSoftRecovery,
    );
    _loadPersistedHarnessSession();
    _initNativeMenuChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    // 窗口失焦、最小化或进入后台时继续朗读；仅在应用真正退出时停止。
    if (state == AppLifecycleState.detached) {
      unawaited(_ttsPlaybackService.stop());
    }
    // 进入后台或失活时立即保存 Harness 会话，避免系统终止进程时丢失状态。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final pendingHarnessRecord = _persistedHarnessSession;
      if (pendingHarnessRecord != null) {
        // 取消延迟任务并立即保存最新快照。
        _harnessSessionSaveDebouncer.cancel();
        unawaited(_persistHarnessSessionBestEffort(pendingHarnessRecord));
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
    _templateRuntimeLinkageController = context
        .read<TemplateRuntimeLinkageController>();
    if (identical(_observedSessionController, sessionController)) {
      return;
    }
    final goalYieldPredicate = _goalContinuationYieldPredicate ??=
        _hasRunnableQueuedMessagesForSession;
    _observedSessionController?.removeGoalContinuationYieldPredicate(
      goalYieldPredicate,
    );
    _observedSessionController?.removeListener(_handleSessionControllerChanged);
    _observedSessionController?.toolSearchLoadedSignal.removeListener(
      _handleToolSearchLoadedSignal,
    );
    _observedSessionController = sessionController;
    _observedSessionController?.addGoalContinuationYieldPredicate(
      goalYieldPredicate,
    );
    _observedSessionController?.addListener(_handleSessionControllerChanged);
    _observedSessionController?.toolSearchLoadedSignal.addListener(
      _handleToolSearchLoadedSignal,
    );
    _activeComposerSessionId = sessionController.currentSessionId;
    final messageGatewayController = _readMessageGatewayController();
    if (!identical(
      _observedMessageGatewayController,
      messageGatewayController,
    )) {
      _cancelWriteApprovalSubscription('替换写入审批流');
      _observedMessageGatewayController = messageGatewayController;
      _writeApprovalSubscription = messageGatewayController
          ?.pendingWriteApprovalsStream
          .listen(
            (approvals) {
              if (!identical(
                _observedMessageGatewayController,
                messageGatewayController,
              )) {
                return;
              }
              _handlePendingWriteApprovalsChanged(approvals);
            },
            onError: (Object error, StackTrace stack) {
              if (identical(
                _observedMessageGatewayController,
                messageGatewayController,
              )) {
                silentLog('openhand_home_page', '写入审批响应流', error, stack);
              }
            },
          );
      _handlePendingWriteApprovalsChanged(
        messageGatewayController?.pendingWriteApprovals ??
            const <WebWriteApprovalRequest>[],
      );
    }
  }

  @override
  void dispose() {
    if (identical(_activeHomeState, this)) {
      _activeHomeState = null;
    }
    _inputRepairParticipantToken?.dispose();
    _inputRepairParticipantToken = null;
    _toolSearchReplayDispatcher.dispose();
    unawaited(_ttsPlaybackService.dispose());
    _translationService.dispose();
    _activeHarnessOrchestrator?.removeListener(_onHarnessOrchestratorChanged);
    _activeHarnessOrchestrator?.cancel();
    _activeHarnessOrchestrator?.dispose();
    // 关闭防抖前先写入逆向运行时的最后状态，避免快速退出丢失最新元数据。
    _syncWebReverseRuntimeMetadata();
    for (final entry in _androidReverseControllers.entries) {
      unawaited(_persistAndroidReverseRuntimeMetadata(entry.key, entry.value));
    }
    _webReverseCdpMcpBridge.dispose();
    for (final entry in _webReverseControllers.entries) {
      unawaited(_disposeWebReverseControllerAfterStop(entry.key, entry.value));
    }
    _webReverseControllers.clear();
    _webReverseRestoreTasks.clear();
    _webReverseRuntimeMetadataDebouncer.cancel();
    _webReverseRuntimeMetadataSignatures.clear();
    for (final entry in _androidReverseControllers.entries) {
      unawaited(_disposeAndroidReverseController(entry.key, entry.value));
    }
    _androidReverseControllers.clear();
    _androidReverseRuntimeMetadataSignatures.clear();
    _reverseRuntimeLeasesBySessionId.clear();
    _reverseRuntimeLeases.clear();
    _reverseRuntimeOperationCounts.clear();
    _reverseRuntimeStopTasks.clear();
    _reverseControllerDisposalTasks.clear();
    _harnessSessionSaveDebouncer.dispose();
    _editorTabsSaveDebouncer.cancel();
    // Flush pending editor tabs before disposal.
    if (_editorTabsSessionId != null) {
      unawaited(_persistEditorTabs());
    }
    final pendingHarnessRecord = _persistedHarnessSession;
    if (pendingHarnessRecord != null) {
      unawaited(_persistHarnessSessionBestEffort(pendingHarnessRecord));
    }
    WidgetsBinding.instance.removeObserver(this);
    final goalYieldPredicate = _goalContinuationYieldPredicate;
    if (goalYieldPredicate != null) {
      _observedSessionController?.removeGoalContinuationYieldPredicate(
        goalYieldPredicate,
      );
    }
    _observedSessionController?.removeListener(_handleSessionControllerChanged);
    _observedSessionController?.toolSearchLoadedSignal.removeListener(
      _handleToolSearchLoadedSignal,
    );
    _observedMessageGatewayController = null;
    _cancelWriteApprovalSubscription('销毁时关闭写入审批流');
    _suppressWriteApprovalDialogResponse = true;
    final writeApprovalSession = _writeApprovalSession;
    _writeApprovalSession = null;
    if (writeApprovalSession != null) {
      unawaited(
        writeApprovalSession.dismiss(logTag: 'home', logAction: '主页销毁时关闭写入审批'),
      );
    }
    _messageScrollController.removeListener(_handleMessageScroll);
    HardwareKeyboard.instance.removeHandler(_handleGlobalShortcutKeyEvent);
    _disposeAskUserChoicePresenter?.call();
    _disposeAskUserChoicePresenter = null;
    _macosMenuChannel?.setMethodCallHandler(null);
    _macosMenuChannel = null;
    _globalShortcutFocusNode.dispose();
    _composerFocusNode.dispose();
    InputRepairService.instance.registerSoftRecoveryHook(null);
    _composerController.dispose();
    _messageScrollController.dispose();
    _navigationWidthNotifier.dispose();
    _userScrollGraceDebouncer.dispose();
    _transcriptScrollActivity.dispose();
    super.dispose();
  }

  void _cancelWriteApprovalSubscription(String action) {
    final subscription = _writeApprovalSubscription;
    _writeApprovalSubscription = null;
    if (subscription == null) return;
    unawaited(
      cancelStreamSubscriptionBounded<List<WebWriteApprovalRequest>>(
        subscription,
        onError: (error, stack) =>
            silentLog('openhand_home_page', action, error, stack),
      ),
    );
  }

  void _clearPendingAutoFollowState() {
    _pendingForcedScrollToBottom = false;
    _queuedForcedScrollToBottom = false;
    _pendingAnimatedScrollToBottom = false;
    _scrollToBottomAwaitingPosition = false;
    _scrollToBottomPositionRetryCounter = 0;
    _scrollToBottomSettleFramesRemaining = 0;
    _scrollToBottomStableFrames = 0;
    _messageProgrammaticScrollWindow.cancel();
  }

  void _handleMessageExpansionChanged(bool _) {
    _shouldAutoFollowMessages = false;
    _clearPendingAutoFollowState();
    _syncAutoFollowPausedState();
  }

  void _pauseAutoFollowUntilExplicitResume() {
    _shouldAutoFollowMessages = false;
    _autoFollowPaused = false;
    _clearPendingAutoFollowState();
  }

  bool _isProgrammaticMessageScrollInProgress() {
    return _messageProgrammaticScrollWindow.active ||
        _programmaticTranscriptScrollCorrectionDepth > 0 ||
        _composerScrollCompensationInProgress;
  }

  bool _isProgrammaticMessageScrollCommandBusy() {
    return _messageProgrammaticScrollWindow.busy ||
        _programmaticTranscriptScrollCorrectionDepth > 0 ||
        _composerScrollCompensationInProgress;
  }

  bool _isUserMessageScrollActivityActive() {
    if (_userScrollInProgress || _hasRecentScrollActivity()) {
      return true;
    }
    if (_isProgrammaticMessageScrollInProgress()) {
      return false;
    }
    return _messageScrollPositionIsActivelyScrolling();
  }

  void _beginProgrammaticMessageScroll() {
    _messageProgrammaticScrollWindow.begin();
  }

  void _endProgrammaticMessageScroll() {
    _messageProgrammaticScrollWindow.end();
  }

  void _runProgrammaticTranscriptScrollCorrection(VoidCallback correction) {
    if (!mounted) return;
    _programmaticTranscriptScrollCorrectionDepth += 1;
    _messageProgrammaticScrollWindow.markSettling();
    try {
      correction();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _programmaticTranscriptScrollCorrectionDepth = math.max(
          0,
          _programmaticTranscriptScrollCorrectionDepth - 1,
        );
        _messageProgrammaticScrollWindow.markSettling();
      });
    }
  }

  /// 标记用户正在主动滚动；取消任何待执行的 scroll-end 宽限计时。
  void _markUserScrollInProgress() {
    _userScrollGraceDebouncer.cancel();
    _userScrollInProgress = true;
    // 广播给订阅者（如 `_HtmlBubbleWebView`），让其在
    // 用户滚动期间冻结高度应用，避免异步测高把 viewport 拽回底部。
    _transcriptScrollActivity.markActive();
  }

  void _handleMessagePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _messageProgrammaticScrollWindow.cancel();
    _lastPointerSignalScrollAt = _scrollActivityStopwatch.elapsed;
    _markUserScrollInProgress();
    _scheduleUserScrollEndGrace();
  }

  bool _hasRecentPointerSignalScrollActivity() {
    final last = _lastPointerSignalScrollAt;
    if (last == null) {
      return false;
    }
    return _scrollActivityStopwatch.elapsed - last <=
        _pointerSignalScrollActivityWindow;
  }

  // 仅记录已确认的用户滚动活动。不要把普通 ScrollUpdateNotification
  // 当作兜底输入源：流式输出、Markdown 测高和 Sliver 几何修正同样会
  // 产生无 dragDetails 的 update，误记后会暂停自动跟随。
  bool _hasRecentScrollActivity() {
    final last = _lastScrollActivityAt;
    if (last == null) {
      return false;
    }
    return _scrollActivityStopwatch.elapsed - last < _scrollActivityWindow;
  }

  bool _messageScrollPositionIsActivelyScrolling() {
    final position = _activeMessageScrollPosition();
    return position?.isScrollingNotifier.value ?? false;
  }

  bool _hasActiveOrRecentMessageScrollActivity() {
    return _isUserMessageScrollActivityActive();
  }

  /// 用户当前 tick 的 scroll-end 已触发，但 trackpad / 滚轮的下一 tick
  /// 可能紧跟到来。在 [_userScrollEndGraceDuration] 内若有新的滚动活动，
  /// `_markUserScrollInProgress` 会取消本计时器；超时未续期则真正放手。
  void _scheduleUserScrollEndGrace() {
    _userScrollGraceDebouncer.schedule(() {
      if (!mounted) {
        return;
      }
      _userScrollInProgress = false;
      // 同步通知订阅者：宽限期结束，HTML WebView 可应用滚动期间累积的
      // 最新高度，触发一次性 setState。
      _transcriptScrollActivity.markInactive();
      if (_autoFollowEnabled &&
          _shouldAutoFollowMessages &&
          (_pendingForcedScrollToBottom || _queuedForcedScrollToBottom)) {
        _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
      }
    });
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
      cancelSignal: request.cancelSignal,
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
    _handleSessionDeletionNotice(sessionController);
    _dismissWriteApprovalDialogIfSessionChanged(
      sessionController?.currentSessionId,
    );
    _handlePendingWriteApprovalsChanged(
      _observedMessageGatewayController?.pendingWriteApprovals ??
          const <WebWriteApprovalRequest>[],
    );
    _scheduleSessionControllerUiSync();
    _processMessageQueueIfNeeded(sessionController);
  }

  MessageGatewayController? _readMessageGatewayController() {
    try {
      return context.read<MessageGatewayController>();
    } catch (_) {
      return null;
    }
  }

  void _dismissWriteApprovalDialogIfSessionChanged(String? currentSessionId) {
    final presentingSessionId = _presentingWriteApprovalSessionId;
    if (presentingSessionId == null ||
        presentingSessionId == currentSessionId ||
        _presentingWriteApprovalSource == 'dingtalk_gateway') {
      return;
    }
    _suppressWriteApprovalDialogResponse = true;
    final session = _writeApprovalSession;
    if (session != null) {
      unawaited(session.dismiss(logTag: 'home', logAction: '会话切换后关闭写入审批'));
    }
  }

  void _handlePendingWriteApprovalsChanged(
    List<WebWriteApprovalRequest> approvals,
  ) {
    if (!mounted) return;
    final pendingIds = approvals.map((item) => item.id).toSet();
    final scheduledId = _scheduledWriteApprovalDialogId;
    if (scheduledId != null && !pendingIds.contains(scheduledId)) {
      _scheduledWriteApprovalDialogId = null;
    }
    _handledWriteApprovalDialogIds.removeWhere(
      (id) =>
          !pendingIds.contains(id) &&
          id != _presentingWriteApprovalDialogId &&
          id != _scheduledWriteApprovalDialogId,
    );
    final presentingId = _presentingWriteApprovalDialogId;
    if (presentingId != null) {
      if (!pendingIds.contains(presentingId)) {
        final session = _writeApprovalSession;
        if (session != null) {
          unawaited(
            session.dismiss(logTag: 'home', logAction: '关闭已在外部解决的写入审批'),
          );
        }
      }
      return;
    }
    if (_scheduledWriteApprovalDialogId != null) {
      return;
    }
    for (final approval in approvals) {
      final isDingTalkApproval = approval.source == 'dingtalk_gateway';
      final currentSessionId = _observedSessionController?.currentSessionId;
      if (!isDingTalkApproval &&
          (currentSessionId == null ||
              currentSessionId.isEmpty ||
              approval.sessionId != currentSessionId)) {
        continue;
      }
      if (_handledWriteApprovalDialogIds.contains(approval.id)) {
        continue;
      }
      _scheduledWriteApprovalDialogId = approval.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scheduledWriteApprovalDialogId == approval.id) {
          _scheduledWriteApprovalDialogId = null;
        }
        if (!mounted) {
          return;
        }
        unawaited(_presentSharedWriteApprovalDialog(approval));
      });
      return;
    }
  }

  Future<void> _presentSharedWriteApprovalDialog(
    WebWriteApprovalRequest approval,
  ) async {
    final gatewayController =
        _observedMessageGatewayController ?? _readMessageGatewayController();
    if (gatewayController == null || !mounted) {
      return;
    }
    if (_presentingWriteApprovalDialogId != null ||
        _handledWriteApprovalDialogIds.contains(approval.id)) {
      return;
    }
    if (approval.source != 'dingtalk_gateway' &&
        _observedSessionController?.currentSessionId != approval.sessionId) {
      return;
    }
    if (!gatewayController.pendingWriteApprovals.any(
      (item) => item.id == approval.id,
    )) {
      return;
    }

    _presentingWriteApprovalDialogId = approval.id;
    _presentingWriteApprovalSessionId = approval.sessionId;
    _presentingWriteApprovalSource = approval.source;
    _suppressWriteApprovalDialogResponse = false;
    _handledWriteApprovalDialogIds.add(approval.id);
    var responseAttempted = false;
    OpenHandDialogSession<BashCommandApprovalDecision>? dialogSession;
    try {
      final session = showWriteCommandConfirmationDialogSession(
        context,
        request: approval.toBashCommandApprovalRequest(),
      );
      dialogSession = session;
      _writeApprovalSession = session;
      final decision = await session.result;
      if (!mounted ||
          _suppressWriteApprovalDialogResponse ||
          !gatewayController.pendingWriteApprovals.any(
            (item) => item.id == approval.id,
          )) {
        return;
      }
      responseAttempted = true;
      gatewayController.respondWriteApproval(
        approval.id,
        decision: decision ?? BashCommandApprovalDecision.dismissed,
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '显示共享写入审批', error, stack);
      if (!responseAttempted &&
          mounted &&
          !_suppressWriteApprovalDialogResponse &&
          gatewayController.pendingWriteApprovals.any(
            (item) => item.id == approval.id,
          )) {
        try {
          gatewayController.respondWriteApproval(
            approval.id,
            decision: BashCommandApprovalDecision.dismissed,
          );
        } catch (fallbackError, fallbackStack) {
          silentLog(
            'openhand_home_page',
            '关闭共享写入审批失败',
            fallbackError,
            fallbackStack,
          );
        }
      }
    } finally {
      final suppressed = _suppressWriteApprovalDialogResponse;
      if (suppressed) {
        _handledWriteApprovalDialogIds.remove(approval.id);
      }
      if (_presentingWriteApprovalDialogId == approval.id) {
        _presentingWriteApprovalDialogId = null;
      }
      if (_presentingWriteApprovalSessionId == approval.sessionId) {
        _presentingWriteApprovalSessionId = null;
      }
      if (_presentingWriteApprovalSource == approval.source) {
        _presentingWriteApprovalSource = null;
      }
      if (identical(_writeApprovalSession, dialogSession)) {
        _writeApprovalSession = null;
      }
      _suppressWriteApprovalDialogResponse = false;
      if (mounted) {
        _handlePendingWriteApprovalsChanged(
          gatewayController.pendingWriteApprovals,
        );
      }
    }
  }

  void _handleSessionDeletionNotice(AiSessionController? sessionController) {
    final notice = sessionController?.lastDeletionNotice;
    if (notice == null || identical(_handledSessionDeletionNotice, notice)) {
      return;
    }
    _handledSessionDeletionNotice = notice;
    _releaseDeletedSessionState(notice.sessionId);
    if (!notice.wasCurrentSession || notice.source == 'app') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deletedBy = notice.deletedByLabel.trim().isEmpty
          ? openHandLocalizedText(context, zh: 'Web 用户', en: 'a Web user')
          : notice.deletedByLabel.trim();
      unawaited(
        showOpenHandInfoDialog(
          context: context,
          title: openHandLocalizedText(
            context,
            zh: '当前线程已被删除',
            en: 'Current Thread Deleted',
          ),
          message: openHandLocalizedText(
            context,
            zh: '当前会话「${notice.sessionTitle}」已被 $deletedBy 删除。',
            en: 'The current session "${notice.sessionTitle}" was deleted by $deletedBy.',
          ),
          closeLabel: openHandBackLabel(context),
          barrierDismissible: false,
        ),
      );
    });
  }

  void _releaseDeletedSessionState(String sessionId) {
    _activeSubmissionSerialsBySessionId.remove(sessionId);
    _locallyStoppedSubmissionSerialsBySessionId.remove(sessionId);
    _locallyStoppedPendingSubmissionSessionIds.remove(sessionId);
    final removedQueue = _queuedMessagesBySessionId.remove(sessionId);
    if (removedQueue != null) {
      _releaseComposerTempPaths(
        removedQueue.expand(
          (message) => message.attachments.map((item) => item.filePath),
        ),
      );
    }
    _autoQueuedMessageDispatchSessionIds.remove(sessionId);
    _queuedGuidanceSessionIds.remove(sessionId);
    _queuedGoalResumeSessionIds.remove(sessionId);
    _failedQueuedMessageIdsBySessionId.remove(sessionId);
    _pendingGoalStartOptionsBySessionId.remove(sessionId);
    _collapsedPlanTimelinesBySessionId.remove(sessionId);
    _removeComposerDraftForSession(sessionId);
    _visibleMachineTerminalPanelSessionIds.remove(sessionId);
    if (_submittingSessionId == sessionId) {
      _submittingSessionId = null;
    }

    final webReverseController = _webReverseControllers.remove(sessionId);
    _webReverseRestoreTasks.remove(sessionId);
    _webReverseRuntimeMetadataSignatures.remove(sessionId);
    _webReverseCdpMcpBridge.stopSession(sessionId);
    if (webReverseController != null) {
      unawaited(
        _disposeWebReverseControllerAfterStop(sessionId, webReverseController),
      );
    }

    final androidReverseController = _androidReverseControllers.remove(
      sessionId,
    );
    _androidReverseRuntimeMetadataSignatures.remove(sessionId);
    if (androidReverseController != null) {
      unawaited(
        _disposeAndroidReverseController(sessionId, androidReverseController),
      );
    }
    if (webReverseController == null &&
        androidReverseController == null &&
        !_reverseRuntimeOperationCounts.containsKey(sessionId) &&
        !_reverseRuntimeStopTasks.containsKey(sessionId) &&
        !_reverseControllerDisposalTasks.containsKey(sessionId)) {
      _releaseReverseRuntimeSlot(sessionId);
    }
    _removeTemplateRuntimeLinkage(sessionId);
  }

  /// 监听 [AiSessionController.toolSearchLoadedSignal]：当模型成功通过
  /// `ToolSearch` 加载若干 MCP 工具时，仅在事件指向当前会话时弹出 SnackBar。
  int _lastObservedToolSearchRevision = 0;
  void _handleToolSearchLoadedSignal() {
    if (!mounted) return;
    final controller = _observedSessionController;
    if (controller == null) return;
    final event = controller.toolSearchLoadedSignal.value;
    if (event == null) return;
    if (event.revision == _lastObservedToolSearchRevision) return;
    _lastObservedToolSearchRevision = event.revision;
    if (event.sessionId != controller.currentSessionId) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    _showToolSearchLoadedSnack(
      message: l10n.snackToolSearchLoaded(
        event.loadedCount,
        event.totalDeferred,
      ),
      actionLabel: l10n.snackToolSearchLoadedAction,
      onViewDetails: () {
        final controller = _observedSessionController;
        final sessionId = event.sessionId;
        final names = controller == null
            ? const <String>[]
            : controller.loadedMcpToolNamesForSession(sessionId);
        final history = controller == null
            ? const <AiToolSearchLoadHistoryEntry>[]
            : controller.loadedMcpToolHistoryForSession(sessionId);
        _showToolSearchLoadedDialog(
          names: names,
          history: history,
          onClear: controller == null
              ? null
              : () => controller.clearLoadedMcpToolsForSession(sessionId),
          onReplayBatch: _replayToolSearchSelectQuery,
        );
      },
    );
  }

  /// ToolSearch 批量加载提示条：AI 会话与 Harness phase 两条链路共用同一
  /// 外观（放大镜图标 + 文案 + 「查看」动作），只有文案与动作回调不同。
  void _showToolSearchLoadedSnack({
    required String message,
    required String actionLabel,
    required VoidCallback onViewDetails,
  }) {
    showOpenHandSnackBarOn(
      context,
      ScaffoldMessenger.maybeOf(context),
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18),
            kOpenHandHGap8,
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: actionLabel, onPressed: onViewDetails),
      ),
    );
  }

  /// Harness ToolSearch 重放反悔窗口由
  /// [SettingsController.toolSearchReplayCancelWindowSeconds] 提供
  /// （默认 3 秒，范围 1..30）；dispatcher 自身不再持有硬编码默认。
  late final ToolSearchReplayDispatcher _toolSearchReplayDispatcher =
      ToolSearchReplayDispatcher();

  /// Harness 阶段没有共享 tracker，因此本地维护一份按 phase-session 分桶的
  /// ToolSearch 历史时间线，供 dialog 展示。用 [LinkedHashMap] 的插入序
  /// 天然实现 LRU：每次写入都先 remove 再 put，让最近活跃的 phase 落在
  /// Map 末尾；新增时若超过用户配置的上限（运行时读自
  /// [SettingsController.harnessToolSearchHistoryMaxPhases]，默认值由
  /// [AppSettingsSnapshot.defaultHarnessToolSearchHistoryMaxPhases] 给出，
  /// 上下界 1..64），淘汰最早的 phase 桶，防止长会话内存膨胀（即使
  /// onPhaseEnded 因异常路径漏调也兜底）。
  final Map<String, List<AiToolSearchLoadHistoryEntry>>
  _harnessToolSearchHistory = <String, List<AiToolSearchLoadHistoryEntry>>{};

  /// 获取（或创建）指定 phase 的历史桶，并将其在 LRU Map 中提升为最近使用。
  List<AiToolSearchLoadHistoryEntry> _touchHarnessHistoryBucket(
    String phaseSessionId,
  ) {
    final existing = _harnessToolSearchHistory.remove(phaseSessionId);
    final bucket = existing ?? <AiToolSearchLoadHistoryEntry>[];
    _harnessToolSearchHistory[phaseSessionId] = bucket;
    final cap = context
        .read<SettingsController>()
        .harnessToolSearchHistoryMaxPhases;
    while (_harnessToolSearchHistory.length > cap) {
      _harnessToolSearchHistory.remove(_harnessToolSearchHistory.keys.first);
    }
    return bucket;
  }

  void _handleHarnessToolSearchLoaded({
    required String phaseSessionId,
    required List<String> loadedNames,
    required int totalLoadedSoFar,
    required int totalDeferred,
    required String query,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final entry = AiToolSearchLoadHistoryEntry(
      timestamp: DateTime.now().toUtc(),
      query: query,
      addedNames: loadedNames,
      totalDeferred: totalDeferred,
      source: AiToolSearchLoadSource.harnessPhase,
    );
    _touchHarnessHistoryBucket(phaseSessionId).add(entry);
    _showToolSearchLoadedSnack(
      message: l10n.snackToolSearchLoaded(loadedNames.length, totalDeferred),
      actionLabel: l10n.snackToolSearchLoadedAction,
      // Harness phase 自身的 tool loop 是自治的，无法直接重放；用户的意图
      // 通常是「我想再加载这一批」——为了不污染当前 Harness 活跃会话的
      // 上下文，专门走「先建独立 AI session 再在新 session 里发 select:」。
      onViewDetails: () => _showToolSearchLoadedDialog(
        names: List<String>.from(loadedNames)..sort(),
        history: List<AiToolSearchLoadHistoryEntry>.unmodifiable(
          _harnessToolSearchHistory[phaseSessionId] ??
              const <AiToolSearchLoadHistoryEntry>[],
        ),
        onReplayBatch: _replayToolSearchInFreshSession,
      ),
    );
  }

  /// HarnessApiPhaseRunner.runPhase 在结束（成功/失败/取消/异常）时回调
  /// 本方法。借机清理 [_harnessToolSearchHistory] 中与该 phase 关联的
  /// 加载历史，避免长期累积。
  void _handleHarnessPhaseEnded({required String phaseSessionId}) {
    _harnessToolSearchHistory.remove(phaseSessionId);
  }

  void _showToolSearchLoadedDialog({
    required List<String> names,
    void Function()? onClear,
    List<AiToolSearchLoadHistoryEntry> history =
        const <AiToolSearchLoadHistoryEntry>[],
    Future<void> Function(List<String> names)? onReplayBatch,
  }) {
    if (!mounted) return;
    unawaited(
      showToolSearchLoadedDialog(
        context,
        names: names,
        onClear: onClear,
        history: history,
        onReplayBatch: onReplayBatch,
      ),
    );
  }

  /// 把一组 MCP 工具名打包成 `select:N1, select:N2, …`，写进 composer
  /// 并等待 [SettingsController.toolSearchReplayCancelWindowSeconds]
  /// 秒后才提交，期间用户可以通过 SnackBarAction 撤销。等价于用户手动
  /// 复制粘贴后回车，但多了一个可配置（1..30s）的反悔窗口。
  /// 由 [_showToolSearchLoadedDialog] 历史条目点击触发。
  Future<void> _replayToolSearchSelectQuery(List<String> names) async {
    if (!mounted || names.isEmpty) return;
    final query = names.map((n) => 'select:$n').join(', ');
    _replaceComposerTextAndRefocus(query);

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final cancelWindow = Duration(
      seconds: context
          .read<SettingsController>()
          .toolSearchReplayCancelWindowSeconds,
    );
    final completer = Completer<void>();

    void onCancel() {
      // 仅在 composer 仍然展示我们刚塞进去的内容时清空，避免误删
      // 用户在反悔窗口内手动续写的文字。
      if (_composerController.text == query) {
        _composerController.clear();
      }
      if (mounted && l10n != null) {
        replaceOpenHandSnack(
          context,
          l10n.snackToolSearchLoadedReplayCancelledToast,
          duration: kOpenHandSnackBarBriefDuration,
        );
      }
      if (!completer.isCompleted) completer.complete();
    }

    Future<void> onFire() async {
      if (!mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      await _sendMessage();
      if (!mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final l10nNow = AppLocalizations.of(context);
      final messengerNow = ScaffoldMessenger.maybeOf(context);
      if (l10nNow != null && messengerNow != null) {
        showOpenHandSnackBarOn(
          context,
          messengerNow,
          OpenHandSnackBar.success(
            context,
            l10nNow.snackToolSearchLoadedReplayedToast,
          ),
        );
      }
      if (!completer.isCompleted) completer.complete();
    }

    if (l10n != null && messenger != null) {
      showOpenHandSnackBarOn(
        context,
        messenger,
        SnackBar(
          content: Text(l10n.snackToolSearchLoadedReplayPendingToast),
          behavior: SnackBarBehavior.floating,
          duration: cancelWindow,
          action: SnackBarAction(
            label: l10n.snackToolSearchLoadedReplayCancelAction,
            onPressed: _toolSearchReplayDispatcher.cancel,
          ),
        ),
      );
    }

    _toolSearchReplayDispatcher.schedule(
      onFire: onFire,
      onCancel: onCancel,
      window: cancelWindow,
    );

    return completer.future;
  }

  /// Harness 路径专用：先创建一个全新 AI session，再在新 session 里
  /// 发起 select: 查询，避免污染当前 harness 活跃会话的上下文。
  /// 模板沿用当前 AI session 的 templateId（若有），否则 fallback
  /// 到模板仓库的第一个模板。
  Future<void> _replayToolSearchInFreshSession(List<String> names) async {
    if (!mounted || names.isEmpty) return;
    final sessionController = context.read<AiSessionController>();
    final fallbackTemplate =
        sessionController.availableTemplates.firstOrNull ??
        sessionController.templateRepository.templates.first;
    final fallbackTemplateId =
        sessionController.currentSession?.templateId ?? fallbackTemplate.id;
    final initialMode = AiSessionMode.fromStorage(
      context.read<SettingsController>().aiDefaultSessionMode,
    );
    await replayToolSearchInFreshSession(
      names: names,
      createSession: () => _createSession(
        templateId: fallbackTemplateId,
        initialMode: initialMode,
      ),
      replayInCurrentSession: (replayNames) async {
        if (!mounted) return;
        await _replayToolSearchSelectQuery(replayNames);
      },
    );
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
        _syncEditorTabsForSession(sessionController?.currentSessionId);
      }),
    );
  }

  Future<void> _dispatchQueuedMessageForSession(
    AiSessionController sessionController, {
    required String sessionId,
    required int index,
    required bool guidance,
  }) async {
    if (guidance) {
      if (_queuedGuidanceSessionIds.contains(sessionId)) {
        return;
      }
    } else {
      if (_autoQueuedMessageDispatchSessionIds.contains(sessionId) ||
          _queuedGuidanceSessionIds.contains(sessionId)) {
        return;
      }
    }
    final queue = _queuedMessagesBySessionId[sessionId];
    if (queue == null || index < 0 || index >= queue.length) {
      return;
    }
    final queuedMessage = queue[index];
    var removed = false;
    setState(() {
      final liveQueue = _queuedMessagesBySessionId[sessionId];
      if (liveQueue == null ||
          index < 0 ||
          index >= liveQueue.length ||
          liveQueue[index].id != queuedMessage.id) {
        return;
      }
      removed = true;
      if (guidance) {
        _queuedGuidanceSessionIds.add(sessionId);
      } else {
        _autoQueuedMessageDispatchSessionIds.add(sessionId);
      }
      _failedQueuedMessageIdsBySessionId.remove(sessionId);
      liveQueue.removeAt(index);
      if (liveQueue.isEmpty) {
        _queuedMessagesBySessionId.remove(sessionId);
      }
    });
    if (!removed) {
      return;
    }
    if (guidance) {
      final stopped = await _stopCurrentResponseBeforeQueuedGuidance(
        sessionController,
        sessionId,
      );
      if (!stopped) {
        if (mounted) {
          setState(() {
            final liveQueue =
                _queuedMessagesBySessionId[sessionId] ?? <_QueuedMessage>[];
            if (!liveQueue.any((item) => item.id == queuedMessage.id)) {
              final insertAt = index.clamp(0, liveQueue.length).toInt();
              liveQueue.insert(insertAt, queuedMessage);
              _queuedMessagesBySessionId[sessionId] = liveQueue;
            }
            _failedQueuedMessageIdsBySessionId[sessionId] = queuedMessage.id;
            _queuedGuidanceSessionIds.remove(sessionId);
          });
        } else {
          _queuedGuidanceSessionIds.remove(sessionId);
        }
        return;
      }
    }
    final sentOutcome = await _submitTextToSession(
      sessionId,
      queuedMessage.text,
      queuedMessage.attachments,
      responseModalities: queuedMessage.creationRequest.responseModalities,
      creationRequest: queuedMessage.creationRequest,
      additionalSystemReminders: queuedMessage.systemReminders,
      selectedSkillMetadata: queuedMessage.skillMetadata,
      allowQueuedGoalInterruption: true,
      processQueueAfterCompletion: false,
    );
    final shouldRetryBlock =
        sentOutcome == _SubmitTextOutcome.failedBeforeSubmit ||
        (sentOutcome == _SubmitTextOutcome.stoppedBeforeSubmit &&
            (guidance || !_queuedGuidanceSessionIds.contains(sessionId)));
    if (!mounted) {
      if (guidance) {
        _queuedGuidanceSessionIds.remove(sessionId);
      } else {
        _autoQueuedMessageDispatchSessionIds.remove(sessionId);
      }
      return;
    }
    if (sentOutcome != _SubmitTextOutcome.submitted) {
      setState(() {
        final liveQueue =
            _queuedMessagesBySessionId[sessionId] ?? <_QueuedMessage>[];
        if (!liveQueue.any((item) => item.id == queuedMessage.id)) {
          final insertAt = index.clamp(0, liveQueue.length).toInt();
          liveQueue.insert(insertAt, queuedMessage);
          _queuedMessagesBySessionId[sessionId] = liveQueue;
        }
        if (shouldRetryBlock) {
          _failedQueuedMessageIdsBySessionId[sessionId] = queuedMessage.id;
        }
      });
    } else if (_failedQueuedMessageIdsBySessionId[sessionId] ==
        queuedMessage.id) {
      _failedQueuedMessageIdsBySessionId.remove(sessionId);
    }
    setState(() {
      if (guidance) {
        _queuedGuidanceSessionIds.remove(sessionId);
      } else {
        _autoQueuedMessageDispatchSessionIds.remove(sessionId);
      }
    });
    if (sentOutcome == _SubmitTextOutcome.submitted || shouldRetryBlock) {
      _processMessageQueueIfNeeded(sessionController);
    }
  }

  Future<void> _resumeGoalAfterQueuedMessagesIfNeeded(
    AiSessionController sessionController,
    AiSession session,
  ) async {
    final sessionId = session.id;
    if (!_goalPausedForQueuedMessages(session) ||
        _hasRunnableQueuedMessagesForSession(sessionId) ||
        _hasQueuedMessageDispatchInFlight(sessionId) ||
        _displaySendPhaseForSession(sessionController, sessionId) !=
            AiSendPhase.idle ||
        _submittingSessionId == sessionId) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      session,
    );
    if (selectedModel == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _queuedGoalResumeSessionIds.add(sessionId);
    });
    try {
      final latestSession = _sessionForId(sessionController, sessionId);
      if (!mounted ||
          latestSession == null ||
          !_goalPausedForQueuedMessages(latestSession) ||
          _hasRunnableQueuedMessagesForSession(sessionId) ||
          _displaySendPhaseForSession(sessionController, sessionId) !=
              AiSendPhase.idle) {
        return;
      }
      final runtimeContext = await _buildRuntimeContext(
        workingDirectory: _programmingExpertProjectRoot(latestSession),
        skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
      );
      if (!mounted ||
          !_goalPausedForQueuedMessages(
            _sessionForId(sessionController, sessionId),
          ) ||
          _hasRunnableQueuedMessagesForSession(sessionId)) {
        return;
      }
      final currentSession =
          _sessionForId(sessionController, sessionId) ?? latestSession;
      final requireWriteConfirmation =
          AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
            templateId: currentSession.templateId,
            fullAccessPermission: currentSession.fullAccessPermission,
            globalConfirmationEnabled:
                settingsController.aiWriteCommandConfirmationEnabled,
          );
      final ok = await sessionController.resumeGoal(
        sessionId: sessionId,
        model: selectedModel,
        runtimeContext: runtimeContext,
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation: requireWriteConfirmation,
        confirmWriteCommand: (request) =>
            _confirmWriteCommand(request, sessionId: sessionId),
      );
      if (!ok && mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: sessionController.lastErrorMessageForSession(sessionId),
          fallback: AppLocalizations.of(context)!.chatRequestFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _queuedGoalResumeSessionIds.remove(sessionId);
        });
      } else {
        _queuedGoalResumeSessionIds.remove(sessionId);
      }
    }
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
      await Future.delayed(_queuedMessageDispatchDebounce);
      if (!mounted || _submittingSessionId != null) return;

      var dispatchedQueuedMessage = false;
      for (final session in sessionController.sessions) {
        final sessionId = session.id;
        if (_hasQueuedMessageDispatchInFlight(sessionId)) {
          continue;
        }
        final phase = _displaySendPhaseForSession(sessionController, sessionId);
        if (phase == AiSendPhase.idle && _submittingSessionId != sessionId) {
          final q = _queuedMessagesBySessionId[sessionId];
          if (q != null && q.isNotEmpty) {
            if (_failedQueuedMessageIdsBySessionId[sessionId] == q.first.id) {
              continue;
            }
            // Re-check guards before dequeue to avoid dropping a queued item
            // while the AI phase is still settling.
            if (_submittingSessionId != null) break;
            final nextPhase = _displaySendPhaseForSession(
              sessionController,
              sessionId,
            );
            if (nextPhase != AiSendPhase.idle) {
              break;
            }
            if (_effectiveModelForSession(
                  context.read<SettingsController>(),
                  session,
                ) ==
                null) {
              break;
            }
            unawaited(
              _dispatchQueuedMessageForSession(
                sessionController,
                sessionId: sessionId,
                index: 0,
                guidance: false,
              ),
            );
            dispatchedQueuedMessage = true;
            break; // Process one at a time across all sessions
          }
        }
      }
      if (dispatchedQueuedMessage) {
        return;
      }
      for (final session in sessionController.sessions) {
        final sessionId = session.id;
        if (_hasQueuedMessageDispatchInFlight(sessionId) ||
            _hasRunnableQueuedMessagesForSession(sessionId)) {
          continue;
        }
        if (_goalPausedForQueuedMessages(session) &&
            _displaySendPhaseForSession(sessionController, sessionId) ==
                AiSendPhase.idle) {
          unawaited(
            _resumeGoalAfterQueuedMessagesIfNeeded(sessionController, session),
          );
          break;
        }
      }
    } finally {
      _processingQueueInProgress = false;
    }
  }

  String _composerDraftKeyForSessionId(String? sessionId) {
    final normalized = sessionId?.trim() ?? '';
    return normalized.isEmpty ? _detachedComposerDraftSessionKey : normalized;
  }

  void _removeComposerDraftForSession(String? sessionId) {
    final removed = _composerDraftsBySessionId.remove(
      _composerDraftKeyForSessionId(sessionId),
    );
    if (removed != null) {
      _releaseComposerTempPaths(
        removed.attachments.map((item) => item.filePath),
      );
    }
  }

  void _storeComposerDraftForSession(
    String? sessionId, {
    String? text,
    List<_ComposerAttachmentDraft>? attachments,
    AiCreationRequest? creationRequest,
  }) {
    final resolvedText = text ?? _composerController.text;
    final resolvedAttachments = List<_ComposerAttachmentDraft>.from(
      attachments ?? _pendingAttachments,
    );
    final resolvedCreationRequest =
        creationRequest ?? _creationRequestFromComposer(_creationMode);
    if (resolvedText.trim().isEmpty &&
        resolvedAttachments.isEmpty &&
        !resolvedCreationRequest.isActive) {
      _removeComposerDraftForSession(sessionId);
      return;
    }
    final key = _composerDraftKeyForSessionId(sessionId);
    final previous = _composerDraftsBySessionId[key];
    _composerDraftsBySessionId[key] = _ComposerDraftState(
      text: resolvedText,
      attachments: resolvedAttachments,
      creationRequest: resolvedCreationRequest,
    );
    if (previous != null) {
      _releaseComposerTempPaths(
        previous.attachments.map((item) => item.filePath),
      );
    }
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

  bool _sameCreationOptions(AiCreationOptions left, AiCreationOptions right) {
    return left.size == right.size &&
        left.aspectRatio == right.aspectRatio &&
        left.durationSeconds == right.durationSeconds &&
        left.count == right.count &&
        left.quality == right.quality &&
        left.style == right.style &&
        left.outputFormat == right.outputFormat &&
        left.background == right.background &&
        left.negativePrompt == right.negativePrompt &&
        left.promptEnhance == right.promptEnhance &&
        left.watermark == right.watermark &&
        left.seed == right.seed &&
        left.resolution == right.resolution &&
        left.frameRate == right.frameRate &&
        left.numFrames == right.numFrames &&
        left.mode == right.mode &&
        left.voice == right.voice &&
        left.speed == right.speed &&
        left.sampleRate == right.sampleRate &&
        left.bitrate == right.bitrate &&
        left.volume == right.volume &&
        left.pitch == right.pitch &&
        left.languageBoost == right.languageBoost &&
        left.emotion == right.emotion &&
        left.textNormalization == right.textNormalization &&
        left.latexRead == right.latexRead &&
        left.channel == right.channel &&
        left.forceCbr == right.forceCbr &&
        left.subtitleEnable == right.subtitleEnable &&
        left.subtitleType == right.subtitleType &&
        listEquals(left.pronunciationTone, right.pronunciationTone) &&
        jsonEncode(left.timbreWeights) == jsonEncode(right.timbreWeights) &&
        jsonEncode(left.voiceModify) == jsonEncode(right.voiceModify);
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
    final currentCreationRequest = _creationRequestFromComposer(_creationMode);
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
        creationRequest: currentCreationRequest,
      );
      _removeComposerDraftForSession(null);
    } else if (!shouldPreserveSubmittingDraft) {
      _storeComposerDraftForSession(
        previousSessionId,
        text: currentText,
        attachments: currentAttachments,
        creationRequest: currentCreationRequest,
      );
    }
    _activeComposerSessionId = nextSessionId;

    // 目标会话正在发送消息时不恢复草稿。
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
    final nextCreationRequest =
        nextDraft?.creationRequest ?? AiCreationRequest.none;
    final nextCreationState = _composerCreationStateFromRequest(
      nextCreationRequest,
    );
    final attachmentsChanged = !_sameComposerAttachments(
      _pendingAttachments,
      nextAttachments,
    );
    final creationChanged =
        _creationMode != nextCreationState.mode ||
        !_sameCreationOptions(_creationOptions, nextCreationState.options);
    if (_composerController.text != nextText) {
      _replaceComposerText(nextText);
    }
    final hasRestoredDraft =
        nextText.trim().isNotEmpty ||
        nextAttachments.isNotEmpty ||
        nextCreationRequest.isActive;
    if (!attachmentsChanged &&
        !creationChanged &&
        (!hasRestoredDraft || !_composerCollapsed)) {
      return;
    }
    setState(() {
      _pendingAttachments = List<_ComposerAttachmentDraft>.from(
        nextAttachments,
      );
      _creationMode = nextCreationState.mode;
      _creationOptions = nextCreationState.options;
      if (hasRestoredDraft) {
        _composerCollapsed = false;
      }
    });
    _releaseComposerTempPaths(currentAttachments.map((item) => item.filePath));
  }

  bool _armAutoFollowToBottom({bool notifyPausedState = true}) {
    if (!_autoFollowEnabled) {
      _pauseAutoFollowUntilExplicitResume();
      return false;
    }
    final previousPaused = _autoFollowPaused;
    _shouldAutoFollowMessages = true;
    _pendingForcedScrollToBottom = true;
    _autoFollowPaused = false;
    if (!notifyPausedState || !mounted || previousPaused == _autoFollowPaused) {
      return true;
    }
    setState(() {});
    return true;
  }

  bool _requestFollowToLatest({
    bool animated = true,
    bool allowSettlePasses = true,
    bool notifyPausedState = true,
  }) {
    if (!_armAutoFollowToBottom(notifyPausedState: notifyPausedState)) {
      return false;
    }
    _scheduleScrollToBottom(
      force: true,
      animated: animated,
      allowSettlePasses: allowSettlePasses,
    );
    return true;
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
    // 滚动通知有时会在 ListView 的 performLayout 阶段
    // 派发（例如 viewport 在 layout 中调用 applyContentDimensions →
    // dispatchScrollStartNotification）。此时直接 setState 会触发
    // "Build scheduled during frame" 断言。当当前正处于 layout / paint /
    // 持久回调阶段时，把状态变更推迟到本帧结束后的 post-frame 回调里。
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    if (inFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final latestPaused = _autoFollowEnabled && !_shouldAutoFollowMessages;
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
    return !_isAppLifecycleActive() ||
        _resumeAutoFollowSuppressionFrames > 0 ||
        // 用户正在拖动 transcript 时，禁止任何 layout-change /
        // composer 折叠 / 流式 token 触发的 auto-follow 调度，避免那道
        // "把视口往下拽" 的力与用户上滑手势产生拉锯，造成抽搐 / 鬼畜。
        _isUserMessageScrollActivityActive();
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
      if (!_autoFollowEnabled) {
        _clearPendingAutoFollowState();
        return;
      }
      final shouldForce =
          _pendingForcedScrollToBottom || _queuedForcedScrollToBottom;
      if (shouldForce) {
        _scheduleScrollToBottom(force: true);
      }
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
    if (!_autoFollowEnabled) {
      if (shouldForce) {
        _clearPendingAutoFollowState();
      }
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
    final position = _activeMessageScrollPosition();
    if (position == null) return;
    if (_isProgrammaticMessageScrollCommandBusy()) {
      return;
    }
    // ScrollController listener 无法可靠区分「用户上滑」和「弹簧回弹/布局沉降」，
    // 暂停/恢复决策统一交给携带 dragDetails / direction 的
    // _handleMessageScrollNotification。
    // listener 仅保留同步 _syncAutoFollowPausedState（UI 状态一致性）职责。
    // 物理模拟期间（isScrollingNotifier && !_userDragActive）完全跳过，避免
    // 弹簧回弹/fling 减速产生的像素变化触发不必要的 UI 刷新。
    if (position.isScrollingNotifier.value && !_userDragActive) {
      return;
    }
    if (!_autoFollowEnabled) {
      return;
    }
    _syncAutoFollowPausedState();
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    if (!mounted) {
      return false;
    }
    if (notification.depth != 0) {
      return false;
    }
    final programmaticScroll = _isProgrammaticMessageScrollInProgress();
    final recentPointerSignalScroll = _hasRecentPointerSignalScrollActivity();
    final positionActivelyScrolling =
        _messageScrollPositionIsActivelyScrolling();
    final scrollUpdateDelta = notification is ScrollUpdateNotification
        ? notification.scrollDelta
        : null;
    final hasMeaningfulScrollDelta =
        scrollUpdateDelta != null &&
        scrollUpdateDelta.abs() > _messageScrollActivityDeltaThreshold;
    final explicitUserScrollStart =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final explicitUserScroll = isExplicitUserScrollNotification(
      notification,
      programmaticScroll: programmaticScroll,
    );
    final userScrollEnded = isUserScrollEndNotification(notification);
    final implicitPointerSignalScroll =
        isImplicitPointerSignalScrollNotification(
          notification,
          programmaticScroll: programmaticScroll,
          recentPointerSignalScroll: recentPointerSignalScroll,
        );
    // WebView / 桌面平台视图有时吞掉 PointerSignal，导致
    // recentPointerSignalScroll 与 dragDetails 都缺失；但外层 ScrollPosition
    // 仍处于 scrolling，且 ScrollUpdateNotification 携带了非零 delta。
    // 这类 tick 只有在确实向历史方向移动时才计入用户滚动活动；否则
    // 流式内容增高 / Sliver 几何沉降会误写最近用户滚动时间，延迟追底。
    final implicitActivePositionScroll =
        !programmaticScroll &&
        positionActivelyScrolling &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails == null &&
        hasMeaningfulScrollDelta;
    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final previousDistanceToBottom = _lastMessageDistanceToBottom;
    _lastMessageDistanceToBottom = distanceToBottom;
    // 不再单押 UserScrollNotification.direction。Flutter 的
    // forward/reverse 语义容易和“内容视觉方向”混淆，且部分平台视图会缺失
    // pointer metadata。用距底部距离是否增大作为主判据；有 scrollDelta 时
    // 再用负 delta 兜底覆盖首个 tick。
    final distanceMovedAwayFromBottom =
        previousDistanceToBottom != null &&
        distanceToBottom - previousDistanceToBottom >
            _messageDistanceToBottomDeltaThreshold;
    final updateMovedTowardHistory =
        scrollUpdateDelta != null &&
        scrollUpdateDelta < -_messageScrollActivityDeltaThreshold;
    final directionMovedTowardHistory =
        notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward &&
        distanceToBottom > _messageDistanceToBottomDeltaThreshold;
    final implicitActivePositionMovedTowardHistory =
        implicitActivePositionScroll &&
        (distanceMovedAwayFromBottom ||
            updateMovedTowardHistory ||
            directionMovedTowardHistory);
    // 展开消息后自动跟随已经暂停，此时双向滚动都只能来自用户意图。
    // 平台视图吞掉 PointerSignal 时也必须识别向下滚动，否则延迟测高或
    // 锚点修正会继续抢占 ScrollPosition，把视口拉回展开卡片。
    final implicitPausedPositionScroll =
        !_shouldAutoFollowMessages && implicitActivePositionScroll;
    final userScrollActivity =
        explicitUserScroll ||
        implicitPointerSignalScroll ||
        implicitActivePositionMovedTowardHistory ||
        implicitPausedPositionScroll;
    if (userScrollActivity) {
      _lastScrollActivityAt = _scrollActivityStopwatch.elapsed;
      _markUserScrollInProgress();
      _scheduleUserScrollEndGrace();
      if (explicitUserScrollStart) {
        _userDragActive = true;
      }
    } else if (userScrollEnded) {
      _userDragActive = false;
      _scheduleUserScrollEndGrace();
    }
    if (programmaticScroll) {
      if (!explicitUserScroll) {
        return false;
      }
      _cancelProgrammaticAutoFollowScroll(
        keepPixels: notification.metrics.pixels,
      );
    }
    if (!_autoFollowEnabled && userScrollActivity) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    // 「暂停」阈值采用滞回：只有距离底部 > 96 px 才算「真
    // 的离开底部」。加载更多历史后，markdown / 高亮异步完成会让
    // `maxScrollExtent` 在数十像素间反复变动；没有滞回的话，`distanceToBottom`
    // 会在 32 阈值上下反复穿越，造成「靠近底部/离开底部」高频反转、
    // 「跳到最新」按钮、自动跟随状态闪烁，从UI上看就是「消息盒子在抽搐」。
    // 「明显向历史消息移动」仍会在任何距离下触发暂停，保留「轻微上滑
    // 也能暂停」的用户意图。
    final reallyAwayFromBottom = distanceToBottom > _autoFollowPauseHysteresis;
    final userScrolledAwayFromBottom =
        reallyAwayFromBottom && userScrollActivity;
    final userMovedTowardHistory =
        userScrollActivity &&
        (distanceMovedAwayFromBottom ||
            updateMovedTowardHistory ||
            directionMovedTowardHistory);
    if (_autoFollowEnabled &&
        userScrollActivity &&
        !userMovedTowardHistory &&
        distanceToBottom <= _autoFollowResumeDistance) {
      _shouldAutoFollowMessages = true;
      _syncAutoFollowPausedState();
      return false;
    }
    if (userScrolledAwayFromBottom || userMovedTowardHistory) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    _syncAutoFollowPausedState();
    return false;
  }

  void _selectSection(AppSection section) {
    if (_selectedSection == section) return;
    dismissOpenHandTooltipsSafely(debugLabel: '切换功能页面前收起工具提示');
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
      _requestFollowToLatest(notifyPausedState: false);
      return;
    }
    final nextValue = !_autoFollowEnabled;
    setState(() {
      _autoFollowEnabled = nextValue;
      if (!nextValue) {
        _pauseAutoFollowUntilExplicitResume();
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
            _selectedSection != AppSection.harnessSession) ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    // Section and editable-focus gating keep composer shortcuts available in
    // overlays and child Navigators without leaking them to other sections.
    final isEditableFocused = _isEditableTextFocused(focusContext);
    if (!isEditableFocused && _isPlainCopyShortcut(event)) {
      if (HtmlSelectionBridgeClipboard.hasSelection) {
        unawaited(HtmlSelectionBridgeClipboard.copySelection());
        return true;
      }
    }
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
    if (event is KeyRepeatEvent &&
        !_shortcutActionAllowsRepeat(shortcutAction)) {
      return true;
    }
    if (isEditableFocused) {
      final composerShortcutAllowed =
          _composerFocusNode.hasFocus &&
          (shortcutAction == OpenHandShortcutAction.sendMessage ||
              shortcutAction == OpenHandShortcutAction.toggleComposer);
      final harnessComposerShortcutAllowed =
          _selectedSection == AppSection.harnessSession &&
          _harnessSessionPaneController.shouldAllowEditableShortcut(
            shortcutAction,
          );
      if (!composerShortcutAllowed && !harnessComposerShortcutAllowed) {
        return false;
      }
      // 硬件与焦点事件会同时触发；此处执行一次，焦点回调仅标记已处理。
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
    // Cmd/Ctrl+V attachment paste: probe the OS clipboard in parallel with
    // the platform text-paste path. If only text is present the TextField's
    // normal paste continues unaffected.
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
      final hw = HardwareKeyboard.instance;
      final hasModifier = Platform.isMacOS
          ? hw.isMetaPressed
          : hw.isControlPressed;
      if (hasModifier && !hw.isShiftPressed && !hw.isAltPressed) {
        unawaited(_tryPasteAttachmentsFromClipboard());
        // Intentionally fall through (return ignored) so the TextField can
        // still paste text if the clipboard happens to carry both.
      }
    }
    final composerState = _composerPanelState;
    // Escape dismisses the @ mention overlay if it is showing.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (composerState != null && composerState._atMentionOverlay.hasEntry) {
        composerState._userDismissAtMentionOverlay();
        return KeyEventResult.handled;
      }
      if (composerState != null && composerState._skillPickerOverlay.hasEntry) {
        composerState._userDismissSkillPickerOverlay();
        return KeyEventResult.handled;
      }
    }
    if (composerState != null && composerState._atMentionOverlay.hasEntry) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        composerState._moveAtMentionSelection(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        composerState._moveAtMentionSelection(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (composerState._openSelectedAtMentionDirectory()) {
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (composerState._navigateAtMentionToParentDirectory()) {
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (composerState._commitAtMentionSelection()) {
          return KeyEventResult.handled;
        }
      }
    }
    // When the skill picker overlay is visible, let Up/Down move the
    // selection highlight and Enter commit the current selection.  This
    // mirrors Codex / GitHub Copilot Chat behaviour and makes skill lookup
    // an efficient keyboard-only workflow.
    if (composerState != null && composerState._skillPickerOverlay.hasEntry) {
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
    // Composer shortcut consumption (no action).
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
      // 先检查当前获得焦点的组件。
      if (focusContext.widget is EditableText ||
          focusContext.widget is TextField ||
          focusContext.widget is TextFormField) {
        return true;
      }
      // 再检查焦点组件是否位于可编辑文本组件内。
      if (focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
          focusContext.findAncestorWidgetOfExactType<TextField>() != null) {
        return true;
      }
      // 禁止遍历子组件，否则未获焦的输入框也会误判并阻断全局快捷键。
    } catch (_) {
      // 检查失败时按文本输入处理，避免误触快捷键。
      return true;
    }
    return false;
  }

  bool _isPlainCopyShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyC) {
      return false;
    }
    final hw = HardwareKeyboard.instance;
    final hasModifier = Platform.isMacOS
        ? hw.isMetaPressed
        : hw.isControlPressed;
    return hasModifier && !hw.isShiftPressed && !hw.isAltPressed;
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

  bool _shortcutActionAllowsRepeat(OpenHandShortcutAction action) {
    return switch (action) {
      OpenHandShortcutAction.selectPreviousModel ||
      OpenHandShortcutAction.selectNextModel ||
      OpenHandShortcutAction.selectPreviousSession ||
      OpenHandShortcutAction.selectNextSession => true,
      OpenHandShortcutAction.sendMessage ||
      OpenHandShortcutAction.toggleComposer ||
      OpenHandShortcutAction.toggleAutoFollow ||
      OpenHandShortcutAction.undoLastFileMutation => false,
    };
  }

  Future<void> _performShortcutAction(OpenHandShortcutAction action) async {
    final sessionController = context.read<AiSessionController>();
    if (_selectedSection == AppSection.harnessSession) {
      switch (action) {
        case OpenHandShortcutAction.sendMessage:
        case OpenHandShortcutAction.toggleComposer:
        case OpenHandShortcutAction.toggleAutoFollow:
          await _harnessSessionPaneController.invokeShortcut(action);
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
        case OpenHandShortcutAction.undoLastFileMutation:
          await _undoLastFileMutationInCurrentSession();
          return;
      }
    }

    switch (action) {
      case OpenHandShortcutAction.sendMessage:
        final hasComposerDraft =
            _composerController.text.trim().isNotEmpty ||
            _pendingAttachments.isNotEmpty ||
            (_composerPanelState?.hasPendingProjectFileReferences ?? false);
        if (_canStopCurrentSessionResponse(sessionController) &&
            !hasComposerDraft) {
          await _stopResponding();
          return;
        }
        _composerPanelState?._injectReferencesIntoText();
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
      case OpenHandShortcutAction.undoLastFileMutation:
        await _undoLastFileMutationInCurrentSession();
        return;
    }
  }

  void _cycleSelectedModel(int delta) {
    final settingsController = context.read<SettingsController>();
    final entries = settingsController.flatModelEntries;
    if (entries.isEmpty) return;

    final sessionController = context.read<AiSessionController>();
    final currentSession = sessionController.currentSession;
    final currentProvider = _effectiveModelForSession(
      settingsController,
      currentSession,
    );
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
    if (currentSession == null) {
      unawaited(
        settingsController.updateProviderActiveModel(
          next.providerConfigId,
          next.modelId,
        ),
      );
      return;
    }
    unawaited(
      sessionController.updateSessionLastUsedModel(
        currentSession.id,
        providerConfigId: next.providerConfigId,
        modelId: next.modelId,
      ),
    );
    unawaited(
      settingsController.addRecentModelSelection(
        next.providerConfigId,
        next.modelId,
      ),
    );
  }

  Future<void> _cycleSessionSelection(int delta) async {
    final sessionController = context.read<AiSessionController>();
    final sessions = sessionController.sessions
        .where((session) => session.isPrimaryWorkspaceSession)
        .toList(growable: false);
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

  /// 全局快捷键 [OpenHandShortcutAction.undoLastFileMutation] 的实现：取
  /// 当前会话 ledger 里 createdAt 最新且仍可撤销的记录调用 undoRecord，
  /// 并以 SnackBar 提示文件路径。无可撤销目标时静默忽略。
  Future<void> _undoLastFileMutationInCurrentSession() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    final ledger = sessionController.toolRuntimeService.mutationLedger;
    final records = await ledger.recordsForSession(sessionId);
    if (records.isEmpty) return;
    // recordsForSession 按追加顺序返回，尾部即最新；从尾向前找第一条 ledger
    // 接受 undo 的记录（undoRecord 自身会处理"已撤销"幂等返回 success=false）。
    for (var i = records.length - 1; i >= 0; i--) {
      final r = records[i];
      final outcome = await ledger.undoRecord(
        sessionId: sessionId,
        recordId: r.recordId,
      );
      if (!mounted) return;
      if (outcome.success) {
        showOpenHandSuccessSnack(
          context,
          '${AppLocalizations.of(context)!.fileMutationUndone}: ${r.filePath}',
          action: SnackBarAction(
            label: AppLocalizations.of(context)!.fileMutationRedo,
            onPressed: () async {
              final redoResult = await ledger.redoRecord(
                sessionId: sessionId,
                recordId: r.recordId,
              );
              if (!mounted) return;
              final msg = redoResult.success
                  ? '${AppLocalizations.of(context)!.fileMutationRedo}: '
                        '${r.filePath}'
                  : AppLocalizations.of(context)!.fileMutationRedoFailed;
              if (redoResult.success) {
                showOpenHandSuccessSnack(context, msg);
              } else {
                showOpenHandErrorSnack(context, msg);
              }
            },
          ),
        );
        return;
      }
    }
  }

  Future<void> _activateSession(String sessionId) async {
    final activationGeneration = ++_sessionActivationGeneration;
    final sessionController = context.read<AiSessionController>();
    final switchingSessions = sessionController.currentSessionId != sessionId;
    if (switchingSessions || _selectedSection != AppSection.workspace) {
      dismissOpenHandTooltipsSafely(debugLabel: '切换线程会话前收起工具提示');
    }
    _userScrollGraceDebouncer.cancel();
    _userScrollInProgress = false;
    _lastPointerSignalScrollAt = null;
    _lastScrollActivityAt = null;
    _transcriptScrollActivity.markInactive();
    _clearPendingAutoFollowState();

    // Session selection is a synchronous UI intent. Never keep the previous
    // section visible while unrelated audio cleanup or frame callbacks finish.
    if (_selectedSection != AppSection.workspace) {
      setState(() {
        _selectedSection = AppSection.workspace;
      });
    }

    if (kDebugMode) {
      developer.Timeline.startSync(
        'openhand.session.open',
        arguments: <String, Object?>{'sessionId': sessionId},
      );
    }
    try {
      await sessionController.selectSession(sessionId);
    } finally {
      if (kDebugMode) developer.Timeline.finishSync();
    }

    unawaited(
      _ttsPlaybackService.stop().catchError((Object error, StackTrace stack) {
        silentLog('openhand_home_page', '选择会话后停止 TTS', error, stack);
      }),
    );
    if (!mounted ||
        activationGeneration != _sessionActivationGeneration ||
        sessionController.currentSessionId != sessionId ||
        _selectedSection != AppSection.workspace) {
      return;
    }
    if (!switchingSessions) {
      _requestFollowToLatest();
    }
  }

  AiModelConfig? _effectiveModelForSession(
    SettingsController settingsController,
    AiSession? session,
  ) {
    final fallback = settingsController.selectedAiModel;
    final storedProviderId = session?.lastUsedModelId?.trim();
    final storedModelId = session?.lastUsedModelLabel?.trim();
    if (storedProviderId == null ||
        storedProviderId.isEmpty ||
        storedModelId == null ||
        storedModelId.isEmpty) {
      return fallback;
    }
    AiModelConfig? provider;
    for (final item in settingsController.aiModels) {
      if (item.id == storedProviderId) {
        provider = item;
        break;
      }
    }
    if (provider == null) {
      return fallback;
    }
    final allIds = provider.allModelIds;
    if (allIds.isNotEmpty && !allIds.contains(storedModelId)) {
      return provider;
    }
    if (provider.modelId == storedModelId) {
      return provider;
    }
    return provider.copyWith(modelId: storedModelId);
  }

  Future<String?> _showThreadTemplateDialog() async {
    return showAnimatedDialog<String>(
      context: context,
      builder: (dialogContext) {
        final sessionController = dialogContext.read<AiSessionController>();
        return _ThreadTemplateDialog(
          templates: sessionController.availableTemplates,
        );
      },
    );
  }

  AiModelConfig? _initialModelForAutoStartTemplate() {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    return _effectiveModelForSession(
          settingsController,
          sessionController.currentSession,
        ) ??
        settingsController.selectedAiModel;
  }

  Future<void> _applyNewSessionModelSelection({
    required String? providerConfigId,
    required String? modelId,
    String? sessionId,
  }) async {
    final normalizedProviderConfigId = providerConfigId?.trim();
    final normalizedModelId = modelId?.trim();
    if (normalizedProviderConfigId == null ||
        normalizedProviderConfigId.isEmpty ||
        normalizedModelId == null ||
        normalizedModelId.isEmpty) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final providerExists = settingsController.aiModels.any(
      (item) =>
          item.id == normalizedProviderConfigId &&
          item.allModelIds.contains(normalizedModelId),
    );
    if (!providerExists) {
      return;
    }
    await settingsController.addRecentModelSelection(
      normalizedProviderConfigId,
      normalizedModelId,
    );
    final currentSessionId = sessionId ?? sessionController.currentSessionId;
    if (currentSessionId != null && currentSessionId.isNotEmpty) {
      await sessionController.updateSessionLastUsedModel(
        currentSessionId,
        providerConfigId: normalizedProviderConfigId,
        modelId: normalizedModelId,
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
      // F5 优化：UI 创建新会话不再等 session_start hook 跑完。hook 可能涉及
      // shell 进程冷启动 (~数百 ms ~ 数秒)，会让 "+新会话" 按钮卡顿；通过
      // unawaited 让 hook 异步执行，新会话立刻可见、可输入。
      awaitStartHook: false,
    );
    if (!mounted) {
      return false;
    }
    if (!created) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = sessionController.lastErrorMessage;
      showFriendlyErrorSnackBar(
        context,
        message: errorMessage,
        fallback: l10n.chatRequestFailed,
      );
      return false;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    return true;
  }

  Future<bool> _createMachineExpertSession({
    AiSessionRuntimeContext? runtimeContext,
    AiSessionMode initialMode = AiSessionMode.chat,
    bool initialFullAccessPermission = false,
  }) async {
    final resolvedRuntimeContext =
        runtimeContext ?? await _buildRuntimeContext();
    if (!mounted) {
      return false;
    }
    final created = await _createSession(
      templateId: kMachineExpertTemplateId,
      runtimeContext: resolvedRuntimeContext,
      initialMode: initialMode,
      initialFullAccessPermission: initialFullAccessPermission,
    );
    if (!created || !mounted) {
      return created;
    }
    final sessionController = context.read<AiSessionController>();
    final session = sessionController.currentSession;
    if (session == null) {
      return created;
    }
    final terminalService = context.read<MachineTerminalService>();
    final metadata = await terminalService.initialMetadata(
      sessionId: session.id,
      workingDirectory: resolvedRuntimeContext.workingDirectory,
      existingMetadata: session.metadata[kMachineTerminalMetadataKey],
    );
    await sessionController.updateSessionMetadata(session.id, <String, Object?>{
      kMachineTerminalMetadataKey: metadata,
    });
    if (!mounted) {
      return created;
    }
    _showMachineTerminalPanel(session.id);
    unawaited(terminalService.startTerminal(sessionId: session.id));
    return created;
  }

  Future<bool> _createSessionFromDialog({
    AiSessionRuntimeContext? runtimeContext,
  }) async {
    final templateId = await _showThreadTemplateDialog();
    if (!mounted || templateId == null) {
      return false;
    }
    if (templateId == kMachineExpertTemplateId) {
      return _createMachineExpertSession(runtimeContext: runtimeContext);
    }
    if (templateId == 'programming_expert') {
      final sessionController = context.read<AiSessionController>();
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
          await sessionController.updateSessionMetadata(
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
        }
      }
      return created;
    }
    if (templateId == 'harness_engineering') {
      final settingsCtrl = context.read<SettingsController>();
      final config = await showAnimatedDialog<HarnessSessionConfig>(
        context: context,
        builder: (context) =>
            HarnessEngineeringDialog(settingsController: settingsCtrl),
      );
      if (!mounted || config == null) {
        return false;
      }
      try {
        await config.initializePersistenceDirectories();
      } catch (error, stack) {
        _reportHarnessPersistenceError(
          operation: '初始化 Harness 持久化目录',
          error: error,
          stack: stack,
          zhAction: '无法初始化 Harness 持久化目录',
          enAction: 'Failed to initialize Harness storage',
        );
        return false;
      }
      if (!mounted) return false;
      final orchestrator = HarnessOrchestrator(config);
      orchestrator.fullAccessPermission = _heFullAccessPermission;
      orchestrator.onPhaseApprovalRequired = _handlePhaseApprovalRequired;
      final now = DateTime.now().toUtc();
      final record = HarnessSessionRecord(
        id: const Uuid().v4(),
        title: _harnessTitleFromTask(config.task),
        config: config,
        statusValue: HarnessOrchestratorStatus.running.name,
        createdAt: now,
        updatedAt: now,
      );
      _wireHarnessApiMode(orchestrator, sessionId: record.id);
      final previousOrchestrator = _activeHarnessOrchestrator;
      previousOrchestrator?.removeListener(_onHarnessOrchestratorChanged);
      _harnessSessionSaveDebouncer.cancel();
      try {
        await _harnessSessionStore.save(record);
      } catch (error, stack) {
        previousOrchestrator?.addListener(_onHarnessOrchestratorChanged);
        if (previousOrchestrator != null) {
          _onHarnessOrchestratorChanged();
        }
        orchestrator.dispose();
        _reportHarnessPersistenceError(
          operation: '保存初始 Harness 会话',
          error: error,
          stack: stack,
          zhAction: '无法保存 Harness 会话',
          enAction: 'Failed to save the Harness session',
        );
        return false;
      }
      if (!mounted) {
        orchestrator.dispose();
        return false;
      }
      previousOrchestrator?.cancel();
      previousOrchestrator?.dispose();
      orchestrator.addListener(_onHarnessOrchestratorChanged);
      _cacheHarnessShellState(orchestrator);
      setState(() {
        _activeHarnessOrchestrator = orchestrator;
        _activeHarnessConfig = config;
        _persistedHarnessSession = record;
        _selectedSection = AppSection.harnessSession;
      });
      unawaited(orchestrator.start());
      unawaited(
        _generateHarnessAutoTitle(
          record.id,
          config,
          expectedCurrentTitle: record.title,
        ),
      );
      return true;
    }
    if (templateId == 'web_reverse_expert') {
      final result = await _showWebReverseSetupAndCreate(
        runtimeContext: runtimeContext,
      );
      return result;
    }
    if (templateId == 'android_reverse_expert') {
      final result = await _showAndroidReverseSetupAndCreate(
        runtimeContext: runtimeContext,
      );
      return result;
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

  Object? _reserveReverseRuntimeSlot() {
    if (_reverseRuntimeLeases.length >= _maxActiveReverseRuntimes) return null;
    final lease = Object();
    _reverseRuntimeLeases.add(lease);
    return lease;
  }

  void _bindReverseRuntimeSlot(Object lease, String sessionId) {
    _reverseRuntimeLeasesBySessionId[sessionId] = lease;
  }

  bool _acquireReverseRuntimeSlot(String sessionId) {
    if (_reverseRuntimeLeasesBySessionId.containsKey(sessionId)) return true;
    final lease = _reserveReverseRuntimeSlot();
    if (lease == null) return false;
    _bindReverseRuntimeSlot(lease, sessionId);
    return true;
  }

  void _releaseReverseRuntimeReservation(Object lease) {
    _reverseRuntimeLeases.remove(lease);
  }

  void _releaseReverseRuntimeSlot(String sessionId) {
    final lease = _reverseRuntimeLeasesBySessionId.remove(sessionId);
    if (lease != null) _reverseRuntimeLeases.remove(lease);
  }

  void _releaseReverseRuntimeSlotIfUnchanged(
    String sessionId,
    Object? expectedLease,
  ) {
    final currentLease = _reverseRuntimeLeasesBySessionId[sessionId];
    if (!identical(currentLease, expectedLease) || currentLease == null) return;
    _reverseRuntimeLeasesBySessionId.remove(sessionId);
    _reverseRuntimeLeases.remove(currentLease);
  }

  Future<AiSession?> _createReverseSessionWithReservedRuntime({
    required Object runtimeLease,
    required String templateId,
    required AiSessionRuntimeContext? runtimeContext,
    required AiSessionMode initialMode,
    required bool initialFullAccessPermission,
  }) async {
    var bound = false;
    try {
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
        initialMode: initialMode,
        initialFullAccessPermission: initialFullAccessPermission,
      );
      if (!created || !mounted) return null;
      final controller = context.read<AiSessionController>();
      final session = controller.currentSession;
      if (session == null) return null;
      _bindReverseRuntimeSlot(runtimeLease, session.id);
      bound = true;
      return session;
    } finally {
      if (!bound) _releaseReverseRuntimeReservation(runtimeLease);
    }
  }

  Future<bool> _configureNewReverseSession({
    required String sessionId,
    required String? providerConfigId,
    required String? modelId,
    required String metadataKey,
    required Object metadataValue,
    required String runtimeLabel,
  }) async {
    try {
      await _applyNewSessionModelSelection(
        sessionId: sessionId,
        providerConfigId: providerConfigId,
        modelId: modelId,
      );
      if (!mounted) return false;
      final updated = await context
          .read<AiSessionController>()
          .updateSessionMetadata(sessionId, <String, Object?>{
            metadataKey: metadataValue,
          });
      if (!updated) throw StateError('$runtimeLabel 会话配置保存失败。');
      return mounted;
    } catch (error, stack) {
      silentLog('openhand_home_page', '配置 $runtimeLabel 会话', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: userFailureMessage(error, fallback: '$runtimeLabel 会话配置失败'),
          fallback: '$runtimeLabel 会话配置失败',
        );
      }
      return false;
    }
  }

  void _beginReverseRuntimeOperation(String sessionId) {
    _reverseRuntimeOperationCounts.update(
      sessionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _finishReverseRuntimeOperation(String sessionId) {
    final count = _reverseRuntimeOperationCounts[sessionId] ?? 0;
    if (count <= 1) {
      _reverseRuntimeOperationCounts.remove(sessionId);
    } else {
      _reverseRuntimeOperationCounts[sessionId] = count - 1;
    }
  }

  void _releaseInactiveReverseRuntimeSlot(
    String sessionId, {
    required bool active,
  }) {
    if (!active && !_reverseRuntimeOperationCounts.containsKey(sessionId)) {
      _releaseReverseRuntimeSlot(sessionId);
    }
  }

  String _reverseRuntimeCapacityMessage(BuildContext context) {
    return openHandLocalizedText(
      context,
      zh: '最多同时运行 $_maxActiveReverseRuntimes 个逆向会话，请先停止一个运行时。',
      zhHant: '最多同時執行 $_maxActiveReverseRuntimes 個逆向會話，請先停止一個執行環境。',
      en: 'At most $_maxActiveReverseRuntimes reverse sessions can run at once. Stop one runtime first.',
      fr: 'Au maximum $_maxActiveReverseRuntimes sessions d’analyse inverse peuvent fonctionner simultanément. Arrêtez d’abord un environnement.',
      de: 'Es können höchstens $_maxActiveReverseRuntimes Reverse-Sitzungen gleichzeitig laufen. Beenden Sie zuerst eine Laufzeit.',
      ja: '同時に実行できるリバースセッションは最大 $_maxActiveReverseRuntimes 件です。先に実行中の環境を停止してください。',
    );
  }

  Future<void> _startReverseRuntime({
    required String sessionId,
    required Future<void> Function() start,
    required bool Function() isActive,
  }) async {
    final stopping = _reverseRuntimeStopTasks[sessionId];
    if (stopping != null) await stopping;
    final disposing = _reverseControllerDisposalTasks[sessionId];
    if (disposing != null) await disposing;
    if (!mounted) throw StateError('页面已关闭，无法启动逆向运行时。');
    if (!_acquireReverseRuntimeSlot(sessionId)) {
      throw _ReverseRuntimeCapacityException(
        mounted ? _reverseRuntimeCapacityMessage(context) : '逆向运行时已达到容量上限。',
      );
    }
    _beginReverseRuntimeOperation(sessionId);
    try {
      await start();
    } finally {
      _finishReverseRuntimeOperation(sessionId);
      _releaseInactiveReverseRuntimeSlot(sessionId, active: isActive());
    }
  }

  Future<void> restartWebReverseBrowser(
    String sessionId,
    WebReverseSessionController controller,
  ) {
    return _startReverseRuntime(
      sessionId: sessionId,
      start: controller.restartBrowser,
      isActive: () => controller.hasManagedBrowserProcess,
    );
  }

  void _trimRetainedWebReverseControllers({bool makeRoom = false}) {
    final limit = makeRoom
        ? _maxRetainedReverseControllersPerType - 1
        : _maxRetainedReverseControllersPerType;
    while (_webReverseControllers.length > limit) {
      String? sessionId;
      WebReverseSessionController? controller;
      for (final entry in _webReverseControllers.entries) {
        if (!entry.value.hasManagedBrowserProcess &&
            !_reverseRuntimeOperationCounts.containsKey(entry.key) &&
            !_reverseRuntimeStopTasks.containsKey(entry.key) &&
            !_reverseControllerDisposalTasks.containsKey(entry.key)) {
          sessionId = entry.key;
          controller = entry.value;
          break;
        }
      }
      if (sessionId == null || controller == null) return;
      unawaited(_persistWebReverseRuntimeMetadata(sessionId, controller));
      _webReverseControllers.remove(sessionId);
      _webReverseRuntimeMetadataSignatures.remove(sessionId);
      _webReverseCdpMcpBridge.stopSession(sessionId);
      unawaited(_disposeWebReverseControllerAfterStop(sessionId, controller));
    }
  }

  void _trimRetainedAndroidReverseControllers({bool makeRoom = false}) {
    final limit = makeRoom
        ? _maxRetainedReverseControllersPerType - 1
        : _maxRetainedReverseControllersPerType;
    while (_androidReverseControllers.length > limit) {
      String? sessionId;
      AndroidReverseSessionController? controller;
      for (final entry in _androidReverseControllers.entries) {
        if (!entry.value.isRunning &&
            !_reverseRuntimeOperationCounts.containsKey(entry.key) &&
            !_reverseRuntimeStopTasks.containsKey(entry.key) &&
            !_reverseControllerDisposalTasks.containsKey(entry.key)) {
          sessionId = entry.key;
          controller = entry.value;
          break;
        }
      }
      if (sessionId == null || controller == null) return;
      _androidReverseControllers.remove(sessionId);
      _androidReverseRuntimeMetadataSignatures.remove(sessionId);
      unawaited(_disposeAndroidReverseController(sessionId, controller));
    }
  }

  /// 创建一个 Web 逆向专家会话：弹设置对话框 → 启动浏览器/CDP →
  /// 把 controller 绑到 session.id → 写入会话 metadata → 拼 prompt 发送。
  Future<bool> _showWebReverseSetupAndCreate({
    AiSessionRuntimeContext? runtimeContext,
    String? initialPrompt,
    AiSessionMode initialMode = AiSessionMode.chat,
    bool initialFullAccessPermission = false,
  }) async {
    final userDataDirRoot =
        '${OpenHandPaths.defaultRootDirectoryPath()}/web_reverse';
    final settingsController = context.read<SettingsController>();
    final initialModel = _initialModelForAutoStartTemplate();
    final setup = await showWebReverseSetupDialog(
      context,
      initialTargetUrl: firstHttpUrlFromText(initialPrompt),
      initialObjective: _webReverseInitialObjectiveFromPrompt(initialPrompt),
      userDataDirRoot: userDataDirRoot,
      availableModels: settingsController.aiModels,
      recentModelSelections: settingsController.recentModelSelections,
      initialSelectedModelConfigId: initialModel?.id,
      initialSelectedModelId: initialModel?.modelId,
    );
    if (!mounted || setup == null) return false;
    final runtimeLease = _reserveReverseRuntimeSlot();
    if (runtimeLease == null) {
      showOpenHandErrorSnack(context, _reverseRuntimeCapacityMessage(context));
      return false;
    }
    final session = await _createReverseSessionWithReservedRuntime(
      runtimeLease: runtimeLease,
      templateId: 'web_reverse_expert',
      runtimeContext: runtimeContext,
      initialMode: initialMode,
      initialFullAccessPermission: initialFullAccessPermission,
    );
    if (session == null) return false;
    const created = true;
    _beginPendingAutoStartSubmission(session.id);
    _replaceComposerText('');
    // 把 user-data-dir 在 session.id 就绪后改写为 `<root>/profile_<browser>_<sid>`，
    // 这样每个会话各占一个 profile 目录，从源头规避另一个 Chrome 实例
    // 抓着同一 user-data-dir 时触发的 "Profile is in use" 锁导致 CDP 起不来。
    final sessionScopedUserDataDir =
        '$userDataDirRoot/profiles/${setup.config.browserKind.id}_${session.id}';
    final scopedConfig = setup.config.copyWith(
      userDataDir: sessionScopedUserDataDir,
    );
    final configured = await _configureNewReverseSession(
      sessionId: session.id,
      providerConfigId: setup.selectedModelConfigId,
      modelId: setup.selectedModelId,
      metadataKey: 'web_reverse_config',
      metadataValue: scopedConfig.toJson(),
      runtimeLabel: 'Web 逆向',
    );
    if (!configured) {
      _releaseReverseRuntimeSlot(session.id);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (!mounted ||
        !context.read<AiSessionController>().sessions.any(
          (item) => item.id == session.id,
        )) {
      _releaseReverseRuntimeSlot(session.id);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    // 启动控制器。
    final controller = WebReverseSessionController(
      config: scopedConfig,
      executablePath: setup.executablePath,
      artifactsRootDir: '$userDataDirRoot/sessions/${session.id}',
    );
    _trimRetainedWebReverseControllers(makeRoom: true);
    _webReverseControllers[session.id] = controller;
    controller.addListener(_onWebReverseControllerChanged);
    var launchOk = false;
    var runtimePersisted = false;
    try {
      await _startReverseRuntime(
        sessionId: session.id,
        start: controller.start,
        isActive: () => controller.hasManagedBrowserProcess,
      );
      launchOk = controller.isBrowserAlive;
      runtimePersisted = await _persistWebReverseRuntimeMetadata(
        session.id,
        controller,
      );
    } on WebReverseLaunchException catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '启动 Web 逆向（${error.failure}）',
        error,
        stack,
      );
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: _formatWebReverseLaunchError(error),
          fallback: 'Web 逆向会话启动失败',
        );
      }
    } catch (error, stack) {
      silentLog('openhand_home_page', '启动 Web 逆向', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: userFailureMessage(error, fallback: 'Web 逆向会话启动失败'),
          fallback: 'Web 逆向会话启动失败',
        );
      }
    }
    if (!launchOk) {
      await _persistWebReverseRuntimeMetadata(session.id, controller);
      // 启动失败时移除失效控制器，避免调试入口继续引用残留对象。
      _webReverseControllers.remove(session.id);
      _webReverseRuntimeMetadataSignatures.remove(session.id);
      _webReverseCdpMcpBridge.stopSession(session.id);
      await _disposeWebReverseControllerAfterStop(session.id, controller);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (!runtimePersisted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (_autoStartSubmissionWasStopped(session.id)) {
      _webReverseControllers.remove(session.id);
      _webReverseRuntimeMetadataSignatures.remove(session.id);
      _webReverseCdpMcpBridge.stopSession(session.id);
      unawaited(_disposeWebReverseControllerAfterStop(session.id, controller));
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    final requestConfig = scopedConfig.copyWith(
      cdpPort: controller.cdpPort ?? scopedConfig.cdpPort,
    );
    final requestPrompt = requestConfig.toRequestTemplate();
    _replaceComposerText('');
    try {
      await _submitTextToSession(
        session.id,
        requestPrompt,
        const <_ComposerAttachmentDraft>[],
        runtimeContext: runtimeContext,
        restoreDraftOnLocalStop: false,
      );
    } finally {
      _clearPendingAutoStartSubmission(session.id);
    }
    return created;
  }

  String? _webReverseInitialObjectiveFromPrompt(String? prompt) {
    final value = prompt?.trim();
    if (value == null || value.isEmpty) return null;
    const maxChars = 4000;
    return clipTextByCodeUnits(value, maxChars, suffix: '\n...');
  }

  String? _androidReverseInitialPackageFromPrompt(String? prompt) {
    final value = prompt?.trim();
    if (value == null || value.isEmpty) return null;
    final labeled = RegExp(
      r'(?:包名|package(?:\s+name)?|pkg)\s*[:：=]?\s*([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
    if (looksLikeAndroidPackageName(labeled)) return labeled;
    final commonPackage = RegExp(
      r'\b(?:com|org|net|io|cn|dev|app)\.[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*){2,}\b',
      caseSensitive: false,
    ).firstMatch(value)?.group(0);
    return looksLikeAndroidPackageName(commonPackage) ? commonPackage : null;
  }

  void _onWebReverseControllerChanged() {
    if (!mounted) return;
    for (final entry in _webReverseControllers.entries) {
      if (!entry.value.isBrowserAlive) {
        _webReverseCdpMcpBridge.stopSession(entry.key);
      }
      _releaseInactiveReverseRuntimeSlot(
        entry.key,
        active: entry.value.hasManagedBrowserProcess,
      );
    }
    _trimRetainedWebReverseControllers();
    setState(() {});
    _scheduleWebReverseRuntimeMetadataSync();
  }

  Future<void> _disposeWebReverseControllerAfterStop(
    String sessionId,
    WebReverseSessionController controller,
  ) {
    controller.removeListener(_onWebReverseControllerChanged);
    _removeTemplateRuntimeLinkage(sessionId);
    return _disposeReverseRuntimeController(
      sessionId: sessionId,
      operation: '释放 Web 逆向控制器 $sessionId',
      shutdown: controller.shutdown,
      dispose: controller.dispose,
    );
  }

  Future<void> _disposeReverseRuntimeController({
    required String sessionId,
    required String operation,
    required Future<void> Function() shutdown,
    required void Function() dispose,
    void Function()? afterShutdown,
  }) {
    final active = _reverseControllerDisposalTasks[sessionId];
    if (active != null) {
      return active.then(
        (_) => _disposeReverseRuntimeController(
          sessionId: sessionId,
          operation: operation,
          shutdown: shutdown,
          dispose: dispose,
          afterShutdown: afterShutdown,
        ),
      );
    }
    final expectedLease = _reverseRuntimeLeasesBySessionId[sessionId];
    late final Future<void> task;
    task =
        (() async {
          _beginReverseRuntimeOperation(sessionId);
          try {
            await shutdown();
          } catch (error, stack) {
            silentLog('openhand_home_page', operation, error, stack);
          } finally {
            _finishReverseRuntimeOperation(sessionId);
            try {
              afterShutdown?.call();
              dispose();
            } catch (error, stack) {
              silentLog('openhand_home_page', '$operation：释放对象', error, stack);
            } finally {
              _releaseReverseRuntimeSlotIfUnchanged(sessionId, expectedLease);
            }
          }
        })().whenComplete(() {
          if (identical(_reverseControllerDisposalTasks[sessionId], task)) {
            _reverseControllerDisposalTasks.remove(sessionId);
          }
        });
    _reverseControllerDisposalTasks[sessionId] = task;
    return task;
  }

  // ── Android Reverse ─────────────────────────────────────────────────────

  AndroidReverseSessionController? androidReverseControllerFor(
    String sessionId,
  ) => _androidReverseControllers[sessionId];

  String _androidReverseArtifactsRootDir(String sessionId) =>
      '${OpenHandPaths.defaultRootDirectoryPath()}/android_reverse/sessions/$sessionId';

  AndroidReverseSessionController? ensureAndroidReverseControllerFor(
    AiSession session,
  ) {
    if (session.templateId != 'android_reverse_expert') {
      return null;
    }
    final existing = _androidReverseControllers[session.id];
    if (existing != null) {
      return existing;
    }
    final AndroidReverseSessionConfig? config;
    try {
      config = AndroidReverseSessionConfig.fromJson(
        session.metadata['android_reverse_config'],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '恢复 Android 逆向配置', error, stack);
      return null;
    }
    if (config == null) {
      return null;
    }
    final controller = AndroidReverseSessionController(
      config: config,
      artifactsRootDir: _androidReverseArtifactsRootDir(session.id),
    );
    _trimRetainedAndroidReverseControllers(makeRoom: true);
    _androidReverseControllers[session.id] = controller;
    controller.addListener(_onAndroidReverseControllerChanged);
    unawaited(_persistAndroidReverseRuntimeMetadata(session.id, controller));
    if (mounted) {
      setState(() {});
    }
    return controller;
  }

  Future<void> openAndroidReverseDashboardFor(
    BuildContext dialogContext,
    AiSession session,
  ) async {
    final controller = ensureAndroidReverseControllerFor(session);
    if (controller == null) {
      if (dialogContext.mounted) {
        showFriendlyErrorSnackBar(
          dialogContext,
          message: openHandLocalizedText(
            dialogContext,
            zh: 'Android 逆向会话缺少运行配置，无法打开调试面板。',
            zhHant: 'Android 逆向會話缺少執行設定，無法開啟調試面板。',
            en: 'Android reverse session config is missing; debugger cannot open.',
            fr: 'La configuration de session Android Reverse manque ; impossible d’ouvrir le débogueur.',
            de: 'Android-Reverse-Sitzungskonfiguration fehlt; Debugger kann nicht geöffnet werden.',
            ja: 'Android Reverse セッション設定がないため、デバッガを開けません。',
          ),
          fallback: openHandLocalizedText(
            dialogContext,
            zh: 'Android 逆向调试面板打开失败',
            zhHant: 'Android 逆向調試面板開啟失敗',
            en: 'Failed to open Android Reverse debugger',
            fr: 'Échec d’ouverture du débogueur Android Reverse',
            de: 'Android-Reverse-Debugger konnte nicht geöffnet werden',
            ja: 'Android Reverse デバッガを開けませんでした',
          ),
        );
      }
      return;
    }
    try {
      await _startReverseRuntime(
        sessionId: session.id,
        start: controller.start,
        isActive: () => controller.isRunning,
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '启动 Android 逆向调试面板运行时', error, stack);
      if (dialogContext.mounted) {
        showFriendlyErrorSnackBar(
          dialogContext,
          message: userFailureMessage(error, fallback: 'Android 逆向运行时启动失败'),
          fallback: 'Android 逆向运行时启动失败',
        );
      }
      return;
    }
    if (!controller.isRunning) return;
    if (!dialogContext.mounted) return;
    await showAndroidReverseDashboardDialog(
      dialogContext,
      controller: controller,
      sessionId: session.id,
    );
  }

  Future<bool> _showAndroidReverseSetupAndCreate({
    AiSessionRuntimeContext? runtimeContext,
    String? initialPrompt,
    AiSessionMode? initialMode,
    bool? initialFullAccessPermission,
  }) async {
    final settingsController = context.read<SettingsController>();
    final initialModel = _initialModelForAutoStartTemplate();
    final setup = await showAndroidReverseSetupDialog(
      context,
      initialPackageName: _androidReverseInitialPackageFromPrompt(
        initialPrompt,
      ),
      initialObjective: _webReverseInitialObjectiveFromPrompt(initialPrompt),
      availableModels: settingsController.aiModels,
      recentModelSelections: settingsController.recentModelSelections,
      initialSelectedModelConfigId: initialModel?.id,
      initialSelectedModelId: initialModel?.modelId,
    );
    if (!mounted || setup == null) return false;
    final runtimeLease = _reserveReverseRuntimeSlot();
    if (runtimeLease == null) {
      showOpenHandErrorSnack(context, _reverseRuntimeCapacityMessage(context));
      return false;
    }
    final session = await _createReverseSessionWithReservedRuntime(
      runtimeLease: runtimeLease,
      templateId: 'android_reverse_expert',
      runtimeContext: runtimeContext,
      initialMode:
          initialMode ??
          AiSessionMode.fromStorage(settingsController.aiDefaultSessionMode),
      initialFullAccessPermission:
          initialFullAccessPermission ??
          settingsController.aiDefaultFullAccessPermission,
    );
    if (session == null) return false;
    const created = true;
    _beginPendingAutoStartSubmission(session.id);
    _replaceComposerText('');
    final config = setup.config;
    final configured = await _configureNewReverseSession(
      sessionId: session.id,
      providerConfigId: setup.selectedModelConfigId,
      modelId: setup.selectedModelId,
      metadataKey: 'android_reverse_config',
      metadataValue: config.toJson(),
      runtimeLabel: 'Android 逆向',
    );
    if (!configured) {
      _releaseReverseRuntimeSlot(session.id);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (!mounted ||
        !context.read<AiSessionController>().sessions.any(
          (item) => item.id == session.id,
        )) {
      _releaseReverseRuntimeSlot(session.id);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    final controller = AndroidReverseSessionController(
      config: config,
      artifactsRootDir: _androidReverseArtifactsRootDir(session.id),
    );
    _trimRetainedAndroidReverseControllers(makeRoom: true);
    _androidReverseControllers[session.id] = controller;
    controller.addListener(_onAndroidReverseControllerChanged);
    var launchOk = false;
    try {
      await _startReverseRuntime(
        sessionId: session.id,
        start: controller.start,
        isActive: () => controller.isRunning,
      );
      launchOk = controller.isRunning;
    } catch (error, stack) {
      silentLog('openhand_home_page', '启动 Android 逆向', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: userFailureMessage(error, fallback: 'Android 逆向会话启动失败'),
          fallback: 'Android 逆向会话启动失败',
        );
      }
    }
    await _persistAndroidReverseRuntimeMetadata(session.id, controller);
    if (!launchOk) {
      _androidReverseControllers.remove(session.id);
      _androidReverseRuntimeMetadataSignatures.remove(session.id);
      await _disposeAndroidReverseController(session.id, controller);
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (_autoStartSubmissionWasStopped(session.id)) {
      _androidReverseControllers.remove(session.id);
      _androidReverseRuntimeMetadataSignatures.remove(session.id);
      unawaited(_disposeAndroidReverseController(session.id, controller));
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    final requestPrompt = config.toRequestTemplate();
    _replaceComposerText('');
    try {
      await _submitTextToSession(
        session.id,
        requestPrompt,
        const <_ComposerAttachmentDraft>[],
        runtimeContext: runtimeContext,
        restoreDraftOnLocalStop: false,
      );
    } finally {
      _clearPendingAutoStartSubmission(session.id);
    }
    return created;
  }

  void _onAndroidReverseControllerChanged() {
    if (!mounted) return;
    setState(() {});
    for (final entry in _androidReverseControllers.entries) {
      _releaseInactiveReverseRuntimeSlot(
        entry.key,
        active: entry.value.isRunning,
      );
      unawaited(_persistAndroidReverseRuntimeMetadata(entry.key, entry.value));
    }
    _trimRetainedAndroidReverseControllers();
  }

  Future<void> _disposeAndroidReverseController(
    String sessionId,
    AndroidReverseSessionController controller,
  ) {
    controller.removeListener(_onAndroidReverseControllerChanged);
    _removeTemplateRuntimeLinkage(sessionId);
    return _disposeReverseRuntimeController(
      sessionId: sessionId,
      operation: '释放 Android 逆向控制器 $sessionId',
      shutdown: controller.shutdown,
      dispose: controller.dispose,
      afterShutdown: () =>
          _androidReverseRuntimeMetadataSignatures.remove(sessionId),
    );
  }

  Future<bool> _persistAndroidReverseRuntimeMetadata(
    String sessionId,
    AndroidReverseSessionController controller,
  ) async {
    if (!mounted) return false;
    final metadata = _androidReverseRuntimeMetadata(controller);
    _syncAndroidReverseTemplateRuntimeLinkage(sessionId, controller);
    final signature = jsonEncode(metadata);
    if (_androidReverseRuntimeMetadataSignatures[sessionId] == signature) {
      return true;
    }
    try {
      final updated = await context
          .read<AiSessionController>()
          .updateSessionMetadata(sessionId, <String, Object?>{
            'android_reverse_runtime': metadata,
          });
      if (!updated) return false;
      if (identical(_androidReverseControllers[sessionId], controller)) {
        _androidReverseRuntimeMetadataSignatures[sessionId] = signature;
      }
      return true;
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '保存 Android 逆向运行时元数据 $sessionId',
        error,
        stack,
      );
      return false;
    }
  }

  void _syncAndroidReverseTemplateRuntimeLinkage(
    String sessionId,
    AndroidReverseSessionController controller,
  ) {
    try {
      _templateRuntimeLinkageController?.upsertSession(
        sessionId: sessionId,
        templateId: TemplateRuntimeDependencyRegistry.androidReverse.templateId,
        capabilities: <TemplateRuntimeCapabilityState>[
          TemplateRuntimeCapabilityState(
            capabilityId: 'android_adb_mcp',
            enabled: controller.config.adbMcpEnabled,
            status: controller.config.adbMcpEnabled ? 'enabled' : 'disabled',
            message: controller.config.adbMcpEnabled
                ? 'ADB MCP is enabled for this Android Reverse session.'
                : 'ADB MCP is disabled for this Android Reverse session.',
          ),
          TemplateRuntimeCapabilityState(
            capabilityId: 'android_frida_mcp',
            enabled: controller.config.fridaMcpEnabled,
            status: controller.config.fridaMcpEnabled ? 'enabled' : 'disabled',
            message: controller.config.fridaMcpEnabled
                ? 'Frida MCP is enabled for this Android Reverse session.'
                : 'Frida MCP is disabled for this Android Reverse session.',
          ),
        ],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '同步 Android 逆向模板运行时关联', error, stack);
    }
  }

  void _removeTemplateRuntimeLinkage(String sessionId) {
    try {
      _templateRuntimeLinkageController?.removeSession(sessionId);
    } catch (error, stack) {
      silentLog('openhand_home_page', '移除模板运行时关联 $sessionId', error, stack);
    }
  }

  Map<String, Object?> _androidReverseRuntimeMetadata(
    AndroidReverseSessionController controller,
  ) {
    final connected = controller.connectedDevice;
    return <String, Object?>{
      'source': 'OpenHand AndroidReverseSessionController',
      'is_running': controller.isRunning,
      'state': controller.state.name,
      'analysis_mode': controller.config.analysisMode.storageValue,
      'authorization_scope_present':
          controller.config.authorizationScope?.trim().isNotEmpty ?? false,
      'artifacts_root_dir': controller.artifactsRootDir,
      'local_artifacts': <String, Object?>{
        'root_dir': controller.artifactsRootDir,
        'logcat_jsonl': controller.logcatJsonlPath,
        'logcat_dir': controller.logcatDir,
        'network_jsonl': controller.networkJsonlPath,
        'devices_dir': controller.devicesDir,
        'packages_dir': controller.packagesDir,
        'apks_dir': controller.apksDir,
        'screenshots_dir': controller.screenshotsDir,
        'recordings_dir': controller.recordingsDir,
        'network_dir': controller.networkDir,
        'network_readme': controller.networkReadmePath,
        'network_proxy_probe_script': controller.networkProxyProbeScriptPath,
        'mitmproxy_addon': controller.mitmproxyAddonPath,
        'frida_dir': controller.fridaDir,
        'frida_scripts_dir': controller.fridaScriptsDir,
        'frida_output_dir': controller.fridaOutputDir,
        'frida_readme': controller.fridaReadmePath,
        'frida_doctor_script': controller.fridaDoctorScriptPath,
        'frida_capture_script': controller.fridaCaptureScriptPath,
        'decompiled_dir': controller.decompiledDir,
        if (controller.lastStaticQuickScanDir != null)
          'latest_quick_scan_dir': controller.lastStaticQuickScanDir,
        if (controller.lastStaticQuickScanDir != null)
          'latest_quick_scan_summary':
              '${controller.lastStaticQuickScanDir}/SUMMARY.md',
        'mcp_dir': controller.mcpDir,
        'mcp_templates_json': controller.mcpTemplatesPath,
        'mcp_readme': controller.mcpReadmePath,
        'mcp_setup_guide': controller.mcpSetupGuidePath,
        'certs_dir': controller.certsDir,
        'certs_readme': controller.certsReadmePath,
        'network_security_config': controller.networkSecurityConfigPath,
        'manifest_network_config_snippet':
            controller.manifestNetworkConfigSnippetPath,
        'root_ca_install_script': controller.installMitmCaRootScriptPath,
        'generate_debug_keystore_script':
            controller.generateDebugKeystoreScriptPath,
        'sign_repacked_apk_script': controller.signRepackedApkScriptPath,
        'verify_apk_signature_script': controller.verifyApkSignatureScriptPath,
        'toolchain_dir': controller.toolchainDir,
        'toolchain_readme': controller.toolchainReadmePath,
        'toolchain_setup_commands': controller.toolchainSetupCommandsPath,
        'scripts_dir': controller.scriptsDir,
        'scripts_readme': controller.scriptsReadmePath,
        'reproduce_python': controller.reproducePythonPath,
        'reproduce_curl': controller.reproduceCurlPath,
        'evidence_bundle_script': controller.evidenceBundleScriptPath,
        'evidence_bundle_glob': '${controller.scriptsDir}/evidence_bundle_*.md',
        'adb_one_shot_script': controller.adbOneShotScriptPath,
        'dynamic_probe_script': controller.dynamicProbeScriptPath,
        'logs_dir': controller.logsDir,
      },
      'local_read_hints': <String>[
        'tail -200 ${controller.logcatJsonlPath}',
        'find ${controller.logcatDir} -maxdepth 2 -type f | head -200',
        'tail -200 ${controller.networkJsonlPath}',
        'find ${controller.devicesDir} -maxdepth 3 -type f | head -200',
        'find ${controller.packagesDir} -maxdepth 3 -type f | head -200',
        'find ${controller.networkDir} -maxdepth 2 -type f | head -200',
        'cat ${controller.networkReadmePath}',
        '${controller.networkProxyProbeScriptPath} --timeout 6',
        'find ${controller.apksDir} -maxdepth 3 -type f',
        'find ${controller.screenshotsDir} -maxdepth 2 -type f',
        'find ${controller.recordingsDir} -maxdepth 2 -type f',
        'find ${controller.fridaDir} -maxdepth 2 -type f',
        'find ${controller.fridaScriptsDir} -maxdepth 1 -type f | head -200',
        'find ${controller.fridaOutputDir} -maxdepth 1 -type f | head -200',
        'cat ${controller.fridaReadmePath}',
        '${controller.fridaDoctorScriptPath} --timeout 6',
        '${controller.fridaCaptureScriptPath} --help',
        'find ${controller.decompiledDir} -maxdepth 3 -type f | head -200',
        if (controller.lastStaticQuickScanDir != null)
          'cat ${controller.lastStaticQuickScanDir}/SUMMARY.md',
        'find ${controller.decompiledDir} -path "*/quick_scan/SUMMARY.md" -type f -exec cat {} \\;',
        'find ${controller.decompiledDir} -path "*/quick_scan/*" -type f | head -200',
        'find ${controller.mcpDir} -maxdepth 2 -type f | head -200',
        'cat ${controller.mcpSetupGuidePath}',
        'cat ${controller.mcpReadmePath}',
        'cat ${controller.mcpTemplatesPath}',
        'cat ${controller.toolchainReadmePath}',
        'cat ${controller.toolchainSetupCommandsPath}',
        'cat ${controller.scriptsReadmePath}',
        'sed -n "1,220p" ${controller.reproducePythonPath}',
        'sed -n "1,220p" ${controller.reproduceCurlPath}',
        controller.evidenceBundleScriptPath,
        '${controller.adbOneShotScriptPath} --timeout 6 devices',
        '${controller.dynamicProbeScriptPath} --timeout 6',
        'find ${controller.certsDir} -maxdepth 3 -type f | head -200',
        'cat ${controller.certsReadmePath}',
        'bash ${controller.verifyApkSignatureScriptPath} <apk>',
      ],
      'dashboard_actions': const <String>[
        'static_quick_scan_auto_warm_when_apk_path_exists',
        'adb_devices_refresh',
        'wireless_adb_connect_disconnect',
        'adb_tcpip_5555',
        'adb_root_remount_reboot',
        'adb_forward_add_remove',
        'adb_reverse_add_remove',
        'adb_device_field_snapshot_battery_display_storage_foreground_abi',
        'adb_device_field_report_markdown_json_artifacts',
        'adb_shell_presets',
        'evidence_bundle_markdown_artifact',
        'apk_install',
        'file_push_pull',
        'screenshot_capture_to_artifacts',
        'screen_record_to_artifacts',
        'package_analyze_launcher_launch_force_stop_clear_uninstall',
        'package_report_markdown_json_artifacts',
        'package_pull_apks_to_artifacts',
        'process_kill_force_stop',
        'logcat_level_tag_pid_package_filter',
        'logcat_clear_save_jsonl',
        'logcat_snapshot_txt_json_artifacts',
        'mcp_plugin_linkage_status',
        'mcp_setup_checklist_artifact',
        'mcp_linkage_templates_readme_adb_one_shot_artifacts',
        'android_dynamic_probe_adb_launcher_frida_preflight_artifact',
        'toolchain_install_update_uninstall_copy_commands',
        'toolchain_setup_commands_artifact',
        'static_quick_scan_apk_nested_flutter_native_suspicious_network_artifacts',
        'static_quick_scan_business_network_candidates',
        'frida_script_save_metadata_artifacts',
        'frida_doctor_read_only_diagnostics_artifact',
        'frida_output_runbook_artifacts',
        'frida_capture_stdout_stderr_artifacts',
        'frida_server_abi_push_start_forward_reverse_copy_commands',
        'mitmproxy_jsonl_addon_network_flow_artifacts',
        'network_proxy_probe_runbook_artifacts',
        'certificate_network_security_config_artifacts',
        'apk_resigning_keystore_zipalign_apksigner_artifacts',
        'reproduce_python_curl_templates_and_evidence_bundle',
      ],
      if (controller.lastStaticQuickScanDir != null)
        'latest_static_quick_scan': <String, Object?>{
          'dir': controller.lastStaticQuickScanDir,
          'summary': '${controller.lastStaticQuickScanDir}/SUMMARY.md',
          'exit_code': controller.lastStaticQuickScanResult?.exitCode,
          'timed_out': controller.lastStaticQuickScanResult?.timedOut,
        },
      'dashboard_tabs': const <String>[
        'devices',
        'overview',
        'toolchain',
        'mcp',
        'plugins',
        'packages',
        'processes',
        'logcat',
        'frida',
        'network',
        'static_analysis',
        'certs',
        'crypto',
      ],
      if (controller.config.deviceSerial != null)
        'configured_device_serial': controller.config.deviceSerial,
      if (connected != null)
        'connected_device': <String, Object?>{
          'serial': connected.serial,
          'state': connected.state,
          if (connected.model != null) 'model': connected.model,
          if (connected.product != null) 'product': connected.product,
          if (connected.transportId != null)
            'transport_id': connected.transportId,
        },
      'mcp_plugin_linkage': _androidReverseMcpPluginLinkageMetadata(),
      'toolchain_setup_commands':
          _androidReverseToolchainSetupCommandsMetadata(),
      'toolchain_recommendation_ids': _androidReverseToolchainRecommendationIds,
      'visible_devices': controller.allDevices
          .map(
            (device) => <String, Object?>{
              'serial': device.serial,
              'state': device.state,
              if (device.model != null) 'model': device.model,
            },
          )
          .toList(growable: false),
      if (controller.processes.isNotEmpty)
        'process_count': controller.processes.length,
      if (controller.errorMessage != null &&
          controller.errorMessage!.trim().isNotEmpty)
        'last_error': controller.errorMessage!.trim(),
    };
  }

  Map<String, Object?> _androidReverseMcpPluginLinkageMetadata() {
    return <String, Object?>{
      'template_dependency': TemplateRuntimeDependencyRegistry.androidReverse
          .toJson(),
      'mcp': _androidReverseMcpLinkageMetadata(),
      'plugin_runtime_prerequisites':
          _threadTemplatePluginRuntimePrerequisitesMetadata(
            TemplateRuntimeDependencyRegistry.androidReverse,
          ),
      'toolchain_recommendations': _androidReverseToolchainRecommendationIds,
    };
  }

  Map<String, Object?> _threadTemplateMcpPluginLinkageMetadata(
    TemplateRuntimeDependencySpec spec,
  ) {
    return <String, Object?>{
      'template_dependency': spec.toJson(),
      'mcp': _threadTemplateMcpLinkageMetadata(spec),
      'plugin_runtime_prerequisites':
          _threadTemplatePluginRuntimePrerequisitesMetadata(spec),
    };
  }

  Map<String, Object?> _threadTemplateMcpLinkageMetadata(
    TemplateRuntimeDependencySpec spec,
  ) {
    try {
      final mcpController = context.read<McpController>();
      final capabilityRows = <Map<String, Object?>>[];
      for (final capability in spec.mcpCapabilities) {
        final matchedServers = <Map<String, Object?>>[];
        for (final server in mcpController.runtimeServers) {
          final catalog = mcpController.toolCatalogFor(server.name);
          if (!TemplateRuntimeDependencyRegistry.containsAnyKeyword(
            mcpController.serverSearchText(server),
            capability.keywords,
          )) {
            continue;
          }
          matchedServers.add(<String, Object?>{
            'name': server.name,
            'enabled': server.enabled,
            'transport': server.type.transportValue,
            if (server.summary.trim().isNotEmpty) 'summary': server.summary,
            'tool_count': catalog.tools.length,
          });
        }
        capabilityRows.add(<String, Object?>{
          'id': capability.id,
          'label_zh': capability.labelZh,
          'label_en': capability.labelEn,
          if (capability.packageName != null)
            'package_name': capability.packageName,
          'openhand_managed': capability.openHandManaged,
          'matched_server_count': matchedServers.length,
          'enabled_server_count': matchedServers
              .where((server) => server['enabled'] == true)
              .length,
          if (matchedServers.isNotEmpty)
            'matched_servers': matchedServers.take(8).toList(growable: false),
        });
      }
      return <String, Object?>{
        'servers_file_path': mcpController.serversFilePath,
        'storage_dir': mcpController.storageDirectoryPath,
        'server_count': mcpController.runtimeServers.length,
        'tool_search_recommended_query': spec.toolSearchFallbackQuery,
        'capabilities': capabilityRows,
        if (mcpController.errorMessage?.trim().isNotEmpty ?? false)
          'error': mcpController.errorMessage!.trim(),
      };
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '构建模板 MCP 关联元数据 ${spec.templateId}',
        error,
        stack,
      );
      return <String, Object?>{
        'error': '$error',
        'tool_search_recommended_query': spec.toolSearchFallbackQuery,
      };
    }
  }

  Map<String, Object?> _threadTemplatePluginRuntimePrerequisitesMetadata(
    TemplateRuntimeDependencySpec spec,
  ) {
    try {
      final pluginController = context.read<PluginServiceController>();
      final plugins = <Map<String, Object?>>[];
      for (final id in spec.pluginIds) {
        final plugin = pluginController.pluginById(id);
        if (plugin == null) {
          plugins.add(<String, Object?>{'id': id, 'status': 'unknown'});
          continue;
        }
        plugins.add(<String, Object?>{
          'id': plugin.id,
          'name': plugin.name,
          'status': plugin.status.name,
          'enabled': plugin.enabled,
          'installed': plugin.isInstalled,
          'available_actions': <String>[
            if (!plugin.isInstalled) 'install',
            if (plugin.isInstalled) 'check_update',
            if (plugin.isInstalled && plugin.hasUpdate) 'update',
            if (plugin.isInstalled) plugin.enabled ? 'disable' : 'enable',
            if (plugin.isInstalled && plugin.supportsUninstall) 'uninstall',
          ],
          if (plugin.installedVersion?.trim().isNotEmpty ?? false)
            'installed_version': plugin.installedVersion!.trim(),
          if (plugin.latestVersion?.trim().isNotEmpty ?? false)
            'latest_version': plugin.latestVersion!.trim(),
          if (plugin.installPath?.trim().isNotEmpty ?? false)
            'install_path': plugin.installPath!.trim(),
          if (plugin.errorMessage?.trim().isNotEmpty ?? false)
            'error': plugin.errorMessage!.trim(),
        });
      }
      return <String, Object?>{
        'operation_source': 'OpenHand PluginServiceController',
        'template_id': spec.templateId,
        'is_loading': pluginController.isLoading,
        'is_operating': pluginController.isOperating,
        'installed_count': plugins
            .where((plugin) => plugin['installed'] == true)
            .length,
        'plugins': plugins,
        if (pluginController.errorMessage?.trim().isNotEmpty ?? false)
          'error': pluginController.errorMessage!.trim(),
      };
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '构建模板插件元数据 ${spec.templateId}',
        error,
        stack,
      );
      return <String, Object?>{'error': '$error'};
    }
  }

  List<Map<String, Object?>> _androidReverseToolchainSetupCommandsMetadata() {
    return androidReverseToolchainProbes
        .map(
          (probe) => <String, Object?>{
            'id': probe.id,
            'label': probe.label,
            'required': probe.required,
            'install_hint': probe.installHintZh,
            if (probe.installCommand?.trim().isNotEmpty ?? false)
              'install_command': probe.installCommand!.trim(),
            if (probe.updateCommand?.trim().isNotEmpty ?? false)
              'update_command': probe.updateCommand!.trim(),
            if (probe.uninstallCommand?.trim().isNotEmpty ?? false)
              'uninstall_command': probe.uninstallCommand!.trim(),
            if (probe.referenceUrl?.trim().isNotEmpty ?? false)
              'reference_url': probe.referenceUrl!.trim(),
          },
        )
        .toList(growable: false);
  }

  Map<String, Object?> _androidReverseMcpLinkageMetadata() {
    try {
      final mcpController = context.read<McpController>();
      final relatedServers = <Map<String, Object?>>[];
      final toolSearchNames = <String>{};
      var relatedToolCount = 0;
      for (final server in mcpController.runtimeServers) {
        final catalog = mcpController.toolCatalogFor(server.name);
        final health = mcpController.healthStatusFor(server.name);
        final matchedTools = catalog.tools
            .where(
              (tool) => _androidReverseContainsMcpKeyword(
                '${tool.id} ${tool.name} ${tool.description}',
              ),
            )
            .toList(growable: false);
        final serverIsRelevant = _androidReverseContainsMcpKeyword(
          '${server.name} ${server.summary} ${server.type.transportValue}',
        );
        if (!serverIsRelevant && matchedTools.isEmpty) continue;
        relatedToolCount += matchedTools.length;
        for (final tool in matchedTools) {
          if (toolSearchNames.length >= _androidReverseMcpToolSearchLimit) {
            break;
          }
          toolSearchNames.add(_androidReverseResolvedMcpToolName(server, tool));
        }
        relatedServers.add(<String, Object?>{
          'name': server.name,
          'enabled': server.enabled,
          'transport': server.type.transportValue,
          if (server.summary.trim().isNotEmpty) 'summary': server.summary,
          'health_status': health.status.name,
          if (health.latencyMs != null) 'health_latency_ms': health.latencyMs,
          if (health.errorMessage?.trim().isNotEmpty ?? false)
            'health_error': health.errorMessage!.trim(),
          'tool_catalog_status': catalog.status.name,
          'tool_count': catalog.tools.length,
          'android_related_tool_count': matchedTools.length,
          if (catalog.errorMessage?.trim().isNotEmpty ?? false)
            'tool_catalog_error': catalog.errorMessage!.trim(),
          if (matchedTools.isNotEmpty)
            'android_related_tool_names': matchedTools
                .take(8)
                .map((tool) => _androidReverseResolvedMcpToolName(server, tool))
                .toList(growable: false),
        });
      }
      relatedServers.sort((a, b) {
        final aEnabled = a['enabled'] == true ? 1 : 0;
        final bEnabled = b['enabled'] == true ? 1 : 0;
        final enabled = bEnabled.compareTo(aEnabled);
        if (enabled != 0) return enabled;
        final aTools = a['android_related_tool_count'] is int
            ? a['android_related_tool_count'] as int
            : 0;
        final bTools = b['android_related_tool_count'] is int
            ? b['android_related_tool_count'] as int
            : 0;
        final tools = bTools.compareTo(aTools);
        if (tools != 0) return tools;
        return '${a['name']}'.compareTo('${b['name']}');
      });
      return <String, Object?>{
        'servers_file_path': mcpController.serversFilePath,
        'storage_dir': mcpController.storageDirectoryPath,
        'server_count': mcpController.runtimeServers.length,
        'related_server_count': relatedServers.length,
        'related_tool_count': relatedToolCount,
        'tool_search_recommended_query': toolSearchNames.isEmpty
            ? _androidReverseMcpFallbackToolSearchQuery
            : 'select:${toolSearchNames.join(',')}',
        if (mcpController.errorMessage?.trim().isNotEmpty ?? false)
          'error': mcpController.errorMessage!.trim(),
        if (relatedServers.isNotEmpty)
          'related_servers': relatedServers.take(12).toList(growable: false),
      };
    } catch (error, stack) {
      silentLog('openhand_home_page', '构建 Android 逆向 MCP 关联元数据', error, stack);
      return <String, Object?>{
        'error': '$error',
        'tool_search_recommended_query':
            _androidReverseMcpFallbackToolSearchQuery,
      };
    }
  }

  bool _androidReverseContainsMcpKeyword(String raw) {
    final text = raw.toLowerCase();
    return _androidReverseMcpKeywords.any(text.contains);
  }

  String _androidReverseResolvedMcpToolName(McpServer server, McpTool tool) {
    return compactToolName(prefix: 'mcp__${server.name}', token: tool.id);
  }

  void _scheduleWebReverseRuntimeMetadataSync() {
    _webReverseRuntimeMetadataDebouncer.schedule(
      _syncWebReverseRuntimeMetadata,
    );
  }

  void _syncWebReverseRuntimeMetadata() {
    if (!mounted) return;
    final entries = List<MapEntry<String, WebReverseSessionController>>.of(
      _webReverseControllers.entries,
    );
    for (final entry in entries) {
      unawaited(_persistWebReverseRuntimeMetadata(entry.key, entry.value));
    }
  }

  Future<bool> _persistWebReverseRuntimeMetadata(
    String sessionId,
    WebReverseSessionController controller, {
    WebReverseCdpMcpBridgeDiagnostic? cdpMcpBridgeDiagnostic,
  }) async {
    if (!mounted) return false;
    final sessionController = context.read<AiSessionController>();
    final session = sessionController.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final diagnostic =
        cdpMcpBridgeDiagnostic ??
        _webReverseCdpMcpBridge.cachedDiagnostic(
          enabled: _webReverseCdpMcpEnabledForSession(session),
          sessionId: sessionId,
          sessionTemplateId: session?.templateId,
          controller: controller,
          existingServers: context.read<McpController>().servers,
        );
    final metadata = _webReverseRuntimeMetadata(
      controller,
      cdpMcpBridgeDiagnostic: diagnostic,
    );
    _syncWebReverseTemplateRuntimeLinkage(
      sessionId,
      diagnostic,
      enabled: _webReverseCdpMcpEnabledForSession(session),
    );
    final signature = jsonEncode(metadata);
    if (_webReverseRuntimeMetadataSignatures[sessionId] == signature) {
      return true;
    }
    try {
      final updated = await sessionController.updateSessionMetadata(
        sessionId,
        <String, Object?>{'web_reverse_cdp_runtime': metadata},
      );
      if (!updated) return false;
      if (identical(_webReverseControllers[sessionId], controller)) {
        _webReverseRuntimeMetadataSignatures[sessionId] = signature;
      }
      return true;
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '保存 Web 逆向运行时元数据 $sessionId',
        error,
        stack,
      );
      return false;
    }
  }

  Map<String, Object?> _webReverseRuntimeMetadata(
    WebReverseSessionController controller, {
    WebReverseCdpMcpBridgeDiagnostic? cdpMcpBridgeDiagnostic,
  }) {
    final browserAlive = controller.isBrowserAlive;
    final port = controller.cdpPort;
    final browserVersion = controller.browserVersion?.trim();
    final currentTargetId = controller.currentPageTargetId;
    CdpPageTargetSnapshot? currentTarget;
    if (currentTargetId != null && currentTargetId.isNotEmpty) {
      for (final target in controller.pageTargets) {
        if (target.id == currentTargetId) {
          currentTarget = target;
          break;
        }
      }
    }
    return <String, Object?>{
      'source': 'OpenHand WebReverseSessionController',
      'is_running': controller.isRunning,
      'browser_alive': browserAlive,
      if (port != null && !browserAlive) 'last_cdp_port': port,
      if (port != null && browserAlive) ...<String, Object?>{
        'cdp_port': port,
        'cdp_host': webReverseCdpLoopbackHost,
        'cdp_http_endpoint': webReverseCdpHttpOrigin(port),
        'json_version_url': webReverseCdpHttpUri(
          port,
          webReverseCdpJsonVersionPath,
        ).toString(),
        'json_list_url': webReverseCdpHttpUri(port, '/json/list').toString(),
      },
      if (browserVersion != null && browserVersion.isNotEmpty)
        'browser_version': browserVersion,
      'artifacts_root_dir': controller.artifactsRootDir,
      if (currentTarget != null && browserAlive)
        'current_target': <String, Object?>{
          'id': currentTarget.id,
          'url': currentTarget.url,
          'title': currentTarget.title,
        },
      if (currentTarget != null && !browserAlive)
        'last_current_target': <String, Object?>{
          'id': currentTarget.id,
          'url': currentTarget.url,
          'title': currentTarget.title,
        },
      if (cdpMcpBridgeDiagnostic != null)
        'cdp_mcp_bridge': cdpMcpBridgeDiagnostic.toJson(),
      'mcp_plugin_linkage': _threadTemplateMcpPluginLinkageMetadata(
        TemplateRuntimeDependencyRegistry.webReverse,
      ),
    };
  }

  void _syncWebReverseTemplateRuntimeLinkage(
    String sessionId,
    WebReverseCdpMcpBridgeDiagnostic diagnostic, {
    required bool enabled,
  }) {
    try {
      _templateRuntimeLinkageController?.upsertSession(
        sessionId: sessionId,
        templateId: TemplateRuntimeDependencyRegistry.webReverse.templateId,
        capabilities: <TemplateRuntimeCapabilityState>[
          TemplateRuntimeCapabilityState(
            capabilityId: 'web_reverse_cdp_mcp',
            enabled: enabled,
            status: enabled ? diagnostic.status.name : 'disabled',
            serverName: diagnostic.serverName,
            toolCount: diagnostic.toolCount,
            message: diagnostic.message,
          ),
        ],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '同步 Web 逆向模板运行时关联', error, stack);
    }
  }

  /// 把 [WebReverseLaunchException] 转成"标题 + 详情"两段式文案，
  /// 标题给 SnackBar 主行，详情通过「详情」按钮展开。
  /// 详情区由 [WebReverseLaunchDiagnosis] 把 launcher 抓回来的 stderr
  /// 摘要 / 探测次数 / 进程退出码结构化为「现象 → 根因 → 建议」三段式，
  /// 末尾保留原始报错供高级用户复制。
  String _formatWebReverseLaunchError(WebReverseLaunchException error) {
    final headline = switch (error.failure) {
      WebReverseLaunchFailure.noFreePort => '9222-9322 端口区间已被占用，无法分配 CDP 端口',
      WebReverseLaunchFailure.spawnFailed => '浏览器进程启动失败',
      WebReverseLaunchFailure.cdpHandshakeFailed => 'CDP 握手超时',
    };
    final diagnosis = WebReverseLaunchDiagnosis.parse(error.message);
    final buf = StringBuffer()
      ..writeln(headline)
      ..writeln()
      ..writeln('【现象】${diagnosis.phenomenon}')
      ..writeln();
    for (var i = 0; i < diagnosis.causes.length; i++) {
      final c = diagnosis.causes[i];
      buf
        ..writeln('【可能根因 ${i + 1}】${c.title}')
        ..writeln('【建议】${c.suggestion}')
        ..writeln();
    }
    buf
      ..writeln('— 原始报错 —')
      ..writeln(diagnosis.fullText.trim());
    return buf.toString();
  }

  /// 给定 sessionId 返回当前活跃的 Web 逆向 controller（无则 null）。
  WebReverseSessionController? webReverseControllerFor(String sessionId) {
    return _webReverseControllers[sessionId];
  }

  bool _webReverseCdpMcpEnabledForSession(AiSession? session) {
    if (session?.templateId != WebReverseCdpMcpBridge.templateId) return false;
    final config = WebReverseSessionConfig.fromJson(
      session!.metadata['web_reverse_config'],
    );
    return config?.cdpMcpEnabled == true;
  }

  Future<bool> setWebReverseCdpMcpEnabled(
    String sessionId, {
    required bool enabled,
  }) async {
    if (!mounted) return false;
    final sessionController = context.read<AiSessionController>();
    final session = sessionController.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    if (session == null ||
        session.templateId != WebReverseCdpMcpBridge.templateId) {
      return false;
    }
    final config = WebReverseSessionConfig.fromJson(
      session.metadata['web_reverse_config'],
    );
    if (config == null) return false;
    if (config.cdpMcpEnabled == enabled) return true;
    final nextConfig = config.copyWith(cdpMcpEnabled: enabled);
    final updated = await sessionController.updateSessionMetadata(
      sessionId,
      <String, Object?>{'web_reverse_config': nextConfig.toJson()},
    );
    if (!updated || !mounted) return false;

    final controller = _webReverseControllers[sessionId];
    if (controller == null) return true;
    if (!enabled) {
      _webReverseCdpMcpBridge.stopSession(sessionId);
      await _persistWebReverseRuntimeMetadata(
        sessionId,
        controller,
        cdpMcpBridgeDiagnostic:
            const WebReverseCdpMcpBridgeDiagnostic.disabled(),
      );
      return true;
    }

    await _persistWebReverseRuntimeMetadata(
      sessionId,
      controller,
      cdpMcpBridgeDiagnostic: _webReverseCdpMcpBridge.cachedDiagnostic(
        enabled: true,
        sessionId: sessionId,
        sessionTemplateId: session.templateId,
        controller: controller,
        existingServers: context.read<McpController>().servers,
      ),
    );
    unawaited(_prepareEnabledWebReverseCdpMcp(sessionId));
    return true;
  }

  Future<void> _prepareEnabledWebReverseCdpMcp(String sessionId) async {
    if (!mounted) return;
    final sessionController = context.read<AiSessionController>();
    final mcpController = context.read<McpController>();
    final session = sessionController.sessions
        .where((item) => item.id == sessionId)
        .firstOrNull;
    final controller = _webReverseControllers[sessionId];
    if (session == null || controller == null) return;
    if (!_webReverseCdpMcpEnabledForSession(session)) return;
    final snapshot = await _webReverseCdpMcpBridge.buildSnapshot(
      enabled: true,
      sessionId: sessionId,
      sessionTemplateId: session.templateId,
      controller: controller,
      existingServers: mcpController.servers,
    );
    if (!mounted) return;
    await _persistWebReverseRuntimeMetadata(
      sessionId,
      controller,
      cdpMcpBridgeDiagnostic: snapshot.diagnostic,
    );
  }

  /// 按已存在的会话 metadata 重启 Web 逆向 controller（应用重启 / 切回旧会话用）。
  ///
  /// 若 metadata 缺失 / 浏览器探测失败 / 启动异常都会安全降级，错误以 SnackBar 通知。
  Future<WebReverseSessionController?> restoreWebReverseSession(
    AiSession session,
  ) {
    final existing = _webReverseControllers[session.id];
    if (existing != null) return Future.value(existing);
    final restoring = _webReverseRestoreTasks[session.id];
    if (restoring != null) return restoring;
    if (!_acquireReverseRuntimeSlot(session.id)) {
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          _reverseRuntimeCapacityMessage(context),
        );
      }
      return Future<WebReverseSessionController?>.value();
    }
    late final Future<WebReverseSessionController?> task;
    task = _restoreWebReverseSessionOnce(session).whenComplete(() {
      final controller = _webReverseControllers[session.id];
      _releaseInactiveReverseRuntimeSlot(
        session.id,
        active: controller?.hasManagedBrowserProcess ?? false,
      );
      if (identical(_webReverseRestoreTasks[session.id], task)) {
        _webReverseRestoreTasks.remove(session.id);
      }
    });
    _webReverseRestoreTasks[session.id] = task;
    return task;
  }

  Future<WebReverseSessionController?> _restoreWebReverseSessionOnce(
    AiSession session,
  ) async {
    final existing = _webReverseControllers[session.id];
    if (existing != null) return existing;
    final raw = session.metadata['web_reverse_config'];
    final config = WebReverseSessionConfig.fromJson(raw);
    if (config == null) {
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '该会话缺少 web_reverse_config，请新建会话。',
            en: 'Session is missing web_reverse_config; create a new session.',
          ),
        );
      }
      return null;
    }
    // 不强制沿用配置中的浏览器类型，用户机器上的可用浏览器可能已经变化。
    final detector = WebReverseBrowserDetector();
    var attempts = 0;
    var probe = await detector.detect();
    while (!probe.isInstalled &&
        attempts < _maxWebReverseRestoreDetectionAttempts - 1) {
      attempts += 1;
      if (!mounted) return null;
      final decision = await showWebReverseInstallGuideDialog(context);
      if (decision == null ||
          decision == WebReverseInstallGuideDecision.cancelled) {
        return null;
      }
      probe = await detector.detect();
    }
    if (!mounted) return null;
    if (!probe.isInstalled) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '连续检测 $_maxWebReverseRestoreDetectionAttempts 次仍未找到可用浏览器，请完成安装后重试。',
          en: 'No supported browser was found after $_maxWebReverseRestoreDetectionAttempts checks. Finish installation and try again.',
        ),
      );
      return null;
    }
    // 兼容旧 metadata：早期版本的 userDataDir 形如 `<root>/profile_<browser>`，
    // 多个会话会共享同一目录而触发 Profile 锁。这里在 restore 时按 sessionId
    // 改写，并把新值写回 metadata，从源头根除该 race；旧目录保留不动以避免
    // 误删用户已登录态，老会话首次 restore 后即升级到独立 profile。
    final userDataDirRoot =
        '${OpenHandPaths.defaultRootDirectoryPath()}/web_reverse';
    final desired =
        '$userDataDirRoot/profiles/${config.browserKind.id}_${session.id}';
    var effectiveConfig = config;
    if (config.userDataDir != desired) {
      effectiveConfig = config.copyWith(userDataDir: desired);
      try {
        await context.read<AiSessionController>().updateSessionMetadata(
          session.id,
          <String, Object?>{'web_reverse_config': effectiveConfig.toJson()},
        );
      } catch (e, st) {
        silentLog(
          'openhand_home_page',
          '为 ${session.id} 重写 user_data_dir',
          e,
          st,
        );
      }
    }
    if (!mounted ||
        !context.read<AiSessionController>().sessions.any(
          (item) => item.id == session.id,
        )) {
      _releaseReverseRuntimeSlot(session.id);
      return null;
    }
    final controller = WebReverseSessionController(
      config: effectiveConfig,
      executablePath: probe.executablePath!,
      artifactsRootDir:
          '${OpenHandPaths.defaultRootDirectoryPath()}/web_reverse/sessions/${session.id}',
    );
    _trimRetainedWebReverseControllers(makeRoom: true);
    _webReverseControllers[session.id] = controller;
    controller.addListener(_onWebReverseControllerChanged);
    var launchOk = false;
    try {
      await _startReverseRuntime(
        sessionId: session.id,
        start: controller.start,
        isActive: () => controller.hasManagedBrowserProcess,
      );
      launchOk = controller.isBrowserAlive;
      await _persistWebReverseRuntimeMetadata(session.id, controller);
    } on WebReverseLaunchException catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '恢复 Web 逆向（${error.failure}）',
        error,
        stack,
      );
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: _formatWebReverseLaunchError(error),
          fallback: '浏览器恢复启动失败',
        );
      }
    } catch (error, stack) {
      silentLog('openhand_home_page', '恢复 Web 逆向', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: userFailureMessage(error, fallback: '浏览器恢复启动失败'),
          fallback: '浏览器恢复启动失败',
        );
      }
    }
    if (!launchOk) {
      await _persistWebReverseRuntimeMetadata(session.id, controller);
      _webReverseControllers.remove(session.id);
      _webReverseRuntimeMetadataSignatures.remove(session.id);
      _webReverseCdpMcpBridge.stopSession(session.id);
      await _disposeWebReverseControllerAfterStop(session.id, controller);
      return null;
    }
    return controller;
  }

  HarnessSessionRecord _snapshotHarnessRecord(
    HarnessSessionRecord base,
    HarnessOrchestrator orchestrator,
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

  void _scheduleHarnessSessionSave(
    HarnessSessionRecord record, {
    bool immediate = false,
  }) {
    _harnessSessionSaveDebouncer.cancel();
    if (immediate) {
      unawaited(_persistHarnessSessionBestEffort(record));
      return;
    }
    _harnessSessionSaveDebouncer.schedule(
      () => _persistHarnessSessionBestEffort(record),
    );
  }

  Future<void> _persistHarnessSessionBestEffort(
    HarnessSessionRecord record,
  ) async {
    if (!DatabaseService.isInitialized) return;
    try {
      await _harnessSessionStore.save(record);
    } catch (error, stack) {
      if (!DatabaseService.isInitialized) return;
      silentLog('openhand_home_page', '保存 Harness 会话元数据', error, stack);
    }
  }

  HarnessSessionRecord _normalizeRestoredHarnessRecord(
    HarnessSessionRecord record,
  ) {
    final interruptedByAppClose =
        record.status == HarnessOrchestratorStatus.running ||
        (record.status == HarnessOrchestratorStatus.cancelled &&
            record.errorMessage ==
                'Session was interrupted because the app closed.');
    if (!interruptedByAppClose) {
      return record;
    }

    HarnessPhase? resumePhase;
    final normalizedPhaseLogs = record.phaseLogs
        .map((entry) {
          final isInterruptedPhase =
              entry.status == HarnessPhaseStatus.running ||
              entry.status == HarnessPhaseStatus.paused ||
              (resumePhase == null &&
                  entry.status == HarnessPhaseStatus.pending);
          if (!isInterruptedPhase) {
            return entry;
          }
          final nextLines = List<String>.from(entry.lines);
          final restoreMessage = entry.status == HarnessPhaseStatus.running
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
            statusValue: HarnessPhaseStatus.paused.name,
            lines: nextLines,
          );
        })
        .toList(growable: false);

    return record.copyWith(
      statusValue: HarnessOrchestratorStatus.idle.name,
      updatedAt: DateTime.now().toUtc(),
      phaseLogs: normalizedPhaseLogs,
      errorMessage: null,
      currentPhaseValue: resumePhase?.storageValue,
    );
  }

  /// Wires API-mode (URL) support on a [HarnessOrchestrator] so that phases
  /// configured with [HarnessExecutionMode.url] can run through the AI
  /// chat infrastructure instead of a CLI tool.
  void _wireHarnessApiMode(
    HarnessOrchestrator orchestrator, {
    required String sessionId,
  }) {
    final aiCtrl = context.read<AiSessionController>();
    orchestrator.apiPhaseRunner = HarnessApiPhaseRunner(
      chatClient: aiCtrl.chatClient,
      toolRuntimeService: aiCtrl.toolRuntimeService,
      toolUsagePromotionStore: aiCtrl.toolUsagePromotionStore,
      templateRepository: aiCtrl.templateRepository,
      usageSessionId: sessionId,
      confirmWriteCommand: _confirmHarnessApiWriteCommand,
      onToolSearchLoaded: _handleHarnessToolSearchLoaded,
      onPhaseEnded: _handleHarnessPhaseEnded,
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

  /// Loads the last-persisted Harness Engineering session record from disk
  /// and displays it in the navigation sidebar.
  Future<void> _loadPersistedHarnessSession() async {
    try {
      final record = await _harnessSessionStore.load();
      if (!mounted || record == null) {
        return;
      }
      final migratedRecord = _migrateLegacyHarnessAutoRewrittenModels(record);
      final effectiveRecord = _normalizeRestoredHarnessRecord(migratedRecord);
      if (effectiveRecord != record) {
        _scheduleHarnessSessionSave(effectiveRecord, immediate: true);
      }
      _activeHarnessOrchestrator?.removeListener(_onHarnessOrchestratorChanged);
      final restoredOrchestrator = HarnessOrchestrator(effectiveRecord.config);
      restoredOrchestrator.fullAccessPermission = _heFullAccessPermission;
      restoredOrchestrator.onPhaseApprovalRequired =
          _handlePhaseApprovalRequired;
      _wireHarnessApiMode(restoredOrchestrator, sessionId: effectiveRecord.id);
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
      restoredOrchestrator.addListener(_onHarnessOrchestratorChanged);
      _cacheHarnessShellState(restoredOrchestrator);
      setState(() {
        _persistedHarnessSession = effectiveRecord;
        _activeHarnessConfig = effectiveRecord.config;
        _activeHarnessOrchestrator = restoredOrchestrator;
      });
    } catch (error, stack) {
      _reportHarnessPersistenceError(
        operation: '恢复 Harness 会话',
        error: error,
        stack: stack,
        zhAction: '恢复 Harness 会话失败',
        enAction: 'Failed to restore the Harness session',
        postFrame: true,
      );
    }
  }

  /// Called whenever the active [HarnessOrchestrator] notifies listeners.
  /// Propagates status changes to the navigation tile and persisted record.
  void _onHarnessOrchestratorChanged() {
    if (!mounted) return;
    final orchestrator = _activeHarnessOrchestrator;
    final currentRecord = _persistedHarnessSession;
    if (orchestrator == null || currentRecord == null) return;
    final updatedRecord = _snapshotHarnessRecord(currentRecord, orchestrator);
    final statusChanged =
        updatedRecord.statusValue != currentRecord.statusValue;
    final awaitingApprovalChanged =
        _lastHarnessAwaitingApprovalPhase != orchestrator.awaitingApprovalPhase;
    _persistedHarnessSession = updatedRecord;
    _lastHarnessAwaitingApprovalPhase = orchestrator.awaitingApprovalPhase;
    _scheduleHarnessSessionSave(
      updatedRecord,
      immediate: orchestrator.status != HarnessOrchestratorStatus.running,
    );
    if (statusChanged || awaitingApprovalChanged) {
      setState(() {});
    }
  }

  void _handleHeFullAccessToggle(bool enabled) {
    if (!mounted) return;
    if (enabled) {
      // Show confirmation dialog before enabling full access.
      unawaited(_showFullAccessConfirmationDialog().then((confirmed) {
        if (confirmed && mounted) {
          setState(() {
            _heFullAccessPermission = true;
            _activeHarnessOrchestrator?.fullAccessPermission = true;
          });
        }
      }));
    } else {
      setState(() {
        _heFullAccessPermission = false;
        _activeHarnessOrchestrator?.fullAccessPermission = false;
      });
    }
  }

  void _handleHeConfigChanged(HarnessSessionConfig newConfig) {
    if (!mounted) return;
    final currentRecord = _persistedHarnessSession;
    final updatedRecord = currentRecord?.copyWith(
      config: newConfig,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() {
      _activeHarnessConfig = newConfig;
      if (updatedRecord != null) {
        _persistedHarnessSession = updatedRecord;
      }
    });
    _activeHarnessOrchestrator?.updateConfig(newConfig);
    if (updatedRecord != null) {
      _scheduleHarnessSessionSave(updatedRecord);
    }
    unawaited(_initializeHarnessPersistenceDirectories(newConfig));
  }

  Future<void> _initializeHarnessPersistenceDirectories(
    HarnessSessionConfig config,
  ) async {
    try {
      await config.initializePersistenceDirectories();
    } catch (error, stack) {
      _reportHarnessPersistenceError(
        operation: '更新 Harness 持久化目录',
        error: error,
        stack: stack,
        zhAction: '无法更新 Harness 持久化目录',
        enAction: 'Failed to update Harness storage',
      );
    }
  }

  static final RegExp _legacyHeAutoModelRewritePattern = RegExp(
    r'^ℹ 检测到旧模型标识 "([^"]+)"，已自动改用 ',
  );

  HarnessSessionRecord _migrateLegacyHarnessAutoRewrittenModels(
    HarnessSessionRecord record,
  ) {
    final recoveredModels = <HarnessPhase, String>{};
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

    HarnessRoleConfig restoreRoleConfig(
      HarnessRoleConfig roleConfig,
      HarnessPhase phase,
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
        HarnessPhase.metaCollection,
      ),
      readerConfig: restoreRoleConfig(
        record.config.readerConfig,
        HarnessPhase.reading,
      ),
      plannerConfig: restoreRoleConfig(
        record.config.plannerConfig,
        HarnessPhase.planning,
      ),
      implementerConfig: restoreRoleConfig(
        record.config.implementerConfig,
        HarnessPhase.implementing,
      ),
      reviewerConfig: restoreRoleConfig(
        record.config.reviewerConfig,
        HarnessPhase.reviewing,
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

  void _handlePhaseApprovalRequired(HarnessPhase nextPhase) {
    // The orchestrator pauses, creates a completer, and sets awaitingApprovalPhase.
    // The UI banner (_HePhaseApprovalBanner) handles user interaction.
    // resolvePhaseApproval() is called from the banner's approve/reject buttons,
    // which completes the orchestrator's internal completer and unblocks the
    // pipeline. This callback only triggers a rebuild so the banner appears.
    if (mounted) setState(() {});
  }

  /// Extracts a short display title from the raw task text.
  static String _harnessTitleFromTask(String task) {
    final firstLine =
        splitTrimmedNonEmpty(task, separator: '\n').firstOrNull ?? task.trim();
    return clipTextByCodeUnits(firstLine, 45, suffix: '…');
  }

  Future<void> _generateHarnessAutoTitle(
    String sessionId,
    HarnessSessionConfig config, {
    required String expectedCurrentTitle,
  }) async {
    final settingsController = context.read<SettingsController>();
    if (!settingsController.aiAutoTitleEnabled) {
      return;
    }
    final model = _resolveHarnessAutoTitleModel(
      config: config,
      settingsController: settingsController,
    );
    if (model == null) return;
    try {
      final generatedTitle = await context
          .read<AiSessionController>()
          .generateStandaloneAutoTitle(content: config.task, model: model);
      if (!mounted || generatedTitle == null || generatedTitle.isEmpty) {
        return;
      }
      final current = _persistedHarnessSession;
      if (current == null || current.id != sessionId) return;
      if (current.title != expectedCurrentTitle) {
        return;
      }
      final updated = current.copyWith(
        title: generatedTitle,
        updatedAt: DateTime.now().toUtc(),
      );
      setState(() {
        _persistedHarnessSession = updated;
      });
      await _harnessSessionStore.save(updated);
    } catch (error, stack) {
      silentLog('openhand_home_page', '生成 HE 自动标题', error, stack);
    }
  }

  AiModelConfig? _resolveHarnessAutoTitleModel({
    required HarnessSessionConfig config,
    required SettingsController settingsController,
  }) {
    for (final roleConfig in <HarnessRoleConfig>[
      config.profilerConfig,
      config.readerConfig,
      config.plannerConfig,
      config.implementerConfig,
      config.reviewerConfig,
    ]) {
      if (!roleConfig.isUrlMode) {
        continue;
      }
      final configId = roleConfig.aiModelConfigId?.trim();
      if (configId == null || configId.isEmpty) {
        continue;
      }
      final baseModel = settingsController.aiModels
          .where((model) => model.id == configId)
          .firstOrNull;
      if (baseModel == null) {
        continue;
      }
      final overrideModelId = roleConfig.urlModeModelId?.trim();
      return overrideModelId != null && overrideModelId.isNotEmpty
          ? baseModel.copyWith(modelId: overrideModelId)
          : baseModel;
    }
    return settingsController.selectedAiModel ??
        settingsController.aiModels.firstOrNull;
  }

  void _toggleInstructionSkip(String id) {
    setState(() {
      if (!_skippedInstructionIds.add(id)) {
        _skippedInstructionIds.remove(id);
      }
    });
  }

  Brightness _resolveEffectiveBrightness(BuildContext context) {
    final settingsController = context.read<SettingsController>();
    final themeMode = settingsController.themeMode;
    if (themeMode == ThemeMode.light) return Brightness.light;
    if (themeMode == ThemeMode.dark) return Brightness.dark;
    return MediaQuery.platformBrightnessOf(context);
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
    final sessionController = context.read<AiSessionController>();
    final effectiveBrightness = _resolveEffectiveBrightness(context);
    final mcpRuntimeReadyFuture = mcpController.ensureRuntimeToolCatalogs();
    sessionController.updateAvailableModelsForWebSearch(
      settingsController.aiModels,
    );
    sessionController.updateAvailableModelsForWebFetch(
      settingsController.aiModels,
    );
    final effectiveWorkingDirectory =
        workingDirectory ?? OpenHandPaths.applicationDirectoryPath();
    final gitSnapshotFuture = _gitSnapshotService.loadSnapshot(
      workingDirectory: effectiveWorkingDirectory,
    );
    _workspaceInstructionService.maxDocumentCharacters =
        settingsController.aiMaxWorkspaceDocumentCharacters;
    final workspaceInstructionDocumentsFuture = _workspaceInstructionService
        .loadDocuments(
          startDirectory: OpenHandPaths.applicationDirectoryPath(),
          homeDirectory: OpenHandPaths.homeDirectoryPath(),
        );
    await mcpRuntimeReadyFuture;
    final baseMcpServers = mcpController.runtimeServers;
    final currentSession = sessionController.currentSession;
    final currentWebReverseController = currentSession == null
        ? null
        : _webReverseControllers[currentSession.id];
    final currentWebReverseCdpMcpEnabled = _webReverseCdpMcpEnabledForSession(
      currentSession,
    );
    final webReverseCdpMcpSnapshotFuture = _webReverseCdpMcpBridge
        .buildSnapshot(
          enabled: currentWebReverseCdpMcpEnabled,
          sessionId: currentSession?.id,
          sessionTemplateId: currentSession?.templateId,
          controller: currentWebReverseController,
          existingServers: baseMcpServers,
        );
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{
      for (final server in baseMcpServers)
        server.name: mcpController.toolCatalogFor(server.name),
    };
    final gitSnapshot = await gitSnapshotFuture;
    final workspaceInstructionDocuments =
        await workspaceInstructionDocumentsFuture;
    final webReverseCdpMcpSnapshot = await webReverseCdpMcpSnapshotFuture;
    final availableMcpServers = <McpServer>[
      ...baseMcpServers,
      ...webReverseCdpMcpSnapshot.servers,
    ];
    mcpToolCatalogsByServerName.addAll(
      webReverseCdpMcpSnapshot.catalogsByServerName,
    );
    if (currentSession != null &&
        currentWebReverseController != null &&
        currentSession.templateId == WebReverseCdpMcpBridge.templateId) {
      await _persistWebReverseRuntimeMetadata(
        currentSession.id,
        currentWebReverseController,
        cdpMcpBridgeDiagnostic: webReverseCdpMcpSnapshot.diagnostic,
      );
    }
    final memoryEnabled = settingsController.memoryEnabled;
    final memoryEntries = memoryEnabled
        ? await memoryController.trustedEntriesSnapshot() ??
              const <UserMemoryEntry>[]
        : const <UserMemoryEntry>[];
    final now = DateTime.now().toLocal();
    return buildAiSessionRuntimeContext(
      settingsController: settingsController,
      appInfo: appInfo,
      appThemeBrightness: effectiveBrightness.name,
      localNow: now,
      workingDirectory: effectiveWorkingDirectory,
      memoryEntries: memoryEntries,
      allowCommandRules: settingsController.aiAllowCommandRules,
      availableSkills: skillsController.skills,
      availableMcpServers: availableMcpServers,
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
      builtinToolConfigs: settingsController.builtinToolConfigs,
      repositorySnapshot: gitSnapshot,
      workspaceInstructionDocuments: workspaceInstructionDocuments,
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
    final model = _effectiveModelForSession(settingsController, session);
    if (session == null || model == null) {
      _runtimeToolPreviewCacheKey = null;
      _runtimeToolPreviewCacheValue = null;
      return null;
    }

    final allowCommandRules = settingsController.aiAllowCommandRules;
    final builtinToolConfigs = settingsController.builtinToolConfigs;
    final availableSkills = skillsController.skills;
    final baseMcpServers = mcpController.runtimeServers;
    final webReverseCdpMcpSnapshot = _webReverseCdpMcpBridge.cachedSnapshot(
      enabled: _webReverseCdpMcpEnabledForSession(session),
      sessionId: session.id,
      sessionTemplateId: session.templateId,
      controller: _webReverseControllers[session.id],
      existingServers: baseMcpServers,
    );
    final availableMcpServers = <McpServer>[
      ...baseMcpServers,
      ...webReverseCdpMcpSnapshot.servers,
    ];
    final now = DateTime.now().toLocal();
    final todayLocalDate = formatYearMonthDay(now);
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{};
    final mcpCatalogKeyParts = <Object?>[];
    for (final server in availableMcpServers) {
      final catalog =
          webReverseCdpMcpSnapshot.catalogsByServerName[server.name] ??
          mcpController.toolCatalogFor(server.name);
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
      settingsController.subprocessGracefulShutdownMs,
      settingsController.bashOutputMaxBytes,
      settingsController.maxConcurrentTools,
      settingsController.aiAttachmentMaxInlineImageDimension,
      settingsController.aiAttachmentMaxTextRawBytes,
      settingsController.aiAttachmentMaxPdfRawBytes,
      settingsController.aiAttachmentMaxImageRawBytes,
      settingsController.aiChatMaxStreamLineBufferBytes,
      settingsController.aiImageSizeLimitBytes,
      settingsController.memoryEnabled,
      settingsController.mcpLazyLoadingMode,
      settingsController.mcpLazyLoadingThresholdTokens,
      settingsController.aiWriteCommandConfirmationEnabled,
      settingsController.aiConnectTimeoutSeconds,
      settingsController.aiResponseTimeoutSeconds,
      settingsController.aiStreamIdleTimeoutSeconds,
      settingsController.aiAutoTitleEnabled,
      settingsController.telemetryDebugEnabled,
      settingsController.telemetryCaptureRawPayload,
      settingsController.telemetryCaptureEnvironment,
      settingsController.telemetryMaxPayloadChars,
      settingsController.aiSandboxSettings,
      settingsController.builtinToolLazyLoadingMode,
      settingsController.mcpLazyLoadingThresholdTokens,
      _identityHashAll(allowCommandRules),
      allowCommandRules.length,
      _identityHashAll(builtinToolConfigs),
      builtinToolConfigs.length,
      _identityHashAll(availableSkills),
      availableSkills.length,
      // 必须按元素身份哈希：availableMcpServers 是每次调用现拼的新 List，
      // 用 identityHashCode 取整个 List 的身份会导致缓存键每帧都变、
      // previewRuntimeToolCatalog 在每次 build 同步重算整个工具目录。
      _identityHashAll(availableMcpServers),
      availableMcpServers.length,
      todayLocalDate,
      now.timeZoneName,
      ...mcpCatalogKeyParts,
    ]);
    if (_runtimeToolPreviewCacheKey == cacheKey) {
      return _runtimeToolPreviewCacheValue;
    }

    final runtimeCatalogPreviewContext = _buildRuntimeCatalogPreviewContext(
      context: context,
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

  int _identityHashAll(Iterable<Object?> values) {
    return Object.hashAll(values.map(identityHashCode));
  }

  AiSessionRuntimeContext _buildRuntimeCatalogPreviewContext({
    required BuildContext context,
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required AppInfo appInfo,
    required DateTime now,
    List<AiAllowCommandRule>? allowCommandRules,
    List<LocalSkill>? availableSkills,
    List<McpServer>? availableMcpServers,
    List<AiBuiltinToolConfig>? builtinToolConfigs,
  }) {
    final localNow = now.toLocal();
    final servers = availableMcpServers ?? mcpController.runtimeServers;
    return buildAiSessionRuntimeContext(
      settingsController: settingsController,
      appInfo: appInfo,
      appThemeBrightness: _resolveEffectiveBrightness(context).name,
      localNow: localNow,
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      memoryEntries: const <UserMemoryEntry>[],
      allowCommandRules:
          allowCommandRules ?? settingsController.aiAllowCommandRules,
      availableSkills: availableSkills ?? skillsController.skills,
      availableMcpServers: servers,
      mcpToolCatalogsByServerName: <String, McpToolCatalog>{
        for (final server in servers)
          server.name: mcpController.toolCatalogFor(server.name),
      },
      builtinToolConfigs:
          builtinToolConfigs ?? settingsController.builtinToolConfigs,
    );
  }

  Future<void> _setComposerMode(AiSessionMode mode) async {
    final sessionController = context.read<AiSessionController>();
    final currentSession = sessionController.currentSession;
    if (currentSession == null) {
      if (mode == AiSessionMode.goal) {
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '请先进入支持目标模式的线程。',
            en: 'Open a thread that supports Goal Mode first.',
          ),
        );
        return;
      }
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
    AiSessionGoalStartOptions? pendingGoalStartOptions;
    if (mode == AiSessionMode.goal) {
      if (!aiSessionGoalModeAllowedForTemplate(currentSession.templateId)) {
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '当前线程模板暂不支持目标模式。',
            en: 'This thread template does not support Goal Mode.',
          ),
        );
        return;
      }
      final settingsController = context.read<SettingsController>();
      final selectedModel = _effectiveModelForSession(
        settingsController,
        currentSession,
      );
      if (selectedModel == null) {
        showOpenHandErrorSnack(
          context,
          AppLocalizations.of(context)!.aiModelSelectionRequired,
        );
        return;
      }
      final result = await _showGoalStartOptionsDialog(
        selectedModel: selectedModel,
      );
      if (!mounted || result == null) {
        return;
      }
      if (sessionController.currentSessionId != currentSession.id) {
        return;
      }
      pendingGoalStartOptions = result;
    }
    final updated = await sessionController.updateSessionMode(
      currentSession.id,
      mode,
    );
    if (!mounted) {
      return;
    }
    if (updated) {
      if (mode == AiSessionMode.goal && pendingGoalStartOptions != null) {
        _pendingGoalStartOptionsBySessionId[currentSession.id] =
            pendingGoalStartOptions;
      } else {
        _pendingGoalStartOptionsBySessionId.remove(currentSession.id);
      }
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final errorMessage = sessionController.lastErrorMessage;
    showFriendlyErrorSnackBar(
      context,
      message: errorMessage,
      fallback: l10n.chatRequestFailed,
    );
  }

  AiSessionGoalStartOptions? _rememberedGoalStartOptionsForSession(
    AiSession? session,
  ) {
    if (session == null) return null;
    final cached = _pendingGoalStartOptionsBySessionId[session.id];
    if (cached != null) return cached;
    final restored = _goalStartOptionsFromLatestGoal(session);
    if (restored != null) {
      _pendingGoalStartOptionsBySessionId[session.id] = restored;
    }
    return restored;
  }

  AiSessionGoalStartOptions? _goalStartOptionsFromLatestGoal(
    AiSession session,
  ) {
    final goalState = session.goalState;
    final latestGoal =
        goalState.current ??
        (goalState.history.isEmpty ? null : goalState.history.last);
    if (latestGoal == null) return null;
    final evaluatorProviderConfigId = latestGoal.evaluatorProviderConfigId
        .trim();
    final evaluatorModelId = latestGoal.evaluatorModelId.trim();
    if (evaluatorProviderConfigId.isEmpty || evaluatorModelId.isEmpty) {
      return null;
    }
    final evaluatorModelLabel = latestGoal.evaluatorModelLabel.trim();
    return AiSessionGoalStartOptions(
      evaluatorProviderConfigId: evaluatorProviderConfigId,
      evaluatorModelId: evaluatorModelId,
      evaluatorModelLabel: evaluatorModelLabel.isEmpty
          ? evaluatorModelId
          : evaluatorModelLabel,
      maxTurns: latestGoal.maxTurns,
      tokenBudget: latestGoal.tokenBudget,
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
    showFriendlyErrorSnackBar(
      context,
      message: errorMessage,
      fallback: l10n.chatRequestFailed,
    );
  }

  Future<bool> _showFullAccessConfirmationDialog() {
    return showOpenHandFullAccessConfirmationDialog(context: context);
  }

  void _queueMessageForSession({
    required String sessionId,
    required String prompt,
    required List<_ComposerAttachmentDraft> pendingAttachments,
    required AiCreationRequest creationRequest,
    required List<String> additionalSystemReminders,
    required Map<String, Object?>? selectedSkillMetadata,
  }) {
    final queue = _queuedMessagesBySessionId[sessionId];
    if ((queue?.length ?? 0) >= _maxQueuedMessagesPerSession) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '等待队列最多保留 $_maxQueuedMessagesPerSession 条消息。',
          en: 'The waiting queue can hold up to $_maxQueuedMessagesPerSession messages.',
        ),
      );
      return;
    }
    final queued = _QueuedMessage(
      id: _nextQueuedMessageId(),
      text: prompt,
      attachments: pendingAttachments,
      creationRequest: creationRequest,
      systemReminders: additionalSystemReminders,
      skillMetadata: selectedSkillMetadata,
    );
    setState(() {
      final q = queue ?? <_QueuedMessage>[];
      q.add(queued);
      _queuedMessagesBySessionId[sessionId] = q;
      _replaceComposerText('');
      _pendingAttachments = const <_ComposerAttachmentDraft>[];
      _creationMode = _CreationMode.none;
      _creationOptions = AiCreationOptions.empty;
      if (!_composerCollapsed) {
        _composerFocusNode.requestFocus();
      }
    });
    if (!mounted) {
      return;
    }
    OpenHandGlobalSnackBarHost.hideCurrent();
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '消息已暂存，将在当前回答完成后自动发送。',
        en: 'Message queued and will be sent automatically.',
      ),
      duration: kOpenHandSnackBarBriefDuration,
    );
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
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      sessionController.currentSession,
    );
    if (selectedModel == null) {
      showOpenHandErrorSnack(context, l10n.aiModelSelectionRequired);
      return;
    }
    final attachmentCapabilities = _selectedModelAttachmentCapabilities(
      selectedModel,
    );
    if (pendingAttachments.isNotEmpty && !attachmentCapabilities.supportsAny) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前模型不支持附件。',
          en: 'The selected model does not support attachments.',
        ),
      );
      return;
    }
    final unsupportedAttachmentCount = pendingAttachments
        .where((item) => !attachmentCapabilities.supportsPath(item.filePath))
        .length;
    if (unsupportedAttachmentCount > 0) {
      _showAttachmentAppendNotices(
        _AppendComposerAttachmentsResult(
          unsupported: unsupportedAttachmentCount,
        ),
      );
      return;
    }
    final existingSessionId = sessionController.currentSessionId;
    if (existingSessionId != null &&
        _displaySendPhaseForSession(sessionController, existingSessionId) !=
            AiSendPhase.idle) {
      final composerState = _composerPanelState;
      final skillDisplayMetadata = composerState?.peekPendingSkillMetadata();
      final skillReminder = composerState?.consumePendingSkillReminder();
      final additionalSystemReminders = <String>[
        if (skillReminder != null && skillReminder.trim().isNotEmpty)
          skillReminder,
      ];
      _queueMessageForSession(
        sessionId: existingSessionId,
        prompt: prompt,
        pendingAttachments: pendingAttachments,
        creationRequest: _creationRequestFromComposer(_creationMode),
        additionalSystemReminders: additionalSystemReminders,
        selectedSkillMetadata: skillDisplayMetadata,
      );
      return;
    }
    final slashCommand = parseOpenHandSlashCommand(prompt);
    if (slashCommand != null) {
      if (pendingAttachments.isNotEmpty) {
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '本地斜杠命令不支持携带附件。',
            en: 'Local slash commands do not accept attachments.',
          ),
        );
        return;
      }
      _replaceComposerText('');
      await _handleSlashCommand(slashCommand);
      return;
    }
    AiSessionRuntimeContext? runtimeContext;
    final submitPreflightTimingsMs = <String, int>{};
    if (sessionController.currentSession == null) {
      final templateId = await _showThreadTemplateDialog();
      if (!mounted || templateId == null) {
        return;
      }
      if (templateId == 'web_reverse_expert') {
        await _showWebReverseSetupAndCreate(
          initialPrompt: prompt,
          initialMode: _detachedComposerMode,
          initialFullAccessPermission: _detachedFullAccessPermission,
        );
        return;
      }
      if (templateId == 'android_reverse_expert') {
        await _showAndroidReverseSetupAndCreate(
          initialPrompt: prompt,
          runtimeContext: runtimeContext,
          initialMode: _detachedComposerMode,
          initialFullAccessPermission: _detachedFullAccessPermission,
        );
        return;
      }
      // Programming Expert: show project config dialog so the AI knows
      // the correct working directory and project context.
      _ProgrammingExpertConfig? peConfig;
      if (templateId == 'programming_expert') {
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
      final runtimeContextStopwatch = Stopwatch()..start();
      runtimeContext = await _buildRuntimeContext(
        workingDirectory: peConfig?.projectRoot,
        skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
      );
      submitPreflightTimingsMs['runtime_context_build'] =
          runtimeContextStopwatch.elapsedMilliseconds;
      if (!mounted) {
        return;
      }
      final created = templateId == kMachineExpertTemplateId
          ? await _createMachineExpertSession(
              runtimeContext: runtimeContext,
              initialMode: _detachedComposerMode,
              initialFullAccessPermission: _detachedFullAccessPermission,
            )
          : await _createSession(
              templateId: templateId,
              runtimeContext: runtimeContext,
              initialMode: _detachedComposerMode,
              initialFullAccessPermission: _detachedFullAccessPermission,
            );
      if (!mounted || !created || sessionController.currentSession == null) {
        return;
      }
      // After creating a PE session, persist the project config into metadata.
      if (peConfig != null) {
        final currentSession = sessionController.currentSession;
        if (currentSession != null) {
          await sessionController.updateSessionMetadata(
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
    // 技能提示词通过隐藏元数据发送，避免污染会话中展示的用户原文。
    final composerState = _composerPanelState;
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
      _queueMessageForSession(
        sessionId: targetSessionId,
        prompt: prompt,
        pendingAttachments: pendingAttachments,
        creationRequest: _creationRequestFromComposer(_creationMode),
        additionalSystemReminders: additionalSystemReminders,
        selectedSkillMetadata: skillDisplayMetadata,
      );
      return;
    }
    final sendSession = _sessionForId(sessionController, targetSessionId);
    if (sendSession?.hasActiveGoal == true) {
      final activeContext = context;
      if (!activeContext.mounted) {
        return;
      }
      final activeGoalMessage = openHandLocalizedText(
        activeContext,
        zh: '当前目标仍在执行中，请暂停后继续目标或终止目标。',
        en: 'A goal is active. Resume or terminate it before sending manually.',
      );
      showOpenHandInfoSnack(activeContext, activeGoalMessage);
      return;
    }
    AiSessionGoalStartOptions? goalStartOptions;
    if (sendSession?.mode == AiSessionMode.goal) {
      goalStartOptions = _rememberedGoalStartOptionsForSession(sendSession);
      if (goalStartOptions == null) {
        final result = await _showGoalStartOptionsDialog(
          selectedModel: selectedModel,
        );
        if (!mounted || result == null) {
          return;
        }
        goalStartOptions = result;
        _pendingGoalStartOptionsBySessionId[targetSessionId] = goalStartOptions;
      }
    }

    _replaceComposerText('');
    // Capture the creation mode and reset it before sending.
    final creationMode = _creationMode;
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
      responseModalities: creationRequest.responseModalities,
      creationRequest: creationRequest,
      callerPreflightTimingsMs: submitPreflightTimingsMs,
      additionalSystemReminders: additionalSystemReminders,
      selectedSkillMetadata: skillDisplayMetadata,
      goalStartOptions: goalStartOptions,
    );
  }

  void _beginPendingAutoStartSubmission(String sessionId) {
    _locallyStoppedPendingSubmissionSessionIds.remove(sessionId);
    if (mounted) {
      setState(() => _submittingSessionId = sessionId);
    } else {
      _submittingSessionId = sessionId;
    }
  }

  bool _autoStartSubmissionWasStopped(String sessionId) {
    return _locallyStoppedPendingSubmissionSessionIds.contains(sessionId);
  }

  void _clearPendingAutoStartSubmission(String sessionId) {
    _locallyStoppedPendingSubmissionSessionIds.remove(sessionId);
    if (_activeSubmissionSerialsBySessionId.containsKey(sessionId)) {
      return;
    }
    if (mounted) {
      setState(() {
        if (_submittingSessionId == sessionId) {
          _submittingSessionId = null;
        }
      });
    } else if (_submittingSessionId == sessionId) {
      _submittingSessionId = null;
    }
  }

  /// Translates the composer-private [_CreationMode] enum into the public
  /// [AiCreationRequest] model that the controller/adapter layers speak.
  AiCreationRequest _creationRequestFromComposer(_CreationMode mode) {
    switch (mode) {
      case _CreationMode.none:
        return AiCreationRequest.none;
      case _CreationMode.image:
        final options = _creationOptions.hasExplicitOptions
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

  _CreationMode _composerModeFromCreationRequest(AiCreationRequest request) {
    return switch (request.mode) {
      AiCreationMode.none => _CreationMode.none,
      AiCreationMode.image => _CreationMode.image,
      AiCreationMode.video => _CreationMode.video,
      AiCreationMode.audio => _CreationMode.audio,
      AiCreationMode.deepResearch => _CreationMode.deepResearch,
    };
  }

  ({_CreationMode mode, AiCreationOptions options})
  _composerCreationStateFromRequest(AiCreationRequest request) {
    final mode = _composerModeFromCreationRequest(request);
    if (mode == _CreationMode.none) {
      return (mode: _CreationMode.none, options: AiCreationOptions.empty);
    }
    return (mode: mode, options: request.options);
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

  Future<AiSessionGoalStartOptions?> _showGoalStartOptionsDialog({
    required AiModelConfig selectedModel,
  }) {
    final settingsController = context.read<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;
    return showAnimatedDialog<AiSessionGoalStartOptions>(
      context: context,
      barrierColor: colorScheme.scrim.withValues(alpha: 0.38),
      builder: (dialogContext) => _GoalStartOptionsDialog(
        availableModels: settingsController.aiModels,
        recentSelections: settingsController.recentModelSelections,
        initialModel: selectedModel,
      ),
    );
  }

  /// 打开当前创建模式的选项面板；用户未确认时返回 `null`。
  Future<AiCreationOptions?> _showCreationOptionsSheet(
    _CreationMode mode,
    AiCreationOptions initial,
  ) async {
    if (mode == _CreationMode.none || mode == _CreationMode.deepResearch) {
      return null;
    }
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      sessionController.currentSession,
    );
    final colorScheme = Theme.of(context).colorScheme;
    return showAnimatedModalSheet<AiCreationOptions>(
      context: context,
      barrierColor: colorScheme.scrim.withValues(alpha: 0.38),
      showDragHandle: false,
      elevation: 14,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius)),
      builder: (dialogContext) => _CreationOptionsSheet(
        mode: mode,
        initial: initial,
        selectedModel: selectedModel,
      ),
    );
  }

  Future<bool> _ensureReverseRuntimeReadyForSubmission(
    AiSession? session,
  ) async {
    if (session == null) return true;
    try {
      if (session.templateId == WebReverseCdpMcpBridge.templateId) {
        var controller = _webReverseControllers[session.id];
        controller ??= await restoreWebReverseSession(session);
        if (controller == null || !mounted) return false;
        if (!controller.isBrowserAlive) {
          await restartWebReverseBrowser(session.id, controller);
        }
        if (!controller.isBrowserAlive) {
          throw StateError('Web 逆向浏览器未连接。');
        }
      } else if (session.templateId ==
          TemplateRuntimeDependencyRegistry.androidReverse.templateId) {
        final controller = ensureAndroidReverseControllerFor(session);
        if (controller == null) {
          throw StateError('Android 逆向会话缺少运行配置。');
        }
        if (!controller.isRunning) {
          await _startReverseRuntime(
            sessionId: session.id,
            start: controller.start,
            isActive: () => controller.isRunning,
          );
        }
        if (!controller.isRunning) {
          throw StateError('Android 逆向运行时未启动。');
        }
      }
      return true;
    } catch (error, stack) {
      silentLog('openhand_home_page', '准备逆向会话运行时', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: '$error',
          fallback: '逆向会话运行时准备失败',
        );
      }
      return false;
    }
  }

  Future<_SubmitTextOutcome> _submitTextToSession(
    String targetSessionId,
    String prompt,
    List<_ComposerAttachmentDraft> pendingAttachments, {
    AiSessionRuntimeContext? runtimeContext,
    Map<String, int> callerPreflightTimingsMs = const <String, int>{},
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    List<String> additionalSystemReminders = const <String>[],
    Map<String, Object?>? selectedSkillMetadata,
    AiSessionGoalStartOptions? goalStartOptions,
    bool allowQueuedGoalInterruption = false,
    bool restoreDraftOnLocalStop = true,
    bool processQueueAfterCompletion = true,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final l10n = AppLocalizations.of(context)!;
    await sessionController.ensureSessionMessagesHydrated(targetSessionId);
    if (!mounted) {
      return _SubmitTextOutcome.failedBeforeSubmit;
    }
    final initialSession = sessionController.sessions
        .cast<AiSession?>()
        .firstWhere((s) => s?.id == targetSessionId, orElse: () => null);
    final selectedModel = _effectiveModelForSession(
      settingsController,
      initialSession,
    );
    if (selectedModel == null) return _SubmitTextOutcome.failedBeforeSubmit;
    final attachmentCapabilities = _selectedModelAttachmentCapabilities(
      selectedModel,
    );
    if (pendingAttachments.any(
      (item) => !attachmentCapabilities.supportsPath(item.filePath),
    )) {
      if (mounted) {
        _showAttachmentAppendNotices(
          _AppendComposerAttachmentsResult(
            unsupported: pendingAttachments
                .where(
                  (item) => !attachmentCapabilities.supportsPath(item.filePath),
                )
                .length,
          ),
        );
      }
      return _SubmitTextOutcome.failedBeforeSubmit;
    }
    if (!await _ensureReverseRuntimeReadyForSubmission(initialSession)) {
      return _SubmitTextOutcome.failedBeforeSubmit;
    }
    final initialUserMessageCount = initialSession != null
        ? _visibleUserMessageCount(initialSession)
        : 0;
    final editingMessageIdBeforeSend = sessionController.editingMessageId;
    _submissionSerial += 1;
    final submissionSerial = _submissionSerial;
    final stoppedBeforeSubmissionSerial =
        _locallyStoppedPendingSubmissionSessionIds.remove(targetSessionId);
    _activeSubmissionSerialsBySessionId[targetSessionId] = submissionSerial;
    if (stoppedBeforeSubmissionSerial) {
      _locallyStoppedSubmissionSerialsBySessionId[targetSessionId] =
          submissionSerial;
    } else {
      _locallyStoppedSubmissionSerialsBySessionId.remove(targetSessionId);
    }

    _storeComposerDraftForSession(
      targetSessionId,
      text: prompt,
      attachments: pendingAttachments,
      creationRequest: creationRequest,
    );

    setState(() {
      _submittingSessionId = targetSessionId;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
    bool submissionWasStopped() =>
        _locallyStoppedSubmissionSerialsBySessionId[targetSessionId] ==
        submissionSerial;
    bool submittedUserTurnVisible() {
      final targetSession = _sessionForId(sessionController, targetSessionId);
      if (_visibleUserMessageCount(targetSession) > initialUserMessageCount) {
        return true;
      }
      if (targetSession == null || editingMessageIdBeforeSend == null) {
        return false;
      }
      for (final message in targetSession.messages) {
        if (message.id == editingMessageIdBeforeSend &&
            !message.isDeleted &&
            message.kind == AiSessionMessageKind.user &&
            message.content.trim() == prompt) {
          return true;
        }
      }
      return false;
    }

    _SubmitTextOutcome unresolvedOutcome({required bool stopped}) {
      if (submittedUserTurnVisible()) {
        return _SubmitTextOutcome.submitted;
      }
      return stopped
          ? _SubmitTextOutcome.stoppedBeforeSubmit
          : _SubmitTextOutcome.failedBeforeSubmit;
    }

    void restoreSubmittedDraftIfNeeded({required bool localStop}) {
      if (localStop && !restoreDraftOnLocalStop) {
        _removeComposerDraftForSession(targetSessionId);
        return;
      }
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
          creationRequest: creationRequest,
        );
      }
    }

    try {
      if (submissionWasStopped()) {
        restoreSubmittedDraftIfNeeded(localStop: true);
        return _SubmitTextOutcome.stoppedBeforeSubmit;
      }
      final submitPreflightTimingsMs = <String, int>{
        ...callerPreflightTimingsMs,
      };
      if (runtimeContext == null) {
        // For Programming Expert sessions, use the project root as the
        // working directory so tool calls resolve against the loaded project.
        final peProjectRoot = _programmingExpertProjectRoot(initialSession);
        final runtimeContextStopwatch = Stopwatch()..start();
        runtimeContext = await _buildRuntimeContext(
          workingDirectory: peProjectRoot,
          skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
        );
        submitPreflightTimingsMs['runtime_context_build'] =
            runtimeContextStopwatch.elapsedMilliseconds;
      }
      if (!mounted) {
        return unresolvedOutcome(stopped: false);
      }
      if (submissionWasStopped()) {
        restoreSubmittedDraftIfNeeded(localStop: true);
        return unresolvedOutcome(stopped: true);
      }
      final sendSession = sessionController.sessions
          .cast<AiSession?>()
          .firstWhere((s) => s?.id == targetSessionId, orElse: () => null);
      final requireWriteConfirmation =
          AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
            templateId: sendSession?.templateId,
            fullAccessPermission: sendSession?.fullAccessPermission ?? false,
            globalConfirmationEnabled:
                settingsController.aiWriteCommandConfirmationEnabled,
          );
      final sent = await sessionController.sendMessage(
        sessionId: targetSessionId,
        content: prompt,
        model: selectedModel,
        runtimeContext: runtimeContext,
        callerPreflightTimingsMs: submitPreflightTimingsMs,
        responseModalities: responseModalities,
        creationRequest: creationRequest,
        attachmentFilePaths: pendingAttachments
            .map((item) => item.filePath)
            .toList(growable: false),
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation: requireWriteConfirmation,
        confirmWriteCommand: (request) =>
            _confirmWriteCommand(request, sessionId: targetSessionId),
        additionalSystemReminders: additionalSystemReminders,
        selectedSkillMetadata: selectedSkillMetadata,
        goalStartOptions: goalStartOptions,
        allowQueuedGoalInterruption: allowQueuedGoalInterruption,
      );
      if (!mounted) {
        return sent || submittedUserTurnVisible()
            ? _SubmitTextOutcome.submitted
            : _SubmitTextOutcome.failedBeforeSubmit;
      }
      if (submissionWasStopped()) {
        restoreSubmittedDraftIfNeeded(localStop: true);
        return unresolvedOutcome(stopped: true);
      }
      if (!sent) {
        if (submissionWasStopped()) {
          restoreSubmittedDraftIfNeeded(localStop: true);
          return unresolvedOutcome(stopped: true);
        }
        restoreSubmittedDraftIfNeeded(localStop: false);
        final errorMessage = sessionController.lastErrorMessageForSession(
          targetSessionId,
        );
        showFriendlyErrorSnackBar(
          context,
          message: errorMessage,
          fallback: l10n.chatRequestFailed,
        );
        return unresolvedOutcome(stopped: false);
      }
      if (!submittedUserTurnVisible()) {
        restoreSubmittedDraftIfNeeded(localStop: submissionWasStopped());
        return unresolvedOutcome(stopped: submissionWasStopped());
      }
      _removeComposerDraftForSession(targetSessionId);
      await sessionController.completeEditingMessage();
      if (!mounted) {
        return _SubmitTextOutcome.submitted;
      }
      if (sessionController.didCompressInLastSendForSession(targetSessionId)) {
        showOpenHandInfoSnack(context, l10n.threadCompressionNotice);
      }
      _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
      return _SubmitTextOutcome.submitted;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'openhand_home_page',
          context: ErrorDescription('发送聊天消息时'),
        ),
      );
      if (mounted && (!submissionWasStopped() || restoreDraftOnLocalStop)) {
        restoreSubmittedDraftIfNeeded(localStop: submissionWasStopped());
      }
      if (mounted) {
        final errorMessage = '$error'.trim();
        showOpenHandErrorSnack(
          context,
          errorMessage.isEmpty ? l10n.chatRequestFailed : errorMessage,
        );
      }
      return unresolvedOutcome(stopped: submissionWasStopped());
    } finally {
      final isActiveSubmission =
          _activeSubmissionSerialsBySessionId[targetSessionId] ==
          submissionSerial;
      if (isActiveSubmission) {
        _activeSubmissionSerialsBySessionId.remove(targetSessionId);
        _locallyStoppedPendingSubmissionSessionIds.remove(targetSessionId);
        if (_locallyStoppedSubmissionSerialsBySessionId[targetSessionId] ==
            submissionSerial) {
          _locallyStoppedSubmissionSerialsBySessionId.remove(targetSessionId);
        }
      }
      if (mounted) {
        setState(() {
          if (isActiveSubmission && _submittingSessionId == targetSessionId) {
            _submittingSessionId = null;
          }
        });
        if (processQueueAfterCompletion) {
          _processMessageQueueIfNeeded(sessionController);
        }
      } else if (isActiveSubmission &&
          _submittingSessionId == targetSessionId) {
        _submittingSessionId = null;
      }
    }
  }

  void _replaceComposerText(String value) {
    _replaceComposerTextAndRefocus(value, requestFocusAfter: false);
  }

  /// 程序化改写 composer 文本的统一入口。
  ///
  /// 直接 `_composerController.value = ...` 会在 IME 正在组合（composing）
  /// 期间把陈旧的 selection 推给 framework 与平台 IME，下一次
  /// `TextInputClient.updateEditingState` 反向回调时可能带着越界 selection
  /// （典型日志：`Range start 293 is out of text of length 290`）触发
  /// `TextEditingValue.fromJSON` 断言。先把焦点摘掉、清掉平台 IME 的
  /// 组合态，再写入新值；如需恢复焦点再走 `requestFocusAfter`。
  void _replaceComposerTextAndRefocus(
    String value, {
    bool requestFocusAfter = true,
  }) {
    final wasFocused = _composerFocusNode.hasFocus;
    if (wasFocused) {
      _composerFocusNode.unfocus();
    }
    _composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    if (requestFocusAfter && wasFocused && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_composerCollapsed) {
          _composerFocusNode.requestFocus();
        }
      });
    }
  }

  /// 给 [InputRepairService] 注册的软恢复钩子：当 framework
  /// 在 `TextInputClient.updateEditingState` 里检测到平台 IME 选区越界
  /// 时，由 `FlutterError.onError` 触发本钩子，做一次"摘焦点 → 下一帧再
  /// focus"动作，把 IME 的陈旧 composing/selection 状态清掉，重新与
  /// controller 对齐。这里不用 `scheduleMicrotask`，避免与 overlay/
  /// follower 退场和 leader 清理落在同一帧，触发 Flutter layer 断言。
  void _runComposerImeSoftRecovery() {
    if (!mounted) return;
    final wasFocused = _composerFocusNode.hasFocus;
    if (wasFocused) {
      _composerFocusNode.unfocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (wasFocused && !_composerCollapsed) {
        _composerFocusNode.requestFocus();
      }
    });
  }

  AiAttachmentInputCapabilities _selectedModelAttachmentCapabilities(
    AiModelConfig? model,
  ) {
    return resolveAiAttachmentInputCapabilities(model);
  }

  bool _selectedModelSupportsAttachments(AiModelConfig? model) {
    return _selectedModelAttachmentCapabilities(model).supportsAny;
  }

  Future<void> _tryPasteAttachmentsFromClipboard() async {
    if (!mounted || _clipboardAttachmentPasteInProgress) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      context.read<AiSessionController>().currentSession,
    );
    final capabilities = _selectedModelAttachmentCapabilities(selectedModel);
    if (!capabilities.supportsAny) {
      return;
    }
    if (_pendingAttachments.length >= aiMessageAttachmentLimit) {
      _showAttachmentAppendNotices(
        const _AppendComposerAttachmentsResult(limitSkipped: 1),
      );
      return;
    }
    _clipboardAttachmentPasteInProgress = true;
    try {
      List<String> clipboardFiles = const <String>[];
      try {
        clipboardFiles = await getOpenHandClipboardFiles(
          timeout: _composerClipboardReadTimeout,
        );
      } catch (error, stack) {
        silentLog('openhand_home_page', '读取剪贴板文件', error, stack);
      }
      if (!mounted) {
        return;
      }
      if (clipboardFiles.isNotEmpty) {
        final result = await _appendComposerAttachmentPaths(
          clipboardFiles,
          capabilities: capabilities,
        );
        if (!mounted) {
          return;
        }
        _showAttachmentAppendNotices(result);
        return;
      }
      if (!capabilities.supportsImageInput) {
        return;
      }
      Uint8List? bytes;
      try {
        bytes = await getOpenHandClipboardImage(timeout: _composerClipboardReadTimeout);
      } catch (error, stack) {
        silentLog('openhand_home_page', '读取剪贴板图片', error, stack);
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        return;
      }
      if (bytes.lengthInBytes > aiMessageAttachmentMaxFileBytes) {
        _showAttachmentAppendNotices(
          const _AppendComposerAttachmentsResult(oversized: 1),
        );
        return;
      }
      String tempPath;
      try {
        final ts = DateTime.now().microsecondsSinceEpoch;
        final tempFile = await writeNewTemporaryFileBytesBounded(
          directoryPrefix: 'openhand_paste_',
          fileName: 'pasted_$ts.png',
          bytes: bytes,
          timeout: _composerAttachmentWriteTimeout,
          onSecondaryError: (error, stack) =>
              silentLog('openhand_home_page', '清理剪贴板图片临时文件', error, stack),
        );
        tempPath = p.normalize(p.absolute(tempFile.path));
        _ownedComposerTempPaths.add(tempPath);
      } catch (error, stack) {
        silentLog('openhand_home_page', '写入剪贴板临时文件', error, stack);
        return;
      }
      if (!mounted) {
        _releaseComposerTempPaths(<String>[tempPath]);
        return;
      }
      final result = await _appendComposerAttachmentPaths(<String>[
        tempPath,
      ], capabilities: capabilities);
      if (!mounted) {
        return;
      }
      _showAttachmentAppendNotices(result);
    } finally {
      _clipboardAttachmentPasteInProgress = false;
    }
  }

  Future<void> _pickComposerAttachments() async {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      context.read<AiSessionController>().currentSession,
    );
    if (selectedModel == null) {
      showOpenHandErrorSnack(context, l10n.aiModelSelectionRequired);
      return;
    }
    final capabilities = _selectedModelAttachmentCapabilities(selectedModel);
    if (!capabilities.supportsAny) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前模型不支持附件。',
          en: 'The selected model does not support attachments.',
        ),
      );
      return;
    }
    final extensions = aiAttachmentPickerExtensionsForCapabilities(
      capabilities,
    );
    if (extensions.isEmpty) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前模型没有可添加的附件类型。',
          en: 'The selected model has no supported attachment types.',
        ),
      );
      return;
    }
    final remainingSlots =
        aiMessageAttachmentLimit - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '单条消息最多携带 20 个附件。',
          en: 'A single message supports at most 20 attachments.',
        ),
      );
      return;
    }
    final pickedFiles = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: 'Attachments', extensions: extensions),
      ],
    );
    if (!mounted || pickedFiles.isEmpty) {
      return;
    }
    final result = await _appendComposerAttachmentPaths(
      pickedFiles.map((file) => file.path),
      capabilities: capabilities,
    );
    if (!mounted) {
      return;
    }
    _showAttachmentAppendNotices(result);
  }

  Future<_AppendComposerAttachmentsResult> _appendComposerAttachmentPaths(
    Iterable<String> rawPaths, {
    required AiAttachmentInputCapabilities capabilities,
  }) async {
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
    var unsupportedCount = 0;
    var unreadableCount = 0;
    var limitSkippedCount = 0;
    for (final rawPath in rawPaths) {
      final path = rawPath.trim();
      if (path.isEmpty) {
        continue;
      }
      if (existingPaths.contains(path)) {
        continue;
      }
      if (nextAttachments.length >= aiMessageAttachmentLimit) {
        limitSkippedCount += 1;
        _releaseComposerTempPaths(<String>[path]);
        continue;
      }
      final kind = aiAttachmentKindForPath(path);
      if (!capabilities.supportsPath(path)) {
        unsupportedCount += 1;
        _releaseComposerTempPaths(<String>[path]);
        continue;
      }
      var resolvedPath = path;
      if (kind == AiAttachmentKind.image) {
        try {
          final bytes = await readBoundedFileBytes(
            File(path),
            maxBytes: aiMessageAttachmentMaxFileBytes,
            idleTimeout: _composerAttachmentReadIdleTimeout,
            totalTimeout: _composerAttachmentReadTotalTimeout,
          );
          if (!mounted) {
            _releaseComposerTempPaths(<String>[path]);
            return const _AppendComposerAttachmentsResult();
          }
          final editorResult = await showImageEditorDialog(
            context,
            imageBytes: bytes,
            imageSizeLimitBytes: imageSizeLimitBytes,
          );
          if (!mounted) {
            _releaseComposerTempPaths(<String>[path]);
            return const _AppendComposerAttachmentsResult();
          }
          if (editorResult == null) {
            _releaseComposerTempPaths(<String>[path]);
            continue;
          }
          final ext = editorResult.format;
          final basename = p.basenameWithoutExtension(path).trim().isEmpty
              ? 'image'
              : p.basenameWithoutExtension(path).trim();
          final tempFile = await writeNewTemporaryFileBytesBounded(
            directoryPrefix: 'openhand_edit_',
            fileName: '$basename.$ext',
            bytes: editorResult.bytes,
            timeout: _composerAttachmentWriteTimeout,
            onSecondaryError: (error, stack) =>
                silentLog('openhand_home_page', '清理编辑图片临时文件', error, stack),
          );
          resolvedPath = p.normalize(p.absolute(tempFile.path));
          _ownedComposerTempPaths.add(resolvedPath);
          _releaseComposerTempPaths(<String>[path]);
        } on BoundedFileReadException catch (error, stack) {
          silentLog('openhand_home_page', '有界读取图片附件', error, stack);
          if (error.failure == BoundedFileReadFailure.tooLarge) {
            oversizedCount += 1;
          } else {
            unreadableCount += 1;
          }
          _releaseComposerTempPaths(<String>[path]);
          continue;
        } on FileSystemException catch (error, stack) {
          silentLog('openhand_home_page', '读取图片附件文件', error, stack);
          unreadableCount += 1;
          _releaseComposerTempPaths(<String>[path]);
          continue;
        } on TimeoutException catch (error, stack) {
          silentLog('openhand_home_page', '读取图片附件超时', error, stack);
          unreadableCount += 1;
          _releaseComposerTempPaths(<String>[path]);
          continue;
        } catch (error, stack) {
          silentLog('openhand_home_page', '编辑图片附件', error, stack);
          resolvedPath = path;
        }
      }
      if (existingPaths.contains(resolvedPath)) {
        _releaseComposerTempPaths(<String>[resolvedPath]);
        continue;
      }
      try {
        final draft = await _ComposerAttachmentDraft.fromPath(resolvedPath);
        if (draft.sizeBytes < 0 ||
            draft.sizeBytes > aiMessageAttachmentMaxFileBytes) {
          oversizedCount += 1;
          _releaseComposerTempPaths(<String>[resolvedPath]);
          continue;
        }
        nextAttachments.add(draft);
      } catch (error, stack) {
        silentLog('openhand_home_page', '创建附件草稿', error, stack);
        unreadableCount += 1;
        _releaseComposerTempPaths(<String>[resolvedPath]);
        continue;
      }
      existingPaths.add(resolvedPath);
      addedCount += 1;
    }
    if (!mounted) {
      _releaseComposerTempPaths(nextAttachments.map((item) => item.filePath));
    } else if (addedCount > 0) {
      setState(() {
        _pendingAttachments = nextAttachments;
        _composerCollapsed = false;
      });
    }
    return _AppendComposerAttachmentsResult(
      added: addedCount,
      oversized: oversizedCount,
      unsupported: unsupportedCount,
      unreadable: unreadableCount,
      limitSkipped: limitSkippedCount,
    );
  }

  void _showAttachmentAppendNotices(_AppendComposerAttachmentsResult result) {
    if (!mounted || !result.hasNotices) {
      return;
    }
    final lines = <String>[];
    if (result.limitSkipped > 0) {
      lines.add(
        openHandLocalizedText(
          context,
          zh: '单条消息最多携带 20 个附件。',
          en: 'A single message supports at most 20 attachments.',
        ),
      );
    }
    if (result.unsupported > 0) {
      lines.add(
        openHandLocalizedText(
          context,
          zh: '已忽略 ${result.unsupported} 个当前模型不支持的附件类型。',
          en: 'Ignored ${result.unsupported} unsupported attachment type(s) for the selected model.',
        ),
      );
    }
    if (result.oversized > 0) {
      lines.add(
        openHandLocalizedText(
          context,
          zh: '已忽略 ${result.oversized} 个超出 10MB 单文件上限的附件。',
          en: 'Ignored ${result.oversized} file(s) exceeding the 10MB per-attachment limit.',
        ),
      );
    }
    if (result.unreadable > 0) {
      lines.add(
        openHandLocalizedText(
          context,
          zh: '已忽略 ${result.unreadable} 个无法读取的附件。',
          en: 'Ignored ${result.unreadable} unreadable attachment(s).',
        ),
      );
    }
    if (lines.isNotEmpty) {
      showOpenHandInfoSnack(context, lines.join('\n'), maxLines: 3);
    }
  }

  bool _composerTempPathIsReferenced(String path) {
    bool matches(_ComposerAttachmentDraft item) =>
        p.equals(p.normalize(p.absolute(item.filePath)), path);
    if (_pendingAttachments.any(matches)) return true;
    if (_composerDraftsBySessionId.values.any(
      (draft) => draft.attachments.any(matches),
    )) {
      return true;
    }
    return _queuedMessagesBySessionId.values.any(
      (queue) => queue.any((message) => message.attachments.any(matches)),
    );
  }

  void _releaseComposerTempPaths(Iterable<String> paths) {
    final tempRoot = p.absolute(Directory.systemTemp.path);
    for (final rawPath in paths) {
      final path = p.normalize(p.absolute(rawPath));
      if (!_ownedComposerTempPaths.contains(path) ||
          _composerTempPathIsReferenced(path)) {
        continue;
      }
      _ownedComposerTempPaths.remove(path);
      unawaited(() async {
        try {
          await deletePathBounded(
            p.absolute(File(path).parent.path),
            policy: _composerTempDeletePolicy,
            allowedRoot: tempRoot,
          );
        } catch (error, stack) {
          silentLog('openhand_home_page', '清理输入框临时附件', error, stack);
        }
      }());
    }
  }

  void _removePendingAttachment(String filePath) {
    final removed = _pendingAttachments
        .where((item) => item.filePath == filePath)
        .toList(growable: false);
    setState(() {
      _pendingAttachments = _pendingAttachments
          .where((item) => item.filePath != filePath)
          .toList(growable: false);
    });
    _storeComposerDraftForSession(_activeComposerSessionId);
    _releaseComposerTempPaths(removed.map((item) => item.filePath));
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
    required AiCreationRequest creationRequest,
  }) {
    _storeComposerDraftForSession(
      sessionId,
      text: prompt,
      attachments: attachments,
      creationRequest: creationRequest,
    );
    if (sessionController.currentSessionId != sessionId) {
      return;
    }
    _replaceComposerText(prompt);
    final creationState = _composerCreationStateFromRequest(creationRequest);
    setState(() {
      _pendingAttachments = List<_ComposerAttachmentDraft>.from(attachments);
      _creationMode = creationState.mode;
      _creationOptions = creationState.options;
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
    final sessionId =
        sessionController.currentSessionId ?? _submittingSessionId;
    if (sessionId == null) {
      return;
    }
    final activeSubmissionSerial =
        _activeSubmissionSerialsBySessionId[sessionId];
    if (_submittingSessionId == sessionId || activeSubmissionSerial != null) {
      if (activeSubmissionSerial != null) {
        _locallyStoppedSubmissionSerialsBySessionId[sessionId] =
            activeSubmissionSerial;
      } else {
        _locallyStoppedPendingSubmissionSessionIds.add(sessionId);
      }
      if (mounted) {
        setState(() {
          if (_submittingSessionId == sessionId) {
            _submittingSessionId = null;
          }
        });
      } else {
        _submittingSessionId = null;
      }
    }
    _stopReverseRuntimeForSession(sessionId);
    unawaited(
      sessionController.stopResponding(sessionId).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        silentLog('openhand_home_page', '停止响应', error, stackTrace);
      }),
    );
  }

  Future<void> _pauseCurrentGoal() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) return;
    final ok = await sessionController.pauseGoal(sessionId);
    if (!mounted || ok) return;
    showFriendlyErrorSnackBar(
      context,
      message: sessionController.lastErrorMessageForSession(sessionId),
      fallback: AppLocalizations.of(context)!.chatRequestFailed,
    );
  }

  Future<void> _terminateCurrentGoal() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) return;
    final ok = await sessionController.terminateGoal(sessionId);
    if (!mounted || ok) return;
    showFriendlyErrorSnackBar(
      context,
      message: sessionController.lastErrorMessageForSession(sessionId),
      fallback: AppLocalizations.of(context)!.chatRequestFailed,
    );
  }

  Future<void> _resumeCurrentGoal() async {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final currentSession = sessionController.currentSession;
    if (currentSession == null) return;
    final selectedModel = _effectiveModelForSession(
      settingsController,
      currentSession,
    );
    if (selectedModel == null) {
      showOpenHandErrorSnack(
        context,
        AppLocalizations.of(context)!.aiModelSelectionRequired,
      );
      return;
    }
    final runtimeContext = await _buildRuntimeContext(
      workingDirectory: _programmingExpertProjectRoot(currentSession),
      skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
    );
    if (!mounted) return;
    final requireWriteConfirmation =
        AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
          templateId: currentSession.templateId,
          fullAccessPermission: currentSession.fullAccessPermission,
          globalConfirmationEnabled:
              settingsController.aiWriteCommandConfirmationEnabled,
        );
    final ok = await sessionController.resumeGoal(
      sessionId: currentSession.id,
      model: selectedModel,
      runtimeContext: runtimeContext,
      denyCommandRules: settingsController.aiDenyCommandRules,
      requireWriteCommandConfirmation: requireWriteConfirmation,
      confirmWriteCommand: (request) =>
          _confirmWriteCommand(request, sessionId: currentSession.id),
    );
    if (!mounted || ok) return;
    showFriendlyErrorSnackBar(
      context,
      message: sessionController.lastErrorMessageForSession(currentSession.id),
      fallback: AppLocalizations.of(context)!.chatRequestFailed,
    );
  }

  void _stopReverseRuntimeForSession(String sessionId) {
    final webReverseController = _webReverseControllers[sessionId];
    if (webReverseController != null) {
      _webReverseCdpMcpBridge.stopSession(sessionId);
      _stopReverseRuntimeController(
        sessionId: sessionId,
        operation: '停止 Web 逆向运行时',
        stop: webReverseController.stopBrowser,
        isActive: () => webReverseController.hasManagedBrowserProcess,
      );
    }
    final androidReverseController = _androidReverseControllers[sessionId];
    if (androidReverseController != null) {
      _stopReverseRuntimeController(
        sessionId: sessionId,
        operation: '停止 Android 逆向运行时',
        stop: androidReverseController.stop,
        isActive: () => androidReverseController.isRunning,
      );
    }
  }

  void _stopReverseRuntimeController({
    required String sessionId,
    required String operation,
    required Future<void> Function() stop,
    required bool Function() isActive,
  }) {
    if (_reverseRuntimeStopTasks.containsKey(sessionId)) return;
    late final Future<void> task;
    task =
        (() async {
          _beginReverseRuntimeOperation(sessionId);
          try {
            await stop();
          } catch (error, stack) {
            silentLog('openhand_home_page', operation, error, stack);
          } finally {
            _finishReverseRuntimeOperation(sessionId);
            _releaseInactiveReverseRuntimeSlot(sessionId, active: isActive());
            _trimRetainedWebReverseControllers();
            _trimRetainedAndroidReverseControllers();
          }
        })().whenComplete(() {
          if (identical(_reverseRuntimeStopTasks[sessionId], task)) {
            _reverseRuntimeStopTasks.remove(sessionId);
          }
        });
    _reverseRuntimeStopTasks[sessionId] = task;
    unawaited(task);
  }

  void _scheduleScrollToBottom({
    bool force = false,
    bool animated = false,
    bool allowSettlePasses = true,
  }) {
    if (!_autoFollowEnabled) {
      _clearPendingAutoFollowState();
      return;
    }
    if (!force &&
        (!_autoFollowEnabled ||
            !_shouldAutoFollowMessages ||
            _shouldDeferAutoFollowScheduling())) {
      return;
    }
    if (force) {
      _shouldAutoFollowMessages = true;
      _queuedForcedScrollToBottom = true;
    }
    if (allowSettlePasses) {
      _scrollToBottomSettleFramesRemaining = math.max(
        _scrollToBottomSettleFramesRemaining,
        _scrollToBottomSettleFrameLimit,
      );
      _scrollToBottomStableFrames = 0;
    }
    _pendingAnimatedScrollToBottom = _pendingAnimatedScrollToBottom || animated;
    if (_isProgrammaticMessageScrollCommandBusy()) {
      return;
    }
    if (_isUserMessageScrollActivityActive()) {
      return;
    }
    if (_scrollToBottomAwaitingPosition) {
      return;
    }
    if (_scrollToBottomCallbackQueued) {
      return;
    }
    final scheduledSessionId = context
        .read<AiSessionController>()
        .currentSessionId;
    _scrollToBottomCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomCallbackQueued = false;
      if (!mounted) {
        _queuedForcedScrollToBottom = false;
        _pendingAnimatedScrollToBottom = false;
        return;
      }
      if (context.read<AiSessionController>().currentSessionId !=
          scheduledSessionId) {
        return;
      }
      if (_hasActiveOrRecentMessageScrollActivity()) {
        return;
      }
      final shouldForce = _queuedForcedScrollToBottom;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      if (!_autoFollowEnabled) {
        _clearPendingAutoFollowState();
        return;
      }
      if (!shouldForce &&
          (!_autoFollowEnabled ||
              !_shouldAutoFollowMessages ||
              _shouldDeferAutoFollowScheduling())) {
        _pendingAnimatedScrollToBottom = false;
        return;
      }
      // 跨会话 AnimatedSwitcher cross-fade 期间，新旧两个 _SessionTranscript
      // 子树可能同时持有 _messageScrollController 的 ScrollPosition，导致
      // controller.positions.length > 1。此时 jumpTo/animateTo 会触发
      // Scrollbar 的 _debugCheckHasValidScrollPosition 断言。跳过本次滚动，
      // 等 transition 完成后旧 position 自然 detach，后续帧会重新 follow。
      final positions = _messageScrollController.positions.toList(
        growable: false,
      );
      if (positions.length != 1) {
        if (_scrollToBottomPositionRetryCounter >=
            _scrollToBottomPositionRetryLimit) {
          _scrollToBottomPositionRetryCounter = 0;
          _queuedForcedScrollToBottom = false;
          _pendingAnimatedScrollToBottom = false;
          return;
        }
        _scrollToBottomAwaitingPosition = true;
        _scrollToBottomPositionRetryCounter += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _scrollToBottomAwaitingPosition = false;
          if (context.read<AiSessionController>().currentSessionId !=
              scheduledSessionId) {
            return;
          }
          if (_hasActiveOrRecentMessageScrollActivity()) {
            return;
          }
          _scheduleScrollToBottom(
            force: shouldForce,
            animated: shouldAnimate,
            allowSettlePasses: allowSettlePasses,
          );
        });
        return;
      }
      _scrollToBottomPositionRetryCounter = 0;
      _queuedForcedScrollToBottom = false;
      _pendingAnimatedScrollToBottom = false;
      final activePosition = positions.single;
      final targetOffset = activePosition.maxScrollExtent
          .clamp(activePosition.minScrollExtent, activePosition.maxScrollExtent)
          .toDouble();
      final distance = (targetOffset - activePosition.pixels).abs();
      void clearProgrammaticScrollFlag() {
        _endProgrammaticMessageScroll();
      }

      void scheduleSettlePass() {
        if (allowSettlePasses) {
          _queueScrollToBottomSettlePass();
        }
      }

      if (distance >= 1) {
        _beginProgrammaticMessageScroll();
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

  void _queueScrollToBottomSettlePass() {
    if (_scrollToBottomSettleQueued ||
        _scrollToBottomSettleFramesRemaining <= 0) {
      return;
    }
    _scrollToBottomSettleQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomSettleQueued = false;
      if (!mounted) {
        _scrollToBottomSettleFramesRemaining = 0;
        _scrollToBottomStableFrames = 0;
        return;
      }
      if (!_autoFollowEnabled ||
          !_shouldAutoFollowMessages ||
          _shouldDeferAutoFollowScheduling()) {
        _scrollToBottomSettleFramesRemaining = 0;
        _scrollToBottomStableFrames = 0;
        return;
      }
      final positions = _messageScrollController.positions.toList(
        growable: false,
      );
      if (positions.length != 1) {
        _scrollToBottomSettleFramesRemaining = math.max(
          0,
          _scrollToBottomSettleFramesRemaining - 1,
        );
        _queueScrollToBottomSettlePass();
        return;
      }
      final position = positions.single;
      if (_hasActiveOrRecentMessageScrollActivity()) {
        _scrollToBottomSettleFramesRemaining = 0;
        _scrollToBottomStableFrames = 0;
        return;
      }
      final targetOffset = position.maxScrollExtent
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      final distance = (targetOffset - position.pixels).abs();
      _scrollToBottomSettleFramesRemaining = math.max(
        0,
        _scrollToBottomSettleFramesRemaining - 1,
      );
      if (distance > _scrollToBottomSettleTolerance) {
        _scrollToBottomStableFrames = 0;
        _beginProgrammaticMessageScroll();
        position.jumpTo(targetOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _endProgrammaticMessageScroll();
          _queueScrollToBottomSettlePass();
        });
        return;
      }
      _scrollToBottomStableFrames += 1;
      if (_scrollToBottomSettleFramesRemaining > 0 &&
          _scrollToBottomStableFrames < _scrollToBottomSettleStableFrameLimit) {
        _queueScrollToBottomSettlePass();
        return;
      }
      _scrollToBottomSettleFramesRemaining = 0;
      _scrollToBottomStableFrames = 0;
    });
  }

  void _cancelProgrammaticAutoFollowScroll({double? keepPixels}) {
    _messageProgrammaticScrollWindow.cancel();
    _scrollToBottomSettleFramesRemaining = 0;
    _scrollToBottomStableFrames = 0;
  }

  void _maybeAutoFollowSession(AiSession? session) {
    final nextSignature = _sessionAutoScrollSignature(session);
    if (_lastAutoScrollSignature == nextSignature) {
      return;
    }
    final previousSignature = _lastAutoScrollSignature;
    _lastAutoScrollSignature = nextSignature;
    if (nextSignature == null) {
      return;
    }
    // 仅当用户当前仍处于"贴底跟随"状态时，才在新消息
    // 到达时重新装填强制滚到底的请求。如果用户已经手动上滑导致
    // `_shouldAutoFollowMessages` 被置为 false（自动跟随暂停），
    // 那么本次 session 变更不应越权把视口拉回底部 —— 必须等用户
    // 主动滚回底部之后才恢复自动跟随。原先无脑调用 `_armAutoFollowToBottom`
    // 会把 `_shouldAutoFollowMessages` 又置为 true，并带上
    // `_pendingForcedScrollToBottom`，导致暂停状态在下一条新消息到来时
    // 被悄悄取消、强行把用户拉回底部。
    if (_autoFollowEnabled && _shouldAutoFollowMessages) {
      _armAutoFollowToBottom(notifyPausedState: false);
    }
    // 会话切换时把贴底请求交给新 transcript；同会话追加仍由父级跟随。
    final sessionIdChanged =
        previousSignature == null ||
        !previousSignature.startsWith('${session!.id}|');
    if (sessionIdChanged) {
      _lastMessageDistanceToBottom = null;
      // 新 transcript 会在不可见状态完成物化与贴底。首帧后只消费父级请求，
      // 避免两套 settle 同时改写共享 ScrollController。
      final selectedSessionId = session!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            context.read<AiSessionController>().currentSessionId !=
                selectedSessionId) {
          return;
        }
        _pendingForcedScrollToBottom = false;
        _queuedForcedScrollToBottom = false;
        _pendingAnimatedScrollToBottom = false;
        _scrollToBottomSettleFramesRemaining = 0;
        _scrollToBottomStableFrames = 0;
      });
    } else {
      _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
    }
  }

  void _handleComposerLayoutChanged() {
    // SizeChangedLayoutNotification 在 layout 阶段同步派发，此时读取
    // `RenderBox.size` 会触发 `sizeAccessAllowed` 断言；而我们也想在补偿
    // scrollOffset 时避开 layout 临界期。统一推迟到下一帧再处理 —— 既能拿到
    // 稳定的 composer 高度，也避免 jumpTo 与正在进行的 layout 互相打架。
    if (_composerLayoutMeasureScheduled) {
      return;
    }
    _composerLayoutMeasureScheduled = true;
    // 使用 addPostFrameCallback 而非 endOfFrame：确保在下一帧 layout 完成后
    // 再测量和补偿，此时 transcript 的 maxScrollExtent 已经更新到位，
    // 避免 clamp 到过时的范围导致消息列表不跟随。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerLayoutMeasureScheduled = false;
      if (!mounted) return;
      _measureComposerAndMaybeFollow();
    });
  }

  void _scheduleComposerTransitionMeasurements() {
    final reduceMotion = openHandReduceMotionOf(context);
    _composerTransitionMeasurePassesRemaining = math.max(
      _composerTransitionMeasurePassesRemaining,
      reduceMotion ? 2 : 24,
    );
    _queueComposerTransitionMeasurePass();
  }

  void _queueComposerTransitionMeasurePass() {
    if (_composerTransitionMeasureQueued ||
        _composerTransitionMeasurePassesRemaining <= 0) {
      return;
    }
    _composerTransitionMeasureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composerTransitionMeasureQueued = false;
      if (!mounted || _composerTransitionMeasurePassesRemaining <= 0) {
        return;
      }
      _composerTransitionMeasurePassesRemaining -= 1;
      _measureComposerAndMaybeFollow();
      _queueComposerTransitionMeasurePass();
    });
  }

  void _measureComposerAndMaybeFollow() {
    final compensation = _measureComposerHeightAndCompensate();
    if (_shouldDeferAutoFollowScheduling()) {
      return;
    }
    _scheduleAutoFollowIfNeeded(
      animated: compensation.grew && !compensation.compensated,
      allowSettlePasses: false,
    );
  }

  ({bool compensated, bool grew}) _measureComposerHeightAndCompensate() {
    // 折叠/展开期间稳住消息：用 composer panel size delta 反向补偿 transcript
    // scrollOffset，让上方消息无论用户是否在底部，都被 Q 弹自然地"压下来 /
    // 顶上去"，与 AnimatedSize 节奏（260ms easeInOutCubicEmphasized）严丝合缝。
    final composerCtx = _composerPanelState?.context;
    final renderObject = composerCtx?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return (compensated: false, grew: false);
    }
    final newHeight = renderObject.size.height;
    final prev = _lastComposerHeight;
    _lastComposerHeight = newHeight;
    if (prev == null) return (compensated: false, grew: false);
    final delta = newHeight - prev;
    if (delta.abs() <= 0.5) {
      return (compensated: false, grew: false);
    }
    final grew = delta > 0;
    // correctBy 虽不会派发滚动通知，但依然会改写 pixels。用户正在慢速
    // 滚轮/trackpad 读历史，或已暂停自动跟随时，只刷新高度基线，不改写
    // ScrollPosition，避免下一次恢复时用陈旧 prev 算出一记大幅反向拉扯。
    if (_hasActiveOrRecentMessageScrollActivity() ||
        !_shouldAutoFollowMessages) {
      return (compensated: false, grew: grew);
    }
    final position = _activeMessageScrollPosition();
    if (position == null) {
      return (compensated: false, grew: grew);
    }
    // 反向偏移 scroll position：composer 长高 → pixels +delta，让"上方"内容
    // 视觉上往上挪同等距离 = 像是被新出现的 composer 顶上去；反之 composer
    // 收起 → 内容自然滑下来填补空间。correctBy 不做 clamp，由下一帧
    // _maybeAutoFollowSession / ballistic settle 兜底；越界量在动画下一帧
    // 自动回拉，体感上是 Q 弹自然的回弹而非硬截断。
    _composerScrollCompensationInProgress = true;
    position.correctBy(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _composerScrollCompensationInProgress = false;
      }
    });
    return (compensated: true, grew: grew);
  }

  void _handleTranscriptLayoutChanged() {
    if (_shouldDeferAutoFollowScheduling()) {
      return;
    }
    if (_transcriptLayoutAutoFollowQueued) {
      return;
    }
    _transcriptLayoutAutoFollowQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transcriptLayoutAutoFollowQueued = false;
      if (!mounted || _shouldDeferAutoFollowScheduling()) {
        return;
      }
      // 自动跟随开启且未被用户暂停时，布局增长也要钉到底部；否则流式
      // reasoning 上方继续增高时，底部 pending tool-call 卡片会掉出视口。
      if (!_autoFollowEnabled || !_shouldAutoFollowMessages) return;
      final position = _activeMessageScrollPosition();
      if (position == null) return;
      // 避免真实用户滚动期间 jumpTo 与弹道位置对抗产生弹跳；程序化追底
      // 的 settle 窗口不再阻塞这里，否则高速流式增高会追丢底部。
      if (_hasActiveOrRecentMessageScrollActivity()) {
        return;
      }
      _scheduleScrollToBottom();
    });
  }

  bool _messageDrivesAutoFollow(AiSessionMessage message) {
    if (boolFromValue(message.metadata[aiSessionMessageMetadataStreamingKey])) {
      return true;
    }
    final kind = message.kind;
    if (kind != AiSessionMessageKind.toolCall &&
        kind != AiSessionMessageKind.hook) {
      return false;
    }
    if (boolFromValue(message.metadata['tool_arguments_streaming']) ||
        boolFromValue(message.metadata['tool_preparing'])) {
      return true;
    }
    final status = _toolExecutionStatus(message);
    final hasOutput =
        _toolExecutionStdout(message).isNotEmpty ||
        _toolExecutionStderr(message).isNotEmpty ||
        _toolExecutionResult(message).isNotEmpty ||
        '${message.metadata['result_text'] ?? ''}'.trim().isNotEmpty;
    return status.isEmpty && !hasOutput;
  }

  String _messageAutoFollowRenderSignature(AiSessionMessage message) {
    return [
      message.id,
      message.kind.storageValue,
      message.characterCount,
      '${boolFromValue(message.metadata[aiSessionMessageMetadataStreamingKey])}',
      '${boolFromValue(message.metadata['tool_arguments_streaming'])}',
      '${boolFromValue(message.metadata['tool_preparing'])}',
      compactTextSignature(message.metadata['tool_arguments']),
      compactTextSignature(message.metadata['tool_execution_command']),
      _toolExecutionStatus(message),
      '${_toolExecutionStdout(message).length}',
      '${_toolExecutionStderr(message).length}',
      '${_toolExecutionResult(message).length}',
      compactTextSignature(message.metadata['result_text']),
    ].join(':');
  }

  void _handleRevealOlderMessages() {
    _shouldAutoFollowMessages = false;
    _clearPendingAutoFollowState();
    _syncAutoFollowPausedState();
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
    final activeFollowParts = <String>[];
    // 回溯硬上限：驱动自动跟随的消息（流式 / 运行中工具）只可能出现在
    // 当前回合尾部。历史消息几乎都不满足条件，不设上限时每次 rebuild
    // 都会把整个已加载列表从尾扫到头，大会话下这是 build 路径上最大的
    // 一笔 O(N) 常数税。
    final scanFloor = math.max(0, displayMessages.length - 32);
    for (
      var index = displayMessages.length - 1;
      index >= scanFloor && activeFollowParts.length < 4;
      index -= 1
    ) {
      final message = displayMessages[index];
      if (!_messageDrivesAutoFollow(message)) continue;
      activeFollowParts.add(
        'active:$index:${_messageAutoFollowRenderSignature(message)}',
      );
    }
    return [
      currentSession.id,
      displayMessages.length,
      lastMessage.id,
      lastMessage.kind.storageValue,
      lastMessage.characterCount,
      _messageAutoFollowRenderSignature(lastMessage),
      _toolExecutionStatus(lastMessage),
      '${_toolExecutionStdout(lastMessage).length}',
      '${_toolExecutionStderr(lastMessage).length}',
      '${_toolExecutionResult(lastMessage).length}',
      ...activeFollowParts,
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

  Future<BashCommandApprovalDecision> _confirmWriteCommand(
    BashCommandApprovalRequest request, {
    String? sessionId,
    bool trackSessionBadge = true,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final forceAndroidReverseApproval =
        _androidReverseCommandRequiresExplicitApproval(
          sessionController: sessionController,
          sessionId: sessionId,
          command: request.command,
        );
    final settingsController = context.read<SettingsController>();
    if (!forceAndroidReverseApproval) {
      for (final rule in settingsController.aiAllowCommandRules) {
        if (rule.matches(request.command)) {
          return BashCommandApprovalDecision.approved;
        }
      }
    }
    // Use the explicitly provided sessionId so the correct session badge
    // is updated even when the user has navigated to a different session.
    final effectiveSessionId = trackSessionBadge
        ? (sessionId ?? sessionController.currentSessionId)
        : null;
    final gatewayController =
        _observedMessageGatewayController ?? _readMessageGatewayController();
    if (effectiveSessionId != null && gatewayController != null) {
      return gatewayController.requestWriteApproval(
        sessionId: effectiveSessionId,
        request: request,
      );
    }
    if (effectiveSessionId != null) {
      sessionController.setSessionAwaitingApproval(effectiveSessionId);
    }
    try {
      final decision = await showWriteCommandConfirmationDialog(
        context,
        request: request,
      );
      // null 仅来自 Session 外部关闭或 Route 树销毁，统一视为 dismissed。
      return decision ?? BashCommandApprovalDecision.dismissed;
    } finally {
      if (effectiveSessionId != null) {
        sessionController.clearSessionAwaitingApproval(effectiveSessionId);
      }
    }
  }

  bool _androidReverseCommandRequiresExplicitApproval({
    required AiSessionController sessionController,
    required String? sessionId,
    required String command,
  }) {
    final effectiveSessionId = (sessionId ?? sessionController.currentSessionId)
        ?.trim();
    if (effectiveSessionId == null || effectiveSessionId.isEmpty) {
      return false;
    }
    final session = sessionController.sessions.cast<AiSession?>().firstWhere(
      (item) => item?.id == effectiveSessionId,
      orElse: () => null,
    );
    if (session?.templateId != AndroidReverseAdbCommandGuard.templateId) {
      return false;
    }
    return AndroidReverseAdbCommandGuard.isGlobalAdbRecoveryCommand(command);
  }

  Future<BashCommandApprovalDecision> _confirmHarnessApiWriteCommand(
    BashCommandApprovalRequest request,
  ) {
    return _confirmWriteCommand(request, trackSessionBadge: false);
  }

  Future<void> _handleSlashCommand(OpenHandSlashCommand command) async {
    switch (command.kind) {
      case OpenHandSlashCommandKind.help:
        _selectSection(AppSection.settings);
        await _showSlashHelpDialog();
        return;
      case OpenHandSlashCommandKind.feedback:
        _selectSection(AppSection.settings);
        await _showFeedbackDialog(command.argument);
        return;
      case OpenHandSlashCommandKind.newSession:
        await _createSessionFromDialog();
        return;
      case OpenHandSlashCommandKind.status:
        final session = context.read<AiSessionController>().currentSession;
        if (session == null) {
          showOpenHandInfoSnack(
            context,
            openHandLocalizedText(
              context,
              zh: '当前没有活动会话。',
              en: 'There is no active session.',
            ),
          );
          return;
        }
        await _showSessionMetadataDialog(
          context,
          session,
          activeProfile: () {
            final selected = _effectiveModelForSession(
              context.read<SettingsController>(),
              session,
            );
            return selected?.modelProfiles[selected.modelId];
          }(),
          claudeStyle:
              _effectiveModelForSession(
                context.read<SettingsController>(),
                session,
              )?.protocolType ==
              AiProtocolType.claude,
        );
        return;
      case OpenHandSlashCommandKind.stop:
        final sessionController = context.read<AiSessionController>();
        final currentSessionId = sessionController.currentSessionId;
        final hasActiveResponse =
            currentSessionId != null &&
            _canStopCurrentSessionResponse(sessionController);
        if (!hasActiveResponse) {
          showOpenHandInfoSnack(
            context,
            openHandLocalizedText(
              context,
              zh: '当前没有正在进行的响应。',
              en: 'There is no active response to stop.',
            ),
          );
          return;
        }
        await _stopResponding();
        if (mounted) {
          showOpenHandInfoSnack(
            context,
            openHandLocalizedText(
              context,
              zh: '已请求当前会话停止继续响应。',
              en: 'Requested the current session to stop responding.',
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
      case OpenHandSlashCommandKind.skills:
        _activateSlashCommandSection(AppSection.skills);
        return;
      case OpenHandSlashCommandKind.memory:
        _activateSlashCommandSection(AppSection.memory);
        return;
      case OpenHandSlashCommandKind.mcp:
        _activateSlashCommandSection(AppSection.mcp);
        return;
      case OpenHandSlashCommandKind.agents:
        _activateSlashCommandSection(AppSection.agents);
        return;
      case OpenHandSlashCommandKind.crons:
        _activateSlashCommandSection(AppSection.crons);
        return;
    }
  }

  void _activateSlashCommandSection(AppSection section) {
    _selectSection(section);
    final label = switch (section) {
      AppSection.workspace => openHandWorkspaceLabel(context),
      AppSection.skills => openHandLocalizedText(
        context,
        zh: '技能',
        en: 'Skills',
      ),
      AppSection.memory => openHandMemoryLabel(context),
      AppSection.mcp => openHandLocalizedText(context, zh: 'MCP', en: 'MCP'),
      AppSection.hooks => _homeHooksLabel(context),
      AppSection.crons => 'Crons',
      AppSection.instructions => openHandInstructionsLabel(context),
      AppSection.messageGateway => openHandLocalizedText(
        context,
        zh: '消息网关',
        en: 'Message Gateway',
      ),
      AppSection.pluginService => _homePluginsLabel(context),
      AppSection.knowledgeBase => openHandKnowledgeBaseLabel(context),
      AppSection.agents => _homeAgentsLabel(context),
      AppSection.services => AppLocalizations.of(context)!.servicesTitle,
      AppSection.settings => openHandLocalizedText(
        context,
        zh: '设置',
        en: 'Settings',
      ),
      AppSection.harnessSession => openHandLocalizedText(
        context,
        zh: 'Harness 会话',
        en: 'Harness Session',
      ),
    };
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已切换到 $label。',
        en: 'Switched to $label.',
      ),
    );
  }

  Future<void> _showSlashHelpDialog() {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final closeLabel = openHandCloseLabel(context);
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
      '/skills',
      '/memory',
      '/mcp',
      '/agents',
    ].join('\n');
    final detail = openHandLocalizedText(
      context,
      zh: '可用本地命令：\n$commandList\n\n`/help`、`/commands`、`/feedback`、`/new`、`/status`、`/stop` 不会发给模型，而是由 OpenHand 本地处理。\n\n写命令确认：${settingsController.aiWriteCommandConfirmationEnabled ? '开启' : '关闭'}\n允许命令规则：${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\n设置文件：${settingsController.displaySettingsFilePath}\n会话目录：${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
      en: 'Available local commands:\n$commandList\n\n`/help`, `/commands`, `/feedback`, `/new`, `/status`, and `/stop` are handled locally by OpenHand instead of being sent to the model.\n\nWrite command confirmation: ${settingsController.aiWriteCommandConfirmationEnabled ? 'enabled' : 'disabled'}\nAllow command rules: ${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\nSettings file: ${settingsController.displaySettingsFilePath}\nSession directory: ${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
    );
    return showOpenHandInfoDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: 'Slash Commands',
        en: 'Slash Commands',
      ),
      closeLabel: closeLabel,
      content: SelectableText(detail),
    );
  }

  Future<void> _showFeedbackDialog(String note) {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final closeLabel = openHandCloseLabel(context);
    final copiedLabel = openHandLocalizedText(
      context,
      zh: '反馈模板已复制。',
      en: 'Feedback template copied.',
    );
    final trimmedNote = note.trim();
    final feedbackTemplate = openHandLocalizedText(
      context,
      zh: 'OpenHand 反馈\n备注：${trimmedNote.isEmpty ? '请在这里补充问题描述。' : trimmedNote}\n设置文件：${settingsController.settingsFilePath}\n会话目录：${sessionController.sessionsDirectoryPath}',
      en: 'OpenHand Feedback\nNote: ${trimmedNote.isEmpty ? 'Add your issue details here.' : trimmedNote}\nSettings file: ${settingsController.settingsFilePath}\nSession directory: ${sessionController.sessionsDirectoryPath}',
    );
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) {
        return buildOpenHandAlertDialog(
          title: Text(
            openHandLocalizedText(context, zh: '反馈信息', en: 'Feedback Info'),
          ),
          content: SelectableText(
            openHandLocalizedText(
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
                final copied = await copyOpenHandTextToClipboard(
                  logTag: 'home',
                  context: context,
                  text: feedbackTemplate,
                  logAction: '复制反馈模板',
                  successMessage: copiedLabel,
                  showSuccess: false,
                );
                if (!copied || !mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                showOpenHandSuccessSnack(context, copiedLabel);
              },
              label: openHandLocalizedText(
                context,
                zh: '复制模板',
                en: 'Copy Template',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final submitted = await showOpenHandTextInputDialog(
      context: context,
      title: _homeRenameThreadLabel(context),
      initialValue: session.title,
      hintText: openHandLocalizedText(
        context,
        zh: '输入线程标题',
        en: 'Enter a thread title',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonSave,
    );
    if (!mounted || submitted == null || submitted.isEmpty) {
      return;
    }
    final renamed = await controller.renameSession(session.id, submitted);
    if (!mounted || renamed) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      controller.lastErrorMessage ??
          openHandLocalizedText(context, zh: '线程重命名失败。', en: 'Rename failed.'),
    );
  }

  void _generateTitleForSession(AiSession session) {
    unawaited(
      _generateTitleForSessionAsync(session).catchError((error, stack) {
        silentLog('openhand_home_page', '生成线程标题', error, stack);
      }),
    );
  }

  Future<void> _generateTitleForSessionAsync(AiSession session) async {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    AiSession sourceSession;
    try {
      final hydrated = await sessionController.ensureSessionMessagesHydrated(
        session.id,
      );
      if (!mounted) return;
      sourceSession =
          hydrated ?? sessionController.sessionById(session.id) ?? session;
    } catch (error) {
      if (!mounted) return;
      showFriendlyErrorDetailsDialog(
        context,
        title: _openhandHomePaTitleGenerationFailedLabel(context),
        fullText: openHandLocalizedText(
          context,
          zh: '现象：读取线程消息失败。\n原因：$error',
          en: 'Summary: Failed to load thread messages.\nReason: $error',
        ),
      );
      return;
    }
    if (sourceSession.hasPartialMessages) {
      final errorMessage =
          sessionController.lastErrorMessageForSession(session.id) ??
          sessionController.lastErrorMessage ??
          openHandLocalizedText(
            context,
            zh: '线程消息尚未完整加载，请稍后重试。',
            en: 'Thread messages are not fully loaded. Please try again later.',
          );
      showFriendlyErrorDetailsDialog(
        context,
        title: _openhandHomePaTitleGenerationFailedLabel(context),
        fullText: errorMessage,
      );
      return;
    }
    final userMessages = sourceSession.messages
        .where(
          (m) =>
              !m.isDeleted &&
              m.kind == AiSessionMessageKind.user &&
              m.content.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (userMessages.isEmpty) {
      await showOpenHandInfoDialog(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '无法生成标题',
          en: 'Unable to Generate Title',
        ),
        message: openHandLocalizedText(
          context,
          zh: '暂无用户消息可供总结。',
          en: 'No user messages to summarize.',
        ),
        closeLabel: AppLocalizations.of(context)!.commonClose,
      );
      return;
    }
    final model = AiTitleModelResolver.resolveDefault(
      models: settingsController.aiModels,
      currentModel: _effectiveModelForSession(
        settingsController,
        sourceSession,
      ),
    );
    _showTitleSummaryRangeDialog(
      session: sourceSession,
      userMessages: userMessages,
      model: model,
      sessionController: sessionController,
      settingsController: settingsController,
    );
  }

  Future<void> _showTitleSummaryRangeDialog({
    required AiSession session,
    required List<AiSessionMessage> userMessages,
    required AiModelConfig? model,
    required AiSessionController sessionController,
    required SettingsController settingsController,
  }) async {
    final result = await showAnimatedDialog<_TitleSummaryDialogResult>(
      context: context,
      builder: (dialogContext) => _TitleSummaryRangeDialog(
        userMessages: userMessages,
        availableModels: settingsController.aiModels,
        recentModelSelections: settingsController.recentModelSelections,
        initialModel: model,
      ),
    );
    if (!mounted || result == null) return;
    final startIdx = result.startIndex;
    final endIdx = result.endIndex;
    final selectedContent = userMessages
        .sublist(startIdx, endIdx + 1)
        .map((m) => m.content.trim())
        .join('\n\n');
    await _executeGenerateTitle(
      session: session,
      content: selectedContent,
      model: result.model,
      sessionController: sessionController,
      settingsController: settingsController,
    );
  }

  Future<void> _executeGenerateTitle({
    required AiSession session,
    required String content,
    required AiModelConfig? model,
    required AiSessionController sessionController,
    required SettingsController settingsController,
  }) async {
    final cancelCompleter = Completer<void>();
    var userCancelled = false;

    void cancelTitleGeneration() {
      userCancelled = true;
      if (!cancelCompleter.isCompleted) {
        cancelCompleter.complete();
      }
    }

    late final OpenHandDialogSession<bool> progressSession;
    Future<void> closeProgressDialog() async {
      await progressSession.dismiss(
        logTag: 'openhand_home_page',
        logAction: '生成标题：关闭进度对话框',
      );
    }

    progressSession = showTrackedAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      dismissOnEscape: false,
      builder: (_) => _TitleGenerationProgressDialog(
        onCancel: () {
          cancelTitleGeneration();
          unawaited(
            progressSession.dismiss(
              result: true,
              logTag: 'openhand_home_page',
              logAction: '生成标题：取消进度对话框',
            ),
          );
        },
      ),
    );
    unawaited(
      progressSession.result.then<void>((cancelled) {
        if (cancelled == true) {
          cancelTitleGeneration();
        }
      }, onError: (Object error, StackTrace stackTrace) {}),
    );

    try {
      await sessionController.generateTitleManually(
        sessionId: session.id,
        content: content,
        model: model,
        maxTitleCharacters: settingsController.aiGeneratedTitleMaxCharacters,
        cancelSignal: cancelCompleter.future,
      );
      if (!mounted || userCancelled) return;
      await closeProgressDialog();
      if (!mounted || userCancelled) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(context, zh: '标题生成成功', en: 'Title generated'),
      );
    } on AiChatCancelledException {
      cancelTitleGeneration();
    } catch (error) {
      if (!mounted || userCancelled) return;
      await closeProgressDialog();
      if (!mounted || userCancelled) return;
      showFriendlyErrorDetailsDialog(
        context,
        title: _openhandHomePaTitleGenerationFailedLabel(context),
        fullText: openHandLocalizedText(
          context,
          zh: '原因：$error',
          en: 'Reason: $error',
        ),
      );
    } finally {
      await closeProgressDialog();
    }
  }

  Future<void> _deleteSession(AiSession session) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(context, zh: '删除线程', en: 'Delete Thread'),
      message: session.title,
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteSession(session.id);
    if (!mounted || deleted) return;
    showOpenHandErrorSnack(
      context,
      controller.lastErrorMessage ??
          openHandLocalizedText(context, zh: '线程删除失败。', en: 'Delete failed.'),
    );
  }

  void _reportHarnessPersistenceError({
    required String operation,
    required Object error,
    required StackTrace stack,
    required String zhAction,
    required String enAction,
    bool postFrame = false,
  }) {
    silentLog('openhand_home_page', operation, error, stack);
    if (!mounted) return;
    final message = openHandLocalizedText(
      context,
      zh: '$zhAction：$error',
      en: '$enAction: $error',
    );
    if (postFrame) {
      flashOpenHandSnack(
        context,
        message,
        kind: OpenHandSnackKind.error,
        maxLines: 2,
      );
      return;
    }
    showOpenHandErrorSnack(context, message, maxLines: 2);
  }

  Future<void> _renameHarnessSession() async {
    final record = _persistedHarnessSession;
    if (record == null) return;
    final submitted = await showOpenHandTextInputDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '重命名 Harness Engineering 会话',
        en: 'Rename Harness Session',
      ),
      initialValue: record.title,
      hintText: openHandLocalizedText(
        context,
        zh: '输入会话标题',
        en: 'Enter a session title',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonSave,
    );
    if (!mounted || submitted == null || submitted.isEmpty) {
      return;
    }
    final updated = record.copyWith(
      title: submitted,
      updatedAt: DateTime.now().toUtc(),
    );
    final orchestrator = _activeHarnessOrchestrator;
    orchestrator?.removeListener(_onHarnessOrchestratorChanged);
    _harnessSessionSaveDebouncer.cancel();
    void resumeOrchestratorObservation() {
      if (!identical(_activeHarnessOrchestrator, orchestrator)) return;
      orchestrator?.addListener(_onHarnessOrchestratorChanged);
      if (orchestrator != null) _onHarnessOrchestratorChanged();
    }

    try {
      await _harnessSessionStore.save(updated);
    } catch (error, stack) {
      resumeOrchestratorObservation();
      _reportHarnessPersistenceError(
        operation: '重命名 Harness 会话',
        error: error,
        stack: stack,
        zhAction: '重命名 Harness 会话失败',
        enAction: 'Failed to rename the Harness session',
      );
      return;
    }
    if (!mounted) return;
    if (_persistedHarnessSession?.id != record.id) {
      resumeOrchestratorObservation();
      return;
    }
    setState(() => _persistedHarnessSession = updated);
    resumeOrchestratorObservation();
  }

  Future<void> _deleteHarnessSession() async {
    final record = _persistedHarnessSession;
    if (record == null) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除 Harness Engineering 会话',
        en: 'Delete Harness Session',
      ),
      content: Text(record.title),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final orchestrator = _activeHarnessOrchestrator;
    orchestrator?.removeListener(_onHarnessOrchestratorChanged);
    _harnessSessionSaveDebouncer.cancel();
    try {
      await _harnessSessionStore.clear();
    } catch (error, stack) {
      orchestrator?.addListener(_onHarnessOrchestratorChanged);
      _reportHarnessPersistenceError(
        operation: '删除 Harness 会话',
        error: error,
        stack: stack,
        zhAction: '删除 Harness 会话失败',
        enAction: 'Failed to delete the Harness session',
      );
      return;
    }
    if (!mounted) return;
    orchestrator?.dispose();
    setState(() {
      _activeHarnessOrchestrator = null;
      _activeHarnessConfig = null;
      _persistedHarnessSession = null;
      if (_selectedSection == AppSection.harnessSession) {
        _selectedSection = AppSection.workspace;
      }
    });
  }

  /// Hard cap on a single export operation so a corrupt session can never
  /// hang the UI indefinitely.
  /// 导出统一走超时与失败兜底，避免某次卡住的写入把进度弹窗永久留在屏幕上。
  Future<ExportResult> _runBoundedExport({
    required String logAction,
    required Future<ExportResult> Function() export,
    required ExportCancelToken cancelToken,
  }) async {
    try {
      return await export().timeout(
        kOpenHandExportTimeout,
        onTimeout: () {
          cancelToken.cancel();
          return const ExportResult(kind: ExportResultKind.failure);
        },
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', logAction, error, stack);
      return ExportResult(kind: ExportResultKind.failure, error: error);
    }
  }

  Future<void> _exportSession(AiSession session) async {
    final controller = context.read<AiSessionController>();

    // Step 1: load the full session up-front so the config dialog can show
    // an accurate message count for range validation.
    AiSession? loaded;
    try {
      loaded = await controller.store.loadSession(session.id);
    } catch (error, stack) {
      silentLog('openhand_home_page', '加载待导出会话', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '加载会话失败：$error',
          en: 'Failed to load session: $error',
        ),
        maxLines: 2,
      );
      return;
    }
    if (loaded == null || !mounted) {
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '会话不存在或已被删除。',
            en: 'Session is missing or has been deleted.',
          ),
        );
      }
      return;
    }
    // 绑定为 final：可空局部变量的类型提升不会延续到下面的闭包里。
    final loadedSession = loaded;

    // Step 2: collect the export configuration from the user.
    final config = await showAiSessionExportConfigDialog(
      context: context,
      totalMessages: loadedSession.messages.length,
    );
    if (config == null || !mounted) return;

    // Step 3: pick the destination file.
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    final suggested = jsonlExportPickerSuggestedName(
      buildJsonlExportFilename(title: loaded.title, sessionId: loaded.id),
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '选择会话导出位置', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '无法打开保存对话框：$error',
          en: 'Unable to open save dialog: $error',
        ),
        maxLines: 2,
      );
      return;
    }
    if (location == null || !mounted) return;

    // Step 4: kick off the streamed export with progress UI.
    final destinationPath = normalizeJsonlExportPath(location.path);
    final result = await runWithExportProgressDialog(
      context: context,
      title: _homeExportSessionDataLabel(context),
      subtitle: openHandLocalizedText(
        context,
        zh: '正在导出 “${loadedSession.title}”…',
        en: 'Exporting "${loadedSession.title}"…',
      ),
      cancelLabel: openHandCancelLabel(context),
      logTag: 'openhand_home_page',
      logAction: '导出会话：关闭进度对话框',
      run: (cancelToken, progressController) => _runBoundedExport(
        logAction: '导出会话',
        export: () => exportAiSessionToJsonl(
          session: loadedSession,
          destinationPath: destinationPath,
          cancelToken: cancelToken,
          config: config,
          onProgress: progressController.updateProgress,
        ),
        cancelToken: cancelToken,
      ),
    );

    if (!mounted) return;
    _showExportResultSnackBar(result, destinationPath);
  }

  Future<void> _exportHarnessSession() async {
    final record = _persistedHarnessSession;
    if (record == null) return;

    // Step 1: collect the export configuration from the user.
    final config = await showHarnessSessionExportConfigDialog(
      context: context,
      totalPhaseLogs: record.phaseLogs.length,
    );
    if (config == null || !mounted) return;

    // Step 2: pick the destination file.
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    final suggested = jsonlExportPickerSuggestedName(
      buildJsonlExportFilename(title: record.title, sessionId: record.id),
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('openhand_home_page', '选择 Harness 会话导出位置', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '无法打开保存对话框：$error',
          en: 'Unable to open save dialog: $error',
        ),
        maxLines: 2,
      );
      return;
    }
    if (location == null || !mounted) return;

    final destinationPath = normalizeJsonlExportPath(location.path);
    final result = await runWithExportProgressDialog(
      context: context,
      title: _homeExportSessionDataLabel(context),
      subtitle: openHandLocalizedText(
        context,
        zh: '正在导出 “${record.title}”…',
        en: 'Exporting "${record.title}"…',
      ),
      cancelLabel: openHandCancelLabel(context),
      logTag: 'openhand_home_page',
      logAction: '导出 Harness 会话：关闭进度对话框',
      run: (cancelToken, progressController) => _runBoundedExport(
        logAction: '导出 Harness 会话',
        export: () => exportHarnessSessionToJsonl(
          record: record,
          destinationPath: destinationPath,
          cancelToken: cancelToken,
          config: config,
          onProgress: progressController.updateProgress,
        ),
        cancelToken: cancelToken,
      ),
    );

    if (!mounted) return;
    _showExportResultSnackBar(result, destinationPath);
  }

  void _showExportResultSnackBar(ExportResult result, String destinationPath) {
    final ctx = context;
    switch (result.kind) {
      case ExportResultKind.success:
        showOpenHandSuccessSnack(
          ctx,
          openHandLocalizedText(
            ctx,
            zh: '导出成功：$destinationPath',
            en: 'Export succeeded: $destinationPath',
          ),
          duration: kOpenHandSnackBarLongReadDuration,
          maxLines: 2,
        );
      case ExportResultKind.cancelled:
        showOpenHandInfoSnack(
          ctx,
          openHandLocalizedText(ctx, zh: '已取消导出。', en: 'Export cancelled.'),
        );
      case ExportResultKind.failure:
        final reason = result.error?.toString() ?? 'unknown error';
        showOpenHandErrorSnack(
          ctx,
          openHandLocalizedText(
            ctx,
            zh: '导出失败：$reason',
            en: 'Export failed: $reason',
          ),
          duration: kOpenHandSnackBarLongReadDuration,
          maxLines: 2,
        );
    }
  }

  Future<void> _editMessage(AiSessionMessage message) async {
    final controller = context.read<AiSessionController>();
    final sessionId = controller.currentSessionId;
    final result = await controller.beginEditingMessage(message.id);
    if (!mounted ||
        result == null ||
        controller.currentSessionId != sessionId ||
        controller.editingMessageId != message.id) {
      return;
    }
    _replaceComposerText(result.content);

    // Restore attachments from the original message so the user can
    // keep, remove, or add more attachments while editing.
    final restoredAttachments = <_ComposerAttachmentDraft>[];
    for (final attachment in result.attachments) {
      final path = attachment.storagePath.trim();
      if (path.isNotEmpty && await isRegularFilePath(path)) {
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
    if (!mounted ||
        controller.currentSessionId != sessionId ||
        controller.editingMessageId != message.id) {
      return;
    }
    final creationState = _composerCreationStateFromRequest(
      result.creationRequest,
    );

    setState(() {
      _selectedSection = AppSection.workspace;
      _composerCollapsed = false;
      _pendingAttachments = restoredAttachments;
      _creationMode = creationState.mode;
      _creationOptions = creationState.options;
    });
    unawaited(
      _composerPanelState?.restoreSelectedSkillFromMetadata(
            result.selectedSkillMetadata,
          ) ??
          Future<void>.value(),
    );
    _scheduleScrollToBottom();
  }

  Future<void> _copyMessage(AiSessionMessage message) async {
    var content = message.content;
    if (message.metadata[aiSessionMessageContentPreviewMetadataKey] == true) {
      final sessionId = context.read<AiSessionController>().currentSession?.id;
      if (sessionId == null) return;
      final loaded = await context
          .read<AiSessionController>()
          .loadFullSessionMessageContent(sessionId, message.id);
      if (!mounted) return;
      if (loaded == null) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '完整内容加载失败，未执行复制。',
            en: 'Unable to load the full content. Nothing was copied.',
          ),
        );
        return;
      }
      content = loaded.content;
    }
    await copyOpenHandTextToClipboard(
      logTag: 'home',
      context: context,
      text: content,
      logAction: '复制消息内容',
      successMessage: openHandLocalizedText(
        context,
        zh: '消息内容已复制。',
        en: 'Message copied.',
      ),
    );
  }

  Future<bool> _deleteMessage(AiSessionMessage message) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(context, zh: '删除消息', en: 'Delete Message'),
      message: openHandLocalizedText(
        context,
        zh: '删除后，这条消息将不再显示。',
        en: 'This message will no longer be shown.',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteMessages(<String>[message.id]);
    if (!mounted || deleted) {
      return deleted;
    }
    showOpenHandErrorSnack(
      context,
      controller.lastErrorMessage ??
          openHandLocalizedText(context, zh: '消息删除失败。', en: 'Delete failed.'),
    );
    return false;
  }

  Future<bool> _deleteMessageFromHere(AiSessionMessage message) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除此条及后续消息',
        en: 'Delete From Here',
      ),
      message: openHandLocalizedText(
        context,
        zh: '删除后，这条消息及其后续消息将不再显示。',
        en: 'This message and the later messages will no longer be shown.',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: AppLocalizations.of(context)!.commonDelete,
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return false;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteMessagesFrom(message.id);
    if (!mounted || deleted) {
      return deleted;
    }
    showOpenHandErrorSnack(
      context,
      controller.lastErrorMessage ??
          openHandLocalizedText(context, zh: '批量删除消息失败。', en: 'Delete failed.'),
    );
    return false;
  }

  Future<void> _forkMessage(AiSessionMessage message) async {
    final controller = context.read<AiSessionController>();
    final sourceSessionId = controller.currentSessionId;
    if (sourceSessionId == null || sourceSessionId.trim().isEmpty) {
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(context, zh: '派生新会话', en: 'Fork Session'),
      message: openHandLocalizedText(
        context,
        zh: '将从当前会话的这条消息之后派生出一个新会话。新会话会保留这条消息及之前的内容，并舍弃之后的消息。',
        en: 'Create a new session from this point. The new session keeps this message and everything before it, and drops later messages.',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: _homeForkLabel(context),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final forked = await controller.forkSessionFromMessage(
      message.id,
      sessionId: sourceSessionId,
    );
    if (!mounted) {
      return;
    }
    if (forked == null) {
      showOpenHandErrorSnack(
        context,
        controller.lastErrorMessage ??
            openHandLocalizedText(
              context,
              zh: '派生会话失败。',
              en: 'Failed to fork session.',
            ),
      );
      return;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(context, zh: '已派生新会话。', en: 'Session forked.'),
    );
  }

  Future<void> _setMessageFeedback(
    AiSessionMessage message,
    AiSessionMessageFeedback? feedback,
  ) async {
    final controller = context.read<AiSessionController>();
    final sessionId = controller.currentSessionId;
    if (sessionId == null || sessionId.trim().isEmpty) {
      return;
    }
    final saved = await controller.updateMessageFeedback(
      sessionId: sessionId,
      messageId: message.id,
      feedback: feedback,
    );
    if (!mounted || saved) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '反馈保存失败。',
        en: 'Failed to save feedback.',
      ),
    );
  }

  Future<void> _selectMessageResponseVariant(
    AiSessionMessage message,
    int index,
  ) async {
    final controller = context.read<AiSessionController>();
    final sessionId = controller.currentSessionId;
    if (sessionId == null || sessionId.trim().isEmpty) {
      return;
    }
    final selected = await controller.selectMessageResponseVariant(
      sessionId: sessionId,
      messageId: message.id,
      index: index,
    );
    if (!mounted || selected) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '响应候选切换失败。',
        en: 'Failed to switch response variant.',
      ),
    );
  }

  Future<void> _regenerateMessage(AiSessionMessage message) async {
    final controller = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final session = controller.currentSession;
    if (session == null || controller.currentSessionId == null) {
      return;
    }
    if (_displaySendPhaseForSession(controller, session.id) !=
        AiSendPhase.idle) {
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前会话正在响应，请先停止或等待完成。',
          en: 'This session is still responding. Stop it or wait for it to finish.',
        ),
      );
      return;
    }
    final selectedModel = _effectiveModelForSession(
      settingsController,
      session,
    );
    if (selectedModel == null) {
      showOpenHandErrorSnack(
        context,
        AppLocalizations.of(context)!.aiModelSelectionRequired,
      );
      return;
    }
    final runtimeContext = await _buildRuntimeContext(
      workingDirectory: _programmingExpertProjectRoot(session),
      skippedInstructionIds: Set<String>.from(_skippedInstructionIds),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    final regenerated = await controller.regenerateAssistantMessageVariant(
      sessionId: session.id,
      messageId: message.id,
      model: selectedModel,
      runtimeContext: runtimeContext,
      denyCommandRules: settingsController.aiDenyCommandRules,
      requireWriteCommandConfirmation:
          AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
            templateId: session.templateId,
            fullAccessPermission: session.fullAccessPermission,
            globalConfirmationEnabled:
                settingsController.aiWriteCommandConfirmationEnabled,
          ),
      confirmWriteCommand: (request) =>
          _confirmWriteCommand(request, sessionId: session.id),
    );
    if (!mounted || regenerated) {
      return;
    }
    showFriendlyErrorSnackBar(
      context,
      message: controller.lastErrorMessageForSession(session.id),
      fallback: openHandLocalizedText(
        context,
        zh: '重新生成失败。',
        en: 'Failed to regenerate response.',
      ),
    );
  }

  Future<void> _cancelEditingMessage() async {
    final controller = context.read<AiSessionController>();
    final cancelled = await controller.cancelEditingMessage();
    if (!mounted || cancelled) {
      return;
    }
    showOpenHandErrorSnack(
      context,
      controller.lastErrorMessage ??
          openHandLocalizedText(
            context,
            zh: '恢复编辑前的会话状态失败。',
            en: 'Failed to restore the previous conversation state.',
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
    final workspaceSessionLayout = context
        .select<
          AiSessionController,
          ({
            String? currentSessionId,
            String? projectRoot,
            String? machineTerminalSessionId,
            String projectLanguage,
            String projectSdkPath,
            String projectLspPath,
          })
        >((controller) {
          final session = controller.currentSession;
          return (
            currentSessionId: session?.id,
            projectRoot: _programmingExpertProjectRoot(session),
            machineTerminalSessionId:
                session?.templateId == kMachineExpertTemplateId
                ? session!.id
                : null,
            projectLanguage: _programmingExpertLanguage(session),
            projectSdkPath: _programmingExpertSdkPath(session),
            projectLspPath: _programmingExpertLspPath(session),
          );
        });
    final homeContentConstraints = BoxConstraints.tight(
      _homeContentViewportSize(context),
    );
    // 顶层注入滚动活动信号：让 transcript 子树里的 `_HtmlBubbleWebView`
    // 通过安全 helper 订阅，滚动期间冻结
    // 高度应用，滚动结束再一次性应用累积的最新值。
    final homeContent = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.canvasStart, palette.canvasEnd],
              ),
            ),
            child: SafeArea(
              minimum: _homeContentSafeAreaMinimum,
              child: Builder(
                builder: (context) {
                  final constraints = homeContentConstraints;
                  final stackedLayout =
                      constraints.maxWidth < _sideBySideLayoutMinWidth;
                  final stackedNavigationHeight = (constraints.maxHeight * 0.34)
                      .clamp(
                        _stackedNavigationMinHeight,
                        _stackedNavigationMaxHeight,
                      )
                      .toDouble();
                  final navigationPane =
                      Selector<AiSessionController, _NavigationSessionSnapshot>(
                        selector: (_, sessionController) {
                          final sessions = _navigationSessions(
                            sessionController,
                          );
                          return _NavigationSessionSnapshot(
                            sessions: sessions,
                            sendPhases: _navigationSendPhases(
                              sessionController,
                              sessions,
                            ),
                            currentSessionId:
                                sessionController.currentSessionId,
                            totalSessionCount: sessionController.sessions
                                .where(
                                  (session) =>
                                      session.isPrimaryWorkspaceSession,
                                )
                                .length,
                            harnessInsertionIndex:
                                _navigationHarnessInsertionIndex(sessions),
                          );
                        },
                        builder: (context, snapshot, _) => _NavigationPane(
                          selectedSection: _selectedSection,
                          sessions: snapshot.sessions,
                          sessionLimit: _navigationSessionLimit,
                          totalSessionCount: snapshot.totalSessionCount,
                          hasMoreSessions:
                              _navigationSessionLimit <
                              snapshot.totalSessionCount,
                          sessionSendPhases: snapshot.sendPhases,
                          currentSessionId: snapshot.currentSessionId,
                          onLoadMoreSessions: _loadMoreNavigationSessions,
                          onCreateThreadRequested: _createSessionFromDialog,
                          onSessionSelected: _activateSession,
                          onRenameSession: _renameSession,
                          onDeleteSession: _deleteSession,
                          onExportSession: _exportSession,
                          onGenerateTitleForSession: _generateTitleForSession,
                          onShowTrajectoryForSession: _showTrajectoryForSession,
                          onSectionSelected: _selectSection,
                          activeHarnessOrchestrator: _activeHarnessOrchestrator,
                          harnessSessionRecord: _persistedHarnessSession,
                          onHarnessSessionSelected:
                              _persistedHarnessSession != null ||
                                  _activeHarnessOrchestrator != null
                              ? () => _selectSection(AppSection.harnessSession)
                              : null,
                          onRenameHarnessSession:
                              _persistedHarnessSession != null
                              ? _renameHarnessSession
                              : null,
                          onDeleteHarnessSession:
                              _persistedHarnessSession != null
                              ? _deleteHarnessSession
                              : null,
                          onExportHarnessSession:
                              _persistedHarnessSession != null
                              ? _exportHarnessSession
                              : null,
                        ),
                      );

                  // Swap left pane to file explorer when toggled for
                  // programming_expert sessions.
                  final machineTerminalSessionId =
                      workspaceSessionLayout.machineTerminalSessionId;
                  final showFileExplorer =
                      _fileExplorerVisible &&
                      workspaceSessionLayout.projectRoot != null &&
                      _selectedSection == AppSection.workspace;
                  final showMachineTerminal =
                      machineTerminalSessionId != null &&
                      _visibleMachineTerminalPanelSessionIds.contains(
                        machineTerminalSessionId,
                      ) &&
                      _selectedSection == AppSection.workspace;
                  final panelSettings = openHandMotionSettingsOf(
                    context,
                    OpenHandMotionSettingsScope.panel,
                  );
                  final leftPaneEntranceDuration = _effectiveSwitchDuration(
                    panelSettings.entranceDuration,
                    minimumAnimatedDurationMs: 240,
                  );
                  final leftPaneExitDuration = _effectiveSwitchDuration(
                    panelSettings.exitDuration,
                    minimumAnimatedDurationMs: 240,
                  );
                  final Widget leftPane = ClipRect(
                    child: AnimatedSwitcher(
                      duration: leftPaneEntranceDuration,
                      reverseDuration: leftPaneExitDuration,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return _buildWorkspaceSidebarTransition(
                          child: child,
                          animation: animation,
                          settings: panelSettings,
                        );
                      },
                      child: showMachineTerminal
                          ? _ContentPane(
                              key: const ValueKey<String>(
                                'machine-terminal-pane',
                              ),
                              child: _MachineExpertTerminalPanel(
                                sessionId: machineTerminalSessionId,
                                onPanelClose: () => _hideMachineTerminalPanel(
                                  machineTerminalSessionId,
                                ),
                              ),
                            )
                          : showFileExplorer
                          ? _ContentPane(
                              key: ValueKey<String>(
                                'file-explorer-pane:${workspaceSessionLayout.projectRoot}',
                              ),
                              child: _FileExplorerPanel(
                                rootPath: workspaceSessionLayout.projectRoot!,
                                onFileSelected: _openFileInEditor,
                                activeFilePath: _activeFilePath,
                                onCloseRequested: _toggleFileExplorer,
                              ),
                            )
                          : KeyedSubtree(
                              key: const ValueKey<String>('navigation-pane'),
                              child: navigationPane,
                            ),
                    ),
                  );

                  // Swap right pane to code editor when files are open.
                  final showEditor =
                      _selectedSection == AppSection.workspace &&
                      workspaceSessionLayout.currentSessionId != null &&
                      _editorTabsSessionId ==
                          workspaceSessionLayout.currentSessionId &&
                      _activeFilePath != null &&
                      _openFilePaths.isNotEmpty;
                  final pageSettings = openHandMotionSettingsOf(
                    context,
                    OpenHandMotionSettingsScope.page,
                  );
                  final rightPaneEntranceDuration = _effectiveSwitchDuration(
                    pageSettings.entranceDuration,
                    minimumAnimatedDurationMs: 280,
                  );
                  final rightPaneExitDuration = _effectiveSwitchDuration(
                    pageSettings.exitDuration,
                    minimumAnimatedDurationMs: 280,
                  );
                  final Widget rightPane = ClipRect(
                    child: AnimatedSwitcher(
                      duration: rightPaneEntranceDuration,
                      reverseDuration: rightPaneExitDuration,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return _buildWorkspaceContentTransition(
                          child: child,
                          animation: animation,
                          settings: pageSettings,
                        );
                      },
                      child: showEditor
                          ? Padding(
                              key: const ValueKey<String>('editor-pane'),
                              padding: const EdgeInsets.all(4),
                              child: _CodeEditorView(
                                openFiles: _openFilePaths,
                                activeFilePath: _activeFilePath!,
                                projectLanguage:
                                    workspaceSessionLayout.projectLanguage,
                                projectSdkPath:
                                    workspaceSessionLayout.projectSdkPath,
                                projectLspPath:
                                    workspaceSessionLayout.projectLspPath,
                                onOpenFile: _openFileInEditor,
                                onTabSelected: _selectFileTab,
                                onTabClosed: _closeFileTab,
                                onCloseAll: _closeAllFileTabs,
                                onReorderTabs: _reorderFileTabs,
                                fileExplorerVisible: _fileExplorerVisible,
                                onToggleFileExplorer: _toggleFileExplorer,
                              ),
                            )
                          : _selectedSection == AppSection.workspace
                          ? Selector<
                              AiSessionController,
                              _WorkspaceSessionSnapshot
                            >(
                              key: ValueKey<String>(
                                'section-${_selectedSection.name}',
                              ),
                              selector: (context, controller) =>
                                  _workspaceSessionSnapshot(controller),
                              builder: (context, snapshot, _) => _ContentPane(
                                child: _buildSectionContent(
                                  context,
                                  section: AppSection.workspace,
                                  workspaceSessionSnapshot: snapshot,
                                ),
                              ),
                            )
                          : _ContentPane(
                              key: ValueKey<String>(
                                'section-${_selectedSection.name}',
                              ),
                              child: _buildSectionContent(context),
                            ),
                    ),
                  );

                  if (stackedLayout) {
                    return Column(
                      children: [
                        SizedBox(
                          height: stackedNavigationHeight,
                          child: leftPane,
                        ),
                        // Match the horizontal pane gap and SafeArea outer
                        // inset so the spacing between stacked panes is
                        // visually consistent with every other gutter.
                        const SizedBox(height: _contentPaneGap),
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
          Focus(
            focusNode: _globalShortcutFocusNode,
            autofocus: true,
            canRequestFocus: true,
            skipTraversal: true,
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
    return ListenableProvider<TranscriptScrollActivity>.value(
      value: _transcriptScrollActivity,
      child: homeContent,
    );
  }

  Widget _buildSectionContent(
    BuildContext context, {
    AppSection? section,
    _WorkspaceSessionSnapshot? workspaceSessionSnapshot,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final effectiveSection = section ?? _selectedSection;
    final workspaceSelected = effectiveSection == AppSection.workspace;
    final settingsController = workspaceSelected
        ? context.watch<SettingsController>()
        : context.read<SettingsController>();
    final skillsController = workspaceSelected
        ? context.watch<SkillsController>()
        : context.read<SkillsController>();
    final mcpController = workspaceSelected
        ? context.watch<McpController>()
        : context.read<McpController>();
    final sessionController = context.read<AiSessionController>();
    final appInfo = context.read<AppInfo>();
    final currentSession = workspaceSelected
        ? workspaceSessionSnapshot?.session ?? sessionController.currentSession
        : sessionController.currentSession;
    final machineTerminalSessionId =
        currentSession?.templateId == kMachineExpertTemplateId
        ? currentSession!.id
        : null;
    final selectedModel = _effectiveModelForSession(
      settingsController,
      currentSession,
    );
    final transcriptHydrating = workspaceSelected
        ? workspaceSessionSnapshot?.hydrating ?? false
        : currentSession != null &&
              sessionController.isSessionMessagesHydrating(currentSession.id);
    final transcriptLoadError = workspaceSelected
        ? workspaceSessionSnapshot?.loadError
        : currentSession == null
        ? null
        : sessionController.sessionMessageWindowLoadErrorFor(currentSession.id);
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
      _maybeAutoFollowSession(currentSession);
    }

    return switch (effectiveSection) {
      AppSection.workspace => _WorkspaceView(
        draftController: _composerController,
        messageScrollController: _messageScrollController,
        onMessageScrollNotification: _handleMessageScrollNotification,
        onMessagePointerSignal: _handleMessagePointerSignal,
        currentSession: currentSession,
        liveRuntimeToolPreview: liveRuntimeToolPreview,
        transcriptHydrating: transcriptHydrating,
        transcriptLoadError: transcriptLoadError,
        onRetryTranscriptLoad: () async {
          final session = sessionController.currentSession;
          if (session == null) return;
          await sessionController.retrySessionMessageWindowHydration(
            session.id,
          );
        },
        selectedModel: selectedModel,
        availableModels: settingsController.aiModels,
        recentModelSelections: settingsController.recentModelSelections,
        onModelSelected: (providerConfigId, modelId) {
          final session = sessionController.currentSession;
          if (session != null &&
              isInputCacheModelSelectionLockedForSession(
                inputCacheEnabled: settingsController.aiInputCacheEnabled,
                session: session,
              )) {
            showOpenHandInfoSnack(
              context,
              _inputCacheModelLockReason(context),
              maxLines: 2,
            );
            return;
          }
          if (session != null) {
            sessionController.updateSessionLastUsedModel(
              session.id,
              providerConfigId: providerConfigId,
              modelId: modelId,
            );
          } else {
            settingsController.updateProviderActiveModel(
              providerConfigId,
              modelId,
            );
          }
          settingsController.addRecentModelSelection(providerConfigId, modelId);
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
        onMessageExpansionChanged: _handleMessageExpansionChanged,
        onRevealOlderMessages: _handleRevealOlderMessages,
        onProgrammaticScrollCorrection:
            _runProgrammaticTranscriptScrollCorrection,
        autoFollowEnabled: _autoFollowEnabled,
        autoFollowPaused: _autoFollowPaused,
        onToggleAutoFollow: _toggleAutoFollow,
        sendPhase:
            workspaceSessionSnapshot?.sendPhase ??
            _effectiveSendPhase(sessionController),
        canStopSending:
            workspaceSessionSnapshot?.canStop ??
            _canStopCurrentSessionResponse(sessionController),
        planTimelineCollapsed: _isPlanTimelineCollapsed(currentSession?.id),
        onPlanTimelineCollapsedChanged: currentSession == null
            ? null
            : (collapsed) {
                _setPlanTimelineCollapsed(currentSession.id, collapsed);
              },
        sessionMode: _effectiveComposerMode(sessionController),
        onSessionModeChanged: _setComposerMode,
        goalControls: _GoalControls(
          available:
              currentSession != null &&
              aiSessionGoalModeAllowedForTemplate(currentSession.templateId),
          suppressedForQueue: _goalPausedForQueuedMessages(currentSession),
          onPause: _pauseCurrentGoal,
          onResume: _resumeCurrentGoal,
          onTerminate: _terminateCurrentGoal,
        ),
        fullAccessPermission:
            currentSession?.fullAccessPermission ??
            _detachedFullAccessPermission,
        onToggleFullAccessPermission: _handleFullAccessPermissionToggle,
        queuedPanel: _QueuedMessagesPanel(
          messages: currentSession != null
              ? (_queuedMessagesBySessionId[currentSession.id] ?? const [])
              : const [],
          guidanceInProgress:
              currentSession != null &&
              _queuedGuidanceSessionIds.contains(currentSession.id),
          onRemove: (index) {
            if (currentSession != null) {
              _QueuedMessage? removedMessage;
              setState(() {
                final q = _queuedMessagesBySessionId[currentSession.id];
                if (q != null && index >= 0 && index < q.length) {
                  final removed = q[index];
                  removedMessage = removed;
                  q.removeAt(index);
                  if (_failedQueuedMessageIdsBySessionId[currentSession.id] ==
                      removed.id) {
                    _failedQueuedMessageIdsBySessionId.remove(
                      currentSession.id,
                    );
                  }
                  if (q.isEmpty) {
                    _queuedMessagesBySessionId.remove(currentSession.id);
                  }
                }
              });
              final removed = removedMessage;
              if (removed != null) {
                _releaseComposerTempPaths(
                  removed.attachments.map((item) => item.filePath),
                );
              }
            }
          },
          onMove: (from, to) {
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
                  _failedQueuedMessageIdsBySessionId.remove(currentSession.id);
                }
              });
            }
          },
          onEdit: (index, newText) {
            if (currentSession != null) {
              final trimmed = newText.trim();
              if (trimmed.isEmpty) return;
              setState(() {
                final q = _queuedMessagesBySessionId[currentSession.id];
                if (q != null && index >= 0 && index < q.length) {
                  q[index] = _QueuedMessage(
                    id: q[index].id,
                    text: trimmed,
                    attachments: q[index].attachments,
                    creationRequest: q[index].creationRequest,
                    systemReminders: q[index].systemReminders,
                    skillMetadata: q[index].skillMetadata,
                  );
                  _failedQueuedMessageIdsBySessionId.remove(currentSession.id);
                }
              });
            }
          },
          onGuide: (index) {
            if (currentSession == null) return;
            _failedQueuedMessageIdsBySessionId.remove(currentSession.id);
            unawaited(
              _dispatchQueuedMessageForSession(
                sessionController,
                sessionId: currentSession.id,
                index: index,
                guidance: true,
              ),
            );
          },
        ),
        attachments: _ComposerAttachments(
          drafts: _pendingAttachments,
          enabled: _selectedModelSupportsAttachments(selectedModel),
          onPick: _pickComposerAttachments,
          onRemove: _removePendingAttachment,
          onReorder: _reorderPendingAttachments,
        ),
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
        editingMessageId:
            workspaceSessionSnapshot?.editingMessageId ??
            sessionController.editingMessageId,
        onCancelEditing: _cancelEditingMessage,
        messageActions: _MessageActions(
          onEdit: _editMessage,
          onCopy: _copyMessage,
          onDelete: _deleteMessage,
          onDeleteFromHere: _deleteMessageFromHere,
          onFork: _forkMessage,
          onSetFeedback: _setMessageFeedback,
          onRegenerate: _regenerateMessage,
          onSelectResponseVariant: _selectMessageResponseVariant,
        ),
        ttsPlaybackService: _ttsPlaybackService,
        translationService: _translationService,
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
        machineTerminalPanelVisible: _machineTerminalPanelVisibleFor(
          currentSession,
        ),
        onMachineTerminalPanelToggled: machineTerminalSessionId == null
            ? null
            : () => _toggleMachineTerminalPanel(machineTerminalSessionId),
        projectRoot: _programmingExpertProjectRoot(currentSession),
        onComposerStateCreated: (state) {
          _composerPanelState = state;
        },
        onComposerStateDisposed: (state) {
          if (identical(_composerPanelState, state)) {
            _composerPanelState = null;
          }
        },
        skippedInstructionIds: _skippedInstructionIds,
        onToggleInstructionSkip: _toggleInstructionSkip,
      ),
      AppSection.skills => const SkillsView(),
      AppSection.memory => const MemoryView(),
      AppSection.mcp => const McpView(),
      AppSection.hooks => const HooksView(),
      AppSection.crons => const CronsView(),
      AppSection.instructions => const InstructionsView(),
      AppSection.messageGateway => const MessageGatewayView(),
      AppSection.pluginService => const PluginServiceView(),
      AppSection.knowledgeBase => KnowledgeBaseView(
        onOpenPlugins: () => _selectSection(AppSection.pluginService),
      ),
      AppSection.agents => const AgentsView(),
      AppSection.services => const ServicesView(),
      AppSection.settings => Provider<ToolSearchReplayDispatcher>.value(
        value: _toolSearchReplayDispatcher,
        child: const SettingsView(),
      ),
      AppSection.harnessSession =>
        _activeHarnessOrchestrator != null && _activeHarnessConfig != null
            ? HarnessSessionPane(
                controller: _harnessSessionPaneController,
                config: _activeHarnessConfig!,
                orchestrator: _activeHarnessOrchestrator!,
                isZh: openHandIsChineseLocale(context),
                sessionTitle: _persistedHarnessSession?.title,
                updatedAtLabel: _persistedHarnessSession == null
                    ? null
                    : formatYearMonthDayHmLocal(_persistedHarnessSession!.updatedAt),
                sessionId: _persistedHarnessSession?.id,
                createdAtLabel: _persistedHarnessSession == null
                    ? null
                    : formatYearMonthDayHmLocal(_persistedHarnessSession!.createdAt),
                sessionCreatedAt: _persistedHarnessSession?.createdAt,
                sessionUpdatedAt: _persistedHarnessSession?.updatedAt,
                fullAccessPermission: _heFullAccessPermission,
                onToggleFullAccessPermission: _handleHeFullAccessToggle,
                onConfigChanged: _handleHeConfigChanged,
                filePathRoots: [
                  if ((_activeHarnessConfig?.workingDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    _activeHarnessConfig!.workingDirectory,
                  if ((_activeHarnessConfig?.persistenceDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    _activeHarnessConfig!.persistenceDirectory,
                  if ((_activeHarnessConfig?.persistenceDirectory ?? '')
                      .trim()
                      .isNotEmpty)
                    p.join(
                      _activeHarnessConfig!.persistenceDirectory,
                      'steering',
                    ),
                ],
                onRestart: () {
                  setState(() => _selectedSection = AppSection.harnessSession);
                  _activeHarnessOrchestrator?.startOrResume();
                },
                replayPendingDeadlineListenable:
                    _toolSearchReplayDispatcher.pendingDeadlineListenable,
                onCancelPendingReplay: _toolSearchReplayDispatcher.cancel,
              )
            : SectionPlaceholder(
                icon: Icons.construction_rounded,
                title: 'Harness Engineering',
                body: l10n.threadsEmptyBody,
                footer: l10n.placeholderComingSoon,
                actionLabel: l10n.newThread,
                onAction: _createSessionFromDialog,
              ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 本库内共用的文案
//
// 下列标签原先在同一个库的多个 part 里各写了一份多语言字面量，改一处措辞就
// 得同步改两到三处。
// ─────────────────────────────────────────────────────────────────────────────

String _homeAgentsLabel(BuildContext context) {
  return openHandAgentsLabel(context);
}

String _homeAwaitingApprovalLabel(BuildContext context) {
  return openHandAwaitingApprovalLabel(context);
}

String _homeCreatedAtLabel(BuildContext context) {
  return openHandCreatedAtLabel(context);
}

String _homeEvidenceLabel(BuildContext context) {
  return openHandEvidenceLabel(context);
}

String _homeExportSessionDataLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '导出会话数据',
    en: 'Export Session Data',
  );
}

String _homeFailedLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '异常', en: 'Failed');
}

String _homeForkLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '派生', en: 'Fork');
}

String _homeHooksLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: 'Hooks', en: 'Hooks');
}

String _homeMissingLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '缺口', en: 'Missing');
}

String _homeNoTextualDiffAvailableLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '内容相同或不可对比。',
    en: 'No textual diff available.',
  );
}

String _homeOpenLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '打开', en: 'Open');
}

String _homePlatformLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '平台', en: 'Platform');
}

String _homePluginsLabel(BuildContext context) {
  return openHandPluginsLabel(context);
}

String _homeRenameThreadLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '重命名线程', en: 'Rename Thread');
}

String _homeSessionsDirectoryLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '会话目录', en: 'Sessions Directory');
}

String _homeStartingLabel(BuildContext context) {
  return openHandStartingLabel(context);
}

String _homeTerminalLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '终端', en: 'Terminal');
}

String _homeTerminalsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '终端数量', en: 'Terminals');
}

String _homeUpdatedAtLabel(BuildContext context) {
  return openHandUpdatedAtLabel(context);
}

String _homeWorkingDirectoryLabel(BuildContext context) {
  return openHandWorkingDirectoryLabel(context);
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _openhandHomePaTitleGenerationFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '标题生成失败',
    en: 'Title Generation Failed',
  );
}

class _ReverseRuntimeCapacityException implements Exception {
  const _ReverseRuntimeCapacityException(this.message);

  final String message;

  @override
  String toString() => message;
}

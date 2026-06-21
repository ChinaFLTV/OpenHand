import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
import '../../shared/db/database_service.dart';
import '../../shared/ui/animated_appearance.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/animated_overlay.dart';
import '../../shared/ui/appear_once.dart';
import '../../shared/ui/appear_tracker.dart';
import '../../shared/ui/bounded_animation.dart';
import '../../shared/ui/choice_input_dialog.dart';
import '../../shared/ui/error_snackbar.dart';
import '../../shared/ui/export_config_dialog.dart';
import '../../shared/ui/export_progress_dialog.dart';
import '../../shared/ui/highlight_pulse.dart';
import '../../shared/ui/image_editor_dialog.dart';
import '../../shared/ui/interactive_image_preview.dart';
import '../../shared/ui/markdown_math.dart';
import '../../shared/ui/micro_press_feedback.dart';
import '../../shared/ui/model_search_selector.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_editor_scroll_behavior.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/rolling_text.dart';
import '../../shared/ui/section_placeholder.dart';
import '../../shared/ui/streaming_text_reveal.dart';
import '../../shared/ui/structured_error_text.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/unified_diff.dart'
    show unifiedDiffLines, unifiedDiffLinesFromText;
import '../ai/index.dart';
import '../android_reverse/index.dart';
import '../crons/index.dart';
import '../hardness/index.dart';
import '../hooks/index.dart';
import '../instructions/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../message_gateway/index.dart';
import '../plugin_service/index.dart';
import '../settings/index.dart';
import '../skills/index.dart';
import '../web_reverse/index.dart';
import 'model/cache_hit_ratio.dart';
import 'model/session_cache_hit_trend.dart';
import 'util/editor_indentation.dart';
import 'util/message_path_linking.dart';
import 'util/slash_command_parser.dart';
import 'util/tool_call_argument_parser.dart';
import 'widgets/html_selection_bridge_clipboard.dart';
import 'widgets/machine_expert_dialog.dart';
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
part 'widgets/_home_hardness_annotations.dart';
part 'widgets/_home_motion_tokens.dart';
part 'widgets/_openhand_home_page_helpers.dart';
part 'widgets/_openhand_home_page_prelude.dart';

/// 2026-06-07：HTML WebView 抽搐 bug 真凶的关键协调信号。
/// 外层 ListView 检测到"用户正在主动滚动"时标记 active，滚动结束（含
/// 800 ms 宽限期）后标记 inactive。`_HtmlBubbleWebView` 订阅此信号：
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

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage>
    with WidgetsBindingObserver {
  /// 当前活跃的 home state 实例引用——`part of` 文件（例如
  /// [_home_session_toolbar.dart] 中的 [_showContextStatsDialog]）需要
  /// 通过它取到 [_buildRuntimeContext]、[AiSessionController] 等私有 API。
  /// 同一时刻只会存在一个 OpenHand home page。
  static _OpenHandHomePageState? _activeHomeState;
  static const int _androidReverseMcpRuntimeToolNameLimit = 64;
  static const int _androidReverseMcpToolSearchLimit = 8;
  static const List<String> _androidReverseMcpKeywords = <String>[
    'adb',
    'android',
    'apk',
    'aapt',
    'apksigner',
    'apktool',
    'jadx',
    'frida',
    'objection',
    'ida',
    'radare',
    'r2',
    'mitm',
    'proxy',
    'flutter',
    'dart',
    'blutter',
    'doldrums',
    'anything',
    'analyzer',
    'logcat',
    'device',
    'shell',
  ];
  static const String _androidReverseMcpFallbackToolSearchQuery =
      'select:adb,android,frida,ida,apktool,jadx,anything-analyzer,flutter';

  final TextEditingController _composerController = SafeTextEditingController();
  // HTML WebView 异步测高协调信号——见 [TranscriptScrollActivity] 注释。
  // 在 ListView build 树顶层用 ListenableProvider 注入，供深层的
  // `_HtmlBubbleWebView` 订阅，实现"用户滚动期间冻结高度应用"。
  final TranscriptScrollActivity _transcriptScrollActivity =
      TranscriptScrollActivity();
  late final ScrollController _messageScrollController =
      OpenHandStableScrollController(
        userScrollActivity: _transcriptScrollActivity,
      );
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
  bool _programmaticAutoFollowScrollInProgress = false;
  int _programmaticTranscriptScrollCorrectionDepth = 0;
  bool _userScrollInProgress = false;
  bool _userDragActive = false;
  bool _transcriptLayoutAutoFollowQueued = false;
  bool _scrollToBottomAwaitingPosition = false;
  int _scrollToBottomPositionRetryCounter = 0;
  bool _composerScrollCompensationInProgress = false;
  DateTime? _lastPointerSignalScrollAt;
  // 2026-05-17：trackpad / 鼠标滚轮等 pointer-signal 滚动每个 tick 都会
  // 完整经历 ScrollStart → Update → ScrollEnd，而非整段手势包裹一次。
  // 慢速滚动时两个 tick 之间会出现 _userScrollInProgress=false 的空窗，
  // 让 layout-change / composer 折叠 / 流式新消息触发的 jumpTo 抢到一帧，
  // 表现为视口被一股力反复拽回底部，呈现"抽搐/鬼畜"。给 scroll-end 加上
  // 1200 ms 宽限：宽限期内任何新的 scroll start 都会续期；超时未再发生
  // 滚动活动才视为用户真正松手。快速滑动时 ballistic 持续 → scroll-end
  // 推迟到松手才发，不依赖此宽限。
  // 2026-05-26 — 420→800 ms：极慢速触控板滚动时单 tick 间隔可超 420 ms，
  // 导致宽限期在两 tick 间过期→_userScrollInProgress 抖回 false→自动跟随
  // 抢一帧 jumpTo 把视口拽回底部→用户再拉回→往复振荡抽搐。
  // 2026-06-19 — 800→1200 ms：加载更早消息后，慢速上滑会不断物化
  // 可变高度旧消息；过早释放滚动活动会让 HTML 高度回写和 Sliver 估算
  // 修正插入到 tick 间隙，表现为整列消息轻微震动、滚动条长度漂移。
  late final OpenHandDebouncer _userScrollGraceDebouncer = OpenHandDebouncer(
    delay: _userScrollEndGraceDuration,
  );
  static const Duration _userScrollEndGraceDuration = Duration(
    milliseconds: 1200,
  );
  static const Duration _pointerSignalScrollActivityWindow = Duration(
    milliseconds: 500,
  );
  int _composerTransitionMeasurePassesRemaining = 0;
  bool _composerTransitionMeasureQueued = false;
  // 2026-06-07 修复：桌面端 WebView 平台视图可能吞掉 PointerScrollEvent，
  // 导致 _userScrollInProgress 未被置位。用 _lastScrollActivityAt 兜底记录
  // 外层 ListView 的 ScrollUpdateNotification，作为独立的后备检测源。
  DateTime? _lastScrollActivityAt;
  static const Duration _scrollActivityWindow = Duration(milliseconds: 1200);
  String? _lastAutoScrollSignature;
  List<_ComposerAttachmentDraft> _pendingAttachments =
      const <_ComposerAttachmentDraft>[];
  final Map<String, List<_QueuedMessage>> _queuedMessagesBySessionId =
      <String, List<_QueuedMessage>>{};
  final Map<String, _ComposerDraftState> _composerDraftsBySessionId =
      <String, _ComposerDraftState>{};
  final Map<String, bool> _collapsedPlanTimelinesBySessionId = <String, bool>{};
  final Set<String> _handledSessionDeletionNoticeKeys = <String>{};
  int? _runtimeToolPreviewCacheKey;
  AiRuntimeToolPreview? _runtimeToolPreviewCacheValue;
  AiSessionController? _observedSessionController;
  MessageGatewayController? _observedMessageGatewayController;
  StreamSubscription<List<WebWriteApprovalRequest>>? _writeApprovalSubscription;
  final Set<String> _handledWriteApprovalDialogIds = <String>{};
  String? _scheduledWriteApprovalDialogId;
  String? _presentingWriteApprovalDialogId;
  String? _presentingWriteApprovalSessionId;
  BuildContext? _activeWriteApprovalDialogContext;
  bool _suppressWriteApprovalDialogResponse = false;
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
  InputRepairParticipantToken? _inputRepairParticipantToken;
  int _resumeAutoFollowSuppressionFrames = 0;
  bool _resumeAutoFollowSyncQueued = false;
  final ValueNotifier<double> _navigationWidthNotifier = ValueNotifier<double>(
    _desktopNavigationWidth,
  );

  // Active Harness Engineering session (null when no HE session is running).
  HardnessOrchestrator? _activeHardnessOrchestrator;
  HardnessSessionConfig? _activeHardnessConfig;
  bool _heFullAccessPermission = false;
  final HardnessSessionPaneController _hardnessSessionPaneController =
      HardnessSessionPaneController();

  // Persisted record for the last HE session (survives app restarts).
  final HardnessSessionStore _hardnessSessionStore = HardnessSessionStore();
  HardnessSessionRecord? _persistedHardnessSession;
  late final OpenHandDebouncer _hardnessSessionSaveDebouncer =
      OpenHandDebouncer(delay: _hardnessSessionPersistenceDebounce);
  HardnessPhase? _lastHardnessAwaitingApprovalPhase;

  // Active Web Reverse Expert sessions, keyed by session id. Each holds a
  // controller managing one external Chrome process + CDP channel.
  final Map<String, WebReverseSessionController> _webReverseControllers =
      <String, WebReverseSessionController>{};
  final Map<String, String> _webReverseRuntimeMetadataSignatures =
      <String, String>{};
  late final OpenHandDebouncer _webReverseRuntimeMetadataDebouncer =
      OpenHandDebouncer(delay: _webReverseRuntimeMetadataDebounce);

  // Active Android Reverse Expert sessions, keyed by session id.
  final Map<String, AndroidReverseSessionController>
  _androidReverseControllers = <String, AndroidReverseSessionController>{};
  final Map<String, String> _androidReverseRuntimeMetadataSignatures =
      <String, String>{};

  // Programming Expert: file explorer & inline editor state.
  bool _fileExplorerVisible = false;
  final List<String> _openFilePaths = [];
  String? _activeFilePath;
  String? _editorTabsSessionId;
  late final OpenHandDebouncer _editorTabsSaveDebouncer = OpenHandDebouncer(
    delay: _editorTabsPersistenceDebounce,
  );

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
          debugLabel: 'home',
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
    // 2026-06-02 — 当平台 IME 反向回调 `updateEditingState` 触发
    // `Range start ... is out of text of length ...` 断言时，由
    // `FlutterError.onError` 摘调这个轻量钩子做一次 composer 焦点重置，
    // 避免每次都把完整的 `repair()` 全套（killTrackedChildren +
    // clearTextInputClient + hideTextInput）跑一遍而强行关掉键盘。
    InputRepairService.instance.registerSoftRecoveryHook(
      _runComposerImeSoftRecovery,
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
      unawaited(_ttsPlaybackService.stop());
      final pendingHardnessRecord = _persistedHardnessSession;
      if (pendingHardnessRecord != null) {
        // Cancel debounced timer and flush immediately.
        _hardnessSessionSaveDebouncer.cancel();
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
    _observedSessionController?.toolSearchLoadedSignal.removeListener(
      _handleToolSearchLoadedSignal,
    );
    _observedSessionController = sessionController;
    _observedSessionController?.addListener(_handleSessionControllerChanged);
    _observedSessionController?.toolSearchLoadedSignal.addListener(
      _handleToolSearchLoadedSignal,
    );
    _activeComposerSessionId = sessionController.currentSessionId;
    _activeTranscriptSessionId = sessionController.currentSessionId;
    final messageGatewayController = _readMessageGatewayController();
    if (!identical(
      _observedMessageGatewayController,
      messageGatewayController,
    )) {
      _writeApprovalSubscription?.cancel();
      _observedMessageGatewayController = messageGatewayController;
      _writeApprovalSubscription = messageGatewayController
          ?.pendingWriteApprovalsStream
          .listen(_handlePendingWriteApprovalsChanged);
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
    _activeHardnessOrchestrator?.removeListener(_onHardnessOrchestratorChanged);
    _activeHardnessOrchestrator?.cancel();
    _activeHardnessOrchestrator?.dispose();
    _webReverseCdpMcpBridge.dispose();
    for (final entry in _webReverseControllers.entries) {
      _disposeWebReverseControllerAfterStop(entry.key, entry.value);
    }
    _webReverseControllers.clear();
    _webReverseRuntimeMetadataDebouncer.cancel();
    _webReverseRuntimeMetadataSignatures.clear();
    for (final entry in _androidReverseControllers.entries) {
      _disposeAndroidReverseController(entry.key, entry.value);
    }
    _androidReverseControllers.clear();
    _androidReverseRuntimeMetadataSignatures.clear();
    _hardnessSessionSaveDebouncer.cancel();
    _editorTabsSaveDebouncer.cancel();
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
    _observedSessionController?.toolSearchLoadedSignal.removeListener(
      _handleToolSearchLoadedSignal,
    );
    _writeApprovalSubscription?.cancel();
    _writeApprovalSubscription = null;
    _observedMessageGatewayController = null;
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

  void _clearPendingAutoFollowState() {
    _pendingForcedScrollToBottom = false;
    _queuedForcedScrollToBottom = false;
    _pendingAnimatedScrollToBottom = false;
    _scrollToBottomAwaitingPosition = false;
    _scrollToBottomPositionRetryCounter = 0;
  }

  bool _isProgrammaticMessageScrollInProgress() {
    return _programmaticAutoFollowScrollInProgress ||
        _programmaticTranscriptScrollCorrectionDepth > 0 ||
        _composerScrollCompensationInProgress;
  }

  void _runProgrammaticTranscriptScrollCorrection(VoidCallback correction) {
    if (!mounted) return;
    _programmaticTranscriptScrollCorrectionDepth += 1;
    try {
      correction();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _programmaticTranscriptScrollCorrectionDepth = math.max(
          0,
          _programmaticTranscriptScrollCorrectionDepth - 1,
        );
      });
    }
  }

  /// 标记用户正在主动滚动；取消任何待执行的 scroll-end 宽限计时。
  void _markUserScrollInProgress() {
    _userScrollGraceDebouncer.cancel();
    _userScrollInProgress = true;
    // 2026-06-07：广播给订阅者（如 `_HtmlBubbleWebView`），让其在
    // 用户滚动期间冻结高度应用，避免异步测高把 viewport 拽回底部。
    _transcriptScrollActivity.markActive();
  }

  void _handleMessagePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _lastPointerSignalScrollAt = DateTime.now();
    _markUserScrollInProgress();
    _scheduleUserScrollEndGrace();
  }

  bool _hasRecentPointerSignalScrollActivity() {
    final last = _lastPointerSignalScrollAt;
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last) <=
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
    return DateTime.now().difference(last) < _scrollActivityWindow;
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
    _maybePresentExternalSessionDeletionNotice(sessionController);
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
        presentingSessionId == currentSessionId) {
      return;
    }
    _suppressWriteApprovalDialogResponse = true;
    final dialogContext = _activeWriteApprovalDialogContext;
    if (dialogContext != null && Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }
  }

  void _handlePendingWriteApprovalsChanged(
    List<WebWriteApprovalRequest> approvals,
  ) {
    if (!mounted ||
        _presentingWriteApprovalDialogId != null ||
        _scheduledWriteApprovalDialogId != null) {
      return;
    }
    final currentSessionId = _observedSessionController?.currentSessionId;
    if (currentSessionId == null || currentSessionId.isEmpty) {
      return;
    }
    for (final approval in approvals) {
      if (approval.sessionId != currentSessionId) {
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
    if (_observedSessionController?.currentSessionId != approval.sessionId) {
      return;
    }
    if (!gatewayController.pendingWriteApprovals.any(
      (item) => item.id == approval.id,
    )) {
      return;
    }

    _presentingWriteApprovalDialogId = approval.id;
    _presentingWriteApprovalSessionId = approval.sessionId;
    _suppressWriteApprovalDialogResponse = false;
    _handledWriteApprovalDialogIds.add(approval.id);
    var resolvedElsewhere = false;
    late final StreamSubscription<List<WebWriteApprovalRequest>> sub;
    sub = gatewayController.pendingWriteApprovalsStream.listen((items) {
      if (items.any((item) => item.id == approval.id)) {
        return;
      }
      resolvedElsewhere = true;
      final contextToClose = _activeWriteApprovalDialogContext;
      if (contextToClose != null &&
          contextToClose.mounted &&
          Navigator.of(contextToClose).canPop()) {
        Navigator.of(contextToClose).pop();
      }
    });
    try {
      final decision = await showWriteCommandConfirmationDialog(
        context,
        request: approval.toBashCommandApprovalRequest(),
        onDialogContext: (context) {
          _activeWriteApprovalDialogContext = context;
        },
      );
      if (!mounted ||
          resolvedElsewhere ||
          _suppressWriteApprovalDialogResponse) {
        return;
      }
      gatewayController.respondWriteApproval(
        approval.id,
        decision: decision ?? BashCommandApprovalDecision.dismissed,
      );
    } finally {
      await sub.cancel();
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
      _activeWriteApprovalDialogContext = null;
      _suppressWriteApprovalDialogResponse = false;
      if (mounted) {
        _handlePendingWriteApprovalsChanged(
          gatewayController.pendingWriteApprovals,
        );
      }
    }
  }

  void _maybePresentExternalSessionDeletionNotice(
    AiSessionController? sessionController,
  ) {
    final notice = sessionController?.lastDeletionNotice;
    if (notice == null || !notice.wasCurrentSession) return;
    if (notice.source == 'app') return;
    final key = '${notice.sessionId}:${notice.deletedAt.toIso8601String()}';
    if (!_handledSessionDeletionNoticeKeys.add(key)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deletedBy = notice.deletedByLabel.trim().isEmpty
          ? _localizedText(context, zh: 'Web 用户', en: 'a Web user')
          : notice.deletedByLabel.trim();
      unawaited(
        showOpenHandInfoDialog(
          context: context,
          title: _localizedText(
            context,
            zh: '当前线程已被删除',
            en: 'Current Thread Deleted',
          ),
          message: _localizedText(
            context,
            zh: '当前会话「${notice.sessionTitle}」已被 $deletedBy 删除。',
            en: 'The current session "${notice.sessionTitle}" was deleted by $deletedBy.',
          ),
          closeLabel: _localizedText(context, zh: '返回', en: 'Back'),
          barrierDismissible: false,
        ),
      );
    });
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _showHomeSnackBarWithMessenger(
      context,
      messenger,
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.snackToolSearchLoaded(
                  event.loadedCount,
                  event.totalDeferred,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.snackToolSearchLoadedAction,
          onPressed: () {
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
        ),
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
  /// [SettingsController.hardnessToolSearchHistoryMaxPhases]，默认值由
  /// [AppSettingsSnapshot.defaultHardnessToolSearchHistoryMaxPhases] 给出，
  /// 上下界 1..64），淘汰最早的 phase 桶，防止长会话内存膨胀（即使
  /// onPhaseEnded 因异常路径漏调也兜底）。
  final Map<String, List<AiToolSearchLoadHistoryEntry>>
  _hardnessToolSearchHistory = <String, List<AiToolSearchLoadHistoryEntry>>{};

  /// 获取（或创建）指定 phase 的历史桶，并将其在 LRU Map 中提升为最近使用。
  List<AiToolSearchLoadHistoryEntry> _touchHardnessHistoryBucket(
    String phaseSessionId,
  ) {
    final existing = _hardnessToolSearchHistory.remove(phaseSessionId);
    final bucket = existing ?? <AiToolSearchLoadHistoryEntry>[];
    _hardnessToolSearchHistory[phaseSessionId] = bucket;
    final cap = context
        .read<SettingsController>()
        .hardnessToolSearchHistoryMaxPhases;
    while (_hardnessToolSearchHistory.length > cap) {
      _hardnessToolSearchHistory.remove(_hardnessToolSearchHistory.keys.first);
    }
    return bucket;
  }

  void _handleHardnessToolSearchLoaded({
    required String phaseSessionId,
    required List<String> loadedNames,
    required int totalLoadedSoFar,
    required int totalDeferred,
    required String query,
  }) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final entry = AiToolSearchLoadHistoryEntry(
      timestamp: DateTime.now().toUtc(),
      query: query,
      addedNames: loadedNames,
      totalDeferred: totalDeferred,
      source: AiToolSearchLoadSource.hardnessPhase,
    );
    _touchHardnessHistoryBucket(phaseSessionId).add(entry);
    _showHomeSnackBarWithMessenger(
      context,
      messenger,
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.snackToolSearchLoaded(loadedNames.length, totalDeferred),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.snackToolSearchLoadedAction,
          onPressed: () => _showToolSearchLoadedDialog(
            names: List<String>.from(loadedNames)..sort(),
            history: List<AiToolSearchLoadHistoryEntry>.unmodifiable(
              _hardnessToolSearchHistory[phaseSessionId] ??
                  const <AiToolSearchLoadHistoryEntry>[],
            ),
            // Harness phase 自身的 tool loop 是自治的，无法直接重放；
            // 用户的意图通常是「我想再加载这一批」——为了不污染当前
            // Harness 活跃会话的上下文，专门走「先建独立 AI session
            // 再在新 session 里发 select:」的路径。
            onReplayBatch: _replayToolSearchInFreshSession,
          ),
        ),
      ),
    );
  }

  /// HardnessApiPhaseRunner.runPhase 在结束（成功/失败/取消/异常）时回调
  /// 本方法。借机清理 [_hardnessToolSearchHistory] 中与该 phase 关联的
  /// 加载历史，避免长期累积。
  void _handleHardnessPhaseEnded({required String phaseSessionId}) {
    _hardnessToolSearchHistory.remove(phaseSessionId);
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
  /// 并在 [kToolSearchReplayCancelWindow] 之后才提交，期间用户可以
  /// 通过 SnackBarAction 撤销。等价于用户手动复制粘贴后回车，但多了
  /// 一个 3s 反悔窗口。由 [_showToolSearchLoadedDialog] 历史条目点击触发。
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
      // 用户在 3 秒窗口内手动续写的文字。
      if (_composerController.text == query) {
        _composerController.clear();
      }
      if (mounted && l10n != null && messenger != null) {
        OpenHandSnackBar.hideCurrentOn(messenger);
        _showHomeSnackBarWithMessenger(
          context,
          messenger,
          SnackBar(
            content: Text(l10n.snackToolSearchLoadedReplayCancelledToast),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
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
        _showHomeSnackBarWithMessenger(
          context,
          messengerNow,
          SnackBar(
            content: Text(l10nNow.snackToolSearchLoadedReplayedToast),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (!completer.isCompleted) completer.complete();
    }

    if (l10n != null && messenger != null) {
      _showHomeSnackBarWithMessenger(
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

  /// Hardness 路径专用：先创建一个全新 AI session，再在新 session 里
  /// 发起 select: 查询，避免污染当前 hardness 活跃会话的上下文。
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
            late final _QueuedMessage nextMessage;
            setState(() {
              nextMessage = q.removeAt(0);
              if (q.isEmpty) {
                _queuedMessagesBySessionId.remove(sessionId);
              }
            });
            unawaited(
              _submitTextToSession(
                sessionId,
                nextMessage.text,
                nextMessage.attachments,
                creationRequest: nextMessage.creationRequest,
                additionalSystemReminders: nextMessage.systemReminders,
                selectedSkillMetadata: nextMessage.skillMetadata,
              ),
            );
            break; // Process one at a time across all sessions
          }
        }
      }
    } finally {
      _processingQueueInProgress = false;
    }
  }

  bool _shouldPrepareTranscript(AiSession? session) {
    if (session == null) return false;
    final messageCount = session.messages.isNotEmpty
        ? session.messages.length
        : session.statistics.totalMessageCount;
    return messageCount >= _transcriptPreparationThreshold;
  }

  bool _isTranscriptReadyForReveal(String sessionId) {
    final controller = _observedSessionController;
    if (controller == null) {
      return true;
    }
    final session = controller.sessionById(sessionId);
    if (session == null) {
      return true;
    }
    if (controller.isSessionMessagesHydrating(sessionId)) {
      return false;
    }
    return session.messages.isNotEmpty ||
        session.statistics.totalMessageCount <= 0 ||
        !session.hasMoreHistoricalMessages;
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

  // Frame-driven placeholder dismissal. We wait for both the selected
  // session's initial message window to hydrate and a few rendered frames to
  // pass; only then do we mount the real transcript tree.  This keeps slow
  // SQLite / very long sessions from dropping the mask while the expensive
  // first transcript build is still queued.
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
        final ready = _isTranscriptReadyForReveal(expectedSessionId);
        if (ready && remainingFrames <= 0) {
          finish();
          return;
        }
        if (stopwatch.elapsed >= _transcriptPreparationHardTimeout) {
          finish();
          return;
        }
        scheduleNextFrame(ready ? remainingFrames - 1 : remainingFrames);
      });
    }

    scheduleNextFrame(_transcriptPreparationFrameBudget);

    // Safety net in case post-frame callbacks stop firing (e.g. the route is
    // backgrounded) or a storage fault leaves hydration stuck.  It is long
    // enough not to mask ordinary slow-disk hydration, but prevents a
    // permanent overlay.
    Future<void>.delayed(_transcriptPreparationHardTimeout, finish);
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
    _composerDraftsBySessionId[_composerDraftKeyForSessionId(
      sessionId,
    )] = _ComposerDraftState(
      text: resolvedText,
      attachments: resolvedAttachments,
      creationRequest: resolvedCreationRequest,
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
        left.pitch == right.pitch;
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
        // 2026-05-17：用户正在拖动 transcript 时，禁止任何 layout-change /
        // composer 折叠 / 流式 token 触发的 auto-follow 调度，避免那道
        // "把视口往下拽" 的力与用户上滑手势产生拉锯，造成抽搐 / 鬼畜。
        _userScrollInProgress ||
        // 2026-06-07 修复：桌面端 WebView 平台视图可能拦截 PointerScrollEvent，
        // 导致 _userScrollInProgress 未被置位。用 _hasRecentScrollActivity 兜底。
        _hasRecentScrollActivity();
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
      // 2026-05-23 (修复 后台→前台 跳底)：应用被从后台拉回前台后，
      // 活跃 transcript 可能处于「分帧 drip」状态（后台期间流式下发了
      // 一堆消息但未完全物化），此时 maxScrollExtent 只反映「已被
      // 允许看见」的尾部。跳底之前必须先冲刷 drip，以给后面的
      // _scheduleScrollToBottom 提供真实的 maxScrollExtent。同时打开
      // settle passes，让 markdown 异步解析 / 代码高亮后续帧为高度
      // 增长还能追上。
      final activeSessionId = _activeTranscriptSessionId;
      var flushedDrip = false;
      if (activeSessionId != null && activeSessionId.isNotEmpty) {
        flushedDrip = _TranscriptScrollDispatcher.instance.flushDripFor(
          activeSessionId,
        );
      }
      final shouldForce =
          _pendingForcedScrollToBottom || _queuedForcedScrollToBottom;
      if (shouldForce || flushedDrip) {
        _scheduleScrollToBottom(force: shouldForce);
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
    final position = _activeMessageScrollPosition();
    if (position == null) return;
    if (_isProgrammaticMessageScrollInProgress()) {
      return;
    }
    // 2026-05-26 (重构): 彻底移除 listener 中的 delta 判定逻辑。
    // ScrollController listener 无法可靠区分「用户上滑」和「弹簧回弹/布局沉降」，
    // 基于 delta 的启发式检测已经历多轮修补仍无法根除误判。根本原因是 listener
    // 缺少 ScrollNotification 携带的 dragDetails / UserScrollNotification.direction
    // 等精确元数据。此后 listener 不再越俎代庖做暂停/恢复决策，该职责完全交给
    // _handleMessageScrollNotification，它拥有完整的用户意图分类信息。
    //
    // listener 仅保留同步 _syncAutoFollowPausedState（UI 状态一致性）职责。
    //
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
    // 2026-05-21：只有 Listener 真实捕获到 PointerScrollEvent 后，才把
    // 无 dragDetails 的 start/update/overscroll 归类为鼠标滚轮 / 触控板
    // 滚动。流式内容增高、Sliver 几何修正同样会产生无 dragDetails 的
    // scroll notification；若继续一概当作用户输入，会把贴底跟随误判成
    // "用户正在滚动"，导致 AI 增量输出不再及时追到最新消息。
    final recentPointerSignalScroll = _hasRecentPointerSignalScrollActivity();
    final implicitPointerSignalScroll =
        !_isProgrammaticMessageScrollInProgress() &&
        recentPointerSignalScroll &&
        (notification is ScrollStartNotification ||
            notification is ScrollUpdateNotification ||
            notification is OverscrollNotification);
    final userScrollActivity =
        explicitUserScroll || implicitPointerSignalScroll;
    if (userScrollActivity) {
      _lastScrollActivityAt = DateTime.now();
      if (!implicitPointerSignalScroll || explicitUserScroll) {
        _markUserScrollInProgress();
      }
      if (explicitUserScrollStart) {
        _userDragActive = true;
      }
    } else if (userScrollEnded) {
      _userDragActive = false;
      _scheduleUserScrollEndGrace();
    }
    if (_isProgrammaticMessageScrollInProgress()) {
      if (!explicitUserScroll) {
        return false;
      }
      _cancelProgrammaticAutoFollowScroll(
        keepPixels: notification.metrics.pixels,
      );
    }
    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (!_autoFollowEnabled && userScrollActivity) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    // 2026-05-24 「暂停」阈值采用滞回：只有距离底部 > 96 px 才算「真
    // 的离开底部」。加载更多历史后，markdown / 高亮异步完成会让
    // `maxScrollExtent` 在数十像素间反复变动；没有滞回的话，`distanceToBottom`
    // 会在 32 阈值上下反复穿越，造成「靠近底部/离开底部」高频反转、
    // 「跳到最新」按钮、自动跟随状态闪烁，从UI上看就是「消息盒子在抽搐」。
    // 「明显上滑」（`userScrolledUpwardFromBottom` / `pointerSignalScrolledUpwardFromBottom`）
    // 仍会在任何距离下触发暂停，保留「轻微上抨也能暂停」的用户意图。
    final reallyAwayFromBottom = distanceToBottom > _autoFollowPauseHysteresis;
    final userScrolledAwayFromBottom =
        reallyAwayFromBottom && userScrollActivity;
    // 2026-05-02: Honor the user's mental model — "any deliberate upward
    // scroll while a new message could arrive should pause auto-follow,
    // even if I'm only a few pixels above the floor". Without this, a
    // tiny manual upward nudge that lands within the 32 px tolerance
    // window leaves the transcript silently re-following the next chunk
    // and yanks the viewport away from the line the user just stopped
    // at. We detect the gesture via the `UserScrollNotification.direction
    // == reverse` signal (vertical list: reverse = pixels decreasing =
    // user revealing earlier content) and require strictly-positive
    // distance-to-bottom so a true bottom-pin scroll-end isn't treated
    // as a pause request.
    final userScrolledUpwardFromBottom =
        notification is UserScrollNotification &&
        notification.direction == ScrollDirection.reverse &&
        userScrollActivity &&
        !_isProgrammaticMessageScrollInProgress();
    final pointerSignalScrolledUpwardFromBottom =
        implicitPointerSignalScroll &&
        notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) < -0.5;
    final explicitUserScrollUpward =
        explicitUserScrollUpdate && (notification.scrollDelta ?? 0) < -0.5;
    if (userScrolledAwayFromBottom ||
        userScrolledUpwardFromBottom ||
        pointerSignalScrolledUpwardFromBottom ||
        explicitUserScrollUpward) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      _syncAutoFollowPausedState();
      return false;
    }
    _syncAutoFollowPausedState();
    return false;
  }

  void _selectSection(AppSection section) {
    if (section != AppSection.workspace) {
      unawaited(_ttsPlaybackService.stop());
    }
    setState(() {
      _selectedSection = section;
      // 2026-05-19 — 切回 workspace 板块时强制清掉残留的「转换中」遮罩。
      // 当用户从 workspace（曾经触发过一次 prep 流程）切到其他板块、再
      // 切回 workspace 时，`_WorkspaceView` 是一棵刚 mount 的全新子树，
      // 老 `_SessionTranscript` 早已被 dispose。新 transcript 在
      // initState 里就会同步物化 render entries 并 jumpToBottom，根本
      // 不需要再走 prep placeholder；但如果 `_preparingTranscriptSessionId`
      // 还指向当前 session（比如刚才 prep 还没走完就被切走、frame 回调
      // 提前 return），新 transcript 会被 AnimatedOpacity 覆盖成空白
      // `SizedBox.expand()`，呈现"消息卡片消失"的错觉。
      if (section == AppSection.workspace &&
          _preparingTranscriptSessionId != null) {
        _preparingTranscriptSessionId = null;
        _transcriptPreparationGeneration += 1;
      }
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
      // 2026-05-23 (修复)：点击「跳到最新」时，必须先把 transcript
      // 可能在跑的 drip 一次性冲刷为全量 tail，避免“跳到当前可见
      // 尾部→drip 再露出一条→再点一下”的反复物化概率。
      final activeSessionId = _activeTranscriptSessionId;
      if (activeSessionId != null && activeSessionId.isNotEmpty) {
        _TranscriptScrollDispatcher.instance.flushDripFor(activeSessionId);
      }
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
      if (hasModifier && !hw.isShiftPressed && !hw.isAltPressed) {
        unawaited(_tryPasteImageFromClipboard());
        // Intentionally fall through (return ignored) so the TextField can
        // still paste text if the clipboard happens to carry both.
      }
    }
    final composerState = _composerPanelState;
    // Escape dismisses the @ mention overlay if it is showing.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (composerState != null && composerState._atMentionOverlay != null) {
        composerState._userDismissAtMentionOverlay();
        return KeyEventResult.handled;
      }
      if (composerState != null && composerState._skillPickerOverlay != null) {
        composerState._userDismissSkillPickerOverlay();
        return KeyEventResult.handled;
      }
    }
    if (composerState != null && composerState._atMentionOverlay != null) {
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
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          _showHomeSnackBarWithMessenger(
            context,
            messenger,
            SnackBar(
              content: Text(
                '${AppLocalizations.of(context)!.fileMutationUndone}: '
                '${r.filePath}',
              ),
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
                  _showHomeSnackBar(
                    context,
                    SnackBar(
                      content: Text(msg),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          );
        }
        return;
      }
    }
  }

  Future<void> _activateSession(String sessionId) async {
    final sessionController = context.read<AiSessionController>();
    if (sessionController.currentSessionId == sessionId) {
      if (_selectedSection != AppSection.workspace) {
        setState(() {
          _selectedSection = AppSection.workspace;
          _preparingTranscriptSessionId = null;
          _transcriptPreparationGeneration += 1;
        });
        _clearPendingAutoFollowState();
        _armAutoFollowToBottom();
        _scheduleScrollToBottom(force: true);
      }
      return;
    }
    await _ttsPlaybackService.stop();
    // Devtools / Timeline marker: lets us measure first-open latency on
    // real sessions without sprinkling debug prints. Pairs with the
    // `openhand.boot.*` markers in main.dart.
    developer.Timeline.startSync(
      'openhand.session.open',
      arguments: <String, Object?>{'sessionId': sessionId},
    );
    try {
      final activationGeneration = ++_sessionActivationGeneration;
      // 阶段㉒ — 同步预亮 placeholder 防首帧爆裂：
      // 之前流程是「点击会话 → selectSession 触发 notifyListeners →
      // build 同帧把新 transcript 直接 mount → 等下一帧 listener 才设
      // _preparingTranscriptSessionId」，导致用户看见 1 帧"光秃秃的真
      // 实 transcript 在同步堆 N 张消息卡片"，正是 ANR 主因。
      // 现在在调 selectSession 之前同步置位，让接下来的 build 直接渲染
      // placeholder 而不是真实 transcript，把 mount 延后到 placeholder
      // 反向淡出之后；与 _scheduleTranscriptReveal 的帧预算 + 320ms
      // 兜底配合。极小会话 (<15 条) 跳过本路径，照旧无闪烁直接 mount。
      AiSession? targetSession;
      for (final candidate in sessionController.sessions) {
        if (candidate.id == sessionId) {
          targetSession = candidate;
          break;
        }
      }
      if (_shouldPrepareTranscript(targetSession) &&
          _preparingTranscriptSessionId != sessionId) {
        setState(() {
          _preparingTranscriptSessionId = sessionId;
        });
      }
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
      if (_selectedSection != AppSection.workspace) {
        setState(() {
          _selectedSection = AppSection.workspace;
        });
      }
      _clearPendingAutoFollowState();
      _armAutoFollowToBottom();
      _scheduleScrollToBottom(force: true);
    } finally {
      developer.Timeline.finishSync();
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

  Future<MachineExpertDialogResult?> _showMachineExpertDialog({
    String? initialTask,
    bool useGlobalDefault = false,
  }) async {
    final settingsController = context.read<SettingsController>();
    final selectedModel = useGlobalDefault
        ? settingsController.selectedAiModel
        : _effectiveModelForSession(
            settingsController,
            context.read<AiSessionController>().currentSession,
          );
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
    await _applyNewSessionModelSelection(
      providerConfigId: result.selectedModelConfigId,
      modelId: result.selectedModelId,
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

  Future<bool> _createSessionFromDialog({
    AiSessionRuntimeContext? runtimeContext,
  }) async {
    final templateId = await _showThreadTemplateDialog();
    if (!mounted || templateId == null) {
      return false;
    }
    if (templateId == 'machine_expert') {
      final result = await _showMachineExpertDialog(useGlobalDefault: true);
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
        silentLog(
          'openhand_home_page',
          'initialize HE persistence directories',
          error,
          stack,
        );
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
      unawaited(
        _generateHardnessAutoTitle(
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
    final created = await _createSession(
      templateId: 'web_reverse_expert',
      runtimeContext: runtimeContext,
      initialMode: initialMode,
      initialFullAccessPermission: initialFullAccessPermission,
    );
    if (!created || !mounted) return false;
    final sessionController = context.read<AiSessionController>();
    final session = sessionController.currentSession;
    if (session == null) return created;
    _beginPendingAutoStartSubmission(session.id);
    _replaceComposerText('');
    await _applyNewSessionModelSelection(
      sessionId: session.id,
      providerConfigId: setup.selectedModelConfigId,
      modelId: setup.selectedModelId,
    );
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    // 把 user-data-dir 在 session.id 就绪后改写为 `<root>/profile_<browser>_<sid>`，
    // 这样每个会话各占一个 profile 目录，从源头规避另一个 Chrome 实例
    // 抓着同一 user-data-dir 时触发的 "Profile is in use" 锁导致 CDP 起不来。
    final sessionScopedUserDataDir =
        '$userDataDirRoot/profiles/${setup.config.browserKind.id}_${session.id}';
    final scopedConfig = setup.config.copyWith(
      userDataDir: sessionScopedUserDataDir,
    );
    // 写入 metadata，便于 SessionDetailPage / 调试胶囊定位 controller。
    await sessionController.updateSessionMetadata(session.id, <String, Object?>{
      'web_reverse_config': scopedConfig.toJson(),
    });
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    // 启动 controller。
    final controller = WebReverseSessionController(
      config: scopedConfig,
      executablePath: setup.executablePath,
      artifactsRootDir: '$userDataDirRoot/sessions/${session.id}',
    );
    _webReverseControllers[session.id] = controller;
    controller.addListener(_onWebReverseControllerChanged);
    var launchOk = false;
    var runtimePersisted = false;
    try {
      await controller.start();
      launchOk = true;
      runtimePersisted = await _persistWebReverseRuntimeMetadata(
        session.id,
        controller,
      );
    } on WebReverseLaunchException catch (error, stack) {
      silentLog(
        'openhand_home_page',
        'web reverse launch ${error.failure}',
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
      silentLog('openhand_home_page', 'web reverse start', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: '$error',
          fallback: 'Web 逆向会话启动失败',
        );
      }
    }
    if (!launchOk) {
      await _persistWebReverseRuntimeMetadata(session.id, controller);
      // 启动失败则把 dead controller 摘除，避免胶囊点击拿到残骸。
      controller.removeListener(_onWebReverseControllerChanged);
      _webReverseControllers.remove(session.id);
      _webReverseRuntimeMetadataSignatures.remove(session.id);
      _webReverseCdpMcpBridge.stopSession(session.id);
      // 必须先 await stop() 才能 dispose；旧顺序会触发
      // dispose 后 notifyListeners 断言。
      try {
        await controller.stop();
      } catch (e, st) {
        silentLog('openhand_home_page', 'web reverse stop', e, st);
      }
      controller.dispose();
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
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n...';
  }

  void _onWebReverseControllerChanged() {
    if (!mounted) return;
    for (final entry in _webReverseControllers.entries) {
      if (!entry.value.isBrowserAlive) {
        _webReverseCdpMcpBridge.stopSession(entry.key);
      }
    }
    setState(() {});
    _scheduleWebReverseRuntimeMetadataSync();
  }

  void _disposeWebReverseControllerAfterStop(
    String sessionId,
    WebReverseSessionController controller,
  ) {
    controller.removeListener(_onWebReverseControllerChanged);
    unawaited(
      (() async {
        try {
          await controller.stop();
        } catch (error, stack) {
          silentLog(
            'openhand_home_page',
            'dispose web reverse controller $sessionId',
            error,
            stack,
          );
        } finally {
          controller.dispose();
        }
      })(),
    );
  }

  // ── Android Reverse ─────────────────────────────────────────────────────

  AndroidReverseSessionController? androidReverseControllerFor(
    String sessionId,
  ) => _androidReverseControllers[sessionId];

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
      initialObjective: _webReverseInitialObjectiveFromPrompt(initialPrompt),
      availableModels: settingsController.aiModels,
      recentModelSelections: settingsController.recentModelSelections,
      initialSelectedModelConfigId: initialModel?.id,
      initialSelectedModelId: initialModel?.modelId,
    );
    if (!mounted || setup == null) return false;
    final created = await _createSession(
      templateId: 'android_reverse_expert',
      runtimeContext: runtimeContext,
      initialMode:
          initialMode ??
          AiSessionMode.fromStorage(settingsController.aiDefaultSessionMode),
      initialFullAccessPermission:
          initialFullAccessPermission ??
          settingsController.aiDefaultFullAccessPermission,
    );
    if (!created || !mounted) return false;
    final sessionController = context.read<AiSessionController>();
    final session = sessionController.currentSession;
    if (session == null) return created;
    _beginPendingAutoStartSubmission(session.id);
    _replaceComposerText('');
    final config = setup.config;
    await _applyNewSessionModelSelection(
      sessionId: session.id,
      providerConfigId: setup.selectedModelConfigId,
      modelId: setup.selectedModelId,
    );
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    await sessionController.updateSessionMetadata(session.id, <String, Object?>{
      'android_reverse_config': config.toJson(),
    });
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    final controller = AndroidReverseSessionController(
      config: config,
      artifactsRootDir:
          '${OpenHandPaths.defaultRootDirectoryPath()}/android_reverse/sessions/${session.id}',
    );
    _androidReverseControllers[session.id] = controller;
    controller.addListener(_onAndroidReverseControllerChanged);
    try {
      await controller.start();
    } catch (error, stack) {
      silentLog('openhand_home_page', 'android reverse start', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: '$error',
          fallback: 'Android 逆向会话启动失败',
        );
      }
    }
    await _persistAndroidReverseRuntimeMetadata(session.id, controller);
    if (!mounted) {
      _clearPendingAutoStartSubmission(session.id);
      return created;
    }
    if (_autoStartSubmissionWasStopped(session.id)) {
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
      unawaited(_persistAndroidReverseRuntimeMetadata(entry.key, entry.value));
    }
  }

  void _disposeAndroidReverseController(
    String sessionId,
    AndroidReverseSessionController controller,
  ) {
    controller.removeListener(_onAndroidReverseControllerChanged);
    unawaited(
      (() async {
        try {
          await controller.stop();
        } catch (error, stack) {
          silentLog(
            'openhand_home_page',
            'dispose android reverse controller $sessionId',
            error,
            stack,
          );
        } finally {
          _androidReverseRuntimeMetadataSignatures.remove(sessionId);
          controller.dispose();
        }
      })(),
    );
  }

  Future<bool> _persistAndroidReverseRuntimeMetadata(
    String sessionId,
    AndroidReverseSessionController controller,
  ) async {
    if (!mounted) return false;
    final metadata = _androidReverseRuntimeMetadata(controller);
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
      _androidReverseRuntimeMetadataSignatures[sessionId] = signature;
      return true;
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        'persist android reverse runtime metadata $sessionId',
        error,
        stack,
      );
      return false;
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
        'frida_dir': controller.fridaDir,
        'frida_scripts_dir': controller.fridaScriptsDir,
        'frida_output_dir': controller.fridaOutputDir,
        'frida_readme': controller.fridaReadmePath,
        'decompiled_dir': controller.decompiledDir,
        'mcp_dir': controller.mcpDir,
        'mcp_templates_json': controller.mcpTemplatesPath,
        'mcp_readme': controller.mcpReadmePath,
        'certs_dir': controller.certsDir,
        'scripts_dir': controller.scriptsDir,
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
        'find ${controller.apksDir} -maxdepth 3 -type f',
        'find ${controller.screenshotsDir} -maxdepth 2 -type f',
        'find ${controller.recordingsDir} -maxdepth 2 -type f',
        'find ${controller.fridaDir} -maxdepth 2 -type f',
        'find ${controller.fridaScriptsDir} -maxdepth 1 -type f | head -200',
        'cat ${controller.fridaReadmePath}',
        'find ${controller.decompiledDir} -maxdepth 3 -type f | head -200',
        'find ${controller.decompiledDir} -path "*/quick_scan/*" -type f | head -200',
        'find ${controller.mcpDir} -maxdepth 2 -type f | head -200',
        'cat ${controller.mcpReadmePath}',
        'cat ${controller.mcpTemplatesPath}',
        '${controller.adbOneShotScriptPath} --timeout 6 devices',
        '${controller.dynamicProbeScriptPath} --timeout 6',
        'find ${controller.certsDir} -maxdepth 3 -type f | head -200',
      ],
      'dashboard_actions': const <String>[
        'adb_devices_refresh',
        'wireless_adb_connect_disconnect',
        'adb_tcpip_5555',
        'adb_root_remount_reboot',
        'adb_forward_add_remove',
        'adb_device_field_snapshot_battery_display_storage_foreground_abi',
        'adb_device_field_report_markdown_json_artifacts',
        'adb_shell_presets',
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
        'mcp_linkage_templates_readme_adb_one_shot_artifacts',
        'android_dynamic_probe_adb_launcher_frida_preflight_artifact',
        'toolchain_install_update_uninstall_copy_commands',
        'static_quick_scan_apk_nested_flutter_native_suspicious_network_artifacts',
        'frida_script_save_metadata_artifacts',
        'frida_output_runbook_artifacts',
        'frida_server_abi_push_start_forward_copy_commands',
        'mitmproxy_jsonl_addon_network_flow_artifacts',
        'certificate_network_security_config_artifacts',
        'apk_resigning_keystore_zipalign_apksigner_artifacts',
      ],
      'dashboard_tabs': const <String>[
        'devices',
        'overview',
        'toolchain',
        'mcp_plugins',
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
      'mcp': _androidReverseMcpLinkageMetadata(),
      'plugin_runtime_prerequisites':
          _androidReversePluginRuntimePrerequisitesMetadata(),
    };
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
      for (final server in mcpController.servers) {
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
        'server_count': mcpController.servers.length,
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
      silentLog(
        'openhand_home_page',
        'build android reverse mcp linkage metadata',
        error,
        stack,
      );
      return <String, Object?>{
        'error': '$error',
        'tool_search_recommended_query':
            _androidReverseMcpFallbackToolSearchQuery,
      };
    }
  }

  Map<String, Object?> _androidReversePluginRuntimePrerequisitesMetadata() {
    try {
      final pluginController = context.read<PluginServiceController>();
      const ids = <String>['nodejs', 'python', 'pip', 'playwright'];
      final plugins = <Map<String, Object?>>[];
      for (final id in ids) {
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
        'build android reverse plugin runtime metadata',
        error,
        stack,
      );
      return <String, Object?>{'error': '$error'};
    }
  }

  bool _androidReverseContainsMcpKeyword(String raw) {
    final text = raw.toLowerCase();
    return _androidReverseMcpKeywords.any(text.contains);
  }

  String _androidReverseResolvedMcpToolName(McpServer server, McpTool tool) {
    final normalizedPrefix = _androidReverseNormalizeMcpToolToken(
      'mcp__${server.name}',
    );
    final normalizedToken = _androidReverseNormalizeMcpToolToken(tool.id);
    var candidate = '${normalizedPrefix}__$normalizedToken';
    if (candidate.length <= _androidReverseMcpRuntimeToolNameLimit) {
      return candidate;
    }
    final hash = _androidReverseStableMcpToolNameHash(tool.id);
    final allowedTokenLength =
        _androidReverseMcpRuntimeToolNameLimit -
        normalizedPrefix.length -
        hash.length -
        4;
    final preferredLength =
        allowedTokenLength > 8 && allowedTokenLength < normalizedToken.length
        ? allowedTokenLength
        : (normalizedToken.length < 24 ? normalizedToken.length : 24);
    final shortenedToken = normalizedToken.substring(0, preferredLength);
    candidate = '${normalizedPrefix}__${shortenedToken}_$hash';
    return candidate.length > _androidReverseMcpRuntimeToolNameLimit
        ? candidate.substring(0, _androidReverseMcpRuntimeToolNameLimit)
        : candidate;
  }

  String _androidReverseNormalizeMcpToolToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'tool' : sanitized;
  }

  String _androidReverseStableMcpToolNameHash(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
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
    final metadata = _webReverseRuntimeMetadata(
      controller,
      cdpMcpBridgeDiagnostic:
          cdpMcpBridgeDiagnostic ??
          _webReverseCdpMcpBridge.cachedDiagnostic(
            enabled: _webReverseCdpMcpEnabledForSession(session),
            sessionId: sessionId,
            sessionTemplateId: session?.templateId,
            controller: controller,
            existingServers: context.read<McpController>().servers,
          ),
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
      _webReverseRuntimeMetadataSignatures[sessionId] = signature;
      return true;
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        'persist web reverse runtime metadata $sessionId',
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
          '/json/version',
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
    };
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
  ) async {
    final existing = _webReverseControllers[session.id];
    if (existing != null) return existing;
    final raw = session.metadata['web_reverse_config'];
    final config = WebReverseSessionConfig.fromJson(raw);
    if (config == null) {
      if (mounted) {
        _showHomeSnackBar(
          context,
          SnackBar(
            content: Text(
              _localizedText(
                context,
                zh: '该会话缺少 web_reverse_config，请新建会话。',
                en: 'Session is missing web_reverse_config; create a new session.',
              ),
            ),
          ),
        );
      }
      return null;
    }
    // 重新探测一次，不强求是配置里的 browserKind——用户机器可能已变更。
    final probe = await WebReverseBrowserDetector().detect();
    if (!mounted) return null;
    if (!probe.isInstalled) {
      final decision = await showWebReverseInstallGuideDialog(context);
      if (decision == null ||
          decision == WebReverseInstallGuideDecision.cancelled) {
        return null;
      }
      return restoreWebReverseSession(session);
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
          'rewrite user_data_dir for ${session.id}',
          e,
          st,
        );
      }
    }
    final controller = WebReverseSessionController(
      config: effectiveConfig,
      executablePath: probe.executablePath!,
      artifactsRootDir:
          '${OpenHandPaths.defaultRootDirectoryPath()}/web_reverse/sessions/${session.id}',
    );
    _webReverseControllers[session.id] = controller;
    controller.addListener(_onWebReverseControllerChanged);
    var launchOk = false;
    try {
      await controller.start();
      launchOk = true;
      await _persistWebReverseRuntimeMetadata(session.id, controller);
    } on WebReverseLaunchException catch (error, stack) {
      silentLog(
        'openhand_home_page',
        'restore web reverse ${error.failure}',
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
      silentLog('openhand_home_page', 'restore web reverse', error, stack);
      if (mounted) {
        showFriendlyErrorSnackBar(
          context,
          message: '$error',
          fallback: '浏览器恢复启动失败',
        );
      }
    }
    if (!launchOk) {
      await _persistWebReverseRuntimeMetadata(session.id, controller);
      controller.removeListener(_onWebReverseControllerChanged);
      _webReverseControllers.remove(session.id);
      _webReverseRuntimeMetadataSignatures.remove(session.id);
      _webReverseCdpMcpBridge.stopSession(session.id);
      // 必须先 await stop()，stop 内部的收尾 I/O 才能在 dispose 之前完成；
      // 旧实现 unawaited(stop) + dispose() 会触发 dispose 后的 notifyListeners。
      try {
        await controller.stop();
      } catch (error, stack) {
        silentLog(
          'openhand_home_page',
          'restore web reverse stop',
          error,
          stack,
        );
      }
      controller.dispose();
      return null;
    }
    return controller;
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
    _hardnessSessionSaveDebouncer.cancel();
    if (immediate) {
      unawaited(_hardnessSessionStore.save(record).catchError((_) {}));
      return;
    }
    _hardnessSessionSaveDebouncer.schedule(() {
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
      onToolSearchLoaded: _handleHardnessToolSearchLoaded,
      onPhaseEnded: _handleHardnessPhaseEnded,
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

  Future<void> _generateHardnessAutoTitle(
    String sessionId,
    HardnessSessionConfig config, {
    required String expectedCurrentTitle,
  }) async {
    final settingsController = context.read<SettingsController>();
    if (!settingsController.aiAutoTitleEnabled) {
      return;
    }
    final model = _resolveHardnessAutoTitleModel(
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
      final current = _persistedHardnessSession;
      if (current == null || current.id != sessionId) return;
      if (current.title != expectedCurrentTitle) {
        return;
      }
      final updated = current.copyWith(
        title: generatedTitle,
        updatedAt: DateTime.now().toUtc(),
      );
      unawaited(_hardnessSessionStore.save(updated).catchError((_) {}));
      setState(() {
        _persistedHardnessSession = updated;
      });
    } catch (error, stack) {
      silentLog('openhand_home_page', 'generate HE auto title', error, stack);
    }
  }

  AiModelConfig? _resolveHardnessAutoTitleModel({
    required HardnessSessionConfig config,
    required SettingsController settingsController,
  }) {
    for (final roleConfig in <HardnessRoleConfig>[
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
    final baseMcpServers = mcpController.servers;
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
      microCompressionEnabled: settingsController.aiMicroCompressionEnabled,
      messageContentFormat: settingsController.aiMessageContentFormat,
      htmlRenderFallback: settingsController.aiHtmlRenderFallback,
      htmlContentRichness: settingsController.aiHtmlContentRichness,
      appThemeBrightness: effectiveBrightness.name,
      appThemePresetName: settingsController.themePreset.storageValue,
      appThemePrimaryColor:
          '#${settingsController.themePreset.seedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      writeToolSummaryMaxChars: settingsController.aiWriteToolSummaryMaxChars,
      aiInputCacheEnabled: settingsController.aiInputCacheEnabled,
      aiInputCacheUpdateMode: settingsController.aiInputCacheUpdateMode,
      aiInputCacheUpdateInterval: settingsController.aiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount:
          settingsController.aiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions:
          settingsController.aiInputCacheBreakpointPositions,
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      maxRecentErrors: settingsController.aiMaxRecentErrors,
      maxPlanHistoryEntries: settingsController.aiMaxPlanHistoryEntries,
      maxTruncationContinuations:
          settingsController.aiMaxTruncationContinuations,
      estimatedCharactersPerToken:
          settingsController.aiEstimatedCharactersPerToken,
      maxToolOutputChars: settingsController.aiMaxToolOutputChars,
      writeConfirmationTimeoutMs:
          settingsController.aiWriteConfirmationTimeoutMs,
      fastPathWriteAnalysisThreshold:
          settingsController.aiFastPathWriteAnalysisThreshold,
      maxHookTextCharacters: settingsController.aiMaxHookTextCharacters,
      subprocessGracefulShutdownMs:
          settingsController.subprocessGracefulShutdownMs,
      bashOutputMaxBytes: settingsController.bashOutputMaxBytes,
      maxConcurrentTools: settingsController.maxConcurrentTools,
      webFetchMaxResponseBytes: settingsController.aiWebFetchMaxResponseBytes,
      webFetchMaxRedirects: settingsController.aiWebFetchMaxRedirects,
      webFetchMaxCacheEntries: settingsController.aiWebFetchMaxCacheEntries,
      attachmentMaxInlineImageDimension:
          settingsController.aiAttachmentMaxInlineImageDimension,
      attachmentMaxTextRawBytes: settingsController.aiAttachmentMaxTextRawBytes,
      attachmentMaxPdfRawBytes: settingsController.aiAttachmentMaxPdfRawBytes,
      attachmentMaxImageRawBytes:
          settingsController.aiAttachmentMaxImageRawBytes,
      chatMaxStreamLineBufferBytes:
          settingsController.aiChatMaxStreamLineBufferBytes,
      imageSizeLimitBytes: settingsController.aiImageSizeLimitBytes,
      memoryEnabled: settingsController.memoryEnabled,
      mcpLazyLoadingMode: settingsController.mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens:
          settingsController.mcpLazyLoadingThresholdTokens,
      builtinToolLazyLoadingMode: settingsController.builtinToolLazyLoadingMode,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      connectTimeoutSeconds: settingsController.aiConnectTimeoutSeconds,
      responseTimeoutSeconds: settingsController.aiResponseTimeoutSeconds,
      streamIdleTimeoutSeconds: settingsController.aiStreamIdleTimeoutSeconds,
      streamMaxCharsPerSecond: settingsController.aiStreamMaxCharsPerSecond,
      streamThrottleEnabled: settingsController.aiStreamThrottleEnabled,
      streamThrottleAutoMode: settingsController.aiStreamThrottleAutoMode,
      streamThrottleDurationSeconds:
          settingsController.aiStreamThrottleDurationSeconds,
      streamMaxMessageCardsPerSecond:
          settingsController.aiStreamMaxMessageCardsPerSecond,
      autoTitleEnabled: settingsController.aiAutoTitleEnabled,
      autoTitleFetchMode: settingsController.aiAutoTitleFetchMode,
      autoTitleMaxRetryCount: settingsController.aiAutoTitleMaxRetryCount,
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
      sandboxSettings: settingsController.aiSandboxSettings,
      availableSkills: skillsController.skills,
      availableMcpServers: availableMcpServers,
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
      builtinToolConfigs: settingsController.builtinToolConfigs,
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
    final baseMcpServers = mcpController.servers;
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
    final todayLocalDate = _formatLocalDate(now);
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
      settingsController.aiSandboxSettings.toJson().toString(),
      settingsController.builtinToolLazyLoadingMode,
      settingsController.mcpLazyLoadingThresholdTokens,
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

  String _formatLocalDate(DateTime now) {
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
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
      microCompressionEnabled: settingsController.aiMicroCompressionEnabled,
      messageContentFormat: settingsController.aiMessageContentFormat,
      htmlRenderFallback: settingsController.aiHtmlRenderFallback,
      htmlContentRichness: settingsController.aiHtmlContentRichness,
      appThemeBrightness: _resolveEffectiveBrightness(context).name,
      appThemePresetName: settingsController.themePreset.storageValue,
      appThemePrimaryColor:
          '#${settingsController.themePreset.seedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      writeToolSummaryMaxChars: settingsController.aiWriteToolSummaryMaxChars,
      aiInputCacheEnabled: settingsController.aiInputCacheEnabled,
      aiInputCacheUpdateMode: settingsController.aiInputCacheUpdateMode,
      aiInputCacheUpdateInterval: settingsController.aiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount:
          settingsController.aiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions:
          settingsController.aiInputCacheBreakpointPositions,
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      maxRecentErrors: settingsController.aiMaxRecentErrors,
      maxPlanHistoryEntries: settingsController.aiMaxPlanHistoryEntries,
      maxTruncationContinuations:
          settingsController.aiMaxTruncationContinuations,
      estimatedCharactersPerToken:
          settingsController.aiEstimatedCharactersPerToken,
      maxToolOutputChars: settingsController.aiMaxToolOutputChars,
      writeConfirmationTimeoutMs:
          settingsController.aiWriteConfirmationTimeoutMs,
      fastPathWriteAnalysisThreshold:
          settingsController.aiFastPathWriteAnalysisThreshold,
      maxHookTextCharacters: settingsController.aiMaxHookTextCharacters,
      subprocessGracefulShutdownMs:
          settingsController.subprocessGracefulShutdownMs,
      bashOutputMaxBytes: settingsController.bashOutputMaxBytes,
      maxConcurrentTools: settingsController.maxConcurrentTools,
      webFetchMaxResponseBytes: settingsController.aiWebFetchMaxResponseBytes,
      webFetchMaxRedirects: settingsController.aiWebFetchMaxRedirects,
      webFetchMaxCacheEntries: settingsController.aiWebFetchMaxCacheEntries,
      attachmentMaxInlineImageDimension:
          settingsController.aiAttachmentMaxInlineImageDimension,
      attachmentMaxTextRawBytes: settingsController.aiAttachmentMaxTextRawBytes,
      attachmentMaxPdfRawBytes: settingsController.aiAttachmentMaxPdfRawBytes,
      attachmentMaxImageRawBytes:
          settingsController.aiAttachmentMaxImageRawBytes,
      chatMaxStreamLineBufferBytes:
          settingsController.aiChatMaxStreamLineBufferBytes,
      imageSizeLimitBytes: settingsController.aiImageSizeLimitBytes,
      memoryEnabled: settingsController.memoryEnabled,
      mcpLazyLoadingMode: settingsController.mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens:
          settingsController.mcpLazyLoadingThresholdTokens,
      builtinToolLazyLoadingMode: settingsController.builtinToolLazyLoadingMode,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      connectTimeoutSeconds: settingsController.aiConnectTimeoutSeconds,
      responseTimeoutSeconds: settingsController.aiResponseTimeoutSeconds,
      streamIdleTimeoutSeconds: settingsController.aiStreamIdleTimeoutSeconds,
      streamMaxCharsPerSecond: settingsController.aiStreamMaxCharsPerSecond,
      streamThrottleEnabled: settingsController.aiStreamThrottleEnabled,
      streamThrottleAutoMode: settingsController.aiStreamThrottleAutoMode,
      streamThrottleDurationSeconds:
          settingsController.aiStreamThrottleDurationSeconds,
      streamMaxMessageCardsPerSecond:
          settingsController.aiStreamMaxMessageCardsPerSecond,
      autoTitleEnabled: settingsController.aiAutoTitleEnabled,
      autoTitleFetchMode: settingsController.aiAutoTitleFetchMode,
      autoTitleMaxRetryCount: settingsController.aiAutoTitleMaxRetryCount,
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
      sandboxSettings: settingsController.aiSandboxSettings,
      availableSkills: availableSkills ?? skillsController.skills,
      availableMcpServers: availableMcpServers ?? mcpController.servers,
      mcpToolCatalogsByServerName: <String, McpToolCatalog>{
        for (final server in availableMcpServers ?? mcpController.servers)
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
    showFriendlyErrorSnackBar(
      context,
      message: errorMessage,
      fallback: l10n.chatRequestFailed,
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
    return showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(
        context,
        zh: '启用完全访问权限？',
        en: 'Enable Full Access?',
      ),
      message: _localizedText(
        context,
        zh: '在完全访问权限模式下，OpenHand 可无需审批直接编辑计算机上的任意文件并运行网络命令。\n\n启用完全访问权限前请谨慎评估。此操作将显著增加数据丢失、泄露或异常行为的风险。',
        en: 'With Full Access enabled, OpenHand can edit any file and run commands without requiring your explicit approval.\n\nPlease evaluate carefully before enabling. This action significantly increases the risk of data loss, leakage, or unexpected behavior.',
      ),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
      confirmLabel: _localizedText(context, zh: '是，仍然继续', en: 'Yes, Continue'),
      destructive: true,
    );
  }

  void _queueMessageForSession({
    required String sessionId,
    required String prompt,
    required List<_ComposerAttachmentDraft> pendingAttachments,
    required AiCreationRequest creationRequest,
    required List<String> additionalSystemReminders,
    required Map<String, Object?>? selectedSkillMetadata,
  }) {
    final queued = _QueuedMessage(
      text: prompt,
      attachments: pendingAttachments,
      creationRequest: creationRequest,
      systemReminders: additionalSystemReminders,
      skillMetadata: selectedSkillMetadata,
    );
    setState(() {
      final q = _queuedMessagesBySessionId[sessionId] ?? <_QueuedMessage>[];
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
    OpenHandSnackBar.hideCurrentOn(ScaffoldMessenger.of(context));
    _showHomeSnackBar(
      context,
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
      OpenHandSnackBar.showError(context, l10n.aiModelSelectionRequired);
      return;
    }
    if (pendingAttachments.isNotEmpty &&
        !_selectedModelSupportsAttachments(selectedModel)) {
      _showHomeSnackBar(
        context,
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
        _showHomeSnackBar(
          context,
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
    // Warn (non-blocking) when the user attaches images but the model is
    // not detected as supporting inline image content.
    if (pendingAttachments.any(
          (a) => aiAttachmentKindForPath(a.filePath) == AiAttachmentKind.image,
        ) &&
        !AiProtocolRegistry.supportsInlineImages(selectedModel)) {
      _showHomeSnackBar(
        context,
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

    MachineExpertDialogResult? machineExpertConfig;
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
    // Consume any pending skill selection from the composer.  The reminder is
    // carried as hidden metadata on the outgoing LLM turn (via the existing
    // `aiHookSystemRemindersMetadataKey` channel) so the stored user message
    // content shown in the transcript bubble remains exactly what the user
    // typed, without leaking the `<skill-manifest>` XML block.
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
      callerPreflightTimingsMs: submitPreflightTimingsMs,
      additionalSystemReminders: additionalSystemReminders,
      selectedSkillMetadata: skillDisplayMetadata,
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
    Map<String, int> callerPreflightTimingsMs = const <String, int>{},
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    List<String> additionalSystemReminders = const <String>[],
    Map<String, Object?>? selectedSkillMetadata,
    bool restoreDraftOnLocalStop = true,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final l10n = AppLocalizations.of(context)!;
    await sessionController.ensureSessionMessagesHydrated(targetSessionId);
    if (!mounted) {
      return;
    }
    final initialSession = sessionController.sessions
        .cast<AiSession?>()
        .firstWhere((s) => s?.id == targetSessionId, orElse: () => null);
    final selectedModel = _effectiveModelForSession(
      settingsController,
      initialSession,
    );
    if (selectedModel == null) return;
    if (initialSession?.templateId == WebReverseCdpMcpBridge.templateId &&
        _webReverseControllers[targetSessionId] == null) {
      await restoreWebReverseSession(initialSession!);
      if (!mounted) return;
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
    _scheduleScrollToBottom(force: true);
    bool submissionWasStopped() =>
        _locallyStoppedSubmissionSerialsBySessionId[targetSessionId] ==
        submissionSerial;
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
        return;
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
        return;
      }
      if (submissionWasStopped()) {
        restoreSubmittedDraftIfNeeded(localStop: true);
        return;
      }
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
      if (submissionWasStopped()) {
        restoreSubmittedDraftIfNeeded(localStop: true);
        return;
      }
      if (!sent) {
        if (submissionWasStopped()) {
          restoreSubmittedDraftIfNeeded(localStop: true);
          return;
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
        return;
      }
      _removeComposerDraftForSession(targetSessionId);
      await sessionController.completeEditingMessage();
      if (!mounted) {
        return;
      }
      if (sessionController.didCompressInLastSendForSession(targetSessionId)) {
        OpenHandSnackBar.showInfo(context, l10n.threadCompressionNotice);
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
      if (mounted && (!submissionWasStopped() || restoreDraftOnLocalStop)) {
        restoreSubmittedDraftIfNeeded(localStop: submissionWasStopped());
      }
      if (mounted) {
        final errorMessage = '$error'.trim();
        _showHomeSnackBar(
          context,
          SnackBar(
            content: Text(
              errorMessage.isEmpty ? l10n.chatRequestFailed : errorMessage,
            ),
          ),
        );
      }
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
        _processMessageQueueIfNeeded(sessionController);
      } else if (isActiveSubmission &&
          _submittingSessionId == targetSessionId) {
        _submittingSessionId = null;
      }
    }
  }

  void _replaceComposerText(String value) {
    _replaceComposerTextAndRefocus(value, requestFocusAfter: false);
  }

  /// 2026-06-02 — 程序化改写 composer 文本的统一入口。
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

  /// 2026-06-02 — 给 [InputRepairService] 注册的软恢复钩子：当 framework
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
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      context.read<AiSessionController>().currentSession,
    );
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
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '剪贴板图片超出 10MB 单文件上限，已忽略。',
              en: 'Clipboard image exceeds the 10MB per-attachment limit and was ignored.',
            ),
          ),
        ),
      );
      return;
    }
    String tempPath;
    try {
      final tempDir = await Directory.systemTemp.createTemp('openhand_paste_');
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
    final settingsController = context.read<SettingsController>();
    final selectedModel = _effectiveModelForSession(
      settingsController,
      context.read<AiSessionController>().currentSession,
    );
    if (selectedModel == null) {
      OpenHandSnackBar.showError(context, l10n.aiModelSelectionRequired);
      return;
    }
    if (!_selectedModelSupportsAttachments(selectedModel)) {
      OpenHandSnackBar.showInfo(
        context,
        _localizedText(
          context,
          zh: '当前模型不支持附件。',
          en: 'The selected model does not support attachments.',
        ),
      );
      return;
    }
    final remainingSlots =
        aiMessageAttachmentLimit - _pendingAttachments.length;
    if (remainingSlots <= 0) {
      OpenHandSnackBar.showInfo(
        context,
        _localizedText(
          context,
          zh: '单条消息最多携带 20 个附件。',
          en: 'A single message supports at most 20 attachments.',
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
      _showHomeSnackBar(
        context,
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
    final sessionId = sessionController.currentSessionId;
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
        silentLog('openhand_home_page', 'stop responding', error, stackTrace);
      }),
    );
  }

  void _stopReverseRuntimeForSession(String sessionId) {
    final webReverseController = _webReverseControllers[sessionId];
    if (webReverseController != null) {
      _webReverseCdpMcpBridge.stopSession(sessionId);
      unawaited(
        webReverseController.stop().catchError((
          Object error,
          StackTrace stack,
        ) {
          silentLog(
            'openhand_home_page',
            'stop web reverse runtime',
            error,
            stack,
          );
        }),
      );
    }
    final androidReverseController = _androidReverseControllers[sessionId];
    if (androidReverseController != null) {
      unawaited(
        androidReverseController.stop().catchError((
          Object error,
          StackTrace stack,
        ) {
          silentLog(
            'openhand_home_page',
            'stop android reverse runtime',
            error,
            stack,
          );
        }),
      );
    }
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
    if (_isProgrammaticMessageScrollInProgress()) {
      return;
    }
    if (_userScrollInProgress) {
      return;
    }
    if (_scrollToBottomAwaitingPosition) {
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
        return;
      }
      if (_userScrollInProgress) {
        return;
      }
      final shouldForce = _queuedForcedScrollToBottom;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      if (!shouldForce &&
          (!_autoFollowEnabled ||
              !_shouldAutoFollowMessages ||
              _userScrollInProgress)) {
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
          if (_userScrollInProgress) {
            return;
          }
          _scheduleScrollToBottom(
            force: shouldForce,
            animated: shouldAnimate,
            allowSettlePasses: false,
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
        _programmaticAutoFollowScrollInProgress = false;
      }

      void scheduleSettlePass() {
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
    // 2026-05-04 (修复): 仅当用户当前仍处于"贴底跟随"状态时，才在新消息
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
    // 阶段㉓ 修复：会话切换 (signature 的 sessionId 段变了) 这一次回调
    // 故意 *不消费* `_pendingForcedScrollToBottom`。原因：
    //   1. workspace_view 在同一帧的 build 里马上要把 _pendingForcedScrollToBottom
    //      作为 `jumpToBottomOnInit` 传给新挂载的 _SessionTranscript；
    //   2. 若在此处先消费，传给 transcript 的就变成 false，transcript 内
    //      的「mount 即贴底」短路径失效，要完全依赖随后的 settle 通行
    //      （8 次 = 133 ms）跟上 markdown 异步解析后还会继续增大的
    //      maxScrollExtent，长会话首屏 layout 完全稳定前 settle 已耗尽，
    //      最终视口卡在「最后一页消息列表的最旧那条」上。
    //   3. 同会话内消息追加场景 (sessionId 不变只 length/lastMessage 变)
    //      仍按原逻辑消费 + schedule，保持流式期间贴底跟随。
    final sessionIdChanged =
        previousSignature == null ||
        !previousSignature.startsWith('${session!.id}|');
    if (sessionIdChanged) {
      // 会话切换：transcript 内部已通过 jumpToBottomOnInit + 16 帧 settle
      // 自行贴底；这里再额外发一个 *jump*（非 animate） 兜底，避免与
      // transcript 的 jumpTo 互相打架。
      _scheduleAutoFollowIfNeeded(animated: false);
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
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
    if (_userScrollInProgress || !_shouldAutoFollowMessages) {
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
      // 避免滚动惯性期间 jumpTo 与弹道位置对抗产生弹跳。
      // 2026-06-07 修复：桌面端 WebView 可能吞掉 PointerScrollEvent，导致
      // isScrollingNotifier 在两 tick 间短暂为 false 时 layout-change 仍能
      // 穿透。增加 _hasRecentScrollActivity() 兜底，覆盖 trackpad 滚动的空窗期。
      if (position.isScrollingNotifier.value || _hasRecentScrollActivity()) {
        return;
      }
      _scheduleScrollToBottom(allowSettlePasses: false);
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

  String _metadataTextFingerprint(Object? value) {
    if (value == null) return '0';
    final text = value is String
        ? value
        : (() {
            try {
              return jsonEncode(value);
            } catch (_) {
              return value.toString();
            }
          })();
    if (text.isEmpty) return '0';
    final head = text.length <= 48 ? text : text.substring(0, 48);
    final tail = text.length <= 24 ? text : text.substring(text.length - 24);
    return '${text.length}:$head:$tail';
  }

  String _messageAutoFollowRenderSignature(AiSessionMessage message) {
    return [
      message.id,
      message.kind.storageValue,
      message.characterCount,
      '${boolFromValue(message.metadata[aiSessionMessageMetadataStreamingKey])}',
      '${boolFromValue(message.metadata['tool_arguments_streaming'])}',
      '${boolFromValue(message.metadata['tool_preparing'])}',
      _metadataTextFingerprint(message.metadata['tool_arguments']),
      _metadataTextFingerprint(message.metadata['tool_execution_command']),
      _toolExecutionStatus(message),
      '${_toolExecutionStdout(message).length}',
      '${_toolExecutionStderr(message).length}',
      '${_toolExecutionResult(message).length}',
      _metadataTextFingerprint(message.metadata['result_text']),
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
    for (
      var index = displayMessages.length - 1;
      index >= 0 && activeFollowParts.length < 4;
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
    final settingsController = context.read<SettingsController>();
    for (final rule in settingsController.aiAllowCommandRules) {
      if (rule.matches(request.command)) {
        return BashCommandApprovalDecision.approved;
      }
    }
    final sessionController = context.read<AiSessionController>();
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
      // null = barrier 之外触发关闭（理论上 barrierDismissible: false 已禁用，
      // 但 root navigator pop 的兜底场景仍可能发生）。视为 dismissed。
      return decision ?? BashCommandApprovalDecision.dismissed;
    } finally {
      if (effectiveSessionId != null) {
        sessionController.clearSessionAwaitingApproval(effectiveSessionId);
      }
    }
  }

  Future<BashCommandApprovalDecision> _confirmHardnessApiWriteCommand(
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
          _showHomeSnackBar(
            context,
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
          _showHomeSnackBar(
            context,
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
          _showHomeSnackBar(
            context,
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
      AppSection.pluginService => _localizedText(
        context,
        zh: '插件',
        en: 'Plugins',
      ),
      AppSection.settings => _localizedText(context, zh: '设置', en: 'Settings'),
      AppSection.hardnessSession => _localizedText(
        context,
        zh: 'Harness 会话',
        en: 'Harness Session',
      ),
    };
    _showHomeSnackBar(
      context,
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
      '/skills',
      '/memory',
      '/mcp',
    ].join('\n');
    final detail = _localizedText(
      context,
      zh: '可用本地命令：\n$commandList\n\n`/help`、`/commands`、`/feedback`、`/new`、`/status`、`/stop` 不会发给模型，而是由 OpenHand 本地处理。\n\n写命令确认：${settingsController.aiWriteCommandConfirmationEnabled ? '开启' : '关闭'}\n允许命令规则：${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\n设置文件：${settingsController.displaySettingsFilePath}\n会话目录：${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
      en: 'Available local commands:\n$commandList\n\n`/help`, `/commands`, `/feedback`, `/new`, `/status`, and `/stop` are handled locally by OpenHand instead of being sent to the model.\n\nWrite command confirmation: ${settingsController.aiWriteCommandConfirmationEnabled ? 'enabled' : 'disabled'}\nAllow command rules: ${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\nSettings file: ${settingsController.displaySettingsFilePath}\nSession directory: ${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
    );
    return showOpenHandInfoDialog(
      context: context,
      title: _localizedText(
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
        return buildOpenHandAlertDialog(
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
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showHomeSnackBarWithMessenger(
                  context,
                  scaffoldMessenger,
                  OpenHandSnackBar.success(context, copiedLabel),
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
    final submitted = await showOpenHandTextInputDialog(
      context: context,
      title: _localizedText(context, zh: '重命名线程', en: 'Rename Thread'),
      initialValue: session.title,
      hintText: _localizedText(
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
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '线程重命名失败。', en: 'Rename failed.'),
        ),
      ),
    );
  }

  void _generateTitleForSession(AiSession session) {
    final sessionController = context.read<AiSessionController>();
    final settingsController = context.read<SettingsController>();
    final userMessages = session.messages
        .where(
          (m) =>
              !m.isDeleted &&
              m.kind == AiSessionMessageKind.user &&
              m.content.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (userMessages.isEmpty) {
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '暂无用户消息可供总结',
              en: 'No user messages to summarize',
            ),
          ),
        ),
      );
      return;
    }
    final model = _effectiveModelForSession(settingsController, session);
    if (model == null) {
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(context, zh: '未配置模型', en: 'No model configured'),
          ),
        ),
      );
      return;
    }
    // 单条消息直接生成
    if (userMessages.length == 1) {
      _executeGenerateTitle(
        session: session,
        content: userMessages.first.content,
        model: model,
        sessionController: sessionController,
        settingsController: settingsController,
      );
      return;
    }
    // 多条消息时弹出选择弹窗
    _showTitleSummaryRangeDialog(
      session: session,
      userMessages: userMessages,
      model: model,
      sessionController: sessionController,
      settingsController: settingsController,
    );
  }

  Future<void> _showTitleSummaryRangeDialog({
    required AiSession session,
    required List<AiSessionMessage> userMessages,
    required AiModelConfig model,
    required AiSessionController sessionController,
    required SettingsController settingsController,
  }) async {
    final result = await showAnimatedDialog<(int, int)>(
      context: context,
      builder: (dialogContext) =>
          _TitleSummaryRangeDialog(userMessages: userMessages),
    );
    if (!mounted || result == null) return;
    final (startIdx, endIdx) = result;
    final selectedContent = userMessages
        .sublist(startIdx, endIdx + 1)
        .map((m) => m.content.trim())
        .join('\n\n');
    _executeGenerateTitle(
      session: session,
      content: selectedContent,
      model: model,
      sessionController: sessionController,
      settingsController: settingsController,
    );
  }

  Future<void> _executeGenerateTitle({
    required AiSession session,
    required String content,
    required AiModelConfig model,
    required AiSessionController sessionController,
    required SettingsController settingsController,
  }) async {
    showOpenHandLoadingDialog(
      context: context,
      message: _localizedText(
        context,
        zh: '正在生成摘要标题…',
        en: 'Generating title…',
      ),
    );
    try {
      await sessionController.generateTitleManually(
        sessionId: session.id,
        content: content,
        model: model,
        maxTitleCharacters: settingsController.aiGeneratedTitleMaxCharacters,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            _localizedText(context, zh: '标题生成成功', en: 'Title generated'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            '${_localizedText(context, zh: '标题生成失败', en: 'Title generation failed')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _deleteSession(AiSession session) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(context, zh: '删除线程', en: 'Delete Thread'),
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
    if (!mounted || deleted) {
      if (deleted) {
        _removeComposerDraftForSession(session.id);
        // 释放该会话挂着的 Web 逆向 controller（停 dock / 关 CDP / 关浏览器进程）。
        final wr = _webReverseControllers.remove(session.id);
        _webReverseRuntimeMetadataSignatures.remove(session.id);
        _webReverseCdpMcpBridge.stopSession(session.id);
        if (wr != null) {
          _disposeWebReverseControllerAfterStop(session.id, wr);
        }
      }
      return;
    }
    _showHomeSnackBar(
      context,
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
    final submitted = await showOpenHandTextInputDialog(
      context: context,
      title: _localizedText(
        context,
        zh: '重命名 Harness Engineering 会话',
        en: 'Rename Harness Session',
      ),
      initialValue: record.title,
      hintText: _localizedText(
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
      updatedAt: DateTime.now(),
    );
    setState(() => _persistedHardnessSession = updated);
    unawaited(_hardnessSessionStore.save(updated).catchError((_) {}));
  }

  Future<void> _deleteHardnessSession() async {
    final record = _persistedHardnessSession;
    if (record == null) return;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(
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
    _activeHardnessOrchestrator?.removeListener(_onHardnessOrchestratorChanged);
    _activeHardnessOrchestrator?.dispose();
    _hardnessSessionSaveDebouncer.cancel();
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
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '加载会话失败：$error',
              en: 'Failed to load session: $error',
            ),
          ),
        ),
      );
      return;
    }
    if (loaded == null || !mounted) {
      if (mounted) {
        _showHomeSnackBarWithMessenger(
          context,
          messenger,
          SnackBar(
            content: Text(
              _localizedText(
                context,
                zh: '会话不存在或已被删除。',
                en: 'Session is missing or has been deleted.',
              ),
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
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    final suggested = jsonlExportPickerSuggestedName(
      '${_sanitizeFileBasename(loaded.title)}_${loaded.id}.jsonl',
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '_exportSession.getSaveLocation',
        error,
        stack,
      );
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '无法打开保存对话框：$error',
              en: 'Unable to open save dialog: $error',
            ),
          ),
        ),
      );
      return;
    }
    if (location == null || !mounted) return;

    // Step 4: kick off the streamed export with progress UI.
    final cancelToken = ExportCancelToken();
    final progressController = ExportProgressController(
      cancelToken: cancelToken,
    );

    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context, zh: '导出会话数据', en: 'Export Session Data'),
      subtitle: _localizedText(
        context,
        zh: '正在导出 “${loaded.title}”…',
        en: 'Exporting "${loaded.title}"…',
      ),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
    );

    final destinationPath = normalizeJsonlExportPath(location.path);
    ExportResult result;
    try {
      result =
          await exportAiSessionToJsonl(
            session: loaded,
            destinationPath: destinationPath,
            cancelToken: cancelToken,
            config: config,
            onProgress: progressController.updateProgress,
          ).timeout(
            _exportTimeout,
            onTimeout: () {
              cancelToken.cancel();
              return const ExportResult(kind: ExportResultKind.failure);
            },
          );
    } catch (error, stack) {
      silentLog('openhand_home_page', '_exportSession.runExport', error, stack);
      result = ExportResult(kind: ExportResultKind.failure, error: error);
    }
    progressController.markFinished();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    progressController.dispose();

    if (!mounted) return;
    _showExportResultSnackBar(messenger, result, destinationPath);
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
    const typeGroup = XTypeGroup(label: 'JSONL', extensions: <String>['jsonl']);
    final suggested = jsonlExportPickerSuggestedName(
      '${_sanitizeFileBasename(record.title)}_${record.id}.jsonl',
    );
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog(
        'openhand_home_page',
        '_exportHardnessSession.getSaveLocation',
        error,
        stack,
      );
      if (!mounted) return;
      _showHomeSnackBarWithMessenger(
        context,
        messenger,
        SnackBar(
          content: Text(
            _localizedText(
              context,
              zh: '无法打开保存对话框：$error',
              en: 'Unable to open save dialog: $error',
            ),
          ),
        ),
      );
      return;
    }
    if (location == null || !mounted) return;

    final cancelToken = ExportCancelToken();
    final progressController = ExportProgressController(
      cancelToken: cancelToken,
    );

    final dialogFuture = showExportProgressDialog(
      context: context,
      controller: progressController,
      title: _localizedText(context, zh: '导出会话数据', en: 'Export Session Data'),
      subtitle: _localizedText(
        context,
        zh: '正在导出 “${record.title}”…',
        en: 'Exporting "${record.title}"…',
      ),
      cancelLabel: _localizedText(context, zh: '取消', en: 'Cancel'),
    );

    final destinationPath = normalizeJsonlExportPath(location.path);
    ExportResult result;
    try {
      result =
          await exportHardnessSessionToJsonl(
            record: record,
            destinationPath: destinationPath,
            cancelToken: cancelToken,
            config: config,
            onProgress: progressController.updateProgress,
          ).timeout(
            _exportTimeout,
            onTimeout: () {
              cancelToken.cancel();
              return const ExportResult(kind: ExportResultKind.failure);
            },
          );
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
    _showExportResultSnackBar(messenger, result, destinationPath);
  }

  void _showExportResultSnackBar(
    ScaffoldMessengerState messenger,
    ExportResult result,
    String destinationPath,
  ) {
    final ctx = context;
    final String message;
    late final SnackBar snackBar;
    switch (result.kind) {
      case ExportResultKind.success:
        message = _localizedText(
          ctx,
          zh: '导出成功：$destinationPath',
          en: 'Export succeeded: $destinationPath',
        );
        snackBar = OpenHandSnackBar.success(
          ctx,
          message,
          duration: const Duration(seconds: 6),
        );
        break;
      case ExportResultKind.cancelled:
        message = _localizedText(ctx, zh: '已取消导出。', en: 'Export cancelled.');
        snackBar = OpenHandSnackBar.info(ctx, message);
        break;
      case ExportResultKind.failure:
        final reason = result.error?.toString() ?? 'unknown error';
        message = _localizedText(
          ctx,
          zh: '导出失败：$reason',
          en: 'Export failed: $reason',
        );
        snackBar = OpenHandSnackBar.error(
          ctx,
          message,
          maxLines: 2,
          duration: const Duration(seconds: 6),
        );
        break;
    }
    OpenHandSnackBar.show(ctx, messenger, snackBar);
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
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) {
      return;
    }
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(context, zh: '消息内容已复制。', en: 'Message copied.'),
        ),
      ),
    );
  }

  Future<bool> _deleteMessage(AiSessionMessage message) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(context, zh: '删除消息', en: 'Delete Message'),
      message: _localizedText(
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
    _showHomeSnackBar(
      context,
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
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(context, zh: '删除此条及后续消息', en: 'Delete From Here'),
      message: _localizedText(
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
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '批量删除消息失败。', en: 'Delete failed.'),
        ),
      ),
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
      title: _localizedText(context, zh: '派生新会话', en: 'Fork Session'),
      message: _localizedText(
        context,
        zh: '将从当前会话的这条消息之后派生出一个新会话。新会话会保留这条消息及之前的内容，并舍弃之后的消息。',
        en: 'Create a new session from this point. The new session keeps this message and everything before it, and drops later messages.',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: _localizedText(context, zh: '派生', en: 'Fork'),
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
      _showHomeSnackBar(
        context,
        SnackBar(
          content: Text(
            controller.lastErrorMessage ??
                _localizedText(
                  context,
                  zh: '派生会话失败。',
                  en: 'Failed to fork session.',
                ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _armAutoFollowToBottom(notifyPausedState: false);
    });
    _showHomeSnackBar(
      context,
      SnackBar(
        content: Text(
          _localizedText(context, zh: '已派生新会话。', en: 'Session forked.'),
        ),
      ),
    );
  }

  Future<void> _cancelEditingMessage() async {
    final controller = context.read<AiSessionController>();
    final cancelled = await controller.cancelEditingMessage();
    if (!mounted || cancelled) {
      return;
    }
    _showHomeSnackBar(
      context,
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
    // 顶层注入滚动活动信号：让 transcript 子树里的 `_HtmlBubbleWebView`
    // 通过 `context.read<TranscriptScrollActivity>()` 订阅，滚动期间冻结
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
                    onGenerateTitleForSession: _generateTitleForSession,
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
                  final panelSettings = context
                      .read<SettingsController>()
                      .panelAnimationSettings;
                  final leftPaneDuration = Duration(
                    milliseconds: math.max(
                      _effectiveSwitchDuration(panelSettings).inMilliseconds,
                      240,
                    ),
                  );
                  final Widget leftPane = ClipRect(
                    child: AnimatedSwitcher(
                      duration: leftPaneDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
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
                        return _buildWorkspaceSidebarTransition(
                          child: child,
                          animation: animation,
                          settings: panelSettings,
                        );
                      },
                      child: showFileExplorer
                          ? _ContentPane(
                              key: const ValueKey<String>('file-explorer-pane'),
                              child: _FileExplorerPanel(
                                rootPath: projectRoot,
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
                      _activeFilePath != null &&
                      _openFilePaths.isNotEmpty;
                  final pageSettings = context
                      .read<SettingsController>()
                      .pageAnimationSettings;
                  final rightPaneDuration = Duration(
                    milliseconds: math.max(
                      _effectiveSwitchDuration(pageSettings).inMilliseconds,
                      280,
                    ),
                  );
                  final Widget rightPane = ClipRect(
                    child: AnimatedSwitcher(
                      duration: rightPaneDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
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
    final selectedModel = _effectiveModelForSession(
      settingsController,
      currentSession,
    );
    final transcriptHydrating =
        currentSession != null &&
        sessionController.isSessionMessagesHydrating(currentSession.id);
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
        onMessagePointerSignal: _handleMessagePointerSignal,
        currentSession: currentSession,
        liveRuntimeToolPreview: liveRuntimeToolPreview,
        transcriptHydrating: transcriptHydrating,
        transcriptPreparing: transcriptPreparing,
        selectedModel: selectedModel,
        availableModels: settingsController.aiModels,
        recentModelSelections: settingsController.recentModelSelections,
        onModelSelected: (providerConfigId, modelId) {
          // 2026-05-01 — 输入缓存锁定守卫: 启用缓存且本会话已有 assistant
          // 回复后, 切换 provider/model 会让命中的 cache_control 前缀全部
          // 失效；显式拦截并提示。
          final session = sessionController.currentSession;
          if (settingsController.aiInputCacheEnabled &&
              session != null &&
              session.statistics.assistantMessageCount > 0) {
            _showHomeSnackBar(
              context,
              SnackBar(
                content: Text(
                  _localizedText(
                    context,
                    zh: '已锁定服务商与模型以保证缓存命中（可在设置→AI→成本控制中关闭输入缓存后再切换）',
                    en: 'Provider & model locked to ensure cache hit (disable Input Cache under Settings → AI → Cost Control to switch)',
                  ),
                ),
                duration: const Duration(seconds: 3),
              ),
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
        onRevealOlderMessages: _handleRevealOlderMessages,
        onProgrammaticScrollCorrection:
            _runProgrammaticTranscriptScrollCorrection,
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
                  creationRequest: q[index].creationRequest,
                  systemReminders: q[index].systemReminders,
                  skillMetadata: q[index].skillMetadata,
                );
              }
            });
          }
        },
        pendingAttachments: _pendingAttachments,
        attachmentsEnabled: _selectedModelSupportsAttachments(selectedModel),
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
        onForkMessage: _forkMessage,
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
      AppSection.settings => Provider<ToolSearchReplayDispatcher>.value(
        value: _toolSearchReplayDispatcher,
        child: const SettingsView(),
      ),
      AppSection.hardnessSession =>
        _activeHardnessOrchestrator != null && _activeHardnessConfig != null
            ? HardnessSessionPane(
                controller: _hardnessSessionPaneController,
                config: _activeHardnessConfig!,
                orchestrator: _activeHardnessOrchestrator!,
                isZh: openHandIsChineseLocale(context),
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

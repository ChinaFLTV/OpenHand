import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart' as xml;
import 'package:yaml/yaml.dart';

import '../../app/model/app_info.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/theme/openhand_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/animated_menu.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_attachment.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session.dart';
import '../ai/model/ai_session_message.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/model/ai_thread_template.dart';
import '../ai/service/ai_bash_tool_service.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_git_snapshot_service.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_workspace_instruction_service.dart';
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
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_view.dart';
import '../mcp/model/mcp_tool.dart';
import '../memory/memory_controller.dart';
import '../memory/memory_view.dart';
import '../settings/settings_view.dart';
import '../skills/skills_controller.dart';
import '../skills/skills_view.dart';
import 'machine_expert_dialog.dart';
import 'message_path_linking.dart';
import 'openhand_loading_logo.dart';
import 'slash_command_parser.dart';
import 'tool_call_argument_parser.dart';

enum AppSection {
  workspace,
  automations,
  skills,
  memory,
  mcp,
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
// Reduced from 120 ms: the placeholder frame is now shorter so users spend
// less time waiting before the real content appears.
const Duration _transcriptLoadingPlaceholderDelay = Duration(milliseconds: 750);
const Duration _transcriptMessageDeleteAnimationDuration = Duration(
  milliseconds: 220,
);
const Duration _sessionTitleRevealAnimationDuration = Duration(
  milliseconds: 420,
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
  final AiWorkspaceInstructionService _workspaceInstructionService =
      AiWorkspaceInstructionService();
  final AiGitSnapshotService _gitSnapshotService = AiGitSnapshotService();

  AppSection _selectedSection = AppSection.workspace;
  _CreationMode _creationMode = _CreationMode.none;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
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
    _loadPersistedHardnessSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _transcriptPreparationGeneration ||
          _preparingTranscriptSessionId != nextSessionId) {
        return;
      }
      unawaited(() async {
        await Future<void>.delayed(_transcriptLoadingPlaceholderDelay);
        if (!mounted ||
            generation != _transcriptPreparationGeneration ||
            _preparingTranscriptSessionId != nextSessionId) {
          return;
        }
        setState(() {
          if (_preparingTranscriptSessionId == nextSessionId) {
            _preparingTranscriptSessionId = null;
          }
        });
      }());
    });
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

  void _armAutoFollowToBottom() {
    _shouldAutoFollowMessages = true;
    _pendingForcedScrollToBottom = true;
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
      return false;
    }
    final userScrolledAwayFromBottom = !isNearBottom && explicitUserScroll;
    if (userScrolledAwayFromBottom) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
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
    return false;
  }

  void _selectSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
  }

  void _toggleAutoFollow() {
    final nextValue = !_autoFollowEnabled;
    setState(() {
      _autoFollowEnabled = nextValue;
      if (!nextValue) {
        _clearPendingAutoFollowState();
      } else {
        _armAutoFollowToBottom();
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
    final currentRoute = ModalRoute.of(context);
    final focusedRoute = focusContext == null
        ? currentRoute
        : ModalRoute.of(focusContext);
    if (currentRoute != null &&
        focusedRoute != null &&
        !identical(currentRoute, focusedRoute)) {
      return false;
    }
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
      // The workspace composer and hardness manual-phase composer each have
      // a dedicated FocusNode.onKeyEvent handler that performs the actual
      // send / toggle action.  HardwareKeyboard fires on a separate dispatch
      // pipeline, so both would execute for the same key event — causing
      // toggleComposer to collapse then immediately re-expand (net no-op)
      // and sendMessage to attempt a redundant second send.
      // Return true here to claim the event at the platform level without
      // performing the action; the FocusNode handler takes care of it.
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
    final bindings = context.read<SettingsController>().shortcutBindings;
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    // Handle send and toggle-composer directly on the focus node so that
    // user-configured shortcut bindings always fire, regardless of whether
    // the key event reaches the global shortcut focus node via bubbling.
    for (final action in const <OpenHandShortcutAction>[
      OpenHandShortcutAction.sendMessage,
      OpenHandShortcutAction.toggleComposer,
    ]) {
      final shortcutKeyIds = normalizeShortcutKeyIds(
        bindings[action] ?? const <int>[],
      );
      if (shortcutKeyIds.isEmpty) {
        continue;
      }
      if (shortcutKeyIds.length != pressedKeyIds.length ||
          !pressedKeyIds.containsAll(shortcutKeyIds)) {
        continue;
      }
      switch (action) {
        case OpenHandShortcutAction.sendMessage:
          final sessionController = context.read<AiSessionController>();
          if (_canStopCurrentSessionResponse(sessionController) &&
              _composerController.text.trim().isEmpty &&
              _pendingAttachments.isEmpty) {
            unawaited(_stopResponding());
          } else {
            // Always delegate to _sendMessage() which handles both direct
            // send (when idle) and queueing (when busy).
            unawaited(_sendMessage());
          }
        case OpenHandShortcutAction.toggleComposer:
          _setComposerCollapsedState(
            !_composerCollapsed,
            requestFocusWhenExpanded: _composerCollapsed,
          );
        default:
          continue;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isEditableTextFocused(BuildContext? focusContext) {
    if (focusContext == null) {
      return false;
    }
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
      _armAutoFollowToBottom();
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
      final result = await showAnimatedDialog<MachineExpertDialogResult>(
        context: context,
        builder: (context) => const MachineExpertDialog(),
      );
      if (!mounted || result == null) {
        return false;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
      );
      if (created && mounted) {
        _replaceComposerText(result.toPrompt());
        await _sendMessage();
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
      } catch (_) {}
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
      unawaited(_hardnessSessionStore.save(record).catchError((_) {}));
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
    final record = await _hardnessSessionStore.load();
    if (!mounted || record == null) return;
    final migratedRecord = _migrateLegacyHardnessAutoRewrittenModels(record);
    final effectiveRecord = _normalizeRestoredHardnessRecord(migratedRecord);
    if (effectiveRecord != record) {
      _scheduleHardnessSessionSave(effectiveRecord, immediate: true);
    }
    _activeHardnessOrchestrator?.removeListener(_onHardnessOrchestratorChanged);
    final restoredOrchestrator = HardnessOrchestrator(effectiveRecord.config);
    restoredOrchestrator.fullAccessPermission = _heFullAccessPermission;
    restoredOrchestrator.onPhaseApprovalRequired = _handlePhaseApprovalRequired;
    _wireHardnessApiMode(restoredOrchestrator);
    restoredOrchestrator.restoreSnapshot(
      status: effectiveRecord.status,
      phaseLogs: effectiveRecord.phaseLogs,
      errorMessage: effectiveRecord.errorMessage,
      currentPhase: effectiveRecord.currentPhase,
      manualPhaseInputRequested: effectiveRecord.manualPhaseInputRequested,
      queuedManualPhaseInput: effectiveRecord.queuedManualPhaseInput,
      queuedManualPhaseInputPhase: effectiveRecord.queuedManualPhaseInputPhase,
    );
    restoredOrchestrator.addListener(_onHardnessOrchestratorChanged);
    _cacheHardnessShellState(restoredOrchestrator);
    setState(() {
      _persistedHardnessSession = effectiveRecord;
      _activeHardnessConfig = effectiveRecord.config;
      _activeHardnessOrchestrator = restoredOrchestrator;
    });
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

  Future<AiSessionRuntimeContext> _buildRuntimeContext({
    String? workingDirectory,
  }) async {
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    final skillsController = context.read<SkillsController>();
    final mcpController = context.read<McpController>();
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
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      memoryEnabled: settingsController.memoryEnabled,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
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
      workspaceInstructionDocuments: _workspaceInstructionService.loadDocuments(
        startDirectory: OpenHandPaths.applicationDirectoryPath(),
        homeDirectory: OpenHandPaths.homeDirectoryPath(),
      ),
    );
  }

  AiSessionRuntimeContext _buildRuntimeCatalogPreviewContext({
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required AppInfo appInfo,
  }) {
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
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      sequentialToolRoundLimit: settingsController.aiSequentialToolRoundLimit,
      memoryEnabled: settingsController.memoryEnabled,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      platformName: Platform.operatingSystem,
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      todayLocalDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      timeZoneName: now.timeZoneName,
      memoryEntries: const [],
      allowCommandRules: settingsController.aiAllowCommandRules,
      availableSkills: skillsController.skills,
      availableMcpServers: mcpController.servers,
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

    final sessionController = context.read<AiSessionController>();
    AiSessionRuntimeContext? runtimeContext;
    if (sessionController.currentSession == null) {
      final templateId = await _showThreadTemplateDialog();
      if (!mounted || templateId == null) {
        return;
      }
      if (templateId == 'machine_expert') {
        final result = await showAnimatedDialog<MachineExpertDialogResult>(
          context: context,
          builder: (context) => MachineExpertDialog(initialTask: prompt),
        );
        if (!mounted || result == null) {
          return;
        }
        prompt = result.toPrompt();
        _replaceComposerText(prompt);
      }
      runtimeContext = await _buildRuntimeContext();
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
    }
    final targetSessionId = sessionController.currentSessionId;
    if (targetSessionId == null) {
      return;
    }
    final isProcessing =
        _displaySendPhaseForSession(sessionController, targetSessionId) !=
        AiSendPhase.idle;
    if (isProcessing) {
      final queued = _QueuedMessage(
        text: prompt,
        attachments: pendingAttachments,
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
    final responseModalities = creationMode == _CreationMode.image
        ? const <String>['Text', 'Image']
        : const <String>[];
    setState(() {
      _pendingAttachments = const <_ComposerAttachmentDraft>[];
      _creationMode = _CreationMode.none;
    });

    await _submitTextToSession(
      targetSessionId,
      prompt,
      pendingAttachments,
      runtimeContext: runtimeContext,
      responseModalities: responseModalities,
    );
  }

  Future<void> _submitTextToSession(
    String targetSessionId,
    String prompt,
    List<_ComposerAttachmentDraft> pendingAttachments, {
    AiSessionRuntimeContext? runtimeContext,
    List<String> responseModalities = const <String>[],
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
      _armAutoFollowToBottom();
    });
    _scheduleScrollToBottom(force: true);
    try {
      runtimeContext ??= await _buildRuntimeContext();
      if (!mounted) {
        return;
      }
      final sent = await sessionController.sendMessage(
        sessionId: targetSessionId,
        content: prompt,
        model: selectedModel,
        runtimeContext: runtimeContext,
        responseModalities: responseModalities,
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
    if (model == null) {
      return false;
    }
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    return adapter.supportsAttachmentsForModel(model);
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
    var addedCount = 0;
    for (final file in pickedFiles) {
      final path = file.path.trim();
      if (path.isEmpty || existingPaths.contains(path)) {
        continue;
      }
      if (nextAttachments.length >= aiMessageAttachmentLimit) {
        break;
      }
      nextAttachments.add(await _ComposerAttachmentDraft.fromPath(path));
      existingPaths.add(path);
      addedCount += 1;
    }
    if (!mounted) {
      return;
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
      _pendingScrollToBottomSettlePasses = math.max(
        _pendingScrollToBottomSettlePasses,
        force ? 30 : (animated ? 4 : 3),
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
        unawaited(
          _messageScrollController
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
        _messageScrollController.jumpTo(targetOffset);
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
      _armAutoFollowToBottom();
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
    final effectiveSessionId = sessionId ?? sessionController.currentSessionId;
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
                );
                final contentPane = _ContentPane(
                  child: _buildSectionContent(context),
                );

                if (stackedLayout) {
                  return Column(
                    children: [
                      SizedBox(
                        height: stackedNavigationHeight,
                        child: navigationPane,
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: contentPane),
                    ],
                  );
                }

                return ValueListenableBuilder<double>(
                  valueListenable: _navigationWidthNotifier,
                  builder: (context, navWidth, _) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: navWidth, child: navigationPane),
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
                        Expanded(child: contentPane),
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
    final settingsController = context.watch<SettingsController>();
    final skillsController = context.watch<SkillsController>();
    final mcpController = context.watch<McpController>();
    final sessionController = context.watch<AiSessionController>();
    final appInfo = context.read<AppInfo>();
    final currentSession = sessionController.currentSession;
    final transcriptPreparing = _isPreparingTranscriptForSession(
      currentSession,
    );
    // Defer runtime catalog preview work to the workspace section — these
    // computations involve DateTime.now(), object allocation, and tool catalog
    // resolution that are wasted when viewing other sections.
    AiRuntimeToolPreview? liveRuntimeToolPreview;
    if (_selectedSection == AppSection.workspace) {
      final runtimeCatalogPreviewContext = _buildRuntimeCatalogPreviewContext(
        settingsController: settingsController,
        skillsController: skillsController,
        mcpController: mcpController,
        appInfo: appInfo,
      );
      liveRuntimeToolPreview =
          currentSession == null || settingsController.selectedAiModel == null
          ? null
          : sessionController.previewRuntimeToolCatalog(
              session: currentSession,
              model: settingsController.selectedAiModel!,
              runtimeContext: runtimeCatalogPreviewContext,
              mcpToolCatalogsByServerName: <String, McpToolCatalog>{
                for (final server in mcpController.servers)
                  server.name: mcpController.toolCatalogFor(server.name),
              },
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
        onModelSelected: (providerConfigId, modelId) {
          settingsController.updateProviderActiveModel(
            providerConfigId,
            modelId,
          );
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
        onCreationModeChanged: (mode) {
          setState(() => _creationMode = mode);
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
  const _QueuedMessage({required this.text, required this.attachments});

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
}

extension on AppSection {
  int? get drawerIndex {
    return switch (this) {
      AppSection.workspace => null,
      AppSection.hardnessSession => null,
      AppSection.automations => 0,
      AppSection.skills => 1,
      AppSection.memory => 2,
      AppSection.mcp => 3,
      AppSection.settings => 4,
    };
  }
}

AppSection _sectionFromDrawerIndex(int index) {
  return switch (index) {
    0 => AppSection.automations,
    1 => AppSection.skills,
    2 => AppSection.memory,
    3 => AppSection.mcp,
    4 => AppSection.settings,
    _ => AppSection.workspace,
  };
}

class _NavigationPane extends StatefulWidget {
  const _NavigationPane({
    required this.selectedSection,
    required this.sessions,
    required this.sessionSendPhases,
    required this.currentSessionId,
    required this.onCreateThreadRequested,
    required this.onSessionSelected,
    required this.onRenameSession,
    required this.onDeleteSession,
    required this.onSectionSelected,
    this.activeHardnessOrchestrator,
    this.hardnessSessionRecord,
    this.onHardnessSessionSelected,
    this.onRenameHardnessSession,
    this.onDeleteHardnessSession,
  });

  final AppSection selectedSection;
  final List<AiSession> sessions;
  final Map<String, AiSendPhase> sessionSendPhases;
  final String? currentSessionId;
  final Future<void> Function() onCreateThreadRequested;
  final Future<void> Function(String sessionId) onSessionSelected;
  final Future<void> Function(AiSession session) onRenameSession;
  final Future<void> Function(AiSession session) onDeleteSession;
  final ValueChanged<AppSection> onSectionSelected;
  final HardnessOrchestrator? activeHardnessOrchestrator;
  final HardnessSessionRecord? hardnessSessionRecord;
  final VoidCallback? onHardnessSessionSelected;
  final VoidCallback? onRenameHardnessSession;
  final VoidCallback? onDeleteHardnessSession;

  @override
  State<_NavigationPane> createState() => _NavigationPaneState();
}

class _NavigationPaneState extends State<_NavigationPane> {
  ThemeData? _cachedDrawerTheme;
  int? _cachedThemeSignature;

  ThemeData _ensureDrawerTheme(ThemeData theme) {
    final signature = Object.hashAll(<Object?>[
      theme.colorScheme.primary.toARGB32(),
      theme.colorScheme.primaryContainer.toARGB32(),
      theme.brightness.index,
      theme.textTheme.titleMedium?.fontSize,
    ]);
    if (_cachedDrawerTheme != null && _cachedThemeSignature == signature) {
      return _cachedDrawerTheme!;
    }
    final colorScheme = theme.colorScheme;
    _cachedDrawerTheme = theme.copyWith(
      navigationDrawerTheme: theme.navigationDrawerTheme.copyWith(
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return theme.textTheme.titleMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
    );
    _cachedThemeSignature = signature;
    return _cachedDrawerTheme!;
  }

  /// Builds an interleaved list of AI thread tiles and the optional HE session
  /// tile, sorted by [updatedAt] descending.  The incoming [widget.sessions]
  /// are already sorted by the store; we simply merge-insert the HE record at
  /// the correct position.
  List<Widget> _buildMergedThreadTiles({
    required HardnessSessionRecord? heRecord,
    required HardnessOrchestratorStatus? heStatus,
    required bool heAwaitingApproval,
  }) {
    final tiles = <Widget>[];
    bool heInserted = false;

    Widget buildHeTile() {
      final record = heRecord;
      final status = heStatus;
      if (record == null || status == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        key: ValueKey<String>('he-thread-${record.id}'),
        padding: const EdgeInsets.only(bottom: 10),
        child: _HardnessSessionTile(
          title: record.title,
          status: status,
          awaitingApproval: heAwaitingApproval,
          isSelected: widget.selectedSection == AppSection.hardnessSession,
          onTap: widget.onHardnessSessionSelected ?? () {},
          onRename: widget.onRenameHardnessSession ?? () {},
          onDelete: widget.onDeleteHardnessSession ?? () {},
        ),
      );
    }

    for (final session in widget.sessions) {
      // Insert HE tile when its updatedAt >= the current AI session's.
      if (!heInserted &&
          heRecord != null &&
          !session.updatedAt.isAfter(heRecord.updatedAt)) {
        tiles.add(buildHeTile());
        heInserted = true;
      }
      tiles.add(
        Padding(
          key: ValueKey<String>('ai-thread-${session.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: _ThreadTile(
            session: session,
            sendPhase: widget.sessionSendPhases[session.id] ?? AiSendPhase.idle,
            isSelected:
                widget.selectedSection == AppSection.workspace &&
                widget.currentSessionId == session.id,
            onTap: () => widget.onSessionSelected(session.id),
            onRename: () => widget.onRenameSession(session),
            onDelete: () => widget.onDeleteSession(session),
          ),
        ),
      );
    }

    // HE session is the oldest, or there are no AI sessions — append at end.
    if (!heInserted && heRecord != null) {
      tiles.add(buildHeTile());
    }

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final drawerTheme = _ensureDrawerTheme(theme);

    // HE tile status: prefer the live orchestrator status when it is actually
    // running/completed/failed/cancelled; fall back to the persisted record
    // status when the live orchestrator is idle (e.g. an orchestrator that
    // was reconstructed from a persisted record on app restart).
    final liveHeStatus = widget.activeHardnessOrchestrator?.status;
    final heAwaitingApprovalForTile =
        widget.activeHardnessOrchestrator?.awaitingApprovalPhase != null;
    final heStatusForTile = widget.hardnessSessionRecord == null
        ? null
        : (liveHeStatus != null &&
              liveHeStatus != HardnessOrchestratorStatus.idle)
        ? liveHeStatus
        : widget.hardnessSessionRecord!.status;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: drawerTheme,
        child: NavigationDrawer(
          selectedIndex: widget.selectedSection.drawerIndex,
          onDestinationSelected: (index) {
            widget.onSectionSelected(_sectionFromDrawerIndex(index));
          },
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: widget.onCreateThreadRequested,
                icon: const Icon(Icons.add_comment_rounded),
                label: Text(l10n.newThread),
              ),
            ),
            const SizedBox(height: 12),
            NavigationDrawerDestination(
              icon: const Icon(Icons.history_toggle_off_outlined),
              selectedIcon: const Icon(Icons.schedule_rounded),
              label: Text(l10n.automations),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.extension_outlined),
              selectedIcon: const Icon(Icons.extension_rounded),
              label: Text(l10n.skills),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.psychology_alt_outlined),
              selectedIcon: const Icon(Icons.psychology_alt_rounded),
              label: Text(l10n.memory),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.hub_outlined),
              selectedIcon: const Icon(Icons.hub_rounded),
              label: Text(l10n.mcp),
            ),
            NavigationDrawerDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: Text(l10n.settings),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(l10n.threads, style: theme.textTheme.titleMedium),
            ),
            // Unified thread list: merge AI sessions and HE session,
            // sorted by updatedAt descending (most recently updated first).
            if (widget.sessions.isEmpty && widget.hardnessSessionRecord == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  l10n.threadsEmptyBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMergedThreadTiles(
                    heRecord: widget.hardnessSessionRecord,
                    heStatus: heStatusForTile,
                    heAwaitingApproval: heAwaitingApprovalForTile,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

Future<bool?> showWriteCommandConfirmationDialog(
  BuildContext context, {
  required BashCommandApprovalRequest request,
}) {
  return showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _WriteCommandConfirmationDialog(request: request),
  );
}

class _WriteCommandConfirmationDialog extends StatefulWidget {
  const _WriteCommandConfirmationDialog({required this.request});

  final BashCommandApprovalRequest request;

  @override
  State<_WriteCommandConfirmationDialog> createState() =>
      _WriteCommandConfirmationDialogState();
}

class _WriteCommandConfirmationDialogState
    extends State<_WriteCommandConfirmationDialog> {
  final ScrollController _bodyScrollController = ScrollController();
  final FocusNode _shortcutFocusNode = FocusNode();
  bool _isExpanded = false;

  bool get _isLongCommand =>
      widget.request.command.length > 150 ||
      widget.request.command.contains('\n');

  String get _shortenedCommand {
    if (!_isLongCommand) {
      return widget.request.command;
    }
    final command = widget.request.command.trim();
    final firstLine = command.split('\n').first;
    if (firstLine.length > 120) {
      return '${firstLine.substring(0, 120)}... [omitted ${command.length - 120} chars]';
    }
    return '$firstLine\n... [omitted ${command.length - firstLine.length} chars]';
  }

  void _closeWithResult(bool approved) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(approved);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _shortcutFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _closeWithResult(false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _closeWithResult(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 860,
            maxHeight: screenSize.height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedText(
                    context,
                    zh: '确认执行写命令',
                    en: 'Confirm Write Command',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Scrollbar(
                    controller: _bodyScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _bodyScrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _localizedText(
                              context,
                              zh: '该 bash 命令可能修改文件或系统状态，需要你确认后才会真正执行。',
                              en: 'This bash command may modify files or system state. OpenHand needs your approval before running it.',
                            ),
                          ),
                          if (_isExpanded)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(
                                  widget.request.command,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontFamily: 'monospace',
                                        height: 1.45,
                                      ),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              child: SelectableText(
                                _shortenedCommand,
                                maxLines: 3,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                              ),
                            ),
                          if (_isLongCommand)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isExpanded = !_isExpanded;
                                  });
                                },
                                icon: Icon(
                                  _isExpanded
                                      ? Icons.unfold_less_rounded
                                      : Icons.unfold_more_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _isExpanded
                                      ? _localizedText(
                                          context,
                                          zh: '收起命令',
                                          en: 'Collapse',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '查看完整命令',
                                          en: 'View Full Command',
                                        ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            '${_localizedText(context, zh: '工作目录', en: 'Working Directory')}: ${widget.request.workingDirectory}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _localizedText(
                    context,
                    zh: '快捷键：Enter 确认，Esc 取消',
                    en: 'Shortcuts: Enter confirms, Esc cancels',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: () => _closeWithResult(false),
                      label: AppLocalizations.of(context)!.commonCancel,
                    ),
                    const SizedBox(width: 12),
                    OpenHandDialogActionButton.primary(
                      onPressed: () => _closeWithResult(true),
                      label: _localizedText(
                        context,
                        zh: '允许执行',
                        en: 'Run Command',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.transcriptPreparing,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.composerFocusNode,
    required this.composerHeight,
    required this.composerCollapsed,
    required this.onComposerHeightChanged,
    required this.onComposerCollapsedChanged,
    required this.onComposerLayoutChanged,
    required this.onTranscriptLayoutChanged,
    required this.onRevealOlderMessages,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.pendingAttachments,
    required this.attachmentsEnabled,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onReorderAttachments,
    required this.onSend,
    required this.onStop,
    required this.onCreateThreadRequested,
    required this.creationMode,
    required this.onCreationModeChanged,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onDismissError,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.queuedMessages,
    required this.onRemoveQueuedMessage,
    required this.onMoveQueuedMessage,
    required this.onEditQueuedMessage,
    this.jumpToBottomOnInit = false,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final bool Function(ScrollNotification notification)
  onMessageScrollNotification;
  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final bool transcriptPreparing;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode composerFocusNode;
  final double composerHeight;
  final bool composerCollapsed;
  final ValueChanged<double> onComposerHeightChanged;
  final ValueChanged<bool> onComposerCollapsedChanged;
  final VoidCallback onComposerLayoutChanged;
  final VoidCallback onTranscriptLayoutChanged;
  final VoidCallback onRevealOlderMessages;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final List<_ComposerAttachmentDraft> pendingAttachments;
  final bool attachmentsEnabled;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(int oldIndex, int newIndex) onReorderAttachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final Future<void> Function() onCreateThreadRequested;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final List<_QueuedMessage> queuedMessages;
  final ValueChanged<int> onRemoveQueuedMessage;
  final void Function(int from, int to) onMoveQueuedMessage;
  final void Function(int index, String newText) onEditQueuedMessage;
  // When true, the message list widget will immediately jump to the bottom
  // on its first frame instead of relying on the parent's scroll scheduler.
  final bool jumpToBottomOnInit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxComposerHeight = (constraints.maxHeight - 96)
            .clamp(_composerMinHeight, _composerMaxHeight)
            .toDouble();
        final effectiveComposerHeight = composerHeight
            .clamp(_composerMinHeight, maxComposerHeight)
            .toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: currentSession == null
                  ? const _WorkspaceEmptyState(
                      key: ValueKey<String>('no-session'),
                    )
                  : currentSession!.messages.isEmpty
                  ? _WorkspaceEmptyState(
                      key: ValueKey<String>(currentSession!.id),
                      session: currentSession,
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedOpacity(
                            // 瞬间使其隐身以彻底遮盖背后的列表疯狂重排乱跳的现象
                            opacity: transcriptPreparing ? 0.0 : 1.0,
                            duration: transcriptPreparing
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            curve: Curves.easeInCubic,
                            child: _SessionTranscript(
                              key: ValueKey<String>(
                                'messages-${currentSession!.id}',
                              ),
                              controller: messageScrollController,
                              onScrollNotification: onMessageScrollNotification,
                              session: currentSession!,
                              liveRuntimeToolPreview: liveRuntimeToolPreview,
                              sendPhase: sendPhase,
                              planTimelineCollapsed: planTimelineCollapsed,
                              onPlanTimelineCollapsedChanged:
                                  onPlanTimelineCollapsedChanged,
                              onLayoutChanged: onTranscriptLayoutChanged,
                              onRevealOlderMessages: onRevealOlderMessages,
                              onEditMessage: onEditMessage,
                              onCopyMessage: onCopyMessage,
                              onDeleteMessage: onDeleteMessage,
                              onDeleteMessageFromHere: onDeleteMessageFromHere,
                              onDismissError: onDismissError,
                              // Jump to the very bottom on the first frame when the
                              // session was just activated, so the user never sees a
                              // flash from scroll-top to scroll-bottom.
                              jumpToBottomOnInit: jumpToBottomOnInit,
                            ),
                          ),
                        ),
                        // Overlay mask that visually hides the initial rendering
                        // and scroll-to-bottom operations of the transcript list.
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !transcriptPreparing,
                            child: AnimatedOpacity(
                              opacity: transcriptPreparing ? 1.0 : 0.0,
                              // 进场需提前快过底部列表跳跃，退场再慢慢淡出
                              duration: transcriptPreparing
                                  ? const Duration(milliseconds: 100)
                                  : const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              child: _SessionTranscriptLoadingPlaceholder(
                                key: ValueKey<String>(
                                  'session-transcript-loading-${currentSession!.id}',
                                ),
                                session: currentSession!,
                                liveRuntimeToolPreview: liveRuntimeToolPreview,
                                sendPhase: sendPhase,
                                planTimelineCollapsed: planTimelineCollapsed,
                                onPlanTimelineCollapsedChanged:
                                    onPlanTimelineCollapsedChanged,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (currentSession != null) ...[
              const SizedBox(height: 16),
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (notification) {
                  onComposerLayoutChanged();
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: _ComposerPanel(
                    currentSession: currentSession,
                    liveRuntimeToolPreview: liveRuntimeToolPreview,
                    controller: draftController,
                    selectedModel: selectedModel,
                    availableModels: availableModels,
                    onModelSelected: onModelSelected,
                    focusNode: composerFocusNode,
                    composerHeight: effectiveComposerHeight,
                    isCollapsed: composerCollapsed,
                    onCollapsedChanged: onComposerCollapsedChanged,
                    autoFollowEnabled: autoFollowEnabled,
                    onToggleAutoFollow: onToggleAutoFollow,
                    sendPhase: sendPhase,
                    canStopSending: canStopSending,
                    sessionMode: sessionMode,
                    onSessionModeChanged: onSessionModeChanged,
                    pendingAttachments: pendingAttachments,
                    attachmentsEnabled: attachmentsEnabled,
                    onPickAttachments: onPickAttachments,
                    onRemoveAttachment: onRemoveAttachment,
                    onReorderAttachments: onReorderAttachments,
                    onSend: onSend,
                    onStop: onStop,
                    creationMode: creationMode,
                    onCreationModeChanged: onCreationModeChanged,
                    editingMessageId: editingMessageId,
                    onCancelEditing: onCancelEditing,
                    fullAccessPermission: fullAccessPermission,
                    onToggleFullAccessPermission: onToggleFullAccessPermission,
                    queuedMessages: queuedMessages,
                    onRemoveQueuedMessage: onRemoveQueuedMessage,
                    onMoveQueuedMessage: onMoveQueuedMessage,
                    onEditQueuedMessage: onEditQueuedMessage,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState({super.key, this.session});

  final AiSession? session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = session?.title ?? l10n.newThread;
    final subtitle = session?.templateName ?? l10n.appTitle;
    final emptyStateContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.appTagline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Center(child: emptyStateContent),
          ),
        );
      },
    );
  }
}

class _SessionTranscriptLoadingPlaceholder extends StatelessWidget {
  const _SessionTranscriptLoadingPlaceholder({
    super.key,
    required this.session,
    required this.liveRuntimeToolPreview,
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          liveRuntimeToolPreview: liveRuntimeToolPreview,
          sendPhase: sendPhase,
          planTimelineCollapsed: planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: onPlanTimelineCollapsedChanged,
        ),
        const SizedBox(height: 14),
        const Expanded(child: OpenHandLoadingLogo()),
      ],
    );
  }
}

class _TranscriptRenderEntry {
  const _TranscriptRenderEntry({
    required this.message,
    this.exiting = false,
    this.entering = false,
  });

  final AiSessionMessage message;
  final bool exiting;
  final bool entering;

  String get id => message.id;

  _TranscriptRenderEntry copyWith({
    AiSessionMessage? message,
    bool? exiting,
    bool? entering,
  }) {
    return _TranscriptRenderEntry(
      message: message ?? this.message,
      exiting: exiting ?? this.exiting,
      entering: entering ?? this.entering,
    );
  }
}

class _SessionTranscript extends StatefulWidget {
  const _SessionTranscript({
    super.key,
    required this.controller,
    required this.onScrollNotification,
    required this.session,
    required this.liveRuntimeToolPreview,
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
    required this.onLayoutChanged,
    required this.onRevealOlderMessages,
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onDismissError,
    this.jumpToBottomOnInit = false,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;
  final VoidCallback onLayoutChanged;
  final VoidCallback onRevealOlderMessages;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;
  // When true, the list will jump to the very bottom on its first frame.
  // This eliminates the visible scroll-from-top animation that would otherwise
  // appear when a session is loaded and the parent schedules a forced scroll.
  final bool jumpToBottomOnInit;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;
  final Set<String> _dismissedErrorIds = <String>{};
  int _windowStartIndex = 0;
  bool _loadingOlderMessages = false;
  List<_TranscriptRenderEntry> _renderEntries =
      const <_TranscriptRenderEntry>[];
  bool _initialBuildDone = false;

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _replaceRenderEntries(_visibleMessagesForWindow());
    _syncVisibleError();
    // Immediately jump to the bottom on the first rendered frame, before the
    // parent's postFrameCallback chain fires. This prevents the user from ever
    // seeing the list start at scroll-offset 0 while a forced scroll-to-bottom
    // is pending, which manifests as a jarring flash/jump animation.
    if (widget.jumpToBottomOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = widget.controller;
        if (controller.hasClients) {
          final position = controller.positions.isNotEmpty
              ? controller.positions.last
              : null;
          if (position != null && position.maxScrollExtent > 0) {
            controller.jumpTo(position.maxScrollExtent);
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _syncWindowStartIndex(forceReset: true);
      _replaceRenderEntries(_visibleMessagesForWindow());
    } else if (oldWidget.session.messages != widget.session.messages ||
        oldWidget.session.updatedAt != widget.session.updatedAt) {
      final previousWindowStartIndex = _windowStartIndex;
      _syncWindowStartIndex();
      _syncRenderEntries(
        forceReset: previousWindowStartIndex != _windowStartIndex,
      );
    }
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.recentErrors != widget.session.recentErrors) {
      _syncVisibleError();
    }
  }

  void _syncWindowStartIndex({bool forceReset = false}) {
    final displayMessages = widget.session.displayMessages;
    final nextWindowStartIndex = forceReset
        ? _initialWindowStartIndex(displayMessages.length)
        : _windowStartIndex.clamp(0, displayMessages.length).toInt();
    if (forceReset) {
      _loadingOlderMessages = false;
    }
    if (nextWindowStartIndex == _windowStartIndex) {
      return;
    }
    _windowStartIndex = nextWindowStartIndex;
  }

  List<AiSessionMessage> _visibleMessagesForWindow() {
    final displayMessages = widget.session.displayMessages;
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    return displayMessages.sublist(clampedWindowStartIndex);
  }

  void _replaceRenderEntries(
    List<AiSessionMessage> visibleMessages, {
    bool animate = true,
  }) {
    final previousIds = animate && _initialBuildDone
        ? _renderEntries.where((e) => !e.exiting).map((e) => e.id).toSet()
        : null;
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        _TranscriptRenderEntry(
          message: message,
          entering: previousIds != null && !previousIds.contains(message.id),
        ),
    ];
    _initialBuildDone = true;
  }

  void _syncRenderEntries({bool forceReset = false}) {
    final visibleMessages = _visibleMessagesForWindow();
    if (forceReset || _renderEntries.isEmpty) {
      _replaceRenderEntries(visibleMessages, animate: false);
      return;
    }
    final visibleMessageIds = visibleMessages
        .map((message) => message.id)
        .toList(growable: false);
    final visibleMessageIdSet = visibleMessageIds.toSet();
    final visibleMessagesById = <String, AiSessionMessage>{
      for (final message in visibleMessages) message.id: message,
    };
    final activeEntries = _renderEntries
        .where((entry) => !entry.exiting)
        .toList(growable: false);
    final activeEntryIds = activeEntries
        .map((entry) => entry.id)
        .toList(growable: false);
    final activeEntryIdSet = activeEntryIds.toSet();
    final removedIds = activeEntryIds
        .where((id) => !visibleMessageIdSet.contains(id))
        .toSet();
    final hasAddedIds = visibleMessages.any(
      (message) => !activeEntryIdSet.contains(message.id),
    );
    final hasExitingEntries = _renderEntries.any((entry) => entry.exiting);
    if (removedIds.isEmpty) {
      if (!hasExitingEntries) {
        _replaceRenderEntries(visibleMessages);
        return;
      }
      _renderEntries = <_TranscriptRenderEntry>[
        for (final entry in _renderEntries)
          entry.exiting
              ? entry
              : entry.copyWith(message: visibleMessagesById[entry.id]),
      ];
      return;
    }
    if (hasAddedIds ||
        !_isOrderedSubsequence(visibleMessageIds, activeEntryIds)) {
      _replaceRenderEntries(visibleMessages);
      return;
    }
    _renderEntries = <_TranscriptRenderEntry>[
      for (final entry in _renderEntries)
        if (entry.exiting)
          entry
        else if (visibleMessagesById.containsKey(entry.id))
          entry.copyWith(message: visibleMessagesById[entry.id])
        else
          entry.copyWith(exiting: true),
    ];
  }

  bool _isOrderedSubsequence(List<String> candidate, List<String> source) {
    if (candidate.length > source.length) {
      return false;
    }
    var sourceIndex = 0;
    for (final candidateId in candidate) {
      var matched = false;
      while (sourceIndex < source.length) {
        if (source[sourceIndex] == candidateId) {
          matched = true;
          sourceIndex++;
          break;
        }
        sourceIndex++;
      }
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  void _handleRenderEntryExitCompleted(String messageId) {
    if (!mounted) {
      return;
    }
    final shouldRemove = _renderEntries.any(
      (entry) => entry.id == messageId && entry.exiting,
    );
    if (!shouldRemove) {
      return;
    }
    setState(() {
      _renderEntries = _renderEntries
          .where((entry) => !(entry.id == messageId && entry.exiting))
          .toList(growable: false);
    });
  }

  int _initialWindowStartIndex(int messageCount) {
    if (messageCount <= _transcriptWindowingThreshold) {
      return 0;
    }
    return math.max(0, messageCount - _transcriptInitialWindowSize);
  }

  Future<void> _revealOlderMessages(int totalMessageCount) async {
    if (_windowStartIndex <= 0 || _loadingOlderMessages) {
      return;
    }
    setState(() {
      _loadingOlderMessages = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }
    setState(() {
      _windowStartIndex = math.max(
        0,
        _windowStartIndex - _transcriptWindowIncrement,
      );
      _replaceRenderEntries(_visibleMessagesForWindow(), animate: false);
      _loadingOlderMessages = false;
    });
  }

  Future<void> _runDeleteAction(
    AiSessionMessage message,
    Future<bool> Function(AiSessionMessage message) deleteAction,
  ) async {
    final deleted = await deleteAction(message);
    if (!mounted || !deleted || _selectedMessageId != message.id) {
      return;
    }
    setState(() {
      _selectedMessageId = null;
    });
  }

  void _syncVisibleError() {
    final visibleError = _resolveUserVisibleError(widget.session);
    final visibleErrorId = visibleError?.id;
    final hasCurrentVisibleError =
        _visibleErrorId != null &&
        widget.session.recentErrors.any((error) => error.id == _visibleErrorId);
    if (visibleError != null && visibleErrorId != null) {
      _visibleErrorId = visibleErrorId;
      _markErrorAsPresented(visibleError);
      return;
    }
    if (!hasCurrentVisibleError) {
      _visibleErrorId = null;
    }
  }

  void _markErrorAsPresented(AiSessionErrorRecord error) {
    if (error.hasBeenPresented || _pendingPresentedErrorId == error.id) {
      return;
    }
    _pendingPresentedErrorId = error.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await context.read<AiSessionController>().markErrorAsPresented(
        sessionId: widget.session.id,
        errorId: error.id,
      );
      if (!mounted || _pendingPresentedErrorId != error.id) {
        return;
      }
      _pendingPresentedErrorId = null;
    });
  }

  AiSessionErrorRecord? _resolveUserVisibleError(AiSession session) {
    for (final error in session.recentErrors) {
      if (error.stage == 'title_generation') {
        continue;
      }
      if (_dismissedErrorIds.contains(error.id)) {
        continue;
      }
      if (!error.hasBeenPresented) {
        return error;
      }
    }
    final visibleErrorId = _visibleErrorId;
    if (visibleErrorId == null) {
      return null;
    }
    for (final error in session.recentErrors) {
      if (_dismissedErrorIds.contains(error.id)) {
        continue;
      }
      if (error.id == visibleErrorId && error.stage != 'title_generation') {
        return error;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final displayMessages = session.displayMessages;
    final clampedWindowStartIndex = _windowStartIndex
        .clamp(0, displayMessages.length)
        .toInt();
    final hiddenMessageCount = clampedWindowStartIndex;
    final visibleMessages = displayMessages.sublist(clampedWindowStartIndex);
    if (_renderEntries.isEmpty && visibleMessages.isEmpty) {
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    final visibleMessageIndexById = <String, int>{
      for (var index = 0; index < visibleMessages.length; index++)
        visibleMessages[index].id: index,
    };
    final userVisibleError = _resolveUserVisibleError(session);
    if (_renderEntries.isEmpty &&
        visibleMessages.isEmpty &&
        userVisibleError == null) {
      return _WorkspaceEmptyState(
        key: ValueKey<String>('empty-session-transcript-${session.id}'),
        session: session,
      );
    }
    final hiddenLoadMoreCount = hiddenMessageCount > 0 ? 1 : 0;
    final errorBannerCount = userVisibleError == null ? 0 : 1;
    final listItemCount =
        _renderEntries.length + hiddenLoadMoreCount + errorBannerCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          liveRuntimeToolPreview: widget.liveRuntimeToolPreview,
          sendPhase: widget.sendPhase,
          planTimelineCollapsed: widget.planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: widget.onPlanTimelineCollapsedChanged,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: widget.onScrollNotification,
            child: ListView.builder(
              key: const ValueKey<String>('session-transcript-list'),
              controller: widget.controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 12),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              // Keep a modest cache: large enough to avoid jank when
              // scrolling slightly but small enough to limit the work done
              // on the first layout pass (fewer off-screen items built).
              cacheExtent: 400,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: listItemCount,
              itemBuilder: (context, index) {
                if (hiddenLoadMoreCount > 0 && index == 0) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: listItemCount == 1 ? 0 : 14,
                    ),
                    child: _TranscriptLoadEarlierButton(
                      hiddenMessageCount: hiddenMessageCount,
                      loading: _loadingOlderMessages,
                      onPressed: () {
                        widget.onRevealOlderMessages();
                        unawaited(_revealOlderMessages(displayMessages.length));
                      },
                    ),
                  );
                }
                final messageIndex = index - hiddenLoadMoreCount;
                if (messageIndex >= _renderEntries.length) {
                  return _SessionErrorBanner(
                    error: userVisibleError!,
                    onDismiss: () async {
                      _dismissedErrorIds.add(userVisibleError.id);
                      setState(() {
                        if (_visibleErrorId == userVisibleError.id) {
                          _visibleErrorId = null;
                        }
                        if (_pendingPresentedErrorId == userVisibleError.id) {
                          _pendingPresentedErrorId = null;
                        }
                      });
                      await widget.onDismissError(userVisibleError);
                    },
                  );
                }
                final entry = _renderEntries[messageIndex];
                final message = entry.message;
                final visibleMessageIndex = visibleMessageIndexById[message.id];
                final isSelected =
                    !entry.exiting && _selectedMessageId == message.id;
                final isLastVisibleMessage =
                    visibleMessageIndex != null &&
                    visibleMessageIndex == visibleMessages.length - 1;
                final hasLaterVisibleMessages =
                    visibleMessageIndex != null &&
                    visibleMessageIndex < visibleMessages.length - 1;
                return _TranscriptAnimatedMessageEntry(
                  key: ValueKey<String>('transcript-entry-${message.id}'),
                  entering: entry.entering,
                  exiting: entry.exiting,
                  bottomSpacing: messageIndex == _renderEntries.length - 1
                      ? 0
                      : 14,
                  onExitCompleted: () =>
                      _handleRenderEntryExitCompleted(message.id),
                  child: IgnorePointer(
                    ignoring: entry.exiting,
                    child: RepaintBoundary(
                      child: _MessageBubble(
                        key: ValueKey<String>(message.id),
                        message: message,
                        sessionTitle: session.title,
                        sessionEnvironment: session.environment,
                        showReasoningSweep:
                            !entry.exiting &&
                            widget.sendPhase == AiSendPhase.responding &&
                            _isStreamingReasoningMessage(message),
                        trackLayoutChanges:
                            !entry.exiting &&
                            _shouldTrackMessageLayout(
                              message: message,
                              sendPhase: widget.sendPhase,
                              isLastVisibleMessage: isLastVisibleMessage,
                            ),
                        onLayoutChanged: widget.onLayoutChanged,
                        isSelected: isSelected,
                        onSelect: () {
                          if (_selectedMessageId == message.id) {
                            return;
                          }
                          setState(() {
                            _selectedMessageId = message.id;
                          });
                        },
                        onDeselect: () {
                          if (_selectedMessageId != message.id) {
                            return;
                          }
                          setState(() {
                            _selectedMessageId = null;
                          });
                        },
                        onEdit:
                            !entry.exiting &&
                                message.kind == AiSessionMessageKind.user
                            ? () => widget.onEditMessage(message)
                            : null,
                        onCopy: () => widget.onCopyMessage(message),
                        onDelete: () async {
                          if (entry.exiting) {
                            return;
                          }
                          await _runDeleteAction(
                            message,
                            widget.onDeleteMessage,
                          );
                        },
                        onDeleteFromHere:
                            !entry.exiting && hasLaterVisibleMessages
                            ? () => _runDeleteAction(
                                message,
                                widget.onDeleteMessageFromHere,
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptAnimatedMessageEntry extends StatefulWidget {
  const _TranscriptAnimatedMessageEntry({
    super.key,
    required this.entering,
    required this.exiting,
    required this.bottomSpacing,
    required this.onExitCompleted,
    required this.child,
  });

  final bool entering;
  final bool exiting;
  final double bottomSpacing;
  final VoidCallback onExitCompleted;
  final Widget child;

  @override
  State<_TranscriptAnimatedMessageEntry> createState() =>
      _TranscriptAnimatedMessageEntryState();
}

class _TranscriptAnimatedMessageEntryState
    extends State<_TranscriptAnimatedMessageEntry>
    with SingleTickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 420);

  AnimationController? _entranceCtrl;
  Animation<double>? _opacity;
  Animation<double>? _scale;
  Animation<Offset>? _slide;

  @override
  void initState() {
    super.initState();
    if (widget.entering) {
      _entranceCtrl = AnimationController(
        duration: _entranceDuration,
        vsync: this,
      );
      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl!,
          curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
        ),
      );
      _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
        CurvedAnimation(parent: _entranceCtrl!, curve: Curves.easeOutBack),
      );
      _slide = Tween<Offset>(begin: const Offset(0.0, 0.04), end: Offset.zero)
          .animate(
            CurvedAnimation(parent: _entranceCtrl!, curve: Curves.easeOutCubic),
          );
      _entranceCtrl!.forward();
    }
  }

  @override
  void dispose() {
    _entranceCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: widget.child,
    );

    // Exit animation takes priority.
    if (widget.exiting) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: _transcriptMessageDeleteAnimationDuration,
        curve: Curves.easeInOutCubic,
        onEnd: widget.onExitCompleted,
        builder: (context, value, child) {
          final clampedValue = value.clamp(0.0, 1.0);
          final exitProgress = 1 - clampedValue;
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: clampedValue,
              child: Opacity(
                opacity: clampedValue,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    -8 * Curves.easeOutCubic.transform(exitProgress),
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: child,
      );
    }

    // Entrance animation (plays once on mount for newly added messages).
    if (_entranceCtrl != null) {
      return FadeTransition(
        opacity: _opacity!,
        child: ScaleTransition(
          scale: _scale!,
          alignment: Alignment.topCenter,
          child: SlideTransition(position: _slide!, child: child),
        ),
      );
    }

    // Fast path: no animation.
    return child;
  }
}

class _TranscriptLoadEarlierButton extends StatelessWidget {
  const _TranscriptLoadEarlierButton({
    required this.hiddenMessageCount,
    required this.loading,
    required this.onPressed,
  });

  final int hiddenMessageCount;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _localizedText(
      context,
      zh: loading ? '加载更早消息中...' : '加载更早消息（$hiddenMessageCount）',
      en: loading
          ? 'Loading earlier messages...'
          : 'Load earlier messages ($hiddenMessageCount)',
    );
    return Center(
      child: OutlinedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.history_rounded, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _SessionErrorBanner extends StatelessWidget {
  const _SessionErrorBanner({required this.error, required this.onDismiss});

  final AiSessionErrorRecord error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  presentation.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: ValueKey<String>('session-error-dismiss-${error.id}'),
            onPressed: onDismiss,
            tooltip: _localizedText(context, zh: '关闭提示', en: 'Dismiss'),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSessionTitleText extends StatelessWidget {
  const _AnimatedSessionTitleText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _sessionTitleRevealAnimationDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            ...previousChildren,
            ...?(currentChild == null ? null : <Widget>[currentChild]),
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final slide =
            Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            );
        final scale = Tween<double>(begin: 0.96, end: 1).animate(curved);
        return ClipRect(
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          ),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    this.liveRuntimeToolPreview,
    this.sendPhase = AiSendPhase.idle,
    this.planTimelineCollapsed = false,
    this.onPlanTimelineCollapsedChanged,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final runtimeStatus = _runtimeToolCatalogStatus(
      session,
      livePreview: liveRuntimeToolPreview,
    );
    final planTimeline = _buildPlanTimelineData(
      context,
      session,
      sendPhase,
      requiresReview: runtimeStatus.planRecoveryRequired,
    );
    final showPlanTimelineToggle =
        planTimeline != null && onPlanTimelineCollapsedChanged != null;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _AnimatedSessionTitleText(
                        text: session.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: Row(
                          children: [
                            _ToolbarPill(
                              icon: _runtimeModeIcon(runtimeStatus),
                              label: _runtimeModeLabel(
                                context,
                                runtimeStatus,
                                compact: true,
                              ),
                            ),
                            if (runtimeStatus.notices.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _ToolbarPill(
                                icon: Icons.info_outline_rounded,
                                label: _localizedText(
                                  context,
                                  zh: '运行时 Notice ${runtimeStatus.notices.length}',
                                  en: 'Runtime Notices ${runtimeStatus.notices.length}',
                                ),
                                onTap: () {
                                  _showSessionMetadataDialog(
                                    context,
                                    session,
                                    liveRuntimeToolPreview:
                                        liveRuntimeToolPreview,
                                  );
                                },
                              ),
                            ],
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.layers_rounded,
                              label:
                                  '${session.templateName} · v${session.templateInternalVersion}',
                            ),
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.data_object_rounded,
                              label: _localizedText(
                                context,
                                zh: '会话元数据',
                                en: 'Session Metadata',
                              ),
                              onTap: () {
                                _showSessionMetadataDialog(
                                  context,
                                  session,
                                  liveRuntimeToolPreview:
                                      liveRuntimeToolPreview,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _ToolbarPill(
                              icon: Icons.update_rounded,
                              label: _formatDateTime(session.updatedAt),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showPlanTimelineToggle && planTimelineCollapsed) ...[
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _ToolbarPill(
                    key: ValueKey<bool>(planTimelineCollapsed),
                    icon: planTimelineCollapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    label: planTimelineCollapsed
                        ? _localizedText(context, zh: '展开计划', en: 'Show Plan')
                        : _localizedText(context, zh: '收起计划', en: 'Hide Plan'),
                    onTap: () {
                      onPlanTimelineCollapsedChanged?.call(
                        !planTimelineCollapsed,
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(width: 10),
              _TokenDial(
                totalTokens: session.statistics.totalTokens ?? 0,
                cacheReadTokens: session.statistics.cacheReadTokens,
                cacheCreationTokens: session.statistics.cacheCreationTokens,
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: _planTimelineRevealAnimationDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...previousChildren,
                  currentChild ?? const SizedBox.shrink(),
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return ClipRect(
                child: FadeTransition(
                  opacity: fade,
                  child: SizeTransition(
                    sizeFactor: fade,
                    axisAlignment: -1,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.04),
                        end: Offset.zero,
                      ).animate(fade),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: planTimeline == null || planTimelineCollapsed
                ? const SizedBox(key: ValueKey<String>('plan-timeline-hidden'))
                : Padding(
                    key: ValueKey<String>(
                      'plan-timeline-visible-${planTimeline.awaitingApproval}-${planTimeline.requiresReview}-${planTimeline.steps.length}',
                    ),
                    padding: const EdgeInsets.only(top: 12),
                    child: _SessionPlanTimelineBar(
                      data: planTimeline,
                      onVisibilityToggle: showPlanTimelineToggle
                          ? () {
                              onPlanTimelineCollapsedChanged?.call(true);
                            }
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: _borderRadius999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: child,
      ),
    );
  }
}

enum _PlanTimelineStepState { completed, current, pending, failed }

class _PlanTimelineStep {
  const _PlanTimelineStep({
    required this.id,
    required this.label,
    required this.state,
  });

  final String id;
  final String label;
  final _PlanTimelineStepState state;
}

class _PlanTimelineData {
  const _PlanTimelineData({
    required this.awaitingApproval,
    required this.requiresReview,
    required this.steps,
  });

  final bool awaitingApproval;
  final bool requiresReview;
  final List<_PlanTimelineStep> steps;

  int get completedStepCount {
    return steps
        .where((item) => item.state == _PlanTimelineStepState.completed)
        .length;
  }

  bool get isComplete {
    return steps.isNotEmpty &&
        steps.every((item) => item.state == _PlanTimelineStepState.completed);
  }

  bool get hasFailedStep {
    return steps.any((item) => item.state == _PlanTimelineStepState.failed);
  }
}

class _SessionPlanTimelineBar extends StatelessWidget {
  const _SessionPlanTimelineBar({required this.data, this.onVisibilityToggle});

  final _PlanTimelineData data;
  final VoidCallback? onVisibilityToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = data.awaitingApproval
        ? colorScheme.secondary
        : data.requiresReview
        ? colorScheme.tertiary
        : data.hasFailedStep
        ? colorScheme.error
        : data.isComplete
        ? colorScheme.primary
        : colorScheme.tertiary;
    final headline = data.awaitingApproval
        ? _localizedText(context, zh: '计划待确认', en: 'Plan Awaiting Approval')
        : data.requiresReview
        ? _localizedText(context, zh: '计划待复核', en: 'Plan Needs Review')
        : data.hasFailedStep
        ? _localizedText(context, zh: '计划需要处理', en: 'Plan Needs Attention')
        : data.isComplete
        ? _localizedText(context, zh: '计划已完成', en: 'Plan Completed')
        : _localizedText(context, zh: '计划推进中', en: 'Plan In Progress');
    final subtitle = data.awaitingApproval
        ? _localizedText(
            context,
            zh: '请确认后开始执行',
            en: 'Confirm to begin execution',
          )
        : data.requiresReview
        ? _localizedText(
            context,
            zh: '继续前先检查已完成步骤、产物和 Todo',
            en: 'Inspect completed steps, artifacts, and todos before resuming',
          )
        : data.hasFailedStep
        ? _localizedText(
            context,
            zh: '当前步骤执行失败，请检查后继续',
            en: 'A step failed. Review it and continue.',
          )
        : _localizedText(
            context,
            zh: '已完成 ${data.completedStepCount}/${data.steps.length} 项',
            en: '${data.completedStepCount}/${data.steps.length} steps completed',
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: _borderRadius18,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            statusColor.withValues(alpha: 0.08),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  data.awaitingApproval
                      ? Icons.fact_check_outlined
                      : data.requiresReview
                      ? Icons.manage_search_rounded
                      : data.isComplete
                      ? Icons.task_alt_rounded
                      : Icons.timeline_rounded,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onVisibilityToggle != null) ...[
                _PlanTimelineVisibilityButton(
                  label: _localizedText(context, zh: '收起计划', en: 'Hide Plan'),
                  icon: Icons.unfold_less_rounded,
                  color: statusColor,
                  onTap: onVisibilityToggle!,
                ),
                const SizedBox(width: 12),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  data.awaitingApproval
                      ? _localizedText(context, zh: '等待确认', en: 'Pending')
                      : data.requiresReview
                      ? _localizedText(context, zh: '待复核', en: 'Review')
                      : '${data.completedStepCount}/${data.steps.length}',
                  key: ValueKey<String>(
                    '${data.awaitingApproval}-${data.requiresReview}-${data.completedStepCount}-${data.steps.length}',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < data.steps.length; index++)
                  _SessionPlanTimelineStepChip(
                    index: index,
                    step: data.steps[index],
                    isLast: index == data.steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTimelineVisibilityButton extends StatelessWidget {
  const _PlanTimelineVisibilityButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: _borderRadius999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          color.withValues(alpha: 0.08),
        ),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: _borderRadius999,
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionPlanTimelineStepChip extends StatelessWidget {
  const _SessionPlanTimelineStepChip({
    required this.index,
    required this.step,
    required this.isLast,
  });

  final int index;
  final _PlanTimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = step.state;
    final accentColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.primary,
      _PlanTimelineStepState.current => colorScheme.tertiary,
      _PlanTimelineStepState.failed => colorScheme.error,
      _PlanTimelineStepState.pending => colorScheme.outline,
    };
    final backgroundColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.primaryContainer,
      _PlanTimelineStepState.current => colorScheme.tertiaryContainer,
      _PlanTimelineStepState.failed => colorScheme.errorContainer,
      _PlanTimelineStepState.pending => colorScheme.surface,
    };
    final foregroundColor = switch (state) {
      _PlanTimelineStepState.completed => colorScheme.onPrimaryContainer,
      _PlanTimelineStepState.current => colorScheme.onTertiaryContainer,
      _PlanTimelineStepState.failed => colorScheme.onErrorContainer,
      _PlanTimelineStepState.pending => colorScheme.onSurfaceVariant,
    };
    final marker = switch (state) {
      _PlanTimelineStepState.completed => Icon(
        Icons.check_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.current => Icon(
        Icons.play_arrow_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.failed => Icon(
        Icons.close_rounded,
        size: 13,
        color: accentColor,
      ),
      _PlanTimelineStepState.pending => Text(
        '${index + 1}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: accentColor,
        ),
      ),
    };
    final chipContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: _borderRadius999,
          ),
          alignment: Alignment.center,
          child: marker,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            step.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ),
      ],
    );
    final chipDecoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      boxShadow: state == _PlanTimelineStepState.current
          ? <BoxShadow>[
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ]
          : const <BoxShadow>[],
    );
    final chip = state == _PlanTimelineStepState.current
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: chipDecoration.boxShadow,
            ),
            child: _SweepBadge(
              backgroundColor: backgroundColor,
              borderColor: accentColor.withValues(alpha: 0.22),
              sweepColor: Colors.white.withValues(alpha: 0.20),
              child: chipContent,
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: chipDecoration,
            child: chipContent,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        if (!isLast)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 18,
              height: 2,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.28),
                borderRadius: _borderRadius999,
              ),
            ),
          ),
      ],
    );
  }
}

_PlanTimelineData? _buildPlanTimelineData(
  BuildContext context,
  AiSession session,
  AiSendPhase sendPhase, {
  bool requiresReview = false,
}) {
  if (session.mode != AiSessionMode.plan) {
    return null;
  }
  final activePlanRecord = _activePlanRecordForTimeline(session);
  if (activePlanRecord != null) {
    final planRecordTimeline = _buildPlanTimelineDataFromPlanRecord(
      session,
      activePlanRecord,
      sendPhase,
    );
    if (planRecordTimeline != null) {
      return planRecordTimeline;
    }
  }
  if (_shouldSuppressInactivePlanTimeline(session)) {
    return null;
  }
  final reflectRunningStepFailure = _shouldReflectCurrentPlanStepFailure(
    session,
    sendPhase,
  );
  final todoSteps = _planTimelineTodoSteps(
    session.todoItems,
    reflectRunningStepFailure: reflectRunningStepFailure,
    reviewCompletedPlan: _shouldReviewCompletedPlan(session),
    allowTerminalFailureStates: sendPhase == AiSendPhase.idle,
  );
  if (todoSteps.isNotEmpty) {
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      requiresReview: requiresReview,
      steps: todoSteps,
    );
  }
  final pendingPlanSteps = _planTimelineStepsFromPendingPlan(
    session.pendingPlan,
  );
  if (pendingPlanSteps.isNotEmpty) {
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: session.awaitingPlanApproval,
        idPrefix: 'plan-step',
      ),
    );
  }
  return null;
}

_PlanTimelineData? _buildPlanTimelineDataFromPlanRecord(
  AiSession session,
  AiSessionPlanRecord planRecord,
  AiSendPhase sendPhase,
) {
  if (planRecord.status == AiSessionPlanStatus.cancelled ||
      planRecord.status == AiSessionPlanStatus.completed) {
    return null;
  }
  if (planRecord.status == AiSessionPlanStatus.pendingApproval) {
    final pendingPlanSteps = _planTimelineStepsFromPlanRecord(planRecord);
    if (pendingPlanSteps.isEmpty) {
      return null;
    }
    return _PlanTimelineData(
      awaitingApproval: true,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: true,
        idPrefix: 'plan-step-${planRecord.id}',
      ),
    );
  }
  final effectivePlanRecordFailed =
      planRecord.status == AiSessionPlanStatus.failed &&
      sendPhase == AiSendPhase.idle;
  final todoSteps = _planTimelineTodoSteps(
    planRecord.steps,
    reflectRunningStepFailure:
        effectivePlanRecordFailed ||
        _shouldReflectCurrentPlanStepFailure(session, sendPhase),
    reviewCompletedPlan: false,
    allowTerminalFailureStates: sendPhase == AiSendPhase.idle,
  );
  if (todoSteps.isEmpty) {
    final pendingPlanSteps = _planTimelineStepsFromPlanRecord(planRecord);
    if (pendingPlanSteps.isEmpty) {
      return null;
    }
    return _PlanTimelineData(
      awaitingApproval: false,
      requiresReview: false,
      steps: _planTimelinePendingSteps(
        pendingPlanSteps,
        awaitingApproval: false,
        idPrefix: 'plan-step-${planRecord.id}',
        markCurrentStepFailed: effectivePlanRecordFailed,
      ),
    );
  }
  return _PlanTimelineData(
    awaitingApproval: false,
    requiresReview: false,
    steps: todoSteps,
  );
}

List<_PlanTimelineStep> _planTimelinePendingSteps(
  List<String> stepLabels, {
  required bool awaitingApproval,
  required String idPrefix,
  bool markCurrentStepFailed = false,
}) {
  final normalizedLabels = stepLabels
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (normalizedLabels.isEmpty) {
    return const <_PlanTimelineStep>[];
  }
  return normalizedLabels
      .asMap()
      .entries
      .map((entry) {
        final isFirstStep = entry.key == 0;
        return _PlanTimelineStep(
          id: '$idPrefix-${entry.key}',
          label: entry.value,
          state: awaitingApproval
              ? _PlanTimelineStepState.pending
              : isFirstStep
              ? markCurrentStepFailed
                    ? _PlanTimelineStepState.failed
                    : _PlanTimelineStepState.current
              : _PlanTimelineStepState.pending,
        );
      })
      .toList(growable: false);
}

List<_PlanTimelineStep> _planTimelineTodoSteps(
  List<AiSessionTodoItem> todoItems, {
  required bool reflectRunningStepFailure,
  required bool reviewCompletedPlan,
  required bool allowTerminalFailureStates,
}) {
  final todoSteps = <_PlanTimelineStep>[];
  var hasInProgressStep = false;
  var hasFailedStep = false;
  for (final item in todoItems) {
    final label = item.content.trim();
    if (label.isEmpty) {
      continue;
    }
    final state = switch (item.status.trim().toLowerCase()) {
      'completed' => _PlanTimelineStepState.completed,
      'in_progress' when reflectRunningStepFailure =>
        _PlanTimelineStepState.failed,
      'in_progress' => _PlanTimelineStepState.current,
      'failed' || 'blocked' || 'cancelled' when allowTerminalFailureStates =>
        _PlanTimelineStepState.failed,
      'failed' || 'blocked' || 'cancelled' => _PlanTimelineStepState.pending,
      _ => _PlanTimelineStepState.pending,
    };
    if (state == _PlanTimelineStepState.current) {
      hasInProgressStep = true;
    }
    if (state == _PlanTimelineStepState.failed) {
      hasFailedStep = true;
    }
    todoSteps.add(
      _PlanTimelineStep(id: item.id.trim(), label: label, state: state),
    );
  }
  if (todoSteps.isEmpty) {
    return const <_PlanTimelineStep>[];
  }
  if (!hasInProgressStep && !hasFailedStep) {
    final firstPendingIndex = todoSteps.indexWhere(
      (item) => item.state == _PlanTimelineStepState.pending,
    );
    if (firstPendingIndex >= 0) {
      todoSteps[firstPendingIndex] = _PlanTimelineStep(
        id: todoSteps[firstPendingIndex].id,
        label: todoSteps[firstPendingIndex].label,
        state: reflectRunningStepFailure
            ? _PlanTimelineStepState.failed
            : _PlanTimelineStepState.current,
      );
    } else if (reviewCompletedPlan) {
      final lastCompletedIndex = todoSteps.lastIndexWhere(
        (item) => item.state == _PlanTimelineStepState.completed,
      );
      if (lastCompletedIndex >= 0) {
        todoSteps[lastCompletedIndex] = _PlanTimelineStep(
          id: todoSteps[lastCompletedIndex].id,
          label: todoSteps[lastCompletedIndex].label,
          state: _PlanTimelineStepState.current,
        );
      }
    }
  }
  return todoSteps;
}

bool _shouldSuppressInactivePlanTimeline(AiSession session) {
  final latestPlanRecord = session.latestPlanRecord;
  if (latestPlanRecord == null || latestPlanRecord.status.isActive) {
    return false;
  }
  return true;
}

AiSessionPlanRecord? _activePlanRecordForTimeline(AiSession session) {
  final activePlanRecord = session.latestActivePlanRecord;
  if (activePlanRecord == null || _hasTransientPlanState(session)) {
    return activePlanRecord;
  }
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return activePlanRecord;
  }
  return _planTimelineMessageActivityAt(
        latestUserMessage,
      ).isAfter(activePlanRecord.updatedAt)
      ? null
      : activePlanRecord;
}

bool _hasTransientPlanState(AiSession session) {
  return session.awaitingPlanApproval ||
      session.todoItems.isNotEmpty ||
      (session.pendingPlan ?? '').trim().isNotEmpty;
}

List<String> _planTimelineStepsFromPlanRecord(AiSessionPlanRecord planRecord) {
  final planSteps = _planTimelineStepsFromPendingPlan(planRecord.plan);
  if (planSteps.isNotEmpty) {
    return planSteps;
  }
  return planRecord.steps
      .map((item) => item.content.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _shouldReflectCurrentPlanStepFailure(
  AiSession session,
  AiSendPhase sendPhase,
) {
  if (sendPhase != AiSendPhase.idle) {
    return false;
  }
  final latestRecoveryMessage = _latestPlanRecoveryTimelineMessage(session);
  if (_shouldReflectPlanTimelineFailureAfter(
    _latestPlanErrorFailureAt(session),
    latestRecoveryMessage,
  )) {
    return true;
  }
  return _shouldReflectPlanTimelineFailureAfter(
    _latestPlanToolFailureAt(session),
    latestRecoveryMessage,
  );
}

bool _shouldReflectPlanTimelineFailureAfter(
  DateTime? latestFailureAt,
  AiSessionMessage? latestRecoveryMessage,
) {
  if (latestFailureAt == null) {
    return false;
  }
  if (latestRecoveryMessage == null) {
    return true;
  }
  return !latestRecoveryMessage.createdAt.isAfter(latestFailureAt);
}

DateTime? _latestPlanToolFailureAt(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
      continue;
    }
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      continue;
    }
    if (!_isFailurePlanTimelineToolStatus(status)) {
      return null;
    }
    return _readToolExecutionFinishedAt(message) ?? message.createdAt;
  }
  return null;
}

DateTime? _latestPlanErrorFailureAt(AiSession session) {
  for (final error in session.recentErrors) {
    if (_isPlanTimelineRelevantErrorStage(error.stage)) {
      return error.createdAt;
    }
  }
  return null;
}

bool _isFailurePlanTimelineToolStatus(String status) {
  return switch (status) {
    'failed' ||
    'cancelled' ||
    'denied' ||
    'rejected' ||
    'timed_out' ||
    'invalid_arguments' => true,
    _ => false,
  };
}

bool _isPlanTimelineRelevantErrorStage(String stage) {
  return switch (stage.trim().toLowerCase()) {
    'chat_request' ||
    'chat_continuation_request' ||
    'chat_stream' ||
    'follow_up_request' ||
    'tool_execution' ||
    'tool_loop' => true,
    _ => false,
  };
}

DateTime? _readToolExecutionFinishedAt(AiSessionMessage message) {
  final rawValue = '${message.metadata['tool_execution_finished_at'] ?? ''}'
      .trim();
  if (rawValue.isEmpty) {
    return null;
  }
  try {
    return DateTime.parse(rawValue).toUtc();
  } catch (_) {
    return null;
  }
}

AiSessionMessage? _latestPlanRecoveryTimelineMessage(AiSession session) {
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return null;
  }
  return _looksLikePlanRecoveryTimelineMessage(latestUserMessage.content)
      ? latestUserMessage
      : null;
}

bool _shouldReviewCompletedPlan(AiSession session) {
  if (session.mode != AiSessionMode.plan || session.awaitingPlanApproval) {
    return false;
  }
  if (!_hasOnlyCompletedPlanTodoItems(session.todoItems)) {
    return false;
  }
  final latestUserMessage = _latestActiveUserMessage(session);
  if (latestUserMessage == null) {
    return false;
  }
  return _looksLikePlanRecoveryTimelineMessage(latestUserMessage.content);
}

bool _hasOnlyCompletedPlanTodoItems(List<AiSessionTodoItem> todoItems) {
  return todoItems.isNotEmpty &&
      todoItems.every(
        (item) => item.status.trim().toLowerCase() == 'completed',
      );
}

AiSessionMessage? _latestActiveUserMessage(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (!message.isDeleted && message.kind == AiSessionMessageKind.user) {
      return message;
    }
  }
  return null;
}

DateTime _planTimelineMessageActivityAt(AiSessionMessage message) {
  final editedAt = '${message.metadata['edited_at'] ?? ''}'.trim();
  if (editedAt.isNotEmpty) {
    try {
      return DateTime.parse(editedAt).toUtc();
    } catch (_) {}
  }
  return message.createdAt;
}

bool _looksLikePlanRecoveryTimelineMessage(String content) {
  final normalized = content.trim().toLowerCase();
  if (normalized.isEmpty) {
    return false;
  }
  const recoveryPhrases = <String>[
    'continue',
    'continue.',
    'go on',
    'keep going',
    'continue implementation',
    'finish it',
    'retry',
    'retry it',
    'retry the step',
    'retry the failed step',
    'resume',
    '继续',
    '继续吧',
    '继续做',
    '继续完成',
    '继续实施',
    '继续执行',
    '接着',
    '接着做',
    '重试',
    '重试一下',
    '重新执行',
    '重新试',
    '恢复执行',
  ];
  return recoveryPhrases.any((phrase) => normalized.contains(phrase));
}

List<String> _planTimelineStepsFromPendingPlan(String? pendingPlan) {
  final normalizedPlan = (pendingPlan ?? '').trim();
  if (normalizedPlan.isEmpty) {
    return const <String>[];
  }
  return normalizedPlan
      .split('\n')
      .map(_structuredPlanTimelineStepLabel)
      .whereType<String>()
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

String? _structuredPlanTimelineStepLabel(String rawLine) {
  final normalizedLine = rawLine.trim();
  if (normalizedLine.isEmpty) {
    return null;
  }
  final match = _planTimelineStepPrefixPattern.firstMatch(normalizedLine);
  if (match == null) {
    return null;
  }
  final label = normalizedLine.substring(match.end).trim();
  return label.isEmpty ? null : label;
}

Future<void> _showSessionMetadataDialog(
  BuildContext context,
  AiSession session, {
  AiRuntimeToolPreview? liveRuntimeToolPreview,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionMetadataDialog(
      session: session,
      liveRuntimeToolPreview: liveRuntimeToolPreview,
    ),
  );
}

int _metadataInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
}

List<Map<String, Object?>> _metadataObjectList(Object? rawValue) {
  if (rawValue is! List) {
    return const <Map<String, Object?>>[];
  }
  return rawValue
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

List<String> _metadataStringList(Object? rawValue) {
  if (rawValue is! List) {
    return const <String>[];
  }
  return rawValue
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class _RuntimeToolCatalogStatus {
  const _RuntimeToolCatalogStatus({
    required this.sessionMode,
    required this.hasSnapshot,
    required this.stale,
    required this.isLivePreview,
    required this.awaitingPlanApproval,
    required this.planRecoveryRequired,
    required this.planExecutionApproved,
    required this.hasActiveTodoItems,
    required this.hasPendingPlan,
    required this.toolCount,
    required this.toolNames,
    required this.notices,
    required this.gateReason,
    required this.supportsToolCalls,
  });

  final AiSessionMode sessionMode;
  final bool hasSnapshot;
  final bool stale;
  final bool isLivePreview;
  final bool awaitingPlanApproval;
  final bool planRecoveryRequired;
  final bool planExecutionApproved;
  final bool hasActiveTodoItems;
  final bool hasPendingPlan;
  final int toolCount;
  final List<String> toolNames;
  final List<String> notices;
  final String gateReason;
  final bool supportsToolCalls;

  bool get hasActivePlanState => hasActiveTodoItems || hasPendingPlan;
}

_RuntimeToolCatalogStatus _runtimeToolCatalogStatus(
  AiSession session, {
  AiRuntimeToolPreview? livePreview,
}) {
  if (livePreview != null) {
    return _RuntimeToolCatalogStatus(
      sessionMode: livePreview.sessionMode,
      hasSnapshot: true,
      stale: false,
      isLivePreview: true,
      awaitingPlanApproval: livePreview.awaitingPlanApproval,
      planRecoveryRequired: livePreview.planRecoveryInspectionRequired,
      planExecutionApproved: livePreview.planExecutionApproved,
      hasActiveTodoItems: session.todoItems.isNotEmpty,
      hasPendingPlan: (session.pendingPlan ?? '').trim().isNotEmpty,
      toolCount: livePreview.toolCount,
      toolNames: livePreview.toolNames,
      notices: livePreview.notices,
      gateReason: livePreview.gateReason,
      supportsToolCalls: livePreview.supportsToolCalls,
    );
  }
  final metadata = session.lastPromptMetadata;
  final toolNames = _metadataStringList(metadata['current_tool_names']);
  final notices = _metadataStringList(metadata['runtime_tool_catalog_notices']);
  final rawToolCount = _metadataInt(metadata['current_tool_count']);
  final awaitingPlanApproval =
      metadata['awaiting_plan_approval'] == true ||
      session.awaitingPlanApproval;
  final planRecoveryRequired =
      metadata['plan_mode_recovery_inspection_required'] == true ||
      metadata['plan_recovery_required'] == true;
  final planExecutionApproved =
      metadata['plan_mode_execution_approved_for_send'] == true;
  final hasActiveTodoItems = session.todoItems.isNotEmpty;
  final hasPendingPlan = (session.pendingPlan ?? '').trim().isNotEmpty;
  var gateReason = '${metadata['runtime_tool_gate_reason'] ?? ''}'.trim();
  if (gateReason.isEmpty) {
    if (awaitingPlanApproval) {
      gateReason = 'awaiting_plan_approval';
    } else if (session.mode != AiSessionMode.plan) {
      gateReason = metadata.isEmpty ? 'no_runtime_snapshot' : 'chat_mode';
    } else if (planRecoveryRequired) {
      gateReason = 'plan_mode_recovery_inspection';
    } else if (planExecutionApproved) {
      gateReason = 'plan_mode_execution';
    } else if (hasActiveTodoItems) {
      gateReason = 'plan_mode_planning_with_exit_allowed';
    } else {
      gateReason = 'plan_mode_planning_only';
    }
  }
  return _RuntimeToolCatalogStatus(
    sessionMode: session.mode,
    hasSnapshot: metadata.isNotEmpty,
    stale: metadata['runtime_tool_catalog_stale'] == true,
    isLivePreview: false,
    awaitingPlanApproval: awaitingPlanApproval,
    planRecoveryRequired: planRecoveryRequired,
    planExecutionApproved: planExecutionApproved,
    hasActiveTodoItems: hasActiveTodoItems,
    hasPendingPlan: hasPendingPlan,
    toolCount: rawToolCount > 0 ? rawToolCount : toolNames.length,
    toolNames: toolNames,
    notices: notices,
    gateReason: gateReason,
    supportsToolCalls: true,
  );
}

String _runtimeModeLabel(
  BuildContext context,
  _RuntimeToolCatalogStatus? status, {
  bool compact = false,
  AiSessionMode? explicitMode,
}) {
  final mode = explicitMode ?? status?.sessionMode ?? AiSessionMode.chat;
  if (mode != AiSessionMode.plan) {
    return _localizedText(
      context,
      zh: '聊天模式',
      en: compact ? 'Chat Mode' : 'Chat Mode',
    );
  }
  if (status != null && status.sessionMode == AiSessionMode.plan) {
    if (status.awaitingPlanApproval) {
      return _localizedText(
        context,
        zh: '计划待确认',
        en: compact ? 'Plan Awaiting' : 'Plan Awaiting Approval',
      );
    }
    if (status.planRecoveryRequired) {
      return _localizedText(
        context,
        zh: '计划待复核',
        en: compact ? 'Plan Review' : 'Plan Needs Review',
      );
    }
    if (status.planExecutionApproved) {
      return _localizedText(
        context,
        zh: '执行计划',
        en: compact ? 'Plan Execute' : 'Plan Execution',
      );
    }
    if (status.hasActivePlanState) {
      return _localizedText(
        context,
        zh: '计划规划中',
        en: compact ? 'Plan Draft' : 'Plan Drafting',
      );
    }
  }
  return _localizedText(
    context,
    zh: '计划模式',
    en: compact ? 'Plan Mode' : 'Plan Mode',
  );
}

IconData _runtimeModeIcon(
  _RuntimeToolCatalogStatus? status, {
  AiSessionMode? explicitMode,
}) {
  final mode = explicitMode ?? status?.sessionMode ?? AiSessionMode.chat;
  if (mode != AiSessionMode.plan) {
    return Icons.forum_outlined;
  }
  if (status != null && status.sessionMode == AiSessionMode.plan) {
    if (status.awaitingPlanApproval) {
      return Icons.fact_check_outlined;
    }
    if (status.planRecoveryRequired) {
      return Icons.manage_search_rounded;
    }
    if (status.planExecutionApproved) {
      return Icons.playlist_play_rounded;
    }
  }
  return Icons.alt_route_rounded;
}

String _runtimeToolCatalogStatusLabel(
  BuildContext context,
  _RuntimeToolCatalogStatus status,
) {
  if (!status.supportsToolCalls) {
    return _localizedText(
      context,
      zh: '当前模型协议不支持工具调用',
      en: 'The current model protocol does not support tool calls',
    );
  }
  if (!status.hasSnapshot) {
    return _localizedText(
      context,
      zh: '尚未生成运行时工具快照',
      en: 'No runtime tool snapshot yet',
    );
  }
  if (status.stale) {
    return _localizedText(
      context,
      zh: '工具目录已过期，等待下一轮刷新',
      en: 'The tool catalog is stale and will refresh next round',
    );
  }
  return _localizedText(
    context,
    zh: '运行时工具目录已同步',
    en: 'The runtime tool catalog is synchronized',
  );
}

String _runtimeToolGateReasonLabel(BuildContext context, String gateReason) {
  return switch (gateReason.trim()) {
    'awaiting_plan_approval' => _localizedText(
      context,
      zh: '计划待确认，当前轮不开放执行工具',
      en: 'The plan is awaiting approval, so execution tools stay hidden',
    ),
    'plan_mode_recovery_inspection' => _localizedText(
      context,
      zh: '需要先复核已有步骤、产物和 Todo',
      en: 'Review completed steps, artifacts, and todos before resuming',
    ),
    'plan_mode_execution' => _localizedText(
      context,
      zh: '计划已获准执行，当前轮开放执行工具',
      en: 'The plan is approved and execution tools are available',
    ),
    'plan_mode_planning_with_exit_allowed' => _localizedText(
      context,
      zh: '当前仅开放规划工具，可在准备好后提交执行计划',
      en: 'Only planning tools are available until the execution plan is ready',
    ),
    'plan_mode_planning_only' => _localizedText(
      context,
      zh: '当前仅开放规划工具',
      en: 'Only planning tools are available right now',
    ),
    'mode_switch_requires_refresh' => _localizedText(
      context,
      zh: '模式刚切换，等待下一轮重新计算工具目录',
      en: 'The mode just changed, so the tool catalog will refresh next round',
    ),
    'chat_mode_no_tools' => _localizedText(
      context,
      zh: '聊天模式当前没有可用工具',
      en: 'No tools are available in chat mode right now',
    ),
    'chat_mode' => _localizedText(
      context,
      zh: '聊天模式当前开放完整运行时工具目录',
      en: 'Chat mode currently exposes the full runtime catalog',
    ),
    'model_no_tool_support' => _localizedText(
      context,
      zh: '当前模型协议不支持工具调用',
      en: 'The current model protocol does not support tool calls',
    ),
    'no_runtime_snapshot' => _localizedText(
      context,
      zh: '当前还没有运行时快照，请先发起一轮请求',
      en: 'No runtime snapshot is available yet; send a request first',
    ),
    _ =>
      gateReason.isEmpty
          ? _localizedText(
              context,
              zh: '暂无门控说明',
              en: 'No gate reason available',
            )
          : gateReason,
  };
}

String _composerModeTooltip(
  BuildContext context,
  AiSessionMode mode,
  _RuntimeToolCatalogStatus? status,
) {
  if (mode != AiSessionMode.plan) {
    if (status != null && !status.supportsToolCalls) {
      return _localizedText(
        context,
        zh: '当前模型协议不支持工具调用。点击切换到计划模式。',
        en: 'The current model protocol does not support tool calls. Click to switch to plan mode.',
      );
    }
    return _localizedText(
      context,
      zh: '当前为聊天模式，点击切换到计划模式',
      en: 'Chat mode is active. Click to switch to plan mode.',
    );
  }
  if (status == null) {
    return _localizedText(
      context,
      zh: '当前为计划模式，点击切换到聊天模式',
      en: 'Plan mode is active. Click to switch to chat mode.',
    );
  }
  if (!status.supportsToolCalls) {
    return _localizedText(
      context,
      zh: '当前模型协议不支持工具调用。计划模式仍可组织步骤，但不会开放工具执行。点击切换到聊天模式。',
      en: 'The current model protocol does not support tool calls. Plan mode can still organize steps, but tool execution stays unavailable. Click to switch to chat mode.',
    );
  }
  if (status.stale) {
    return _localizedText(
      context,
      zh: '计划模式刚切换完成，运行时工具会在下一轮自动刷新。点击切换到聊天模式。',
      en: 'Plan mode just changed. Runtime tools will refresh on the next round. Click to switch to chat mode.',
    );
  }
  if (status.awaitingPlanApproval) {
    return _localizedText(
      context,
      zh: '计划待确认。当前轮不会暴露执行工具，请先确认计划。点击切换到聊天模式。',
      en: 'The plan is awaiting approval. Execution tools stay hidden until approval. Click to switch to chat mode.',
    );
  }
  if (status.planRecoveryRequired) {
    return _localizedText(
      context,
      zh: '计划待复核。继续执行前应先检查已完成步骤、产物与 Todo。点击切换到聊天模式。',
      en: 'The plan needs review. Inspect completed steps, artifacts, and todos before continuing. Click to switch to chat mode.',
    );
  }
  if (status.planExecutionApproved) {
    return _localizedText(
      context,
      zh: '计划执行中。当前轮会按运行时目录暴露执行工具。点击切换到聊天模式。',
      en: 'The plan is executing. Runtime tools are exposed according to the current catalog. Click to switch to chat mode.',
    );
  }
  return _localizedText(
    context,
    zh: '当前为计划模式，会先规划，再在获得确认后执行。点击切换到聊天模式。',
    en: 'Plan mode is active. It plans first, then executes after approval. Click to switch to chat mode.',
  );
}

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({
    required this.session,
    this.liveRuntimeToolPreview,
  });

  final AiSession session;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statistics = session.statistics;
    final environment = session.environment;
    final lastPromptMetadata = session.lastPromptMetadata;
    final runtimeStatus = _runtimeToolCatalogStatus(
      session,
      livePreview: liveRuntimeToolPreview,
    );
    final hasPromptMetadata = lastPromptMetadata.isNotEmpty;
    final writeCommandConfirmationEnabled =
        lastPromptMetadata['write_command_confirmation_enabled'] == true;
    final allowCommandRuleCount = _metadataInt(
      lastPromptMetadata['allow_command_rule_count'],
    );
    final allowCommandRules = _metadataObjectList(
      lastPromptMetadata['allow_command_rules'],
    );
    final todoWriteRecommended =
        lastPromptMetadata['todo_write_recommended'] == true;
    final todoWriteReason = '${lastPromptMetadata['todo_write_reason'] ?? ''}'
        .trim();
    final planHistory = session.planHistory.reversed.toList(growable: false);
    final currentTodos = session.todoItems
        .map((item) => item.toJson())
        .toList(growable: false);
    final recentErrors = session.recentErrors
        .where((error) => error.stage != 'title_generation')
        .toList(growable: false);
    final summaryBlocks = <Widget>[
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '消息总数', en: 'Messages'),
        value: '${statistics.totalMessageCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: 'Prompt 构建', en: 'Prompt Builds'),
        value: '${statistics.promptBuildCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '压缩次数', en: 'Compressions'),
        value: '${statistics.compressionRunCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
        value: '${statistics.totalTokens ?? 0}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '当前模式', en: 'Mode'),
        value: _runtimeModeLabel(context, runtimeStatus, compact: true),
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '运行工具', en: 'Runtime Tools'),
        value: !runtimeStatus.supportsToolCalls
            ? '-'
            : runtimeStatus.hasSnapshot && !runtimeStatus.stale
            ? '${runtimeStatus.toolCount}'
            : _localizedText(context, zh: '待刷新', en: 'Pending'),
      ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizedText(
                            context,
                            zh: '当前会话元数据',
                            en: 'Current Session Metadata',
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '会话概览',
                          en: 'Session Overview',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'session_id',
                            ),
                            value: session.id,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'template'),
                            value:
                                '${session.templateName} · v${session.templateInternalVersion}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'created_at',
                            ),
                            value: _formatDateTime(session.createdAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'updated_at',
                            ),
                            value: _formatDateTime(session.updatedAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_model',
                            ),
                            value:
                                session.lastUsedModelLabel ??
                                session.lastUsedModelId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_checkpoint',
                            ),
                            value:
                                session.latestCompressionCheckpointMessageId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'latest_compression_at',
                            ),
                            value: session.latestCompressionAt == null
                                ? '-'
                                : _formatDateTime(session.latestCompressionAt!),
                          ),
                        ],
                      ),
                      if (session.templateId == 'hardness_engineering') ...[
                        const SizedBox(height: 16),
                        _buildHardnessConfigSection(context, session),
                      ],
                      if (session.metadata.entries
                          .where(
                            (e) =>
                                !(session.templateId ==
                                        'hardness_engineering' &&
                                    e.key == 'hardness_config'),
                          )
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _MetadataSection(
                          title: _localizedText(
                            context,
                            zh: '扩展元数据',
                            en: 'Extended Metadata',
                          ),
                          children: session.metadata.entries
                              .where(
                                (e) =>
                                    !(session.templateId ==
                                            'hardness_engineering' &&
                                        e.key == 'hardness_config'),
                              )
                              .map((entry) {
                                return _MetadataEntryRow(
                                  label: entry.key,
                                  value: '${entry.value}',
                                );
                              })
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '统计信息',
                          en: 'Statistics',
                        ),
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '用户', en: 'User')} ${statistics.userMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '助手', en: 'Assistant')} ${statistics.assistantMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '工具', en: 'Tool')} ${statistics.toolMessageCount}',
                              ),
                              _MetadataChip(
                                label: 'MCP ${statistics.mcpMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '技能', en: 'Skill')} ${statistics.skillMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '压缩', en: 'Compression')} ${statistics.compressionPointCount}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_input_characters',
                            ),
                            value: '${statistics.totalInputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_output_characters',
                            ),
                            value: '${statistics.totalOutputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_prompt_characters',
                            ),
                            value: '${statistics.totalPromptCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_system_message_count',
                            ),
                            value: '${statistics.lastPromptSystemMessageCount}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_history_message_count',
                            ),
                            value:
                                '${statistics.lastPromptHistoryMessageCount}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '运行环境',
                          en: 'Environment',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'locale_tag',
                            ),
                            value: environment.localeTag,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'platform'),
                            value: environment.platform,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'app_version',
                            ),
                            value:
                                '${environment.appVersion} (${environment.appBuildNumber})',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_threshold_chars',
                            ),
                            value: '${environment.compressionThresholdChars}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'single_round_tool_call_limit',
                            ),
                            value: '${environment.singleRoundToolCallLimit}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'sequential_tool_round_limit',
                            ),
                            value: '${environment.sequentialToolRoundLimit}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'application_directory',
                            ),
                            value: environment.applicationDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'home_directory',
                            ),
                            value: environment.homeDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'settings_file',
                            ),
                            value: environment.settingsFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'skills_storage',
                            ),
                            value: environment.skillsStoragePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'mcp_servers_file',
                            ),
                            value: environment.mcpServersFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'user_memory_file',
                            ),
                            value: environment.userMemoryFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'sessions_directory',
                            ),
                            value: environment.sessionsDirectoryPath,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '命令策略',
                          en: 'Command Policy',
                        ),
                        children: !hasPromptMetadata
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前还没有可展示的 prompt 元数据。',
                                    en: 'Prompt metadata is not available yet.',
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : [
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '写命令确认',
                                    en: 'Write Confirmation',
                                  ),
                                  value: writeCommandConfirmationEnabled
                                      ? _localizedText(
                                          context,
                                          zh: '需要确认',
                                          en: 'Required',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '无需确认',
                                          en: 'Not required',
                                        ),
                                ),
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '允许规则数',
                                    en: 'Allow Rules',
                                  ),
                                  value: '$allowCommandRuleCount',
                                ),
                                if (allowCommandRules.isEmpty)
                                  Text(
                                    _localizedText(
                                      context,
                                      zh: '当前没有已上屏的允许命令规则。',
                                      en: 'There are no surfaced allow command rules.',
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: allowCommandRules
                                        .map((rule) {
                                          final pattern =
                                              '${rule['pattern'] ?? ''}'.trim();
                                          final matchMode =
                                              '${rule['match_mode'] ?? ''}'
                                                  .trim();
                                          if (pattern.isEmpty) {
                                            return null;
                                          }
                                          final prefix = matchMode.isEmpty
                                              ? ''
                                              : '$matchMode: ';
                                          return _MetadataChip(
                                            label: '$prefix$pattern',
                                          );
                                        })
                                        .whereType<Widget>()
                                        .toList(growable: false),
                                  ),
                              ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '运行时编排',
                          en: 'Runtime Orchestration',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '状态来源',
                              en: 'State Source',
                            ),
                            value: runtimeStatus.isLivePreview
                                ? _localizedText(
                                    context,
                                    zh: '根据当前模型、MCP/Skills 与 Plan 状态即时生成',
                                    en: 'Generated from the current model, MCP/skills, and plan state',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '上一轮已落盘的运行时快照',
                                    en: 'The last persisted runtime snapshot',
                                  ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前模式',
                              en: 'Mode',
                            ),
                            value: _runtimeModeLabel(context, runtimeStatus),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '工具目录状态',
                              en: 'Tool Catalog State',
                            ),
                            value: _runtimeToolCatalogStatusLabel(
                              context,
                              runtimeStatus,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '门控原因',
                              en: 'Gate Reason',
                            ),
                            value: _runtimeToolGateReasonLabel(
                              context,
                              runtimeStatus.gateReason,
                            ),
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前运行时工具数',
                              en: 'Runtime Tool Count',
                            ),
                            value:
                                runtimeStatus.hasSnapshot &&
                                    !runtimeStatus.stale
                                ? '${runtimeStatus.toolCount}'
                                : _localizedText(
                                    context,
                                    zh: '等待下一轮刷新',
                                    en: 'Refreshes next round',
                                  ),
                          ),
                          if (runtimeStatus.notices.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _localizedText(
                                context,
                                zh: '运行时 Notices',
                                en: 'Runtime Notices',
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: runtimeStatus.notices
                                  .map((item) => _MetadataChip(label: item))
                                  .toList(growable: false),
                            ),
                          ],
                          if (runtimeStatus.toolNames.isNotEmpty &&
                              !runtimeStatus.stale) ...[
                            const SizedBox(height: 12),
                            Text(
                              _localizedText(
                                context,
                                zh: '当前运行时工具',
                                en: 'Current Runtime Tools',
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: runtimeStatus.toolNames
                                  .map((item) => _MetadataChip(label: item))
                                  .toList(growable: false),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '任务跟踪',
                          en: 'Task Tracking',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前 Todo 数量',
                              en: 'Current Todos',
                            ),
                            value: '${currentTodos.length}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '计划记录数量',
                              en: 'Plan Records',
                            ),
                            value: '${planHistory.length}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: 'TodoWrite 强提醒',
                              en: 'TodoWrite Reminder',
                            ),
                            value: hasPromptMetadata
                                ? (todoWriteRecommended
                                      ? _localizedText(
                                          context,
                                          zh: '已触发',
                                          en: 'Triggered',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '未触发',
                                          en: 'Not triggered',
                                        ))
                                : _localizedText(
                                    context,
                                    zh: '暂无数据',
                                    en: 'Unavailable',
                                  ),
                          ),
                          if (todoWriteReason.isNotEmpty)
                            _MetadataEntryRow(
                              label: _localizedText(
                                context,
                                zh: '提醒原因',
                                en: 'Reminder Reason',
                              ),
                              value: todoWriteReason,
                            ),
                          if (currentTodos.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: currentTodos
                                  .map((todo) {
                                    final id = '${todo['id'] ?? ''}'.trim();
                                    final content = '${todo['content'] ?? ''}'
                                        .trim();
                                    final status = '${todo['status'] ?? ''}'
                                        .trim();
                                    if (content.isEmpty) {
                                      return null;
                                    }
                                    final prefix = status.isEmpty
                                        ? ''
                                        : '[$status] ';
                                    final idPrefix = id.isEmpty ? '' : '$id: ';
                                    return _MetadataChip(
                                      label: '$prefix$idPrefix$content',
                                    );
                                  })
                                  .whereType<Widget>()
                                  .toList(growable: false),
                            ),
                          if (planHistory.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              _localizedText(
                                context,
                                zh: '计划历史',
                                en: 'Plan History',
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...planHistory.asMap().entries.map(
                              (entry) => _MetadataPlanRecordCard(
                                planIndex: planHistory.length - entry.key,
                                planRecord: entry.value,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '最近异常',
                          en: 'Recent Errors',
                        ),
                        children: recentErrors.isEmpty
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前没有需要关注的会话异常。',
                                    en: 'There are no session errors to review.',
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : recentErrors
                                  .map(
                                    (error) => _MetadataErrorCard(error: error),
                                  )
                                  .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '最后一次 Prompt 元数据',
                          en: 'Last Prompt Metadata',
                        ),
                        children: [
                          _MetadataJsonPanel(
                            content: const JsonEncoder.withIndent(
                              '  ',
                            ).convert(session.lastPromptMetadata),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: _localizedText(context, zh: '关闭', en: 'Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _MetadataSummaryTile extends StatelessWidget {
  const _MetadataSummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: _borderRadius18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataEntryRow extends StatelessWidget {
  const _MetadataEntryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius999,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _sessionPlanStatusLabel(
  BuildContext context,
  AiSessionPlanStatus status,
) {
  return switch (status) {
    AiSessionPlanStatus.pendingApproval => _localizedText(
      context,
      zh: '待确认',
      en: 'Pending Approval',
    ),
    AiSessionPlanStatus.inProgress => _localizedText(
      context,
      zh: '进行中',
      en: 'In Progress',
    ),
    AiSessionPlanStatus.completed => _localizedText(
      context,
      zh: '已完成',
      en: 'Completed',
    ),
    AiSessionPlanStatus.failed => _localizedText(
      context,
      zh: '失败',
      en: 'Failed',
    ),
    AiSessionPlanStatus.cancelled => _localizedText(
      context,
      zh: '已取消',
      en: 'Cancelled',
    ),
  };
}

class _MetadataPlanRecordCard extends StatelessWidget {
  const _MetadataPlanRecordCard({
    required this.planIndex,
    required this.planRecord,
  });

  final int planIndex;
  final AiSessionPlanRecord planRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = switch (planRecord.status) {
      AiSessionPlanStatus.pendingApproval => colorScheme.secondary,
      AiSessionPlanStatus.inProgress => colorScheme.tertiary,
      AiSessionPlanStatus.completed => colorScheme.primary,
      AiSessionPlanStatus.failed => colorScheme.error,
      AiSessionPlanStatus.cancelled => colorScheme.outline,
    };
    final steps = planRecord.steps
        .map((item) {
          final content = item.content.trim();
          if (content.isEmpty) {
            return null;
          }
          return _MetadataChip(label: content);
        })
        .whereType<Widget>()
        .toList(growable: false);
    final planSummary = planRecord.plan.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _localizedText(
                  context,
                  zh: '计划 #$planIndex',
                  en: 'Plan #$planIndex',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: _borderRadius999,
                ),
                child: Text(
                  _sessionPlanStatusLabel(context, planRecord.status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_localizedText(context, zh: '创建', en: 'Created')} ${_formatDateTime(planRecord.createdAt)} · ${_localizedText(context, zh: '更新', en: 'Updated')} ${_formatDateTime(planRecord.updatedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (planSummary.isNotEmpty && steps.isEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              planSummary,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: steps),
          ],
        ],
      ),
    );
  }
}

class _MetadataErrorCard extends StatelessWidget {
  const _MetadataErrorCard({required this.error});

  final AiSessionErrorRecord error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    final detail = (error.detail ?? '').trim();
    final rawMessage = error.message.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            presentation.title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            presentation.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          if (detail.isNotEmpty && detail != rawMessage) ...[
            const SizedBox(height: 8),
            Text(
              _localizedText(context, zh: '错误细节', en: 'Error Detail'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_sessionErrorStageLabel(context, error.stage)} · ${_formatDateTime(error.createdAt)} · ${error.hasBeenPresented ? _localizedText(context, zh: '已展示', en: 'Presented') : _localizedText(context, zh: '未展示', en: 'Pending')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionErrorPresentation {
  const _SessionErrorPresentation({required this.title, required this.message});

  final String title;
  final String message;
}

_SessionErrorPresentation _presentSessionError(
  BuildContext context,
  AiSessionErrorRecord error,
) {
  final fallbackTitle = _sessionErrorStageLabel(context, error.stage);
  final rawMessage = error.message.trim();
  final fallbackMessage = rawMessage.isNotEmpty
      ? rawMessage
      : _localizedText(
          context,
          zh: '当前会话已提前结束。请重试或继续发送更具体的指令。',
          en: 'This session ended early. Retry the request or continue with a more specific instruction.',
        );
  return switch (error.stage) {
    'tool_loop' => _SessionErrorPresentation(
      title: _localizedText(
        context,
        zh: '工具调用已安全停止',
        en: 'Tool Calls Stopped for Safety',
      ),
      message: () {
        final configuredLimit = _extractConfiguredToolLoopLimit(
          error.detail ?? '',
        );
        final limitSuffix = configuredLimit == null
            ? ''
            : _localizedText(
                context,
                zh: ' 当前连续工具轮次上限为 $configuredLimit。',
                en: ' The current sequential tool round limit is $configuredLimit.',
              );
        return _localizedText(
              context,
              zh: '本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。这次停止发生在会话控制层，并不是某个具体工具真的执行失败。你可以让助手先总结当前进展，或给出更具体的下一步指令。',
              en: 'OpenHand stopped this session for safety after too many sequential tool rounds. This stop happened in the session controller before the next tool could run, not because one specific tool execution failed. Ask the assistant to summarize the current progress or give a more specific next step.',
            ) +
            limitSuffix;
      }(),
    ),
    'chat_stream' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '回答已中断', en: 'Response Interrupted'),
      message: _localizedText(
        context,
        zh: '本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。',
        en: 'The response was interrupted while streaming and this session has stopped. Retry the request or continue with a new message.',
      ),
    ),
    'chat_request' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '请求发送失败', en: 'Request Failed'),
      message: _localizedText(
        context,
        zh: '本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。',
        en: 'The request failed before the assistant could continue. Check the configuration and retry, or send a new message.',
      ),
    ),
    'chat_continuation_request' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '后续请求失败', en: 'Continuation Failed'),
      message: _localizedText(
        context,
        zh: '本次会话在继续执行后续步骤时，请求下一轮模型响应失败。已完成的步骤与工具结果都已保留，你可以直接回复继续/重试，或检查配置后再试。',
        en: 'The session failed while requesting the next assistant round after continuing execution. Completed steps and tool results were preserved. Reply with continue/retry, or check the configuration and try again.',
      ),
    ),
    _ => _SessionErrorPresentation(
      title: fallbackTitle,
      message: fallbackMessage,
    ),
  };
}

int? _extractConfiguredToolLoopLimit(String detail) {
  final match = _toolLoopLimitPattern.firstMatch(detail);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

String _sessionErrorStageLabel(BuildContext context, String stage) {
  return switch (stage) {
    'tool_loop' => _localizedText(context, zh: '安全停止', en: 'Safety Stop'),
    'chat_stream' => _localizedText(context, zh: '响应中断', en: 'Stream Error'),
    'chat_request' => _localizedText(context, zh: '请求失败', en: 'Request Error'),
    'chat_continuation_request' => _localizedText(
      context,
      zh: '后续请求失败',
      en: 'Continuation Error',
    ),
    'tool_execution' => _localizedText(
      context,
      zh: '工具执行失败',
      en: 'Tool Execution Error',
    ),
    'history_compression' => _localizedText(
      context,
      zh: '历史压缩失败',
      en: 'Compression Error',
    ),
    'user_prompt_hook' => _localizedText(
      context,
      zh: '提示词被拦截',
      en: 'Prompt Blocked',
    ),
    'title_generation' => _localizedText(
      context,
      zh: '标题生成失败',
      en: 'Title Generation Error',
    ),
    _ => _localizedText(context, zh: '会话异常', en: 'Session Error'),
  };
}

class _MetadataJsonPanel extends StatelessWidget {
  const _MetadataJsonPanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF17181C),
        borderRadius: _borderRadius18,
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.sessionTitle,
    required this.sessionEnvironment,
    required this.showReasoningSweep,
    required this.trackLayoutChanges,
    required this.onLayoutChanged,
    required this.isSelected,
    required this.onSelect,
    required this.onDeselect,
    required this.onCopy,
    required this.onDelete,
    this.onDeleteFromHere,
    this.onEdit,
  });

  final AiSessionMessage message;
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool trackLayoutChanges;
  final VoidCallback onLayoutChanged;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDelete;
  final Future<void> Function()? onDeleteFromHere;
  final Future<void> Function()? onEdit;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _compressionExpanded = false;
  bool? _reasoningExpandedOverride;

  // Cached expensive objects to avoid re-allocation on every build.
  List<md.InlineSyntax>? _cachedInlineSyntaxes;
  Map<String, MarkdownElementBuilder>? _cachedBuilders;
  _MessageMarkdownThemeData? _cachedMarkdownThemeData;
  String? _cachedFilePathParseKey;
  List<String>? _cachedFilePathRoots;
  String? _lastCacheMessageId;
  String? _lastCacheEnvironmentKey;
  int? _lastCacheThemeBrightness;
  bool? _lastCacheIsSelected;
  bool? _lastCacheDarkCodeSurface;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpandedOverride = null;
      _invalidateCache();
    }
  }

  void _invalidateCache() {
    _cachedInlineSyntaxes = null;
    _cachedBuilders = null;
    _cachedMarkdownThemeData = null;
    _cachedFilePathParseKey = null;
    _cachedFilePathRoots = null;
    _lastCacheMessageId = null;
    _lastCacheEnvironmentKey = null;
    _lastCacheThemeBrightness = null;
    _lastCacheIsSelected = null;
    _lastCacheDarkCodeSurface = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = widget.message;
    final isUser = message.kind == AiSessionMessageKind.user;
    final isCompressionPoint =
        message.kind == AiSessionMessageKind.compressionPoint;
    final isReasoning = message.kind == AiSessionMessageKind.reasoning;
    final isStreamingReasoning = _isStreamingReasoningMessage(message);
    final isToolCall = message.kind == AiSessionMessageKind.toolCall;
    final isToolResult =
        message.kind == AiSessionMessageKind.tool ||
        message.kind == AiSessionMessageKind.mcp ||
        message.kind == AiSessionMessageKind.skill;
    final isStatus = message.kind == AiSessionMessageKind.status;
    final attachments = AiMessageAttachment.listFromMetadata(
      message.metadata[aiSessionMessageAttachmentsMetadataKey],
    );
    final reasoningExpanded =
        _reasoningExpandedOverride ?? _shouldDefaultExpandReasoning(message);

    final alignment = isCompressionPoint
        ? Alignment.center
        : isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final borderRadius = BorderRadius.circular(isReasoning ? 18 : 26);
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isUser
        ? colorScheme.primaryContainer
        : isReasoning
        ? const Color(0xFF18181B)
        : isToolCall
        ? colorScheme.secondaryContainer
        : isToolResult
        ? colorScheme.surfaceContainerHighest
        : isStatus
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh;
    final textColor = isCompressionPoint
        ? colorScheme.onTertiaryContainer
        : isUser
        ? colorScheme.onPrimaryContainer
        : isReasoning
        ? Colors.white
        : isToolCall
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final useDarkCodeSurface = isReasoning || isToolCall;
    final environmentKey =
        '${widget.sessionEnvironment.applicationDirectory}|${_toolExecutionWorkingDirectory(message)}';
    final themeBrightness = theme.brightness.index;
    final needsCacheRefresh =
        _lastCacheMessageId != message.id ||
        _lastCacheEnvironmentKey != environmentKey ||
        _lastCacheThemeBrightness != themeBrightness ||
        _lastCacheIsSelected != widget.isSelected ||
        _lastCacheDarkCodeSurface != useDarkCodeSurface;
    if (needsCacheRefresh) {
      _lastCacheMessageId = message.id;
      _lastCacheEnvironmentKey = environmentKey;
      _lastCacheThemeBrightness = themeBrightness;
      _lastCacheIsSelected = widget.isSelected;
      _lastCacheDarkCodeSurface = useDarkCodeSurface;
      _cachedMarkdownThemeData = _MessageMarkdownThemeData.fromMessageBubble(
        theme: theme,
        backgroundColor: backgroundColor,
        textColor: textColor,
        useDarkCodeSurface: useDarkCodeSurface,
      );
      _cachedFilePathRoots = messageFilePathRoots(
        widget.sessionEnvironment,
        workingDirectory: _toolExecutionWorkingDirectory(message),
      );
      _cachedFilePathParseKey = _cachedFilePathRoots!.join('|');
      _cachedBuilders = <String, MarkdownElementBuilder>{
        'pre': _HighlightedCodeBlockBuilder(
          theme: theme,
          baseColor: textColor,
          darkSurface: useDarkCodeSurface,
          selectable: widget.isSelected,
        ),
        'openhand-file-resolved': _FilePathMarkdownBuilder(
          textColor: textColor,
          onOpenPath: _openResolvedMessagePath,
        ),
        'openhand-file-pending': _FilePathMarkdownBuilder(
          textColor: textColor,
          onOpenPath: _openResolvedMessagePath,
        ),
      };
      _cachedInlineSyntaxes = <md.InlineSyntax>[
        MessagePathCodeSyntax(candidateRoots: _cachedFilePathRoots!),
        MessageFilePathSyntax(candidateRoots: _cachedFilePathRoots!),
      ];
    }
    final markdownStyleSheet = _cachedMarkdownThemeData!;
    final filePathRoots = _cachedFilePathRoots!;
    final filePathParseKey = _cachedFilePathParseKey!;
    final markdownBuilders = _cachedBuilders!;
    final inlineSyntaxes = _cachedInlineSyntaxes!;

    // Parse Hardness Engineering agent/phase annotations from message content.
    // Only assistant-role messages can carry these markers.
    final heAnnotation =
        (!isUser &&
            !isCompressionPoint &&
            !isToolCall &&
            !isToolResult &&
            !isStatus)
        ? _parseHeAnnotation(message.content)
        : null;
    final effectiveContent = heAnnotation?.strippedContent ?? message.content;

    final bubbleBody = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (heAnnotation != null && heAnnotation.hasAnnotations)
          _HardnessAnnotationCapsuleRow(annotation: heAnnotation),
        DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: isToolCall
                ? Border.all(color: colorScheme.secondary, width: 1.2)
                : widget.isSelected
                ? Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.38),
                    width: 1.5,
                  )
                : Border.all(
                    color: colorScheme.outlineVariant.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
                    ),
                  ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
                ),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompressionPoint)
                  _MessageMetaRow(
                    icon: Icons.summarize_rounded,
                    label: AppLocalizations.of(
                      context,
                    )!.threadCompressionCheckpointLabel,
                    color: textColor,
                  )
                else if (isReasoning)
                  _ReasoningMetaRow(
                    message: message,
                    color: textColor,
                    showSweep: widget.showReasoningSweep,
                    expanded: reasoningExpanded,
                    onTap: () {
                      final nextExpanded = !reasoningExpanded;
                      setState(() {
                        _reasoningExpandedOverride = nextExpanded;
                      });
                    },
                  )
                else if (isToolCall)
                  _ToolCallMetaRow(
                    data: _ToolCallStatusViewData.from(context, message),
                    color: textColor,
                  )
                else if (isToolResult)
                  _MessageMetaRow(
                    icon: Icons.inventory_2_outlined,
                    label: _localizedText(
                      context,
                      zh: '工具结果',
                      en: 'Tool Result',
                    ),
                    color: textColor,
                  )
                else if (message.modelLabel != null)
                  Text(
                    message.modelLabel!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isUser
                          ? textColor.withValues(alpha: 0.86)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (isCompressionPoint ||
                    isReasoning ||
                    isToolCall ||
                    isToolResult ||
                    message.modelLabel != null)
                  const SizedBox(height: 10),
                if (isCompressionPoint)
                  _CompressionCheckpointBody(
                    content: message.content,
                    expanded: _compressionExpanded,
                    onToggle: () {
                      setState(() {
                        _compressionExpanded = !_compressionExpanded;
                      });
                    },
                    selectable: widget.isSelected,
                    textColor: textColor,
                    fadeColor: backgroundColor,
                    styleSheet: markdownStyleSheet.styleSheet,
                    builders: markdownBuilders,
                    inlineSyntaxes: inlineSyntaxes,
                    pathRoots: filePathRoots,
                    parseKey: filePathParseKey,
                  )
                else if (isReasoning)
                  _ReasoningBody(
                    content: message.content,
                    expanded: reasoningExpanded,
                    streaming: isStreamingReasoning,
                    selectable: widget.isSelected,
                    textColor: textColor,
                    fadeColor: backgroundColor,
                    styleSheet: markdownStyleSheet.styleSheet,
                    builders: markdownBuilders,
                    inlineSyntaxes: inlineSyntaxes,
                    pathRoots: filePathRoots,
                    parseKey: filePathParseKey,
                  )
                else if (isToolCall)
                  _ToolCallBody(message: message, selectable: widget.isSelected)
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (attachments.isNotEmpty) ...[
                        _MessageAttachmentSummaryBlock(
                          attachments: attachments,
                          textColor: textColor,
                          backgroundColor: backgroundColor,
                          onAttachmentTap: (attachment) =>
                              _openAttachment(context, attachment),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SafeMarkdownBody(
                        data: effectiveContent.isEmpty ? ' ' : effectiveContent,
                        selectable: widget.isSelected,
                        builders: markdownBuilders,
                        styleSheet: markdownStyleSheet.styleSheet,
                        inlineSyntaxes: inlineSyntaxes,
                        pathRoots: filePathRoots,
                        parseKey: filePathParseKey,
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  _formatDateTime(message.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.isSelected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _MessageActionButton(
                  onPressed: widget.onCopy,
                  icon: Icons.content_copy_outlined,
                  label: _localizedText(context, zh: '复制', en: 'Copy'),
                ),
                if (widget.onEdit != null)
                  _MessageActionButton(
                    onPressed: widget.onEdit,
                    icon: Icons.edit_outlined,
                    label: AppLocalizations.of(context)!.commonEdit,
                  ),
                _MessageActionButton(
                  onPressed: widget.onDelete,
                  icon: Icons.delete_outline_rounded,
                  label: AppLocalizations.of(context)!.commonDelete,
                ),
                if (widget.onDeleteFromHere != null)
                  _MessageActionButton(
                    onPressed: widget.onDeleteFromHere,
                    icon: Icons.delete_sweep_outlined,
                    label: _localizedText(
                      context,
                      zh: '删除此条及后续',
                      en: 'Delete From Here',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    final messageContent = widget.trackLayoutChanges
        ? NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (notification) {
              widget.onLayoutChanged();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: bubbleBody),
          )
        : bubbleBody;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onSelect,
      child: TapRegion(
        enabled: widget.isSelected,
        onTapOutside: (_) => widget.onDeselect(),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: messageContent,
          ),
        ),
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

class _MessageAttachmentSummaryBlock extends StatelessWidget {
  const _MessageAttachmentSummaryBlock({
    required this.attachments,
    required this.textColor,
    required this.backgroundColor,
    this.onAttachmentTap,
  });

  final List<AiMessageAttachment> attachments;
  final Color textColor;
  final Color backgroundColor;
  final void Function(AiMessageAttachment attachment)? onAttachmentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onAttachmentTap?.call(attachment),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      textColor.withValues(alpha: 0.08),
                      backgroundColor,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: textColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForAttachmentKind(attachment.kind),
                        size: 16,
                        color: textColor.withValues(alpha: 0.88),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Text(
                          '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.88),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Opens a message attachment: images are shown in an in-app preview dialog;
/// other file types are opened with the system default application.
Future<void> _openAttachment(
  BuildContext context,
  AiMessageAttachment attachment,
) async {
  final storagePath = attachment.storagePath.trim();
  if (storagePath.isEmpty) {
    return;
  }
  final file = File(storagePath);
  if (!file.existsSync()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '附件文件不存在或已被移动。',
            en: 'Attachment file not found or has been moved.',
          ),
        ),
      ),
    );
    return;
  }

  if (attachment.isImage) {
    if (!context.mounted) return;
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _ImagePreviewDialog(filePath: storagePath, title: attachment.name),
    );
    return;
  }

  // Non-image files: open with system default application.
  if (!context.mounted) return;
  try {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[storagePath]);
    } else if (Platform.isWindows) {
      result = await Process.run('cmd', <String>[
        '/c',
        'start',
        '',
        storagePath,
      ]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[storagePath]);
    } else {
      return;
    }
    if (result.exitCode != 0) {
      final message = '${result.stderr}'.trim();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isEmpty ? 'Failed to open file.' : message),
          ),
        );
      }
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

/// Opens a composer attachment draft: images are shown in an in-app preview
/// dialog; other file types are opened with the system default application.
Future<void> _openComposerAttachment(
  BuildContext context,
  _ComposerAttachmentDraft draft,
) async {
  _openAttachment(
    context,
    AiMessageAttachment(
      id: draft.filePath,
      storagePath: draft.filePath,
      kind: draft.kind,
      name: draft.name,
      mimeType: '',
      sizeBytes: draft.sizeBytes,
    ),
  );
}

/// Shimmer / skeleton placeholder shown while an image frame is loading.
class _ImageShimmerPlaceholder extends StatefulWidget {
  const _ImageShimmerPlaceholder();

  @override
  State<_ImageShimmerPlaceholder> createState() =>
      _ImageShimmerPlaceholderState();
}

class _ImageShimmerPlaceholderState extends State<_ImageShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surfaceContainerLow;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
              end: Alignment(-1.0 + 2.0 * _ctrl.value + 1.0, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.image_outlined,
              size: 40,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen image preview dialog with zoom and pan support.
class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({required this.filePath, required this.title});

  final String filePath;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.open_in_new_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _localizedText(
                      context,
                      zh: '使用系统应用打开',
                      en: 'Open with System App',
                    ),
                    onPressed: () async {
                      if (Platform.isMacOS) {
                        await Process.run('open', <String>[filePath]);
                      } else if (Platform.isWindows) {
                        await Process.run('cmd', <String>[
                          '/c',
                          'start',
                          '',
                          filePath,
                        ]);
                      } else if (Platform.isLinux) {
                        await Process.run('xdg-open', <String>[filePath]);
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Image body with zoom/pan.
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.file(
                    File(filePath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _localizedText(
                              context,
                              zh: '无法加载图片',
                              en: 'Failed to load image',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompressionCheckpointBody extends StatelessWidget {
  const _CompressionCheckpointBody({
    required this.content,
    required this.expanded,
    required this.onToggle,
    required this.selectable,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final VoidCallback onToggle;
  final bool selectable;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggleLabel = _localizedText(
      context,
      zh: expanded ? '收起摘要' : '展开摘要',
      en: expanded ? 'Collapse Summary' : 'Expand Summary',
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: _borderRadius18,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      toggleLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: textColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: textColor.withValues(alpha: 0.82),
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topLeft,
                  child: expanded
                      ? KeyedSubtree(
                          key: const ValueKey<String>('compression-expanded'),
                          child: _SafeMarkdownBody(
                            data: content.isEmpty ? ' ' : content,
                            selectable: selectable,
                            builders: builders,
                            styleSheet: styleSheet,
                            inlineSyntaxes: inlineSyntaxes,
                            pathRoots: pathRoots,
                            parseKey: parseKey,
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey<String>('compression-preview'),
                          child: _MarkdownPreviewBody(
                            data: content.isEmpty ? ' ' : content,
                            maxHeight: 122,
                            styleSheet: styleSheet,
                            builders: builders,
                            inlineSyntaxes: inlineSyntaxes,
                            pathRoots: pathRoots,
                            parseKey: '$parseKey|compression-preview',
                            fadeColor: fadeColor,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasoningBody extends StatelessWidget {
  const _ReasoningBody({
    required this.content,
    required this.expanded,
    required this.streaming,
    required this.selectable,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final bool streaming;
  final bool selectable;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    if (streaming) {
      return _StreamingReasoningBody(
        content: content,
        expanded: expanded,
        textStyle: styleSheet.p?.copyWith(color: textColor),
        fadeColor: fadeColor,
        selectable: selectable,
        styleSheet: styleSheet,
        builders: builders,
        inlineSyntaxes: inlineSyntaxes,
        pathRoots: pathRoots,
        parseKey: parseKey,
      );
    }
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>('reasoning-expanded'),
                child: _SafeMarkdownBody(
                  data: content.isEmpty ? ' ' : content,
                  selectable: selectable,
                  builders: builders,
                  styleSheet: styleSheet,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: parseKey,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>('reasoning-preview'),
                child: _MarkdownPreviewBody(
                  data: content.isEmpty ? ' ' : content,
                  maxHeight: 142,
                  styleSheet: styleSheet,
                  builders: builders,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|reasoning-preview',
                  fadeColor: fadeColor,
                ),
              ),
      ),
    );
  }
}

class _StreamingReasoningBody extends StatelessWidget {
  const _StreamingReasoningBody({
    required this.content,
    required this.expanded,
    required this.selectable,
    required this.textStyle,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final bool selectable;
  final TextStyle? textStyle;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.isEmpty ? ' ' : content;
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>(
                  'streaming-reasoning-markdown-expanded',
                ),
                child: _SafeMarkdownBody(
                  data: effectiveContent,
                  selectable: selectable,
                  builders: builders,
                  styleSheet: styleSheet,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|streaming-markdown',
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>(
                  'streaming-reasoning-markdown-preview',
                ),
                child: _MarkdownPreviewBody(
                  data: effectiveContent,
                  maxHeight: 142,
                  styleSheet: styleSheet,
                  builders: builders,
                  inlineSyntaxes: inlineSyntaxes,
                  pathRoots: pathRoots,
                  parseKey: '$parseKey|streaming-markdown-preview',
                  fadeColor: fadeColor,
                ),
              ),
      ),
    );
  }
}

class _MarkdownPreviewBody extends StatefulWidget {
  const _MarkdownPreviewBody({
    required this.data,
    required this.maxHeight,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.pathRoots,
    required this.parseKey,
    required this.fadeColor,
  });

  final String data;
  final double maxHeight;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;
  final Color fadeColor;

  @override
  State<_MarkdownPreviewBody> createState() => _MarkdownPreviewBodyState();
}

class _MarkdownPreviewBodyState extends State<_MarkdownPreviewBody> {
  double? _contentHeight;

  @override
  void didUpdateWidget(covariant _MarkdownPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parseKey != widget.parseKey) {
      _contentHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final measuredHeight = _contentHeight;
    final effectiveHeight = measuredHeight == null
        ? widget.maxHeight
        : math.min(measuredHeight, widget.maxHeight);
    final showFade =
        measuredHeight != null && measuredHeight > widget.maxHeight + 0.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: constrainedWidth,
                    maxWidth: constrainedWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: _MeasureSize(
                      onChange: (size) {
                        if (!mounted) {
                          return;
                        }
                        final nextHeight = size.height;
                        final currentHeight = _contentHeight;
                        if (currentHeight != null &&
                            (currentHeight - nextHeight).abs() < 0.5) {
                          return;
                        }
                        setState(() {
                          _contentHeight = nextHeight;
                        });
                      },
                      child: IgnorePointer(
                        child: _SafeMarkdownBody(
                          data: widget.data,
                          builders: widget.builders,
                          styleSheet: widget.styleSheet,
                          inlineSyntaxes: widget.inlineSyntaxes,
                          pathRoots: widget.pathRoots,
                          parseKey: widget.parseKey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showFade)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.fadeColor.withValues(alpha: 0),
                            widget.fadeColor.withValues(alpha: 0.96),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (newSize == null || _oldSize == newSize) {
      return;
    }
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(newSize);
    });
  }
}

class _MessageMarkdownThemeData {
  factory _MessageMarkdownThemeData.fromMessageBubble({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    required bool useDarkCodeSurface,
  }) {
    final colorScheme = theme.colorScheme;
    final palette = theme.extension<OpenHandPalette>();
    final bubbleIsDark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final overlayBase = bubbleIsDark ? Colors.white : Colors.black;
    final subtleSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: bubbleIsDark ? 0.06 : 0.035),
      backgroundColor,
    );
    final elevatedSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: bubbleIsDark ? 0.11 : 0.06),
      backgroundColor,
    );
    final accentColor = bubbleIsDark
        ? Color.lerp(colorScheme.primaryContainer, Colors.white, 0.08) ??
              colorScheme.primaryContainer
        : colorScheme.primary;
    final linkColor = bubbleIsDark
        ? Color.lerp(accentColor, Colors.white, 0.08) ?? accentColor
        : accentColor;
    final borderColor =
        palette?.outlineSoft.withValues(alpha: bubbleIsDark ? 0.72 : 0.88) ??
        Color.alphaBlend(
          overlayBase.withValues(alpha: bubbleIsDark ? 0.18 : 0.12),
          backgroundColor,
        );
    final quoteSurface = Color.alphaBlend(
      accentColor.withValues(alpha: bubbleIsDark ? 0.22 : 0.10),
      elevatedSurface,
    );
    final secondaryTextColor = textColor.withValues(
      alpha: bubbleIsDark ? 0.92 : 0.88,
    );
    final bodyStyle =
        theme.textTheme.bodyLarge?.copyWith(color: textColor, height: 1.55) ??
        TextStyle(color: textColor, height: 1.55);
    final tableBodyStyle =
        theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.5) ??
        TextStyle(color: textColor, height: 1.5);
    final codeStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: 'monospace',
          fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.94,
          backgroundColor: subtleSurface,
        ) ??
        TextStyle(
          color: textColor,
          fontFamily: 'monospace',
          backgroundColor: subtleSurface,
        );
    final codeBlockSurface = useDarkCodeSurface
        ? Colors.white.withValues(alpha: 0.08)
        : subtleSurface;
    return _MessageMarkdownThemeData(
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: bodyStyle.copyWith(
          color: linkColor,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.78),
        ),
        p: bodyStyle,
        code: codeStyle,
        em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        blockquote: bodyStyle.copyWith(color: secondaryTextColor),
        listBullet: bodyStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        listBulletPadding: const EdgeInsets.only(right: 8),
        tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        tableBody: tableBodyStyle,
        tableBorder: TableBorder.all(color: borderColor),
        tableCellsPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        tableCellsDecoration: BoxDecoration(color: subtleSurface),
        tableHeadCellsPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        tableHeadCellsDecoration: BoxDecoration(color: elevatedSurface),
        tableColumnWidth: const IntrinsicColumnWidth(),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        blockquoteDecoration: BoxDecoration(
          color: quoteSurface,
          borderRadius: _borderRadius18,
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: codeBlockSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor, width: 1.2)),
        ),
      ),
    );
  }
  const _MessageMarkdownThemeData({required this.styleSheet});

  final MarkdownStyleSheet styleSheet;
}

class _SafeMarkdownBody extends StatefulWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.styleSheet,
    this.selectable = false,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.inlineSyntaxes = const <md.InlineSyntax>[],
    this.pathRoots = const <String>[],
    this.parseKey = '',
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool selectable;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final List<String> pathRoots;
  final String parseKey;

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  int? _lastThemeSignature;
  String? _lastData;
  bool? _lastSelectable;
  String? _lastBuilderSignature;
  String? _lastParseKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeSignature = _computeThemeSignature();
    if (_children == null || _lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdown();
    }
  }

  @override
  void didUpdateWidget(covariant _SafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final builderSignature = _builderSignature();
    if (_lastData != widget.data ||
        _lastSelectable != widget.selectable ||
        _lastBuilderSignature != builderSignature ||
        _lastParseKey != widget.parseKey) {
      _parseMarkdown();
      return;
    }
    final themeSignature = _computeThemeSignature();
    if (_lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdown();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parseMarkdown() {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    final normalizedSource = _sanitizeMarkdownSource(
      widget.data.isEmpty ? ' ' : widget.data,
    );
    _lastThemeSignature = _computeThemeSignature();
    _lastData = widget.data;
    _lastSelectable = widget.selectable;
    _lastBuilderSignature = _builderSignature();
    _lastParseKey = widget.parseKey;
    _disposeRecognizers();
    if (_canRenderMarkdownAsPlainText(widget.data)) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(normalizedSource, style: effectiveStyleSheet.p)
            : Text(normalizedSource, style: effectiveStyleSheet.p),
      ];
      return;
    }
    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: widget.inlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(normalizedSource),
      );
      _sanitizeMarkdownAst(astNodes);
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: widget.selectable,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: _buildMarkdownImage,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: widget.builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        fitContent: true,
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _children = builder.build(astNodes);
    } catch (_) {
      _children = <Widget>[
        widget.selectable
            ? SelectableText(widget.data, style: effectiveStyleSheet.p)
            : Text(widget.data, style: effectiveStyleSheet.p),
      ];
    }
  }

  int _computeThemeSignature() {
    final theme = Theme.of(context);
    return Object.hashAll(<Object?>[
      theme.brightness,
      theme.colorScheme.surface.toARGB32(),
      theme.colorScheme.onSurface.toARGB32(),
      theme.colorScheme.primary.toARGB32(),
      widget.styleSheet.hashCode,
      widget.styleSheet.p?.color?.toARGB32(),
      widget.styleSheet.code?.color?.toARGB32(),
    ]);
  }

  String _builderSignature() {
    final keys = widget.builders.keys.toList(growable: false)..sort();
    return keys.join('|');
  }

  static final RegExp _setextEscapePattern = RegExp(
    r'(^|\n)(\s*)(=+|\^+)(?=\n|$)',
  );

  String _sanitizeMarkdownSource(String source) {
    return _closeUnterminatedFencedCodeBlock(
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    ).replaceAllMapped(
      _setextEscapePattern,
      (match) => '${match[1]}${match[2]}\\${match[3]}',
    );
  }

  void _sanitizeMarkdownAst(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) {
        continue;
      }
      if (node.tag == 'ol') {
        final start = node.attributes['start'];
        if (start != null && int.tryParse(start.trim()) == null) {
          node.attributes.remove('start');
        }
      }
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        _sanitizeMarkdownAst(children);
      }
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final localRecognizers = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in localRecognizers) {
      recognizer.dispose();
    }
  }

  Widget _buildMarkdownImage(Uri uri, String? title, String? alt) {
    // Handle local file paths (absolute or file:// scheme).
    final filePath = uri.scheme == 'file'
        ? uri.toFilePath()
        : (uri.scheme.isEmpty && uri.path.startsWith('/'))
        ? uri.path
        : null;
    if (filePath != null && File(filePath).existsSync()) {
      return GestureDetector(
        onTap: () {
          showAnimatedDialog<void>(
            context: context,
            builder: (ctx) => _ImagePreviewDialog(
              filePath: filePath,
              title: alt ?? title ?? p.basename(filePath),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.6,
              maxHeight: 400,
            ),
            child: Image.file(
              File(filePath),
              fit: BoxFit.contain,
              frameBuilder: _fadeInImageFrameBuilder,
              errorBuilder: (_, __, ___) =>
                  _brokenImagePlaceholder(context, alt ?? 'Image'),
            ),
          ),
        ),
      );
    }
    // Handle network URLs.
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.6,
            maxHeight: 400,
          ),
          child: Image.network(
            uri.toString(),
            fit: BoxFit.contain,
            frameBuilder: _fadeInImageFrameBuilder,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              final progress = loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null;
              return SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.4,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) =>
                _brokenImagePlaceholder(context, alt ?? uri.toString()),
          ),
        ),
      );
    }
    // Fallback: show alt text.
    return Text(alt ?? title ?? uri.toString());
  }

  /// Shared frame builder that fades in images with a smooth animation.
  static Widget _fadeInImageFrameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    if (frame == null) {
      // No frame decoded yet — show shimmer placeholder.
      return const _ImageShimmerPlaceholder();
    }
    // First frame decoded — fade in with a one-shot animation.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }

  static Widget _brokenImagePlaceholder(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    final resolvedPath = resolveMarkdownMessageLinkPath(href, widget.pathRoots);
    if (resolvedPath != null) {
      recognizer.onTap = () {
        unawaited(_openResolvedMessagePath(context, resolvedPath));
      };
      return recognizer;
    }
    final externalUri = parseSupportedMessageLinkUri(href);
    if (externalUri != null) {
      recognizer.onTap = () {
        unawaited(_openMessageLinkUri(context, externalUri));
      };
    }
    return recognizer;
  }

  static final RegExp _trailingNewlinePattern = RegExp(r'\n$');

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(_trailingNewlinePattern, '');
    final resolvedPath = resolveExistingMessagePath(
      normalizedCode,
      widget.pathRoots,
    );
    if (resolvedPath == null) {
      return TextSpan(text: normalizedCode, style: styleSheet.code);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        unawaited(_openResolvedMessagePath(context, resolvedPath));
      };
    _recognizers.add(recognizer);
    final linkColor = Theme.of(context).colorScheme.primary;
    return TextSpan(
      text: normalizedCode,
      recognizer: recognizer,
      style: styleSheet.code?.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null || children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ToolCallBody extends StatefulWidget {
  const _ToolCallBody({required this.message, required this.selectable});

  final AiSessionMessage message;
  final bool selectable;

  @override
  State<_ToolCallBody> createState() => _ToolCallBodyState();
}

class _ToolCallBodyState extends State<_ToolCallBody> {
  bool? _argumentsExpandedOverride;
  bool? _resultExpandedOverride;
  _ToolCallViewData? _cachedViewData;
  int? _cachedViewDataSignature;

  @override
  void didUpdateWidget(covariant _ToolCallBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _argumentsExpandedOverride = null;
      _resultExpandedOverride = null;
      _cachedViewData = null;
      _cachedViewDataSignature = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final defaultExpanded = _shouldDefaultExpandToolStatus(
      _toolExecutionStatus(message),
    );
    final argumentsExpanded = _argumentsExpandedOverride ?? defaultExpanded;
    final resultExpanded = _resultExpandedOverride ?? defaultExpanded;
    final toolCall = _resolveToolCallViewData(
      context,
      message,
      argumentsExpanded: argumentsExpanded,
      resultExpanded: resultExpanded,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ToolExecutionChip(
              icon: toolCall.presentation.icon,
              label: toolCall.primaryChipLabel,
            ),
            if (toolCall.workingDirectory.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.folder_outlined,
                label:
                    '${_localizedText(context, zh: '目录', en: 'Dir')}: ${toolCall.workingDirectory}',
              ),
            if (toolCall.status.isNotEmpty)
              _ToolExecutionChip(
                icon: toolCall.statusIcon,
                label: toolCall.outcomeLabel,
              ),
            if (toolCall.durationMs > 0 || toolCall.status == 'running')
              _ToolExecutionChip(
                icon: Icons.timer_outlined,
                label:
                    '${_localizedText(context, zh: '耗时', en: 'Elapsed')}: ${_formatToolExecutionDuration(toolCall.durationMs)}',
              ),
            if (toolCall.exitCode != null)
              _ToolExecutionChip(
                icon: Icons.flag_outlined,
                label:
                    '${_localizedText(context, zh: '退出码', en: 'Exit')}: ${toolCall.exitCode}',
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '工具入参', en: 'Tool Input'),
          preview: toolCall.argumentsPreview,
          expanded: argumentsExpanded,
          onToggle: () {
            setState(() {
              _argumentsExpandedOverride = !argumentsExpanded;
            });
          },
          expandedBuilder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (toolCall.command.isNotEmpty)
                _ToolOutputPanel(
                  label: _localizedText(context, zh: 'command', en: 'command'),
                  content: toolCall.formattedCommand,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              if (toolCall.command.isNotEmpty) const SizedBox(height: 10),
              _ToolOutputPanel(
                label: _localizedText(
                  context,
                  zh: 'arguments',
                  en: 'arguments',
                ),
                content: toolCall.formattedArguments,
                theme: theme,
                selectable: widget.selectable,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '结果输出', en: 'Tool Output'),
          preview: toolCall.hasResultContent
              ? toolCall.resultPreview
              : _localizedText(context, zh: '暂无输出', en: 'No output yet'),
          expanded: resultExpanded,
          onToggle: () {
            setState(() {
              _resultExpandedOverride = !resultExpanded;
            });
          },
          expandedBuilder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (toolCall.stdout.isNotEmpty)
                _ToolOutputPanel(
                  label: 'stdout',
                  content: toolCall.formattedStdout,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              if (toolCall.stderr.isNotEmpty) ...[
                if (toolCall.stdout.isNotEmpty) const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: 'stderr',
                  content: toolCall.formattedStderr,
                  theme: theme,
                  isError: true,
                  selectable: widget.selectable,
                ),
              ],
              if (toolCall.showResultText) ...[
                if (toolCall.stdout.isNotEmpty || toolCall.stderr.isNotEmpty)
                  const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: _localizedText(context, zh: 'result', en: 'result'),
                  content: toolCall.formattedResult,
                  theme: theme,
                  selectable: widget.selectable,
                ),
              ],
              if (toolCall.stdout.isEmpty &&
                  toolCall.stderr.isEmpty &&
                  !toolCall.showResultText)
                Text(
                  _localizedText(
                    context,
                    zh: '当前还没有工具输出。',
                    en: 'There is no tool output yet.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // ── File mutation indicator (mirrors HE changed-files row) ──
        if (_fileMutationPath(message).isNotEmpty &&
            _toolExecutionStatus(message) == 'success') ...[
          const SizedBox(height: 10),
          _FileMutationRow(message: message),
        ],
      ],
    );
  }

  _ToolCallViewData _resolveToolCallViewData(
    BuildContext context,
    AiSessionMessage message, {
    required bool argumentsExpanded,
    required bool resultExpanded,
  }) {
    final signature = Object.hashAll(<Object?>[
      Localizations.localeOf(context).toLanguageTag(),
      message.id,
      '${message.metadata['tool_name'] ?? ''}',
      '${message.metadata['tool_source'] ?? ''}',
      '${message.metadata['mcp_server_name'] ?? ''}',
      '${message.metadata['mcp_tool_name'] ?? ''}',
      '${message.metadata['mcp_tool_id'] ?? ''}',
      '${message.metadata['skill_name'] ?? ''}',
      '${message.metadata['tool_execution_status'] ?? ''}',
      '${message.metadata['tool_execution_command'] ?? ''}',
      '${message.metadata['tool_execution_working_directory'] ?? ''}',
      '${message.metadata['tool_execution_stdout'] ?? ''}',
      '${message.metadata['tool_execution_stderr'] ?? ''}',
      '${message.metadata['tool_execution_result'] ?? ''}',
      '${message.metadata['tool_arguments'] ?? ''}',
      '${message.metadata['tool_execution_exit_code'] ?? ''}',
      '${message.metadata['tool_execution_elapsed_ms'] ?? message.metadata['tool_execution_duration_ms'] ?? ''}',
      argumentsExpanded,
      resultExpanded,
    ]);
    if (_cachedViewData != null && _cachedViewDataSignature == signature) {
      return _cachedViewData!;
    }
    final viewData = _ToolCallViewData.from(
      context,
      message,
      includeArgumentsContent: argumentsExpanded,
      includeResultContent: resultExpanded,
    );
    _cachedViewData = viewData;
    _cachedViewDataSignature = signature;
    return viewData;
  }
}

class _ExpandableToolSection extends StatelessWidget {
  const _ExpandableToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.expandedBuilder,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final WidgetBuilder expandedBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: InkWell(
        onTap: onToggle,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (!expanded && preview.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: 12),
                Builder(builder: expandedBuilder),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolOutputPanel extends StatefulWidget {
  const _ToolOutputPanel({
    required this.label,
    required this.content,
    required this.theme,
    required this.selectable,
    this.isError = false,
  });

  final String label;
  final _FormattedToolContent content;
  final ThemeData theme;
  final bool selectable;
  final bool isError;

  @override
  State<_ToolOutputPanel> createState() => _ToolOutputPanelState();
}

class _ToolOutputPanelState extends State<_ToolOutputPanel> {
  bool _isExpanded = false;
  bool _isWrapped = false;
  List<String>? _cachedLines;
  String? _cachedLinesKey;

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _toggleWrapped() {
    setState(() {
      _isWrapped = !_isWrapped;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Cache line splitting to avoid re-splitting large tool output on every build.
    if (_cachedLinesKey != widget.content.text) {
      _cachedLinesKey = widget.content.text;
      _cachedLines = const LineSplitter().convert(widget.content.text);
    }
    final lines = _cachedLines!;
    final bool isLong = widget.content.text.length > 800 || lines.length > 15;

    final displayContent = isLong && !_isExpanded
        ? '${lines.take(15).join('\n')}${lines.length > 15 || widget.content.text.length > 800 ? '\n\n... [已折叠以优化显示体验，请点击“查看完整内容”]' : ''}'
        : widget.content.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: widget.theme.textTheme.labelLarge?.copyWith(
                  color: widget.isError
                      ? widget.theme.colorScheme.error
                      : widget.theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _toggleWrapped,
                  icon: Icon(
                    _isWrapped
                        ? Icons.wrap_text_rounded
                        : Icons.segment_rounded,
                    size: 14,
                  ),
                  label: Text(
                    _localizedText(
                      context,
                      zh: _isWrapped ? '取消换行' : '自动换行',
                      en: _isWrapped ? 'Unwrap' : 'Wrap Lines',
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 28),
                    foregroundColor: widget.theme.colorScheme.primary,
                    textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLong) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _toggleExpanded,
                    icon: Icon(
                      _isExpanded
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      size: 14,
                    ),
                    label: Text(
                      _localizedText(
                        context,
                        zh: _isExpanded ? '查看压缩内容' : '查看完整内容',
                        en: _isExpanded
                            ? 'View Compressed Content'
                            : 'View Full Content',
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      foregroundColor: widget.theme.colorScheme.primary,
                      textStyle: widget.theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _HighlightedCodePanel(
          content: displayContent,
          theme: widget.theme,
          language: widget.content.language,
          selectable: widget.selectable,
          baseColor: widget.isError
              ? widget.theme.colorScheme.onErrorContainer
              : widget.theme.colorScheme.onSurface,
          accentColor: widget.isError ? widget.theme.colorScheme.error : null,
          wrapLines: _isWrapped,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileMutationRow — shows file-change indicator for write/edit/multiedit tools
// ─────────────────────────────────────────────────────────────────────────────

String _fileMutationPath(AiSessionMessage message) =>
    '${message.metadata['file_mutation_path'] ?? ''}'.trim();

String _fileMutationKind(AiSessionMessage message) =>
    '${message.metadata['file_mutation_kind'] ?? ''}'.trim();

class _FileMutationRow extends StatelessWidget {
  const _FileMutationRow({required this.message});

  final AiSessionMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutPath = _fileMutationPath(message);
    final mutKind = _fileMutationKind(message);

    final editCount = message.metadata['file_mutation_edit_count'];

    // Determine icon & color based on mutation kind.
    final (
      IconData icon,
      Color iconColor,
      String kindLabel,
    ) = switch (mutKind) {
      'write' => (
        Icons.add_circle_outline_rounded,
        const Color(0xFF4CAF50),
        _localizedText(context, zh: '写入', en: 'Write'),
      ),
      'edit' => (
        Icons.edit_outlined,
        colorScheme.primary,
        _localizedText(context, zh: '编辑', en: 'Edit'),
      ),
      'multi_edit' => (
        Icons.edit_note_outlined,
        colorScheme.primary,
        editCount is int && editCount > 1
            ? _localizedText(
                context,
                zh: '多处编辑 ×$editCount',
                en: 'Multi-edit ×$editCount',
              )
            : _localizedText(context, zh: '多处编辑', en: 'Multi-edit'),
      ),
      'notebook_edit' => (
        Icons.menu_book_outlined,
        colorScheme.tertiary,
        _localizedText(context, zh: 'Notebook 编辑', en: 'Notebook Edit'),
      ),
      'bash_write' => (
        Icons.terminal_rounded,
        const Color(0xFFF57F17),
        _localizedText(context, zh: '命令写入', en: 'Bash Write'),
      ),
      _ => (
        Icons.difference_rounded,
        colorScheme.onSurfaceVariant,
        _localizedText(context, zh: '文件变更', en: 'File Changed'),
      ),
    };

    // Extract a shorter display path.
    final displayPath = _shortenFilePath(mutPath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.difference_rounded,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            _localizedText(context, zh: '文件变动', en: 'Changed File'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              displayPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: _borderRadius999,
            ),
            child: Text(
              kindLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: iconColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shorten an absolute path to the last 3 segments for readability.
  static String _shortenFilePath(String filePath) {
    if (filePath.isEmpty) return filePath;
    // Normalise to forward slashes for splitting (handles Windows paths too).
    final normalised = filePath.replaceAll('\\', '/');
    final parts = normalised.split('/');
    if (parts.length <= 3) return normalised;
    return '.../${parts.sublist(parts.length - 3).join('/')}';
  }
}

class _ToolExecutionChip extends StatelessWidget {
  const _ToolExecutionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: _borderRadius999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ToolCallPresentation {
  const _ToolCallPresentation({
    required this.categoryLabel,
    required this.displayName,
    required this.icon,
    this.isCommandLike = false,
  });

  final String categoryLabel;
  final String displayName;
  final IconData icon;
  final bool isCommandLike;
}

class _ToolCallViewData {
  const _ToolCallViewData({
    required this.presentation,
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.durationMs,
    required this.argumentsPreview,
    required this.formattedCommand,
    required this.formattedArguments,
    required this.formattedStdout,
    required this.formattedStderr,
    required this.formattedResult,
    required this.defaultExpanded,
    required this.showResultText,
    required this.hasResultContent,
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.primaryChipLabel,
    required this.statusLabel,
    required this.outcomeLabel,
    required this.resultPreview,
  });

  factory _ToolCallViewData.from(
    BuildContext context,
    AiSessionMessage message, {
    bool includeArgumentsContent = true,
    bool includeResultContent = true,
  }) {
    final presentation = _toolCallPresentation(context, message);
    final status = _toolExecutionStatus(message);
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message).trimRight();
    final stderr = _toolExecutionStderr(message).trimRight();
    final resultText = _toolExecutionResult(message).trimRight();
    final exitCode = _toolExecutionExitCode(message);
    final durationMs = _toolExecutionDurationMs(message);
    final argumentsPreview = _toolArgumentsPreview(message);
    final formattedCommand = !includeArgumentsContent || command.isEmpty
        ? const _FormattedToolContent(text: '')
        : _FormattedToolContent(text: '\$ $command', language: 'bash');
    final formattedArguments = includeArgumentsContent
        ? _formatToolContent(
            '${message.metadata['tool_arguments'] ?? ''}',
            emptyFallback: '{}',
          )
        : const _FormattedToolContent(text: '{}');
    final formattedStdout = includeResultContent
        ? _formatToolContent(stdout)
        : const _FormattedToolContent(text: '');
    final formattedStderr = includeResultContent
        ? _formatToolContent(stderr)
        : const _FormattedToolContent(text: '');
    final formattedResult = includeResultContent
        ? _formatToolContent(resultText)
        : const _FormattedToolContent(text: '');
    final isStructuredWrapper =
        resultText.startsWith('status: ') &&
        resultText.contains('\ncommand: ') &&
        resultText.contains('\nduration_ms: ');
    final showResultText =
        resultText.isNotEmpty &&
        resultText != stdout.trim() &&
        resultText != stderr.trim() &&
        !isStructuredWrapper;
    final hasResultContent =
        stdout.isNotEmpty ||
        stderr.isNotEmpty ||
        resultText.isNotEmpty ||
        exitCode != null ||
        status.isNotEmpty;
    final viewData = _ToolCallViewData(
      presentation: presentation,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout,
      stderr: stderr,
      resultText: resultText,
      exitCode: exitCode,
      durationMs: durationMs,
      argumentsPreview: argumentsPreview,
      formattedCommand: formattedCommand,
      formattedArguments: formattedArguments,
      formattedStdout: formattedStdout,
      formattedStderr: formattedStderr,
      formattedResult: formattedResult,
      defaultExpanded: _shouldDefaultExpandToolStatus(status),
      showResultText: showResultText,
      hasResultContent: hasResultContent,
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      primaryChipLabel: presentation.displayName == presentation.categoryLabel
          ? presentation.categoryLabel
          : '${presentation.categoryLabel}: ${presentation.displayName}',
      statusLabel: _toolCallStatusLabelForData(
        context,
        presentation,
        status,
        durationMs,
      ),
      outcomeLabel: _toolExecutionOutcomeLabel(context, status),
      resultPreview: _toolExecutionPreviewText(
        context,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
    return viewData;
  }

  final _ToolCallPresentation presentation;
  final String status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final int durationMs;
  final String argumentsPreview;
  final _FormattedToolContent formattedCommand;
  final _FormattedToolContent formattedArguments;
  final _FormattedToolContent formattedStdout;
  final _FormattedToolContent formattedStderr;
  final _FormattedToolContent formattedResult;
  final bool defaultExpanded;
  final bool showResultText;
  final bool hasResultContent;
  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String primaryChipLabel;
  final String statusLabel;
  final String outcomeLabel;
  final String resultPreview;
}

String _toolCallName(AiSessionMessage message) =>
    '${message.metadata['tool_name'] ?? ''}'.trim();

String _toolExecutionStatus(AiSessionMessage message) =>
    '${message.metadata['tool_execution_status'] ?? ''}'.trim();

bool _shouldSweepToolStatus(String status) {
  return status.isEmpty || status == 'running';
}

String _toolExecutionCommand(AiSessionMessage message) {
  final executionCommand = '${message.metadata['tool_execution_command'] ?? ''}'
      .trim();
  if (executionCommand.isNotEmpty) {
    return executionCommand;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolCommandFromArguments(rawArguments);
}

String _toolExecutionWorkingDirectory(AiSessionMessage message) {
  final executionDirectory =
      '${message.metadata['tool_execution_working_directory'] ?? ''}'.trim();
  if (executionDirectory.isNotEmpty) {
    return executionDirectory;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolWorkingDirectoryFromArguments(rawArguments);
}

String _toolExecutionStdout(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stdout'] ?? ''}';

String _toolExecutionStderr(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stderr'] ?? ''}';

String _toolExecutionResult(AiSessionMessage message) =>
    '${message.metadata['tool_execution_result'] ?? ''}';

bool _isStreamingReasoningMessage(AiSessionMessage message) {
  return message.kind == AiSessionMessageKind.reasoning &&
      message.metadata[aiSessionMessageMetadataStreamingKey] == true;
}

bool _shouldTrackMessageLayout({
  required AiSessionMessage message,
  required AiSendPhase sendPhase,
  required bool isLastVisibleMessage,
}) {
  if (_isStreamingReasoningMessage(message)) {
    return true;
  }
  if (message.kind == AiSessionMessageKind.toolCall) {
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      return true;
    }
  }
  if (sendPhase != AiSendPhase.idle && isLastVisibleMessage) {
    return switch (message.kind) {
      AiSessionMessageKind.assistant || AiSessionMessageKind.status => true,
      _ => false,
    };
  }
  return false;
}

bool _shouldDefaultExpandReasoning(AiSessionMessage message) {
  return _isStreamingReasoningMessage(message);
}

bool _shouldDefaultExpandToolStatus(String status) {
  return status.isEmpty;
}

int _reasoningElapsedMs(AiSessionMessage message) {
  final elapsed = DateTime.now()
      .toUtc()
      .difference(message.createdAt.toUtc())
      .inMilliseconds;
  return math.max(0, elapsed);
}

int? _toolExecutionExitCode(AiSessionMessage message) {
  final value = message.metadata['tool_execution_exit_code'];
  if (value is int) {
    return value;
  }
  return int.tryParse('${value ?? ''}'.trim());
}

IconData _toolExecutionStatusIcon(String status) {
  return switch (status) {
    'running' => Icons.play_circle_outline_rounded,
    'cancelled' => Icons.stop_circle_outlined,
    'success' => Icons.check_circle_outline_rounded,
    'denied' => Icons.block_rounded,
    'rejected' => Icons.cancel_outlined,
    'timed_out' => Icons.timer_off_outlined,
    'failed' => Icons.error_outline_rounded,
    'invalid_arguments' => Icons.warning_amber_rounded,
    _ => Icons.terminal_rounded,
  };
}

_ToolCallPresentation _toolCallPresentation(
  BuildContext context,
  AiSessionMessage message,
) {
  final rawToolName = _toolCallName(message);
  final normalizedToolName = rawToolName.trim().toLowerCase();
  final toolSource = '${message.metadata['tool_source'] ?? ''}'
      .trim()
      .toLowerCase();
  if (toolSource == 'skill' || normalizedToolName.startsWith('skill__')) {
    final skillName = '${message.metadata['skill_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: _localizedText(context, zh: '技能', en: 'Skill'),
      displayName: skillName.isEmpty ? rawToolName : skillName,
      icon: Icons.extension_rounded,
    );
  }
  if (toolSource == 'mcp' || normalizedToolName.startsWith('mcp__')) {
    final serverName = '${message.metadata['mcp_server_name'] ?? ''}'.trim();
    final toolName = '${message.metadata['mcp_tool_name'] ?? ''}'.trim();
    final toolId = '${message.metadata['mcp_tool_id'] ?? ''}'.trim();
    final displayName = <String>[
      if (serverName.isNotEmpty) serverName,
      if (toolName.isNotEmpty) toolName else if (toolId.isNotEmpty) toolId,
    ].join(' / ');
    return _ToolCallPresentation(
      categoryLabel: 'MCP',
      displayName: displayName.isEmpty ? rawToolName : displayName,
      icon: Icons.account_tree_outlined,
    );
  }
  return switch (normalizedToolName) {
    'bash' => const _ToolCallPresentation(
      categoryLabel: 'Bash',
      displayName: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    ),
    'grep' => const _ToolCallPresentation(
      categoryLabel: 'Grep',
      displayName: 'Grep',
      icon: Icons.manage_search_rounded,
    ),
    'ls' => const _ToolCallPresentation(
      categoryLabel: 'LS',
      displayName: 'LS',
      icon: Icons.folder_open_rounded,
    ),
    'read' => const _ToolCallPresentation(
      categoryLabel: 'Read',
      displayName: 'Read',
      icon: Icons.article_outlined,
    ),
    'write' => const _ToolCallPresentation(
      categoryLabel: 'Write',
      displayName: 'Write',
      icon: Icons.edit_note_rounded,
    ),
    'edit' => const _ToolCallPresentation(
      categoryLabel: 'Edit',
      displayName: 'Edit',
      icon: Icons.edit_outlined,
    ),
    'multiedit' => const _ToolCallPresentation(
      categoryLabel: 'MultiEdit',
      displayName: 'MultiEdit',
      icon: Icons.edit_note_outlined,
    ),
    'notebookedit' => const _ToolCallPresentation(
      categoryLabel: 'NotebookEdit',
      displayName: 'NotebookEdit',
      icon: Icons.menu_book_outlined,
    ),
    'webfetch' => const _ToolCallPresentation(
      categoryLabel: 'WebFetch',
      displayName: 'WebFetch',
      icon: Icons.language_rounded,
    ),
    'websearch' => const _ToolCallPresentation(
      categoryLabel: 'WebSearch',
      displayName: 'WebSearch',
      icon: Icons.travel_explore_rounded,
    ),
    'todowrite' => const _ToolCallPresentation(
      categoryLabel: 'TodoWrite',
      displayName: 'TodoWrite',
      icon: Icons.checklist_rounded,
    ),
    'task' => const _ToolCallPresentation(
      categoryLabel: 'Task',
      displayName: 'Task',
      icon: Icons.hub_outlined,
    ),
    'glob' => const _ToolCallPresentation(
      categoryLabel: 'Glob',
      displayName: 'Glob',
      icon: Icons.filter_alt_outlined,
    ),
    'exitplanmode' => const _ToolCallPresentation(
      categoryLabel: 'ExitPlanMode',
      displayName: 'ExitPlanMode',
      icon: Icons.assignment_turned_in_outlined,
    ),
    _ => _ToolCallPresentation(
      categoryLabel: _localizedText(context, zh: '工具', en: 'Tool'),
      displayName: rawToolName.isEmpty
          ? _localizedText(context, zh: '工具', en: 'Tool')
          : rawToolName,
      icon: Icons.build_circle_outlined,
    ),
  };
}

class _FormattedToolContent {
  const _FormattedToolContent({required this.text, this.language});

  final String text;
  final String? language;
}

_FormattedToolContent _formatToolContent(
  String rawContent, {
  String emptyFallback = '',
}) {
  final normalized = rawContent
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
  final trimmed = normalized.trim();
  if (trimmed.isEmpty) {
    return _FormattedToolContent(text: emptyFallback);
  }
  final jsonContent = _tryFormatJsonContent(trimmed);
  if (jsonContent != null) {
    return _FormattedToolContent(text: jsonContent, language: 'json');
  }
  final xmlContent = _tryFormatXmlContent(trimmed);
  if (xmlContent != null) {
    return _FormattedToolContent(text: xmlContent, language: 'xml');
  }
  final yamlContent = _tryFormatYamlContent(trimmed);
  if (yamlContent != null) {
    return _FormattedToolContent(text: yamlContent, language: 'yaml');
  }
  if (_looksLikeTomlContent(trimmed)) {
    return _FormattedToolContent(text: normalized, language: 'toml');
  }
  return _FormattedToolContent(text: normalized);
}

String? _tryFormatJsonContent(String content) {
  if (!_looksLikeJsonContent(content)) {
    return null;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(content));
  } catch (_) {
    return null;
  }
}

bool _looksLikeJsonContent(String content) {
  if (content.length < 2) {
    return false;
  }
  final startsWithObject = content.startsWith('{') && content.endsWith('}');
  final startsWithArray = content.startsWith('[') && content.endsWith(']');
  return startsWithObject || startsWithArray;
}

String? _tryFormatXmlContent(String content) {
  if (!_looksLikeXmlContent(content)) {
    return null;
  }
  try {
    return xml.XmlDocument.parse(
      content,
    ).toXmlString(pretty: true, indent: '  ');
  } catch (_) {
    try {
      return xml.XmlDocumentFragment.parse(
        content,
      ).toXmlString(pretty: true, indent: '  ');
    } catch (_) {
      return null;
    }
  }
}

bool _looksLikeXmlContent(String content) {
  return content.startsWith('<') &&
      content.endsWith('>') &&
      _xmlStartTagProbePattern.hasMatch(content);
}

String? _tryFormatYamlContent(String content) {
  if (!_looksLikeYamlContent(content)) {
    return null;
  }
  try {
    final decoded = loadYamlNode(content);
    final value = decoded.value;
    if (value is! YamlMap &&
        value is! YamlList &&
        !_isYamlMultilineScalar(value)) {
      return null;
    }
    return _renderYamlNode(value, 0);
  } catch (_) {
    return null;
  }
}

bool _looksLikeYamlContent(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trimLeft())
      .where((line) => line.isNotEmpty)
      .take(12)
      .toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  var structuredLineCount = 0;
  for (final line in lines) {
    if (line == '---' || line == '...') {
      structuredLineCount += 1;
      continue;
    }
    if (line.startsWith('- ') || _yamlKeyPrefixPattern.hasMatch(line)) {
      structuredLineCount += 1;
    }
  }
  return structuredLineCount > 0;
}

bool _looksLikeTomlContent(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .take(12)
      .toList(growable: false);
  if (lines.isEmpty) {
    return false;
  }
  return lines.every(
    (line) =>
        _tomlSectionPattern.hasMatch(line) ||
        _tomlKeyValuePattern.hasMatch(line),
  );
}

bool _isYamlMultilineScalar(Object? value) {
  return value is String && value.contains('\n');
}

String _renderYamlNode(Object? value, int indent) {
  final padding = ' ' * indent;
  if (value is YamlMap) {
    if (value.isEmpty) {
      return '$padding{}';
    }
    final buffer = StringBuffer();
    var isFirst = true;
    for (final entry in value.entries) {
      if (!isFirst) {
        buffer.writeln();
      }
      final key = _renderYamlKey(entry.key);
      final entryValue = entry.value;
      if (_isYamlInlineValue(entryValue)) {
        buffer.write('$padding$key: ${_renderYamlScalar(entryValue)}');
      } else {
        buffer.write(
          '$padding$key:\n${_renderYamlNode(entryValue, indent + 2)}',
        );
      }
      isFirst = false;
    }
    return buffer.toString();
  }
  if (value is YamlList) {
    if (value.isEmpty) {
      return '$padding[]';
    }
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index += 1) {
      if (index > 0) {
        buffer.writeln();
      }
      final item = value[index];
      if (_isYamlInlineValue(item)) {
        buffer.write('$padding- ${_renderYamlScalar(item)}');
      } else {
        buffer.write('$padding-\n${_renderYamlNode(item, indent + 2)}');
      }
    }
    return buffer.toString();
  }
  if (value is String && value.contains('\n')) {
    final childPadding = ' ' * (indent + 2);
    final lines = value.split('\n');
    return '$padding|\n${lines.map((line) => '$childPadding$line').join('\n')}';
  }
  return '$padding${_renderYamlScalar(value)}';
}

bool _isYamlInlineValue(Object? value) {
  return switch (value) {
    null => true,
    bool() => true,
    num() => true,
    String() => !value.contains('\n'),
    _ => false,
  };
}

String _renderYamlKey(Object? value) {
  final key = '${value ?? ''}';
  if (_tomlBareKeyPattern.hasMatch(key)) {
    return key;
  }
  return jsonEncode(key);
}

String _renderYamlScalar(Object? value) {
  return switch (value) {
    null => 'null',
    bool() => value ? 'true' : 'false',
    num() => '$value',
    String() => jsonEncode(value),
    DateTime() => jsonEncode(value.toIso8601String()),
    _ => jsonEncode('$value'),
  };
}

String _toolArgumentsPreview(AiSessionMessage message) {
  final command = _toolExecutionCommand(message);
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) {
        final entries = Map<String, Object?>.from(decoded).entries.take(2);
        final summary = entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(', ');
        if (summary.isNotEmpty) {
          return summary;
        }
      }
      if (decoded is List) {
        return '[${decoded.length} items]';
      }
    } catch (_) {
      // Fallback to the prettified text preview below.
    }
  }
  final preview = rawArguments.isEmpty ? '{}' : rawArguments;
  final firstLine = const LineSplitter()
      .convert(preview)
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '{}');
  return firstLine;
}

String _toolCallStatusLabelForData(
  BuildContext context,
  _ToolCallPresentation presentation,
  String status,
  int durationMs,
) {
  final suffix = durationMs <= 0
      ? ''
      : ' (${_formatToolExecutionDuration(durationMs)})';
  final toolLabel = presentation.displayName.trim().isEmpty
      ? presentation.categoryLabel
      : presentation.displayName.trim();
  final statusLabel = _toolCallStatusActionLabel(
    context,
    status,
    isCommandLike: presentation.isCommandLike,
  );
  return suffix.isEmpty
      ? '$toolLabel · $statusLabel'
      : '$toolLabel · $statusLabel$suffix';
}

String _toolCallStatusActionLabel(
  BuildContext context,
  String status, {
  required bool isCommandLike,
}) {
  return switch (status) {
    '' => _localizedText(
      context,
      zh: isCommandLike ? '准备执行' : '准备调用',
      en: 'Preparing',
    ),
    'running' => _localizedText(
      context,
      zh: isCommandLike ? '执行中' : '调用中',
      en: 'Running',
    ),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(
      context,
      zh: isCommandLike ? '执行完成' : '调用完成',
      en: 'Completed',
    ),
    'denied' => _localizedText(context, zh: '已拦截', en: 'Blocked'),
    'rejected' => _localizedText(context, zh: '已拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(
      context,
      zh: isCommandLike ? '执行超时' : '调用超时',
      en: 'Timed Out',
    ),
    'failed' => _localizedText(
      context,
      zh: isCommandLike ? '执行失败' : '调用失败',
      en: 'Failed',
    ),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
    _ => _localizedText(context, zh: '工具调用', en: 'Tool Call'),
  };
}

String _toolExecutionOutcomeLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => _localizedText(context, zh: '运行中', en: 'Running'),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(context, zh: '执行成功', en: 'Succeeded'),
    'denied' => _localizedText(context, zh: '已被禁止', en: 'Denied'),
    'rejected' => _localizedText(context, zh: '用户拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(context, zh: '执行超时', en: 'Timed Out'),
    'failed' => _localizedText(context, zh: '执行失败', en: 'Failed'),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
    _ => status,
  };
}

String _toolExecutionPreviewText(
  BuildContext context, {
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = _lastNonEmptyToolOutputLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _lastNonEmptyToolOutputLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = _lastNonEmptyToolOutputLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (_shouldSweepToolStatus(status)) {
    return _localizedText(
      context,
      zh: '工具运行中，等待新的输出...',
      en: 'Tool is running. Waiting for output...',
    );
  }
  return _localizedText(
    context,
    zh: '点击展开查看工具输出',
    en: 'Expand to inspect tool output',
  );
}

String _lastNonEmptyToolOutputLine(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }
  return lines.last;
}

int _toolExecutionDurationMs(AiSessionMessage message) {
  final rawValue =
      message.metadata['tool_execution_elapsed_ms'] ??
      message.metadata['tool_execution_duration_ms'] ??
      0;
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('$rawValue'.trim()) ?? 0;
}

String _formatToolExecutionDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).floor();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds}s';
}

Future<void> _openResolvedMessagePath(
  BuildContext context,
  MessageResolvedPath resolvedPath,
) async {
  try {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run(
        'open',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['-R', resolvedPath.resolvedPath],
      );
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['/select,${resolvedPath.resolvedPath}'],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[
        resolvedPath.isDirectory
            ? resolvedPath.resolvedPath
            : p.dirname(resolvedPath.resolvedPath),
      ]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open file location.' : message,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

Future<void> _openMessageLinkUri(BuildContext context, Uri uri) async {
  try {
    late final ProcessResult result;
    final target = uri.toString();
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[target]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', <String>[target]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[target]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open link.' : message,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showMessageLinkOpenError(context, error);
  }
}

void _showMessageLinkOpenError(BuildContext context, Object error) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        _localizedText(
          context,
          zh: '打开文件位置失败：$error',
          en: 'Failed to open file location: $error',
        ),
      ),
    ),
  );
}

class _FilePathMarkdownBuilder extends MarkdownElementBuilder {
  _FilePathMarkdownBuilder({required this.textColor, required this.onOpenPath});

  final Color textColor;
  final Future<void> Function(
    BuildContext context,
    MessageResolvedPath resolvedPath,
  )
  onOpenPath;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == 'openhand-file-resolved') {
      final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
      final displayPath = element.textContent.trim();
      final isDirectory =
          (element.attributes['entity_type'] ?? '').trim() == 'directory';
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildChip(
              context,
              displayPath: displayPath,
              resolvedPath: resolvedPath,
              isDirectory: isDirectory,
            ),
          ),
        ),
      );
    }

    final normalizedPath = element.attributes['normalized_path'] ?? '';
    final candidateRoots = (element.attributes['candidate_roots'] ?? '').split(
      '\r',
    );
    final fullMatch = element.textContent;
    final trailing = element.attributes['trailing'] ?? '';
    final isCodeSpan = element.attributes['is_code_span'] == 'true';

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _AsyncFilePathChip(
          normalizedPath: normalizedPath,
          candidateRoots: candidateRoots,
          fullMatch: fullMatch,
          trailing: trailing,
          isCodeSpan: isCodeSpan,
          parentStyle: parentStyle,
          builder: this,
        ),
      ),
    );
  }

  Widget _buildCodeSpan(
    BuildContext context,
    String text,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style:
            parentStyle?.copyWith(
              fontFamily: 'monospace',
              fontSize: (parentStyle.fontSize ?? 14) * 0.9,
              color: colorScheme.onSurface,
            ) ??
            theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurface,
            ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String displayPath,
    required String resolvedPath,
    required bool isDirectory,
    bool isUnresolved = false,
  }) {
    return _FilePathChip(
      displayPath: displayPath,
      resolvedPath: resolvedPath,
      isDirectory: isDirectory,
      isUnresolved: isUnresolved,
      textColor: textColor,
      onOpenPath: () => onOpenPath(
        context,
        MessageResolvedPath(
          displayPath: displayPath,
          resolvedPath: resolvedPath,
          isDirectory: isDirectory,
        ),
      ),
    );
  }
}

class _AsyncFilePathChip extends StatefulWidget {
  const _AsyncFilePathChip({
    required this.normalizedPath,
    required this.candidateRoots,
    required this.fullMatch,
    required this.trailing,
    required this.isCodeSpan,
    required this.parentStyle,
    required this.builder,
  });

  final String normalizedPath;
  final List<String> candidateRoots;
  final String fullMatch;
  final String trailing;
  final bool isCodeSpan;
  final TextStyle? parentStyle;
  final _FilePathMarkdownBuilder builder;

  @override
  State<_AsyncFilePathChip> createState() => _AsyncFilePathChipState();
}

class _AsyncFilePathChipState extends State<_AsyncFilePathChip> {
  Future<MessageResolvedPath?>? _future;

  @override
  void initState() {
    super.initState();
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void didUpdateWidget(_AsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _future = resolveExistingMessagePathAsync(
        widget.normalizedPath,
        widget.candidateRoots,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data;
        if (resolvedPath == null) {
          if (widget.isCodeSpan) {
            return widget.builder._buildCodeSpan(
              context,
              widget.fullMatch,
              widget.parentStyle,
            );
          }
          final isExplicitPath =
              widget.normalizedPath.startsWith('~/') ||
              widget.normalizedPath.startsWith('./') ||
              widget.normalizedPath.startsWith('../') ||
              looksLikeAbsoluteMessagePath(widget.normalizedPath);
          if (isExplicitPath) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: widget.builder._buildChip(
                      context,
                      displayPath: widget.normalizedPath,
                      resolvedPath: widget.normalizedPath,
                      isDirectory: widget.trailing.contains('/'),
                      isUnresolved: true,
                    ),
                  ),
                ),
                if (widget.trailing.isNotEmpty)
                  Text(widget.trailing, style: widget.parentStyle),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(widget.fullMatch, style: widget.parentStyle),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: widget.builder._buildChip(
                  context,
                  displayPath: resolvedPath.displayPath,
                  resolvedPath: resolvedPath.resolvedPath,
                  isDirectory: resolvedPath.isDirectory,
                ),
              ),
            ),
            if (widget.trailing.isNotEmpty)
              Text(widget.trailing, style: widget.parentStyle),
          ],
        );
      },
    );
  }
}

class _FilePathChip extends StatelessWidget {
  const _FilePathChip({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
    this.isUnresolved = false,
    required this.textColor,
    required this.onOpenPath,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
  final bool isUnresolved;
  final Color textColor;
  final VoidCallback onOpenPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);

    return _FileHoverPopup(
      resolvedPath: resolvedPath,
      isUnresolved: isUnresolved,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _borderRadius999,
          onTap: isUnresolved ? null : onOpenPath,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isUnresolved
                  ? chipColor.withValues(alpha: 0.3)
                  : chipColor,
              borderRadius: _borderRadius999,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnresolved
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: isUnresolved
                      ? textColor.withValues(alpha: 0.5)
                      : textColor.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      displayPath,
                      overflow: TextOverflow.ellipsis,
                      style: isUnresolved
                          ? labelStyle.copyWith(
                              color: textColor.withValues(alpha: 0.5),
                            )
                          : labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileHoverPopup extends StatefulWidget {
  const _FileHoverPopup({
    required this.resolvedPath,
    required this.child,
    this.isUnresolved = false,
  });
  final String resolvedPath;
  final Widget child;
  final bool isUnresolved;

  @override
  State<_FileHoverPopup> createState() => _FileHoverPopupState();
}

class _FileHoverPopupState extends State<_FileHoverPopup> {
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;
  bool _showScheduled = false;
  bool _hideScheduled = false;

  /// Returns true if any Ctrl or Meta (Cmd on macOS) modifier key is currently
  /// held down. Uses [physicalKeysPressed] which reflects raw hardware state
  /// and is unaffected by logical-key remapping or keyboard guard filtering.
  bool get _isModifierPressed {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return pressed.contains(PhysicalKeyboardKey.controlLeft) ||
        pressed.contains(PhysicalKeyboardKey.controlRight) ||
        pressed.contains(PhysicalKeyboardKey.metaLeft) ||
        pressed.contains(PhysicalKeyboardKey.metaRight);
  }

  void _showOverlay() {
    if (widget.isUnresolved || _overlayEntry != null || _showScheduled) return;
    // Defer overlay insertion to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase, which triggers the
    // !_debugDuringDeviceUpdate re-entrancy assertion.
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlayEntry != null) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    var targetLeft = offset.dx;
    if (targetLeft + 320 > screenSize.width - 16) {
      targetLeft = screenSize.width - 320 - 16;
      if (targetLeft < 8) targetLeft = 8;
    }

    var targetTop = offset.dy + size.height + 6;
    const estimatedHeight = 140.0;
    if (targetTop + estimatedHeight > screenSize.height - 16) {
      targetTop = offset.dy - estimatedHeight - 6;
    }

    // Capture the path at the time of showing to avoid stale closure issues.
    final resolvedPath = widget.resolvedPath;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: targetLeft,
        top: targetTop,
        // IgnorePointer: the popup is read-only metadata; it must not consume
        // pointer events so that the chip and underlying widgets remain
        // interactive (e.g. clicking the chip still opens Finder).
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  overlayContext,
                ).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(overlayContext).dividerColor,
                ),
              ),
              width: 320,
              child: FutureBuilder<FileStat>(
                future: FileStat.stat(resolvedPath),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 40,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final stat = snapshot.data!;
                  final theme = Theme.of(context);
                  final colorScheme = theme.colorScheme;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resolvedPath,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StatRow(
                        _localizedText(context, zh: '类型', en: 'Type'),
                        stat.type.toString(),
                      ),
                      _StatRow(
                        _localizedText(context, zh: '大小', en: 'Size'),
                        '${stat.size} bytes',
                      ),
                      _StatRow(
                        _localizedText(context, zh: '修改于', en: 'Modified'),
                        '${stat.modified}',
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    try {
      Overlay.of(context).insert(_overlayEntry!);
    } catch (_) {
      _overlayEntry = null;
    }
  }

  void _hideOverlay() {
    if (_overlayEntry == null && !_showScheduled) return;
    _showScheduled = false;
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    // Defer overlay removal to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase.
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      entry.remove();
    });
  }

  @override
  void didUpdateWidget(_FileHoverPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the resolved path changed while the overlay was visible, dismiss it
    // so it doesn't show stale metadata from the previous path.
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.isUnresolved != widget.isUnresolved) {
      _hideOverlay();
    }
  }

  @override
  void deactivate() {
    // Synchronous removal is safe when the widget is leaving the tree.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isHovered = false;
    super.deactivate();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || !_isHovered || widget.isUnresolved) {
      return false;
    }
    if (_isModifierPressed) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    // Synchronous cleanup—widget is being permanently destroyed.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        if (!widget.isUnresolved && _isModifierPressed) {
          _showOverlay();
        }
      },
      onHover: (_) {
        if (!widget.isUnresolved) {
          if (_isModifierPressed) {
            _showOverlay();
          } else {
            _hideOverlay();
          }
        }
      },
      onExit: (_) {
        _isHovered = false;
        _hideOverlay();
      },
      child: widget.child,
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.controller,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.focusNode,
    required this.composerHeight,
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.pendingAttachments,
    required this.attachmentsEnabled,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onReorderAttachments,
    required this.onSend,
    required this.onStop,
    required this.creationMode,
    required this.onCreationModeChanged,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.queuedMessages,
    required this.onRemoveQueuedMessage,
    required this.onMoveQueuedMessage,
    required this.onEditQueuedMessage,
  });

  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode focusNode;
  final double composerHeight;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final List<_ComposerAttachmentDraft> pendingAttachments;
  final bool attachmentsEnabled;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(int oldIndex, int newIndex) onReorderAttachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final List<_QueuedMessage> queuedMessages;
  final ValueChanged<int> onRemoveQueuedMessage;
  final void Function(int from, int to) onMoveQueuedMessage;
  final void Function(int index, String newText) onEditQueuedMessage;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  List<Widget> _buildModelMenuItems(BuildContext context) {
    final items = <Widget>[];
    final selectedId = widget.selectedModel?.id;
    final selectedModelId = widget.selectedModel?.modelId;
    for (final provider in widget.availableModels) {
      final allIds = provider.allModelIds;
      if (allIds.isEmpty) {
        // Provider with no discovered models — show as single entry.
        final isActive =
            provider.id == selectedId && provider.modelId == selectedModelId;
        items.add(
          MenuItemButton(
            leadingIcon: Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
            onPressed: () =>
                widget.onModelSelected(provider.id, provider.modelId),
            child: Text(provider.providerLabel),
          ),
        );
      } else {
        // Provider with models — show group header + sub-items.
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              '${provider.providerLabel}  (${provider.protocolType.storageValue})',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        for (final modelId in allIds) {
          final isActive =
              provider.id == selectedId && modelId == selectedModelId;
          items.add(
            MenuItemButton(
              leadingIcon: Icon(
                isActive
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
              ),
              onPressed: () => widget.onModelSelected(provider.id, modelId),
              child: Text(modelId),
            ),
          );
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedModelLabel =
        widget.selectedModel?.displayName ?? l10n.chatModelButton;
    final isCompressing = widget.sendPhase == AiSendPhase.compressing;
    final isSendingMessage = widget.sendPhase == AiSendPhase.sendingMessage;
    final isResponding = widget.sendPhase == AiSendPhase.responding;
    final isBusy = widget.sendPhase != AiSendPhase.idle;
    final canStopSending = widget.canStopSending;
    final modeToggleEnabled = widget.sendPhase == AiSendPhase.idle;
    final runtimeStatus = widget.currentSession == null
        ? null
        : _runtimeToolCatalogStatus(
            widget.currentSession!,
            livePreview: widget.liveRuntimeToolPreview,
          );
    final sendButtonLabel = canStopSending
        ? _localizedText(context, zh: '停止回答', en: 'Stop Response')
        : switch (widget.sendPhase) {
            AiSendPhase.compressing => _localizedText(
              context,
              zh: '消息压缩中',
              en: 'Compressing Messages',
            ),
            AiSendPhase.sendingMessage => l10n.chatSending,
            AiSendPhase.responding => _localizedText(
              context,
              zh: '停止回答',
              en: 'Stop Response',
            ),
            AiSendPhase.awaitingApproval => _localizedText(
              context,
              zh: '等待批准',
              en: 'Awaiting Approval',
            ),
            AiSendPhase.idle => l10n.composerSend,
          };

    final expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.editingMessageId != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: _borderRadius999,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  _localizedText(
                    context,
                    zh: '正在编辑历史消息',
                    en: 'Editing Previous Message',
                  ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    widget.onCancelEditing();
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.queuedMessages.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.queuedMessages.length,
            itemBuilder: (context, index) {
              final msg = widget.queuedMessages[index];
              final isFirst = index == 0;
              final isLast = index == widget.queuedMessages.length - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      if (msg.attachments.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${msg.attachments.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isFirst
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index - 1),
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: 14,
                          color: isFirst
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '上移',
                          en: 'Move up',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isLast
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index + 1),
                        icon: Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: isLast
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '下移',
                          en: 'Move down',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () async {
                          final edited = await _showEditQueuedMessageDialog(
                            context,
                            msg.text,
                          );
                          if (edited != null && edited.trim().isNotEmpty) {
                            widget.onEditQueuedMessage(index, edited);
                          }
                        },
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '编辑此等待消息',
                          en: 'Edit this queued message',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => widget.onRemoveQueuedMessage(index),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '删除此等待消息',
                          en: 'Remove this queued message',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        if (widget.pendingAttachments.isNotEmpty) ...[
          _ReorderableAttachmentWrap(
            attachments: widget.pendingAttachments,
            onReorder: widget.onReorderAttachments,
            onRemove: (filePath) => widget.onRemoveAttachment(filePath),
            onTap: (draft) => _openComposerAttachment(context, draft),
          ),
          const SizedBox(height: 12),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            height: widget.composerHeight,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              expands: true,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(hintText: l10n.composerHint),
            ),
          ),
        ),
      ],
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                MenuAnchor(
                  style: MenuStyle(
                    maximumSize: WidgetStatePropertyAll(
                      Size(360, MediaQuery.sizeOf(context).height * 0.5),
                    ),
                  ),
                  menuChildren: _buildModelMenuItems(context),
                  builder: (context, controller, child) {
                    return OutlinedButton.icon(
                      onPressed: widget.availableModels.isEmpty
                          ? null
                          : () {
                              if (controller.isOpen) {
                                controller.close();
                                return;
                              }
                              controller.open();
                            },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.hub_outlined),
                      label: Text(
                        selectedModelLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: widget.attachmentsEnabled
                      ? _localizedText(
                          context,
                          zh: '选择附件（最多 $aiMessageAttachmentLimit 个，支持图片、文本、代码、表格和 PDF）',
                          en: 'Choose attachments (up to $aiMessageAttachmentLimit; images, text, code, spreadsheets, and PDF)',
                        )
                      : _localizedText(
                          context,
                          zh: '当前模型不支持附件',
                          en: 'The selected model does not support attachments',
                        ),
                  child: OutlinedButton.icon(
                    onPressed: widget.attachmentsEnabled
                        ? widget.onPickAttachments
                        : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      widget.pendingAttachments.isEmpty
                          ? _localizedText(context, zh: '附件', en: 'Attach')
                          : _localizedText(
                              context,
                              zh: '附件 ${widget.pendingAttachments.length}',
                              en: 'Files ${widget.pendingAttachments.length}',
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ComposerFullAccessModeButton(
                  fullAccess: widget.fullAccessPermission,
                  enabled: true,
                  onChanged: (bool value) {
                    if (value != widget.fullAccessPermission) {
                      widget.onToggleFullAccessPermission(value);
                    }
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: _composerModeTooltip(
                    context,
                    widget.sessionMode,
                    runtimeStatus,
                  ),
                  child: _ComposerModeButton(
                    mode: widget.sessionMode,
                    runtimeStatus: runtimeStatus,
                    enabled: modeToggleEnabled,
                    onPressed: () {
                      widget.onSessionModeChanged(
                        widget.sessionMode == AiSessionMode.plan
                            ? AiSessionMode.chat
                            : AiSessionMode.plan,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.isCollapsed ? '展开输入框' : '折叠输入框',
            en: widget.isCollapsed ? 'Expand Composer' : 'Collapse Composer',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: () => widget.onCollapsedChanged(!widget.isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Icon(
                widget.isCollapsed
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.autoFollowEnabled ? '关闭自动滚动' : '开启自动滚动',
            en: widget.autoFollowEnabled
                ? 'Disable Auto Follow'
                : 'Enable Auto Follow',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.onToggleAutoFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: widget.autoFollowEnabled
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: widget.autoFollowEnabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                side: widget.autoFollowEnabled
                    ? null
                    : BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                widget.autoFollowEnabled
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.vertical_align_bottom_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ComposerCreationModeButton(
          creationMode: widget.creationMode,
          onCreationModeChanged: widget.onCreationModeChanged,
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, textValue, _) {
            final hasUserTextOrAttachments =
                textValue.text.trim().isNotEmpty ||
                widget.pendingAttachments.isNotEmpty;
            final isQueueingAction = isBusy && hasUserTextOrAttachments;

            return SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: isQueueingAction
                    ? () => widget.onSend()
                    : canStopSending && !hasUserTextOrAttachments
                    ? () => widget.onStop()
                    : isBusy
                    ? null
                    : () => widget.onSend(),
                icon: isQueueingAction
                    ? const Icon(Icons.queue_play_next_rounded)
                    : canStopSending && !hasUserTextOrAttachments
                    ? const Icon(Icons.stop_rounded)
                    : isCompressing || isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        isResponding
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                label: Text(
                  isQueueingAction
                      ? _localizedText(context, zh: '提前发送', en: 'Queue Message')
                      : canStopSending && !hasUserTextOrAttachments
                      ? _localizedText(
                          context,
                          zh: '停止回答',
                          en: 'Stop Responding',
                        )
                      : sendButtonLabel,
                ),
              ),
            );
          },
        ),
      ],
    );

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubicEmphasized,
        padding: EdgeInsets.fromLTRB(18, 14, 18, widget.isCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: widget.isCollapsed ? 1 : 0,
                end: widget.isCollapsed ? 0 : 1,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              child: expandedContent,
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: value,
                    child: IgnorePointer(
                      ignoring: value < 0.98,
                      child: Opacity(
                        opacity: value.clamp(0, 1).toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              height: widget.isCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

class _ComposerFullAccessModeButton extends StatelessWidget {
  const _ComposerFullAccessModeButton({
    required this.fullAccess,
    required this.enabled,
    required this.onChanged,
  });

  final bool fullAccess;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeLabel = fullAccess
        ? _localizedText(context, zh: '完全访问权限', en: 'Full Access')
        : _localizedText(context, zh: '默认权限', en: 'Default Access');
    final backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : fullAccess
        ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : fullAccess
        ? const Color(0xFFF59E0B)
        : colorScheme.onSurfaceVariant;
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : fullAccess
        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
        : colorScheme.outlineVariant;

    return MenuAnchor(
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                fullAccess
                    ? Icons.gpp_maybe_outlined
                    : Icons.admin_panel_settings_outlined,
                size: 18,
                color: foregroundColor,
              ),
              const SizedBox(width: 8),
              Text(
                modeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: foregroundColor,
              ),
            ],
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(
            Icons.admin_panel_settings_outlined,
            size: 20,
          ),
          trailingIcon: !fullAccess
              ? const Icon(Icons.check_rounded, size: 20)
              : const SizedBox(width: 20),
          onPressed: () => onChanged(false),
          child: Text(
            _localizedText(context, zh: '默认权限', en: 'Default Access'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.gpp_maybe_outlined, size: 20),
          trailingIcon: fullAccess
              ? const Icon(Icons.check_rounded, size: 20)
              : const SizedBox(width: 20),
          onPressed: () => onChanged(true),
          child: Text(_localizedText(context, zh: '完全访问权限', en: 'Full Access')),
        ),
      ],
    );
  }
}

class _ComposerModeButton extends StatelessWidget {
  const _ComposerModeButton({
    required this.mode,
    required this.runtimeStatus,
    required this.enabled,
    required this.onPressed,
  });

  final AiSessionMode mode;
  final _RuntimeToolCatalogStatus? runtimeStatus;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPlanMode = mode == AiSessionMode.plan;
    final modeIcon = _runtimeModeIcon(runtimeStatus, explicitMode: mode);
    final modeLabel = _runtimeModeLabel(
      context,
      runtimeStatus,
      compact: true,
      explicitMode: mode,
    );
    final backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : isPlanMode
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isPlanMode
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final accentColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.28)
        : colorScheme.primary.withValues(alpha: isPlanMode ? 1 : 0.9);
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : isPlanMode
        ? colorScheme.primary.withValues(alpha: 0.24)
        : colorScheme.outlineVariant;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isPlanMode ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: Icon(
                modeIcon,
                key: ValueKey<String>('${mode.storageValue}-$modeIcon'),
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              modeLabel,
              key: ValueKey<String>('${mode.storageValue}-$modeLabel'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Creation mode types for the composer.
enum _CreationMode { none, image, video, audio, deepResearch }

/// A "+" button that opens a popup for creation modes (image, video, audio, deep research).
/// When a supported mode is selected, the button turns active (primary color + mode icon).
class _ComposerCreationModeButton extends StatefulWidget {
  const _ComposerCreationModeButton({
    required this.creationMode,
    required this.onCreationModeChanged,
  });

  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;

  @override
  State<_ComposerCreationModeButton> createState() =>
      _ComposerCreationModeButtonState();
}

class _ComposerCreationModeButtonState
    extends State<_ComposerCreationModeButton> {
  IconData _iconForMode(_CreationMode mode) => switch (mode) {
    _CreationMode.none => Icons.add_rounded,
    _CreationMode.image => Icons.image_outlined,
    _CreationMode.video => Icons.videocam_outlined,
    _CreationMode.audio => Icons.audiotrack_outlined,
    _CreationMode.deepResearch => Icons.travel_explore_rounded,
  };

  /// Notify the parent of a mode change after the current frame to avoid
  /// mutating the widget tree while the [MouseTracker] is mid-update.
  void _deferModeChange(_CreationMode mode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreationModeChanged(mode);
    });
  }

  void _selectMode(_CreationMode mode) {
    if (mode == widget.creationMode) {
      // Toggle off.
      _deferModeChange(_CreationMode.none);
      return;
    }
    // Only image generation is currently supported.
    if (mode != _CreationMode.image) {
      final label = switch (mode) {
        _CreationMode.video => _localizedText(
          context,
          zh: '视频生成功能暂不支持，敬请期待',
          en: 'Video generation is not yet supported',
        ),
        _CreationMode.audio => _localizedText(
          context,
          zh: '音频生成功能暂不支持，敬请期待',
          en: 'Audio generation is not yet supported',
        ),
        _CreationMode.deepResearch => _localizedText(
          context,
          zh: '深度研究功能暂不支持，敬请期待',
          en: 'Deep Research is not yet supported',
        ),
        _ => '',
      };
      if (label.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _deferModeChange(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.creationMode != _CreationMode.none;
    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: _localizedText(context, zh: '创建', en: 'Create'),
          child: SizedBox(
            width: 52,
            height: 52,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FilledButton(
                onPressed: () {
                  // When active, toggle off instead of opening the menu.
                  if (isActive) {
                    _deferModeChange(_CreationMode.none);
                    return;
                  }
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 52),
                  backgroundColor: isActive
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: isActive
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  side: isActive
                      ? null
                      : BorderSide(color: colorScheme.outlineVariant),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    _iconForMode(widget.creationMode),
                    key: ValueKey<_CreationMode>(widget.creationMode),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            Icons.image_outlined,
            size: 20,
            color: widget.creationMode == _CreationMode.image
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          trailingIcon: widget.creationMode == _CreationMode.image
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onPressed: () => _selectMode(_CreationMode.image),
          child: Text(_localizedText(context, zh: '创建图片', en: 'Create Image')),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.videocam_outlined, size: 20),
          onPressed: () => _selectMode(_CreationMode.video),
          child: Text(
            _localizedText(context, zh: '视频生成', en: 'Generate Video'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.audiotrack_outlined, size: 20),
          onPressed: () => _selectMode(_CreationMode.audio),
          child: Text(
            _localizedText(context, zh: '音频生成', en: 'Generate Audio'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.travel_explore_rounded, size: 20),
          onPressed: () => _selectMode(_CreationMode.deepResearch),
          child: Text(_localizedText(context, zh: '深度研究', en: 'Deep Research')),
        ),
      ],
    );
  }
}

/// A wrap layout that allows drag-to-reorder of attachment chips.
class _ReorderableAttachmentWrap extends StatefulWidget {
  const _ReorderableAttachmentWrap({
    required this.attachments,
    required this.onReorder,
    required this.onRemove,
    required this.onTap,
  });

  final List<_ComposerAttachmentDraft> attachments;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;
  final void Function(_ComposerAttachmentDraft draft) onTap;

  @override
  State<_ReorderableAttachmentWrap> createState() =>
      _ReorderableAttachmentWrapState();
}

class _ReorderableAttachmentWrapState
    extends State<_ReorderableAttachmentWrap> {
  int? _dragIndex;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(widget.attachments.length, (index) {
        final attachment = widget.attachments[index];
        final isDragging = _dragIndex == index;
        final isHovering = _hoverIndex == index;
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data != index) {
              setState(() => _hoverIndex = index);
            }
            return details.data != index;
          },
          onLeave: (_) {
            if (_hoverIndex == index) {
              setState(() => _hoverIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _hoverIndex = null);
            widget.onReorder(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Draggable<int>(
              data: index,
              onDragStarted: () => setState(() => _dragIndex = index),
              onDragEnd: (_) => setState(() {
                _dragIndex = null;
                _hoverIndex = null;
              }),
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: Opacity(
                  opacity: 0.85,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () {},
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _ComposerAttachmentChip(
                  attachment: attachment,
                  onRemove: () {},
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: isHovering
                    ? (Matrix4.identity()..scale(1.05))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                child: Opacity(
                  opacity: isDragging ? 0.3 : 1.0,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () => widget.onRemove(attachment.filePath),
                    onTap: () => widget.onTap(attachment),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
    this.onTap,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForAttachmentKind(attachment.kind),
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onRemove,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerAttachmentDraft {
  const _ComposerAttachmentDraft({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.sizeBytes,
  });

  final String filePath;
  final String name;
  final AiAttachmentKind kind;
  final int sizeBytes;

  static Future<_ComposerAttachmentDraft> fromPath(String path) async {
    final file = File(path);
    final stat = await file.stat();
    return _ComposerAttachmentDraft(
      filePath: path,
      name: p.basename(path),
      kind: aiAttachmentKindForPath(path),
      sizeBytes: stat.size,
    );
  }
}

IconData _iconForAttachmentKind(AiAttachmentKind kind) {
  return switch (kind) {
    AiAttachmentKind.image => Icons.image_outlined,
    AiAttachmentKind.text => Icons.description_outlined,
    AiAttachmentKind.spreadsheet => Icons.table_chart_outlined,
    AiAttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AiAttachmentKind.binary => Icons.insert_drive_file_outlined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HE session tile shown in the navigation pane threads list.
// Mirrors the visual design of _ThreadTile for consistency.
// ─────────────────────────────────────────────────────────────────────────────

class _HardnessSessionTile extends StatelessWidget {
  const _HardnessSessionTile({
    required this.title,
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String title;
  final HardnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final showBadge =
        awaitingApproval ||
        (status != HardnessOrchestratorStatus.idle &&
            status != HardnessOrchestratorStatus.completed);

    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final selected = await showAnimatedMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem<String>(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonEdit),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonDelete),
                ],
              ),
            ),
          ],
        );
        if (!context.mounted || selected == null) {
          return;
        }
        final VoidCallback? action = switch (selected) {
          'rename' => onRename,
          'delete' => onDelete,
          _ => null,
        };
        if (action == null) {
          return;
        }
        _scheduleOverlayActionAfterMenuDismissal(context, action);
      },
      child: Material(
        color: backgroundColor,
        borderRadius: _borderRadius18,
        child: InkWell(
          onTap: onTap,
          borderRadius: _borderRadius18,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _AnimatedSessionTitleText(
                    text: title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                    ),
                  ),
                ),
                if (showBadge) ...[
                  const SizedBox(width: 12),
                  _HardnessStatusCapsule(
                    status: status,
                    awaitingApproval: awaitingApproval,
                    isSelected: isSelected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status badge for Hardness Engineering sessions.
/// Uses the same [_SweepBadge] animation for the running state and a static
/// rounded capsule for terminal states — matching the [_ActiveThreadBadge]
/// pattern used for AI thread sessions.
class _HardnessStatusCapsule extends StatelessWidget {
  const _HardnessStatusCapsule({
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
  });

  final HardnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    if (awaitingApproval) {
      const foregroundColor = Color(0xFFE6A817);
      final backgroundColor = foregroundColor.withValues(alpha: 0.14);
      final borderColor = foregroundColor.withValues(alpha: 0.22);
      return _SweepBadge(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        sweepColor: foregroundColor.withValues(alpha: 0.18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PulsingDot(color: foregroundColor, size: 8),
            const SizedBox(width: 8),
            Text(
              isZh ? '等待批准' : 'Awaiting Approval',
              style: theme.textTheme.labelMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final (Color fg, String label) = switch (status) {
      HardnessOrchestratorStatus.running => (
        isSelected ? colorScheme.onPrimaryContainer : colorScheme.primary,
        isZh ? '运行中' : 'Running',
      ),
      HardnessOrchestratorStatus.completed => (
        const Color(0xFF5F7C53),
        isZh ? '已完成' : 'Done',
      ),
      HardnessOrchestratorStatus.failed => (
        const Color(0xFFC84B4B),
        isZh ? '失败' : 'Failed',
      ),
      HardnessOrchestratorStatus.cancelled => (
        const Color(0xFFD97A33),
        isZh ? '已中止' : 'Cancelled',
      ),
      HardnessOrchestratorStatus.idle => (colorScheme.outline, ''),
    };

    if (status == HardnessOrchestratorStatus.idle ||
        status == HardnessOrchestratorStatus.completed) {
      return const SizedBox.shrink();
    }

    final bg = fg.withValues(alpha: 0.12);
    final border = fg.withValues(alpha: 0.22);
    final labelWidget = Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: fg,
        fontWeight: FontWeight.w700,
      ),
    );

    if (status == HardnessOrchestratorStatus.running) {
      return _SweepBadge(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: bg,
        borderColor: border,
        sweepColor: fg.withValues(alpha: 0.18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            labelWidget,
          ],
        ),
      );
    }

    // Static capsule for terminal states.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: _borderRadius999,
        border: Border.all(color: border),
      ),
      child: labelWidget,
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.session,
    required this.sendPhase,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final AiSession session;
  final AiSendPhase sendPhase;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final isActive = sendPhase != AiSendPhase.idle;
    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final selected = await showAnimatedMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem<String>(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonEdit),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonDelete),
                ],
              ),
            ),
          ],
        );
        if (!context.mounted || selected == null) {
          return;
        }
        final VoidCallback? action = switch (selected) {
          'rename' => onRename,
          'delete' => onDelete,
          _ => null,
        };
        if (action == null) {
          return;
        }
        _scheduleOverlayActionAfterMenuDismissal(context, action);
      },
      child: Material(
        color: backgroundColor,
        borderRadius: _borderRadius18,
        child: InkWell(
          borderRadius: _borderRadius18,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _AnimatedSessionTitleText(
                    text: session.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                    ),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 12),
                  _ActiveThreadBadge(
                    key: ValueKey<String>('thread-active-${session.id}'),
                    sendPhase: sendPhase,
                    isSelected: isSelected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveThreadBadge extends StatelessWidget {
  const _ActiveThreadBadge({
    super.key,
    required this.sendPhase,
    required this.isSelected,
  });

  final AiSendPhase sendPhase;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isApprovalPhase = sendPhase == AiSendPhase.awaitingApproval;
    // Use an amber/warning palette for the approval state so it stands out
    // from the regular "active" badge and draws the user's attention.
    final foregroundColor = isApprovalPhase
        ? const Color(0xFFE6A817)
        : isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final backgroundColor = isApprovalPhase
        ? const Color(0xFFE6A817).withValues(alpha: 0.14)
        : isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.14)
        : colorScheme.primary.withValues(alpha: 0.12);
    final label = switch (sendPhase) {
      AiSendPhase.compressing => _localizedText(
        context,
        zh: '压缩中',
        en: 'Compressing',
      ),
      AiSendPhase.sendingMessage => _localizedText(
        context,
        zh: '发送中',
        en: 'Sending',
      ),
      AiSendPhase.responding => _localizedText(
        context,
        zh: '进行中',
        en: 'Active',
      ),
      AiSendPhase.awaitingApproval => _localizedText(
        context,
        zh: '等待批准',
        en: 'Awaiting Approval',
      ),
      AiSendPhase.idle => '',
    };
    return _SweepBadge(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      backgroundColor: backgroundColor,
      borderColor: foregroundColor.withValues(alpha: 0.22),
      sweepColor: foregroundColor.withValues(alpha: 0.18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isApprovalPhase)
            _PulsingDot(color: foregroundColor, size: 8)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: foregroundColor,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circle that pulses (fades in and out) to draw attention.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.35 + _controller.value * 0.65;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _MessageMetaRow extends StatelessWidget {
  const _MessageMetaRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ReasoningMetaRow extends StatefulWidget {
  const _ReasoningMetaRow({
    required this.message,
    required this.color,
    required this.showSweep,
    required this.expanded,
    required this.onTap,
  });

  final AiSessionMessage message;
  final Color color;
  final bool showSweep;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ReasoningMetaRow> createState() => _ReasoningMetaRowState();
}

class _ReasoningMetaRowState extends State<_ReasoningMetaRow> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant _ReasoningMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSweep != widget.showSweep ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      _syncElapsedTimer();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    if (!widget.showSweep) {
      return;
    }
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = _localizedText(context, zh: '思考', en: 'Reasoning');
    final elapsedText = widget.showSweep
        ? ' (${_formatToolExecutionDuration(_reasoningElapsedMs(widget.message))})'
        : '';
    final pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.psychology_alt_outlined,
          size: 18,
          color: widget.color.withValues(alpha: widget.showSweep ? 0.94 : 0.88),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: widget.color.withValues(
                alpha: widget.showSweep ? 0.94 : 0.88,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: widget.expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: widget.color.withValues(alpha: 0.78),
            size: 18,
          ),
        ),
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            borderColor: Colors.white.withValues(alpha: 0.14),
            sweepColor: const Color(0x33E5E7EB),
            child: pillContent,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: _borderRadius999,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: _borderRadius999,
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.03),
        ),
        child: capsule,
      ),
    );
  }
}

class _ToolCallMetaRow extends StatelessWidget {
  const _ToolCallMetaRow({required this.data, required this.color});

  final _ToolCallStatusViewData data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSweep = data.shouldSweepBadge;
    final effectiveColor = showSweep
        ? theme.colorScheme.onSurfaceVariant
        : color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.statusIcon, size: 18, color: effectiveColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: effectiveColor),
          ),
        ),
      ],
    );
    if (showSweep) {
      return _SweepBadge(child: row);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: _borderRadius999,
      ),
      child: row,
    );
  }
}

class _ToolCallStatusViewData {
  const _ToolCallStatusViewData({
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.statusLabel,
  });

  factory _ToolCallStatusViewData.from(
    BuildContext context,
    AiSessionMessage message,
  ) {
    final presentation = _toolCallPresentation(context, message);
    final status = _toolExecutionStatus(message);
    final durationMs = _toolExecutionDurationMs(message);
    return _ToolCallStatusViewData(
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      statusLabel: _toolCallStatusLabelForData(
        context,
        presentation,
        status,
        durationMs,
      ),
    );
  }

  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String statusLabel;
}

class _SweepBadge extends StatefulWidget {
  const _SweepBadge({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.backgroundColor,
    this.borderColor,
    this.sweepColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? sweepColor;

  @override
  State<_SweepBadge> createState() => _SweepBadgeState();
}

class _SweepBadgeState extends State<_SweepBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const borderRadius = BorderRadius.all(Radius.circular(999));
    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedBuilder(
        animation: _controller,
        child: Padding(padding: widget.padding, child: widget.child),
        builder: (context, child) {
          final start = -1.8 + (_controller.value * 2.8);
          final end = start + 0.9;
          final sweepColor =
              widget.sweepColor ??
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
          final backgroundColor =
              widget.backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
          final borderColor =
              widget.borderColor ??
              theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: borderColor.a <= 0
                  ? null
                  : Border.all(color: borderColor),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(start, 0),
                        end: Alignment(end, 0),
                        colors: [
                          Colors.transparent,
                          sweepColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HighlightedCodeBlockBuilder extends MarkdownElementBuilder {
  _HighlightedCodeBlockBuilder({
    required ThemeData theme,
    required Color baseColor,
    required bool darkSurface,
    required bool selectable,
  }) : _theme = theme,
       _baseColor = baseColor,
       _darkSurface = darkSurface,
       _selectable = selectable;

  final ThemeData _theme;
  final Color _baseColor;
  final bool _darkSurface;
  final bool _selectable;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final codeElement = _findCodeElement(element);
    final rawCode = (codeElement?.textContent ?? element.textContent)
        .replaceFirst(_trailingNewlineCodeBlockPattern, '');
    final language = _extractCodeLanguage(codeElement);
    final content = rawCode.isEmpty ? ' ' : rawCode;
    return RepaintBoundary(
      child: _HighlightedCodePanel(
        content: content,
        theme: _theme,
        language: language,
        selectable: _selectable,
        baseColor: _baseColor,
        forceDarkSurface: _darkSurface,
        allowAutoDetection: true,
      ),
    );
  }

  md.Element? _findCodeElement(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        return child;
      }
    }
    return null;
  }
}

class _HighlightedCodePanel extends StatefulWidget {
  const _HighlightedCodePanel({
    required this.content,
    required this.theme,
    required this.baseColor,
    required this.selectable,
    this.language,
    this.forceDarkSurface = false,
    this.accentColor,
    this.allowAutoDetection = false,
    this.wrapLines = false,
  });

  final String content;
  final ThemeData theme;
  final String? language;
  final Color baseColor;
  final bool selectable;
  final bool forceDarkSurface;
  final Color? accentColor;
  final bool allowAutoDetection;
  final bool wrapLines;

  @override
  State<_HighlightedCodePanel> createState() => _HighlightedCodePanelState();
}

class _HighlightedCodePanelState extends State<_HighlightedCodePanel> {
  TextSpan? _highlightedSpan;
  int? _highlightSignature;
  bool _copied = false;
  Timer? _copiedResetTimer;
  _CodeBlockPalette? _cachedPalette;
  int? _cachedPaletteSignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureHighlightedSpan();
  }

  @override
  void didUpdateWidget(covariant _HighlightedCodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.language != widget.language ||
        oldWidget.selectable != widget.selectable ||
        oldWidget.baseColor != widget.baseColor ||
        oldWidget.forceDarkSurface != widget.forceDarkSurface ||
        oldWidget.allowAutoDetection != widget.allowAutoDetection ||
        oldWidget.theme.brightness != widget.theme.brightness ||
        oldWidget.theme.textTheme.bodyMedium?.fontSize !=
            widget.theme.textTheme.bodyMedium?.fontSize ||
        oldWidget.theme.textTheme.bodyMedium?.fontFamily !=
            widget.theme.textTheme.bodyMedium?.fontFamily ||
        oldWidget.theme.textTheme.bodyMedium?.height !=
            widget.theme.textTheme.bodyMedium?.height) {
      _highlightedSpan = null;
      _highlightSignature = null;
    }
    if (oldWidget.content != widget.content) {
      _copiedResetTimer?.cancel();
      _copied = false;
    }
    _ensureHighlightedSpan();
  }

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final paletteSignature = Object.hashAll(<Object?>[
      widget.theme.colorScheme.primary.toARGB32(),
      widget.theme.brightness.index,
      useDarkPalette,
      widget.accentColor?.toARGB32(),
    ]);
    if (_cachedPalette == null || _cachedPaletteSignature != paletteSignature) {
      _cachedPalette = _CodeBlockPalette.fromTheme(
        widget.theme,
        useDarkPalette: useDarkPalette,
        accentColor: widget.accentColor,
      );
      _cachedPaletteSignature = paletteSignature;
    }
    final palette = _cachedPalette!;
    final copyLabel = _localizedText(
      context,
      zh: _copied ? '已复制' : '复制',
      en: _copied ? 'Copied' : 'Copy',
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.containerColor,
        borderRadius: _borderRadius18,
        border: Border.all(color: palette.borderColor),
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: palette.headerColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
              border: Border(bottom: BorderSide(color: palette.dividerColor)),
            ),
            child: Row(
              children: [
                if (effectiveLanguage != null)
                  _buildHeaderPill(
                    label: effectiveLanguage,
                    icon: Icons.code_rounded,
                    backgroundColor: palette.badgeColor,
                    foregroundColor: palette.badgeTextColor,
                  )
                else
                  const SizedBox(height: 32),
                const Spacer(),
                _buildHeaderPill(
                  label: copyLabel,
                  icon: _copied
                      ? Icons.check_rounded
                      : Icons.content_copy_rounded,
                  backgroundColor: palette.actionColor,
                  foregroundColor: palette.actionTextColor,
                  onTap: _copyCodeBlock,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bodyColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.bodyBorderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: widget.wrapLines
                    ? (widget.selectable
                          ? SelectableText.rich(
                              _highlightedSpan ?? const TextSpan(),
                            )
                          : RichText(
                              text: _highlightedSpan ?? const TextSpan(),
                            ))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: widget.selectable
                            ? SelectableText.rich(
                                _highlightedSpan ?? const TextSpan(),
                              )
                            : RichText(
                                text: _highlightedSpan ?? const TextSpan(),
                              ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _ensureHighlightedSpan() {
    final effectiveLanguage = _normalizeCodeLanguage(widget.language);
    final useDarkPalette =
        widget.forceDarkSurface || widget.theme.brightness == Brightness.dark;
    final signature = Object.hashAll(<Object?>[
      widget.content,
      effectiveLanguage,
      widget.allowAutoDetection,
      widget.baseColor.toARGB32(),
      useDarkPalette,
      widget.theme.textTheme.bodyMedium?.fontSize,
      widget.theme.textTheme.bodyMedium?.fontFamily,
      widget.theme.textTheme.bodyMedium?.height,
    ]);
    if (_highlightedSpan != null && _highlightSignature == signature) {
      return;
    }
    final highlighter = _CodeSyntaxHighlighter(
      baseStyle:
          widget.theme.textTheme.bodyMedium?.copyWith(
            color: widget.baseColor,
            fontFamily: 'monospace',
            height: 1.48,
          ) ??
          TextStyle(
            color: widget.baseColor,
            fontFamily: 'monospace',
            height: 1.48,
          ),
      darkSurface: useDarkPalette,
    );
    _highlightedSpan = highlighter.build(
      widget.content,
      language: effectiveLanguage,
      allowAutoDetection: widget.allowAutoDetection,
    );
    _highlightSignature = signature;
  }

  Widget _buildHeaderPill({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    VoidCallback? onTap,
  }) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: widget.theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: _borderRadius999,
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: _borderRadius999,
        child: Ink(decoration: decoration, child: child),
      ),
    );
  }

  void _copyCodeBlock() {
    _copiedResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(context, zh: '代码块内容已复制。', en: 'Code copied.'),
          ),
        ),
      );
    _copiedResetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _copied = false;
      });
    });
    unawaited(_writeCodeBlockToClipboard());
  }

  Future<void> _writeCodeBlockToClipboard() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.content));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _copiedResetTimer?.cancel();
      setState(() {
        _copied = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(
                context,
                zh: '复制代码块失败。',
                en: 'Failed to copy code.',
              ),
            ),
          ),
        );
    }
  }
}

class _CodeBlockPalette {
  factory _CodeBlockPalette.fromTheme(
    ThemeData theme, {
    required bool useDarkPalette,
    Color? accentColor,
  }) {
    final colorScheme = theme.colorScheme;
    final tint = accentColor ?? colorScheme.primary;
    if (useDarkPalette) {
      final darkScheme = theme.brightness == Brightness.dark
          ? colorScheme
          : () {
              final tintValue = tint.toARGB32();
              if (_cachedDarkScheme != null &&
                  _cachedDarkSchemeTintValue == tintValue) {
                return _cachedDarkScheme!;
              }
              final scheme = ColorScheme.fromSeed(
                seedColor: tint,
                brightness: Brightness.dark,
                dynamicSchemeVariant: DynamicSchemeVariant.expressive,
              );
              _cachedDarkScheme = scheme;
              _cachedDarkSchemeTintValue = tintValue;
              return scheme;
            }();
      return _CodeBlockPalette(
        containerColor: Color.alphaBlend(
          tint.withValues(alpha: 0.05),
          darkScheme.surfaceContainerHigh,
        ),
        borderColor: darkScheme.outlineVariant.withValues(alpha: 0.78),
        headerColor: Color.alphaBlend(
          tint.withValues(alpha: 0.08),
          darkScheme.surfaceContainerHighest,
        ),
        dividerColor: darkScheme.outlineVariant.withValues(alpha: 0.52),
        bodyColor: Color.alphaBlend(
          Colors.black.withValues(alpha: 0.14),
          darkScheme.surfaceContainerLow,
        ),
        bodyBorderColor: darkScheme.outlineVariant.withValues(alpha: 0.34),
        badgeColor: Color.alphaBlend(
          tint.withValues(alpha: 0.16),
          darkScheme.surfaceContainerHighest,
        ),
        badgeTextColor: darkScheme.onSurface,
        actionColor: Color.alphaBlend(
          tint.withValues(alpha: 0.08),
          darkScheme.surfaceContainerHighest,
        ),
        actionTextColor: darkScheme.onSurface,
        shadowColor: Colors.black.withValues(alpha: 0.18),
      );
    }
    return _CodeBlockPalette(
      containerColor: Color.alphaBlend(
        tint.withValues(alpha: 0.025),
        colorScheme.surfaceContainerLow,
      ),
      borderColor: Color.alphaBlend(
        tint.withValues(alpha: 0.08),
        colorScheme.outlineVariant.withValues(alpha: 0.85),
      ),
      headerColor: Color.alphaBlend(
        tint.withValues(alpha: 0.05),
        colorScheme.surfaceContainer,
      ),
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.62),
      bodyColor: Colors.white.withValues(alpha: 0.45),
      bodyBorderColor: colorScheme.outlineVariant.withValues(alpha: 0.38),
      badgeColor: Color.alphaBlend(
        tint.withValues(alpha: 0.08),
        colorScheme.surface,
      ),
      badgeTextColor: colorScheme.onSurface,
      actionColor: Color.alphaBlend(
        colorScheme.surface.withValues(alpha: 0.4),
        colorScheme.surfaceContainerHighest,
      ),
      actionTextColor: colorScheme.onSurface,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.03),
    );
  }
  const _CodeBlockPalette({
    required this.containerColor,
    required this.borderColor,
    required this.headerColor,
    required this.dividerColor,
    required this.bodyColor,
    required this.bodyBorderColor,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.actionColor,
    required this.actionTextColor,
    required this.shadowColor,
  });

  // Static cache for the expensive ColorScheme.fromSeed dark palette.
  static ColorScheme? _cachedDarkScheme;
  static int? _cachedDarkSchemeTintValue;

  final Color containerColor;
  final Color borderColor;
  final Color headerColor;
  final Color dividerColor;
  final Color bodyColor;
  final Color bodyBorderColor;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color actionColor;
  final Color actionTextColor;
  final Color shadowColor;
}

final RegExp _markdownCodeFencePattern = RegExp(r'(^|\n)[ ]{0,3}(`{3,}|~{3,})');

bool _containsMarkdownCodeFence(String source) {
  return _markdownCodeFencePattern.hasMatch(source);
}

bool _canRenderMarkdownAsPlainText(String source) {
  final normalized = source.trim();
  if (normalized.isEmpty) {
    return true;
  }
  if (_containsMarkdownCodeFence(normalized)) {
    return false;
  }
  if (normalized.contains('/') || normalized.contains('\\')) {
    return false;
  }
  return !_markdownStructuralPattern.hasMatch(normalized);
}

final RegExp _fencedCodeBlockPattern = RegExp(
  r'^[ ]{0,3}((`{3,}|~{3,}))[^\n]*$',
);

String _closeUnterminatedFencedCodeBlock(String source) {
  final fencePattern = _fencedCodeBlockPattern;
  String? openFence;
  String? openFenceMarker;
  for (final line in const LineSplitter().convert(source)) {
    final match = fencePattern.firstMatch(line);
    if (match == null) {
      continue;
    }
    final delimiter = match.group(1)!;
    final marker = delimiter[0];
    if (openFence == null) {
      openFence = delimiter;
      openFenceMarker = marker;
      continue;
    }
    if (marker == openFenceMarker && delimiter.length >= openFence.length) {
      openFence = null;
      openFenceMarker = null;
    }
  }
  if (openFence == null) {
    return source;
  }
  final separator = source.isEmpty || source.endsWith('\n') ? '' : '\n';
  return '$source$separator$openFence';
}

class _CodeSyntaxHighlighter {
  _CodeSyntaxHighlighter({
    required TextStyle baseStyle,
    required bool darkSurface,
  }) : _baseStyle = baseStyle {
    // Pre-compute all token styles once per highlighter instance.
    _commentStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFF7DD3A7) : const Color(0xFF5B7C68),
      fontStyle: FontStyle.italic,
    );
    _keywordStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFFF9A8D4) : const Color(0xFFB42367),
      fontWeight: FontWeight.w700,
    );
    _stringStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
    );
    _numberStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
    );
    _titleStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFF67E8F9) : const Color(0xFF0F766E),
      fontWeight: FontWeight.w700,
    );
    _typeStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
      fontWeight: FontWeight.w600,
    );
    _metaStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
    );
    _operatorStyle = baseStyle.copyWith(
      color: darkSurface ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
    );
  }

  final TextStyle _baseStyle;

  // Pre-computed styles — avoids hundreds of copyWith() calls per code block.
  late final TextStyle _commentStyle;
  late final TextStyle _keywordStyle;
  late final TextStyle _stringStyle;
  late final TextStyle _numberStyle;
  late final TextStyle _titleStyle;
  late final TextStyle _typeStyle;
  late final TextStyle _metaStyle;
  late final TextStyle _operatorStyle;

  // Class-name → style fast lookup.
  static const Set<String> _commentClasses = {'comment', 'quote'};
  static const Set<String> _keywordClasses = {
    'keyword',
    'selector-tag',
    'meta-keyword',
    'doctag',
  };
  static const Set<String> _stringClasses = {
    'string',
    'regexp',
    'attribute',
    'template-variable',
  };
  static const Set<String> _numberClasses = {
    'number',
    'literal',
    'symbol',
    'bullet',
  };
  static const Set<String> _titleClasses = {
    'title',
    'function',
    'section',
    'title.function_',
    'title.class_',
  };
  static const Set<String> _typeClasses = {
    'type',
    'built_in',
    'class',
    'params',
    'variable',
    'selector-id',
    'selector-class',
    'selector-attr',
    'selector-pseudo',
    'property',
  };
  static const Set<String> _metaClasses = {'meta', 'attr', 'tag', 'name'};
  static const Set<String> _operatorClasses = {'operator', 'punctuation'};

  TextSpan build(
    String source, {
    String? language,
    bool allowAutoDetection = false,
  }) {
    final normalizedLanguage = _normalizeCodeLanguage(language);
    try {
      final parsed = highlight.highlight.parse(
        source,
        language: normalizedLanguage,
        autoDetection: allowAutoDetection && normalizedLanguage == null,
      );
      return TextSpan(
        style: _baseStyle,
        children: _buildHighlightedNodes(parsed.nodes),
      );
    } catch (_) {
      if (normalizedLanguage != null) {
        try {
          final parsed = highlight.highlight.parse(source, autoDetection: true);
          return TextSpan(
            style: _baseStyle,
            children: _buildHighlightedNodes(parsed.nodes),
          );
        } catch (_) {
          // Fall through to plain text rendering.
        }
      }
      return TextSpan(text: source, style: _baseStyle);
    }
  }

  List<InlineSpan> _buildHighlightedNodes(List<highlight.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return <InlineSpan>[TextSpan(style: _baseStyle)];
    }
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(
          TextSpan(
            text: node.value,
            style: node.className == null
                ? null
                : _styleForClass(node.className),
          ),
        );
        continue;
      }
      spans.add(
        TextSpan(
          style: node.className == null ? null : _styleForClass(node.className),
          children: _buildHighlightedNodes(node.children),
        ),
      );
    }
    return spans;
  }

  TextStyle _styleForClass(String? className) {
    final classes = (className ?? '').split(' ');
    for (final cls in classes) {
      if (_commentClasses.contains(cls)) return _commentStyle;
      if (_keywordClasses.contains(cls)) return _keywordStyle;
      if (_stringClasses.contains(cls)) return _stringStyle;
      if (_numberClasses.contains(cls)) return _numberStyle;
      if (_titleClasses.contains(cls)) return _titleStyle;
      if (_typeClasses.contains(cls)) return _typeStyle;
      if (_metaClasses.contains(cls)) return _metaStyle;
      if (_operatorClasses.contains(cls)) return _operatorStyle;
    }
    return _baseStyle;
  }
}

String? _extractCodeLanguage(md.Element? element) {
  final classes = (element?.attributes['class'] ?? '').trim();
  if (classes.isEmpty) {
    return null;
  }
  for (final name in classes.split(' ')) {
    if (name.startsWith('language-') && name.length > 9) {
      return name.substring(9);
    }
    if (name.startsWith('lang-') && name.length > 5) {
      return name.substring(5);
    }
  }
  return null;
}

String? _normalizeCodeLanguage(String? language) {
  final normalized = (language ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'text' || normalized == 'plaintext') {
    return null;
  }
  return switch (normalized) {
    'shell' || 'sh' || 'zsh' => 'bash',
    'yml' => 'yaml',
    'htm' => 'html',
    _ => normalized,
  };
}

class _TokenDial extends StatefulWidget {
  const _TokenDial({
    required this.totalTokens,
    this.cacheReadTokens,
    this.cacheCreationTokens,
  });

  final int totalTokens;
  final int? cacheReadTokens;
  final int? cacheCreationTokens;

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial> {
  late int _previousTokens;
  late int _previousCacheRead;

  @override
  void initState() {
    super.initState();
    _previousTokens = widget.totalTokens;
    _previousCacheRead = widget.cacheReadTokens ?? 0;
  }

  @override
  void didUpdateWidget(covariant _TokenDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalTokens != widget.totalTokens) {
      _previousTokens = oldWidget.totalTokens;
    }
    if (oldWidget.cacheReadTokens != widget.cacheReadTokens) {
      _previousCacheRead = oldWidget.cacheReadTokens ?? 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurfaceVariant,
    );
    final cacheStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: Colors.green.shade600,
    );
    final hasCache = (widget.cacheReadTokens ?? 0) > 0;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasCache
            ? Colors.green.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest,
        borderRadius: _borderRadius999,
        border: Border.all(
          color: hasCache
              ? Colors.green.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasCache ? Icons.bolt_rounded : Icons.confirmation_number_rounded,
            size: 14,
            color: hasCache ? Colors.green.shade600 : colorScheme.primary,
          ),
          const SizedBox(width: 6),
          if (hasCache) ...[
            TweenAnimationBuilder<int>(
              tween: IntTween(
                begin: _previousCacheRead,
                end: widget.cacheReadTokens ?? 0,
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Text('$value', style: cacheStyle);
              },
            ),
            const SizedBox(width: 4),
            Text('Cached', style: cacheStyle),
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: colorScheme.outlineVariant,
            ),
          ],
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: _previousTokens, end: widget.totalTokens),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Text('$value', style: numberStyle);
            },
          ),
          const SizedBox(width: 6),
          Text(
            hasCache
                ? _localizedText(context, zh: '总计', en: 'Total')
                : _localizedText(context, zh: 'Token', en: 'Token'),
            style: labelStyle,
          ),
        ],
      ),
    );
  }
}

class _ThreadTemplateDialog extends StatelessWidget {
  const _ThreadTemplateDialog({required this.templates});

  final List<AiThreadTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.threadTemplateDialogTitle),
      content: SizedBox(
        width: 1080,
        height: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.threadTemplateDialogBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: templates
                    .map(
                      (template) => _ThreadTemplateCard(
                        template: template,
                        onTap: () => Navigator.of(context).pop(template.id),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
      ],
    );
  }
}

class _ThreadTemplateCard extends StatefulWidget {
  const _ThreadTemplateCard({required this.template, required this.onTap});

  final AiThreadTemplate template;
  final VoidCallback onTap;

  @override
  State<_ThreadTemplateCard> createState() => _ThreadTemplateCardState();
}

class _ThreadTemplateCardState extends State<_ThreadTemplateCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: 280,
      height: 300,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: _borderRadius18,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.template.iconData,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.template.name, style: theme.textTheme.titleMedium),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Text(
                        widget.template.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'v${widget.template.internalVersion}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

Widget _buildHardnessConfigSection(BuildContext context, AiSession session) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  final sectionTitle = isZh
      ? 'Hardness Engineering 配置'
      : 'Hardness Engineering Config';
  final rawConfig = session.metadata['hardness_config'];

  final Map<String, Object?> configMap;
  if (rawConfig is Map<String, Object?>) {
    configMap = rawConfig;
  } else if (rawConfig is Map) {
    configMap = Map<String, Object?>.from(rawConfig);
  } else {
    return _MetadataSection(
      title: sectionTitle,
      children: [
        Text(
          isZh
              ? '配置数据尚未写入会话元数据（该会话可能创建于功能推出之前）。'
              : 'Configuration data has not been stored in session metadata (session may predate this feature).',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  HardnessRoleConfig? parseRole(String key) {
    final raw = configMap[key];
    if (raw is Map<String, Object?>) return HardnessRoleConfig.fromJson(raw);
    if (raw is Map) {
      return HardnessRoleConfig.fromJson(Map<String, Object?>.from(raw));
    }
    return null;
  }

  final task = '${configMap['task'] ?? ''}'.trim();
  final workingDirectory = '${configMap['working_directory'] ?? ''}'.trim();
  final persistenceDirectory = '${configMap['persistence_directory'] ?? ''}'
      .trim();
  final firstRunRaw = configMap['first_run'];

  final roleConfigs = <(String, HardnessRoleConfig?)>[
    (isZh ? '探档者 (Profiler)' : 'Profiler', parseRole('profiler')),
    (isZh ? '调查者 (Reader)' : 'Reader', parseRole('reader')),
    (isZh ? '规划者 (Planner)' : 'Planner', parseRole('planner')),
    (isZh ? '实施者 (Implementer)' : 'Implementer', parseRole('implementer')),
    (isZh ? '验收者 (Reviewer)' : 'Reviewer', parseRole('reviewer')),
  ];

  return _MetadataSection(
    title: sectionTitle,
    children: [
      if (task.isNotEmpty)
        _MetadataEntryRow(label: isZh ? '任务描述' : 'Task', value: task),
      _MetadataEntryRow(
        label: isZh ? '工作目录' : 'Working Directory',
        value: workingDirectory.isEmpty ? '-' : workingDirectory,
      ),
      _MetadataEntryRow(
        label: isZh ? '持久化目录' : 'Persistence Directory',
        value: persistenceDirectory.isEmpty ? '-' : persistenceDirectory,
      ),
      if (firstRunRaw != null)
        _MetadataEntryRow(
          label: isZh ? '首次运行' : 'First Run',
          value: firstRunRaw == true
              ? (isZh ? '是（含探档阶段）' : 'Yes (profiler phase included)')
              : (isZh ? '否（增量运行）' : 'No (incremental run)'),
        ),
      const SizedBox(height: 12),
      Text(
        isZh ? '角色配置' : 'Role Configs',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 10),
      for (final entry in roleConfigs)
        _MetadataEntryRow(
          label: entry.$1,
          value: () {
            final rc = entry.$2;
            if (rc == null || !rc.isConfigured) {
              return isZh ? '未配置' : 'Not configured';
            }
            return '${rc.cliName} · ${describeHardnessCliModel(findHardnessCliByName(rc.cliName), rc.modelId, isZh: isZh)}';
          }(),
        ),
    ],
  );
}

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}

Future<String?> _showEditQueuedMessageDialog(
  BuildContext context,
  String currentText,
) async {
  final controller = TextEditingController(text: currentText);
  final languageCode = Localizations.localeOf(context).languageCode;
  final isZh = languageCode.startsWith('zh');
  try {
    return await showAnimatedDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isZh ? '编辑等待消息' : 'Edit Queued Message'),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 8,
              minLines: 3,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: isZh ? '输入消息内容…' : 'Enter message…',
              ),
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(isZh ? '取消' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: Text(isZh ? '保存' : 'Save'),
            ),
          ],
        );
      },
    );
  } finally {
    _disposeTextEditingControllerAfterCurrentFrame(controller);
  }
}

String _localizedMetadataField(BuildContext context, String field) {
  return switch (field) {
    'session_id' => _localizedText(context, zh: '会话 ID', en: 'Session ID'),
    'template' => _localizedText(context, zh: '模板', en: 'Template'),
    'created_at' => _localizedText(context, zh: '创建时间', en: 'Created At'),
    'updated_at' => _localizedText(context, zh: '更新时间', en: 'Updated At'),
    'last_model' => _localizedText(context, zh: '最近模型', en: 'Last Model'),
    'compression_checkpoint' => _localizedText(
      context,
      zh: '压缩检查点',
      en: 'Compression Checkpoint',
    ),
    'latest_compression_at' => _localizedText(
      context,
      zh: '最近压缩时间',
      en: 'Latest Compression At',
    ),
    'total_input_characters' => _localizedText(
      context,
      zh: '输入字符总数',
      en: 'Total Input Characters',
    ),
    'total_output_characters' => _localizedText(
      context,
      zh: '输出字符总数',
      en: 'Total Output Characters',
    ),
    'total_prompt_characters' => _localizedText(
      context,
      zh: 'Prompt 字符总数',
      en: 'Total Prompt Characters',
    ),
    'last_prompt_system_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 系统消息数',
      en: 'Last Prompt System Message Count',
    ),
    'last_prompt_history_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 历史消息数',
      en: 'Last Prompt History Message Count',
    ),
    'locale_tag' => _localizedText(context, zh: '语言区域', en: 'Locale Tag'),
    'platform' => _localizedText(context, zh: '平台', en: 'Platform'),
    'app_version' => _localizedText(context, zh: '应用版本', en: 'App Version'),
    'compression_threshold_chars' => _localizedText(
      context,
      zh: '压缩阈值字符数',
      en: 'Compression Threshold Characters',
    ),
    'single_round_tool_call_limit' => _localizedText(
      context,
      zh: '单轮工具调用上限',
      en: 'Per-Response Tool Call Limit',
    ),
    'sequential_tool_round_limit' => _localizedText(
      context,
      zh: '连续工具轮次上限',
      en: 'Sequential Tool Round Limit',
    ),
    'application_directory' => _localizedText(
      context,
      zh: '应用目录',
      en: 'Application Directory',
    ),
    'home_directory' => _localizedText(
      context,
      zh: '主目录',
      en: 'Home Directory',
    ),
    'settings_file' => _localizedText(context, zh: '设置文件', en: 'Settings File'),
    'skills_storage' => _localizedText(
      context,
      zh: '技能目录',
      en: 'Skills Storage',
    ),
    'mcp_servers_file' => _localizedText(
      context,
      zh: 'MCP 文件',
      en: 'MCP Servers File',
    ),
    'user_memory_file' => _localizedText(
      context,
      zh: '记忆文件',
      en: 'User Memory File',
    ),
    'sessions_directory' => _localizedText(
      context,
      zh: '会话目录',
      en: 'Sessions Directory',
    ),
    _ => field,
  };
}

// ── Hardness Engineering annotation parsing ───────────────────────────────────

final RegExp _heAgentPattern = RegExp(r'\[HE_AGENT:(\w+)\|([^\]]+)\]');
final RegExp _hePhasePattern = RegExp(r'\[HE_PHASE:(\w+)\]');

class _HeAnnotation {
  const _HeAnnotation({
    required this.agentRole,
    required this.agentId,
    required this.phase,
    required this.strippedContent,
  });

  final String? agentRole;
  final String? agentId;
  final String? phase;
  final String strippedContent;

  bool get hasAnnotations => agentRole != null || phase != null;
}

_HeAnnotation? _parseHeAnnotation(String content) {
  final agentMatch = _heAgentPattern.firstMatch(content);
  final phaseMatch = _hePhasePattern.firstMatch(content);
  if (agentMatch == null && phaseMatch == null) return null;
  final stripped = content
      .replaceAll(_heAgentPattern, '')
      .replaceAll(_hePhasePattern, '')
      .replaceAll(RegExp(r'^\s+'), '')
      .trim();
  return _HeAnnotation(
    agentRole: agentMatch?.group(1),
    agentId: agentMatch?.group(2),
    phase: phaseMatch?.group(1),
    strippedContent: stripped,
  );
}

// ── Hardness Engineering capsule row widget ───────────────────────────────────

class _HardnessAnnotationCapsuleRow extends StatelessWidget {
  const _HardnessAnnotationCapsuleRow({required this.annotation});

  final _HeAnnotation annotation;

  static const Map<String, String> _roleDisplayZh = {
    'reader': '调查者',
    'planner': '规划者',
    'implementer': '实施者',
    'reviewer': '验收者',
  };

  static const Map<String, String> _roleDisplayEn = {
    'reader': 'Reader',
    'planner': 'Planner',
    'implementer': 'Implementer',
    'reviewer': 'Reviewer',
  };

  static const Map<String, String> _phaseDisplayZh = {
    'meta_collection': '元数据采集',
    'reading': '调查',
    'planning': '规划',
    'implementing': '实施',
    'reviewing': '验收',
  };

  static const Map<String, String> _phaseDisplayEn = {
    'meta_collection': 'Meta Collection',
    'reading': 'Reading',
    'planning': 'Planning',
    'implementing': 'Implementing',
    'reviewing': 'Reviewing',
  };

  static const Map<String, IconData> _phaseIcons = {
    'meta_collection': Icons.manage_search_rounded,
    'reading': Icons.menu_book_rounded,
    'planning': Icons.route_rounded,
    'implementing': Icons.code_rounded,
    'reviewing': Icons.fact_check_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final capsules = <Widget>[];

    if (annotation.agentRole != null) {
      final roleName = isZh
          ? (_roleDisplayZh[annotation.agentRole] ?? annotation.agentRole!)
          : (_roleDisplayEn[annotation.agentRole] ?? annotation.agentRole!);
      final label = annotation.agentId != null
          ? '$roleName · ${annotation.agentId}'
          : roleName;
      capsules.add(
        _Capsule(
          icon: Icons.person_pin_rounded,
          label: label,
          color: colorScheme.secondary,
          onColor: colorScheme.onSecondary,
        ),
      );
    }

    if (annotation.phase != null) {
      final phaseName = isZh
          ? (_phaseDisplayZh[annotation.phase] ?? annotation.phase!)
          : (_phaseDisplayEn[annotation.phase] ?? annotation.phase!);
      final icon = _phaseIcons[annotation.phase] ?? Icons.timelapse_rounded;
      capsules.add(
        _Capsule(
          icon: icon,
          label: phaseName,
          color: colorScheme.tertiary,
          onColor: colorScheme.onTertiary,
        ),
      );
    }

    if (capsules.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: capsules),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

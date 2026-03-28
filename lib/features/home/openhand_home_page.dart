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
import 'package:xml/xml.dart' as xml;
import 'package:yaml/yaml.dart';

import '../../app/model/app_info.dart';
import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/theme/openhand_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_attachment.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session.dart';
import '../ai/model/ai_session_message.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/model/ai_thread_template.dart';
import '../ai/service/ai_bash_tool_service.dart';
import '../ai/service/ai_git_snapshot_service.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_workspace_instruction_service.dart';
import '../memory/memory_controller.dart';
import '../memory/memory_view.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_view.dart';
import '../settings/settings_view.dart';
import '../skills/skills_controller.dart';
import '../skills/skills_view.dart';
import 'message_path_linking.dart';
import 'slash_command_parser.dart';
import 'tool_call_argument_parser.dart';

enum AppSection { workspace, automations, skills, memory, mcp, settings }

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
const int _transcriptInitialWindowSize = 80;
const int _transcriptWindowIncrement = 80;
const int _transcriptWindowingThreshold = 120;
const Duration _transcriptLoadingPlaceholderDelay = Duration(milliseconds: 48);
const Duration _transcriptMessageDeleteAnimationDuration = Duration(
  milliseconds: 220,
);
const Duration _sessionTitleRevealAnimationDuration = Duration(
  milliseconds: 420,
);
const Duration _planTimelineRevealAnimationDuration = Duration(
  milliseconds: 260,
);
final RegExp _markdownStructuralPattern = RegExp(
  r'[`*_#>\[\]|~]|(^|\n)\s{0,3}([-+*]|\d+\.)\s|(^|\n)\s{0,3}>|(^|\n)\s{0,3}#{1,6}\s|(^|\n)\s*([-*_]\s*){3,}(?=\n|$)|(^|\n)\s*\|.+\||!?\[[^\]]*\]\([^)]+\)|(^|\n)\s{4,}\S',
  multiLine: true,
);

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  final FocusNode _globalShortcutFocusNode = FocusNode();
  final FocusNode _composerFocusNode = FocusNode();
  final AiWorkspaceInstructionService _workspaceInstructionService =
      AiWorkspaceInstructionService();
  final AiGitSnapshotService _gitSnapshotService = AiGitSnapshotService();

  AppSection _selectedSection = AppSection.workspace;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  String? _submittingSessionId;
  bool _shouldAutoFollowMessages = true;
  bool _pendingForcedScrollToBottom = false;
  bool _queuedForcedScrollToBottom = false;
  bool _scrollToBottomCallbackQueued = false;
  bool _pendingAnimatedScrollToBottom = false;
  bool _programmaticAutoFollowScrollInProgress = false;
  int _pendingScrollToBottomSettlePasses = 0;
  String? _lastAutoScrollSignature;
  List<_ComposerAttachmentDraft> _pendingAttachments =
      const <_ComposerAttachmentDraft>[];
  final Map<String, _ComposerDraftState> _composerDraftsBySessionId =
      <String, _ComposerDraftState>{};
  final Map<String, bool> _collapsedPlanTimelinesBySessionId = <String, bool>{};
  AiSessionController? _observedSessionController;
  AiSessionMode _detachedComposerMode = AiSessionMode.chat;
  String? _activeComposerSessionId;
  String? _activeTranscriptSessionId;
  String? _preparingTranscriptSessionId;
  int _transcriptPreparationGeneration = 0;

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
    _composerFocusNode.onKeyEvent = _handleComposerFocusNodeKeyEvent;
    _messageScrollController.addListener(_handleMessageScroll);
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
    _observedSessionController?.removeListener(_handleSessionControllerChanged);
    _messageScrollController.removeListener(_handleMessageScroll);
    _globalShortcutFocusNode.dispose();
    _composerFocusNode.dispose();
    _composerController.dispose();
    _messageScrollController.dispose();
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
    _syncComposerDraftForSession(sessionController?.currentSessionId);
    _syncTranscriptPreparation(sessionController?.currentSession);
  }

  bool _shouldPrepareTranscript(AiSession? session) {
    return session != null &&
        session.messages.length >= _transcriptWindowingThreshold;
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

  bool _shouldScheduleAutoFollow({bool consumePendingRequest = false}) {
    final shouldForce = consumePendingRequest
        ? _consumePendingAutoFollowRequest()
        : _pendingForcedScrollToBottom;
    if (!_autoFollowEnabled && !shouldForce) {
      return false;
    }
    if (!_shouldAutoFollowMessages && !shouldForce) {
      return false;
    }
    return true;
  }

  void _scheduleAutoFollowIfNeeded({
    bool consumePendingRequest = false,
    bool animated = true,
  }) {
    if (!_shouldScheduleAutoFollow(
      consumePendingRequest: consumePendingRequest,
    )) {
      return;
    }
    _scheduleScrollToBottom(force: true, animated: animated);
  }

  void _handleMessageScroll() {
    final nextValue = _isNearBottom();
    if (!nextValue) {
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
    final explicitUserScroll =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle);
    if (_programmaticAutoFollowScrollInProgress) {
      if (!explicitUserScroll) {
        return false;
      }
      _programmaticAutoFollowScrollInProgress = false;
    }
    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final isNearBottom = distanceToBottom <= _autoFollowDistanceThreshold;
    final userScrolledAwayFromBottom = !isNearBottom && explicitUserScroll;
    if (userScrolledAwayFromBottom) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
      return false;
    }
    if (isNearBottom) {
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
        _selectedSection != AppSection.workspace ||
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
      if (!composerShortcutAllowed) {
        return false;
      }
    }
    unawaited(_performShortcutAction(shortcutAction));
    return true;
  }

  KeyEventResult _handleGlobalShortcutFocusEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    return _handleGlobalShortcutKeyEvent(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
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
    final sendShortcutKeyIds = normalizeShortcutKeyIds(
      bindings[OpenHandShortcutAction.sendMessage] ?? const <int>[],
    );
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    if (pressedKeyIds.length != sendShortcutKeyIds.length ||
        !pressedKeyIds.containsAll(sendShortcutKeyIds)) {
      return KeyEventResult.ignored;
    }
    final sessionController = context.read<AiSessionController>();
    final sendPhase = _effectiveSendPhase(sessionController);
    if (_canStopCurrentSessionResponse(sessionController)) {
      unawaited(_stopResponding());
      return KeyEventResult.handled;
    }
    if (sendPhase == AiSendPhase.idle) {
      unawaited(_sendMessage());
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  bool _isEditableTextFocused(BuildContext? focusContext) {
    if (focusContext == null) {
      return false;
    }
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
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
    switch (action) {
      case OpenHandShortcutAction.sendMessage:
        final sessionController = context.read<AiSessionController>();
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
    final models = settingsController.aiModels;
    if (models.isEmpty) {
      return;
    }
    final currentModelId = settingsController.selectedAiModelId;
    final currentIndex = models.indexWhere((item) => item.id == currentModelId);
    final baseIndex = currentIndex >= 0 ? currentIndex : 0;
    final nextIndex = (baseIndex + delta + models.length) % models.length;
    unawaited(settingsController.updateSelectedAiModel(models[nextIndex].id));
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
    await sessionController.selectSession(sessionId);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _clearPendingAutoFollowState();
      _armAutoFollowToBottom();
    });
    _scheduleScrollToBottom(force: true, animated: false);
  }

  Future<String?> _showThreadTemplateDialog() async {
    return showDialog<String>(
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
    return _createSession(
      templateId: templateId,
      runtimeContext: runtimeContext,
    );
  }

  Future<AiSessionRuntimeContext> _buildRuntimeContext() async {
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    final skillsController = context.read<SkillsController>();
    final mcpController = context.read<McpController>();
    final appInfo = context.read<AppInfo>();
    final workingDirectory = OpenHandPaths.applicationDirectoryPath();
    final gitSnapshot = await _gitSnapshotService.loadSnapshot(
      workingDirectory: workingDirectory,
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
      workingDirectory: workingDirectory,
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

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    final prompt = _composerController.text.trim();
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
      runtimeContext = await _buildRuntimeContext();
      if (!mounted) {
        return;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
        initialMode: _detachedComposerMode,
      );
      if (!mounted || !created || sessionController.currentSession == null) {
        return;
      }
    }
    final initialSession = sessionController.currentSession;
    final targetSessionId = sessionController.currentSessionId;
    if (targetSessionId == null || _submittingSessionId == targetSessionId) {
      return;
    }
    final initialUserMessageCount = _visibleUserMessageCount(initialSession);
    final editingMessageIdBeforeSend = sessionController.editingMessageId;

    _storeComposerDraftForSession(
      targetSessionId,
      text: prompt,
      attachments: pendingAttachments,
    );

    _replaceComposerText('');
    setState(() {
      _submittingSessionId = targetSessionId;
      _pendingAttachments = const <_ComposerAttachmentDraft>[];
      _armAutoFollowToBottom();
    });
    _scheduleScrollToBottom(force: true, animated: false);
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
        attachmentFilePaths: pendingAttachments
            .map((item) => item.filePath)
            .toList(growable: false),
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation:
            settingsController.aiWriteCommandConfirmationEnabled,
        confirmWriteCommand: _confirmWriteCommand,
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
      } else if (_submittingSessionId == targetSessionId) {
        _submittingSessionId = null;
      }
    }
  }

  void _replaceComposerText(String value) {
    _composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
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
    if (!force && !_shouldAutoFollowMessages) {
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
        animated ? 4 : 3,
      );
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
      final shouldForce = _queuedForcedScrollToBottom;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      _queuedForcedScrollToBottom = false;
      _pendingAnimatedScrollToBottom = false;
      if (!shouldForce && (!_autoFollowEnabled || !_shouldAutoFollowMessages)) {
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
              .whenComplete(clearProgrammaticScrollFlag),
        );
      } else if (distance >= 1) {
        _programmaticAutoFollowScrollInProgress = true;
        _messageScrollController.jumpTo(targetOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          clearProgrammaticScrollFlag();
        });
      }
      if (_pendingScrollToBottomSettlePasses <= 0) {
        return;
      }
      _pendingScrollToBottomSettlePasses -= 1;
      _scheduleScrollToBottom(force: false, allowSettlePasses: false);
    });
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
    _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
  }

  void _handleComposerLayoutChanged() {
    _scheduleAutoFollowIfNeeded();
  }

  void _handleTranscriptLayoutChanged() {
    _scheduleAutoFollowIfNeeded();
  }

  void _handleRevealOlderMessages() {
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
      '${_toolExecutionStdout(lastMessage).length}',
      '${_toolExecutionStderr(lastMessage).length}',
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

  Future<bool> _confirmWriteCommand(BashCommandApprovalRequest request) async {
    final settingsController = context.read<SettingsController>();
    for (final rule in settingsController.aiAllowCommandRules) {
      if (rule.matches(request.command)) {
        return true;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _WriteCommandConfirmationDialog(request: request),
    );
    return confirmed == true;
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
    return showDialog<void>(
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
    return showDialog<void>(
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
    final submitted = await showDialog<String>(
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
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(titleController.text.trim()),
              label: AppLocalizations.of(context)!.commonSave,
            ),
          ],
        );
      },
    );
    titleController.dispose();
    if (!mounted || submitted == null || submitted.trim().isEmpty) {
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
    final confirmed = await showDialog<bool>(
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

  Future<void> _editMessage(AiSessionMessage message) async {
    final content = await context
        .read<AiSessionController>()
        .beginEditingMessage(message.id);
    if (!mounted || content == null) {
      return;
    }
    _replaceComposerText(content);
    setState(() {
      _selectedSection = AppSection.workspace;
      _composerCollapsed = false;
      _pendingAttachments = const <_ComposerAttachmentDraft>[];
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
    final confirmed = await showDialog<bool>(
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
    final confirmed = await showDialog<bool>(
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
      onKeyEvent: _handleGlobalShortcutFocusEvent,
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

                return Row(
                  children: [
                    SizedBox(
                      width: _desktopNavigationWidth,
                      child: navigationPane,
                    ),
                    const SizedBox(width: _contentPaneGap),
                    Expanded(child: contentPane),
                  ],
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
    final sessionController = context.watch<AiSessionController>();
    final currentSession = sessionController.currentSession;
    final transcriptPreparing = _isPreparingTranscriptForSession(
      currentSession,
    );
    if (_selectedSection == AppSection.workspace && !transcriptPreparing) {
      _maybeAutoFollowSession(currentSession);
    }

    return switch (_selectedSection) {
      AppSection.workspace => _WorkspaceView(
        draftController: _composerController,
        messageScrollController: _messageScrollController,
        onMessageScrollNotification: _handleMessageScrollNotification,
        currentSession: currentSession,
        transcriptPreparing: transcriptPreparing,
        selectedModel: settingsController.selectedAiModel,
        availableModels: settingsController.aiModels,
        onModelSelected: (modelId) {
          settingsController.updateSelectedAiModel(modelId);
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
        pendingAttachments: _pendingAttachments,
        attachmentsEnabled: _selectedModelSupportsAttachments(
          settingsController.selectedAiModel,
        ),
        onPickAttachments: _pickComposerAttachments,
        onRemoveAttachment: _removePendingAttachment,
        onSend: _sendMessage,
        onStop: _stopResponding,
        onCreateThreadRequested: _createSessionFromDialog,
        editingMessageId: sessionController.editingMessageId,
        onCancelEditing: _cancelEditingMessage,
        onEditMessage: _editMessage,
        onCopyMessage: _copyMessage,
        onDeleteMessage: _deleteMessage,
        onDeleteMessageFromHere: _deleteMessageFromHere,
        onDismissError: _dismissSessionError,
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
    };
  }
}

class _ComposerDraftState {
  const _ComposerDraftState({required this.text, required this.attachments});

  final String text;
  final List<_ComposerAttachmentDraft> attachments;
}

extension on AppSection {
  int? get drawerIndex {
    return switch (this) {
      AppSection.workspace => null,
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

class _NavigationPane extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final drawerTheme = theme.copyWith(
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: drawerTheme,
        child: NavigationDrawer(
          selectedIndex: selectedSection.drawerIndex,
          onDestinationSelected: (index) {
            onSectionSelected(_sectionFromDrawerIndex(index));
          },
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: onCreateThreadRequested,
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
            if (sessions.isEmpty)
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
                  children: sessions
                      .map(
                        (session) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ThreadTile(
                            session: session,
                            sendPhase:
                                sessionSendPhases[session.id] ??
                                AiSendPhase.idle,
                            isSelected: currentSessionId == session.id,
                            onTap: () => onSessionSelected(session.id),
                            onRename: () => onRenameSession(session),
                            onDelete: () => onDeleteSession(session),
                          ),
                        ),
                      )
                      .toList(growable: false),
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

  @override
  void dispose() {
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
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
                        const SizedBox(height: 16),
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
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(false),
                    label: AppLocalizations.of(context)!.commonCancel,
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: () => Navigator.of(context).pop(true),
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
    );
  }
}

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.currentSession,
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
    required this.onSend,
    required this.onStop,
    required this.onCreateThreadRequested,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.onEditMessage,
    required this.onCopyMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessageFromHere,
    required this.onDismissError,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final bool Function(ScrollNotification notification)
  onMessageScrollNotification;
  final AiSession? currentSession;
  final bool transcriptPreparing;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
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
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final Future<void> Function() onCreateThreadRequested;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessage;
  final Future<bool> Function(AiSessionMessage message) onDeleteMessageFromHere;
  final Future<void> Function(AiSessionErrorRecord error) onDismissError;

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
                  ? _WorkspaceEmptyState(
                      key: const ValueKey<String>('no-session'),
                    )
                  : currentSession!.messages.isEmpty
                  ? _WorkspaceEmptyState(
                      key: ValueKey<String>(currentSession!.id),
                      session: currentSession,
                    )
                  : transcriptPreparing
                  ? _SessionTranscriptLoadingPlaceholder(
                      key: ValueKey<String>(
                        'session-transcript-loading-${currentSession!.id}',
                      ),
                      session: currentSession!,
                      sendPhase: sendPhase,
                      planTimelineCollapsed: planTimelineCollapsed,
                      onPlanTimelineCollapsedChanged:
                          onPlanTimelineCollapsedChanged,
                    )
                  : _SessionTranscript(
                      key: ValueKey<String>('messages-${currentSession!.id}'),
                      controller: messageScrollController,
                      onScrollNotification: onMessageScrollNotification,
                      session: currentSession!,
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
                    ),
            ),
            const SizedBox(height: 16),
            NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (notification) {
                onComposerLayoutChanged();
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: _ComposerPanel(
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
                  onSend: onSend,
                  onStop: onStop,
                  editingMessageId: editingMessageId,
                  onCancelEditing: onCancelEditing,
                ),
              ),
            ),
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
    required this.sendPhase,
    required this.planTimelineCollapsed,
    required this.onPlanTimelineCollapsedChanged,
  });

  final AiSession session;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mutedTextColor = colorScheme.onSurfaceVariant;
    final cardColor = colorScheme.surfaceContainerHigh;
    final accentColor = colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          sendPhase: sendPhase,
          planTimelineCollapsed: planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: onPlanTimelineCollapsedChanged,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                  child: Column(
                    key: const ValueKey<String>('session-transcript-loading'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _localizedText(
                                context,
                                zh: '正在载入会话消息...',
                                en: 'Loading conversation messages...',
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _localizedText(
                          context,
                          zh: '正在准备较长的聊天记录并预热首屏渲染，请稍候。',
                          en: 'Preparing a longer transcript and warming up the first render.',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: mutedTextColor,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _TranscriptPlaceholderBubble(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.78,
                        color: cardColor,
                      ),
                      const SizedBox(height: 14),
                      _TranscriptPlaceholderBubble(
                        alignment: Alignment.centerRight,
                        widthFactor: 0.58,
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.82,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _TranscriptPlaceholderBubble(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.86,
                        color: cardColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptPlaceholderBubble extends StatelessWidget {
  const _TranscriptPlaceholderBubble({
    required this.alignment,
    required this.widthFactor,
    required this.color,
  });

  final Alignment alignment;
  final double widthFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TranscriptPlaceholderLine(widthFactor: 0.88),
                const SizedBox(height: 10),
                _TranscriptPlaceholderLine(widthFactor: 0.72),
                const SizedBox(height: 10),
                _TranscriptPlaceholderLine(widthFactor: 0.54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptPlaceholderLine extends StatelessWidget {
  const _TranscriptPlaceholderLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const SizedBox(height: 12),
      ),
    );
  }
}

class _TranscriptRenderEntry {
  const _TranscriptRenderEntry({required this.message, this.exiting = false});

  final AiSessionMessage message;
  final bool exiting;

  String get id => message.id;

  _TranscriptRenderEntry copyWith({AiSessionMessage? message, bool? exiting}) {
    return _TranscriptRenderEntry(
      message: message ?? this.message,
      exiting: exiting ?? this.exiting,
    );
  }
}

class _SessionTranscript extends StatefulWidget {
  const _SessionTranscript({
    super.key,
    required this.controller,
    required this.onScrollNotification,
    required this.session,
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
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
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

  @override
  void initState() {
    super.initState();
    _syncWindowStartIndex(forceReset: true);
    _replaceRenderEntries(_visibleMessagesForWindow());
    _syncVisibleError();
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

  void _replaceRenderEntries(List<AiSessionMessage> visibleMessages) {
    _renderEntries = <_TranscriptRenderEntry>[
      for (final message in visibleMessages)
        _TranscriptRenderEntry(message: message),
    ];
  }

  void _syncRenderEntries({bool forceReset = false}) {
    final visibleMessages = _visibleMessagesForWindow();
    if (forceReset || _renderEntries.isEmpty) {
      _replaceRenderEntries(visibleMessages);
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
      _replaceRenderEntries(_visibleMessagesForWindow());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(
          session: session,
          sendPhase: widget.sendPhase,
          planTimelineCollapsed: widget.planTimelineCollapsed,
          onPlanTimelineCollapsedChanged: widget.onPlanTimelineCollapsedChanged,
        ),
        const SizedBox(height: 14),
        if (session.latestCompressionAt != null) ...[
          _CompressionNoticeCard(session: session),
          const SizedBox(height: 14),
        ],
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: widget.onScrollNotification,
            child: ListView.builder(
              key: const ValueKey<String>('session-transcript-list'),
              controller: widget.controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount:
                  _renderEntries.length + (hiddenMessageCount > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (hiddenMessageCount > 0 && index == 0) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: _renderEntries.isEmpty ? 0 : 14,
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
                final messageIndex = hiddenMessageCount > 0 ? index - 1 : index;
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
        if (userVisibleError != null) ...[
          const SizedBox(height: 12),
          _SessionErrorBanner(
            error: userVisibleError,
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
          ),
        ],
      ],
    );
  }
}

class _TranscriptAnimatedMessageEntry extends StatelessWidget {
  const _TranscriptAnimatedMessageEntry({
    super.key,
    required this.exiting,
    required this.bottomSpacing,
    required this.onExitCompleted,
    required this.child,
  });

  final bool exiting;
  final double bottomSpacing;
  final VoidCallback onExitCompleted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = exiting
        ? _transcriptMessageDeleteAnimationDuration
        : Duration.zero;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: exiting ? 0 : 1),
      duration: duration,
      curve: Curves.easeInOutCubic,
      onEnd: exiting ? onExitCompleted : null,
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
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomSpacing),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
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
    this.sendPhase = AiSendPhase.idle,
    this.planTimelineCollapsed = false,
    this.onPlanTimelineCollapsedChanged,
  });

  final AiSession session;
  final AiSendPhase sendPhase;
  final bool planTimelineCollapsed;
  final ValueChanged<bool>? onPlanTimelineCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final planTimeline = _buildPlanTimelineData(context, session, sendPhase);
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
                                _showSessionMetadataDialog(context, session);
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
              _TokenDial(totalTokens: session.statistics.totalTokens ?? 0),
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
                      'plan-timeline-visible-${planTimeline.awaitingApproval}-${planTimeline.steps.length}',
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
        borderRadius: BorderRadius.circular(999),
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
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(
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
    required this.steps,
  });

  final bool awaitingApproval;
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
        : data.hasFailedStep
        ? colorScheme.error
        : data.isComplete
        ? colorScheme.primary
        : colorScheme.tertiary;
    final headline = data.awaitingApproval
        ? _localizedText(context, zh: '计划待确认', en: 'Plan Awaiting Approval')
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
        borderRadius: BorderRadius.circular(18),
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
                      : '${data.completedStepCount}/${data.steps.length}',
                  key: ValueKey<String>(
                    '${data.awaitingApproval}-${data.completedStepCount}-${data.steps.length}',
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
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(color.withValues(alpha: 0.08)),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
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
            borderRadius: BorderRadius.circular(999),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                borderRadius: BorderRadius.circular(999),
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
  AiSendPhase sendPhase,
) {
  final todoSteps = <_PlanTimelineStep>[];
  var hasInProgressStep = false;
  var hasFailedStep = false;
  final reflectRunningStepFailure = _shouldReflectCurrentPlanStepFailure(
    session,
  );
  for (final item in session.todoItems) {
    final label = item.content.trim();
    if (label.isEmpty) {
      continue;
    }
    final state = switch (item.status.trim().toLowerCase()) {
      'completed' => _PlanTimelineStepState.completed,
      'in_progress' when reflectRunningStepFailure =>
        _PlanTimelineStepState.failed,
      'in_progress' => _PlanTimelineStepState.current,
      'failed' || 'blocked' || 'cancelled' => _PlanTimelineStepState.failed,
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
  if (todoSteps.isNotEmpty) {
    if (!hasInProgressStep && !hasFailedStep) {
      final firstPendingIndex = todoSteps.indexWhere(
        (item) => item.state == _PlanTimelineStepState.pending,
      );
      if (firstPendingIndex >= 0) {
        todoSteps[firstPendingIndex] = _PlanTimelineStep(
          id: todoSteps[firstPendingIndex].id,
          label: todoSteps[firstPendingIndex].label,
          state: _PlanTimelineStepState.current,
        );
      } else if (_shouldReviewCompletedPlan(session)) {
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
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      steps: todoSteps,
    );
  }
  final pendingPlanSteps = _planTimelineStepsFromPendingPlan(
    session.pendingPlan,
  );
  if (session.awaitingPlanApproval || pendingPlanSteps.isNotEmpty) {
    return _PlanTimelineData(
      awaitingApproval: session.awaitingPlanApproval,
      steps: <_PlanTimelineStep>[
        _PlanTimelineStep(
          id: 'plan-approval',
          label: _localizedText(context, zh: '确认执行计划', en: 'Approve Plan'),
          state: session.awaitingPlanApproval
              ? _PlanTimelineStepState.current
              : _PlanTimelineStepState.completed,
        ),
        ...pendingPlanSteps.asMap().entries.map(
          (entry) => _PlanTimelineStep(
            id: 'plan-step-${entry.key}',
            label: entry.value,
            state: _PlanTimelineStepState.pending,
          ),
        ),
      ],
    );
  }
  if (session.mode == AiSessionMode.plan) {
    return _PlanTimelineData(
      awaitingApproval: false,
      steps: <_PlanTimelineStep>[
        _PlanTimelineStep(
          id: 'plan-stage-inspect',
          label: _localizedText(context, zh: '分析需求', en: 'Analyze Task'),
          state: sendPhase == AiSendPhase.idle
              ? _PlanTimelineStepState.current
              : _PlanTimelineStepState.completed,
        ),
        _PlanTimelineStep(
          id: 'plan-stage-todos',
          label: _localizedText(context, zh: '生成步骤清单', en: 'Create Todos'),
          state: sendPhase == AiSendPhase.idle
              ? _PlanTimelineStepState.pending
              : _PlanTimelineStepState.current,
        ),
        _PlanTimelineStep(
          id: 'plan-stage-approval',
          label: _localizedText(context, zh: '确认执行计划', en: 'Approve Plan'),
          state: _PlanTimelineStepState.pending,
        ),
      ],
    );
  }
  return null;
}

bool _shouldReflectCurrentPlanStepFailure(AiSession session) {
  for (var index = session.messages.length - 1; index >= 0; index -= 1) {
    final message = session.messages[index];
    if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
      continue;
    }
    final status = _toolExecutionStatus(message);
    if (status.isEmpty || status == 'running') {
      continue;
    }
    return status == 'failed' ||
        status == 'cancelled' ||
        status == 'denied' ||
        status == 'rejected' ||
        status == 'timed_out' ||
        status == 'invalid_arguments';
  }
  return false;
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
      .map((line) {
        final normalizedLine = line.trim();
        if (normalizedLine.isEmpty) {
          return '';
        }
        return normalizedLine.replaceFirst(
          RegExp(r'^(?:[-*+]\s+|\d+[\.\):]\s+)'),
          '',
        );
      })
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

Future<void> _showSessionMetadataDialog(
  BuildContext context,
  AiSession session,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionMetadataDialog(session: session),
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

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statistics = session.statistics;
    final environment = session.environment;
    final lastPromptMetadata = session.lastPromptMetadata;
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
        borderRadius: BorderRadius.circular(18),
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
        borderRadius: BorderRadius.circular(999),
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
  final match = RegExp(r'limit=(\d+)').firstMatch(detail);
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
      decoration: BoxDecoration(
        color: const Color(0xFF17181C),
        borderRadius: BorderRadius.circular(18),
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

class _CompressionNoticeCard extends StatelessWidget {
  const _CompressionNoticeCard({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.summarize_rounded,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.threadCompressionNotice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
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

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpandedOverride = null;
    }
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
    final markdownStyleSheet = _MessageMarkdownThemeData.fromMessageBubble(
      theme: theme,
      backgroundColor: backgroundColor,
      textColor: textColor,
      useDarkCodeSurface: isReasoning || isToolCall,
    );
    final filePathRoots = messageFilePathRoots(
      widget.sessionEnvironment,
      workingDirectory: _toolExecutionWorkingDirectory(message),
    );
    final filePathParseKey = filePathRoots.join('|');
    final markdownBuilders = <String, MarkdownElementBuilder>{
      'pre': _HighlightedCodeBlockBuilder(
        theme: theme,
        baseColor: textColor,
        darkSurface: isReasoning || isToolCall,
        selectable: widget.isSelected,
      ),
      'openhand-file': _FilePathMarkdownBuilder(
        textColor: textColor,
        onOpenPath: _openResolvedMessagePath,
      ),
    };
    final inlineSyntaxes = <md.InlineSyntax>[
      MessageFilePathSyntax(candidateRoots: filePathRoots),
    ];

    final bubbleBody = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: isToolCall
                ? Border.all(color: colorScheme.secondary, width: 1.2)
                : null,
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
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SafeMarkdownBody(
                        data: message.content.isEmpty ? ' ' : message.content,
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
  });

  final List<AiMessageAttachment> attachments;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .map(
            (attachment) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  textColor.withValues(alpha: 0.08),
                  backgroundColor,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: textColor.withValues(alpha: 0.12)),
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
          )
          .toList(growable: false),
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
        borderRadius: BorderRadius.circular(18),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
    final renderMarkdown = _containsMarkdownCodeFence(effectiveContent);
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: renderMarkdown
            ? expanded
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
                    )
            : expanded
            ? selectable
                  ? SelectableText(effectiveContent, style: textStyle)
                  : Text(effectiveContent, style: textStyle)
            : Stack(
                children: [
                  Text(
                    effectiveContent,
                    maxLines: 6,
                    overflow: TextOverflow.fade,
                    softWrap: true,
                    style: textStyle,
                  ),
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
                              fadeColor.withValues(alpha: 0),
                              fadeColor.withValues(alpha: 0.96),
                            ],
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
                        ignoring: true,
                        child: _SafeMarkdownBody(
                          data: widget.data,
                          selectable: false,
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
  const _MessageMarkdownThemeData({required this.styleSheet});

  final MarkdownStyleSheet styleSheet;

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
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        blockquoteDecoration: BoxDecoration(
          color: quoteSurface,
          borderRadius: BorderRadius.circular(18),
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
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: widget.builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        fitContent: true,
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
        onSelectionChanged: null,
        onTapText: null,
        softLineBreak: false,
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

  String _sanitizeMarkdownSource(String source) {
    return _closeUnterminatedFencedCodeBlock(
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    ).replaceAllMapped(
      RegExp(r'(^|\n)(\s*)(=+|\^+)(?=\n|$)'),
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

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
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

class _ToolOutputPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _HighlightedCodePanel(
          content: content.text,
          theme: theme,
          language: content.language,
          selectable: selectable,
          baseColor: isError
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurface,
          accentColor: isError ? theme.colorScheme.error : null,
        ),
      ],
    );
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
        borderRadius: BorderRadius.circular(999),
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
    final showResultText =
        resultText.isNotEmpty &&
        resultText != stdout.trim() &&
        resultText != stderr.trim();
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
    return true;
  }
  return false;
}

bool _shouldDefaultExpandReasoning(AiSessionMessage message) {
  return _isStreamingReasoningMessage(message);
}

bool _shouldDefaultExpandToolStatus(String status) {
  return status.isEmpty || status == 'running';
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
      RegExp(r'^<[\w!?]').hasMatch(content);
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
    if (line.startsWith('- ') || RegExp(r'^[\w./-]+:\s').hasMatch(line)) {
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
        RegExp(r'^\[[^\]]+\]$').hasMatch(line) ||
        RegExp(r'^[A-Za-z0-9_.-]+\s*=').hasMatch(line),
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
  if (RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(key)) {
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
    final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
    final displayPath = element.textContent.trim();
    final isDirectory =
        (element.attributes['entity_type'] ?? '').trim() == 'directory';
    final theme = Theme.of(context);
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: resolvedPath,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  onOpenPath(
                    context,
                    MessageResolvedPath(
                      displayPath: displayPath,
                      resolvedPath: resolvedPath,
                      isDirectory: isDirectory,
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 14,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Text(
                          displayPath,
                          overflow: TextOverflow.ellipsis,
                          style: labelStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
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
    required this.onSend,
    required this.onStop,
    required this.editingMessageId,
    required this.onCancelEditing,
  });

  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
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
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
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
              borderRadius: BorderRadius.circular(999),
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
        if (widget.pendingAttachments.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.pendingAttachments
                .map(
                  (attachment) => _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () =>
                        widget.onRemoveAttachment(attachment.filePath),
                  ),
                )
                .toList(growable: false),
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
              minLines: null,
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
        MenuAnchor(
          menuChildren: widget.availableModels
              .map(
                (model) => MenuItemButton(
                  leadingIcon: Icon(
                    model.id == widget.selectedModel?.id
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  onPressed: () => widget.onModelSelected(model.id),
                  child: Text(model.displayName),
                ),
              )
              .toList(growable: false),
          builder: (context, controller, child) {
            return SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: widget.availableModels.isEmpty
                    ? null
                    : () {
                        if (controller.isOpen) {
                          controller.close();
                          return;
                        }
                        controller.open();
                      },
                icon: const Icon(Icons.hub_outlined),
                label: Text(selectedModelLabel),
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
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: widget.attachmentsEnabled
                  ? widget.onPickAttachments
                  : null,
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
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: widget.sessionMode == AiSessionMode.plan
              ? _localizedText(
                  context,
                  zh: '当前为计划模式，点击切换到聊天模式',
                  en: 'Plan mode is active. Click to switch to chat mode.',
                )
              : _localizedText(
                  context,
                  zh: '当前为聊天模式，点击切换到计划模式',
                  en: 'Chat mode is active. Click to switch to plan mode.',
                ),
          child: SizedBox(
            height: 52,
            child: _ComposerModeButton(
              mode: widget.sessionMode,
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
        ),
        const Spacer(),
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
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: canStopSending
                ? () {
                    widget.onStop();
                  }
                : isBusy
                ? null
                : () {
                    widget.onSend();
                  },
            icon: canStopSending
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
            label: Text(sendButtonLabel),
          ),
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

class _ComposerModeButton extends StatelessWidget {
  const _ComposerModeButton({
    required this.mode,
    required this.enabled,
    required this.onPressed,
  });

  final AiSessionMode mode;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPlanMode = mode == AiSessionMode.plan;
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
                isPlanMode ? Icons.alt_route_rounded : Icons.forum_outlined,
                key: ValueKey<AiSessionMode>(mode),
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
              isPlanMode
                  ? _localizedText(context, zh: '计划模式', en: 'Plan Mode')
                  : _localizedText(context, zh: '聊天模式', en: 'Chat Mode'),
              key: ValueKey<AiSessionMode>(mode),
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

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
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
        final selected = await showMenu<String>(
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
        if (selected == 'rename') {
          onRename();
        } else if (selected == 'delete') {
          onDelete();
        }
      },
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
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
    final foregroundColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final backgroundColor = isSelected
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
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(
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
        borderRadius: BorderRadius.circular(999),
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
        .replaceFirst(RegExp(r'\n$'), '');
    final language = _extractCodeLanguage(codeElement);
    final content = rawCode.isEmpty ? ' ' : rawCode;
    return _HighlightedCodePanel(
      content: content,
      theme: _theme,
      language: language,
      selectable: _selectable,
      baseColor: _baseColor,
      forceDarkSurface: _darkSurface,
      allowAutoDetection: true,
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
  });

  final String content;
  final ThemeData theme;
  final String? language;
  final Color baseColor;
  final bool selectable;
  final bool forceDarkSurface;
  final Color? accentColor;
  final bool allowAutoDetection;

  @override
  State<_HighlightedCodePanel> createState() => _HighlightedCodePanelState();
}

class _HighlightedCodePanelState extends State<_HighlightedCodePanel> {
  TextSpan? _highlightedSpan;
  int? _highlightSignature;
  bool _copied = false;
  Timer? _copiedResetTimer;

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
    final palette = _CodeBlockPalette.fromTheme(
      widget.theme,
      useDarkPalette: useDarkPalette,
      accentColor: widget.accentColor,
    );
    final copyLabel = _localizedText(
      context,
      zh: _copied ? '已复制' : '复制',
      en: _copied ? 'Copied' : 'Copy',
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.containerColor,
        borderRadius: BorderRadius.circular(18),
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: widget.selectable
                      ? SelectableText.rich(
                          _highlightedSpan ?? const TextSpan(),
                        )
                      : RichText(text: _highlightedSpan ?? const TextSpan()),
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
      borderRadius: BorderRadius.circular(999),
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
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
          : ColorScheme.fromSeed(
              seedColor: tint,
              brightness: Brightness.dark,
              dynamicSchemeVariant: DynamicSchemeVariant.expressive,
              contrastLevel: 0.0,
            );
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

bool _containsMarkdownCodeFence(String source) {
  return RegExp(r'(^|\n)[ ]{0,3}(`{3,}|~{3,})').hasMatch(source);
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

String _closeUnterminatedFencedCodeBlock(String source) {
  final fencePattern = RegExp(r'^[ ]{0,3}((`{3,}|~{3,}))[^\n]*$');
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
  const _CodeSyntaxHighlighter({
    required TextStyle baseStyle,
    required bool darkSurface,
  }) : _baseStyle = baseStyle,
       _darkSurface = darkSurface;

  final TextStyle _baseStyle;
  final bool _darkSurface;

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
    var style = _baseStyle;
    if (classes.any((item) => item == 'comment' || item == 'quote')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF7DD3A7) : const Color(0xFF5B7C68),
        fontStyle: FontStyle.italic,
      );
    }
    if (classes.any(
      (item) =>
          item == 'keyword' ||
          item == 'selector-tag' ||
          item == 'meta-keyword' ||
          item == 'doctag',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFF9A8D4) : const Color(0xFFB42367),
        fontWeight: FontWeight.w700,
      );
    }
    if (classes.any(
      (item) =>
          item == 'string' ||
          item == 'regexp' ||
          item == 'attribute' ||
          item == 'template-variable',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
      );
    }
    if (classes.any(
      (item) =>
          item == 'number' ||
          item == 'literal' ||
          item == 'symbol' ||
          item == 'bullet',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      );
    }
    if (classes.any(
      (item) =>
          item == 'title' ||
          item == 'function' ||
          item == 'section' ||
          item == 'title.function_' ||
          item == 'title.class_',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF67E8F9) : const Color(0xFF0F766E),
        fontWeight: FontWeight.w700,
      );
    }
    if (classes.any(
      (item) =>
          item == 'type' ||
          item == 'built_in' ||
          item == 'class' ||
          item == 'params' ||
          item == 'variable' ||
          item == 'selector-id' ||
          item == 'selector-class' ||
          item == 'selector-attr' ||
          item == 'selector-pseudo' ||
          item == 'property',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
        fontWeight: FontWeight.w600,
      );
    }
    if (classes.any(
      (item) =>
          item == 'meta' || item == 'attr' || item == 'tag' || item == 'name',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
      );
    }
    if (classes.any((item) => item == 'operator' || item == 'punctuation')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
      );
    }
    return style;
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
  const _TokenDial({required this.totalTokens});

  final int totalTokens;

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial> {
  late int _previousTokens;

  @override
  void initState() {
    super.initState();
    _previousTokens = widget.totalTokens;
  }

  @override
  void didUpdateWidget(covariant _TokenDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalTokens != widget.totalTokens) {
      _previousTokens = oldWidget.totalTokens;
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
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.confirmation_number_rounded,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
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
            _localizedText(context, zh: 'Token', en: 'Token'),
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
        width: 620,
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
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
      ],
    );
  }
}

class _ThreadTemplateCard extends StatelessWidget {
  const _ThreadTemplateCard({required this.template, required this.onTap});

  final AiThreadTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: 260,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
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
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    template.iconData,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(template.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  template.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'v${template.internalVersion}',
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

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
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

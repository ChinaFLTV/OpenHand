import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/hook_config.dart';
import '../../app/support/openhand_paths.dart';
import '../hooks/hooks_executor.dart';
import '../mcp/model/mcp_tool.dart';
import '../mcp/service/mcp_tool_discovery_service.dart';
import 'data/ai_session_store.dart';
import 'model/ai_attachment.dart';
import 'model/ai_creation_mode.dart';
import 'model/ai_deny_command_rule.dart';
import 'model/ai_model_config.dart';
import 'model/ai_session.dart';
import 'model/ai_session_message.dart';
import 'model/ai_session_runtime_context.dart';
import 'model/ai_thread_template.dart';
import 'model/ai_token_usage.dart';
import 'service/ai_attachment_service.dart';
import 'service/ai_bash_tool_service.dart';
import 'service/ai_chat_service.dart';
import 'service/ai_claude_hook_service.dart';
import 'service/ai_dsml_tool_call_parser.dart';
import 'service/ai_image_summary_extractor.dart';
import 'service/ai_prompt_builder.dart';
import 'service/ai_prompt_template_repository.dart';
import 'service/ai_protocol_adapter.dart';
import 'service/ai_tool_runtime_service.dart';


part '_ai_session_models.dart';
part '_ai_session_utils.dart';

typedef WriteCommandConfirmationCallback =
    Future<bool> Function(BashCommandApprovalRequest request);

enum AiSendPhase { idle, compressing, sendingMessage, responding, awaitingApproval }

class AiRuntimeToolPreview {
  const AiRuntimeToolPreview({
    required this.sessionMode,
    required this.awaitingPlanApproval,
    required this.planRecoveryInspectionRequired,
    required this.planExecutionApproved,
    required this.toolNames,
    required this.notices,
    required this.gateReason,
    this.supportsToolCalls = true,
    this.isAuthoritative = true,
  });

  final AiSessionMode sessionMode;
  final bool awaitingPlanApproval;
  final bool planRecoveryInspectionRequired;
  final bool planExecutionApproved;
  final List<String> toolNames;
  final List<String> notices;
  final String gateReason;
  final bool supportsToolCalls;
  final bool isAuthoritative;

  int get toolCount => toolNames.length;
}

class AiSessionController extends ChangeNotifier {

  AiSessionController._({
    required AiSessionStore store,
    required AiChatClient chatClient,
    required AiChatClient backgroundChatClient,
    required AiPromptTemplateRepository templateRepository,
    required AiPromptBuilder promptBuilder,
    required AiBashToolService bashToolService,
    required AiClaudeHookService hookService,
    required AiToolRuntimeService toolRuntimeService,
    required AiAttachmentService attachmentService,
    required String Function() idGenerator,
    required DateTime Function() clock,
    HooksExecutor? userHooksExecutor,
  }) : _store = store,
       _chatClient = chatClient,
       _backgroundChatClient = backgroundChatClient,
       _templateRepository = templateRepository,
       _promptBuilder = promptBuilder,
       _bashToolService = bashToolService,
       _hookService = hookService,
       _toolRuntimeService = toolRuntimeService,
       _attachmentService = attachmentService,
       _idGenerator = idGenerator,
       _clock = clock,
       _userHooksExecutor = userHooksExecutor;
  static const String _editRollbackMarkerKey = 'deleted_by_edit_message_id';
  static const String _autoTitleSystemPrompt =
      'Generate a concise chat title. Return a single title only. Keep it within 20 characters. No quotes. No markdown.\n'
      'Summarize the first user request into a clear, specific, human-friendly thread title.\n'
      'Prefer concrete task names or topic names over vague summaries.\n'
      'Avoid titles that are too short, generic, or hard to understand, such as "帮助", "问题", "优化", "定位", "Help", "Question", or "Bug".\n'
      'If the request includes multiple related tasks, combine the main themes into one compact title.\n'
      'Do not mention "first message", do not add prefixes, numbering, emojis, or ending punctuation.';
  static const Set<String> _genericAutoTitleCandidates = <String>{
    '新会话',
    '会话',
    '对话',
    '聊天',
    '标题',
    '问题',
    '需求',
    '任务',
    '优化',
    '修复',
    '定位',
    '排查',
    '帮忙',
    '求助',
    '咨询',
    'chat',
    'thread',
    'conversation',
    'title',
    'help',
    'question',
    'bug',
    'fix',
    'optimize',
    'update',
    'task',
    'issue',
  };
  static const int _estimatedCharactersPerToken = 4;
  static const String _emptyPlanContinuationReplyError =
      'The assistant returned an empty follow-up response after tool execution.';

  static Future<AiSessionController> create({
    AiSessionStore? store,
    AiChatClient? chatClient,
    AiChatClient? backgroundChatClient,
    AiPromptTemplateRepository? templateRepository,
    AiPromptBuilder? promptBuilder,
    AiBashToolService? bashToolService,
    AiClaudeHookService? hookService,
    AiToolRuntimeService? toolRuntimeService,
    AiAttachmentService? attachmentService,
    McpToolDiscoveryService? mcpToolService,
    HooksExecutor? userHooksExecutor,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final resolvedStore = store ?? AiSessionStore();
    final resolvedChatClient = chatClient ?? AiChatService();
    final resolvedBackgroundChatClient =
        backgroundChatClient ??
        (chatClient == null ? AiChatService() : resolvedChatClient);
    final resolvedBashToolService = bashToolService ?? AiBashToolService();
    final resolvedHookService = hookService ?? AiNoopClaudeHookService();
    final resolvedMcpToolService = toolRuntimeService != null
        ? null
        : (mcpToolService ?? DefaultMcpToolDiscoveryService());
    final controller = AiSessionController._(
      store: resolvedStore,
      chatClient: resolvedChatClient,
      backgroundChatClient: resolvedBackgroundChatClient,
      templateRepository: templateRepository ?? AiPromptTemplateRepository(),
      promptBuilder: promptBuilder ?? const AiPromptBuilder(),
      bashToolService: resolvedBashToolService,
      hookService: resolvedHookService,
      userHooksExecutor: userHooksExecutor,
      toolRuntimeService:
          toolRuntimeService ??
          AiToolRuntimeService(
            bashToolService: resolvedBashToolService,
            hookService: resolvedHookService,
            mcpToolService: resolvedMcpToolService!,
            backgroundChatClient: resolvedBackgroundChatClient,
          ),
      attachmentService:
          attachmentService ??
          AiAttachmentService(
            attachmentsDirectoryPath: resolvedStore.attachmentsDirectoryPath,
            perSessionAttachmentsDirectoryPath:
                resolvedStore.perSessionAttachmentsDirectoryPath,
          ),
      idGenerator: idGenerator ?? const Uuid().v4,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
    await controller.refresh();
    return controller;
  }

  static const int _maxRecentErrors = 20;
  static const int _maxPlanHistoryEntries = 20;
  static const int _fallbackTitleMaxCharacters = 20;
  static const int _generatedTitleMaxCharacters = 20;
  static const int _minimumMeaningfulTitleCharacters = 4;
  static const int _minimumMeaningfulLatinTitleWords = 2;
  static const String _defaultNewSessionTitle = '新会话';
  static const Duration _autoTitleRequestTimeout = Duration(seconds: 20);
  static const Duration _autoTitleRetryWaitTimeout = Duration(seconds: 45);
  static const Duration _autoTitleRetryPollInterval = Duration(
    milliseconds: 250,
  );
  static const Duration _streamPreviewThrottle = Duration(milliseconds: 72);
  static const Duration _reasoningStreamPreviewThrottle = Duration(
    milliseconds: 160,
  );

  /// Maximum number of consecutive auto-continuations when the model keeps
  /// hitting its output token limit (finish_reason: "length" / "max_tokens").
  /// This prevents infinite loops when the model is stuck in a truncation cycle.
  static const int _maxTruncationContinuations = 5;

  /// Tracks how many consecutive times the current conversation loop has
  /// auto-continued due to model output truncation.  Reset to zero once the
  /// model completes normally or produces tool calls.
  var _truncationContinuationCount = 0;
  static const Set<String> _planModePlanningToolAllowlist = <String>{
    'task',
    'glob',
    'grep',
    'ls',
    'read',
    'webfetch',
    'websearch',
    'todowrite',
  };
  static const Set<String> _internalPromptLeakHeaders = <String>{
    '[[5] Current Session Messages]',
    '# [0] System Instructions',
    '# [1] Developer Instructions',
    '# [2] Session Metadata (ephemeral)',
    '# [3] User Memory (long-term facts)',
    '# [4] Recent Conversations Summary (past chats, titles + snippets)',
    '# System Reminder',
    '# Runtime Environment Snapshot',
    '# Workspace Instructions',
    '# [6] Your latest message',
    '# Compression System Instructions',
    '# Compression Developer Instructions',
    '# Compression Task Payload',
  };

  final AiSessionStore _store;
  final AiChatClient _chatClient;
  final AiChatClient _backgroundChatClient;
  final AiPromptTemplateRepository _templateRepository;
  final AiPromptBuilder _promptBuilder;
  final AiBashToolService _bashToolService;
  final AiClaudeHookService _hookService;
  final HooksExecutor? _userHooksExecutor;
  final AiToolRuntimeService _toolRuntimeService;
  final AiAttachmentService _attachmentService;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  /// Exposes the chat client for subsystems (e.g. Hardness API phase runner)
  /// that need to perform API calls independently of the session loop.
  AiChatClient get chatClient => _chatClient;

  /// Exposes the tool runtime service for subsystems that run their own
  /// agentic tool loops outside the standard session controller.
  AiToolRuntimeService get toolRuntimeService => _toolRuntimeService;

  /// Exposes the prompt template repository for subsystems that need to
  /// load template bundles (system instructions, developer instructions, etc.).
  AiPromptTemplateRepository get templateRepository => _templateRepository;

  bool _isDisposed = false;
  bool _isLoading = false;
  final Map<String, AiSendPhase> _sessionSendPhases = <String, AiSendPhase>{};
  final Map<String, Future<void>> _sessionOperationQueues =
      <String, Future<void>>{};
  final Map<String, Future<void> Function()> _sessionCancelHandlers =
      <String, Future<void> Function()>{};
  final Map<String, Completer<void>> _sessionStopSignals =
      <String, Completer<void>>{};
  final Set<String> _deletedSessionIds = <String>{};
  final Map<String, AiSendPhase> _approvalPreviousPhases =
      <String, AiSendPhase>{};
  final Map<String, bool> _didCompressInLastSendBySession = <String, bool>{};
  String? _currentSessionId;
  String? _editingMessageId;
  String? _lastErrorMessage;
  final Map<String, String> _lastErrorMessagesBySession = <String, String>{};
  List<AiSession> _sessions = const <AiSession>[];
  List<AiSessionPersistenceIssue> _persistenceIssues =
      const <AiSessionPersistenceIssue>[];
  Future<void> _operationQueue = Future<void>.value();

  bool get isLoading => _isLoading;
  bool get isSending => _sessionSendPhases.isNotEmpty;
  AiSendPhase get sendPhase => sendPhaseForSession(_currentSessionId);
  String? get activeSendSessionId {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null &&
        _sessionSendPhases.containsKey(currentSessionId)) {
      return currentSessionId;
    }
    if (_sessionSendPhases.isEmpty) {
      return null;
    }
    return _sessionSendPhases.keys.first;
  }

  bool get didCompressInLastSend =>
      didCompressInLastSendForSession(_currentSessionId);
  String? get currentSessionId => _currentSessionId;
  String? get editingMessageId => _editingMessageId;
  String? get lastErrorMessage {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null) {
      final sessionError = _lastErrorMessagesBySession[currentSessionId];
      if (sessionError != null) {
        return sessionError;
      }
    }
    return _lastErrorMessage;
  }

  List<AiSession> get sessions => List<AiSession>.unmodifiable(_sessions);
  List<AiSessionPersistenceIssue> get persistenceIssues =>
      List<AiSessionPersistenceIssue>.unmodifiable(_persistenceIssues);
  List<AiThreadTemplate> get templates => _templateRepository.templates;
  String get sessionsDirectoryPath => _store.sessionsDirectoryPath;

  AiSendPhase sendPhaseForSession(String? sessionId) => sessionId == null
      ? AiSendPhase.idle
      : (_sessionSendPhases[sessionId] ?? AiSendPhase.idle);

  bool didCompressInLastSendForSession(String? sessionId) {
    final normalizedSessionId = sessionId?.trim() ?? '';
    if (normalizedSessionId.isEmpty) {
      return false;
    }
    return _didCompressInLastSendBySession[normalizedSessionId] == true;
  }

  String? lastErrorMessageForSession(String? sessionId) {
    final normalizedSessionId = sessionId?.trim() ?? '';
    if (normalizedSessionId.isEmpty) {
      return null;
    }
    return _lastErrorMessagesBySession[normalizedSessionId];
  }

  bool canStopResponding(String? sessionId) {
    return sendPhaseForSession(sessionId) != AiSendPhase.idle;
  }

  /// Temporarily transitions a session into [AiSendPhase.awaitingApproval].
  ///
  /// Call this when showing a write-command confirmation dialog so the sidebar
  /// badge reflects the "waiting for approval" state.  The previous phase is
  /// stored so [clearSessionAwaitingApproval] can restore it.
  void setSessionAwaitingApproval(String sessionId) {
    final current = _sessionSendPhases[sessionId];
    if (current == AiSendPhase.awaitingApproval) {
      return; // Already in the desired state.
    }
    _approvalPreviousPhases[sessionId] = current ?? AiSendPhase.responding;
    _setSessionSendPhase(sessionId, AiSendPhase.awaitingApproval);
    notifyListeners();
  }

  /// Restores the phase that was active before [setSessionAwaitingApproval].
  void clearSessionAwaitingApproval(String sessionId) {
    final previous = _approvalPreviousPhases.remove(sessionId);
    if (_sessionSendPhases[sessionId] != AiSendPhase.awaitingApproval) {
      return; // Phase was already changed by another code path.
    }
    if (previous != null && previous != AiSendPhase.idle) {
      _setSessionSendPhase(sessionId, previous);
    } else {
      // Fallback: restore to responding since the session is still processing.
      _setSessionSendPhase(sessionId, AiSendPhase.responding);
    }
    notifyListeners();
  }


  AiSession? get currentSession {
    final currentSessionId = _currentSessionId;
    if (currentSessionId == null) {
      return null;
    }
    for (final session in _sessions) {
      if (session.id == currentSessionId) {
        return session;
      }
    }
    return null;
  }

  AiSessionMessage? get editingMessage {
    final currentSession = this.currentSession;
    final editingMessageId = _editingMessageId;
    if (currentSession == null || editingMessageId == null) {
      return null;
    }
    for (final message in currentSession.messages) {
      if (message.id == editingMessageId) {
        return message;
      }
    }
    return null;
  }

  void clearLastError() {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null &&
        _lastErrorMessagesBySession.remove(currentSessionId) != null) {
      notifyListeners();
      return;
    }
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    notifyListeners();
  }

  void _resetLastSendOutcome(String sessionId) {
    _didCompressInLastSendBySession[sessionId] = false;
    _lastErrorMessagesBySession.remove(sessionId);
  }

  void _markDidCompressInLastSend(String sessionId) {
    _didCompressInLastSendBySession[sessionId] = true;
  }

  void _setLastSendErrorMessage(String sessionId, String? message) {
    final normalizedMessage = message?.trim() ?? '';
    if (normalizedMessage.isEmpty) {
      _lastErrorMessagesBySession.remove(sessionId);
      return;
    }
    _lastErrorMessagesBySession[sessionId] = normalizedMessage;
  }

  void _clearSessionScopedSendState(String sessionId) {
    _didCompressInLastSendBySession.remove(sessionId);
    _lastErrorMessagesBySession.remove(sessionId);
  }

  void _pruneSessionScopedSendState() {
    final liveSessionIds = _sessions.map((session) => session.id).toSet();
    _didCompressInLastSendBySession.removeWhere(
      (sessionId, _) => !liveSessionIds.contains(sessionId),
    );
    _lastErrorMessagesBySession.removeWhere(
      (sessionId, _) => !liveSessionIds.contains(sessionId),
    );
    _approvalPreviousPhases.removeWhere(
      (sessionId, _) => !liveSessionIds.contains(sessionId),
    );
    // Remove stale entries from _deletedSessionIds that no longer have
    // in-flight operations.  An entry is safe to remove when no session
    // operation queue is pending for that id.
    _deletedSessionIds.removeWhere(
      (sessionId) => !_sessionOperationQueues.containsKey(sessionId),
    );
  }

  void clearPersistenceIssues() {
    if (_persistenceIssues.isEmpty) {
      return;
    }
    _persistenceIssues = const <AiSessionPersistenceIssue>[];
    notifyListeners();
  }

  Future<void> refresh() async {
    await _enqueueOperation(() async {
      _isLoading = true;
      _lastErrorMessage = null;
      _persistenceIssues = const <AiSessionPersistenceIssue>[];
      notifyListeners();
      try {
        final loadResult = await _store.loadAll();
        _sessions = loadResult.sessions
            .map(
              (session) => _normalizeStaleCompletedPlanState(
                session,
                normalizedAt: session.updatedAt,
              ),
            )
            .toList(growable: false);
        _pruneSessionScopedSendState();
        _persistenceIssues = loadResult.issues;
        final currentSessionId = _currentSessionId;
        if (currentSessionId == null ||
            !_sessions.any((session) => session.id == currentSessionId)) {
          _currentSessionId = null;
        }
        final editingMessageId = _editingMessageId;
        if (editingMessageId != null &&
            !_sessions.any(
              (session) =>
                  session.id == _currentSessionId &&
                  session.messages.any(
                    (message) => message.id == editingMessageId,
                  ),
            )) {
          _editingMessageId = null;
        }
      } catch (error) {
        _sessions = const <AiSession>[];
        _currentSessionId = null;
        _editingMessageId = null;
        _lastErrorMessage = '$error';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<bool> createSession({
    required String templateId,
    required AiSessionRuntimeContext runtimeContext,
    AiSessionMode mode = AiSessionMode.chat,
    bool fullAccessPermission = false,
  }) async {
    if (isSending) {
      return _createSessionUnlocked(
        templateId: templateId,
        runtimeContext: runtimeContext,
        mode: mode,
        fullAccessPermission: fullAccessPermission,
      );
    }
    return _enqueueOperation(
      () => _createSessionUnlocked(
        templateId: templateId,
        runtimeContext: runtimeContext,
        mode: mode,
        fullAccessPermission: fullAccessPermission,
      ),
    );
  }

  Future<void> selectSession(String sessionId) async {
    if (_currentSessionId == sessionId ||
        !_sessions.any((session) => session.id == sessionId)) {
      return;
    }
    _currentSessionId = sessionId;
    _editingMessageId = null;
    final selectedSession = _sessionById(sessionId);
    notifyListeners();
    if (selectedSession == null) {
      return;
    }
    unawaited(
      _emitSessionStartHook(
        session: selectedSession,
        source: 'resume',
      ).catchError((Object _, StackTrace stackTrace) {}),
    );
  }

  Future<bool> _createSessionUnlocked({
    required String templateId,
    required AiSessionRuntimeContext runtimeContext,
    required AiSessionMode mode,
    required bool fullAccessPermission,
  }) async {
    final template = _templateRepository.resolveTemplate(templateId);
    final now = _clock().toUtc();
    _lastErrorMessage = null;
    // 2026-04-14: 创建新会话时清理文件追踪器，避免跨会话的脏写检测误判
    _toolRuntimeService.fileTracker.clearAllTracking();
    final session = AiSession(
      id: _idGenerator(),
      title: _defaultNewSessionTitle,
      templateId: template.id,
      templateName: template.name,
      templateIconName: template.iconName,
      templateInternalVersion: template.internalVersion,
      createdAt: now,
      updatedAt: now,
      messages: const <AiSessionMessage>[],
      environment: _environmentFromRuntime(runtimeContext),
      statistics: const AiSessionStatistics.initial(),
      recentErrors: const <AiSessionErrorRecord>[],
      mode: mode,
      fullAccessPermission: fullAccessPermission,
    );
    _deletedSessionIds.remove(session.id);
    final committed = await _commitSessionLocked(session);
    if (!committed) {
      return false;
    }
    _currentSessionId = session.id;
    _editingMessageId = null;
    await _emitSessionStartHook(session: session, source: 'startup');
    notifyListeners();
    return true;
  }

  Future<bool> updateSessionMode(String sessionId, AiSessionMode mode) async {
    return _enqueueSessionOperation(sessionId, () async {
      final session = _sessionById(sessionId);
      if (session == null) {
        return false;
      }
      if (session.mode == mode) {
        return true;
      }
      final clearedSession =
          session.mode == AiSessionMode.plan && mode != AiSessionMode.plan
          ? _clearActivePlanState(session)
          : session;
      final updatedPromptMetadata = _markRuntimeToolCatalogMetadataStale(
        baseMetadata: clearedSession.lastPromptMetadata,
        session: clearedSession,
        mode: mode,
      );
      final updatedSession = _rebuildSession(
        clearedSession.copyWith(
          mode: mode,
          updatedAt: _clock().toUtc(),
          lastPromptMetadata: updatedPromptMetadata,
        ),
      );
      return _commitSessionLocked(updatedSession);
    });
  }

  Future<bool> updateSessionFullAccessPermission(
    String sessionId,
    bool enabled,
  ) async {
    // Bypass the session operation queue so the permission toggle stays
    // responsive even while sendMessage occupies the queue during AI
    // inference. Direct in-memory update is safe because:
    //   1. _mergeLiveSessionState (called by every _commitSessionLocked)
    //      always preserves the live session's fullAccessPermission, so
    //      concurrent commits from sendMessage will not overwrite this
    //      change.
    //   2. _executeSingleToolCall reads the live session state dynamically,
    //      so permission changes take effect on the next tool call.
    final session = _sessionById(sessionId);
    if (session == null) {
      return false;
    }
    if (session.fullAccessPermission == enabled) {
      return true;
    }
    final updatedSession = session.copyWith(
      fullAccessPermission: enabled,
      updatedAt: _clock().toUtc(),
    );
    // Directly replace in the _sessions list to bypass
    // _mergeLiveSessionState which would otherwise revert the permission
    // back to the previous (live) value.
    final existingIndex = _sessions.indexWhere(
      (item) => item.id == sessionId,
    );
    if (existingIndex == -1) {
      return false;
    }
    final updatedSessions = List<AiSession>.from(_sessions);
    updatedSessions[existingIndex] = updatedSession;
    _sessions = updatedSessions;
    notifyListeners();
    // Persist to disk asynchronously. Even if this save races with a
    // concurrent save from sendMessage, the final committed state will be
    // correct: _mergeLiveSessionState always reads the live session's
    // fullAccessPermission from _sessions (which we just updated).
    try {
      await _store.save(updatedSession);
    } catch (_) {
      // Disk persistence failure does not prevent the in-memory update
      // from taking effect. The next successful _commitSessionLocked call
      // (e.g. from sendMessage) will propagate the correct permission to
      // disk via _mergeLiveSessionState.
    }
    return true;
  }

  Future<bool> updateSessionMetadata(
    String sessionId,
    Map<String, Object?> payload,
  ) async {
    // Bypass the session operation queue so UI data (e.g., config popups)
    // stays responsive even while sendMessage occupies the queue.
    final session = _sessionById(sessionId);
    if (session == null || payload.isEmpty) {
      return false;
    }
    final nextMetadata = Map<String, Object?>.from(session.metadata);
    var hasChanges = false;
    for (final entry in payload.entries) {
      if (nextMetadata[entry.key] != entry.value) {
        nextMetadata[entry.key] = entry.value;
        hasChanges = true;
      }
    }
    if (!hasChanges) {
      return true;
    }
    final updatedSession = session.copyWith(
      metadata: nextMetadata,
      updatedAt: _clock().toUtc(),
    );
    final existingIndex = _sessions.indexWhere(
      (item) => item.id == sessionId,
    );
    if (existingIndex == -1) {
      return false;
    }
    final updatedSessions = List<AiSession>.from(_sessions);
    updatedSessions[existingIndex] = updatedSession;
    _sessions = updatedSessions;
    notifyListeners();
    try {
      await _store.save(updatedSession);
    } catch (_) {}
    return true;
  }

  /// Persists the model selection to the given session without going through
  /// the session operation queue (keeps the UI responsive while AI inference
  /// may be occupying the queue).
  Future<bool> updateSessionLastUsedModel(
    String sessionId, {
    required String providerConfigId,
    required String modelId,
  }) async {
    final session = _sessionById(sessionId);
    if (session == null) {
      return false;
    }
    if (session.lastUsedModelId == providerConfigId &&
        session.lastUsedModelLabel == modelId) {
      return true;
    }
    final updatedSession = session.copyWith(
      lastUsedModelId: providerConfigId,
      lastUsedModelLabel: modelId,
      updatedAt: _clock().toUtc(),
    );
    final existingIndex = _sessions.indexWhere(
      (item) => item.id == sessionId,
    );
    if (existingIndex == -1) {
      return false;
    }
    final updatedSessions = List<AiSession>.from(_sessions);
    updatedSessions[existingIndex] = updatedSession;
    _sessions = updatedSessions;
    notifyListeners();
    try {
      await _store.save(updatedSession);
    } catch (_) {}
    return true;
  }

  Future<bool> renameSession(String sessionId, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return false;
    }
    return _enqueueSessionOperation(sessionId, () async {
      final session = _sessionById(sessionId);
      if (session == null) {
        return false;
      }
      final updatedSession = session.copyWith(
        title: normalizedTitle,
        isTitleManuallyEdited: true,
        updatedAt: _clock().toUtc(),
      );
      final committed = await _commitSessionLocked(updatedSession);
      if (!committed) {
        return false;
      }
      _currentSessionId ??= sessionId;
      return true;
    });
  }

  Future<bool> deleteSession(String sessionId) async {
    return _enqueueOperation(() async {
      final previousSessions = List<AiSession>.from(_sessions);
      final previousCurrentSessionId = _currentSessionId;
      final previousEditingMessageId = _editingMessageId;
      final previousDidCompressInLastSendBySession = Map<String, bool>.from(
        _didCompressInLastSendBySession,
      );
      final previousLastErrorMessagesBySession = Map<String, String>.from(
        _lastErrorMessagesBySession,
      );
      final deletedSession = _sessionById(sessionId);
      final wasSending = _sessionSendPhases.containsKey(sessionId);
      final cancelHandler = _sessionCancelHandlers[sessionId];
      final updatedSessions = _sessions
          .where((session) => session.id != sessionId)
          .toList(growable: false);
      if (updatedSessions.length == _sessions.length) {
        return false;
      }
      _deletedSessionIds.add(sessionId);
      _sessions = updatedSessions;
      if (_currentSessionId == sessionId) {
        _currentSessionId = updatedSessions.isEmpty
            ? null
            : updatedSessions.first.id;
      }
      final currentEditingMessageId = _editingMessageId;
      final deletedSessionContainsEditingMessage =
          currentEditingMessageId != null &&
          previousSessions.any(
            (session) =>
                session.id == sessionId &&
                session.messages.any(
                  (message) => message.id == currentEditingMessageId,
                ),
          );
      if (deletedSessionContainsEditingMessage) {
        _editingMessageId = null;
      }
      notifyListeners();
      try {
        await _store.delete(sessionId);
        await _finalizeDeletedSession(
          sessionId: sessionId,
          wasSending: wasSending,
          cancelHandler: cancelHandler,
          deletedSession: deletedSession,
        );
        return true;
      } catch (error) {
        // Guard the existence check so a secondary DB failure does not shadow
        // the original delete error.
        bool stillExists;
        try {
          stillExists = await _store.exists(sessionId);
        } catch (_) {
          stillExists = true;
        }
        if (!stillExists) {
          await _finalizeDeletedSession(
            sessionId: sessionId,
            wasSending: wasSending,
            cancelHandler: cancelHandler,
            deletedSession: deletedSession,
          );
          return true;
        }
        _deletedSessionIds.remove(sessionId);
        _sessions = previousSessions;
        _currentSessionId = previousCurrentSessionId;
        _editingMessageId = previousEditingMessageId;
        _didCompressInLastSendBySession
          ..clear()
          ..addAll(previousDidCompressInLastSendBySession);
        _lastErrorMessagesBySession
          ..clear()
          ..addAll(previousLastErrorMessagesBySession);
        _lastErrorMessage = '$error';
        notifyListeners();
        return false;
      }
    });
  }

  AiRuntimeToolPreview previewRuntimeToolCatalog({
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    Map<String, McpToolCatalog> mcpToolCatalogsByServerName =
        const <String, McpToolCatalog>{},
  }) {
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    if (!adapter.supportsToolCalls) {
      return AiRuntimeToolPreview(
        sessionMode: session.mode,
        awaitingPlanApproval: session.awaitingPlanApproval,
        planRecoveryInspectionRequired: false,
        planExecutionApproved: false,
        toolNames: const <String>[],
        notices: const <String>[],
        gateReason: 'model_no_tool_support',
        supportsToolCalls: false,
      );
    }
    final latestUserMessageId = _latestActiveUserMessageId(session);
    final recoveryInspectionRequired = _shouldRequirePlanModeRecoveryInspection(
      session: session,
      latestUserMessageId: latestUserMessageId,
    );
    final executionApprovedForSend = _shouldAllowPlanModeExecutionTools(
      session: session,
      latestUserMessageId: latestUserMessageId,
    );
    final baseCatalog = _toolRuntimeService.resolveCatalogFromRuntimeSnapshot(
      runtimeContext: runtimeContext,
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
    );
    final effectiveCatalog = session.awaitingPlanApproval
        ? AiResolvedToolCatalog(
            definitions: const <AiToolDefinition>[],
            toolsByName: const <String, AiResolvedTool>{},
            notices: baseCatalog.notices,
          )
        : _toolCatalogForRound(
            session: session,
            baseCatalog: baseCatalog,
            executionApprovedForSend: executionApprovedForSend,
            recoveryInspectionRequired: recoveryInspectionRequired,
          );
    final toolNames = effectiveCatalog.definitions
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return AiRuntimeToolPreview(
      sessionMode: session.mode,
      awaitingPlanApproval: session.awaitingPlanApproval,
      planRecoveryInspectionRequired: recoveryInspectionRequired,
      planExecutionApproved: executionApprovedForSend,
      toolNames: toolNames,
      notices: effectiveCatalog.notices,
      gateReason: _runtimeToolCatalogGateReason(
        session: session,
        toolCatalog: effectiveCatalog,
        executionApprovedForSend: executionApprovedForSend,
        recoveryInspectionRequired: recoveryInspectionRequired,
      ),
    );
  }

  Future<bool> deleteMessages(
    Iterable<String> messageIds, {
    String? sessionId,
  }) async {
    final normalizedMessageIds = messageIds
        .map((messageId) => messageId.trim())
        .where((messageId) => messageId.isNotEmpty)
        .toSet();
    if (normalizedMessageIds.isEmpty) {
      return false;
    }
    final normalizedSessionId = sessionId?.trim() ?? '';
    final resolvedSessionId = normalizedSessionId.isEmpty
        ? _currentSessionId
        : normalizedSessionId;
    if (resolvedSessionId == null || resolvedSessionId.isEmpty) {
      return false;
    }
    return _enqueueSessionOperation(resolvedSessionId, () async {
      final session = _sessionById(resolvedSessionId);
      if (session == null) {
        return false;
      }
      return _deleteMessagesLocked(
        session: session,
        messageIds: normalizedMessageIds,
      );
    });
  }

  Future<bool> deleteMessagesFrom(String messageId, {String? sessionId}) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return false;
    }
    final normalizedSessionId = sessionId?.trim() ?? '';
    final resolvedSessionId = normalizedSessionId.isEmpty
        ? _currentSessionId
        : normalizedSessionId;
    if (resolvedSessionId == null || resolvedSessionId.isEmpty) {
      return false;
    }
    return _enqueueSessionOperation(resolvedSessionId, () async {
      final session = _sessionById(resolvedSessionId);
      if (session == null) {
        return false;
      }
      final startIndex = session.messages.indexWhere(
        (message) => message.id == normalizedMessageId && !message.isDeleted,
      );
      if (startIndex == -1) {
        return false;
      }
      final targetMessageIds = session.messages
          .skip(startIndex)
          .where((message) => !message.isDeleted)
          .map((message) => message.id)
          .toSet();
      if (targetMessageIds.isEmpty) {
        return false;
      }
      return _deleteMessagesLocked(
        session: session,
        messageIds: targetMessageIds,
      );
    });
  }

  Future<bool> _deleteMessagesLocked({
    required AiSession session,
    required Set<String> messageIds,
  }) async {
    final currentEditingMessageId = session.id == _currentSessionId
        ? _editingMessageId
        : null;
    var matchedMessage = false;
    var didChange = false;
    var shouldFinalizeEditRollback = false;
    final updatedMessages = <AiSessionMessage>[];
    for (final message in session.messages) {
      final rollbackMarker = '${message.metadata[_editRollbackMarkerKey] ?? ''}'
          .trim();
      if (!messageIds.contains(message.id)) {
        updatedMessages.add(message);
        continue;
      }
      matchedMessage = true;
      if (currentEditingMessageId != null &&
          rollbackMarker == currentEditingMessageId) {
        shouldFinalizeEditRollback = true;
      }
      if (message.isDeleted) {
        updatedMessages.add(message);
        continue;
      }
      didChange = true;
      updatedMessages.add(message.copyWith(isDeleted: true));
    }
    if (!matchedMessage) {
      return false;
    }
    var nextEditingMessageId = currentEditingMessageId;
    if (currentEditingMessageId != null) {
      final editingMessageStillVisible = updatedMessages.any(
        (message) =>
            message.id == currentEditingMessageId && !message.isDeleted,
      );
      if (!editingMessageStillVisible) {
        nextEditingMessageId = null;
        shouldFinalizeEditRollback = true;
      }
      if (shouldFinalizeEditRollback) {
        for (var index = 0; index < updatedMessages.length; index++) {
          final message = updatedMessages[index];
          final rollbackMarker =
              '${message.metadata[_editRollbackMarkerKey] ?? ''}'.trim();
          if (rollbackMarker != currentEditingMessageId) {
            continue;
          }
          final nextMetadata = Map<String, Object?>.from(message.metadata)
            ..remove(_editRollbackMarkerKey);
          updatedMessages[index] = message.copyWith(metadata: nextMetadata);
          didChange = true;
        }
      }
    }
    if (!didChange) {
      return true;
    }
    final previousEditingMessageId = _editingMessageId;
    if (session.id == _currentSessionId) {
      _editingMessageId = nextEditingMessageId;
    }
    final updatedSession = _rebuildSession(
      session.copyWith(messages: updatedMessages, updatedAt: _clock().toUtc()),
    );
    final committed = await _commitSessionLocked(updatedSession);
    if (committed) {
      return true;
    }
    if (session.id == _currentSessionId) {
      _editingMessageId = previousEditingMessageId;
      notifyListeners();
    }
    return false;
  }

  Future<void> _finalizeDeletedSession({
    required String sessionId,
    required bool wasSending,
    required Future<void> Function()? cancelHandler,
    required AiSession? deletedSession,
  }) async {
    if (wasSending) {
      final stopSignal = _sessionStopSignals.putIfAbsent(
        sessionId,
        Completer<void>.new,
      );
      if (!stopSignal.isCompleted) {
        stopSignal.complete();
      }
    }
    if (!wasSending) {
      _clearSessionExecutionState(sessionId);
      _sessionOperationQueues.remove(sessionId);
    }
    if (cancelHandler != null) {
      unawaited(
        cancelHandler().catchError((Object _, StackTrace stackTrace) {}),
      );
    }
    if (deletedSession != null) {
      await _emitSessionEndHook(session: deletedSession, reason: 'other');
    }
    _clearSessionScopedSendState(sessionId);
  }

  Future<({String content, List<AiMessageAttachment> attachments})?> beginEditingMessage(String messageId) async {
    return _enqueueOperation(() async {
      final session = currentSession;
      if (session == null) {
        return null;
      }
      final messageIndex = session.messages.indexWhere(
        (message) =>
            message.id == messageId &&
            !message.isDeleted &&
            message.kind == AiSessionMessageKind.user,
      );
      if (messageIndex == -1) {
        return null;
      }
      final editingMessage = session.messages[messageIndex];
      final updatedMessages = <AiSessionMessage>[
        for (var index = 0; index < session.messages.length; index++)
          index > messageIndex && !session.messages[index].isDeleted
              ? session.messages[index].copyWith(
                  isDeleted: true,
                  metadata: <String, Object?>{
                    ...session.messages[index].metadata,
                    _editRollbackMarkerKey: messageId,
                  },
                )
              : session.messages[index],
      ];
      final updatedSession = _rebuildSession(
        session.copyWith(
          messages: updatedMessages,
          updatedAt: _clock().toUtc(),
        ),
      );
      final committed = await _commitSessionLocked(updatedSession);
      if (!committed) {
        return null;
      }
      _editingMessageId = messageId;
      notifyListeners();
      final attachments = AiMessageAttachment.listFromMetadata(
        editingMessage.metadata[aiSessionMessageAttachmentsMetadataKey],
      );
      return (content: editingMessage.content, attachments: attachments);
    });
  }

  Future<bool> cancelEditingMessage() async {
    final editingMessageId = _editingMessageId;
    if (editingMessageId == null) {
      return true;
    }
    return _enqueueOperation(() async {
      final session = currentSession;
      if (session == null) {
        _editingMessageId = null;
        notifyListeners();
        return true;
      }
      var didChange = false;
      final updatedMessages = session.messages
          .map((message) {
            final marker = '${message.metadata[_editRollbackMarkerKey] ?? ''}'
                .trim();
            if (marker != editingMessageId) {
              return message;
            }
            didChange = true;
            final nextMetadata = Map<String, Object?>.from(message.metadata)
              ..remove(_editRollbackMarkerKey);
            return message.copyWith(isDeleted: false, metadata: nextMetadata);
          })
          .toList(growable: false);
      _editingMessageId = null;
      if (!didChange) {
        notifyListeners();
        return true;
      }
      final updatedSession = _rebuildSession(
        session.copyWith(
          messages: updatedMessages,
          updatedAt: _clock().toUtc(),
        ),
      );
      final committed = await _commitSessionLocked(updatedSession);
      if (!committed) {
        _editingMessageId = editingMessageId;
      }
      notifyListeners();
      return committed;
    });
  }

  Future<bool> completeEditingMessage() async {
    final editingMessageId = _editingMessageId;
    if (editingMessageId == null) {
      return true;
    }
    return _enqueueOperation(() async {
      final session = currentSession;
      if (session == null) {
        _editingMessageId = null;
        notifyListeners();
        return true;
      }
      var didChange = false;
      final updatedMessages = session.messages
          .map((message) {
            final marker = '${message.metadata[_editRollbackMarkerKey] ?? ''}'
                .trim();
            if (marker != editingMessageId) {
              return message;
            }
            didChange = true;
            final nextMetadata = Map<String, Object?>.from(message.metadata)
              ..remove(_editRollbackMarkerKey);
            return message.copyWith(metadata: nextMetadata);
          })
          .toList(growable: false);
      _editingMessageId = null;
      if (!didChange) {
        notifyListeners();
        return true;
      }
      final updatedSession = _rebuildSession(
        session.copyWith(
          messages: updatedMessages,
          updatedAt: _clock().toUtc(),
        ),
      );
      final committed = await _commitSessionLocked(updatedSession);
      if (!committed) {
        _editingMessageId = editingMessageId;
      }
      notifyListeners();
      return committed;
    });
  }

  Future<void> openStorageDirectory() {
    return _store.openStorageDirectory();
  }

  Future<bool> markErrorAsPresented({
    required String sessionId,
    required String errorId,
  }) async {
    return _enqueueSessionOperation(sessionId, () async {
      final session = _sessionById(sessionId);
      if (session == null) {
        return false;
      }
      var didChange = false;
      final updatedErrors = session.recentErrors
          .map((error) {
            if (error.id != errorId || error.hasBeenPresented) {
              return error;
            }
            didChange = true;
            return error.copyWith(presentedAt: _clock().toUtc());
          })
          .toList(growable: false);
      if (!didChange) {
        return true;
      }
      return _commitSessionLocked(
        session.copyWith(
          recentErrors: updatedErrors,
          updatedAt: session.updatedAt,
        ),
      );
    });
  }

  Future<void> stopResponding(String sessionId) async {
    if (!canStopResponding(sessionId)) {
      return;
    }
    _debugSessionLog(sessionId, 'stop_requested');
    final stopSignal = _sessionStopSignals.putIfAbsent(
      sessionId,
      Completer<void>.new,
    );
    if (!stopSignal.isCompleted) {
      stopSignal.complete();
    }
    _previewCancelledPendingToolCalls(sessionId);
    final cancelHandler = _sessionCancelHandlers[sessionId];
    if (cancelHandler == null) {
      return;
    }
    await cancelHandler().catchError((Object _, StackTrace stackTrace) {});
  }

  Future<bool> sendMessage({
    String? sessionId,
    required String content,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    List<String> attachmentFilePaths = const <String>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    List<AiDenyCommandRule> denyCommandRules = const <AiDenyCommandRule>[],
    bool requireWriteCommandConfirmation = true,
    WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    final normalizedContent = content.trim();
    final normalizedAttachmentPaths = _normalizeAttachmentPaths(
      attachmentFilePaths,
    );
    if (normalizedContent.isEmpty && normalizedAttachmentPaths.isEmpty) {
      return false;
    }
    final resolvedSessionId = sessionId ?? _currentSessionId;
    if (resolvedSessionId == null) {
      _lastErrorMessage = 'No active session selected.';
      notifyListeners();
      return false;
    }

    return _enqueueSessionOperation(resolvedSessionId, () async {
      var session = _sessionById(resolvedSessionId);
      if (session == null) {
        _setLastSendErrorMessage(
          resolvedSessionId,
          'No active session selected.',
        );
        notifyListeners();
        return false;
      }

      _debugSessionLog(
        session.id,
        'send_message_start model=${model.modelId} chars=${normalizedContent.length} attachments=${normalizedAttachmentPaths.length}',
      );
      _setSessionSendPhase(session.id, AiSendPhase.sendingMessage);
      _sessionCancelHandlers.remove(session.id);
      _sessionStopSignals[session.id] = Completer<void>();
      _resetLastSendOutcome(session.id);
      _lastErrorMessage = null;
      notifyListeners();

      try {
        final previousEnvironment = session.environment;
        final previousPromptMetadata = session.lastPromptMetadata;
        await _emitRuntimeCompatibilityHooks(
          sessionId: session.id,
          runtimeContext: runtimeContext,
          previousEnvironment: previousEnvironment,
          previousPromptMetadata: previousPromptMetadata,
        );
        session = session.copyWith(
          environment: _environmentFromRuntime(runtimeContext),
        );
        final userHookResult = await _hookService.runHooks(
          eventName: 'UserPromptSubmit',
          sessionId: session.id,
          matcherValue: '',
          cwd: OpenHandPaths.applicationDirectoryPath(),
          payload: <String, Object?>{
            'prompt': normalizedContent,
            'user_prompt': normalizedContent,
            'userPrompt': normalizedContent,
          },
        );
        await _safeRunUserHook(
          event: HookEvent.userPromptSubmit,
          sessionId: session.id,
          payload: <String, Object?>{
            'prompt': normalizedContent,
          },
        );
        // Re-read session since _safeRunUserHook may have committed hook messages.
        session = _sessionById(session.id) ?? session;
        if (userHookResult.blocked) {
          final blockedSession = _appendError(
            session,
            stage: 'user_prompt_hook',
            message:
                userHookResult.blockReason ??
                'The user prompt was blocked by a hook.',
            detail: userHookResult.executedCommands.join('\n'),
          );
          await _commitSessionLocked(blockedSession);
          _setLastSendErrorMessage(
            session.id,
            userHookResult.blockReason ??
                'The user prompt was blocked by a hook.',
          );
          return false;
        }
        final userMessageMetadata = <String, Object?>{};
        if (creationRequest.isActive) {
          userMessageMetadata[AiCreationRequest.metadataKey] =
              creationRequest.toMetadata();
        }
        if (userHookResult.userFeedback.isNotEmpty) {
          userMessageMetadata[aiUserPromptHookFeedbackMetadataKey] =
              userHookResult.userFeedback;
        }
        if (userHookResult.systemReminders.isNotEmpty) {
          userMessageMetadata[aiHookSystemRemindersMetadataKey] =
              userHookResult.systemReminders;
        }
        if (_shouldResetPlanStateForNewTask(
          session: session,
          latestUserContent: normalizedContent,
        )) {
          session = _clearActivePlanState(session);
        }
        if (session.awaitingPlanApproval &&
            _looksLikePlanApproval(normalizedContent)) {
          final statusMessage = AiSessionMessage.status(
            id: _idGenerator(),
            content: 'Plan approved. Implementation may proceed.',
            createdAt: _clock().toUtc(),
            metadata: const <String, Object?>{'plan_mode_approved': true},
          );
          session = _rebuildSession(
            session.copyWith(
              updatedAt: statusMessage.createdAt,
              awaitingPlanApproval: false,
              clearPendingPlan: true,
              messages: <AiSessionMessage>[...session.messages, statusMessage],
            ),
          );
          session = _syncPlanHistory(
            session,
            statusOverride:
                _deriveTrackedPlanStatus(session) ??
                AiSessionPlanStatus.inProgress,
            trackedAt: statusMessage.createdAt,
          );
          final approvedCommitted = await _commitSessionLocked(session);
          if (!approvedCommitted) {
            _setLastSendErrorMessage(
              session.id,
              'Failed to persist the plan approval state.',
            );
            return false;
          }
        }
        final shouldCompress = _shouldCompressSessionHistory(
          session,
          runtimeContext,
          model,
        );
        if (shouldCompress) {
          _setSessionSendPhase(session.id, AiSendPhase.compressing);
          notifyListeners();
        }
        final compressedSession = await _compressIfNeeded(
          session: session,
          model: model,
          runtimeContext: runtimeContext,
        );
        session = compressedSession;
        if (shouldCompress) {
          _setSessionSendPhase(session.id, AiSendPhase.sendingMessage);
          notifyListeners();
          await Future<void>.delayed(Duration.zero);
        }

        if (!_supportsAttachmentsForSession(
          model: model,
          session: session,
          newAttachmentPaths: normalizedAttachmentPaths,
        )) {
          _setLastSendErrorMessage(
            session.id,
            'The selected model does not support file attachments for this conversation.',
          );
          return false;
        }

        final preparedUserTurn = await _prepareUserTurn(
          session: session,
          content: normalizedContent,
          model: model,
          runtimeContext: runtimeContext,
          attachmentFilePaths: normalizedAttachmentPaths,
          userMessageMetadata: userMessageMetadata,
        );
        session = preparedUserTurn.session;
        final userCommitted = await _commitSessionLocked(session);
        if (!userCommitted) {
          if (preparedUserTurn.importedAttachments) {
            await _attachmentService.deleteMessageAttachments(
              sessionId: session.id,
              messageId: preparedUserTurn.userMessage.id,
            );
          }
          _setLastSendErrorMessage(
            session.id,
            'Failed to persist the user message.',
          );
          return false;
        }
        _setSessionSendPhase(session.id, AiSendPhase.responding);
        notifyListeners();

        if (preparedUserTurn.shouldGenerateTitle &&
            runtimeContext.autoTitleEnabled) {
          unawaited(
            _generateAutoTitle(
              sessionId: session.id,
              sourceMessageId: preparedUserTurn.userMessage.id,
              sourceContent: preparedUserTurn.userMessage.content,
              model: model,
            ),
          );
        }

        final succeeded = await _runAssistantConversation(
          session: session,
          model: model,
          runtimeContext: runtimeContext,
          responseModalities: responseModalities,
          creationRequest: creationRequest,
          latestUserMessageId: preparedUserTurn.userMessage.id,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
        );
        return succeeded;
      } catch (error) {
        _debugSessionLog(resolvedSessionId, 'send_message_failed error=$error');
        final current = _sessionById(resolvedSessionId);
        if (current != null) {
          final failedToolSession = _markPendingToolCallsFailed(
            current,
            detail:
                'The assistant request failed before the pending tool call completed.',
          );
          final updated = _appendError(
            failedToolSession,
            stage: 'chat_request',
            message: '$error',
            detail: '$error',
          );
          await _commitSessionLocked(updated);
        }
        _setLastSendErrorMessage(resolvedSessionId, '$error');
        notifyListeners();
        return false;
      } finally {
        _clearSessionExecutionState(resolvedSessionId);
        notifyListeners();
      }
    });
  }

  List<String> _normalizeAttachmentPaths(List<String> attachmentFilePaths) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawPath in attachmentFilePaths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      normalized.add(path);
    }
    return normalized;
  }

  bool _supportsAttachmentsForSession({
    required AiModelConfig model,
    required AiSession session,
    required List<String> newAttachmentPaths,
  }) {
    final hasNewAttachments = newAttachmentPaths.isNotEmpty;
    final hasExistingAttachments = session.activeConversationMessages.any(
      (message) => AiMessageAttachment.listFromMetadata(
        message.metadata[aiSessionMessageAttachmentsMetadataKey],
      ).isNotEmpty,
    );
    if (!hasNewAttachments && !hasExistingAttachments) {
      return true;
    }
    // Even when a model does not support native image parts, the prompt builder
    // can still include attachment summaries/text extracts safely.
    return true;
  }

  int _characterCountForMessageContent(
    String content, {
    List<AiMessageAttachment> attachments = const <AiMessageAttachment>[],
  }) {
    final attachmentCharacterCount = attachments.fold<int>(
      0,
      (sum, item) => sum + item.promptText.length,
    );
    return AiSessionMessage.countCharacters(content) + attachmentCharacterCount;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final stopSignal in _sessionStopSignals.values) {
      if (!stopSignal.isCompleted) {
        stopSignal.complete();
      }
    }
    final cancelHandlers = _sessionCancelHandlers.values.toList(
      growable: false,
    );
    _sessionCancelHandlers.clear();
    _sessionStopSignals.clear();
    _sessionSendPhases.clear();
    _approvalPreviousPhases.clear();
    for (final cancelHandler in cancelHandlers) {
      unawaited(
        cancelHandler().catchError((Object _, StackTrace stackTrace) {}),
      );
    }
    if (!identical(_backgroundChatClient, _chatClient)) {
      _backgroundChatClient.dispose();
    }
    _toolRuntimeService.dispose();
    _chatClient.dispose();
    super.dispose();
  }

  Future<bool> _runAssistantConversation({
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    required String? latestUserMessageId,
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    _debugSessionLog(
      session.id,
      'assistant_conversation_start model=${model.modelId} latest_user_message_id=${latestUserMessageId ?? ''}',
    );
    _truncationContinuationCount = 0;
    final templateBundle = await _templateRepository.loadBundle(
      session.templateId,
    );
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final toolCatalog = adapter.supportsToolCalls
        ? await _toolRuntimeService.resolveCatalog(
            runtimeContext: runtimeContext,
          )
        : const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          );
    var workingSession = session;
    var activeLatestUserMessageId = latestUserMessageId;
    var planModeRecoveryInspectionRequired =
        _shouldRequirePlanModeRecoveryInspection(
          session: workingSession,
          latestUserMessageId: activeLatestUserMessageId,
        );
    var planModeExecutionApprovedForSend = _shouldAllowPlanModeExecutionTools(
      session: workingSession,
      latestUserMessageId: activeLatestUserMessageId,
    );
    var toolRoundCount = 0;
    var toolCallCount = 0;
    final singleRoundToolCallLimit = math.max(
      1,
      runtimeContext.singleRoundToolCallLimit,
    );
    final sequentialToolRoundLimit = math.max(
      1,
      runtimeContext.sequentialToolRoundLimit,
    );
    final primedSession = await _maybePrefetchClaudeCodeDocs(
      session: workingSession,
      model: model,
      toolCatalog: toolCatalog,
      latestUserMessageId: activeLatestUserMessageId,
      denyCommandRules: denyCommandRules,
      requireWriteCommandConfirmation: requireWriteCommandConfirmation,
      confirmWriteCommand: confirmWriteCommand,
    );
    if (primedSession == null) {
      return false;
    }
    workingSession = primedSession;

    while (true) {
      final latestSession = _sessionById(workingSession.id);
      if (latestSession != null) {
        workingSession = latestSession;
      }
      if (_isStopRequestedForSession(workingSession.id)) {
        _debugSessionLog(workingSession.id, 'assistant_conversation_stopped');
        return true;
      }
      final toolCatalogForRound = workingSession.awaitingPlanApproval
          ? const AiResolvedToolCatalog(
              definitions: <AiToolDefinition>[],
              toolsByName: <String, AiResolvedTool>{},
            )
          : _toolCatalogForRound(
              session: workingSession,
              baseCatalog: toolCatalog,
              executionApprovedForSend: planModeExecutionApprovedForSend,
              recoveryInspectionRequired: planModeRecoveryInspectionRequired,
            );
      final toolsForRound = toolCatalogForRound.definitions;
      _debugSessionLog(
        workingSession.id,
        'stream_round_start round=${toolRoundCount + 1} awaiting_plan_approval=${workingSession.awaitingPlanApproval} plan_mode=${workingSession.mode.storageValue} execution_approved=$planModeExecutionApprovedForSend recovery_inspection_required=$planModeRecoveryInspectionRequired tools=${toolsForRound.length}',
      );
      final promptResult = _promptBuilder.buildSessionPrompt(
        templateBundle: templateBundle,
        session: workingSession,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: runtimeContext.memoryEntries,
        sessionMessages: workingSession.activeConversationMessages,
        latestUserMessageId: activeLatestUserMessageId,
        availableTools: toolsForRound,
      );
      late final AiChatStreamingResponse streamResponse;
      try {
        streamResponse = await _chatClient.sendMessageStream(
          model: model,
          messages: promptResult.messages,
          tools: toolsForRound,
          responseModalities: responseModalities,
          creationRequest: creationRequest,
          timeout: Duration(seconds: runtimeContext.connectTimeoutSeconds),
          streamIdleTimeout: Duration(
            seconds: runtimeContext.streamIdleTimeoutSeconds,
          ),
          cancelSignal: _stopSignalForSession(workingSession.id),
        );
      } catch (error) {
        if (_isStopRequestedForSession(workingSession.id)) {
          _debugSessionLog(
            workingSession.id,
            'stream_open_cancelled round=${toolRoundCount + 1}',
          );
          return true;
        }
        final errorStage = toolRoundCount > 0
            ? 'chat_continuation_request'
            : 'chat_request';
        _debugSessionLog(
          workingSession.id,
          'stream_open_failed round=${toolRoundCount + 1} stage=$errorStage error=$error',
        );
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: errorStage,
          detail: '$error',
        );
        final erroredSession = _appendError(
          workingSession,
          stage: errorStage,
          message: '$error',
          detail: '$error',
        );
        await _commitSessionLocked(_rebuildSession(erroredSession));
        _setLastSendErrorMessage(workingSession.id, '$error');
        notifyListeners();
        return false;
      }
      _debugSessionLog(
        workingSession.id,
        'stream_opened round=${toolRoundCount + 1} prompt_messages=${promptResult.messages.length}',
      );
      _setSessionCancelHandler(workingSession.id, streamResponse.cancel);
      if (_isStopRequestedForSession(workingSession.id) &&
          streamResponse.cancel != null) {
        await streamResponse.cancel!().catchError(
          (Object _, StackTrace stackTrace) {},
        );
      }

      var streamedSession = workingSession;
      // Phase-1 telemetry: immediately stamp the composed prompt + env onto
      // the user message so the audit dialog shows data during streaming.
      var preStreamTelemetryPreviewed = false;
      if (activeLatestUserMessageId != null) {
        final nextSession = _applyPreStreamTelemetryToUserMessage(
          session: streamedSession,
          runtimeContext: runtimeContext,
          promptResult: promptResult,
          userMessageId: activeLatestUserMessageId,
        );
        if (!identical(nextSession, streamedSession)) {
          streamedSession = nextSession;
          _previewSession(streamedSession);
          preStreamTelemetryPreviewed = true;
        }
      }
      String? assistantMessageId;
      String? reasoningMessageId;
      AiTokenUsage? streamedUsage;
      final toolCallMessageIds = <int, String>{};
      final assistantRawBuffer = StringBuffer();
      final reasoningRawBuffer = StringBuffer();
      Timer? previewTimer;
      String? pendingPreviewReason;
      String? pendingReasoningContent;
      var hasPendingReasoningPreview = false;
      var hasPreviewedStreamDelta = preStreamTelemetryPreviewed;

      AiSession setReasoningStreamingState(AiSession session, bool streaming) {
        final messageId = reasoningMessageId;
        if (messageId == null) {
          return session;
        }
        final messageIndex = session.messages.indexWhere(
          (message) => message.id == messageId,
        );
        if (messageIndex == -1) {
          return session;
        }
        final currentMessage = session.messages[messageIndex];
        final currentStreaming =
            currentMessage.metadata[aiSessionMessageMetadataStreamingKey] ==
            true;
        if (currentStreaming == streaming) {
          return session;
        }
        final updatedMessages = List<AiSessionMessage>.from(session.messages);
        updatedMessages[messageIndex] = currentMessage.copyWith(
          metadata: <String, Object?>{
            ...currentMessage.metadata,
            aiSessionMessageMetadataStreamingKey: streaming,
          },
        );
        return session.copyWith(
          messages: updatedMessages,
          updatedAt: _clock().toUtc(),
        );
      }

      AiSession upsertReasoningPreview(AiSession session, String content) {
        final resolvedMessageId = reasoningMessageId ?? _idGenerator();
        reasoningMessageId = resolvedMessageId;
        return _upsertMessage(
          session,
          messageId: resolvedMessageId,
          create: () => AiSessionMessage.reasoning(
            id: resolvedMessageId,
            content: content,
            createdAt: _clock().toUtc(),
            modelId: model.id,
            modelLabel: model.displayName,
            metadata: const <String, Object?>{
              aiSessionMessageMetadataStreamingKey: true,
            },
          ),
          update: (message) => message.copyWith(
            content: content,
            modelId: model.id,
            modelLabel: model.displayName,
            metadata: <String, Object?>{
              ...message.metadata,
              aiSessionMessageMetadataStreamingKey: true,
            },
          ),
        );
      }

      void materializePendingReasoningPreview() {
        if (!hasPendingReasoningPreview) {
          return;
        }
        final content = pendingReasoningContent ?? '';
        hasPendingReasoningPreview = false;
        if (content.isEmpty && reasoningMessageId == null) {
          return;
        }
        streamedSession = upsertReasoningPreview(streamedSession, content);
      }

      AiSession syncFinalAssistantMessage(
        AiSession session,
        String finalReply,
      ) {
        final sanitizedContent = _sanitizeVisibleModelContent(finalReply);
        if (sanitizedContent.isEmpty && assistantMessageId == null) {
          return session;
        }
        final resolvedMessageId = assistantMessageId ?? _idGenerator();
        assistantMessageId = resolvedMessageId;
        return _upsertMessage(
          session,
          messageId: resolvedMessageId,
          create: () => AiSessionMessage.assistant(
            id: resolvedMessageId,
            content: sanitizedContent,
            createdAt: _clock().toUtc(),
            modelId: model.id,
            modelLabel: model.displayName,
          ),
          update: (message) => message.copyWith(
            content: sanitizedContent.isEmpty
                ? message.content
                : sanitizedContent,
            modelId: model.id,
            modelLabel: model.displayName,
          ),
        );
      }

      AiSession syncFinalReasoningMessage(
        AiSession session,
        String finalReasoning,
      ) {
        final sanitizedContent = _sanitizeVisibleModelContent(finalReasoning);
        if (sanitizedContent.isEmpty && reasoningMessageId == null) {
          return session;
        }
        final resolvedMessageId = reasoningMessageId ?? _idGenerator();
        reasoningMessageId = resolvedMessageId;
        return _upsertMessage(
          session,
          messageId: resolvedMessageId,
          create: () => AiSessionMessage.reasoning(
            id: resolvedMessageId,
            content: sanitizedContent,
            createdAt: _clock().toUtc(),
            modelId: model.id,
            modelLabel: model.displayName,
            metadata: const <String, Object?>{
              aiSessionMessageMetadataStreamingKey: false,
            },
          ),
          update: (message) => message.copyWith(
            content: sanitizedContent.isEmpty
                ? message.content
                : sanitizedContent,
            modelId: model.id,
            modelLabel: model.displayName,
            metadata: <String, Object?>{
              ...message.metadata,
              aiSessionMessageMetadataStreamingKey: false,
            },
          ),
        );
      }

      AiSession applyUsageToMessageIfPresent(
        AiSession session, {
        required String? messageId,
        required AiTokenUsage usage,
      }) {
        if (messageId == null || messageId.isEmpty) {
          return session;
        }
        final index = session.messages.indexWhere(
          (message) => message.id == messageId,
        );
        if (index == -1) {
          return session;
        }
        final currentMessage = session.messages[index];
        final updatedMessages = List<AiSessionMessage>.from(session.messages);
        updatedMessages[index] = currentMessage.copyWith(
          usage: usage,
          modelId: currentMessage.modelId ?? model.id,
          modelLabel: currentMessage.modelLabel ?? model.displayName,
        );
        return session.copyWith(
          messages: updatedMessages,
          updatedAt: _clock().toUtc(),
        );
      }

      void flushPreview(String reason) {
        previewTimer?.cancel();
        previewTimer = null;
        pendingPreviewReason = null;
        materializePendingReasoningPreview();
        final sessionToPreview = streamedSession;
        final lastMessage = sessionToPreview.messages.isEmpty
            ? null
            : sessionToPreview.messages.last;
        _debugSessionLog(
          workingSession.id,
          'stream_preview_flush reason=$reason messages=${sessionToPreview.messages.length} last_kind=${lastMessage?.kind.storageValue ?? 'none'} last_chars=${lastMessage?.characterCount ?? 0}',
        );
        _previewSession(sessionToPreview);
        hasPreviewedStreamDelta = true;
      }

      void schedulePreview(String reason) {
        pendingPreviewReason = reason;
        if (!hasPreviewedStreamDelta) {
          flushPreview('immediate_$reason');
          return;
        }
        if (previewTimer != null) {
          return;
        }
        final previewThrottle = reason == 'reasoningDelta'
            ? _reasoningStreamPreviewThrottle
            : _streamPreviewThrottle;
        previewTimer = Timer(previewThrottle, () {
          if (_isDisposed) {
            return;
          }
          flushPreview('throttled_${pendingPreviewReason ?? reason}');
        });
      }

      final subscription = streamResponse.events.listen((event) {
        var sessionChanged = false;
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            materializePendingReasoningPreview();
            final delta = event.textDelta ?? '';
            if (delta.isEmpty) {
              return;
            }
            assistantRawBuffer.write(delta);
            final sanitizedContent = _sanitizeVisibleModelContent(
              assistantRawBuffer.toString(),
            );
            if (sanitizedContent.isEmpty && assistantMessageId == null) {
              return;
            }
            final resolvedMessageId = assistantMessageId ?? _idGenerator();
            assistantMessageId = resolvedMessageId;
            streamedSession = _upsertMessage(
              streamedSession,
              messageId: resolvedMessageId,
              create: () => AiSessionMessage.assistant(
                id: resolvedMessageId,
                content: sanitizedContent,
                createdAt: _clock().toUtc(),
                modelId: model.id,
                modelLabel: model.displayName,
              ),
              update: (message) => message.copyWith(
                content: sanitizedContent,
                modelId: model.id,
                modelLabel: model.displayName,
              ),
            );
            sessionChanged = true;
          case AiChatStreamEventType.reasoningDelta:
            final delta = event.reasoningDelta ?? '';
            if (delta.isEmpty) {
              return;
            }
            reasoningRawBuffer.write(delta);
            final sanitizedContent = _sanitizeVisibleModelContent(
              reasoningRawBuffer.toString(),
            );
            if (sanitizedContent.isEmpty && reasoningMessageId == null) {
              return;
            }
            pendingReasoningContent = sanitizedContent;
            reasoningMessageId ??= _idGenerator();
            hasPendingReasoningPreview = true;
            sessionChanged = true;
          case AiChatStreamEventType.toolCallDelta:
            materializePendingReasoningPreview();
            final delta = event.toolCallDelta;
            if (delta == null) {
              return;
            }
            final resolvedMessageId = toolCallMessageIds.putIfAbsent(
              delta.index,
              _idGenerator,
            );
            streamedSession = _upsertMessage(
              streamedSession,
              messageId: resolvedMessageId,
              create: () {
                final resolvedToolCallId = (delta.id ?? '').trim().isEmpty
                    ? 'tool-call-${delta.index}'
                    : delta.id!.trim();
                final resolvedName = (delta.name ?? '').trim();
                final toolCalls = <String, Object?>{
                  'id': resolvedToolCallId,
                  'name': resolvedName,
                  'arguments': delta.argumentsFragment,
                };
                return AiSessionMessage.toolCall(
                  id: resolvedMessageId,
                  content: _renderToolCallContent(
                    name: resolvedName,
                    arguments: delta.argumentsFragment,
                  ),
                  createdAt: _clock().toUtc(),
                  modelId: model.id,
                  modelLabel: model.displayName,
                  metadata: <String, Object?>{
                    'tool_call_index': delta.index,
                    'tool_call_id': resolvedToolCallId,
                    'tool_name': resolvedName,
                    'tool_arguments': delta.argumentsFragment,
                    'tool_calls': <Map<String, Object?>>[toolCalls],
                  },
                );
              },
              update: (message) {
                final currentArguments =
                    '${message.metadata['tool_arguments'] ?? ''}';
                final mergedArguments =
                    '$currentArguments${delta.argumentsFragment}';
                final resolvedToolCallId = (delta.id ?? '').trim().isNotEmpty
                    ? delta.id!.trim()
                    : '${message.metadata['tool_call_id'] ?? 'tool-call-${delta.index}'}';
                final resolvedName = (delta.name ?? '').trim().isNotEmpty
                    ? delta.name!.trim()
                    : '${message.metadata['tool_name'] ?? ''}'.trim();
                final toolCalls = <Map<String, Object?>>[
                  <String, Object?>{
                    'id': resolvedToolCallId,
                    'name': resolvedName,
                    'arguments': mergedArguments,
                  },
                ];
                return message.copyWith(
                  content: _renderToolCallContent(
                    name: resolvedName,
                    arguments: mergedArguments,
                  ),
                  metadata: <String, Object?>{
                    ...message.metadata,
                    'tool_call_index': delta.index,
                    'tool_call_id': resolvedToolCallId,
                    'tool_name': resolvedName,
                    'tool_arguments': mergedArguments,
                    'tool_calls': toolCalls,
                  },
                  modelId: model.id,
                  modelLabel: model.displayName,
                );
              },
            );
            sessionChanged = true;
          case AiChatStreamEventType.usage:
            streamedUsage = event.usage;
            final usage = streamedUsage;
            if (usage == null) {
              return;
            }
            streamedSession = applyUsageToMessageIfPresent(
              streamedSession,
              messageId: assistantMessageId,
              usage: usage,
            );
            streamedSession = applyUsageToMessageIfPresent(
              streamedSession,
              messageId: activeLatestUserMessageId,
              usage: usage,
            );
            sessionChanged = true;
        }
        if (sessionChanged) {
          schedulePreview(event.type.name);
        }
      });

      final eventDrain = subscription.asFuture<void>();
      late final AiChatStreamResult result;
      try {
        result = await streamResponse.result;
        try {
          await eventDrain.timeout(const Duration(milliseconds: 800));
        } on TimeoutException {
          await subscription.cancel();
          flushPreview('event_drain_timeout');
        }
      } catch (error) {
        // Cancel the preview timer on any error path to prevent a stale timer
        // from firing after the stream has already failed and the surrounding
        // state has been torn down.
        previewTimer?.cancel();
        previewTimer = null;
        await subscription.cancel();
        _setSessionCancelHandler(workingSession.id, null);
        materializePendingReasoningPreview();
        streamedSession = setReasoningStreamingState(streamedSession, false);
        flushPreview('stream_failed');
        _debugSessionLog(workingSession.id, 'stream_failed error=$error');
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: 'chat_stream',
          detail: '$error',
        );
        final failedToolSession = _markPendingToolCallsFailed(
          streamedSession,
          detail:
              'The assistant stream failed before the pending tool call completed.',
        );
        final failedSession = _appendError(
          failedToolSession,
          stage: 'chat_stream',
          message: '$error',
          detail: '$error',
        );
        await _commitSessionLocked(_rebuildSession(failedSession));
        _setLastSendErrorMessage(workingSession.id, '$error');
        notifyListeners();
        return false;
      }
      _setSessionCancelHandler(workingSession.id, null);
      materializePendingReasoningPreview();
      final didCancelStream =
          result.wasCancelled || _isStopRequestedForSession(workingSession.id);
      // Always preserve the intermediate assistant narration if it has
      // meaningful content after sanitization.  Previous versions removed this
      // message when tool calls were present, which caused the AI's chain-of-
      // thought reasoning and narration to be lost from the conversation
      // transcript.  Users reported this as "messages being unexpectedly lost".
      //
      // The sanitizer already strips raw <tool_call>/<tool_result> XML markup,
      // so what remains is the actual narration text that should be preserved.
      final sanitizedReply = _sanitizeVisibleModelContent(result.reply);
      final hasMeaningfulNarration = sanitizedReply.trim().isNotEmpty;
      final shouldPersistIntermediateAssistantNarration =
          hasMeaningfulNarration || didCancelStream;
      if (shouldPersistIntermediateAssistantNarration) {
        // Pull `<image_summary attachment_id="…">…</image_summary>` directives
        // out of the assistant's reply, write the summaries back into the
        // matching user-message attachments, and persist the cleaned text.
        final extraction = AiImageSummaryExtractor.extractAndStrip(
          result.reply,
        );
        if (extraction.summariesByAttachmentId.isNotEmpty) {
          streamedSession = _applyImageSummariesToSession(
            streamedSession,
            extraction.summariesByAttachmentId,
          );
        }
        streamedSession = syncFinalAssistantMessage(
          streamedSession,
          extraction.summariesByAttachmentId.isEmpty
              ? result.reply
              : extraction.strippedContent,
        );
      } else {
        // Only remove the intermediate message if it's truly empty after
        // sanitization (e.g., the AI only produced tool calls with no text).
        if (assistantMessageId != null) {
          streamedSession = _removeMessagesByIds(
            streamedSession,
            messageIds: <String>{
              if (assistantMessageId != null) assistantMessageId!,
            },
          );
        }
        assistantMessageId = null;
      }
      streamedSession = syncFinalReasoningMessage(
        streamedSession,
        result.reasoning,
      );
      streamedSession = setReasoningStreamingState(streamedSession, false);
      flushPreview('stream_completed');
      // Attach per-round telemetry (URL/method/headers/body/raw_response/
      // timings/environment + composed prompt) to the user+assistant+reasoning
      // messages produced this round so the audit dialog has real data to
      // show. Gated by the telemetryDebugEnabled setting.
      streamedSession = _applyRoundTelemetryToMessages(
        session: streamedSession,
        result: result,
        runtimeContext: runtimeContext,
        promptResult: promptResult,
        userMessageId: activeLatestUserMessageId,
        assistantMessageId: assistantMessageId,
        reasoningMessageId: reasoningMessageId,
      );
      _debugSessionLog(
        workingSession.id,
        'stream_completed cancelled=${result.wasCancelled} finish_reason=${result.finishReason ?? 'unknown'} truncated=${result.wasTruncated} reply_chars=${result.reply.length} reasoning_chars=${result.reasoning.length} tool_calls=${result.toolCalls.length}',
      );

      if (didCancelStream) {
        if (result.toolCalls.isNotEmpty) {
          streamedSession = _syncToolCallMessagesFromResult(
            streamedSession,
            result.toolCalls,
            model,
          );
        }
        streamedSession = _markPendingToolCallsCancelled(streamedSession);
      } else {
        streamedSession = _syncToolCallMessagesFromResult(
          streamedSession,
          result.toolCalls,
          model,
        );
      }
      final rebasedSession = _sessionById(workingSession.id) ?? workingSession;
      final effectiveUsage = streamedUsage ?? result.usage;
      // Stamp final usage onto both the assistant and triggering user message
      // so either audit entry can show token data for this round.
      if (effectiveUsage != null) {
        streamedSession = applyUsageToMessageIfPresent(
          streamedSession,
          messageId: assistantMessageId,
          usage: effectiveUsage,
        );
        streamedSession = applyUsageToMessageIfPresent(
          streamedSession,
          messageId: activeLatestUserMessageId,
          usage: effectiveUsage,
        );
      }
      final totalUsage = _usageFromStatistics(
        rebasedSession.statistics,
      ).merge(effectiveUsage ?? const AiTokenUsage());
      final runtimePromptMetadata = _promptMetadataWithRuntimeToolCatalog(
        baseMetadata: promptResult.metadata,
        session: streamedSession,
        toolCatalog: toolCatalogForRound,
        executionApprovedForSend: planModeExecutionApprovedForSend,
        recoveryInspectionRequired: planModeRecoveryInspectionRequired,
      );
      streamedSession = _rebuildSession(
        rebasedSession.copyWith(
          messages: streamedSession.messages,
          updatedAt: _clock().toUtc(),
          lastUsedModelId: model.id,
          lastUsedModelLabel: model.displayName,
          lastPromptMetadata: runtimePromptMetadata,
        ),
        totalPromptCharacters:
            rebasedSession.statistics.totalPromptCharacters +
            promptResult.promptCharacterCount,
        promptBuildCount: rebasedSession.statistics.promptBuildCount + 1,
        totalUsage: totalUsage,
        lastPromptSystemMessageCount: promptResult.systemMessageCount,
        lastPromptHistoryMessageCount: promptResult.historyMessageCount,
      );
      final committed = await _commitSessionLocked(streamedSession);
      if (!committed) {
        _setLastSendErrorMessage(
          workingSession.id,
          'Failed to persist the assistant reply.',
        );
        return false;
      }
      workingSession = streamedSession;

      if (didCancelStream) {
        final cancelledSession = await _commitCancelledPendingToolCalls(
          workingSession,
        );
        if (cancelledSession == null) {
          return false;
        }
        workingSession = cancelledSession;
        _debugSessionLog(workingSession.id, 'stream_exit_cancelled');
        return true;
      }

      if (_shouldFailEmptyPlanContinuationReply(
        session: workingSession,
        toolRoundCount: toolRoundCount,
        finalReply: _sanitizeVisibleModelContent(result.reply),
        hasToolCalls: result.toolCalls.isNotEmpty,
      )) {
        _debugSessionLog(
          workingSession.id,
          'stream_empty_plan_continuation_reply round=${toolRoundCount + 1}',
        );
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: 'chat_continuation_request',
          detail: _emptyPlanContinuationReplyError,
        );
        final failedSession = _appendError(
          workingSession,
          stage: 'chat_continuation_request',
          message: _emptyPlanContinuationReplyError,
          detail: _emptyPlanContinuationReplyError,
        );
        await _commitSessionLocked(_rebuildSession(failedSession));
        _setLastSendErrorMessage(
          workingSession.id,
          _emptyPlanContinuationReplyError,
        );
        notifyListeners();
        return false;
      }

      if (result.toolCalls.isEmpty) {
        // ── Auto-continuation for truncated model output ──────────────────
        // When the model hit its max output token limit (finish_reason ==
        // "length" / "max_tokens") and produced no tool calls, it was likely
        // cut off mid-thought.  Rather than silently stopping and forcing
        // the user to manually type "继续", we automatically inject a
        // continuation prompt and loop back.  A safety counter prevents
        // infinite truncation loops.
        if (result.wasTruncated &&
            !didCancelStream &&
            !workingSession.awaitingPlanApproval) {
          _truncationContinuationCount += 1;
          if (_truncationContinuationCount <= _maxTruncationContinuations) {
            _debugSessionLog(
              workingSession.id,
              'auto_continue_truncated round=${toolRoundCount + 1} '
              'truncation_count=$_truncationContinuationCount '
              'finish_reason=${result.finishReason}',
            );
            // Add a status message so the user can see that auto-
            // continuation happened, then loop back to the stream.
            final statusMessage = AiSessionMessage.status(
              id: _idGenerator(),
              content:
                  '[运行时 Notice] 模型输出被截断 (finish_reason: ${result.finishReason})，正在自动续接…',
              createdAt: _clock().toUtc(),
              metadata: const <String, Object?>{
                'auto_truncation_continue': true,
              },
            );
            workingSession = _rebuildSession(
              workingSession.copyWith(
                updatedAt: statusMessage.createdAt,
                messages: <AiSessionMessage>[
                  ...workingSession.messages,
                  statusMessage,
                ],
              ),
            );
            final truncCommitted = await _commitSessionLocked(workingSession);
            if (!truncCommitted) {
              _setLastSendErrorMessage(
                workingSession.id,
                'Failed to persist the truncation continuation state.',
              );
              return false;
            }
            toolRoundCount += 1;
            activeLatestUserMessageId = null;
            continue;
          }
          _debugSessionLog(
            workingSession.id,
            'truncation_continuation_limit_reached '
            'count=$_truncationContinuationCount '
            'limit=$_maxTruncationContinuations',
          );
        }
        // Reset the truncation counter once the model finishes normally.
        _truncationContinuationCount = 0;

        // ── Detect anomalous empty replies ────────────────────────────────
        // When the model produces NO visible content, NO reasoning, and NO
        // tool calls, and the stream was not cancelled, this is almost
        // certainly an error condition (content filter, empty API response,
        // abnormal stream close, rate limiting, etc.).  Rather than silently
        // returning success and making the user wonder what happened, we
        // surface an explicit error.
        final hasReply = sanitizedReply.trim().isNotEmpty;
        final hasReasoning = result.reasoning.trim().isNotEmpty;
        final isEmptyResponse = !hasReply && !hasReasoning && !didCancelStream;
        if (isEmptyResponse && !workingSession.awaitingPlanApproval) {
          // On the first round this is clearly anomalous — the model had
          // nothing to say in response to the user's message.  On subsequent
          // rounds an empty reply is suspicious if finishReason is absent
          // (abnormal stream close) or 'stop' with no content.
          final treatAsError = toolRoundCount == 0 ||
              result.finishReason == null ||
              result.finishReason!.isEmpty;
          if (treatAsError) {
            final errorDetail = result.finishReason == null
                ? 'The model returned an empty response and the stream closed without a finish reason. '
                    'This may indicate a network interruption, an API error, or a content filter.'
                : 'The model returned an empty response '
                    '(finish_reason: ${result.finishReason}). '
                    'This may indicate a content filter or an API-side issue.';
            _debugSessionLog(
              workingSession.id,
              'empty_response_detected round=${toolRoundCount + 1} '
              'finish_reason=${result.finishReason ?? 'null'} '
              'has_reply=$hasReply has_reasoning=$hasReasoning',
            );
            await _emitStopFailureHook(
              sessionId: workingSession.id,
              stage: 'chat_stream',
              detail: errorDetail,
            );
            final erroredSession = _appendError(
              workingSession,
              stage: 'chat_stream',
              message: errorDetail,
              detail: errorDetail,
            );
            await _commitSessionLocked(_rebuildSession(erroredSession));
            _setLastSendErrorMessage(workingSession.id, errorDetail);
            notifyListeners();
            return false;
          }
        }

        final settledPlanSession = _archiveCompletedPlanStateIfNeeded(
          workingSession,
        );
        if (!identical(settledPlanSession, workingSession)) {
          final committed = await _commitSessionLocked(settledPlanSession);
          if (!committed) {
            _setLastSendErrorMessage(
              workingSession.id,
              'Failed to persist the completed plan state.',
            );
            return false;
          }
          workingSession = settledPlanSession;
        }
        _debugSessionLog(
          workingSession.id,
          'assistant_waiting_for_user reason=${workingSession.awaitingPlanApproval ? 'plan_approval' : 'completed'}',
        );
        await _emitStopHooks(
          sessionId: workingSession.id,
          reason: workingSession.awaitingPlanApproval
              ? 'plan_approval'
              : 'completed',
          awaitingUserInput: true,
        );
        return true;
      }
      // Model produced tool calls — reset the truncation counter since
      // the model is making normal progress.
      _truncationContinuationCount = 0;
      toolCallCount += result.toolCalls.length;
      if (toolCallCount > singleRoundToolCallLimit) {
        _debugSessionLog(
          workingSession.id,
          'tool_call_limit_exceeded count=$toolCallCount limit=$singleRoundToolCallLimit',
        );
        final limitedToolSession = _markPendingToolCallsFailed(
          workingSession,
          detail:
              'The tool call was stopped because the assistant exceeded the per-response tool call limit.',
        );
        final warningMessage = AiSessionMessage.status(
          id: _idGenerator(),
          content: _toolCallLimitWarningMessage(
            runtimeContext: runtimeContext,
            toolCallCount: toolCallCount,
            limit: singleRoundToolCallLimit,
          ),
          createdAt: _clock().toUtc(),
          metadata: <String, Object?>{
            'tool_call_limit_exceeded': true,
            'tool_call_count': toolCallCount,
            'tool_call_limit': singleRoundToolCallLimit,
          },
        );
        final limitedSession = _rebuildSession(
          limitedToolSession.copyWith(
            updatedAt: warningMessage.createdAt,
            messages: <AiSessionMessage>[
              ...limitedToolSession.messages,
              warningMessage,
            ],
          ),
        );
        final committed = await _commitSessionLocked(limitedSession);
        if (!committed) {
          _setLastSendErrorMessage(
            workingSession.id,
            'Failed to persist the tool-call limit warning.',
          );
          return false;
        }
        await _emitStopHooks(
          sessionId: workingSession.id,
          reason: 'tool_call_limit',
          awaitingUserInput: true,
        );
        return true;
      }
      toolRoundCount += 1;
      if (toolRoundCount > sequentialToolRoundLimit) {
        _debugSessionLog(
          workingSession.id,
          'tool_round_limit_exceeded count=$toolRoundCount limit=$sequentialToolRoundLimit',
        );
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: 'tool_loop',
          detail:
              'tool_round_count=$toolRoundCount limit=$sequentialToolRoundLimit',
        );
        final failedToolSession = _markPendingToolCallsFailed(
          workingSession,
          detail:
              'The tool call was stopped before execution because the assistant exceeded the configured sequential tool round safety limit of $sequentialToolRoundLimit rounds.',
        );
        final limitedSession = _appendError(
          failedToolSession,
          stage: 'tool_loop',
          message:
              'The assistant requested too many sequential tool rounds and was stopped for safety.',
          detail:
              'tool_round_count=$toolRoundCount limit=$sequentialToolRoundLimit',
        );
        await _commitSessionLocked(_rebuildSession(limitedSession));
        _setLastSendErrorMessage(
          workingSession.id,
          'The assistant requested too many sequential tool rounds and was stopped for safety.',
        );
        return false;
      }

      final executedSession = await _executeToolCalls(
        session: workingSession,
        model: model,
        toolCatalog: toolCatalogForRound,
        toolCalls: result.toolCalls,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
      );
      if (executedSession == null) {
        final executionError =
            lastErrorMessageForSession(workingSession.id) ??
            'Tool execution failed.';
        _debugSessionLog(
          workingSession.id,
          'tool_execution_failed error=$executionError',
        );
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: 'tool_execution',
          detail: executionError,
        );
        return false;
      }
      workingSession = executedSession;
      if (planModeRecoveryInspectionRequired &&
          _roundRequestedTodoWrite(result.toolCalls)) {
        planModeRecoveryInspectionRequired =
            _shouldRequirePlanModeRecoveryInspection(
              session: workingSession,
              latestUserMessageId: latestUserMessageId,
            );
        planModeExecutionApprovedForSend = _shouldAllowPlanModeExecutionTools(
          session: workingSession,
          latestUserMessageId: latestUserMessageId,
        );
      }
      activeLatestUserMessageId = null;
      if (_isStopRequestedForSession(workingSession.id)) {
        _debugSessionLog(
          workingSession.id,
          'assistant_conversation_stopped_after_tools',
        );
        return true;
      }
    }
  }

  Future<AiSession?> _executeToolCalls({
    required AiSession session,
    required AiModelConfig model,
    required AiResolvedToolCatalog toolCatalog,
    required List<AiToolCall> toolCalls,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    if (_isStopRequestedForSession(session.id)) {
      return _commitCancelledPendingToolCalls(session);
    }
    if (_shouldExecuteToolCallsInParallel(
      toolCatalog: toolCatalog,
      toolCalls: toolCalls,
    )) {
      _debugSessionLog(
        session.id,
        'tool_execution_parallel count=${toolCalls.length}',
      );
      return _executeToolCallsInParallel(
        session: session,
        model: model,
        toolCatalog: toolCatalog,
        toolCalls: toolCalls,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
      );
    }
    var workingSession = session;
    for (final toolCall in toolCalls) {
      if (_isStopRequestedForSession(workingSession.id)) {
        return _commitCancelledPendingToolCalls(workingSession);
      }
      _debugSessionLog(
        workingSession.id,
        'tool_execution_start tool=${toolCall.name} tool_call_id=${toolCall.id}',
      );
      final command = _toolCallCommand(toolCall);
      final workingDirectory = _toolCallWorkingDirectory(toolCall);
      final toolCallMessageId = _resolveToolCallMessageId(
        workingSession,
        toolCall,
      );
      workingSession = _syncToolCallExecutionMessage(
        session: workingSession,
        messageId: toolCallMessageId,
        toolCall: toolCall,
        command: command,
        workingDirectory: workingDirectory,
        status: 'running',
        stdout: '',
        stderr: '',
        elapsedMs: 0,
      );
      final runningCommitted = await _commitSessionLocked(workingSession);
      if (!runningCommitted) {
        _setLastSendErrorMessage(
          workingSession.id,
          'Failed to persist the running tool-call state.',
        );
        return null;
      }
      await _safeRunUserHook(
        event: HookEvent.preToolUse,
        sessionId: workingSession.id,
        payload: <String, Object?>{
          'tool_name': toolCall.name,
          'tool_arguments': toolCall.arguments,
        },
      );
      final result = await _executeSingleToolCall(
        sessionId: workingSession.id,
        toolCall: toolCall,
        model: model,
        toolCatalog: toolCatalog,
        readFilePaths: _readFileHistory(workingSession),
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
        onUpdate: (update) {
          if (update.phase != BashToolExecutionPhase.running) {
            return;
          }
          workingSession = _syncToolCallExecutionMessage(
            session: workingSession,
            messageId: toolCallMessageId,
            toolCall: toolCall,
            command: update.command,
            workingDirectory: update.workingDirectory,
            status: 'running',
            stdout: update.stdout,
            stderr: update.stderr,
            elapsedMs: update.durationMs,
          );
          _previewSession(workingSession);
        },
      );
      workingSession = _syncToolCallExecutionMessage(
        session: workingSession,
        messageId: toolCallMessageId,
        toolCall: toolCall,
        command: result.command,
        workingDirectory: result.workingDirectory,
        status: result.status.storageValue,
        stdout: result.stdout,
        stderr: result.stderr,
        elapsedMs: result.durationMs,
        exitCode: result.exitCode,
        resultText: result.toToolOutput(),
        finishedAt: _clock().toUtc(),
        matchedRuleId: result.matchedRuleId,
        matchedRulePattern: result.matchedRulePattern,
        isWriteCommand: result.isWriteCommand,
        writeAnalysisReason: result.writeAnalysisReason,
        additionalMetadata: result.metadata,
      );
      final toolMessageMetadata = <String, Object?>{
        'tool_call_id': toolCall.id,
        'tool_name': toolCall.name,
        'tool_arguments': toolCall.arguments,
        'command': result.command,
        'working_directory': result.workingDirectory,
        'status': result.status.storageValue,
        'exit_code': result.exitCode,
        'duration_ms': result.durationMs,
        'stdout': result.stdout,
        'stderr': result.stderr,
        'result_text': result.toToolOutput(),
        'matched_rule_id': result.matchedRuleId,
        'matched_rule_pattern': result.matchedRulePattern,
        'is_write_command': result.isWriteCommand,
        'write_analysis_reason': result.writeAnalysisReason,
        ...result.metadata,
      };
      final toolMessage = _buildToolResultMessage(
        toolCall: toolCall,
        result: result,
        metadata: toolMessageMetadata,
      );
      final updatedTodoItems = _applyTodoState(
        currentTodoItems: workingSession.todoItems,
        toolResultMetadata: toolMessageMetadata,
      );
      workingSession = _rebuildSession(
        workingSession.copyWith(
          updatedAt: toolMessage.createdAt,
          todoItems: updatedTodoItems,
          awaitingPlanApproval:
              toolMessageMetadata['plan_mode_awaiting_approval'] == true
              ? true
              : workingSession.awaitingPlanApproval,
          pendingPlan:
              toolMessageMetadata['plan_mode_awaiting_approval'] == true
              ? '${toolMessageMetadata['pending_plan'] ?? ''}'.trim()
              : workingSession.pendingPlan,
          messages: <AiSessionMessage>[...workingSession.messages, toolMessage],
        ),
      );
      final committed = await _commitSessionLocked(workingSession);
      if (!committed) {
        _setLastSendErrorMessage(
          workingSession.id,
          'Failed to persist the tool execution result.',
        );
        return null;
      }
      _debugSessionLog(
        workingSession.id,
        'tool_execution_finish tool=${toolCall.name} status=${result.status.storageValue}',
      );
      await _safeRunUserHook(
        event: HookEvent.postToolUse,
        sessionId: workingSession.id,
        payload: <String, Object?>{
          'tool_name': toolCall.name,
          'status': result.status.storageValue,
          'duration_ms': result.durationMs,
        },
      );
      // Re-read session since _safeRunUserHook may have committed new messages.
      workingSession = _sessionById(workingSession.id) ?? workingSession;
      if (result.status == BashToolExecutionStatus.cancelled ||
          _isStopRequestedForSession(workingSession.id)) {
        return _commitCancelledPendingToolCalls(workingSession);
      }
    }
    return workingSession;
  }

  Future<AiSession?> _executeToolCallsInParallel({
    required AiSession session,
    required AiModelConfig model,
    required AiResolvedToolCatalog toolCatalog,
    required List<AiToolCall> toolCalls,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    var workingSession = session;
    final runningStates = <_RunningToolCallState>[];
    for (final toolCall in toolCalls) {
      _debugSessionLog(
        workingSession.id,
        'tool_execution_start tool=${toolCall.name} tool_call_id=${toolCall.id}',
      );
      final command = _toolCallCommand(toolCall);
      final workingDirectory = _toolCallWorkingDirectory(toolCall);
      final toolCallMessageId = _resolveToolCallMessageId(
        workingSession,
        toolCall,
      );
      workingSession = _syncToolCallExecutionMessage(
        session: workingSession,
        messageId: toolCallMessageId,
        toolCall: toolCall,
        command: command,
        workingDirectory: workingDirectory,
        status: 'running',
        stdout: '',
        stderr: '',
        elapsedMs: 0,
      );
      runningStates.add(
        _RunningToolCallState(
          toolCall: toolCall,
          messageId: toolCallMessageId,
          executionSessionId: _parallelExecutionSessionId(
            parentSessionId: workingSession.id,
            toolCatalog: toolCatalog,
            toolCall: toolCall,
          ),
        ),
      );
    }
    final runningCommitted = await _commitSessionLocked(workingSession);
    if (!runningCommitted) {
      _setLastSendErrorMessage(
        workingSession.id,
        'Failed to persist the running tool-call state.',
      );
      return null;
    }
    final readFilePaths = _readFileHistory(workingSession);
    final results = await Future.wait(
      runningStates.map(
        (state) => _executeSingleToolCall(
          sessionId: workingSession.id,
          executionSessionId: state.executionSessionId,
          toolCall: state.toolCall,
          model: model,
          toolCatalog: toolCatalog,
          readFilePaths: readFilePaths,
          denyCommandRules: denyCommandRules,
          requireWriteCommandConfirmation: requireWriteCommandConfirmation,
          confirmWriteCommand: confirmWriteCommand,
          onUpdate: (update) {
            if (update.phase != BashToolExecutionPhase.running) {
              return;
            }
            workingSession = _syncToolCallExecutionMessage(
              session: workingSession,
              messageId: state.messageId,
              toolCall: state.toolCall,
              command: update.command,
              workingDirectory: update.workingDirectory,
              status: 'running',
              stdout: update.stdout,
              stderr: update.stderr,
              elapsedMs: update.durationMs,
            );
            _previewSession(workingSession);
          },
        ),
      ),
    );
    for (var index = 0; index < runningStates.length; index++) {
      final state = runningStates[index];
      final result = results[index];
      workingSession = _syncToolCallExecutionMessage(
        session: workingSession,
        messageId: state.messageId,
        toolCall: state.toolCall,
        command: result.command,
        workingDirectory: result.workingDirectory,
        status: result.status.storageValue,
        stdout: result.stdout,
        stderr: result.stderr,
        elapsedMs: result.durationMs,
        exitCode: result.exitCode,
        resultText: result.toToolOutput(),
        finishedAt: _clock().toUtc(),
        matchedRuleId: result.matchedRuleId,
        matchedRulePattern: result.matchedRulePattern,
        isWriteCommand: result.isWriteCommand,
        writeAnalysisReason: result.writeAnalysisReason,
        additionalMetadata: result.metadata,
      );
      final toolMessageMetadata = <String, Object?>{
        'tool_call_id': state.toolCall.id,
        'tool_name': state.toolCall.name,
        'tool_arguments': state.toolCall.arguments,
        'command': result.command,
        'working_directory': result.workingDirectory,
        'status': result.status.storageValue,
        'exit_code': result.exitCode,
        'duration_ms': result.durationMs,
        'stdout': result.stdout,
        'stderr': result.stderr,
        'result_text': result.toToolOutput(),
        'matched_rule_id': result.matchedRuleId,
        'matched_rule_pattern': result.matchedRulePattern,
        'is_write_command': result.isWriteCommand,
        'write_analysis_reason': result.writeAnalysisReason,
        ...result.metadata,
      };
      final toolMessage = _buildToolResultMessage(
        toolCall: state.toolCall,
        result: result,
        metadata: toolMessageMetadata,
      );
      final updatedTodoItems = _applyTodoState(
        currentTodoItems: workingSession.todoItems,
        toolResultMetadata: toolMessageMetadata,
      );
      workingSession = _rebuildSession(
        workingSession.copyWith(
          updatedAt: toolMessage.createdAt,
          todoItems: updatedTodoItems,
          awaitingPlanApproval:
              toolMessageMetadata['plan_mode_awaiting_approval'] == true
              ? true
              : workingSession.awaitingPlanApproval,
          pendingPlan:
              toolMessageMetadata['plan_mode_awaiting_approval'] == true
              ? '${toolMessageMetadata['pending_plan'] ?? ''}'.trim()
              : workingSession.pendingPlan,
          messages: <AiSessionMessage>[...workingSession.messages, toolMessage],
        ),
      );
    }
    final committed = await _commitSessionLocked(workingSession);
    if (!committed) {
      _setLastSendErrorMessage(
        workingSession.id,
        'Failed to persist the tool execution result.',
      );
      return null;
    }
    for (final result in results) {
      _debugSessionLog(
        workingSession.id,
        'tool_execution_finish status=${result.status.storageValue} command=${result.command}',
      );
    }
    return workingSession;
  }

  Future<AiToolExecutionResult> _executeSingleToolCall({
    required String sessionId,
    String? executionSessionId,
    required AiToolCall toolCall,
    required AiModelConfig model,
    required AiResolvedToolCatalog toolCatalog,
    required Set<String> readFilePaths,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
  }) async {
    try {
      final currentSession = _sessionById(sessionId);
      final isFullAccess = currentSession?.fullAccessPermission == true;
      return await _toolRuntimeService.execute(
        sessionId: executionSessionId ?? sessionId,
        catalog: toolCatalog,
        toolCall: toolCall,
        model: model,
        previouslyReadFiles: readFilePaths,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: isFullAccess
            ? false
            : requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
        cancelSignal: _stopSignalForSession(sessionId),
        onBashUpdate: onUpdate,
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: toolCall.name,
        workingDirectory: _toolCallWorkingDirectory(toolCall),
        stdout: '',
        stderr: '$error',
        durationMs: 0,
        resultText: 'status: failed\nerror: $error',
      );
    }
  }

  String _toolCallCommand(AiToolCall toolCall) {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    final command =
        '${decodedArguments['cmd'] ?? decodedArguments['command'] ?? ''}'
            .trim();
    if (command.isNotEmpty) {
      return command;
    }
    final normalizedToolName = toolCall.name.trim().toLowerCase();
    if (normalizedToolName == 'websearch') {
      final query = '${decodedArguments['query'] ?? ''}'.trim();
      if (query.isNotEmpty) {
        return 'WebSearch $query';
      }
    }
    return toolCall.name;
  }

  String _toolCallWorkingDirectory(AiToolCall toolCall) {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    final workingDirectory =
        '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
            .trim();
    if (workingDirectory.isNotEmpty) {
      return workingDirectory;
    }
    if (toolCall.name.trim().toLowerCase() == 'websearch') {
      return OpenHandPaths.applicationDirectoryPath();
    }
    return '';
  }

  bool _shouldExecuteToolCallsInParallel({
    required AiResolvedToolCatalog toolCatalog,
    required List<AiToolCall> toolCalls,
  }) {
    if (toolCalls.length < 2) {
      return false;
    }
    return toolCalls.every(
      (toolCall) => _isParallelizableToolCall(
        toolCatalog: toolCatalog,
        toolCall: toolCall,
      ),
    );
  }

  bool _isParallelizableToolCall({
    required AiResolvedToolCatalog toolCatalog,
    required AiToolCall toolCall,
  }) {
    final resolvedTool = toolCatalog.find(toolCall.name);
    if (resolvedTool == null ||
        resolvedTool.source != AiRuntimeToolSource.builtin) {
      return false;
    }
    switch (resolvedTool.builtinKind) {
      case AiBuiltinToolKind.read:
      case AiBuiltinToolKind.ls:
      case AiBuiltinToolKind.glob:
      case AiBuiltinToolKind.grep:
      case AiBuiltinToolKind.webFetch:
      case AiBuiltinToolKind.webSearch:
      case AiBuiltinToolKind.lsp:
      case AiBuiltinToolKind.task:
      case AiBuiltinToolKind.codebaseSearch:
      case AiBuiltinToolKind.git:
      case AiBuiltinToolKind.readLints:
        return true;
      case AiBuiltinToolKind.bash:
        return !_bashToolService
            .analyzeWriteCommand(_toolCallCommand(toolCall))
            .isWrite;
      case null:
      case AiBuiltinToolKind.exitPlanMode:
      case AiBuiltinToolKind.edit:
      case AiBuiltinToolKind.multiEdit:
      case AiBuiltinToolKind.write:
      case AiBuiltinToolKind.notebookEdit:
      case AiBuiltinToolKind.todoWrite:
      case AiBuiltinToolKind.deleteFile:
        return false;
    }
  }

  String _parallelExecutionSessionId({
    required String parentSessionId,
    required AiResolvedToolCatalog toolCatalog,
    required AiToolCall toolCall,
  }) {
    final resolvedTool = toolCatalog.find(toolCall.name);
    return switch (resolvedTool?.builtinKind) {
      AiBuiltinToolKind.bash =>
        '$parentSessionId::parallel-bash::${toolCall.id}',
      AiBuiltinToolKind.task =>
        '$parentSessionId::parallel-task::${toolCall.id}',
      _ => parentSessionId,
    };
  }

  Set<String> _readFileHistory(AiSession session) {
    final filePaths = <String>{};
    for (final message in session.messages) {
      final filePath = '${message.metadata['read_file_path'] ?? ''}'.trim();
      if (filePath.isNotEmpty) {
        filePaths.add(filePath);
      }
    }
    return filePaths;
  }

  Future<AiSession?> _maybePrefetchClaudeCodeDocs({
    required AiSession session,
    required AiModelConfig model,
    required AiResolvedToolCatalog toolCatalog,
    required String? latestUserMessageId,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    final userMessageId = latestUserMessageId?.trim() ?? '';
    if (userMessageId.isEmpty) {
      return session;
    }
    AiSessionMessage? latestUserMessage;
    for (final message in session.messages) {
      if (!message.isDeleted &&
          message.kind == AiSessionMessageKind.user &&
          message.id == userMessageId) {
        latestUserMessage = message;
        break;
      }
    }
    if (latestUserMessage == null ||
        !_looksLikeClaudeCodeProductQuestion(latestUserMessage.content)) {
      return session;
    }
    if (toolCatalog.find('WebFetch') == null) {
      return session;
    }
    final alreadyPrefetched = session.messages.any(
      (message) =>
          '${message.metadata['claude_code_docs_prefetch_for_user_message_id'] ?? ''}'
              .trim() ==
          userMessageId,
    );
    if (alreadyPrefetched) {
      return session;
    }
    var workingSession = session;
    final docsTargets = _claudeCodeDocsTargetsForQuestion(
      latestUserMessage.content,
    );
    final readFilePaths = _readFileHistory(session);
    for (var index = 0; index < docsTargets.length; index++) {
      final target = docsTargets[index];
      final toolCall = AiToolCall(
        id: 'claude-docs-prefetch-$userMessageId-$index',
        name: 'WebFetch',
        arguments: jsonEncode(<String, Object?>{
          'url': target.url,
          'prompt':
              'Summarize only the official Claude Code documentation details that are relevant to the following user question. Focus on documented behavior, supported workflows, and exact terminology.\n\nUser question:\n${latestUserMessage.content.trim()}\n\nCurrent documentation focus: ${target.label}',
        }),
      );
      final result = await _executeSingleToolCall(
        sessionId: workingSession.id,
        toolCall: toolCall,
        model: model,
        toolCatalog: toolCatalog,
        readFilePaths: readFilePaths,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
      );
      final messageId = _resolveToolCallMessageId(workingSession, toolCall);
      workingSession = _syncToolCallExecutionMessage(
        session: workingSession,
        messageId: messageId,
        toolCall: toolCall,
        command: result.command,
        workingDirectory: result.workingDirectory,
        status: result.status.storageValue,
        stdout: result.stdout,
        stderr: result.stderr,
        elapsedMs: result.durationMs,
        exitCode: result.exitCode,
        resultText: result.toToolOutput(),
        finishedAt: _clock().toUtc(),
        matchedRuleId: result.matchedRuleId,
        matchedRulePattern: result.matchedRulePattern,
        isWriteCommand: result.isWriteCommand,
        writeAnalysisReason: result.writeAnalysisReason,
        additionalMetadata: result.metadata,
      );
      final toolMessageMetadata = <String, Object?>{
        'tool_call_id': toolCall.id,
        'tool_name': toolCall.name,
        'tool_arguments': toolCall.arguments,
        'command': result.command,
        'working_directory': result.workingDirectory,
        'status': result.status.storageValue,
        'exit_code': result.exitCode,
        'duration_ms': result.durationMs,
        'stdout': result.stdout,
        'stderr': result.stderr,
        'result_text': result.toToolOutput(),
        'matched_rule_id': result.matchedRuleId,
        'matched_rule_pattern': result.matchedRulePattern,
        'is_write_command': result.isWriteCommand,
        'write_analysis_reason': result.writeAnalysisReason,
        'claude_code_docs_prefetch': true,
        'claude_code_docs_prefetch_url': target.url,
        'claude_code_docs_prefetch_label': target.label,
        'claude_code_docs_prefetch_for_user_message_id': userMessageId,
        ...result.metadata,
      };
      final toolMessage = _buildToolResultMessage(
        toolCall: toolCall,
        result: result,
        metadata: toolMessageMetadata,
      );
      workingSession = _rebuildSession(
        workingSession.copyWith(
          updatedAt: toolMessage.createdAt,
          messages: <AiSessionMessage>[...workingSession.messages, toolMessage],
        ),
      );
      final committed = await _commitSessionLocked(workingSession);
      if (!committed) {
        _setLastSendErrorMessage(
          workingSession.id,
          'Failed to persist the Claude Code documentation prefetch.',
        );
        return null;
      }
    }
    return workingSession;
  }

  bool _looksLikeClaudeCodeProductQuestion(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final mentionsClaudeCode =
        normalized.contains('claude code') ||
        normalized.contains('claude-code') ||
        normalized.contains('claudecode');
    if (!mentionsClaudeCode) {
      return false;
    }
    const negativeSignals = <String>[
      '迁移',
      '移植',
      '集成',
      '仿照',
      '参考',
      '学习',
      'prompt',
      '提示词',
    ];
    const questionSignals = <String>[
      '?',
      '？',
      'what',
      'how',
      'why',
      'when',
      'where',
      'can ',
      'does ',
      'is ',
      'help',
      'docs',
      'documentation',
      'guide',
      'manual',
      'behavior',
      'capability',
      'capabilities',
      'feature',
      'features',
      'hook',
      'hooks',
      'tool',
      'tools',
      'skill',
      'skills',
      'permission',
      'plan mode',
      'slash',
      '如何',
      '怎么',
      '文档',
      '用法',
      '能力',
      '行为',
      '规则',
      '配置',
      '工具',
      '技能',
      '权限',
      '计划模式',
      '支持',
      '是什么',
      '能不能',
      '是否',
    ];
    if (questionSignals.any(normalized.contains)) {
      return true;
    }
    if (negativeSignals.any(normalized.contains)) {
      return false;
    }
    const secondPersonProductSignals = <String>[
      'mcp',
      'hook',
      'hooks',
      'memory',
      'claude.md',
      'permission',
      'permissions',
      'settings',
      'slash',
      'command',
      'commands',
      'tool',
      'tools',
      'plan mode',
      'interactive mode',
      'keyboard shortcut',
      '快捷键',
      '配置',
      '文档',
      '工具',
      '技能',
      '权限',
      '命令',
      '计划模式',
    ];
    const secondPersonSignals = <String>[
      'can you',
      'do you',
      'are you able',
      'are you',
      '你能',
      '你是否',
      '你可以',
    ];
    return secondPersonSignals.any(normalized.contains) &&
        secondPersonProductSignals.any(normalized.contains);
  }

  List<_ClaudeCodeDocsTarget> _claudeCodeDocsTargetsForQuestion(
    String content,
  ) {
    const baseUrl = 'https://docs.anthropic.com/en/docs/claude-code';
    final normalized = content.trim().toLowerCase();
    final urls = <_ClaudeCodeDocsTarget>[
      const _ClaudeCodeDocsTarget(url: baseUrl, label: 'overview'),
    ];
    final specificRoutes = _claudeCodeDocsSubpagesForQuestion(normalized);
    for (final specificRoute in specificRoutes) {
      urls.add(
        _ClaudeCodeDocsTarget(
          url: '$baseUrl/$specificRoute',
          label: specificRoute,
        ),
      );
    }
    final deduplicated = <String>{};
    return urls
        .where((item) => deduplicated.add(item.url))
        .toList(growable: false);
  }

  List<String> _claudeCodeDocsSubpagesForQuestion(String normalizedContent) {
    const routes = <MapEntry<String, List<String>>>[
      MapEntry<String, List<String>>('hooks', <String>['hook', 'hooks']),
      MapEntry<String, List<String>>('slash-commands', <String>[
        'slash command',
        'slash commands',
        '/help',
        '/memory',
        '/mcp',
        '/settings',
        '/status',
      ]),
      MapEntry<String, List<String>>('cli-reference', <String>[
        'cli',
        'cli reference',
        'flag',
        'flags',
        'command line',
      ]),
      MapEntry<String, List<String>>('interactive-mode', <String>[
        'interactive mode',
        'keyboard',
        'shortcut',
        'shortcuts',
        '快捷键',
      ]),
      MapEntry<String, List<String>>('memory', <String>[
        'memory',
        'claude.md',
        'agents.md',
      ]),
      MapEntry<String, List<String>>('mcp', <String>[
        'mcp',
        'model context protocol',
      ]),
      MapEntry<String, List<String>>('settings', <String>[
        'setting',
        'settings',
        'settings json',
        'settings file',
        'settings.local.json',
        'env var',
        'env vars',
        'environment variable',
        'tools json',
        '设置',
      ]),
      MapEntry<String, List<String>>('iam', <String>[
        'auth',
        'authentication',
        'authorization',
        'permission',
        'permissions',
        'token',
        'oauth',
        '登录',
        '权限',
      ]),
      MapEntry<String, List<String>>('security', <String>[
        'security',
        'sandbox',
        '安全',
      ]),
      MapEntry<String, List<String>>('monitoring-usage', <String>[
        'monitoring',
        'usage',
        'otel',
        'telemetry',
        '监控',
      ]),
      MapEntry<String, List<String>>('costs', <String>[
        'cost',
        'costs',
        'pricing',
        'bill',
      ]),
      MapEntry<String, List<String>>('ide-integrations', <String>[
        'ide',
        'vscode',
        'jetbrains',
      ]),
      MapEntry<String, List<String>>('common-workflows', <String>[
        'workflow',
        'workflows',
        'resume',
        'extended thinking',
        'image',
        'pasting images',
      ]),
      MapEntry<String, List<String>>('quickstart', <String>[
        'install',
        'setup',
        'quickstart',
        'getting started',
      ]),
      MapEntry<String, List<String>>('github-actions', <String>[
        'github action',
        'github actions',
      ]),
      MapEntry<String, List<String>>('sdk', <String>['sdk']),
      MapEntry<String, List<String>>('troubleshooting', <String>[
        'troubleshoot',
        'troubleshooting',
        'error',
        'issue',
        'problem',
        'debugging',
      ]),
      MapEntry<String, List<String>>('third-party-integrations', <String>[
        'third-party',
        'third party',
        'integration',
        'integrations',
      ]),
      MapEntry<String, List<String>>('amazon-bedrock', <String>['bedrock']),
      MapEntry<String, List<String>>('google-vertex-ai', <String>['vertex']),
      MapEntry<String, List<String>>('corporate-proxy', <String>['proxy']),
      MapEntry<String, List<String>>('llm-gateway', <String>['gateway']),
      MapEntry<String, List<String>>('devcontainer', <String>[
        'devcontainer',
        'dev container',
      ]),
    ];
    final scoredRoutes = <_ScoredClaudeCodeDocsRoute>[];
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index];
      final matchedKeywords = route.value
          .where(normalizedContent.contains)
          .toList(growable: false);
      if (matchedKeywords.isEmpty) {
        continue;
      }
      scoredRoutes.add(
        _ScoredClaudeCodeDocsRoute(
          route: route.key,
          score: matchedKeywords.length,
          priority: index,
        ),
      );
    }
    scoredRoutes.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return left.priority.compareTo(right.priority);
    });
    return scoredRoutes
        .take(2)
        .map((item) => item.route)
        .toList(growable: false);
  }

  AiSessionMessage _buildToolResultMessage({
    required AiToolCall toolCall,
    required AiToolExecutionResult result,
    required Map<String, Object?> metadata,
  }) {
    final createdAt = _clock().toUtc();
    final toolSource = '${result.metadata['tool_source'] ?? ''}'.trim();
    if (toolSource == 'mcp') {
      return AiSessionMessage.mcpResult(
        id: _idGenerator(),
        content: result.toToolOutput(),
        createdAt: createdAt,
        metadata: metadata,
      );
    }
    if (toolSource == 'skill') {
      return AiSessionMessage.skillResult(
        id: _idGenerator(),
        content: result.toToolOutput(),
        createdAt: createdAt,
        metadata: metadata,
      );
    }
    return AiSessionMessage.toolResult(
      id: _idGenerator(),
      content: result.toToolOutput(),
      createdAt: createdAt,
      metadata: metadata,
    );
  }

  List<AiSessionTodoItem> _applyTodoState({
    required List<AiSessionTodoItem> currentTodoItems,
    required Map<String, Object?> toolResultMetadata,
  }) {
    final todoListReplaced = toolResultMetadata['todo_list_replaced'] == true;
    final rawTodoItems = toolResultMetadata['todo_items'];
    if (rawTodoItems is! List) {
      return currentTodoItems;
    }
    final nextTodoItems = rawTodoItems
        .map((item) {
          if (item is! Map) {
            return null;
          }
          final todoMap = Map<String, Object?>.from(item);
          final id = '${todoMap['id'] ?? ''}'.trim();
          final content = '${todoMap['content'] ?? ''}'.trim();
          final status = '${todoMap['status'] ?? ''}'.trim();
          if (id.isEmpty || content.isEmpty || status.isEmpty) {
            return null;
          }
          return AiSessionTodoItem(id: id, content: content, status: status);
        })
        .whereType<AiSessionTodoItem>()
        .toList(growable: false);
    if (nextTodoItems.isNotEmpty) {
      return nextTodoItems;
    }
    return todoListReplaced ? const <AiSessionTodoItem>[] : currentTodoItems;
  }

  AiResolvedToolCatalog _toolCatalogForRound({
    required AiSession session,
    required AiResolvedToolCatalog baseCatalog,
    required bool executionApprovedForSend,
    required bool recoveryInspectionRequired,
  }) {
    if (session.mode != AiSessionMode.plan) {
      return baseCatalog;
    }
    if (executionApprovedForSend) {
      final filteredEntries = baseCatalog.toolsByName.entries
          .where((entry) => _normalizeToolName(entry.key) != 'exitplanmode')
          .toList(growable: false);
      return AiResolvedToolCatalog(
        definitions: filteredEntries
            .map((entry) => entry.value.definition)
            .toList(growable: false),
        toolsByName: Map<String, AiResolvedTool>.fromEntries(filteredEntries),
        notices: baseCatalog.notices,
      );
    }
    final allowExitPlanMode =
        !recoveryInspectionRequired &&
        _hasIncompleteTodoItems(session.todoItems);
    final filteredEntries = baseCatalog.toolsByName.entries
        .where(
          (entry) => _isAllowedPlanModePlanningTool(
            entry.key,
            allowExitPlanMode: allowExitPlanMode,
          ),
        )
        .toList(growable: false);
    return AiResolvedToolCatalog(
      definitions: filteredEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(filteredEntries),
      notices: baseCatalog.notices,
    );
  }

  Map<String, Object?> _promptMetadataWithRuntimeToolCatalog({
    required Map<String, Object?> baseMetadata,
    required AiSession session,
    required AiResolvedToolCatalog toolCatalog,
    required bool executionApprovedForSend,
    required bool recoveryInspectionRequired,
  }) {
    final toolNames = toolCatalog.definitions
        .map((tool) => tool.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return <String, Object?>{
      ...baseMetadata,
      'tool_catalog_authoritative': true,
      'session_mode': session.mode.storageValue,
      'plan_mode_active': session.mode == AiSessionMode.plan,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'current_todo_count': session.todoItems.length,
      'current_todos': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'current_tool_count': toolNames.length,
      'current_tool_names': toolNames,
      'runtime_tool_catalog_stale': false,
      'runtime_tool_catalog_notices': toolCatalog.notices,
      'runtime_tool_gate_reason': _runtimeToolCatalogGateReason(
        session: session,
        toolCatalog: toolCatalog,
        executionApprovedForSend: executionApprovedForSend,
        recoveryInspectionRequired: recoveryInspectionRequired,
      ),
      'plan_mode_execution_approved_for_send': executionApprovedForSend,
      'plan_mode_recovery_inspection_required': recoveryInspectionRequired,
    };
  }

  Map<String, Object?> _markRuntimeToolCatalogMetadataStale({
    required Map<String, Object?> baseMetadata,
    required AiSession session,
    required AiSessionMode mode,
  }) {
    return <String, Object?>{
      ...baseMetadata,
      'tool_catalog_authoritative': false,
      'session_mode': mode.storageValue,
      'plan_mode_active': mode == AiSessionMode.plan,
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'current_todo_count': session.todoItems.length,
      'current_todos': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
      'runtime_tool_catalog_stale': true,
      'runtime_tool_catalog_notices': const <String>[],
      'runtime_tool_gate_reason': 'mode_switch_requires_refresh',
    };
  }

  String _runtimeToolCatalogGateReason({
    required AiSession session,
    required AiResolvedToolCatalog toolCatalog,
    required bool executionApprovedForSend,
    required bool recoveryInspectionRequired,
  }) {
    if (session.awaitingPlanApproval) {
      return 'awaiting_plan_approval';
    }
    if (session.mode != AiSessionMode.plan) {
      return toolCatalog.definitions.isEmpty
          ? 'chat_mode_no_tools'
          : 'chat_mode';
    }
    if (recoveryInspectionRequired) {
      return 'plan_mode_recovery_inspection';
    }
    if (executionApprovedForSend) {
      return 'plan_mode_execution';
    }
    return _hasIncompleteTodoItems(session.todoItems)
        ? 'plan_mode_planning_with_exit_allowed'
        : 'plan_mode_planning_only';
  }

  bool _isAllowedPlanModePlanningTool(
    String toolName, {
    required bool allowExitPlanMode,
  }) {
    final normalizedToolName = _normalizeToolName(toolName);
    if (_planModePlanningToolAllowlist.contains(normalizedToolName)) {
      return true;
    }
    return allowExitPlanMode && normalizedToolName == 'exitplanmode';
  }

  bool _shouldAllowPlanModeExecutionTools({
    required AiSession session,
    required String? latestUserMessageId,
  }) {
    if (session.mode != AiSessionMode.plan || session.awaitingPlanApproval) {
      return session.mode != AiSessionMode.plan;
    }
    final latestUserMessage = _userMessageById(session, latestUserMessageId);
    if (latestUserMessage == null) {
      return false;
    }
    if (!_hasPlanExecutionContext(session)) {
      return false;
    }
    final content = latestUserMessage.content;
    if (_shouldRequirePlanModeRecoveryInspection(
      session: session,
      latestUserMessageId: latestUserMessageId,
    )) {
      return false;
    }
    if (_looksLikePlanApproval(content)) {
      return true;
    }
    return _hasIncompleteTodoItems(session.todoItems) &&
        _looksLikePlanExecutionContinuation(content);
  }

  bool _shouldRequirePlanModeRecoveryInspection({
    required AiSession session,
    required String? latestUserMessageId,
  }) {
    if (session.mode != AiSessionMode.plan || session.awaitingPlanApproval) {
      return false;
    }
    final latestUserMessage = _userMessageById(session, latestUserMessageId);
    if (latestUserMessage == null) {
      return false;
    }
    final content = latestUserMessage.content;
    final explicitRecoveryRequested = _looksLikePlanRecoveryContinuation(
      content,
    );
    if (_hasCompletedTodoItemsOnly(session.todoItems)) {
      return explicitRecoveryRequested ||
          _looksLikePlanExecutionContinuation(content) ||
          _looksLikePlanApproval(content);
    }
    if (!explicitRecoveryRequested) {
      return false;
    }
    return _hasFailedTodoItems(session.todoItems) ||
        _hasRecentPlanToolFailure(session);
  }

  bool _shouldFailEmptyPlanContinuationReply({
    required AiSession session,
    required int toolRoundCount,
    required String finalReply,
    required bool hasToolCalls,
  }) {
    if (toolRoundCount == 0 ||
        hasToolCalls ||
        finalReply.isNotEmpty ||
        session.mode != AiSessionMode.plan ||
        session.awaitingPlanApproval) {
      return false;
    }
    if (session.todoItems.isNotEmpty) {
      return _hasIncompleteTodoItems(session.todoItems);
    }
    return session.latestActivePlanRecord?.status ==
        AiSessionPlanStatus.inProgress;
  }

  bool _shouldResetPlanStateForNewTask({
    required AiSession session,
    required String latestUserContent,
  }) {
    if (session.mode != AiSessionMode.plan) {
      return false;
    }
    final hasActivePlanState =
        session.todoItems.isNotEmpty ||
        session.awaitingPlanApproval ||
        (session.pendingPlan ?? '').trim().isNotEmpty;
    if (!hasActivePlanState) {
      return false;
    }
    final normalizedContent = latestUserContent.trim();
    if (normalizedContent.isEmpty) {
      return false;
    }
    return !_looksLikePlanApproval(normalizedContent) &&
        !_looksLikePlanExecutionContinuation(normalizedContent) &&
        !_looksLikePlanRecoveryContinuation(normalizedContent);
  }

  AiSession _clearActivePlanState(AiSession session) {
    if (session.todoItems.isEmpty &&
        !session.awaitingPlanApproval &&
        (session.pendingPlan ?? '').trim().isEmpty) {
      return session;
    }
    final clearedAt = _clock().toUtc();
    final archivedSession = _syncPlanHistory(
      session,
      statusOverride: _statusAfterClearingActivePlan(session),
      trackedAt: clearedAt,
    );
    return archivedSession.copyWith(
      updatedAt: clearedAt,
      todoItems: const <AiSessionTodoItem>[],
      awaitingPlanApproval: false,
      clearPendingPlan: true,
    );
  }

  AiSession _archiveCompletedPlanStateIfNeeded(AiSession session) {
    if (session.mode != AiSessionMode.plan ||
        session.awaitingPlanApproval ||
        !_hasCompletedTodoItemsOnly(session.todoItems)) {
      return session;
    }
    final archivedAt = _clock().toUtc();
    final trackedSession = _syncPlanHistory(
      session,
      statusOverride: AiSessionPlanStatus.completed,
      trackedAt: archivedAt,
    );
    return trackedSession.copyWith(
      updatedAt: archivedAt,
      todoItems: const <AiSessionTodoItem>[],
      awaitingPlanApproval: false,
      clearPendingPlan: true,
    );
  }

  AiSession _normalizeStaleCompletedPlanState(
    AiSession session, {
    DateTime? normalizedAt,
  }) {
    final hasStaleApprovalState =
        session.awaitingPlanApproval ||
        (session.pendingPlan ?? '').trim().isNotEmpty;
    if (session.mode != AiSessionMode.plan ||
        !_hasCompletedTodoItemsOnly(session.todoItems) ||
        !hasStaleApprovalState) {
      return session;
    }
    final effectiveNormalizedAt = (normalizedAt ?? _clock()).toUtc();
    final clearedSession = session.copyWith(
      updatedAt: effectiveNormalizedAt,
      awaitingPlanApproval: false,
      clearPendingPlan: true,
    );
    final trackedSession = _syncPlanHistory(
      clearedSession,
      statusOverride: AiSessionPlanStatus.completed,
      trackedAt: effectiveNormalizedAt,
    );
    return trackedSession.copyWith(
      updatedAt: effectiveNormalizedAt,
      todoItems: const <AiSessionTodoItem>[],
      awaitingPlanApproval: false,
      clearPendingPlan: true,
    );
  }

  AiSessionMessage? _userMessageById(AiSession session, String? messageId) {
    final normalizedId = messageId?.trim() ?? '';
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final message in session.messages) {
      if (message.id == normalizedId &&
          !message.isDeleted &&
          message.kind == AiSessionMessageKind.user) {
        return message;
      }
    }
    return null;
  }

  String? _latestActiveUserMessageId(AiSession session) {
    for (var index = session.messages.length - 1; index >= 0; index -= 1) {
      final message = session.messages[index];
      if (!message.isDeleted && message.kind == AiSessionMessageKind.user) {
        return message.id;
      }
    }
    return null;
  }

  AiSessionPlanStatus _statusAfterClearingActivePlan(AiSession session) {
    final derivedStatus = _deriveTrackedPlanStatus(session);
    if (derivedStatus == AiSessionPlanStatus.completed ||
        derivedStatus == AiSessionPlanStatus.failed) {
      return derivedStatus!;
    }
    return AiSessionPlanStatus.cancelled;
  }

  AiSessionPlanStatus? _deriveTrackedPlanStatus(AiSession session) {
    final pendingPlan = (session.pendingPlan ?? '').trim();
    if (session.awaitingPlanApproval ||
        (pendingPlan.isNotEmpty && session.todoItems.isEmpty)) {
      return AiSessionPlanStatus.pendingApproval;
    }
    if (session.todoItems.isEmpty) {
      return null;
    }
    if (_shouldReflectTrackedPlanFailure(session)) {
      return AiSessionPlanStatus.failed;
    }
    if (_hasIncompleteTodoItems(session.todoItems)) {
      return AiSessionPlanStatus.inProgress;
    }
    return AiSessionPlanStatus.completed;
  }

  bool _shouldReflectTrackedPlanFailure(AiSession session) {
    if (session.awaitingPlanApproval) {
      return false;
    }
    final sendPhase = sendPhaseForSession(session.id);
    if (sendPhase != AiSendPhase.idle) {
      return false;
    }
    final latestRecoveryMessage = _latestTrackedPlanRecoveryMessage(session);
    final latestErrorFailureAt = _latestTrackedPlanErrorFailureAt(session);
    if (_shouldReflectTrackedPlanFailureAfter(
      latestErrorFailureAt,
      latestRecoveryMessage,
    )) {
      return true;
    }
    if (_hasFailedTodoItems(session.todoItems)) {
      return true;
    }
    return _shouldReflectTrackedPlanFailureAfter(
      _latestTrackedPlanToolFailureAt(session),
      latestRecoveryMessage,
    );
  }

  bool _shouldReflectTrackedPlanFailureAfter(
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

  DateTime? _latestTrackedPlanToolFailureAt(AiSession session) {
    for (var index = session.messages.length - 1; index >= 0; index -= 1) {
      final message = session.messages[index];
      if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
        continue;
      }
      final status = '${message.metadata['tool_execution_status'] ?? ''}'
          .trim()
          .toLowerCase();
      if (status.isEmpty || status == 'running') {
        continue;
      }
      if (!_isFailureTrackedPlanToolStatus(status)) {
        return null;
      }
      final finishedAt =
          '${message.metadata['tool_execution_finished_at'] ?? ''}'.trim();
      if (finishedAt.isNotEmpty) {
        final parsed = DateTime.tryParse(finishedAt);
        if (parsed != null) {
          return parsed.toUtc();
        }
      }
      return message.createdAt;
    }
    return null;
  }

  DateTime? _latestTrackedPlanErrorFailureAt(AiSession session) {
    for (final error in session.recentErrors) {
      if (_isTrackedPlanRelevantErrorStage(error.stage)) {
        return error.createdAt;
      }
    }
    return null;
  }

  AiSessionMessage? _latestTrackedPlanRecoveryMessage(AiSession session) {
    final latestUserMessage = _latestTrackedPlanUserMessage(session);
    if (latestUserMessage == null) {
      return null;
    }
    return _looksLikePlanRecoveryContinuation(latestUserMessage.content)
        ? latestUserMessage
        : null;
  }

  AiSessionMessage? _latestTrackedPlanUserMessage(AiSession session) {
    for (var index = session.messages.length - 1; index >= 0; index -= 1) {
      final message = session.messages[index];
      if (!message.isDeleted && message.kind == AiSessionMessageKind.user) {
        return message;
      }
    }
    return null;
  }

  AiSession _syncPlanHistory(
    AiSession session, {
    AiSessionPlanStatus? statusOverride,
    DateTime? trackedAt,
  }) {
    final effectiveStatus = statusOverride ?? _deriveTrackedPlanStatus(session);
    if (effectiveStatus == null) {
      return session;
    }
    final normalizedPlan = (session.pendingPlan ?? '').trim();
    final nextSteps = session.todoItems.isEmpty
        ? null
        : session.todoItems
              .map(
                (item) => AiSessionTodoItem(
                  id: item.id,
                  content: item.content,
                  status: item.status,
                ),
              )
              .toList(growable: false);
    final planHistory = List<AiSessionPlanRecord>.from(session.planHistory);
    final trackedIndex = _trackedPlanRecordIndex(
      planHistory,
      normalizedPlan: normalizedPlan,
      nextSteps: nextSteps,
    );
    final effectiveTrackedAt = trackedAt ?? session.updatedAt;
    if (trackedIndex >= 0) {
      final existingRecord = planHistory[trackedIndex];
      planHistory[trackedIndex] = existingRecord.copyWith(
        updatedAt: effectiveTrackedAt,
        status: effectiveStatus,
        plan: normalizedPlan.isNotEmpty ? normalizedPlan : existingRecord.plan,
        steps: nextSteps ?? existingRecord.steps,
      );
    } else {
      planHistory.add(
        AiSessionPlanRecord(
          id: _idGenerator(),
          createdAt: effectiveTrackedAt,
          updatedAt: effectiveTrackedAt,
          status: effectiveStatus,
          plan: normalizedPlan,
          steps: nextSteps ?? const <AiSessionTodoItem>[],
        ),
      );
    }
    final trimmedHistory = planHistory.length > _maxPlanHistoryEntries
        ? planHistory
              .sublist(planHistory.length - _maxPlanHistoryEntries)
              .toList(growable: false)
        : planHistory;
    return session.copyWith(planHistory: trimmedHistory);
  }

  int _trackedPlanRecordIndex(
    List<AiSessionPlanRecord> planHistory, {
    required String normalizedPlan,
    required List<AiSessionTodoItem>? nextSteps,
  }) {
    for (var index = planHistory.length - 1; index >= 0; index -= 1) {
      final planRecord = planHistory[index];
      if (!planRecord.status.isActive) {
        continue;
      }
      if (planRecord.status == AiSessionPlanStatus.failed &&
          !_matchesTrackedPlanRecord(
            planRecord,
            normalizedPlan: normalizedPlan,
            nextSteps: nextSteps,
          )) {
        break;
      }
      return index;
    }
    if (planHistory.isNotEmpty &&
        _matchesTrackedPlanRecord(
          planHistory.last,
          normalizedPlan: normalizedPlan,
          nextSteps: nextSteps,
        )) {
      return planHistory.length - 1;
    }
    return -1;
  }

  bool _matchesTrackedPlanRecord(
    AiSessionPlanRecord planRecord, {
    required String normalizedPlan,
    required List<AiSessionTodoItem>? nextSteps,
  }) {
    if (normalizedPlan.isNotEmpty && normalizedPlan == planRecord.plan.trim()) {
      return true;
    }
    if (nextSteps == null ||
        nextSteps.isEmpty ||
        planRecord.steps.length != nextSteps.length) {
      return false;
    }
    for (var index = 0; index < nextSteps.length; index += 1) {
      final currentStep = nextSteps[index];
      final recordedStep = planRecord.steps[index];
      if (currentStep.id != recordedStep.id ||
          currentStep.content.trim() != recordedStep.content.trim()) {
        return false;
      }
    }
    return true;
  }

  bool _hasRecentPlanToolFailure(AiSession session) {
    for (var index = session.messages.length - 1; index >= 0; index -= 1) {
      final message = session.messages[index];
      if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
        continue;
      }
      final status = '${message.metadata['tool_execution_status'] ?? ''}'
          .trim()
          .toLowerCase();
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

  bool _looksLikePlanExecutionContinuation(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const continuationPhrases = <String>[
      'continue',
      'continue.',
      'go on',
      'keep going',
      'continue the work',
      'continue working',
      'continue implementation',
      'continue improving',
      'continue optimizing',
      'continue fixing',
      'continue debugging',
      'finish it',
      '继续',
      '继续吧',
      '继续做',
      '继续开展',
      '继续完成',
      '继续处理',
      '继续调整',
      '继续排查',
      '继续优化',
      '继续完善',
      '继续改进',
      '继续修复',
      '继续推进',
      '继续跟进',
      '接着',
      '接着做',
    ];
    return continuationPhrases.any((phrase) => normalized.contains(phrase));
  }

  bool _looksLikePlanRecoveryContinuation(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const recoveryPhrases = <String>[
      'retry',
      'retry it',
      'retry the step',
      'retry the failed step',
      'resume',
      'resume execution',
      'resume from the failed step',
      'rerun',
      'rerun the step',
      'continue from the failed step',
      'continue after the failure',
      'continue after failure',
      '继续执行',
      '继续执行失败步骤',
      '从失败步骤继续',
      '重试',
      '重试一下',
      '重新执行',
      '重新尝试',
      '重新试',
      '恢复执行',
      '恢复上次执行',
    ];
    return recoveryPhrases.any((phrase) => normalized.contains(phrase));
  }

  bool _roundRequestedTodoWrite(List<AiToolCall> toolCalls) {
    return toolCalls.any(
      (toolCall) => _normalizeToolName(toolCall.name) == 'todowrite',
    );
  }

  bool _looksLikePlanApproval(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final compactReply = normalized.replaceAll(
      RegExp(r'[\s!！。．\.,，、;；:：~～?？]+'),
      '',
    );
    if (compactReply == '确认') {
      return true;
    }
    const approvalPhrases = <String>[
      'approve',
      'approved',
      'go ahead',
      'proceed',
      'start implementing',
      'begin implementation',
      'continue implementation',
      'confirm execution',
      '确认执行',
      '确认开始',
      '开始执行',
      '继续实施',
      '继续执行',
      '开始吧',
      '执行吧',
      '可以执行',
      '可以开始',
    ];
    return approvalPhrases.any((phrase) => normalized.contains(phrase));
  }

  Future<AiSession> _compressIfNeeded({
    required AiSession session,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
  }) async {
    if (!_shouldCompressSessionHistory(session, runtimeContext, model)) {
      return session;
    }
    final activeConversationMessages = session.activeConversationMessages
        .where(
          (message) => message.kind != AiSessionMessageKind.compressionPoint,
        )
        .toList(growable: false);
    final threshold = _effectiveCompressionThresholdChars(
      runtimeContext: runtimeContext,
      model: model,
    );

    final retainedMessages = <AiSessionMessage>[];
    var retainedCharacterCount = 0;
    for (
      var index = activeConversationMessages.length - 1;
      index >= 0;
      index--
    ) {
      final message = activeConversationMessages[index];
      final nextCharacterCount =
          retainedCharacterCount + message.characterCount;
      if (retainedMessages.isNotEmpty && nextCharacterCount > threshold) {
        break;
      }
      retainedMessages.insert(0, message);
      retainedCharacterCount = nextCharacterCount;
    }

    final compressedMessageCount =
        activeConversationMessages.length - retainedMessages.length;
    if (compressedMessageCount <= 0) {
      return session;
    }

    final candidateMessagesToCompress = activeConversationMessages
        .take(compressedMessageCount)
        .toList(growable: false);
    final previousCompressionPoint = session.latestCompressionPoint;
    final templateBundle = await _templateRepository.loadBundle(
      session.templateId,
    );
    final template = _templateRepository.resolveTemplate(session.templateId);
    final compressionWindow = _selectCompressionWindowForModelContext(
      templateBundle: templateBundle,
      template: template,
      session: session,
      runtimeContext: runtimeContext,
      model: model,
      candidateMessages: candidateMessagesToCompress,
      previousCompressionPoint: previousCompressionPoint,
    );
    final messagesToCompress = compressionWindow.messagesToCompress;
    if (messagesToCompress.isEmpty) {
      _debugSessionLog(
        session.id,
        'compression_window_empty candidate_count=${candidateMessagesToCompress.length} max_context_tokens=${model.maxContextTokens ?? 0}',
      );
      return session;
    }
    final discardedMessages = compressionWindow.discardedMessages;
    try {
      await _emitCompactHooks(
        sessionId: session.id,
        eventName: 'PreCompact',
        trigger: 'auto',
        payload: <String, Object?>{
          'messages_to_compress_count': messagesToCompress.length,
          'discarded_message_count_due_to_context_limit':
              discardedMessages.length,
        },
      );
      final compressionPrompt = _promptBuilder.buildCompressionPrompt(
        templateBundle: templateBundle,
        template: template,
        session: session,
        runtimeContext: runtimeContext,
        messagesToCompress: messagesToCompress,
        previousCompressionPoint: previousCompressionPoint,
      );
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: compressionPrompt,
        timeout: Duration(seconds: runtimeContext.responseTimeoutSeconds),
      );
      final sourceMessages = <AiSessionMessage>[
        if (previousCompressionPoint != null) ...[previousCompressionPoint],
        ...messagesToCompress,
      ];
      final sourceCharacterCount = sourceMessages.fold<int>(
        0,
        (sum, message) => sum + message.characterCount,
      );
      final checkpoint = AiSessionMessage.compressionPoint(
        id: _idGenerator(),
        content: completion.reply,
        createdAt: _clock().toUtc(),
        modelId: model.id,
        modelLabel: model.displayName,
        usage: completion.usage,
        metadata: <String, Object?>{
          'source_message_ids': sourceMessages
              .map((message) => message.id)
              .toList(growable: false),
          'compressed_message_ids': messagesToCompress
              .map((message) => message.id)
              .toList(growable: false),
          'previous_checkpoint_message_id': previousCompressionPoint?.id,
          'trigger_threshold_chars': threshold,
          'discarded_message_ids_due_to_context_limit': discardedMessages
              .map((message) => message.id)
              .toList(growable: false),
          'discarded_message_count_due_to_context_limit':
              discardedMessages.length,
          'source_character_count': sourceCharacterCount,
          'retained_message_ids_after_checkpoint': retainedMessages
              .map((message) => message.id)
              .toList(growable: false),
          'summary_model_id': model.id,
          'summary_model_label': model.displayName,
          'summary_model_max_context_tokens': model.maxContextTokens,
        },
      );
      final anchorMessageId = messagesToCompress.last.id;
      final insertionIndex = session.messages.indexWhere(
        (message) => message.id == anchorMessageId,
      );
      if (insertionIndex == -1) {
        _debugSessionLog(
          session.id,
          'compression_insert_anchor_missing anchor_message_id=$anchorMessageId',
        );
        return session;
      }
      final updatedMessages = <AiSessionMessage>[
        ...session.messages.take(insertionIndex + 1),
        checkpoint,
        ...session.messages.skip(insertionIndex + 1),
      ];
      final totalUsage = _usageFromStatistics(
        session.statistics,
      ).merge(completion.usage ?? const AiTokenUsage());
      final compressedSession = _rebuildSession(
        session.copyWith(
          updatedAt: checkpoint.createdAt,
          messages: updatedMessages,
          lastUsedModelId: model.id,
          lastUsedModelLabel: model.displayName,
          latestCompressionCheckpointMessageId: checkpoint.id,
          latestCompressionAt: checkpoint.createdAt,
        ),
        totalPromptCharacters:
            session.statistics.totalPromptCharacters +
            compressionPrompt.fold<int>(
              0,
              (sum, message) => sum + message.promptCharacterCount,
            ),
        promptBuildCount: session.statistics.promptBuildCount + 1,
        compressionRunCount: session.statistics.compressionRunCount + 1,
        totalUsage: totalUsage,
      );
      final committed = await _commitSessionLocked(compressedSession);
      if (committed) {
        _markDidCompressInLastSend(session.id);
        await _emitCompactHooks(
          sessionId: session.id,
          eventName: 'PostCompact',
          trigger: 'auto',
          payload: <String, Object?>{
            'checkpoint_message_id': checkpoint.id,
            'messages_to_compress_count': messagesToCompress.length,
            'discarded_message_count_due_to_context_limit':
                discardedMessages.length,
          },
        );
      }
      return committed ? compressedSession : session;
    } catch (error) {
      await _emitStopFailureHook(
        sessionId: session.id,
        stage: 'history_compression',
        detail: '$error',
      );
      final erroredSession = _appendError(
        session,
        stage: 'history_compression',
        message: '$error',
        detail: '$error',
      );
      await _commitSessionLocked(erroredSession);
      return erroredSession;
    }
  }

  Future<_PreparedUserTurn> _prepareUserTurn({
    required AiSession session,
    required String content,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
    List<String> attachmentFilePaths = const <String>[],
    Map<String, Object?> userMessageMetadata = const <String, Object?>{},
  }) async {
    final now = _clock().toUtc();
    final visibleUserMessageCount = session.messages
        .where(
          (message) =>
              !message.isDeleted && message.kind == AiSessionMessageKind.user,
        )
        .length;
    final editingMessageId = _editingMessageId;
    if (editingMessageId != null) {
      final messageIndex = session.messages.indexWhere(
        (message) => message.id == editingMessageId && !message.isDeleted,
      );
      if (messageIndex != -1) {
        final original = session.messages[messageIndex];
        final updatedMessages = <AiSessionMessage>[
          for (final message in session.messages)
            (() {
              final marker = '${message.metadata[_editRollbackMarkerKey] ?? ''}'
                  .trim();
              if (marker != editingMessageId) {
                return message;
              }
              final nextMetadata = Map<String, Object?>.from(message.metadata)
                ..remove(_editRollbackMarkerKey);
              return message.copyWith(metadata: nextMetadata);
            })(),
        ];
        final editedMessage = original.copyWith(
          content: content,
          characterCount: _characterCountForMessageContent(
            content,
            attachments: AiMessageAttachment.listFromMetadata(
              original.metadata[aiSessionMessageAttachmentsMetadataKey],
            ),
          ),
          metadata: <String, Object?>{
            ...original.metadata,
            ...userMessageMetadata,
            'edited_at': now.toIso8601String(),
          },
        );
        updatedMessages[messageIndex] = editedMessage;
        _editingMessageId = null;
        final updatedSession = _rebuildSession(
          session.copyWith(
            title: _deriveSessionTitle(session, editedMessage),
            updatedAt: now,
            messages: updatedMessages,
            environment: _environmentFromRuntime(runtimeContext),
            lastUsedModelId: model.id,
            lastUsedModelLabel: model.displayName,
          ),
        );
        return _PreparedUserTurn(
          session: updatedSession,
          userMessage: editedMessage,
          shouldGenerateTitle:
              !updatedSession.isTitleManuallyEdited &&
              visibleUserMessageCount == 1,
          importedAttachments: false,
        );
      }
      _editingMessageId = null;
    }

    final userMessageId = _idGenerator();
    final attachments = await _attachmentService.importAttachments(
      sessionId: session.id,
      messageId: userMessageId,
      filePaths: attachmentFilePaths,
      idGenerator: _idGenerator,
      imageSizeLimitBytes: runtimeContext.imageSizeLimitBytes,
    );
    final attachmentMetadata = attachments.isEmpty
        ? const <String, Object?>{}
        : <String, Object?>{
            aiSessionMessageAttachmentsMetadataKey:
                AiMessageAttachment.listToMetadata(attachments),
          };
    final userMessage =
        AiSessionMessage.user(
          id: userMessageId,
          content: content,
          createdAt: now,
          metadata: <String, Object?>{
            ...userMessageMetadata,
            ...attachmentMetadata,
          },
        ).copyWith(
          characterCount: _characterCountForMessageContent(
            content,
            attachments: attachments,
          ),
        );
    final isFirstVisibleUserMessage = visibleUserMessageCount == 0;
    final shouldKeepDefaultTitle =
        isFirstVisibleUserMessage &&
        !session.isTitleManuallyEdited &&
        session.autoTitleGeneratedAt == null &&
        session.title.trim() == _defaultNewSessionTitle;
    final nextTitle = shouldKeepDefaultTitle
        ? session.title
        : _deriveSessionTitle(session, userMessage);
    final updatedSession = _rebuildSession(
      session.copyWith(
        title: nextTitle,
        updatedAt: now,
        messages: <AiSessionMessage>[...session.messages, userMessage],
        environment: _environmentFromRuntime(runtimeContext),
        lastUsedModelId: model.id,
        lastUsedModelLabel: model.displayName,
      ),
    );
    return _PreparedUserTurn(
      session: updatedSession,
      userMessage: userMessage,
      shouldGenerateTitle:
          !updatedSession.isTitleManuallyEdited && isFirstVisibleUserMessage,
      importedAttachments: attachments.isNotEmpty,
    );
  }

  Future<void> _generateAutoTitle({
    required String sessionId,
    required String sourceMessageId,
    required String sourceContent,
    required AiModelConfig model,
    bool allowRetryAfterIdle = true,
  }) async {
    final session = _sessionById(sessionId);
    if (session == null || session.isTitleManuallyEdited) {
      return;
    }
    if (session.autoTitleSourceMessageId != null &&
        session.autoTitleSourceMessageId != sourceMessageId) {
      return;
    }
    final promptMessages = <AiChatTurn>[
      const AiChatTurn(
        role: AiChatRole.system,
        content: _autoTitleSystemPrompt,
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content: 'First user message:\n$sourceContent',
      ),
    ];
    final requestModels = _autoTitleRequestModels(model);
    Object? lastError;
    for (
      var attemptIndex = 0;
      attemptIndex < requestModels.length;
      attemptIndex++
    ) {
      final requestModel = requestModels[attemptIndex];
      final isLastAttempt = attemptIndex == requestModels.length - 1;
      try {
        final completion = await _backgroundChatClient.sendMessage(
          model: requestModel,
          messages: promptMessages,
          timeout: _autoTitleRequestTimeout,
        );
        final generatedTitle = _sanitizeGeneratedTitle(completion.reply);
        final acceptedGeneratedTitle = _isMeaningfulAutoTitle(generatedTitle)
            ? generatedTitle
            : '';
        final resolvedTitle = acceptedGeneratedTitle.isNotEmpty
            ? acceptedGeneratedTitle
            : isLastAttempt && generatedTitle.isNotEmpty
            ? _deriveReadableTitleFromContent(
                sourceContent,
                maxCharacters: _generatedTitleMaxCharacters,
              )
            : '';
        if (resolvedTitle.isEmpty) {
          if (isLastAttempt) {
            return;
          }
          continue;
        }
        final latestSession = _sessionById(sessionId);
        if (latestSession == null || latestSession.isTitleManuallyEdited) {
          return;
        }
        AiSessionMessage? latestSourceMessage;
        for (final message in latestSession.messages) {
          if (message.id == sourceMessageId) {
            latestSourceMessage = message;
          }
        }
        if (latestSourceMessage == null ||
            latestSourceMessage.content != sourceContent) {
          return;
        }
        final generatedAt = _clock().toUtc();
        final totalUsage = _usageFromStatistics(
          latestSession.statistics,
        ).merge(completion.usage ?? const AiTokenUsage());
        final updatedSession = _rebuildSession(
          latestSession.copyWith(
            title: resolvedTitle,
            updatedAt: generatedAt,
            autoTitleGeneratedAt: generatedAt,
            autoTitleSourceMessageId: sourceMessageId,
          ),
          totalPromptCharacters:
              latestSession.statistics.totalPromptCharacters +
              promptMessages.fold<int>(
                0,
                (sum, message) => sum + message.promptCharacterCount,
              ),
          promptBuildCount: latestSession.statistics.promptBuildCount + 1,
          totalUsage: totalUsage,
        );
        final committed = await _commitSessionLocked(updatedSession);
        if (committed) {
          return;
        }
        lastError =
            _lastErrorMessage ?? 'Failed to persist the generated auto title.';
        break;
      } catch (error) {
        lastError = error;
        final shouldRetryAfterIdle =
            allowRetryAfterIdle &&
            _isRetryableAutoTitleError(error) &&
            sendPhaseForSession(sessionId) != AiSendPhase.idle;
        if (shouldRetryAfterIdle) {
          final waitedForIdle = await _waitForSessionIdleForAutoTitleRetry(
            sessionId: sessionId,
            sourceMessageId: sourceMessageId,
          );
          if (waitedForIdle) {
            return _generateAutoTitle(
              sessionId: sessionId,
              sourceMessageId: sourceMessageId,
              sourceContent: sourceContent,
              model: model,
              allowRetryAfterIdle: false,
            );
          }
        }
        if (!isLastAttempt) {
          continue;
        }
      }
    }
    if (lastError == null) {
      return;
    }
    // All API attempts failed — derive a title from user content as fallback.
    final fallbackTitle = _deriveReadableTitleFromContent(
      sourceContent,
      maxCharacters: _generatedTitleMaxCharacters,
    );
    final latestSession = _sessionById(sessionId);
    if (latestSession == null) {
      return;
    }
    if (fallbackTitle.isNotEmpty &&
        !latestSession.isTitleManuallyEdited &&
        (latestSession.autoTitleGeneratedAt == null ||
            latestSession.autoTitleSourceMessageId == sourceMessageId)) {
      final fallbackAt = _clock().toUtc();
      final fallbackSession = _rebuildSession(
        latestSession.copyWith(
          title: fallbackTitle,
          updatedAt: fallbackAt,
          autoTitleGeneratedAt: fallbackAt,
          autoTitleSourceMessageId: sourceMessageId,
        ),
      );
      final committed = await _commitSessionLocked(fallbackSession);
      if (committed) {
        return;
      }
    }
    final updatedSession = _appendError(
      latestSession,
      stage: 'title_generation',
      message: '$lastError',
      detail: '$lastError',
    );
    await _commitSessionLocked(updatedSession);
  }

  List<AiModelConfig> _autoTitleRequestModels(AiModelConfig model) {
    final preferredModel = _preferredAutoTitleModel(model);
    if (preferredModel.modelId == model.modelId) {
      return <AiModelConfig>[model];
    }
    return <AiModelConfig>[preferredModel, model];
  }

  AiModelConfig _preferredAutoTitleModel(AiModelConfig model) {
    final normalizedModelId = model.modelId.trim().toLowerCase();
    if (normalizedModelId == 'deepseek-reasoner') {
      return model.copyWith(modelId: 'deepseek-chat');
    }
    return model;
  }

  Future<bool> _waitForSessionIdleForAutoTitleRetry({
    required String sessionId,
    required String sourceMessageId,
  }) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < _autoTitleRetryWaitTimeout) {
      final session = _sessionById(sessionId);
      if (session == null ||
          session.isTitleManuallyEdited ||
          session.autoTitleGeneratedAt != null ||
          (session.autoTitleSourceMessageId != null &&
              session.autoTitleSourceMessageId != sourceMessageId)) {
        return false;
      }
      if (sendPhaseForSession(sessionId) == AiSendPhase.idle) {
        return true;
      }
      await Future<void>.delayed(_autoTitleRetryPollInterval);
    }
    return false;
  }

  AiSession _syncToolCallMessagesFromResult(
    AiSession session,
    List<AiToolCall> toolCalls,
    AiModelConfig model,
  ) {
    var updatedSession = session;
    final expectedToolCallIds = toolCalls
        .map((toolCall) => toolCall.id.trim())
        .where((toolCallId) => toolCallId.isNotEmpty)
        .toSet();
    final expectedToolCallIndexes = <int>{};
    for (var index = 0; index < toolCalls.length; index++) {
      expectedToolCallIndexes.add(index);
    }
    final updatedMessages = List<AiSessionMessage>.from(
      updatedSession.messages,
    );
    var removedPreviewCount = 0;
    for (var index = 0; index < updatedMessages.length; index++) {
      final message = updatedMessages[index];
      if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
        continue;
      }
      final currentStatus = '${message.metadata['tool_execution_status'] ?? ''}'
          .trim();
      if (_isTerminalToolExecutionStatus(currentStatus)) {
        continue;
      }
      final toolCallId = '${message.metadata['tool_call_id'] ?? ''}'.trim();
      final toolCallIndex = int.tryParse(
        '${message.metadata['tool_call_index'] ?? ''}'.trim(),
      );
      final matchesById =
          toolCallId.isNotEmpty && expectedToolCallIds.contains(toolCallId);
      final matchesByIndex =
          toolCallIndex != null &&
          expectedToolCallIndexes.contains(toolCallIndex);
      if (matchesById || matchesByIndex) {
        continue;
      }
      removedPreviewCount += 1;
      updatedMessages[index] = message.copyWith(
        isDeleted: true,
        metadata: <String, Object?>{
          ...message.metadata,
          'stream_preview_discarded': true,
        },
      );
    }
    if (removedPreviewCount > 0) {
      updatedSession = updatedSession.copyWith(
        messages: updatedMessages,
        updatedAt: _clock().toUtc(),
      );
    }
    for (var index = 0; index < toolCalls.length; index++) {
      final toolCall = toolCalls[index];
      final existingIndex = updatedSession.messages.lastIndexWhere(
        (message) =>
            !message.isDeleted &&
            message.kind == AiSessionMessageKind.toolCall &&
            '${message.metadata['tool_call_id'] ?? ''}'.trim() == toolCall.id,
      );
      final messageId = existingIndex == -1
          ? _idGenerator()
          : updatedSession.messages[existingIndex].id;
      updatedSession = _upsertMessage(
        updatedSession,
        messageId: messageId,
        create: () => AiSessionMessage.toolCall(
          id: messageId,
          content: _renderToolCallContent(
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
          createdAt: _clock().toUtc(),
          modelId: model.id,
          modelLabel: model.displayName,
          metadata: <String, Object?>{
            'tool_call_index': index,
            'tool_call_id': toolCall.id,
            'tool_name': toolCall.name,
            'tool_arguments': toolCall.arguments,
            'tool_calls': <Map<String, Object?>>[
              <String, Object?>{
                'id': toolCall.id,
                'name': toolCall.name,
                'arguments': toolCall.arguments,
              },
            ],
          },
        ),
        update: (message) => message.copyWith(
          content: _renderToolCallContent(
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
          metadata: <String, Object?>{
            ...message.metadata,
            'tool_call_index': index,
            'tool_call_id': toolCall.id,
            'tool_name': toolCall.name,
            'tool_arguments': toolCall.arguments,
            'tool_calls': <Map<String, Object?>>[
              <String, Object?>{
                'id': toolCall.id,
                'name': toolCall.name,
                'arguments': toolCall.arguments,
              },
            ],
          },
          modelId: model.id,
          modelLabel: model.displayName,
        ),
      );
    }
    return updatedSession;
  }

  AiSession _upsertMessage(
    AiSession session, {
    required String messageId,
    required AiSessionMessage Function() create,
    required AiSessionMessage Function(AiSessionMessage message) update,
  }) {
    final messages = session.messages;
    final int messagesLength = messages.length;
    
    if (messagesLength > 0 && messages[messagesLength - 1].id == messageId) {
      final updatedMessages = List<AiSessionMessage>.of(messages);
      updatedMessages[messagesLength - 1] = update(updatedMessages[messagesLength - 1]);
      return session.copyWith(
        messages: updatedMessages,
        updatedAt: _clock().toUtc(),
      );
    }

    final messageIndex = messages.indexWhere(
      (message) => message.id == messageId,
    );
    final updatedMessages = List<AiSessionMessage>.of(messages);
    if (messageIndex == -1) {
      updatedMessages.add(create());
    } else {
      updatedMessages[messageIndex] = update(updatedMessages[messageIndex]);
    }
    return session.copyWith(
      messages: updatedMessages,
      updatedAt: _clock().toUtc(),
    );
  }

  AiSession _removeMessagesByIds(
    AiSession session, {
    required Set<String> messageIds,
  }) {
    if (messageIds.isEmpty) {
      return session;
    }
    final updatedMessages = session.messages
        .where((message) => !messageIds.contains(message.id))
        .toList(growable: false);
    if (updatedMessages.length == session.messages.length) {
      return session;
    }
    return session.copyWith(
      messages: updatedMessages,
      updatedAt: _clock().toUtc(),
    );
  }

  void _previewSession(AiSession session) {
    final replaced = _replaceSessionInMemory(session, sortSessions: false);
    if (replaced) {
      notifyListeners();
    }
  }

  bool _replaceSessionInMemory(AiSession session, {bool sortSessions = true}) {
    if (_deletedSessionIds.contains(session.id)) {
      return false;
    }
    final existingIndex = _sessions.indexWhere((item) => item.id == session.id);
    final liveSession = existingIndex == -1 ? null : _sessions[existingIndex];
    final effectiveSession = _mergeLiveSessionState(session, liveSession);
    if (existingIndex == -1) {
      _sessions = <AiSession>[effectiveSession, ..._sessions];
    } else {
      final updatedSessions = List<AiSession>.from(_sessions);
      updatedSessions[existingIndex] = effectiveSession;
      if (sortSessions) {
        updatedSessions.sort(
          (left, right) => right.updatedAt.compareTo(left.updatedAt),
        );
      }
      _sessions = updatedSessions;
    }
    return true;
  }

  Future<bool> _commitSessionLocked(AiSession session) async {
    if (_deletedSessionIds.contains(session.id)) {
      return true;
    }
    final normalizedSession = _normalizeStaleCompletedPlanState(session);
    final previousSession = _sessionById(normalizedSession.id);
    final effectiveSession = _mergeLiveSessionState(
      normalizedSession,
      previousSession,
    );
    final previousIssues = List<AiSessionPersistenceIssue>.from(
      _persistenceIssues,
    );
    _replaceSessionInMemory(effectiveSession);
    notifyListeners();
    try {
      await _store.save(effectiveSession);
      if (_persistenceIssues.isNotEmpty) {
        _persistenceIssues = const <AiSessionPersistenceIssue>[];
        notifyListeners();
      }
      return true;
    } catch (error) {
      final restoredSessions = List<AiSession>.from(_sessions)
        ..removeWhere((item) => item.id == session.id);
      if (previousSession != null) {
        restoredSessions.add(previousSession);
        restoredSessions.sort(
          (left, right) => right.updatedAt.compareTo(left.updatedAt),
        );
      }
      _sessions = restoredSessions;
      _persistenceIssues = previousIssues;
      _lastErrorMessage = '$error';
      notifyListeners();
      return false;
    }
  }

  AiSession? _sessionById(String sessionId) {
    for (final session in _sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  Future<void> _emitSessionStartHook({
    required AiSession session,
    required String source,
  }) async {
    await _safeRunHook(
      eventName: 'SessionStart',
      matcherValue: source,
      payload: <String, Object?>{
        'source': source,
        'session_title': session.title,
        'template_id': session.templateId,
      },
      sessionId: session.id,
    );
    await _safeRunUserHook(
      event: HookEvent.sessionStart,
      sessionId: session.id,
      payload: <String, Object?>{
        'source': source,
        'session_title': session.title,
        'template_id': session.templateId,
      },
    );
  }

  Future<void> _emitSessionEndHook({
    required AiSession session,
    required String reason,
  }) async {
    await _safeRunHook(
      eventName: 'SessionEnd',
      matcherValue: reason,
      payload: <String, Object?>{
        'reason': reason,
        'session_title': session.title,
        'template_id': session.templateId,
      },
      sessionId: session.id,
    );
    await _safeRunUserHook(
      event: HookEvent.sessionEnd,
      sessionId: session.id,
      payload: <String, Object?>{
        'reason': reason,
        'session_title': session.title,
        'template_id': session.templateId,
      },
    );
  }

  Future<void> _emitRuntimeCompatibilityHooks({
    required String sessionId,
    required AiSessionRuntimeContext runtimeContext,
    required AiSessionEnvironment previousEnvironment,
    required Map<String, Object?> previousPromptMetadata,
  }) async {
    final currentInstructionPaths = runtimeContext.workspaceInstructionDocuments
        .map((item) => item.path)
        .toList(growable: false);
    final previousInstructionPaths = _readStringList(
      previousPromptMetadata['workspace_instruction_paths'],
    );
    if (!_stringListsEqual(currentInstructionPaths, previousInstructionPaths)) {
      for (final document in runtimeContext.workspaceInstructionDocuments) {
        await _safeRunHook(
          eventName: 'InstructionsLoaded',
          payload: <String, Object?>{
            'instruction_path': document.path,
            'instruction_name': document.name,
            'character_count': document.content.length,
            'source': 'workspace_instructions',
          },
          sessionId: sessionId,
        );
      }
    }

    final nextEnvironment = _environmentFromRuntime(runtimeContext);
    if (!_environmentEquals(previousEnvironment, nextEnvironment) ||
        _readBool(previousPromptMetadata['memory_enabled']) !=
            runtimeContext.memoryEnabled) {
      await _safeRunHook(
        eventName: 'ConfigChange',
        matcherValue: 'user_settings',
        payload: <String, Object?>{
          'source': 'user_settings',
          'previous_environment': previousEnvironment.toJson(),
          'current_environment': nextEnvironment.toJson(),
          'memory_enabled': runtimeContext.memoryEnabled,
        },
        sessionId: sessionId,
      );
    }
  }

  Future<void> _emitStopHooks({
    required String sessionId,
    required String reason,
    required bool awaitingUserInput,
  }) async {
    await _safeRunHook(
      eventName: 'Stop',
      matcherValue: '',
      payload: <String, Object?>{
        'reason': reason,
        'awaiting_user_input': awaitingUserInput,
      },
      sessionId: sessionId,
    );
    await _safeRunUserHook(
      event: HookEvent.stop,
      sessionId: sessionId,
      payload: <String, Object?>{
        'reason': reason,
        'awaiting_user_input': awaitingUserInput,
      },
    );
    if (awaitingUserInput) {
      await _safeRunHook(
        eventName: 'Notification',
        matcherValue: reason == 'plan_approval'
            ? 'permission_prompt'
            : 'idle_prompt',
        payload: <String, Object?>{
          'notification_type': reason == 'plan_approval'
              ? 'permission_prompt'
              : 'idle_prompt',
          'reason': reason,
        },
        sessionId: sessionId,
      );
    }
  }

  Future<void> _emitStopFailureHook({
    required String sessionId,
    required String stage,
    required String detail,
  }) async {
    await _safeRunHook(
      eventName: 'StopFailure',
      payload: <String, Object?>{'stage': stage, 'detail': detail},
      sessionId: sessionId,
    );
    await _safeRunUserHook(
      event: HookEvent.errorOccurred,
      sessionId: sessionId,
      payload: <String, Object?>{'stage': stage, 'detail': detail},
    );
  }

  Future<void> _emitCompactHooks({
    required String sessionId,
    required String eventName,
    required String trigger,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    await _safeRunHook(
      eventName: eventName,
      matcherValue: trigger,
      payload: <String, Object?>{'trigger': trigger, ...payload},
      sessionId: sessionId,
    );
    if (eventName == 'PreCompact') {
      await _safeRunUserHook(
        event: HookEvent.preCompact,
        sessionId: sessionId,
        payload: <String, Object?>{'trigger': trigger, ...payload},
      );
    }
  }

  Future<void> _safeRunHook({
    required String eventName,
    required String sessionId,
    Map<String, Object?> payload = const <String, Object?>{},
    String? matcherValue,
  }) async {
    try {
      await _hookService.runHooks(
        eventName: eventName,
        sessionId: sessionId,
        matcherValue: matcherValue,
        cwd: OpenHandPaths.applicationDirectoryPath(),
        payload: payload,
      );
    } catch (_) {
      return;
    }
  }

  /// Executes user-configured hooks for the given lifecycle event and
  /// appends visible hook-result messages to the session so users can see
  /// exactly which hooks ran, their status, and any output — just like
  /// skill or MCP tool call cards.
  ///
  /// This runs independently from [_safeRunHook] which handles the
  /// Claude-style JSON config hooks. Both systems coexist.
  Future<void> _safeRunUserHook({
    required HookEvent event,
    required String sessionId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final executor = _userHooksExecutor;
    if (executor == null) return;

    // Build rich context payload for the hook script.
    final session = _sessionById(sessionId);
    final enrichedPayload = _buildHookContextPayload(
      event: event,
      sessionId: sessionId,
      session: session,
      extra: payload,
    );

    HookExecutionResult result;
    try {
      result = await executor.executeEvent(
        event: event,
        sessionId: sessionId,
        payload: enrichedPayload,
      );
    } catch (_) {
      return;
    }
    if (result.hookResults.isEmpty) return;

    // Create one visible message per hook that actually ran.
    final currentSession = _sessionById(sessionId);
    if (currentSession == null) return;
    final newMessages = <AiSessionMessage>[];
    for (final hookResult in result.hookResults) {
      final createdAt = _clock().toUtc();
      final toolInput = hookResult.scriptPath != null &&
              hookResult.scriptPath!.isNotEmpty
          ? hookResult.scriptPath!
          : hookResult.scriptContent != null &&
              hookResult.scriptContent!.isNotEmpty
          ? hookResult.scriptContent!
          : event.storageValue;
      newMessages.add(
        AiSessionMessage.hookResult(
          id: _idGenerator(),
          content: hookResult.stdout.isNotEmpty
              ? hookResult.stdout
              : hookResult.stderr.isNotEmpty
              ? hookResult.stderr
              : hookResult.status == 'success'
              ? 'Hook completed successfully.'
              : 'Hook finished with status: ${hookResult.status}.',
          createdAt: createdAt,
          metadata: <String, Object?>{
            'tool_source': 'hook',
            'tool_name': 'hook__${event.storageValue}',
            'hook_name': hookResult.hookLabel,
            'hook_event': event.storageValue,
            'tool_execution_status': hookResult.status,
            'tool_execution_elapsed_ms': hookResult.elapsedMs,
            'tool_execution_stdout': hookResult.stdout,
            'tool_execution_stderr': hookResult.stderr,
            if (hookResult.stdoutFile != null)
              'tool_execution_stdout_file': hookResult.stdoutFile,
            if (hookResult.stderrFile != null)
              'tool_execution_stderr_file': hookResult.stderrFile,
            'tool_arguments': '\$ ${toolInput.trim()}',
          },
        ),
      );
    }
    if (newMessages.isEmpty) return;
    final updatedSession = currentSession.copyWith(
      updatedAt: newMessages.last.createdAt,
      messages: <AiSessionMessage>[...currentSession.messages, ...newMessages],
    );
    await _commitSessionLocked(updatedSession);
  }

  /// Assembles a comprehensive context payload for hook scripts.
  ///
  /// The resulting JSON is passed to hooks via the `OPENHAND_HOOK_CONTEXT`
  /// environment variable and stdin. Scripts can parse it with `jq` or any
  /// JSON parser.
  Map<String, Object?> _buildHookContextPayload({
    required HookEvent event,
    required String sessionId,
    required AiSession? session,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final now = _clock().toUtc();
    final context = <String, Object?>{
      // ── Event info ──
      'hook_event': event.storageValue,
      'timestamp': now.toIso8601String(),

      // ── Session info ──
      'session_id': sessionId,
      'session_title': session?.title ?? '',
      'session_file_path': _store.sessionFilePath(sessionId),
      'session_created_at': session?.createdAt.toIso8601String() ?? '',
      'session_updated_at': session?.updatedAt.toIso8601String() ?? '',
      'session_message_count': session?.messages.length ?? 0,
      'session_mode': session?.mode.storageValue ?? '',

      // ── Model info ──
      'model_id': session?.lastUsedModelId ?? '',
      'model_label': session?.lastUsedModelLabel ?? '',

      // ── Environment ──
      'environment': session?.environment.toJson() ?? <String, Object?>{},

      // ── Session metadata ──
      'session_metadata': session?.metadata ?? <String, Object?>{},
      'last_prompt_metadata': session?.lastPromptMetadata ?? <String, Object?>{},

      // ── Statistics ──
      'statistics': session?.statistics.toJson() ?? <String, Object?>{},

      // ── Paths (convenience shortcuts) ──
      'sessions_directory': _store.sessionsDirectoryPath,
      'working_directory': OpenHandPaths.applicationDirectoryPath(),

      // ── Caller-supplied extra fields (e.g. prompt text, tool info) ──
      ...extra,
    };
    return context;
  }

  List<String> _readStringList(Object? rawValue) {
    if (rawValue is List) {
      return rawValue
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final single = '$rawValue'.trim();
    if (single.isEmpty || single == 'null') {
      return const <String>[];
    }
    return <String>[single];
  }

  bool? _readBool(Object? rawValue) {
    if (rawValue is bool) {
      return rawValue;
    }
    final normalized = '$rawValue'.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    return null;
  }

  AiSession _mergeLiveSessionState(
    AiSession nextSession,
    AiSession? liveSession,
  ) {
    if (liveSession == null) {
      return nextSession;
    }

    if (liveSession.fullAccessPermission != nextSession.fullAccessPermission) {
      nextSession = nextSession.copyWith(
        fullAccessPermission: liveSession.fullAccessPermission,
      );
    }

    if (!identical(liveSession.metadata, nextSession.metadata)) {
      final mergedMetadata = Map<String, Object?>.from(nextSession.metadata);
      var hasMetadataDifferences = false;
      for (final entry in liveSession.metadata.entries) {
        if (mergedMetadata[entry.key] != entry.value) {
          mergedMetadata[entry.key] = entry.value;
          hasMetadataDifferences = true;
        }
      }
      if (hasMetadataDifferences) {
        nextSession = nextSession.copyWith(metadata: mergedMetadata);
      }
    }

    if (liveSession.isTitleManuallyEdited) {
      return nextSession.copyWith(
        title: liveSession.title,
        isTitleManuallyEdited: true,
        autoTitleGeneratedAt: liveSession.autoTitleGeneratedAt,
        autoTitleSourceMessageId: liveSession.autoTitleSourceMessageId,
      );
    }
    final liveAutoTitleGeneratedAt = liveSession.autoTitleGeneratedAt;
    final nextAutoTitleGeneratedAt = nextSession.autoTitleGeneratedAt;
    if (liveAutoTitleGeneratedAt != null &&
        (nextAutoTitleGeneratedAt == null ||
            !nextAutoTitleGeneratedAt.isAfter(liveAutoTitleGeneratedAt))) {
      return nextSession.copyWith(
        title: liveSession.title,
        autoTitleGeneratedAt: liveAutoTitleGeneratedAt,
        autoTitleSourceMessageId: liveSession.autoTitleSourceMessageId,
      );
    }
    return nextSession;
  }

  AiSession _appendError(
    AiSession session, {
    required String stage,
    required String message,
    String? detail,
  }) {
    final errorRecord = AiSessionErrorRecord(
      id: _idGenerator(),
      createdAt: _clock().toUtc(),
      stage: stage,
      message: message,
      detail: detail,
    );
    final nextErrors = <AiSessionErrorRecord>[
      errorRecord,
      ...session.recentErrors,
    ].take(_maxRecentErrors).toList(growable: false);
    return _syncPlanHistory(
      session.copyWith(
        recentErrors: nextErrors,
        updatedAt: errorRecord.createdAt,
      ),
      trackedAt: errorRecord.createdAt,
    );
  }

  AiSessionEnvironment _environmentFromRuntime(
    AiSessionRuntimeContext runtimeContext,
  ) {
    return AiSessionEnvironment(
      localeTag: runtimeContext.localeTag,
      platform: defaultTargetPlatform.name,
      appVersion: runtimeContext.appVersion,
      appBuildNumber: runtimeContext.appBuildNumber,
      applicationDirectory: OpenHandPaths.applicationDirectoryPath(),
      homeDirectory: OpenHandPaths.homeDirectoryPath(),
      settingsFilePath: runtimeContext.settingsFilePath,
      skillsStoragePath: runtimeContext.skillsStoragePath,
      mcpServersFilePath: runtimeContext.mcpServersFilePath,
      userMemoryFilePath: runtimeContext.userMemoryFilePath,
      sessionsDirectoryPath: OpenHandPaths.defaultSessionsDirectoryPath(),
      compressionThresholdChars: runtimeContext.compressionThresholdChars,
      singleRoundToolCallLimit: runtimeContext.singleRoundToolCallLimit,
      sequentialToolRoundLimit: runtimeContext.sequentialToolRoundLimit,
    );
  }

  /// Walks every user message in [session] looking for image attachments
  /// whose ids appear in [summariesByAttachmentId]; for each match it
  /// rewrites the attachment with the new [AiMessageAttachment.summaryText]
  /// and returns the updated session. Non-image attachments and unmatched
  /// ids are left alone.
  AiSession _applyImageSummariesToSession(
    AiSession session,
    Map<String, String> summariesByAttachmentId,
  ) {
    if (summariesByAttachmentId.isEmpty) {
      return session;
    }
    final updatedMessages = <AiSessionMessage>[];
    var sessionChanged = false;
    for (final message in session.messages) {
      if (message.kind != AiSessionMessageKind.user) {
        updatedMessages.add(message);
        continue;
      }
      final raw = message.metadata[aiSessionMessageAttachmentsMetadataKey];
      if (raw is! List || raw.isEmpty) {
        updatedMessages.add(message);
        continue;
      }
      final attachments = AiMessageAttachment.listFromMetadata(raw);
      if (attachments.isEmpty) {
        updatedMessages.add(message);
        continue;
      }
      var messageChanged = false;
      final rebuiltAttachments = <AiMessageAttachment>[];
      for (final attachment in attachments) {
        final summary = summariesByAttachmentId[attachment.id];
        if (summary == null || summary.isEmpty || !attachment.isImage) {
          rebuiltAttachments.add(attachment);
          continue;
        }
        if (attachment.summaryText.trim() == summary.trim()) {
          rebuiltAttachments.add(attachment);
          continue;
        }
        rebuiltAttachments.add(attachment.copyWith(summaryText: summary));
        messageChanged = true;
      }
      if (!messageChanged) {
        updatedMessages.add(message);
        continue;
      }
      sessionChanged = true;
      final newMetadata = <String, Object?>{
        ...message.metadata,
        aiSessionMessageAttachmentsMetadataKey:
            AiMessageAttachment.listToMetadata(rebuiltAttachments),
      };
      updatedMessages.add(message.copyWith(metadata: newMetadata));
    }
    if (!sessionChanged) {
      return session;
    }
    return session.copyWith(messages: updatedMessages);
  }

  AiSession _rebuildSession(
    AiSession session, {
    int? totalPromptCharacters,
    int? promptBuildCount,
    int? compressionRunCount,
    AiTokenUsage? totalUsage,
    int? lastPromptSystemMessageCount,
    int? lastPromptHistoryMessageCount,
  }) {
    final effectiveUsage =
        totalUsage ?? _usageFromStatistics(session.statistics);
    final trackedSession = _syncPlanHistory(session);
    return trackedSession.copyWith(
      statistics: AiSessionStatistics.fromMessages(
        trackedSession.messages,
        totalPromptCharacters:
            totalPromptCharacters ??
            trackedSession.statistics.totalPromptCharacters,
        promptBuildCount:
            promptBuildCount ?? trackedSession.statistics.promptBuildCount,
        compressionRunCount:
            compressionRunCount ??
            trackedSession.statistics.compressionRunCount,
        totalUsage: effectiveUsage,
        lastPromptSystemMessageCount:
            lastPromptSystemMessageCount ??
            trackedSession.statistics.lastPromptSystemMessageCount,
        lastPromptHistoryMessageCount:
            lastPromptHistoryMessageCount ??
            trackedSession.statistics.lastPromptHistoryMessageCount,
      ),
    );
  }

  AiTokenUsage _usageFromStatistics(AiSessionStatistics statistics) {
    return AiTokenUsage(
      promptTokens: statistics.totalPromptTokens,
      completionTokens: statistics.totalCompletionTokens,
      totalTokens: statistics.totalTokens,
      cacheCreationTokens: statistics.cacheCreationTokens,
      cacheReadTokens: statistics.cacheReadTokens,
    );
  }

  bool _shouldCompressSessionHistory(
    AiSession session,
    AiSessionRuntimeContext runtimeContext,
    AiModelConfig model,
  ) {
    final threshold = _effectiveCompressionThresholdChars(
      runtimeContext: runtimeContext,
      model: model,
    );
    if (threshold <= 0) {
      return false;
    }
    final activeConversationMessages = session.activeConversationMessages
        .where(
          (message) => message.kind != AiSessionMessageKind.compressionPoint,
        )
        .toList(growable: false);
    if (activeConversationMessages.isEmpty) {
      return false;
    }
    final totalCharacters = activeConversationMessages.fold<int>(
      0,
      (sum, message) => sum + message.characterCount,
    );
    return totalCharacters > threshold;
  }

  int _effectiveCompressionThresholdChars({
    required AiSessionRuntimeContext runtimeContext,
    required AiModelConfig model,
  }) {
    final configuredThreshold = runtimeContext.compressionThresholdChars;
    final modelCharacterBudget = _estimatedCharacterBudgetForModel(model);
    if (modelCharacterBudget == null) {
      return configuredThreshold;
    }
    return math.min(configuredThreshold, modelCharacterBudget);
  }

  int? _estimatedCharacterBudgetForModel(AiModelConfig model) {
    final maxContextTokens = model.maxContextTokens;
    if (maxContextTokens == null || maxContextTokens <= 0) {
      return null;
    }
    return maxContextTokens * _estimatedCharactersPerToken;
  }

  _CompressionWindowSelection _selectCompressionWindowForModelContext({
    required AiPromptTemplateBundle templateBundle,
    required AiThreadTemplate template,
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required AiModelConfig model,
    required List<AiSessionMessage> candidateMessages,
    required AiSessionMessage? previousCompressionPoint,
  }) {
    final maxContextTokens = model.maxContextTokens;
    if (candidateMessages.isEmpty ||
        maxContextTokens == null ||
        maxContextTokens <= 0) {
      return _CompressionWindowSelection(
        messagesToCompress: candidateMessages,
        discardedMessages: const <AiSessionMessage>[],
      );
    }
    if (_compressionPromptFitsModelContext(
      templateBundle: templateBundle,
      template: template,
      session: session,
      runtimeContext: runtimeContext,
      maxContextTokens: maxContextTokens,
      messagesToCompress: candidateMessages,
      previousCompressionPoint: previousCompressionPoint,
    )) {
      return _CompressionWindowSelection(
        messagesToCompress: candidateMessages,
        discardedMessages: const <AiSessionMessage>[],
      );
    }

    var left = 0;
    var right = candidateMessages.length - 1;
    var bestStartIndex = -1;
    while (left <= right) {
      final middle = left + ((right - left) ~/ 2);
      final candidateSlice = candidateMessages.sublist(middle);
      final fits = _compressionPromptFitsModelContext(
        templateBundle: templateBundle,
        template: template,
        session: session,
        runtimeContext: runtimeContext,
        maxContextTokens: maxContextTokens,
        messagesToCompress: candidateSlice,
        previousCompressionPoint: previousCompressionPoint,
      );
      if (fits) {
        bestStartIndex = middle;
        right = middle - 1;
      } else {
        left = middle + 1;
      }
    }

    if (bestStartIndex == -1) {
      return const _CompressionWindowSelection(
        messagesToCompress: <AiSessionMessage>[],
        discardedMessages: <AiSessionMessage>[],
      );
    }
    final resolvedStartIndex = bestStartIndex;
    return _CompressionWindowSelection(
      messagesToCompress: candidateMessages.sublist(resolvedStartIndex),
      discardedMessages: candidateMessages
          .take(resolvedStartIndex)
          .toList(growable: false),
    );
  }

  bool _compressionPromptFitsModelContext({
    required AiPromptTemplateBundle templateBundle,
    required AiThreadTemplate template,
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required int maxContextTokens,
    required List<AiSessionMessage> messagesToCompress,
    required AiSessionMessage? previousCompressionPoint,
  }) {
    if (messagesToCompress.isEmpty) {
      return false;
    }
    final prompt = _promptBuilder.buildCompressionPrompt(
      templateBundle: templateBundle,
      template: template,
      session: session,
      runtimeContext: runtimeContext,
      messagesToCompress: messagesToCompress,
      previousCompressionPoint: previousCompressionPoint,
    );
    final promptCharacters = prompt.fold<int>(
      0,
      (sum, message) => sum + message.promptCharacterCount,
    );
    return _estimateTokensFromCharacters(promptCharacters) <= maxContextTokens;
  }

  int _estimateTokensFromCharacters(int characterCount) {
    if (characterCount <= 0) {
      return 0;
    }
    return (characterCount + _estimatedCharactersPerToken - 1) ~/
        _estimatedCharactersPerToken;
  }

  Map<String, Object?> _decodeToolArguments(String arguments) {
    final trimmed = arguments.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }

  String _resolveToolCallMessageId(AiSession session, AiToolCall toolCall) {
    final existingIndex = session.messages.lastIndexWhere(
      (message) =>
          !message.isDeleted &&
          message.kind == AiSessionMessageKind.toolCall &&
          '${message.metadata['tool_call_id'] ?? ''}'.trim() == toolCall.id,
    );
    if (existingIndex == -1) {
      return _idGenerator();
    }
    return session.messages[existingIndex].id;
  }

  AiSession _syncToolCallExecutionMessage({
    required AiSession session,
    required String messageId,
    required AiToolCall toolCall,
    required String command,
    required String workingDirectory,
    required String status,
    required String stdout,
    required String stderr,
    required int elapsedMs,
    int? exitCode,
    String? resultText,
    DateTime? finishedAt,
    String? matchedRuleId,
    String? matchedRulePattern,
    bool? isWriteCommand,
    String? writeAnalysisReason,
    Map<String, Object?> additionalMetadata = const <String, Object?>{},
  }) {
    final finishedAtValue = finishedAt?.toUtc().toIso8601String();
    return _upsertMessage(
      session,
      messageId: messageId,
      create: () => AiSessionMessage.toolCall(
        id: messageId,
        content: _renderToolCallContent(
          name: toolCall.name,
          arguments: toolCall.arguments,
        ),
        createdAt: _clock().toUtc(),
        metadata: <String, Object?>{
          'tool_call_id': toolCall.id,
          'tool_name': toolCall.name,
          'tool_arguments': toolCall.arguments,
          'tool_calls': <Map<String, Object?>>[
            <String, Object?>{
              'id': toolCall.id,
              'name': toolCall.name,
              'arguments': toolCall.arguments,
            },
          ],
          'tool_execution_started_at': _clock().toUtc().toIso8601String(),
          'tool_execution_status': status,
          'tool_execution_command': command,
          'tool_execution_working_directory': workingDirectory,
          'tool_execution_stdout': stdout,
          'tool_execution_stderr': stderr,
          'tool_execution_elapsed_ms': elapsedMs,
          'tool_execution_duration_ms': elapsedMs,
          'tool_execution_exit_code': exitCode,
          'tool_execution_result': resultText,
          'tool_execution_finished_at': finishedAtValue,
          'tool_execution_matched_rule_id': matchedRuleId,
          'tool_execution_matched_rule_pattern': matchedRulePattern,
          'tool_execution_is_write_command': isWriteCommand,
          'tool_execution_write_analysis_reason': writeAnalysisReason,
          ...additionalMetadata,
        },
      ),
      update: (message) => message.copyWith(
        metadata: <String, Object?>{
          ...message.metadata,
          ...additionalMetadata,
          'tool_call_id': toolCall.id,
          'tool_name': toolCall.name,
          'tool_arguments': toolCall.arguments,
          'tool_calls': <Map<String, Object?>>[
            <String, Object?>{
              'id': toolCall.id,
              'name': toolCall.name,
              'arguments': toolCall.arguments,
            },
          ],
          'tool_execution_started_at':
              message.metadata['tool_execution_started_at'] ??
              _clock().toUtc().toIso8601String(),
          'tool_execution_status': status,
          'tool_execution_command': command,
          'tool_execution_working_directory': workingDirectory,
          'tool_execution_stdout': stdout,
          'tool_execution_stderr': stderr,
          'tool_execution_elapsed_ms': elapsedMs,
          'tool_execution_duration_ms': elapsedMs,
          'tool_execution_exit_code': exitCode,
          'tool_execution_result': resultText,
          'tool_execution_finished_at': finishedAtValue,
          'tool_execution_matched_rule_id': matchedRuleId,
          'tool_execution_matched_rule_pattern': matchedRulePattern,
          'tool_execution_is_write_command':
              isWriteCommand ??
              message.metadata['tool_execution_is_write_command'],
          'tool_execution_write_analysis_reason':
              writeAnalysisReason ??
              message.metadata['tool_execution_write_analysis_reason'],
        },
      ),
    );
  }

  Future<AiSession?> _commitCancelledPendingToolCalls(AiSession session) async {
    return _commitPendingToolCallsWithTerminalStatus(
      session,
      status: BashToolExecutionStatus.cancelled,
      debugLabel: 'cancelled',
      fallbackResultText:
          ({
            required String command,
            required String workingDirectory,
            required int elapsedMs,
            required bool hadStarted,
          }) => _cancelledToolExecutionResultText(
            command: command,
            workingDirectory: workingDirectory,
            elapsedMs: elapsedMs,
            hadStarted: hadStarted,
          ),
    );
  }

  Future<AiSession?> _commitPendingToolCallsWithTerminalStatus(
    AiSession session, {
    required BashToolExecutionStatus status,
    required String debugLabel,
    required String Function({
      required String command,
      required String workingDirectory,
      required int elapsedMs,
      required bool hadStarted,
    })
    fallbackResultText,
  }) async {
    final updatedSession = _markPendingToolCallsWithTerminalStatus(
      session,
      status: status,
      debugLabel: debugLabel,
      fallbackResultText: fallbackResultText,
    );
    if (identical(updatedSession, session)) {
      return session;
    }
    final committed = await _commitSessionLocked(updatedSession);
    if (!committed) {
      _setLastSendErrorMessage(
        session.id,
        'Failed to persist the ${status.storageValue} tool-call state.',
      );
      return null;
    }
    return updatedSession;
  }

  void _previewCancelledPendingToolCalls(String sessionId) {
    final liveSession = _sessionById(sessionId);
    if (liveSession == null) {
      return;
    }
    final cancelledSession = _markPendingToolCallsCancelled(liveSession);
    if (identical(cancelledSession, liveSession)) {
      return;
    }
    if (_replaceSessionInMemory(cancelledSession, sortSessions: false)) {
      notifyListeners();
    }
  }

  AiSession _markPendingToolCallsCancelled(AiSession session) {
    return _markPendingToolCallsWithTerminalStatus(
      session,
      status: BashToolExecutionStatus.cancelled,
      debugLabel: 'cancelled',
      fallbackResultText:
          ({
            required String command,
            required String workingDirectory,
            required int elapsedMs,
            required bool hadStarted,
          }) => _cancelledToolExecutionResultText(
            command: command,
            workingDirectory: workingDirectory,
            elapsedMs: elapsedMs,
            hadStarted: hadStarted,
          ),
    );
  }

  AiSession _markPendingToolCallsFailed(
    AiSession session, {
    required String detail,
  }) {
    return _markPendingToolCallsWithTerminalStatus(
      session,
      status: BashToolExecutionStatus.failed,
      debugLabel: 'failed',
      fallbackResultText:
          ({
            required String command,
            required String workingDirectory,
            required int elapsedMs,
            required bool hadStarted,
          }) => _failedToolExecutionResultText(
            command: command,
            workingDirectory: workingDirectory,
            elapsedMs: elapsedMs,
            detail: detail,
          ),
    );
  }

  AiSession _markPendingToolCallsWithTerminalStatus(
    AiSession session, {
    required BashToolExecutionStatus status,
    required String debugLabel,
    required String Function({
      required String command,
      required String workingDirectory,
      required int elapsedMs,
      required bool hadStarted,
    })
    fallbackResultText,
  }) {
    final finishedAt = _clock().toUtc();
    final updatedMessages = List<AiSessionMessage>.from(session.messages);
    var updatedCount = 0;
    for (var index = 0; index < updatedMessages.length; index++) {
      final message = updatedMessages[index];
      if (message.isDeleted || message.kind != AiSessionMessageKind.toolCall) {
        continue;
      }
      final currentStatus = '${message.metadata['tool_execution_status'] ?? ''}'
          .trim();
      if (_isTerminalToolExecutionStatus(currentStatus)) {
        continue;
      }
      updatedCount += 1;
      final command =
          '${message.metadata['tool_execution_command'] ?? message.metadata['tool_name'] ?? ''}'
              .trim();
      final workingDirectory =
          '${message.metadata['tool_execution_working_directory'] ?? ''}'
              .trim();
      final stdout = '${message.metadata['tool_execution_stdout'] ?? ''}';
      final stderr = '${message.metadata['tool_execution_stderr'] ?? ''}';
      final elapsedMs = _toolExecutionMetadataInt(
        message.metadata['tool_execution_elapsed_ms'] ??
            message.metadata['tool_execution_duration_ms'],
      );
      final resultText = '${message.metadata['tool_execution_result'] ?? ''}'
          .trim();
      updatedMessages[index] = message.copyWith(
        metadata: <String, Object?>{
          ...message.metadata,
          'tool_execution_status': status.storageValue,
          'tool_execution_command': command,
          'tool_execution_working_directory': workingDirectory,
          'tool_execution_stdout': stdout,
          'tool_execution_stderr': stderr,
          'tool_execution_elapsed_ms': elapsedMs,
          'tool_execution_duration_ms': elapsedMs,
          'tool_execution_result': resultText.isNotEmpty
              ? resultText
              : fallbackResultText(
                  command: command,
                  workingDirectory: workingDirectory,
                  elapsedMs: elapsedMs,
                  hadStarted: currentStatus == 'running',
                ),
          'tool_execution_finished_at': finishedAt.toIso8601String(),
        },
      );
    }
    if (updatedCount == 0) {
      return session;
    }
    _debugSessionLog(
      session.id,
      'tool_call_${debugLabel}_pending_messages count=$updatedCount',
    );
    return _syncPlanHistory(
      session.copyWith(messages: updatedMessages, updatedAt: finishedAt),
      trackedAt: finishedAt,
    );
  }

  int _toolExecutionMetadataInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> _enqueueSessionOperation<T>(
    String sessionId,
    Future<T> Function() operation,
  ) {
    final completer = Completer<T>();
    final previousQueue =
        _sessionOperationQueues[sessionId] ?? Future<void>.value();
    late final Future<void> nextQueue;
    nextQueue = previousQueue
        .catchError((_) {})
        .then((_) async {
          try {
            completer.complete(await operation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_sessionOperationQueues[sessionId], nextQueue)) {
            _sessionOperationQueues.remove(sessionId);
          }
        });
    _sessionOperationQueues[sessionId] = nextQueue;
    return completer.future;
  }

  void _setSessionSendPhase(String sessionId, AiSendPhase phase) {
    _debugSessionLog(sessionId, 'phase=$phase');
    _sessionSendPhases[sessionId] = phase;
  }

  void _clearSessionSendPhase(String sessionId) {
    _sessionSendPhases.remove(sessionId);
  }

  void _setSessionCancelHandler(
    String sessionId,
    Future<void> Function()? handler,
  ) {
    if (handler == null) {
      _sessionCancelHandlers.remove(sessionId);
      return;
    }
    _sessionCancelHandlers[sessionId] = handler;
  }

  bool _isStopRequestedForSession(String sessionId) {
    final stopSignal = _sessionStopSignals[sessionId];
    return stopSignal != null && stopSignal.isCompleted;
  }

  Future<void>? _stopSignalForSession(String sessionId) {
    return _sessionStopSignals[sessionId]?.future;
  }

  void _clearSessionExecutionState(String sessionId) {
    _debugSessionLog(sessionId, 'execution_state_cleared');
    _clearSessionSendPhase(sessionId);
    _approvalPreviousPhases.remove(sessionId);
    _sessionCancelHandlers.remove(sessionId);
    _sessionStopSignals.remove(sessionId);
  }

  void _debugSessionLog(String sessionId, String message) {
    return;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Telemetry instrumentation
  // ───────────────────────────────────────────────────────────────────────

  /// Truncates a long string for audit metadata so a pathological response
  /// cannot balloon the on-disk session file. The cap is controlled by the
  /// [AiSessionRuntimeContext.telemetryMaxPayloadChars] setting.
  String? _clampTelemetryPayload(String? value, int maxChars) {
    if (value == null) return null;
    if (maxChars <= 0 || value.length <= maxChars) return value;
    final kept = value.substring(0, maxChars);
    final dropped = value.length - maxChars;
    return '$kept\n\n…[telemetry_truncated: dropped $dropped chars]';
  }

  /// Renders the list of prompt turns (the final composed body sent to the
  /// AI) into a human-readable, copy-friendly transcript for the audit
  /// dialog. Each turn becomes a `# role` block followed by its content.
  String _renderComposedPromptForAudit(List<AiChatTurn> turns) {
    if (turns.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      if (i > 0) buffer.writeln('\n---\n');
      buffer.writeln('# [${i + 1}/${turns.length}] ${turn.roleName.toUpperCase()}');
      if (turn.toolCallId != null && turn.toolCallId!.isNotEmpty) {
        buffer.writeln('> tool_call_id: ${turn.toolCallId}');
      }
      buffer.writeln();
      buffer.write(turn.content);
      if (turn.toolCalls.isNotEmpty) {
        buffer.writeln();
        buffer.writeln();
        buffer.writeln('> tool_calls:');
        for (final call in turn.toolCalls) {
          buffer.writeln('>   - ${call.name} (${call.id})');
        }
      }
    }
    return buffer.toString();
  }

  /// Serialises prompt turns into a JSON-friendly structure that is stored
  /// on the user message's metadata for audit (stable, machine-parseable).
  List<Map<String, Object?>> _composedPromptTurnsForAudit(
    List<AiChatTurn> turns,
  ) {
    return turns
        .map(
          (turn) => <String, Object?>{
            'role': turn.roleName,
            if (turn.toolCallId != null && turn.toolCallId!.isNotEmpty)
              'tool_call_id': turn.toolCallId,
            'content': turn.content,
            if (turn.toolCalls.isNotEmpty)
              'tool_calls': turn.toolCalls
                  .map(
                    (call) => <String, Object?>{
                      'id': call.id,
                      'name': call.name,
                      'arguments': call.arguments,
                    },
                  )
                  .toList(growable: false),
            if (turn.parts.isNotEmpty)
              'parts': turn.parts
                  .map(
                    (part) => <String, Object?>{
                      'kind': part.kind.name,
                      if (part.text != null) 'text': part.text,
                      if (part.filePath != null) 'file_path': part.filePath,
                      if (part.mimeType != null) 'mime_type': part.mimeType,
                    },
                  )
                  .toList(growable: false),
          },
        )
        .toList(growable: false);
  }

  /// Snapshots the live process/OS environment for audit. Gated by the
  /// `telemetryCaptureEnvironment` setting because `Platform.environment`
  /// can contain secrets (API tokens, CI credentials, …).
  Map<String, Object?> _captureRuntimeEnvironmentSnapshot(
    AiSessionRuntimeContext runtimeContext,
  ) {
    Map<String, String> env;
    try {
      env = Map<String, String>.from(Platform.environment);
    } catch (_) {
      env = <String, String>{};
    }
    String? operatingSystemVersion;
    try {
      operatingSystemVersion = Platform.operatingSystemVersion;
    } catch (_) {
      operatingSystemVersion = null;
    }
    int? numberOfProcessors;
    try {
      numberOfProcessors = Platform.numberOfProcessors;
    } catch (_) {
      numberOfProcessors = null;
    }
    return <String, Object?>{
      'captured_at': _clock().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'operating_system_version': operatingSystemVersion,
      'number_of_processors': numberOfProcessors,
      'locale_name': Platform.localeName,
      'executable': Platform.resolvedExecutable,
      'script': Platform.script.toString(),
      'working_directory': runtimeContext.workingDirectory,
      'today_local_date': runtimeContext.todayLocalDate,
      'time_zone_name': runtimeContext.timeZoneName,
      'environment_variables': env,
      'environment_variable_count': env.length,
    };
  }

  /// Builds the telemetry metadata map that gets merged into a message's
  /// metadata after a round completes. Honours the three telemetry toggles
  /// (debug / captureRaw / captureEnvironment).
  Map<String, Object?> _buildRoundTelemetryMetadata({
    required AiChatStreamResult result,
    required AiSessionRuntimeContext runtimeContext,
  }) {
    if (!runtimeContext.telemetryDebugEnabled) {
      return const <String, Object?>{};
    }
    final maxChars = runtimeContext.telemetryMaxPayloadChars;
    final payload = <String, Object?>{
      if (result.startedAt != null)
        'started_at': result.startedAt!.toIso8601String(),
      if (result.endedAt != null)
        'ended_at': result.endedAt!.toIso8601String(),
      if (result.durationMs != null) 'duration_ms': result.durationMs,
      if (result.finishReason != null) 'finish_reason': result.finishReason,
      if (result.requestUrl != null) 'request_url': result.requestUrl,
      if (result.requestMethod != null)
        'request_method': result.requestMethod,
      if (result.requestHeaders != null && result.requestHeaders!.isNotEmpty)
        'request_headers': Map<String, String>.from(result.requestHeaders!),
      if (result.requestBody != null)
        'request_payload': Map<String, Object?>.from(result.requestBody!),
    };
    if (runtimeContext.telemetryCaptureRawPayload &&
        result.rawResponse != null &&
        result.rawResponse!.isNotEmpty) {
      payload['response_raw'] =
          _clampTelemetryPayload(result.rawResponse, maxChars);
    }
    if (runtimeContext.telemetryCaptureEnvironment) {
      payload['environment'] = _captureRuntimeEnvironmentSnapshot(
        runtimeContext,
      );
    }
    return payload;
  }

  /// Writes telemetry metadata onto the user / assistant / reasoning messages
  /// produced during a round without overwriting existing metadata keys.
  AiSession _applyRoundTelemetryToMessages({
    required AiSession session,
    required AiChatStreamResult result,
    required AiSessionRuntimeContext runtimeContext,
    required AiPromptBuildResult promptResult,
    String? userMessageId,
    String? assistantMessageId,
    String? reasoningMessageId,
  }) {
    if (!runtimeContext.telemetryDebugEnabled) {
      return session;
    }
    final telemetry = _buildRoundTelemetryMetadata(
      result: result,
      runtimeContext: runtimeContext,
    );
    if (telemetry.isEmpty &&
        userMessageId == null &&
        assistantMessageId == null &&
        reasoningMessageId == null) {
      return session;
    }
    final targetIds = <String>{
      if (userMessageId != null && userMessageId.isNotEmpty) userMessageId,
      if (assistantMessageId != null && assistantMessageId.isNotEmpty)
        assistantMessageId,
      if (reasoningMessageId != null && reasoningMessageId.isNotEmpty)
        reasoningMessageId,
    };
    if (targetIds.isEmpty) {
      return session;
    }
    // Composed prompt data has already been applied by the pre-stream phase
    // (_applyPreStreamTelemetryToUserMessage). Here we only apply
    // response-dependent data (timing, request/response payload, etc.) to
    // ALL target messages without duplicating the prompt fields.
    final updatedMessages = <AiSessionMessage>[];
    var changed = false;
    for (final message in session.messages) {
      if (!targetIds.contains(message.id)) {
        updatedMessages.add(message);
        continue;
      }
      final nextMetadata = <String, Object?>{
        ...message.metadata,
        ...telemetry,
      };
      updatedMessages.add(message.copyWith(metadata: nextMetadata));
      changed = true;
    }
    if (!changed) return session;
    return session.copyWith(
      messages: updatedMessages,
      updatedAt: _clock().toUtc(),
    );
  }

  /// Phase-1 (pre-stream) telemetry: attaches the composed prompt, prompt
  /// metadata and environment snapshot to the user message immediately so that
  /// the audit dialog already has meaningful data while the AI is still
  /// streaming its response.
  AiSession _applyPreStreamTelemetryToUserMessage({
    required AiSession session,
    required AiSessionRuntimeContext runtimeContext,
    required AiPromptBuildResult promptResult,
    required String userMessageId,
  }) {
    if (!runtimeContext.telemetryDebugEnabled) {
      return session;
    }
    if (userMessageId.isEmpty) return session;
    final composedPromptTurns = _composedPromptTurnsForAudit(
      promptResult.messages,
    );
    final composedPromptText = _renderComposedPromptForAudit(
      promptResult.messages,
    );
    final userExtras = <String, Object?>{
      if (composedPromptTurns.isNotEmpty)
        'composed_prompt_turns': composedPromptTurns,
      if (composedPromptText.isNotEmpty)
        'composed_prompt_text': _clampTelemetryPayload(
          composedPromptText,
          runtimeContext.telemetryMaxPayloadChars,
        ),
      if (promptResult.metadata.isNotEmpty)
        'prompt_metadata': Map<String, Object?>.from(promptResult.metadata),
      'prompt_character_count': promptResult.promptCharacterCount,
      'prompt_system_message_count': promptResult.systemMessageCount,
      'prompt_history_message_count': promptResult.historyMessageCount,
      // Mark a timestamp so the audit dialog knows data was captured.
      'telemetry_captured_at': _clock().toUtc().toIso8601String(),
    };
    if (runtimeContext.telemetryCaptureEnvironment) {
      userExtras['environment'] = _captureRuntimeEnvironmentSnapshot(
        runtimeContext,
      );
    }
    final updatedMessages = <AiSessionMessage>[];
    var changed = false;
    for (final message in session.messages) {
      if (message.id != userMessageId) {
        updatedMessages.add(message);
        continue;
      }
      final nextMetadata = <String, Object?>{
        ...message.metadata,
        ...userExtras,
      };
      updatedMessages.add(message.copyWith(metadata: nextMetadata));
      changed = true;
    }
    if (!changed) return session;
    return session.copyWith(
      messages: updatedMessages,
      updatedAt: _clock().toUtc(),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/openhand_paths.dart';
import '../mcp/service/mcp_tool_discovery_service.dart';
import 'data/ai_session_store.dart';
import 'model/ai_attachment.dart';
import 'model/ai_deny_command_rule.dart';
import 'model/ai_model_config.dart';
import 'model/ai_session.dart';
import 'model/ai_session_message.dart';
import 'model/ai_session_runtime_context.dart';
import 'model/ai_thread_template.dart';
import 'model/ai_token_usage.dart';
import 'service/ai_bash_tool_service.dart';
import 'service/ai_chat_service.dart';
import 'service/ai_claude_hook_service.dart';
import 'service/ai_prompt_builder.dart';
import 'service/ai_prompt_template_repository.dart';
import 'service/ai_attachment_service.dart';
import 'service/ai_protocol_adapter.dart';
import 'service/ai_tool_runtime_service.dart';

typedef WriteCommandConfirmationCallback =
    Future<bool> Function(BashCommandApprovalRequest request);

enum AiSendPhase { idle, compressing, sendingMessage, responding }

class AiSessionController extends ChangeNotifier {
  static const String _editRollbackMarkerKey = 'deleted_by_edit_message_id';

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
       _clock = clock;

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
          ),
      idGenerator: idGenerator ?? const Uuid().v4,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
    await controller.refresh();
    return controller;
  }

  static const int _maxRecentErrors = 20;
  static const int _defaultTitleMaxCharacters = 48;
  static const int _generatedTitleMaxCharacters = 20;
  static const String _defaultNewSessionTitle = '新会话';
  static const Duration _autoTitleRequestTimeout = Duration(seconds: 20);
  static const Duration _autoTitleRetryWaitTimeout = Duration(seconds: 45);
  static const Duration _autoTitleRetryPollInterval = Duration(
    milliseconds: 250,
  );
  static const Duration _streamPreviewThrottle = Duration(milliseconds: 48);
  static const Duration _reasoningStreamPreviewThrottle = Duration(
    milliseconds: 96,
  );
  static const int _slowPreviewLogThresholdMs = 12;
  static const int _slowCommitLogThresholdMs = 24;
  static const int _maxSequentialToolRounds = 8;
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
  final AiToolRuntimeService _toolRuntimeService;
  final AiAttachmentService _attachmentService;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

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
    return sendPhaseForSession(sessionId) == AiSendPhase.responding;
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
      notifyListeners();
      try {
        final loadResult = await _store.loadAll();
        _sessions = loadResult.sessions;
        _pruneSessionScopedSendState();
        _persistenceIssues = loadResult.issues;
        final currentSessionId = _currentSessionId;
        if (currentSessionId == null ||
            !_sessions.any((session) => session.id == currentSessionId)) {
          _currentSessionId = _sessions.isEmpty ? null : _sessions.first.id;
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
  }) async {
    if (isSending) {
      return _createSessionUnlocked(
        templateId: templateId,
        runtimeContext: runtimeContext,
      );
    }
    return _enqueueOperation(
      () => _createSessionUnlocked(
        templateId: templateId,
        runtimeContext: runtimeContext,
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
    if (selectedSession != null) {
      await _emitSessionStartHook(session: selectedSession, source: 'resume');
    }
    notifyListeners();
  }

  Future<bool> _createSessionUnlocked({
    required String templateId,
    required AiSessionRuntimeContext runtimeContext,
  }) async {
    final template = _templateRepository.resolveTemplate(templateId);
    final now = _clock().toUtc();
    _lastErrorMessage = null;
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

  Future<bool> renameSession(String sessionId, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return false;
    }
    return _enqueueOperation(() async {
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
        if (!await _store.exists(sessionId)) {
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

  Future<String?> beginEditingMessage(String messageId) async {
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
      return updatedMessages[messageIndex].content;
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
    return _enqueueOperation(() async {
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
        if (userHookResult.userFeedback.isNotEmpty) {
          userMessageMetadata[aiUserPromptHookFeedbackMetadataKey] =
              userHookResult.userFeedback;
        }
        if (userHookResult.systemReminders.isNotEmpty) {
          userMessageMetadata[aiHookSystemRemindersMetadataKey] =
              userHookResult.systemReminders;
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

        if (preparedUserTurn.shouldGenerateTitle) {
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
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    return adapter.supportsAttachmentsForModel(model);
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
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    _debugSessionLog(
      session.id,
      'assistant_conversation_start model=${model.modelId} latest_user_message_id=${latestUserMessageId ?? ''}',
    );
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
    final tools = toolCatalog.definitions;
    var workingSession = session;
    var activeLatestUserMessageId = latestUserMessageId;
    var toolRoundCount = 0;
    var toolCallCount = 0;
    final singleRoundToolCallLimit = math.max(
      1,
      runtimeContext.singleRoundToolCallLimit,
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
      final toolsForRound = workingSession.awaitingPlanApproval
          ? const <AiToolDefinition>[]
          : tools;
      _debugSessionLog(
        workingSession.id,
        'stream_round_start round=${toolRoundCount + 1} awaiting_plan_approval=${workingSession.awaitingPlanApproval} tools=${toolsForRound.length}',
      );
      final promptResult = _promptBuilder.buildSessionPrompt(
        templateBundle: templateBundle,
        session: workingSession,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: runtimeContext.memoryEntries,
        sessionMessages: workingSession.activeConversationMessages,
        latestUserMessageId: activeLatestUserMessageId,
      );
      final streamResponse = await _chatClient.sendMessageStream(
        model: model,
        messages: promptResult.messages,
        tools: toolsForRound,
      );
      _debugSessionLog(
        workingSession.id,
        'stream_opened round=${toolRoundCount + 1} prompt_messages=${promptResult.messages.length}',
      );
      _setSessionCancelHandler(workingSession.id, streamResponse.cancel);

      var streamedSession = workingSession;
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
      var hasPreviewedStreamDelta = false;

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

      void flushPreview(String reason) {
        final previewStopwatch = Stopwatch()..start();
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
        previewStopwatch.stop();
        if (previewStopwatch.elapsedMilliseconds >=
            _slowPreviewLogThresholdMs) {
          _debugSessionLog(
            workingSession.id,
            'stream_preview_slow reason=$reason elapsed_ms=${previewStopwatch.elapsedMilliseconds} messages=${sessionToPreview.messages.length} last_kind=${lastMessage?.kind.storageValue ?? 'none'}',
          );
        }
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
      streamedSession = syncFinalAssistantMessage(
        streamedSession,
        result.reply,
      );
      streamedSession = syncFinalReasoningMessage(
        streamedSession,
        result.reasoning,
      );
      streamedSession = setReasoningStreamingState(streamedSession, false);
      flushPreview('stream_completed');
      _debugSessionLog(
        workingSession.id,
        'stream_completed cancelled=${result.wasCancelled} reply_chars=${result.reply.length} reasoning_chars=${result.reasoning.length} tool_calls=${result.toolCalls.length}',
      );

      final didCancelStream =
          result.wasCancelled || _isStopRequestedForSession(workingSession.id);
      final toolSyncStopwatch = Stopwatch()..start();
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
      toolSyncStopwatch.stop();
      if (toolSyncStopwatch.elapsedMilliseconds >= _slowPreviewLogThresholdMs) {
        _debugSessionLog(
          workingSession.id,
          'tool_call_sync_slow elapsed_ms=${toolSyncStopwatch.elapsedMilliseconds} tool_calls=${result.toolCalls.length} messages=${streamedSession.messages.length}',
        );
      }
      final rebasedSession = _sessionById(workingSession.id) ?? workingSession;
      final effectiveUsage = streamedUsage ?? result.usage;
      final totalUsage = _usageFromStatistics(
        rebasedSession.statistics,
      ).merge(effectiveUsage ?? const AiTokenUsage());
      streamedSession = _rebuildSession(
        rebasedSession.copyWith(
          messages: streamedSession.messages,
          updatedAt: _clock().toUtc(),
          lastUsedModelId: model.id,
          lastUsedModelLabel: model.displayName,
          lastPromptMetadata: promptResult.metadata,
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

      if (result.toolCalls.isEmpty) {
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
      if (toolRoundCount > _maxSequentialToolRounds) {
        _debugSessionLog(
          workingSession.id,
          'tool_round_limit_exceeded count=$toolRoundCount',
        );
        await _emitStopFailureHook(
          sessionId: workingSession.id,
          stage: 'tool_loop',
          detail:
              'tool_round_count=$toolRoundCount limit=$_maxSequentialToolRounds',
        );
        final failedToolSession = _markPendingToolCallsFailed(
          workingSession,
          detail:
              'The tool call was stopped because the assistant exceeded the sequential tool round safety limit.',
        );
        final limitedSession = _appendError(
          failedToolSession,
          stage: 'tool_loop',
          message:
              'The assistant requested too many sequential tool rounds and was stopped for safety.',
          detail:
              'tool_round_count=$toolRoundCount limit=$_maxSequentialToolRounds',
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
        toolCatalog: toolCatalog,
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
      return await _toolRuntimeService.execute(
        sessionId: executionSessionId ?? sessionId,
        catalog: toolCatalog,
        toolCall: toolCall,
        model: model,
        previouslyReadFiles: readFilePaths,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
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
    return command.isEmpty ? toolCall.name : command;
  }

  String _toolCallWorkingDirectory(AiToolCall toolCall) {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    return '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
        .trim();
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
      case AiBuiltinToolKind.task:
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

  bool _looksLikePlanApproval(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
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
    if (!_shouldCompressSessionHistory(session, runtimeContext)) {
      return session;
    }
    final activeConversationMessages = session.activeConversationMessages
        .where(
          (message) => message.kind != AiSessionMessageKind.compressionPoint,
        )
        .toList(growable: false);
    final threshold = runtimeContext.compressionThresholdChars;

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

    final messagesToCompress = activeConversationMessages
        .take(compressedMessageCount)
        .toList(growable: false);
    final previousCompressionPoint = session.latestCompressionPoint;
    final templateBundle = await _templateRepository.loadBundle(
      session.templateId,
    );
    try {
      await _emitCompactHooks(
        sessionId: session.id,
        eventName: 'PreCompact',
        trigger: 'auto',
        payload: <String, Object?>{
          'messages_to_compress_count': messagesToCompress.length,
        },
      );
      final compressionPrompt = _promptBuilder.buildCompressionPrompt(
        templateBundle: templateBundle,
        template: _templateRepository.resolveTemplate(session.templateId),
        session: session,
        runtimeContext: runtimeContext,
        messagesToCompress: messagesToCompress,
        previousCompressionPoint: previousCompressionPoint,
      );
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: compressionPrompt,
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
          'source_character_count': sourceCharacterCount,
          'retained_message_ids_after_checkpoint': retainedMessages
              .map((message) => message.id)
              .toList(growable: false),
          'summary_model_id': model.id,
          'summary_model_label': model.displayName,
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
        content:
            'Generate a concise chat title. Return a single title only. Keep it within 20 characters. No quotes. No markdown.',
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
        if (generatedTitle.isEmpty) {
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
            title: generatedTitle,
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
    final latestSession = _sessionById(sessionId);
    if (latestSession == null) {
      return;
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

  bool _isRetryableAutoTitleError(Object error) {
    return '$error'.contains('Request timed out.');
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
    final messageIndex = session.messages.indexWhere(
      (message) => message.id == messageId,
    );
    final updatedMessages = List<AiSessionMessage>.from(session.messages);
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

  void _previewSession(AiSession session) {
    final stopwatch = Stopwatch()..start();
    final replaced = _replaceSessionInMemory(session, sortSessions: false);
    if (replaced) {
      notifyListeners();
    }
    stopwatch.stop();
    if (stopwatch.elapsedMilliseconds >= _slowPreviewLogThresholdMs) {
      final lastMessage = session.messages.isEmpty
          ? null
          : session.messages.last;
      _debugSessionLog(
        session.id,
        'preview_session_slow elapsed_ms=${stopwatch.elapsedMilliseconds} replaced=$replaced messages=${session.messages.length} last_kind=${lastMessage?.kind.storageValue ?? 'none'} last_chars=${lastMessage?.characterCount ?? 0}',
      );
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
    final previousSession = _sessionById(session.id);
    final effectiveSession = _mergeLiveSessionState(session, previousSession);
    final previousIssues = List<AiSessionPersistenceIssue>.from(
      _persistenceIssues,
    );
    final commitStopwatch = Stopwatch()..start();
    _replaceSessionInMemory(effectiveSession);
    notifyListeners();
    try {
      await _store.save(effectiveSession);
      commitStopwatch.stop();
      if (commitStopwatch.elapsedMilliseconds >= _slowCommitLogThresholdMs) {
        _debugSessionLog(
          session.id,
          'commit_session_slow elapsed_ms=${commitStopwatch.elapsedMilliseconds} messages=${effectiveSession.messages.length} recent_errors=${effectiveSession.recentErrors.length}',
        );
      }
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
      commitStopwatch.stop();
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

  bool _environmentEquals(
    AiSessionEnvironment left,
    AiSessionEnvironment right,
  ) {
    return left.localeTag == right.localeTag &&
        left.platform == right.platform &&
        left.appVersion == right.appVersion &&
        left.appBuildNumber == right.appBuildNumber &&
        left.applicationDirectory == right.applicationDirectory &&
        left.homeDirectory == right.homeDirectory &&
        left.settingsFilePath == right.settingsFilePath &&
        left.skillsStoragePath == right.skillsStoragePath &&
        left.mcpServersFilePath == right.mcpServersFilePath &&
        left.userMemoryFilePath == right.userMemoryFilePath &&
        left.sessionsDirectoryPath == right.sessionsDirectoryPath &&
        left.compressionThresholdChars == right.compressionThresholdChars;
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

  bool _stringListsEqual(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
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
    return session.copyWith(
      recentErrors: nextErrors,
      updatedAt: errorRecord.createdAt,
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
    );
  }

  String _toolCallLimitWarningMessage({
    required AiSessionRuntimeContext runtimeContext,
    required int toolCallCount,
    required int limit,
  }) {
    if (_prefersChineseLocale(runtimeContext.localeTag)) {
      return '本轮对话中的工具调用次数已达到 $toolCallCount 次，超过当前设置的上限 $limit 次。OpenHand 已发送警告并安全终止本轮响应。';
    }
    return 'This response reached $toolCallCount tool calls, which exceeds the configured limit of $limit. OpenHand posted a warning and stopped the round for safety.';
  }

  bool _prefersChineseLocale(String localeTag) {
    return localeTag.trim().toLowerCase().startsWith('zh');
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
    return session.copyWith(
      statistics: AiSessionStatistics.fromMessages(
        session.messages,
        totalPromptCharacters:
            totalPromptCharacters ?? session.statistics.totalPromptCharacters,
        promptBuildCount:
            promptBuildCount ?? session.statistics.promptBuildCount,
        compressionRunCount:
            compressionRunCount ?? session.statistics.compressionRunCount,
        totalUsage: effectiveUsage,
        lastPromptSystemMessageCount:
            lastPromptSystemMessageCount ??
            session.statistics.lastPromptSystemMessageCount,
        lastPromptHistoryMessageCount:
            lastPromptHistoryMessageCount ??
            session.statistics.lastPromptHistoryMessageCount,
      ),
    );
  }

  AiTokenUsage _usageFromStatistics(AiSessionStatistics statistics) {
    return AiTokenUsage(
      promptTokens: statistics.totalPromptTokens,
      completionTokens: statistics.totalCompletionTokens,
      totalTokens: statistics.totalTokens,
    );
  }

  String _deriveSessionTitle(
    AiSession session,
    AiSessionMessage latestUserMessage,
  ) {
    final hasExistingUserMessages = session.messages.any(
      (message) =>
          !message.isDeleted && message.kind == AiSessionMessageKind.user,
    );
    if (hasExistingUserMessages &&
        session.title.trim().isNotEmpty &&
        session.title.trim() != session.templateName &&
        session.autoTitleSourceMessageId != latestUserMessage.id &&
        !session.isTitleManuallyEdited) {
      return session.title;
    }
    final characters = latestUserMessage.content.characters;
    if (characters.isEmpty) {
      return session.title;
    }
    final truncated = characters.take(_defaultTitleMaxCharacters).toString();
    if (characters.length <= _defaultTitleMaxCharacters) {
      return truncated;
    }
    return '$truncated...';
  }

  String _sanitizeGeneratedTitle(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('"') && normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    if (normalized.startsWith('《') && normalized.endsWith('》')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    normalized = normalized.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final collapsed = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) {
      return '';
    }
    return collapsed.characters.take(_generatedTitleMaxCharacters).toString();
  }

  String _sanitizeVisibleModelContent(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    var cursor = 0;
    while (cursor < lines.length && lines[cursor].trim().isEmpty) {
      cursor += 1;
    }
    if (cursor >= lines.length ||
        !_internalPromptLeakHeaders.contains(lines[cursor].trim())) {
      return normalized;
    }
    while (cursor < lines.length) {
      final trimmed = lines[cursor].trim();
      if (trimmed.isEmpty || _internalPromptLeakHeaders.contains(trimmed)) {
        cursor += 1;
        continue;
      }
      break;
    }
    final sanitized = lines.skip(cursor).join('\n').trimLeft();
    if (sanitized.length == normalized.length) {
      return normalized;
    }
    return sanitized;
  }

  bool _shouldCompressSessionHistory(
    AiSession session,
    AiSessionRuntimeContext runtimeContext,
  ) {
    final threshold = runtimeContext.compressionThresholdChars;
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

  String _renderToolCallContent({
    required String name,
    required String arguments,
  }) {
    final normalizedName = name.trim().isEmpty ? 'tool' : name.trim();
    final prettyArguments = _prettyToolArguments(arguments);
    return '**$normalizedName**\n\n```json\n$prettyArguments\n```';
  }

  String _prettyToolArguments(String arguments) {
    final trimmed = arguments.trim();
    if (trimmed.isEmpty) {
      return '{}';
    }
    try {
      final decoded = jsonDecode(trimmed);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return trimmed;
    }
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
    return session.copyWith(messages: updatedMessages, updatedAt: finishedAt);
  }

  bool _isTerminalToolExecutionStatus(String status) {
    return switch (status) {
      'success' ||
      'failed' ||
      'cancelled' ||
      'denied' ||
      'rejected' ||
      'timed_out' ||
      'invalid_arguments' => true,
      _ => false,
    };
  }

  int _toolExecutionMetadataInt(Object? rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
  }

  String _cancelledToolExecutionResultText({
    required String command,
    required String workingDirectory,
    required int elapsedMs,
    required bool hadStarted,
  }) {
    final resolvedCommand = command.isEmpty ? 'tool_call' : command;
    final buffer = StringBuffer()
      ..writeln('status: cancelled')
      ..writeln('command: $resolvedCommand')
      ..writeln('working_directory: $workingDirectory')
      ..writeln('duration_ms: $elapsedMs')
      ..write(
        hadStarted
            ? 'detail: The tool execution was cancelled by the user.'
            : 'detail: The tool call was cancelled before execution started.',
      );
    return buffer.toString();
  }

  String _failedToolExecutionResultText({
    required String command,
    required String workingDirectory,
    required int elapsedMs,
    required String detail,
  }) {
    final resolvedCommand = command.isEmpty ? 'tool_call' : command;
    final buffer = StringBuffer()
      ..writeln('status: failed')
      ..writeln('command: $resolvedCommand')
      ..writeln('working_directory: $workingDirectory')
      ..writeln('duration_ms: $elapsedMs')
      ..write('detail: $detail');
    return buffer.toString();
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
    _sessionCancelHandlers.remove(sessionId);
    _sessionStopSignals.remove(sessionId);
  }

  void _debugSessionLog(String sessionId, String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[OpenHand][AiSession][$sessionId] $message');
  }
}

class _ClaudeCodeDocsTarget {
  const _ClaudeCodeDocsTarget({required this.url, required this.label});

  final String url;
  final String label;
}

class _ScoredClaudeCodeDocsRoute {
  const _ScoredClaudeCodeDocsRoute({
    required this.route,
    required this.score,
    required this.priority,
  });

  final String route;
  final int score;
  final int priority;
}

class _RunningToolCallState {
  const _RunningToolCallState({
    required this.toolCall,
    required this.messageId,
    required this.executionSessionId,
  });

  final AiToolCall toolCall;
  final String messageId;
  final String executionSessionId;
}

class _PreparedUserTurn {
  const _PreparedUserTurn({
    required this.session,
    required this.userMessage,
    required this.shouldGenerateTitle,
    required this.importedAttachments,
  });

  final AiSession session;
  final AiSessionMessage userMessage;
  final bool shouldGenerateTitle;
  final bool importedAttachments;
}

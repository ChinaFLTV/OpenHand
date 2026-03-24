import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/openhand_paths.dart';
import 'data/ai_session_store.dart';
import 'model/ai_deny_command_rule.dart';
import 'model/ai_model_config.dart';
import 'model/ai_session.dart';
import 'model/ai_session_message.dart';
import 'model/ai_session_runtime_context.dart';
import 'model/ai_thread_template.dart';
import 'model/ai_token_usage.dart';
import 'service/ai_bash_tool_service.dart';
import 'service/ai_chat_service.dart';
import 'service/ai_prompt_builder.dart';
import 'service/ai_prompt_template_repository.dart';
import 'service/ai_protocol_adapter.dart';

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
    required String Function() idGenerator,
    required DateTime Function() clock,
  }) : _store = store,
       _chatClient = chatClient,
       _backgroundChatClient = backgroundChatClient,
       _templateRepository = templateRepository,
       _promptBuilder = promptBuilder,
       _bashToolService = bashToolService,
       _idGenerator = idGenerator,
       _clock = clock;

  static Future<AiSessionController> create({
    AiSessionStore? store,
    AiChatClient? chatClient,
    AiChatClient? backgroundChatClient,
    AiPromptTemplateRepository? templateRepository,
    AiPromptBuilder? promptBuilder,
    AiBashToolService? bashToolService,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final resolvedChatClient = chatClient ?? AiChatService();
    final controller = AiSessionController._(
      store: store ?? AiSessionStore(),
      chatClient: resolvedChatClient,
      backgroundChatClient:
          backgroundChatClient ??
          (chatClient == null ? AiChatService() : resolvedChatClient),
      templateRepository: templateRepository ?? AiPromptTemplateRepository(),
      promptBuilder: promptBuilder ?? const AiPromptBuilder(),
      bashToolService: bashToolService ?? AiBashToolService(),
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
  static const int _maxSequentialToolRounds = 8;
  static const Set<String> _internalPromptLeakHeaders = <String>{
    '[[5] Current Session Messages]',
    '# [0] System Instructions',
    '# [1] Developer Instructions',
    '# [2] Session Metadata (ephemeral)',
    '# [3] User Memory (long-term facts)',
    '# [4] Recent Conversations Summary (past chats, titles + snippets)',
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
  bool _didCompressInLastSend = false;
  String? _currentSessionId;
  String? _editingMessageId;
  String? _lastErrorMessage;
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

  bool get didCompressInLastSend => _didCompressInLastSend;
  String? get currentSessionId => _currentSessionId;
  String? get editingMessageId => _editingMessageId;
  String? get lastErrorMessage => _lastErrorMessage;
  List<AiSession> get sessions => List<AiSession>.unmodifiable(_sessions);
  List<AiSessionPersistenceIssue> get persistenceIssues =>
      List<AiSessionPersistenceIssue>.unmodifiable(_persistenceIssues);
  List<AiThreadTemplate> get templates => _templateRepository.templates;
  String get sessionsDirectoryPath => _store.sessionsDirectoryPath;

  AiSendPhase sendPhaseForSession(String? sessionId) => sessionId == null
      ? AiSendPhase.idle
      : (_sessionSendPhases[sessionId] ?? AiSendPhase.idle);

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
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    notifyListeners();
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
        return true;
      } catch (error) {
        _deletedSessionIds.remove(sessionId);
        _sessions = previousSessions;
        _currentSessionId = previousCurrentSessionId;
        _editingMessageId = previousEditingMessageId;
        _lastErrorMessage = '$error';
        notifyListeners();
        return false;
      }
    });
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
    final stopSignal = _sessionStopSignals.putIfAbsent(
      sessionId,
      Completer<void>.new,
    );
    if (!stopSignal.isCompleted) {
      stopSignal.complete();
    }
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
    List<AiDenyCommandRule> denyCommandRules = const <AiDenyCommandRule>[],
    bool requireWriteCommandConfirmation = true,
    WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
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
        _lastErrorMessage = 'No active session selected.';
        notifyListeners();
        return false;
      }

      _setSessionSendPhase(session.id, AiSendPhase.sendingMessage);
      _sessionCancelHandlers.remove(session.id);
      _sessionStopSignals[session.id] = Completer<void>();
      _didCompressInLastSend = false;
      _lastErrorMessage = null;
      notifyListeners();

      try {
        session = session.copyWith(
          environment: _environmentFromRuntime(runtimeContext),
        );
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

        final preparedUserTurn = _prepareUserTurn(
          session: session,
          content: normalizedContent,
          model: model,
          runtimeContext: runtimeContext,
        );
        session = preparedUserTurn.session;
        final userCommitted = await _commitSessionLocked(session);
        if (!userCommitted) {
          _lastErrorMessage = 'Failed to persist the user message.';
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
        final current = _sessionById(resolvedSessionId);
        if (current != null) {
          final updated = _appendError(
            current,
            stage: 'chat_request',
            message: '$error',
            detail: '$error',
          );
          await _commitSessionLocked(updated);
        }
        _lastErrorMessage = '$error';
        notifyListeners();
        return false;
      } finally {
        _clearSessionExecutionState(resolvedSessionId);
        notifyListeners();
      }
    });
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
    final templateBundle = await _templateRepository.loadBundle(
      session.templateId,
    );
    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final tools = adapter.supportsToolCalls
        ? _defaultToolDefinitions
        : const <AiToolDefinition>[];
    var workingSession = session;
    var activeLatestUserMessageId = latestUserMessageId;
    var toolRoundCount = 0;

    while (true) {
      final latestSession = _sessionById(workingSession.id);
      if (latestSession != null) {
        workingSession = latestSession;
      }
      if (_isStopRequestedForSession(workingSession.id)) {
        return true;
      }
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
        tools: tools,
      );
      _setSessionCancelHandler(workingSession.id, streamResponse.cancel);

      var streamedSession = workingSession;
      String? assistantMessageId;
      String? reasoningMessageId;
      AiTokenUsage? streamedUsage;
      final toolCallMessageIds = <int, String>{};
      final assistantRawBuffer = StringBuffer();
      final reasoningRawBuffer = StringBuffer();

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

      final subscription = streamResponse.events.listen((event) {
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            streamedSession = setReasoningStreamingState(
              streamedSession,
              false,
            );
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
            final resolvedMessageId = reasoningMessageId ?? _idGenerator();
            reasoningMessageId = resolvedMessageId;
            streamedSession = _upsertMessage(
              streamedSession,
              messageId: resolvedMessageId,
              create: () => AiSessionMessage.reasoning(
                id: resolvedMessageId,
                content: sanitizedContent,
                createdAt: _clock().toUtc(),
                modelId: model.id,
                modelLabel: model.displayName,
                metadata: const <String, Object?>{
                  aiSessionMessageMetadataStreamingKey: true,
                },
              ),
              update: (message) => message.copyWith(
                content: sanitizedContent,
                modelId: model.id,
                modelLabel: model.displayName,
                metadata: <String, Object?>{
                  ...message.metadata,
                  aiSessionMessageMetadataStreamingKey: true,
                },
              ),
            );
          case AiChatStreamEventType.toolCallDelta:
            streamedSession = setReasoningStreamingState(
              streamedSession,
              false,
            );
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
          case AiChatStreamEventType.usage:
            streamedUsage = event.usage;
        }
        _previewSession(streamedSession);
      });

      final eventDrain = subscription.asFuture<void>();
      late final AiChatStreamResult result;
      try {
        result = await streamResponse.result;
        try {
          await eventDrain.timeout(const Duration(milliseconds: 800));
        } on TimeoutException {
          await subscription.cancel();
        }
      } catch (error) {
        await subscription.cancel();
        _setSessionCancelHandler(workingSession.id, null);
        streamedSession = setReasoningStreamingState(streamedSession, false);
        final failedSession = _appendError(
          streamedSession,
          stage: 'chat_stream',
          message: '$error',
          detail: '$error',
        );
        await _commitSessionLocked(_rebuildSession(failedSession));
        _lastErrorMessage = '$error';
        notifyListeners();
        return false;
      }
      _setSessionCancelHandler(workingSession.id, null);
      streamedSession = setReasoningStreamingState(streamedSession, false);

      streamedSession = _syncToolCallMessagesFromResult(
        streamedSession,
        result.toolCalls,
        model,
      );
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
        _lastErrorMessage = 'Failed to persist the assistant reply.';
        return false;
      }
      workingSession = streamedSession;

      if (result.wasCancelled ||
          _isStopRequestedForSession(workingSession.id)) {
        return true;
      }

      if (result.toolCalls.isEmpty) {
        return true;
      }
      toolRoundCount += 1;
      if (toolRoundCount > _maxSequentialToolRounds) {
        final limitedSession = _appendError(
          workingSession,
          stage: 'tool_loop',
          message:
              'The assistant requested too many sequential tool rounds and was stopped for safety.',
          detail:
              'tool_round_count=$toolRoundCount limit=$_maxSequentialToolRounds',
        );
        await _commitSessionLocked(_rebuildSession(limitedSession));
        _lastErrorMessage =
            'The assistant requested too many sequential tool rounds and was stopped for safety.';
        return false;
      }

      final executedSession = await _executeToolCalls(
        session: workingSession,
        toolCalls: result.toolCalls,
        denyCommandRules: denyCommandRules,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
      );
      if (executedSession == null) {
        return false;
      }
      workingSession = executedSession;
      activeLatestUserMessageId = null;
      if (_isStopRequestedForSession(workingSession.id)) {
        return true;
      }
    }
  }

  Future<AiSession?> _executeToolCalls({
    required AiSession session,
    required List<AiToolCall> toolCalls,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
  }) async {
    var workingSession = session;
    for (final toolCall in toolCalls) {
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
        _lastErrorMessage = 'Failed to persist the running tool-call state.';
        return null;
      }
      final result = await _executeSingleToolCall(
        sessionId: workingSession.id,
        toolCall: toolCall,
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
      );
      final toolMessage = AiSessionMessage.toolResult(
        id: _idGenerator(),
        content: result.toToolOutput(),
        createdAt: _clock().toUtc(),
        metadata: <String, Object?>{
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
        },
      );
      workingSession = _rebuildSession(
        workingSession.copyWith(
          updatedAt: toolMessage.createdAt,
          messages: <AiSessionMessage>[...workingSession.messages, toolMessage],
        ),
      );
      final committed = await _commitSessionLocked(workingSession);
      if (!committed) {
        _lastErrorMessage = 'Failed to persist the tool execution result.';
        return null;
      }
    }
    return workingSession;
  }

  Future<BashToolExecutionResult> _executeSingleToolCall({
    required String sessionId,
    required AiToolCall toolCall,
    required List<AiDenyCommandRule> denyCommandRules,
    required bool requireWriteCommandConfirmation,
    required WriteCommandConfirmationCallback? confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
  }) async {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    final command =
        '${decodedArguments['cmd'] ?? decodedArguments['command'] ?? ''}'
            .trim();
    final workingDirectory =
        '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
            .trim();

    if (toolCall.name != 'bash') {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: command,
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: 'Unsupported tool name: ${toolCall.name}',
        durationMs: 0,
      );
    }

    if (command.isEmpty) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: '',
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: 'The bash tool requires a non-empty cmd field.',
        durationMs: 0,
      );
    }

    try {
      return await _bashToolService.execute(
        command: command,
        workingDirectory: workingDirectory,
        denyRules: denyCommandRules,
        requireWriteConfirmation: requireWriteCommandConfirmation,
        confirmWriteCommand: confirmWriteCommand,
        onUpdate: onUpdate,
        cancelSignal: _stopSignalForSession(sessionId),
      );
    } catch (error) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: command,
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: '$error',
        durationMs: 0,
      );
    }
  }

  String _toolCallCommand(AiToolCall toolCall) {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    return '${decodedArguments['cmd'] ?? decodedArguments['command'] ?? ''}'
        .trim();
  }

  String _toolCallWorkingDirectory(AiToolCall toolCall) {
    final decodedArguments = _decodeToolArguments(toolCall.arguments);
    return '${decodedArguments['working_directory'] ?? decodedArguments['cwd'] ?? ''}'
        .trim();
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
      final latestCompressionPointIndex = session.latestCompressionPointIndex;
      final preservedHead = latestCompressionPointIndex == null
          ? const <AiSessionMessage>[]
          : session.messages
                .take(latestCompressionPointIndex)
                .toList(growable: false);
      final updatedMessages = <AiSessionMessage>[
        ...preservedHead,
        checkpoint,
        ...retainedMessages,
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
              (sum, message) => sum + message.content.length,
            ),
        promptBuildCount: session.statistics.promptBuildCount + 1,
        compressionRunCount: session.statistics.compressionRunCount + 1,
        totalUsage: totalUsage,
      );
      final committed = await _commitSessionLocked(compressedSession);
      if (committed) {
        _didCompressInLastSend = true;
      }
      return committed ? compressedSession : session;
    } catch (error) {
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

  _PreparedUserTurn _prepareUserTurn({
    required AiSession session,
    required String content,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
  }) {
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
          metadata: <String, Object?>{
            ...original.metadata,
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
        );
      }
      _editingMessageId = null;
    }

    final userMessage = AiSessionMessage.user(
      id: _idGenerator(),
      content: content,
      createdAt: now,
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
                (sum, message) => sum + message.content.length,
              ),
          promptBuildCount: latestSession.statistics.promptBuildCount + 1,
          totalUsage: totalUsage,
        );
        await _commitSessionLocked(updatedSession);
        return;
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
    if (_replaceSessionInMemory(session)) {
      notifyListeners();
    }
  }

  bool _replaceSessionInMemory(AiSession session) {
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
      updatedSessions.sort(
        (left, right) => right.updatedAt.compareTo(left.updatedAt),
      );
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
    );
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
        },
      ),
      update: (message) => message.copyWith(
        metadata: <String, Object?>{
          ...message.metadata,
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
    _clearSessionSendPhase(sessionId);
    _sessionCancelHandlers.remove(sessionId);
    _sessionStopSignals.remove(sessionId);
  }

  static const List<AiToolDefinition>
  _defaultToolDefinitions = <AiToolDefinition>[
    AiToolDefinition(
      name: 'bash',
      description:
          'Execute a shell command in a subprocess. Use cmd for the command string and optionally working_directory for the working directory.',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'cmd': <String, Object?>{
            'type': 'string',
            'description': 'The exact shell command to execute.',
          },
          'working_directory': <String, Object?>{
            'type': 'string',
            'description':
                'Optional working directory for the command execution.',
          },
        },
        'required': <String>['cmd'],
        'additionalProperties': false,
      },
    ),
  ];
}

class _PreparedUserTurn {
  const _PreparedUserTurn({
    required this.session,
    required this.userMessage,
    required this.shouldGenerateTitle,
  });

  final AiSession session;
  final AiSessionMessage userMessage;
  final bool shouldGenerateTitle;
}

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/silent_log.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../ai/index.dart';
import '../instructions/index.dart';
import '../knowledge_base/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'data/dingtalk_message_gateway_store.dart';
import 'message_gateway_dependencies.dart';
import 'model/dingtalk_message_gateway.dart';
import 'service/dingtalk_message_gateway_service.dart';

typedef DingTalkWriteApprovalHandler =
    Future<BashCommandApprovalDecision> Function(
      String sessionId,
      BashCommandApprovalRequest request,
    );

class _QueuedDingTalkResponse {
  _QueuedDingTalkResponse(this.content, Completer<void> completer)
    : waiters = <Completer<void>>[completer];

  String content;
  final List<Completer<void>> waiters;

  void merge(String nextContent, Completer<void> completer) {
    content = '$content\n\n$nextContent';
    waiters.add(completer);
  }

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

class DingTalkMessageGatewayController extends ChangeNotifier {
  DingTalkMessageGatewayController(
    MessageGatewayDependencies dependencies, {
    DingTalkMessageGatewayStore? store,
    DingTalkMessageGatewayService? service,
  }) : _sessionController = dependencies.sessionController,
       _settingsController = dependencies.settingsController,
       _skillsController = dependencies.skillsController,
       _mcpController = dependencies.mcpController,
       _memoryController = dependencies.memoryController,
       _instructionsController = dependencies.instructionsController,
       _knowledgeBaseController = dependencies.knowledgeBaseController,
       _appInfo = dependencies.appInfo,
       _store = store ?? DingTalkMessageGatewayStore(),
       _service = service ?? DingTalkMessageGatewayService() {
    _runtimeLogSubscription = _service.runtimeLogStream.listen((_) {
      _notify();
    });
  }

  static const Uuid _uuid = Uuid();
  static const int _maxSeenIds = 2000;
  static const Duration _queryWindow = Duration(minutes: 10);
  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final InstructionsController _instructionsController;
  final KnowledgeBaseController? _knowledgeBaseController;
  final AppInfo _appInfo;
  final DingTalkMessageGatewayStore _store;
  final DingTalkMessageGatewayService _service;
  StreamSubscription<String>? _runtimeLogSubscription;
  final Map<String, DingTalkConversation> _conversations =
      <String, DingTalkConversation>{};
  final Set<String> _responseInFlight = <String>{};
  final Map<String, Queue<_QueuedDingTalkResponse>> _responseQueues =
      <String, Queue<_QueuedDingTalkResponse>>{};
  final Set<String> _responseDraining = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  final Map<String, (DateTime, List<DingTalkConversationTarget>)>
  _targetSearchCache = <String, (DateTime, List<DingTalkConversationTarget>)>{};
  Timer? _pollTimer;
  StreamSubscription<DingTalkGatewayMessage>? _eventSubscription;
  Future<void>? _persistInFlight;
  bool _persistQueued = false;
  Object? _persistenceError;
  bool _pollInFlight = false;
  bool _usingPollingFallback = false;
  bool _initialized = false;
  bool _disposed = false;
  DingTalkWriteApprovalHandler? _writeApprovalHandler;
  bool _isAuthenticating = false;
  bool _isPolling = false;
  bool _isSending = false;
  int _unreadCount = 0;
  String? _errorMessage;
  String? _warningMessage;
  String? _deviceUrl;
  DingTalkAuthStatus _authStatus = const DingTalkAuthStatus(
    authenticated: false,
  );
  DingTalkGatewaySettings _settings = const DingTalkGatewaySettings();
  DateTime _lastPollAt = DateTime.now().subtract(_queryWindow);

  bool get isInstalled => _service.cachedExecutable != null;
  bool get isAuthenticating => _isAuthenticating;
  bool get isAuthorized => _authStatus.authenticated;
  bool get isPolling => _isPolling;
  bool get isRealtimeListening => _isPolling && _eventSubscription != null;
  bool get isPollingFallback => _isPolling && _usingPollingFallback;
  bool get isSending => _isSending;
  int get unreadCount => _unreadCount;
  String? get errorMessage => _errorMessage;
  String? get warningMessage => _warningMessage;
  String? get deviceUrl => _deviceUrl;
  String get deviceCode {
    final value = _deviceUrl;
    if (value == null) return '';
    return Uri.tryParse(value)?.queryParameters['user_code'] ?? '';
  }

  DingTalkAuthStatus get authStatus => _authStatus;
  DingTalkGatewaySettings get settings => _settings;
  List<String> get runtimeLogs => _service.runtimeLogs;
  int get runtimeLogRevision => _service.runtimeLogRevision;

  void clearRuntimeLogs() {
    _service.clearRuntimeLogs();
    _notify();
  }

  /// 由应用层注入审批弹窗协调器，控制器本身不持有 BuildContext。
  set writeApprovalHandler(DingTalkWriteApprovalHandler? handler) {
    _writeApprovalHandler = handler;
  }

  List<AiModelConfig> get aiModels =>
      List<AiModelConfig>.unmodifiable(_settingsController.aiModels);
  AiModelConfig? get activeAiModel => _settingsController.selectedAiModel;
  List<AiThreadTemplate> get templates => List<AiThreadTemplate>.unmodifiable(
    _sessionController.availableTemplates,
  );
  List<McpServer> get mcpServers =>
      List<McpServer>.unmodifiable(_mcpController.runtimeServers);
  List<LocalSkill> get skills =>
      List<LocalSkill>.unmodifiable(_skillsController.skills);
  List<UserMemoryEntry> get memories =>
      List<UserMemoryEntry>.unmodifiable(_memoryController.entries);
  List<UserInstructionEntry> get instructions =>
      List<UserInstructionEntry>.unmodifiable(_instructionsController.entries);
  List<KnowledgeSource> get knowledgeSources =>
      List<KnowledgeSource>.unmodifiable(
        _knowledgeBaseController?.sources ?? const <KnowledgeSource>[],
      );
  List<DingTalkConversation> get conversations {
    final values = _conversations.values.toList(growable: false);
    return values..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<DingTalkConversationTarget>> searchTargets({
    required DingTalkConversationType type,
    required String query,
  }) async {
    if (!isAuthorized || query.trim().isEmpty) {
      return const <DingTalkConversationTarget>[];
    }
    final key = '${type.name}:${query.trim().toLowerCase()}';
    final cached = _targetSearchCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 5)) {
      return cached.$2;
    }
    try {
      final results = await _service.searchTargets(type: type, query: query);
      _targetSearchCache[key] = (DateTime.now(), results);
      while (_targetSearchCache.length > 20) {
        _targetSearchCache.remove(_targetSearchCache.keys.first);
      }
      return results;
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '搜索钉钉会话', error, stack);
      return const <DingTalkConversationTarget>[];
    }
  }

  void openConversation(DingTalkConversationTarget target) {
    if (_conversations.containsKey(target.id)) return;
    _conversations[target.id] = DingTalkConversation(
      id: target.id,
      type: target.type,
      title: target.title,
      directUserId: target.userId.trim().isEmpty ? null : target.userId.trim(),
      directOpenDingTalkId: target.openDingTalkId.trim().isEmpty
          ? null
          : target.openDingTalkId.trim(),
    );
    _queuePersist();
    _notify();
  }

  /// 只移除 OpenHand 本地会话，不影响钉钉侧真实群聊或联系人。
  Future<void> deleteConversation(String conversationId) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return;
    await stopConversationResponse(conversationId);
    _conversations.remove(conversationId);
    _queuePersist();
    _notify();
  }

  bool isConversationResponding(String conversationId) {
    final conversation = _conversations[conversationId];
    final sessionId = conversation?.aiSessionId;
    return _responseInFlight.contains(conversationId) ||
        (_responseQueues[conversationId]?.isNotEmpty ?? false) ||
        (sessionId != null && _sessionController.canStopResponding(sessionId));
  }

  Future<void> stopConversationResponse(String conversationId) async {
    final conversation = _conversations[conversationId];
    final sessionId = conversation?.aiSessionId;
    if (sessionId != null && _sessionController.canStopResponding(sessionId)) {
      await _sessionController.stopResponding(sessionId);
    }
    final queue = _responseQueues.remove(conversationId);
    if (queue != null) {
      for (final item in queue) {
        item.complete();
      }
    }
    _responseInFlight.remove(conversationId);
    _notify();
  }

  Future<Object?> loadConversationDetails(String conversationId) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return null;
    return _service.conversationDetails(conversation: conversation);
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    try {
      final snapshot = await _store.loadSnapshot();
      _settings = _normalizeSettings(snapshot.settings);
      _conversations
        ..clear()
        ..addEntries(
          snapshot.conversations
              .where((conversation) => conversation.id.trim().isNotEmpty)
              .map((conversation) => MapEntry(conversation.id, conversation)),
        );
      _seenMessageIds.clear();
      final persistedMessages = <DingTalkGatewayMessage>[];
      for (final conversation in _conversations.values) {
        persistedMessages.addAll(conversation.messages);
      }
      persistedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final firstSeenIndex = persistedMessages.length > _maxSeenIds
          ? persistedMessages.length - _maxSeenIds
          : 0;
      for (final message in persistedMessages.skip(firstSeenIndex)) {
        _remember(message.id);
      }
      await refreshAuthStatus();
    } catch (error, stack) {
      _setError('初始化钉钉消息网关', error, stack);
    } finally {
      _initialized = true;
      _notify();
    }
  }

  Future<void> refreshAuthStatus() async {
    try {
      _authStatus = await _service.authStatus();
      if (!_authStatus.authenticated && _isPolling) {
        unawaited(stopPolling());
      }
      _clearError();
    } catch (error, stack) {
      _setError('读取钉钉授权状态', error, stack);
    }
    _notify();
  }

  Future<void> authorize(Future<void> Function(String url) openUrl) async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    _clearError();
    _notify();
    try {
      _authStatus = await _service.authorize(
        onDeviceUrl: (url) async {
          _deviceUrl = url;
          _notify();
          await openUrl(url);
        },
      );
    } catch (error, stack) {
      _setError('钉钉设备流授权', error, stack);
    } finally {
      _isAuthenticating = false;
      _deviceUrl = null;
      await refreshAuthStatus();
      _notify();
    }
  }

  Future<void> cancelAuthorization() async {
    // 取消授权与轮询互斥：先释放定时器，避免注销过程中继续查询消息。
    await stopPolling();
    try {
      await _service.cancelAuthorization();
    } catch (error, stack) {
      _setError('取消钉钉设备流授权', error, stack);
    }
    _isAuthenticating = false;
    _notify();
  }

  Future<void> logout() async {
    // 立即停止轮询，即使底层注销命令失败也不留下后台定时任务。
    final profile = _authStatus.identity.profile;
    await stopPolling();
    _authStatus = const DingTalkAuthStatus(authenticated: false);
    _notify();
    try {
      await _service.logout(profile: profile);
      _clearError();
    } catch (error, stack) {
      _setError('取消钉钉授权', error, stack);
    } finally {
      await refreshAuthStatus();
    }
    _notify();
  }

  Future<void> updateSettings(DingTalkGatewaySettings value) async {
    final normalized = _normalizeSettings(value);
    if (_settings.templateId != normalized.templateId) {
      for (final conversation in _conversations.values) {
        conversation.aiSessionId = null;
      }
    }
    _settings = normalized;
    _queuePersist();
    final task = _persistInFlight;
    if (task != null) await task;
    final persistenceError = _persistenceError;
    if (persistenceError != null) {
      throw StateError('保存钉钉网关设置失败：$persistenceError');
    }
    if (_isPolling && _usingPollingFallback) _schedulePolling();
    _notify();
  }

  /// 刷新设置弹窗使用的资源目录。资源控制器各自负责并发与持久化，
  /// 这里仅预热 MCP 工具目录并清理已删除资源的历史选择。
  Future<void> refreshResourceCatalogs() async {
    final refreshTasks = <Future<void>>[
      _skillsController.refresh(),
      _memoryController.refresh(),
      _instructionsController.refresh(),
      if (_knowledgeBaseController != null)
        _knowledgeBaseController.initialize(),
    ];
    try {
      await Future.wait<void>(refreshTasks).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // 资源目录刷新有界等待，已完成的控制器快照仍可继续使用。
    }
    await _mcpController.ensureRuntimeToolCatalogs(
      maxWait: const Duration(seconds: 6),
    );
    final normalized = _normalizeSettings(_settings);
    if (normalized.toJson().toString() != _settings.toJson().toString()) {
      _settings = normalized;
      _queuePersist();
      final task = _persistInFlight;
      if (task != null) await task;
    }
    _notify();
  }

  void startPolling() {
    if (_isPolling || !isAuthorized) return;
    _isPolling = true;
    _usingPollingFallback = false;
    _warningMessage = null;
    _lastPollAt = DateTime.now().subtract(_queryWindow);
    _notify();
    unawaited(_startEventListening());
  }

  Future<void> stopPolling() async {
    _isPolling = false;
    _usingPollingFallback = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _notify();
    await _stopEventListening();
  }

  Future<void> pollNow() => _pollOnce();

  Future<bool> sendMessage(String conversationId, String text) async {
    final conversation = _conversations[conversationId];
    final content = text.trim();
    if (conversation == null ||
        content.isEmpty ||
        _isSending ||
        !isAuthorized) {
      return false;
    }
    _isSending = true;
    _appendMessage(
      conversation,
      DingTalkGatewayMessage(
        id: 'local-${_uuid.v4()}',
        conversationId: conversation.id,
        conversationType: conversation.type,
        role: DingTalkGatewayMessageRole.user,
        content: content,
        createdAt: DateTime.now(),
        senderName: _authStatus.identity.label,
        senderId: _authStatus.identity.userId,
        fromSelf: true,
      ),
    );
    _notify();
    try {
      await _service.send(
        conversation: conversation,
        text: content,
        uuid: _uuid.v4(),
      );
      await _enqueueAiResponse(conversation, content);
      return true;
    } catch (error, stack) {
      _setError('发送钉钉消息', error, stack);
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  Future<void> _pollOnce() async {
    if (!_isPolling || _pollInFlight || !isAuthorized || _disposed) return;
    _pollInFlight = true;
    try {
      final now = DateTime.now();
      final result = await _service.query(start: _lastPollAt, end: now);
      _lastPollAt = now.subtract(const Duration(seconds: 2));
      _warningMessage = result.warning;
      for (final message in result.messages) {
        _handleIncomingMessage(message);
      }
      _clearError();
    } catch (error, stack) {
      _setError('轮询钉钉消息', error, stack);
      await refreshAuthStatus();
      if (!isAuthorized) await stopPolling();
    } finally {
      _pollInFlight = false;
      _notify();
    }
  }

  Future<void> _startEventListening() async {
    try {
      final stream = await _service.startEventSubscription();
      if (!_isPolling || _disposed) {
        await _service.stopEventSubscription();
        return;
      }
      _eventSubscription = stream.listen(
        _handleIncomingMessage,
        onError: (Object error, StackTrace stack) {
          silentLog('dingtalk_gateway', '实时事件监听异常', error, stack);
          unawaited(_fallbackToPolling());
        },
        onDone: () {
          unawaited(_fallbackToPolling());
        },
      );
      _usingPollingFallback = false;
      _clearError();
      _warningMessage = null;
      _notify();
    } catch (error, stack) {
      if (!_isPolling || _disposed) return;
      silentLog('dingtalk_gateway', '启动实时事件监听', error, stack);
      await _fallbackToPolling();
    }
  }

  Future<void> _fallbackToPolling() async {
    if (!_isPolling || _disposed || _usingPollingFallback) return;
    _usingPollingFallback = true;
    await _stopEventListening();
    if (!_isPolling || _disposed) return;
    _warningMessage = '实时事件监听暂不可用，已启用有界轮询兜底。';
    _clearError();
    _schedulePolling(immediate: true);
    _notify();
  }

  Future<void> _stopEventListening() async {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await subscription?.cancel();
    await _service.stopEventSubscription();
  }

  void _handleIncomingMessage(DingTalkGatewayMessage message) {
    if (!_isPolling || _disposed) return;
    if (_seenMessageIds.contains(message.id)) return;
    if (_isSelf(message)) {
      _remember(message.id);
      return;
    }
    final allowedTarget = _allowedTargetFor(message);
    if (allowedTarget == null) {
      _remember(message.id);
      return;
    }
    _remember(message.id);
    final conversationId =
        message.conversationType == DingTalkConversationType.group
        ? message.conversationId
        : allowedTarget.id;
    final conversation = _conversations.putIfAbsent(
      conversationId,
      () => DingTalkConversation(
        id: conversationId,
        type: message.conversationType,
        title: allowedTarget.title.trim().isNotEmpty
            ? allowedTarget.title
            : message.conversationTitle.trim().isNotEmpty
            ? message.conversationTitle
            : message.senderName.trim().isEmpty
            ? '钉钉会话'
            : message.senderName,
        directUserId: allowedTarget.userId.trim().isEmpty
            ? null
            : allowedTarget.userId.trim(),
        directOpenDingTalkId: allowedTarget.openDingTalkId.trim().isEmpty
            ? null
            : allowedTarget.openDingTalkId.trim(),
      ),
    );
    _appendMessage(conversation, message);
    _unreadCount += 1;
    if (_settings.reminderMode == DingTalkReminderMode.sound) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    unawaited(_enqueueAiResponse(conversation, message.content));
    _notify();
  }

  DingTalkConversationTarget? _allowedTargetFor(
    DingTalkGatewayMessage message,
  ) {
    if (message.conversationType == DingTalkConversationType.group) {
      if (!message.mentionedCurrentUser) return null;
      final conversationId = message.conversationId.trim();
      for (final target in _settings.allowedGroupTargets) {
        if (target.identifiers.contains(conversationId)) return target;
      }
      return null;
    }
    final candidates = <String>{
      message.senderId.trim(),
      message.conversationId.trim(),
    }..remove('');
    for (final target in _settings.allowedContactTargets) {
      if (target.identifiers.any(candidates.contains)) return target;
    }
    return null;
  }

  void _schedulePolling({bool immediate = false}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: _settings.pollIntervalSeconds),
      (_) => unawaited(_pollOnce()),
    );
    if (immediate) unawaited(_pollOnce());
  }

  Future<void> _respondWithAi(
    DingTalkConversation conversation,
    String content,
  ) async {
    if (!_responseInFlight.add(conversation.id)) return;
    _notify();
    try {
      final model = _resolveModel();
      final templates = _sessionController.availableTemplates;
      if (model == null || templates.isEmpty) return;
      await _mcpController.ensureRuntimeToolCatalogs(
        maxWait: const Duration(seconds: 6),
      );
      final selectedTemplate = templates.where(
        (item) => item.id == _settings.templateId,
      );
      final templateId = selectedTemplate.isNotEmpty
          ? selectedTemplate.first.id
          : templates.any((item) => item.id == 'default')
          ? 'default'
          : templates.first.id;
      final selectedMcp = _mcpController.runtimeServers
          .where(
            (server) => _settings.allowedMcpServerNames.contains(server.name),
          )
          .toList(growable: false);
      final selectedSkills = _skillsController.skills
          .where((skill) => _settings.allowedSkillNames.contains(skill.name))
          .toList(growable: false);
      final selectedMemoryIds = _settings.allowedMemoryIds.toSet();
      final selectedMemory = _settingsController.memoryEnabled
          ? (await _memoryController.trustedEntriesSnapshot().timeout(
                      const Duration(seconds: 5),
                      onTimeout: () => null,
                    ) ??
                    const <UserMemoryEntry>[])
                .where((entry) => selectedMemoryIds.contains(entry.id))
                .toList(growable: false)
          : const <UserMemoryEntry>[];
      final selectedInstructions = _instructionsController.entries
          .where((entry) => _settings.allowedInstructionIds.contains(entry.id))
          .toList(growable: false);
      final knowledgeBaseController = _knowledgeBaseController;
      final selectedKnowledgeSourceIds = knowledgeBaseController == null
          ? const <String>[]
          : _settings.allowedKnowledgeBaseSourceIds
                .where(
                  (id) => knowledgeBaseController.sources.any(
                    (source) => source.id == id,
                  ),
                )
                .toList(growable: false);
      final builtinToolConfigs = selectedKnowledgeSourceIds.isEmpty
          ? const <AiBuiltinToolConfig>[]
          : _knowledgeBuiltinToolConfigs();
      final runtimeContext = buildAiSessionRuntimeContext(
        settingsController: _settingsController,
        appInfo: _appInfo,
        appThemeBrightness: _settingsController.themeMode.name,
        localNow: DateTime.now().toLocal(),
        workingDirectory: _settings.workingDirectory,
        memoryEntries: selectedMemory,
        allowCommandRules: _settingsController.aiAllowCommandRules,
        availableSkills: selectedSkills,
        availableMcpServers: selectedMcp,
        mcpToolCatalogsByServerName: <String, McpToolCatalog>{
          for (final server in selectedMcp)
            server.name: _mcpController.toolCatalogFor(server.name),
        },
        builtinToolConfigs: builtinToolConfigs,
        userInstructions: selectedInstructions,
        templateId: templateId,
        toolExecutionMetadata: <String, Object?>{
          'source': 'dingtalk_gateway',
          'dingtalk_working_directory_boundary': _settings.workingDirectory,
          'dingtalk_allowed_knowledge_source_ids': selectedKnowledgeSourceIds,
        },
      );
      var sessionId = conversation.aiSessionId;
      if (sessionId == null) {
        final created = await _sessionController.createSession(
          templateId: templateId,
          runtimeContext: runtimeContext,
          title: '钉钉 · ${conversation.title}',
          fullAccessPermission: _settings.fullAccessPermission,
          initialModelProviderConfigId: model.id,
          initialModelId: model.modelId,
          metadata: <String, Object?>{
            'created_via': 'dingtalk_gateway',
            'dingtalk_conversation_id': conversation.id,
          },
          selectAfterCreate: false,
        );
        if (!created) return;
        for (final candidate in _sessionController.sessions.reversed) {
          if (candidate.isDingTalkGatewaySession &&
              candidate.metadata['dingtalk_conversation_id'] ==
                  conversation.id) {
            sessionId = candidate.id;
            break;
          }
        }
        conversation.aiSessionId = sessionId;
      }
      if (sessionId == null) return;
      await _sessionController.updateSessionFullAccessPermission(
        sessionId,
        _settings.fullAccessPermission,
      );
      AiSession? sessionBeforeEcho;
      for (final candidate in _sessionController.sessions) {
        if (candidate.id == sessionId) {
          sessionBeforeEcho = candidate;
          break;
        }
      }
      final baselineMessageIds = sessionBeforeEcho == null
          ? <String>{}
          : sessionBeforeEcho.messages.map((message) => message.id).toSet();
      final selectedEchoTypes = _settings.responseEchoTypes.toSet();
      final echoedMessageIds = <String>{};
      var allowFinalResponseEcho = false;
      var echoTail = Future<void>.value();

      AiSession? currentSession() {
        for (final item in _sessionController.sessions) {
          if (item.id == sessionId) return item;
        }
        return null;
      }

      void queueEchoes(AiSession session) {
        final candidates = <AiSessionMessage>[];
        for (final message in session.messages) {
          if (baselineMessageIds.contains(message.id) ||
              echoedMessageIds.contains(message.id)) {
            continue;
          }
          final type = _completedEchoTypeOf(message, session.messages);
          if (type == null || !selectedEchoTypes.contains(type)) continue;
          if (type == DingTalkResponseEchoType.finalResponse &&
              !allowFinalResponseEcho) {
            continue;
          }
          candidates.add(message);
        }
        if (allowFinalResponseEcho) {
          AiSessionMessage? latestAssistant;
          for (final message in candidates.reversed) {
            if (message.kind == AiSessionMessageKind.assistant &&
                _completedEchoTypeOf(message, session.messages) ==
                    DingTalkResponseEchoType.finalResponse) {
              latestAssistant = message;
              break;
            }
          }
          candidates.removeWhere(
            (message) =>
                message.kind == AiSessionMessageKind.assistant &&
                _completedEchoTypeOf(message, session.messages) ==
                    DingTalkResponseEchoType.finalResponse &&
                message.id != latestAssistant?.id,
          );
        }
        final candidateOrder = <String, int>{
          for (var index = 0; index < candidates.length; index++)
            candidates[index].id: index,
        };
        candidates.sort((a, b) {
          final time = _echoCompletionTime(a).compareTo(_echoCompletionTime(b));
          return time == 0
              ? candidateOrder[a.id]!.compareTo(candidateOrder[b.id]!)
              : time;
        });
        for (final message in candidates) {
          final type = _completedEchoTypeOf(message, session.messages);
          if (type == null || !echoedMessageIds.add(message.id)) continue;
          final text = _echoTextForMessage(message, session.messages);
          if (text.trim().isEmpty) {
            echoedMessageIds.remove(message.id);
            continue;
          }
          echoTail = echoTail.then((_) async {
            try {
              await _sendDingTalkEcho(
                conversation: conversation,
                source: message,
                text: text,
              );
            } catch (error, stack) {
              silentLog('dingtalk_gateway', '同步钉钉 AI 过程消息', error, stack);
            }
          });
        }
      }

      void onSessionChanged() {
        if (_disposed) return;
        final session = currentSession();
        if (session != null) queueEchoes(session);
      }

      _sessionController.addListener(onSessionChanged);
      try {
        final requireWriteConfirmation =
            AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
              templateId: templateId,
              fullAccessPermission: _settings.fullAccessPermission,
              globalConfirmationEnabled:
                  _settingsController.aiWriteCommandConfirmationEnabled,
            );
        final sent = await _sessionController.sendMessage(
          sessionId: sessionId,
          content: content,
          model: model,
          runtimeContext: runtimeContext,
          denyCommandRules: _settingsController.aiDenyCommandRules,
          requireWriteCommandConfirmation: requireWriteConfirmation,
          confirmWriteCommand: requireWriteConfirmation
              ? (request) {
                  if (_settingsController.aiAllowCommandRules.any(
                    (rule) => rule.matches(request.command),
                  )) {
                    return Future<BashCommandApprovalDecision>.value(
                      BashCommandApprovalDecision.approved,
                    );
                  }
                  final handler = _writeApprovalHandler;
                  if (handler == null) {
                    return Future<BashCommandApprovalDecision>.value(
                      BashCommandApprovalDecision.rejected,
                    );
                  }
                  return handler(sessionId!, request);
                }
              : null,
          userMessageMetadata: const <String, Object?>{
            'sent_via': 'dingtalk_gateway',
          },
        );
        if (sent) {
          allowFinalResponseEcho = true;
          final session = currentSession();
          if (session != null) queueEchoes(session);
        }
        await echoTail;
        if (!sent) return;
      } finally {
        _sessionController.removeListener(onSessionChanged);
        await echoTail;
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '生成钉钉 AI 回复', error, stack);
    } finally {
      _responseInFlight.remove(conversation.id);
      _notify();
    }
  }

  static const Set<String> _terminalToolEchoStatuses = <String>{
    'success',
    'failed',
    'cancelled',
    'denied',
    'rejected',
    'timed_out',
    'invalid_arguments',
    'blocked',
  };
  static const int _maxDingTalkEchoCharacters = 12000;
  static const int _maxDingTalkToolCellCharacters = 900;
  static const int _maxDingTalkToolFormattingCharacters = 12000;

  DingTalkResponseEchoType? _completedEchoTypeOf(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    if (message.isDeleted || message.content.trim().isEmpty) return null;
    if (message.metadata[aiSessionMessageMetadataStreamingKey] == true) {
      return null;
    }
    if (message.metadata[aiSessionGoalEvaluationMessageMetadataKey] == true) {
      return null;
    }
    return switch (message.kind) {
      AiSessionMessageKind.reasoning => DingTalkResponseEchoType.thinking,
      AiSessionMessageKind.status => DingTalkResponseEchoType.process,
      AiSessionMessageKind.assistant =>
        _isIntermediateAssistantMessage(message, sessionMessages)
            ? DingTalkResponseEchoType.process
            : DingTalkResponseEchoType.finalResponse,
      AiSessionMessageKind.toolCall || AiSessionMessageKind.hook =>
        _terminalToolEchoStatuses.contains(
              '${message.metadata['tool_execution_status'] ?? message.metadata['tool_status'] ?? message.metadata['status'] ?? ''}'
                  .trim()
                  .toLowerCase(),
            )
            ? DingTalkResponseEchoType.toolCall
            : null,
      _ => null,
    };
  }

  bool _isIntermediateAssistantMessage(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    final index = sessionMessages.indexWhere((item) => item.id == message.id);
    if (index < 0) return false;
    return sessionMessages
        .skip(index + 1)
        .any(
          (item) =>
              !item.isDeleted &&
              (item.kind == AiSessionMessageKind.toolCall ||
                  item.kind == AiSessionMessageKind.hook),
        );
  }

  Future<void> _sendDingTalkEcho({
    required DingTalkConversation conversation,
    required AiSessionMessage source,
    required String text,
  }) async {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final normalized = clipTextByCodeUnits(
      text.trim(),
      _maxDingTalkEchoCharacters,
      suffix: '\n\n…内容已截断',
    );
    if (normalized.isEmpty) return;
    await _service
        .send(conversation: conversation, text: normalized, uuid: _uuid.v4())
        .timeout(const Duration(seconds: 30));
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    _appendMessage(
      conversation,
      DingTalkGatewayMessage(
        id: 'assistant-${source.id}',
        conversationId: conversation.id,
        conversationType: conversation.type,
        role: DingTalkGatewayMessageRole.assistant,
        content: normalized,
        createdAt: source.createdAt,
      ),
    );
    _notify();
  }

  String _echoTextForMessage(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    if (message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook) {
      return _formatDingTalkToolEcho(message, sessionMessages);
    }
    return message.content.trim();
  }

  String _formatDingTalkToolEcho(
    AiSessionMessage call,
    List<AiSessionMessage> sessionMessages,
  ) {
    final metadata = call.metadata;
    final toolCallId = _boundedToolValue(metadata['tool_call_id'] ?? call.id);
    final toolName = _boundedToolValue(metadata['tool_name'] ?? '工具');
    final arguments = _toolArgumentsValue(metadata);
    final matchingResult = _matchingToolResult(call, sessionMessages);
    final response = _toolResponseValue(metadata, matchingResult);
    final status =
        '${metadata['tool_execution_status'] ?? metadata['tool_status'] ?? metadata['status'] ?? ''}'
            .trim()
            .toLowerCase();
    final durationMs = _toolDurationMilliseconds(call);
    final statusLabel = switch (status) {
      'success' => '成功',
      'timed_out' => '超时',
      'cancelled' => '已取消',
      'denied' || 'rejected' => '已拒绝',
      'invalid_arguments' => '参数无效',
      'blocked' => '已阻止',
      'failed' => '失败',
      _ => status.isEmpty ? '未知' : status,
    };
    final durationLabel = durationMs <= 0
        ? '—'
        : durationMs >= 1000
        ? '${(durationMs / 1000).toStringAsFixed(2)} 秒'
        : '$durationMs 毫秒';
    return '''### 工具调用结果 · $toolName

| 项目 | 内容 |
| --- | --- |
| 工具调用 ID | ${_markdownTableCell(toolCallId)} |
| 工具参数 | ${_markdownTableCell(arguments)} |
| 工具响应结果 | ${_markdownTableCell(response)} |
| 调用结果 | ${_markdownTableCell(statusLabel)} |
| 调用耗时 | ${_markdownTableCell(durationLabel)} |''';
  }

  AiSessionMessage? _matchingToolResult(
    AiSessionMessage call,
    List<AiSessionMessage> sessionMessages,
  ) {
    final id = '${call.metadata['tool_call_id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    for (final message in sessionMessages.reversed) {
      if (message.isDeleted || !message.kind.isToolResultKind) continue;
      if ('${message.metadata['tool_call_id'] ?? ''}'.trim() == id) {
        return message;
      }
    }
    return null;
  }

  String _toolArgumentsValue(Map<String, Object?> metadata) {
    final raw = metadata['tool_arguments'] ?? metadata['tool_calls'];
    if (raw == null) return '{}';
    if (raw is String && raw.trim().isEmpty) return '{}';
    return _prettyToolValue(raw);
  }

  String _toolResponseValue(
    Map<String, Object?> metadata,
    AiSessionMessage? matchingResult,
  ) {
    final candidates = <Object?>[
      metadata['tool_execution_result'],
      metadata['result_text'],
      metadata['tool_execution_stdout'],
      metadata['tool_execution_stderr'],
      matchingResult?.content,
    ];
    for (final candidate in candidates) {
      final value = _prettyToolValue(candidate);
      if (value.trim().isNotEmpty) return value;
    }
    return '—';
  }

  String _prettyToolValue(Object? raw) {
    if (raw == null) return '';
    var value = raw is String ? raw.trim() : '';
    if (value.length > _maxDingTalkToolFormattingCharacters) {
      value = clipTextByCodeUnits(
        value,
        _maxDingTalkToolFormattingCharacters,
        suffix: '…',
      );
    }
    if (value.isEmpty && raw is! String) {
      try {
        value = prettyPrintJson(raw);
      } catch (_) {
        value = '$raw';
      }
    } else if (value.isNotEmpty) {
      try {
        value = prettyPrintJson(jsonDecode(value));
      } catch (_) {
        // 普通文本不是 JSON，直接保留。
      }
    }
    return _boundedToolValue(value);
  }

  String _boundedToolValue(Object? raw) {
    final value = '$raw'.trim();
    return clipTextByCodeUnits(
      value,
      _maxDingTalkToolCellCharacters,
      suffix: '…',
    );
  }

  DateTime _echoCompletionTime(AiSessionMessage message) {
    if (message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook) {
      return utcDateTimeFromValue(
            message.metadata['tool_execution_finished_at'],
          ) ??
          message.createdAt;
    }
    return message.createdAt;
  }

  String _markdownTableCell(String value) {
    return value
        .replaceAll('`', 'ˋ')
        .replaceAll('|', '\\|')
        .replaceAll(RegExp(r'[\r\n]+'), ' ↵ ')
        .trim();
  }

  int _toolDurationMilliseconds(AiSessionMessage call) {
    final metadata = call.metadata;
    final stored = intFromValue(
      metadata['tool_execution_duration_ms'] ??
          metadata['tool_execution_elapsed_ms'],
      fallback: 0,
    );
    if (stored > 0) return stored;
    final started = utcDateTimeFromValue(metadata['tool_execution_started_at']);
    final finished = utcDateTimeFromValue(
      metadata['tool_execution_finished_at'],
    );
    if (started == null || finished == null) return 0;
    return finished.difference(started).inMilliseconds.clamp(0, 86400000);
  }

  static const int _maxQueuedResponsesPerConversation = 256;

  Future<void> _enqueueAiResponse(
    DingTalkConversation conversation,
    String content,
  ) {
    final normalized = content.trim();
    if (normalized.isEmpty || _disposed) return Future<void>.value();
    final completer = Completer<void>();
    final queue = _responseQueues.putIfAbsent(
      conversation.id,
      () => Queue<_QueuedDingTalkResponse>(),
    );
    if (queue.length >= _maxQueuedResponsesPerConversation) {
      // 极端突发消息时合并队尾，保留全部内容并限制内存增长。
      queue.last.merge(normalized, completer);
      _warningMessage = '钉钉会话消息过多，已将突发消息合并后依次处理。';
    } else {
      queue.add(_QueuedDingTalkResponse(normalized, completer));
    }
    _notify();
    if (_responseDraining.add(conversation.id)) {
      unawaited(_drainResponseQueue(conversation));
    }
    return completer.future;
  }

  Future<void> _drainResponseQueue(DingTalkConversation conversation) async {
    final queue = _responseQueues[conversation.id];
    if (queue == null) {
      _responseDraining.remove(conversation.id);
      return;
    }
    try {
      while (!_disposed && queue.isNotEmpty) {
        final item = queue.removeFirst();
        try {
          await _respondWithAi(conversation, item.content);
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '处理钉钉消息队列', error, stack);
        } finally {
          item.complete();
        }
      }
    } finally {
      _responseDraining.remove(conversation.id);
      if (queue.isEmpty) {
        _responseQueues.remove(conversation.id);
      } else if (!_disposed && _responseDraining.add(conversation.id)) {
        unawaited(_drainResponseQueue(conversation));
      }
      _notify();
    }
  }

  AiModelConfig? _resolveModel() {
    final key = _settings.responseModelKey;
    if (key.isNotEmpty) {
      final separator = key.indexOf('::');
      if (separator > 0) {
        final providerId = key.substring(0, separator);
        final modelId = key.substring(separator + 2);
        for (final provider in _settingsController.aiModels) {
          if (provider.id == providerId) {
            return provider.copyWith(modelId: modelId);
          }
        }
      }
    }
    return _settingsController.selectedAiModel;
  }

  DingTalkGatewaySettings _normalizeSettings(DingTalkGatewaySettings value) {
    return value.normalized(
      availableMcpServerNames: _mcpController.runtimeServers.isEmpty
          ? null
          : _mcpController.runtimeServers.map((server) => server.name),
      availableSkillNames: _skillsController.skills.isEmpty
          ? null
          : _skillsController.skills.map((skill) => skill.name),
      availableMemoryIds: _memoryController.entries.isEmpty
          ? null
          : _memoryController.entries.map((entry) => entry.id),
      availableInstructionIds: _instructionsController.entries.isEmpty
          ? null
          : _instructionsController.entries.map((entry) => entry.id),
      availableKnowledgeBaseSourceIds:
          _knowledgeBaseController == null ||
              _knowledgeBaseController.sources.isEmpty
          ? null
          : _knowledgeBaseController.sources.map((source) => source.id),
    );
  }

  List<AiBuiltinToolConfig> _knowledgeBuiltinToolConfigs() {
    final configured = _settingsController.builtinToolConfigs;
    final source = configured.isEmpty
        ? AiBuiltinToolConfig.defaults()
        : configured;
    return source
        .where(
          (config) =>
              config.kind == AiBuiltinToolKind.knowledgeSearch ||
              config.kind == AiBuiltinToolKind.knowledgeRead,
        )
        .map((config) => config.copyWith(enabled: true))
        .toList(growable: false);
  }

  bool _isSelf(DingTalkGatewayMessage message) {
    if (message.isAssistant || message.fromSelf) return true;
    final sender = message.senderId.trim();
    final current = _authStatus.identity.userId.trim();
    final profile = _authStatus.identity.profile.trim();
    if (sender.isNotEmpty &&
        ((current.isNotEmpty && sender == current) ||
            (profile.isNotEmpty && sender == profile))) {
      return true;
    }
    final senderName = message.senderName.trim();
    final identityName = _authStatus.identity.name.trim();
    final identityLabel = _authStatus.identity.label.trim();
    return senderName.isNotEmpty &&
        ((identityName.isNotEmpty && senderName == identityName) ||
            (identityLabel.isNotEmpty && senderName == identityLabel));
  }

  bool isMessageFromCurrentUser(DingTalkGatewayMessage message) =>
      _isSelf(message);

  void _appendMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (conversation.messages.any((item) => item.id == message.id)) return;
    final last = conversation.messages.isEmpty
        ? null
        : conversation.messages.last;
    if (last == null || !message.createdAt.isBefore(last.createdAt)) {
      conversation.messages.add(message);
    } else {
      conversation.messages
        ..add(message)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    _queuePersist();
  }

  void markAllRead() {
    if (_unreadCount == 0) return;
    _unreadCount = 0;
    _notify();
  }

  void _remember(String id) {
    _seenMessageIds.add(id);
    while (_seenMessageIds.length > _maxSeenIds) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }
  }

  void _setError(String action, Object error, StackTrace stack) {
    _errorMessage = '$action失败：$error';
    silentLog('dingtalk_gateway', action, error, stack);
  }

  void _clearError() => _errorMessage = null;

  void _queuePersist() {
    if (_disposed) return;
    _persistQueued = true;
    _persistenceError = null;
    if (_persistInFlight != null) return;
    final task = _drainPersistQueue();
    _persistInFlight = task;
    unawaited(task);
  }

  Future<void> _drainPersistQueue() async {
    // 让出当前帧，避免消息到达时复制大量历史消息阻塞会话切换和滚动。
    await Future<void>.delayed(Duration.zero);
    while (_persistQueued) {
      _persistQueued = false;
      final conversations = _conversations.values
          .map((conversation) {
            final copy = DingTalkConversation(
              id: conversation.id,
              type: conversation.type,
              title: conversation.title,
              messages: List<DingTalkGatewayMessage>.from(
                conversation.messages,
              ),
              directUserId: conversation.directUserId,
              directOpenDingTalkId: conversation.directOpenDingTalkId,
            )..aiSessionId = conversation.aiSessionId;
            return copy;
          })
          .toList(growable: false);
      try {
        await _store
            .saveSnapshot(settings: _settings, conversations: conversations)
            .timeout(const Duration(seconds: 10));
      } catch (error, stack) {
        _persistenceError = error;
        _setError('保存钉钉网关数据', error, stack);
        break;
      }
    }
    _persistInFlight = null;
    if (_persistQueued && !_disposed) _queuePersist();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _stopEventListening();
    for (final queue in _responseQueues.values) {
      for (final item in queue) {
        item.complete();
      }
    }
    _responseQueues.clear();
    _responseDraining.clear();
    _writeApprovalHandler = null;
    await _runtimeLogSubscription?.cancel();
    _runtimeLogSubscription = null;
    final persist = _persistInFlight;
    if (persist != null) {
      await persist.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    _disposed = true;
    await _service.cancelAuthorization();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}

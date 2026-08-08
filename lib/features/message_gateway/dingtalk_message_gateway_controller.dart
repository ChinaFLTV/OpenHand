import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../ai/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'data/dingtalk_message_gateway_store.dart';
import 'message_gateway_dependencies.dart';
import 'model/dingtalk_message_gateway.dart';
import 'service/dingtalk_message_gateway_service.dart';

class DingTalkMessageGatewayController extends ChangeNotifier {
  DingTalkMessageGatewayController(
    MessageGatewayDependencies dependencies, {
    DingTalkMessageGatewayStore? store,
    DingTalkMessageGatewayService? service,
  }) : _sessionController = dependencies.sessionController,
       _settingsController = dependencies.settingsController,
       _appInfo = dependencies.appInfo,
       _store = store ?? DingTalkMessageGatewayStore(),
       _service = service ?? DingTalkMessageGatewayService();

  static const Uuid _uuid = Uuid();
  static const int _maxSeenIds = 2000;
  static const Duration _queryWindow = Duration(minutes: 10);
  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final AppInfo _appInfo;
  final DingTalkMessageGatewayStore _store;
  final DingTalkMessageGatewayService _service;
  final Map<String, DingTalkConversation> _conversations =
      <String, DingTalkConversation>{};
  final Set<String> _responseInFlight = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _initialized = false;
  bool _disposed = false;
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
  List<AiModelConfig> get aiModels =>
      List<AiModelConfig>.unmodifiable(_settingsController.aiModels);
  List<DingTalkConversation> get conversations {
    final values = _conversations.values.toList(growable: false);
    return values..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    try {
      _settings = (await _store.load()).normalized();
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
      if (!_authStatus.authenticated && _isPolling) stopPolling();
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
    await _service.cancelAuthorization();
    _isAuthenticating = false;
    _notify();
  }

  Future<void> logout() async {
    try {
      await _service.logout(profile: _authStatus.identity.profile);
      _authStatus = const DingTalkAuthStatus(authenticated: false);
      stopPolling();
      _clearError();
    } catch (error, stack) {
      _setError('取消钉钉授权', error, stack);
    }
    _notify();
  }

  Future<void> updateSettings(DingTalkGatewaySettings value) async {
    final normalized = value.normalized();
    await _store.save(normalized);
    _settings = normalized;
    if (_isPolling) _schedulePolling();
    _notify();
  }

  void startPolling() {
    if (_isPolling || !isAuthorized) return;
    _isPolling = true;
    _lastPollAt = DateTime.now().subtract(_queryWindow);
    _schedulePolling(immediate: true);
    _notify();
  }

  void stopPolling() {
    _isPolling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _notify();
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
      ),
    );
    _notify();
    try {
      await _service.send(
        conversation: conversation,
        text: content,
        uuid: _uuid.v4(),
      );
      await _respondWithAi(conversation, content);
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
        if (_seenMessageIds.contains(message.id)) continue;
        if (_isSelf(message)) {
          _remember(message.id);
          continue;
        }
        _remember(message.id);
        final conversation = _conversations.putIfAbsent(
          message.conversationId,
          () => DingTalkConversation(
            id: message.conversationId,
            type: message.conversationType,
            title: message.conversationTitle.trim().isNotEmpty
                ? message.conversationTitle
                : message.senderName.trim().isEmpty
                ? '钉钉会话'
                : message.senderName,
          ),
        );
        _appendMessage(conversation, message);
        _unreadCount += 1;
        if (_settings.reminderMode == DingTalkReminderMode.sound) {
          unawaited(SystemSound.play(SystemSoundType.alert));
        }
        unawaited(_respondWithAi(conversation, message.content));
      }
      _clearError();
    } catch (error, stack) {
      _setError('轮询钉钉消息', error, stack);
      await refreshAuthStatus();
      if (!isAuthorized) stopPolling();
    } finally {
      _pollInFlight = false;
      _notify();
    }
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
    final model = _resolveModel();
    final templates = _sessionController.availableTemplates;
    try {
      if (model == null || templates.isEmpty) return;
      final runtimeContext = buildAiSessionRuntimeContext(
        settingsController: _settingsController,
        appInfo: _appInfo,
        appThemeBrightness: _settingsController.themeMode.name,
        localNow: DateTime.now().toLocal(),
        workingDirectory: OpenHandPaths.applicationDirectoryPath(),
        memoryEntries: const <UserMemoryEntry>[],
        allowCommandRules: _settingsController.aiAllowCommandRules,
        availableSkills: const <LocalSkill>[],
        availableMcpServers: const <McpServer>[],
        mcpToolCatalogsByServerName: const <String, McpToolCatalog>{},
        builtinToolConfigs: const <AiBuiltinToolConfig>[],
        templateId: templates.first.id,
        toolExecutionMetadata: const <String, Object?>{
          'source': 'dingtalk_gateway',
        },
      );
      var sessionId = conversation.aiSessionId;
      if (sessionId == null) {
        final created = await _sessionController.createSession(
          templateId: templates.first.id,
          runtimeContext: runtimeContext,
          title: '钉钉 · ${conversation.title}',
          initialModelProviderConfigId: model.id,
          initialModelId: model.modelId,
          metadata: <String, Object?>{
            'dingtalk_conversation_id': conversation.id,
          },
        );
        if (!created) return;
        sessionId = _sessionController.currentSessionId;
        conversation.aiSessionId = sessionId;
      }
      if (sessionId == null) return;
      final sent = await _sessionController.sendMessage(
        sessionId: sessionId,
        content: content,
        model: model,
        runtimeContext: runtimeContext,
        requireWriteCommandConfirmation: false,
        userMessageMetadata: const <String, Object?>{
          'sent_via': 'dingtalk_gateway',
        },
      );
      if (!sent) return;
      final session = _sessionController.sessions.cast<AiSession?>().firstWhere(
        (item) => item?.id == sessionId,
        orElse: () => null,
      );
      AiSessionMessage? assistant;
      if (session != null) {
        for (final item in session.messages.reversed) {
          if (item.kind == AiSessionMessageKind.assistant &&
              item.content.trim().isNotEmpty) {
            assistant = item;
            break;
          }
        }
      }
      if (assistant == null) return;
      final reply = assistant.content.trim();
      _appendMessage(
        conversation,
        DingTalkGatewayMessage(
          id: 'assistant-${assistant.id}',
          conversationId: conversation.id,
          conversationType: conversation.type,
          role: DingTalkGatewayMessageRole.assistant,
          content: reply,
          createdAt: assistant.createdAt,
        ),
      );
      await _service.send(
        conversation: conversation,
        text: reply,
        uuid: _uuid.v4(),
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '生成钉钉 AI 回复', error, stack);
    } finally {
      _responseInFlight.remove(conversation.id);
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

  bool _isSelf(DingTalkGatewayMessage message) {
    if (message.fromSelf) return true;
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
    return senderName.isNotEmpty &&
        identityName.isNotEmpty &&
        senderName == identityName;
  }

  void _appendMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (conversation.messages.any((item) => item.id == message.id)) return;
    conversation.messages.add(message);
    conversation.messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
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
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _service.cancelAuthorization();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}

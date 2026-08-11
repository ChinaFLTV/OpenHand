import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../shared/model/dingtalk_multimodal_capability.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/timer_safety.dart';
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

class DingTalkMessageAuditSnapshot {
  const DingTalkMessageAuditSnapshot({
    required this.conversation,
    required this.message,
    this.aiSession,
    this.aiMessage,
  });

  final DingTalkConversation conversation;
  final DingTalkGatewayMessage message;
  final AiSession? aiSession;
  final AiSessionMessage? aiMessage;
}

class _QueuedDingTalkResponse {
  _QueuedDingTalkResponse(
    this.content,
    this.sourceMessageId,
    Completer<void> completer,
  ) : waiters = <Completer<void>>[completer];

  String content;
  String sourceMessageId;
  final List<Completer<void>> waiters;

  void merge(
    String nextContent,
    String nextSourceMessageId,
    Completer<void> completer,
  ) {
    content = '$content\n\n$nextContent';
    sourceMessageId = nextSourceMessageId;
    waiters.add(completer);
  }

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

class _DingTalkConversationHistoryState {
  _DingTalkConversationHistoryState({this.hasMore = false});

  bool hasMore;
  bool loading = false;
  bool initialized = false;
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
       _service = service ?? DingTalkMessageGatewayService(),
       _mediaGenerationService = AiImageGenerationService() {
    _runtimeLogSubscription = _service.runtimeLogStream.listen((_) {
      _notify();
    });
  }

  static const Uuid _uuid = Uuid();
  static const int _mediaCacheConcurrency = 3;
  static const int _mediaWarmupMessageLimit = 12;
  static const int _maxMediaHydrationFailureIds = 1024;
  static const int _maxSeenIds = 2000;
  static const int _maxPendingRecallIds = 512;
  static const int _maxPendingStatusMessageIds = 512;
  static const int _maxPendingStatusEventsPerMessage = 24;
  static const int _maxReactionTypes = 12;
  static const Duration _outgoingEchoWindow = Duration(seconds: 30);
  static const int _maxAiConversationContextCharacters = 48000;
  static const int _maxAiConversationContextMessages = 200;
  static const Duration _conversationStartSkew = Duration(seconds: 2);
  static const Duration _queryWindow = Duration(minutes: 10);
  static const Duration _realtimeReconcilePollInterval = Duration(seconds: 10);
  // 编辑消息没有独立个人 IM 事件，保持有界低频对账，通常在一个轮询周期内可见。
  static const Duration _conversationReconcileInterval = Duration(seconds: 15);
  static const Duration _pollCallbackTimeout = Duration(minutes: 2);
  static const Duration _conversationReconcileInitialBackoff = Duration(
    seconds: 30,
  );
  static const Duration _conversationReconcileMaxBackoff = Duration(
    minutes: 10,
  );
  static const Duration _conversationReconcileLogInterval = Duration(
    minutes: 5,
  );
  static const Duration _shutdownCleanupTimeout = Duration(seconds: 10);
  // 媒体只影响附件上下文，不能阻塞文本消息进入 AI 响应链路。
  static const Duration _mediaPreparationTimeout = Duration(seconds: 12);
  static const Duration _stopResponseTimeout = Duration(seconds: 10);
  static const int _maxConversationReconcileCount = 12;
  static const int _conversationReconcileConcurrency = 4;
  static const int _maxConversationReconcileFailureCount = 6;
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
  final AiImageGenerationService _mediaGenerationService;
  StreamSubscription<String>? _runtimeLogSubscription;
  final Map<String, DingTalkConversation> _conversations =
      <String, DingTalkConversation>{};
  final Set<String> _responseInFlight = <String>{};
  final Map<String, int> _responsePreparingCounts = <String, int>{};
  final Map<String, String> _responseErrors = <String, String>{};

  /// 每次停止响应都会递增。正在执行的响应携带启动时版本，前置异步
  /// 阶段完成后若版本已变化，立即结束本轮，避免停止后继续发起 AI 请求。
  final Map<String, int> _responseCancellationVersions = <String, int>{};
  final Map<String, Queue<_QueuedDingTalkResponse>> _responseQueues =
      <String, Queue<_QueuedDingTalkResponse>>{};
  final Set<String> _responseDraining = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  final Set<String> _selfSenderIds = <String>{};
  final Set<String> _pendingRecalledMessageIds = <String>{};
  final Map<String, List<DingTalkGatewayEvent>> _pendingStatusEvents =
      <String, List<DingTalkGatewayEvent>>{};
  final Map<String, (DateTime, List<DingTalkConversationTarget>)>
  _targetSearchCache = <String, (DateTime, List<DingTalkConversationTarget>)>{};
  final Map<String, Future<DingTalkGatewayMessage>> _mediaHydrationTasks =
      <String, Future<DingTalkGatewayMessage>>{};
  final Set<String> _mediaHydrationFailures = <String>{};
  final Map<String, _DingTalkConversationHistoryState>
  _conversationHistoryStates = <String, _DingTalkConversationHistoryState>{};
  final Map<String, _ConversationReconcileFailure>
  _conversationReconcileFailures = <String, _ConversationReconcileFailure>{};
  final Map<String, Future<void>> _conversationReconcileTasks =
      <String, Future<void>>{};
  Timer? _pollTimer;
  StreamSubscription<DingTalkGatewayEvent>? _eventSubscription;
  Future<void>? _eventRestartFuture;
  Future<void>? _periodicReconcileFuture;
  Future<void>? _persistInFlight;
  Future<void>? _shutdownInFlight;
  bool _persistQueued = false;
  Object? _persistenceError;
  bool _pollInFlight = false;
  bool _usingPollingFallback = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _shutdownRequested = false;
  bool _notificationQueued = false;
  DingTalkWriteApprovalHandler? _writeApprovalHandler;
  bool _isAuthenticating = false;
  bool _isPolling = false;
  bool _isSending = false;
  bool _editingMessageInFlight = false;
  int _conversationReconcileCursor = 0;
  int _unreadCount = 0;
  String? _errorMessage;
  String? _warningMessage;
  String? _deviceUrl;
  DingTalkAuthStatus _authStatus = const DingTalkAuthStatus(
    authenticated: false,
  );
  DingTalkGatewaySettings _settings = const DingTalkGatewaySettings();
  DateTime _lastPollAt = DateTime.now().subtract(_queryWindow);
  DateTime _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );

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
  String? responseErrorMessage(String conversationId) =>
      _responseErrors[conversationId.trim()];

  void clearResponseError(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty || _responseErrors.remove(normalizedId) == null) {
      return;
    }
    _notify();
  }

  String? get deviceUrl => _deviceUrl;
  String? get dwsCommandCatalogError => _service.dwsCommandCatalogError;
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
  Future<List<AiDingTalkDwsCommand>> loadDwsCommandCatalog({
    bool forceRefresh = false,
  }) => _service.loadDwsCommandCatalog(forceRefresh: forceRefresh);

  Future<Object?> _executeDwsCommandForAi({
    required AiDingTalkDwsCommand command,
    required Map<String, Object?> arguments,
    required String workingDirectory,
    Future<void>? cancelSignal,
  }) async {
    final result = await _service.executeDwsCommand(
      command: command,
      arguments: AiDingTalkDwsTool.buildCliArguments(command, arguments),
      workingDirectory: workingDirectory,
      cancelSignal: cancelSignal,
    );
    return <String, Object?>{
      'command': result.command,
      'working_directory': result.workingDirectory,
      'stdout': result.stdout,
      'stderr': result.stderr,
      'exit_code': result.exitCode,
      'timed_out': result.timedOut,
      'duration_ms': result.durationMs,
    };
  }

  Future<Object?> _executeDingTalkMediaGenerationForAi({
    required DingTalkConversation conversation,
    required AiDingTalkMultimodalCapability capability,
    required String prompt,
    required AiCreationOptions options,
    required List<String> referenceImagePaths,
    Future<void>? cancelSignal,
  }) async {
    if (_disposed || !isAuthorized) {
      throw StateError('钉钉会话当前不可发送媒体。');
    }
    final modelKey = _multimodalModelKey(capability);
    final model = _resolveModelByKey(modelKey);
    if (model == null) {
      throw StateError('${capability.displayName}尚未配置模型。');
    }
    if (!_supportsMultimodalCapability(capability, model)) {
      throw StateError('所选模型不支持${capability.displayName}。');
    }
    final root = p.normalize(
      OpenHandPaths.normalizePath(
        _settings.workingDirectory,
        defaultPath: OpenHandPaths.applicationDirectoryPath(),
      ),
    );
    final referenceParts = <AiChatContentPart>[];
    for (final rawPath in referenceImagePaths.take(8)) {
      final path = _resolveDingTalkMediaInputPath(root, rawPath);
      if (path == null) continue;
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final resolved = await File(path).resolveSymbolicLinks();
        if (!p.equals(root, resolved) && !p.isWithin(root, resolved)) {
          continue;
        }
      } on FileSystemException {
        continue;
      }
      final stat = await File(path).stat();
      if (stat.size > 32 * kBytesPerMiB) continue;
      referenceParts.add(
        AiChatContentPart.imageFile(
          filePath: path,
          mimeType: _mediaMimeType(path, fallback: 'image/jpeg'),
        ),
      );
    }
    final generated = switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration =>
        await _mediaGenerationService.generateImage(
          model: model,
          prompt: prompt,
          options: options,
          referenceImages: referenceParts,
          timeout: const Duration(minutes: 10),
          cancelSignal: cancelSignal,
        ),
      AiDingTalkMultimodalCapability.videoGeneration =>
        await _mediaGenerationService.generateVideo(
          model: model,
          prompt: prompt,
          options: options,
          referenceImages: referenceParts,
          timeout: const Duration(minutes: 20),
          cancelSignal: cancelSignal,
        ),
      AiDingTalkMultimodalCapability.audioGeneration =>
        await _mediaGenerationService.generateAudio(
          model: model,
          prompt: prompt,
          options: options,
          timeout: const Duration(minutes: 5),
          cancelSignal: cancelSignal,
        ),
    };
    final paths = _generatedMediaPaths(generated.markdown).take(4).toList();
    if (paths.isEmpty) {
      throw StateError('生成服务未返回可发送的媒体文件。');
    }
    final mediaKind = switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration => DingTalkMediaKind.image,
      AiDingTalkMultimodalCapability.videoGeneration => DingTalkMediaKind.video,
      AiDingTalkMultimodalCapability.audioGeneration => DingTalkMediaKind.audio,
    };
    String? firstRemoteId;
    String? firstPath;
    String? firstName;
    final generatedRoot = p.normalize(
      p.join(Directory.systemTemp.path, 'openhand_media'),
    );
    for (final path in paths) {
      if (await isCancelSignalCompleted(cancelSignal)) {
        throw const AiMediaGenerationCancelledException();
      }
      final file = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      try {
        final resolved = await file.resolveSymbolicLinks();
        if (!p.equals(generatedRoot, resolved) &&
            !p.isWithin(generatedRoot, resolved)) {
          continue;
        }
      } on FileSystemException {
        continue;
      }
      if (!await file.exists()) continue;
      final stat = await file.stat();
      if (stat.size <= 0 || stat.size > 2 * kBytesPerGiB) continue;
      final name = p.basename(path).trim().isEmpty ? '生成媒体' : p.basename(path);
      final remoteId = await _service
          .sendFile(
            conversation: conversation,
            filePath: path,
            audio: mediaKind == DingTalkMediaKind.audio,
            uuid: _uuid.v4(),
          )
          .timeout(const Duration(seconds: 60));
      final messageId = remoteId?.trim().isNotEmpty == true
          ? remoteId!.trim()
          : 'assistant-media-${_uuid.v4()}';
      if (remoteId?.trim().isNotEmpty == true) _remember(remoteId!.trim());
      _appendMessage(
        conversation,
        DingTalkGatewayMessage(
          id: messageId,
          conversationId: conversation.id,
          conversationType: conversation.type,
          role: DingTalkGatewayMessageRole.assistant,
          content: '[${mediaKind.name}] $name',
          createdAt: DateTime.now(),
          senderName: 'OpenHand',
          media: <DingTalkGatewayMedia>[
            DingTalkGatewayMedia(
              resourceId: messageId,
              messageId: messageId,
              conversationId: conversation.id,
              kind: mediaKind,
              name: name,
              mimeType: _mediaMimeType(
                path,
                fallback: switch (capability) {
                  AiDingTalkMultimodalCapability.imageGeneration => 'image/png',
                  AiDingTalkMultimodalCapability.videoGeneration => 'video/mp4',
                  AiDingTalkMultimodalCapability.audioGeneration =>
                    'audio/mpeg',
                },
              ),
              sizeBytes: stat.size,
              localPath: path,
            ),
          ],
        ),
      );
      firstRemoteId ??= remoteId?.trim();
      firstPath ??= path;
      firstName ??= name;
    }
    if (firstPath == null) throw StateError('生成媒体文件不存在或无法发送。');
    _notify();
    return <String, Object?>{
      'success': true,
      'file_path': firstPath,
      'file_name': firstName,
      'remote_message_id': firstRemoteId,
      'media_kind': mediaKind.name,
      'duration_ms': generated.durationMs,
      'sent_count': paths.length,
    };
  }

  AiDingTalkMediaGenerationExecutor _mediaExecutorForConversation(
    DingTalkConversation conversation,
  ) {
    return ({
      required AiDingTalkMultimodalCapability capability,
      required String prompt,
      required AiCreationOptions options,
      required List<String> referenceImagePaths,
      Future<void>? cancelSignal,
    }) => _executeDingTalkMediaGenerationForAi(
      conversation: conversation,
      capability: capability,
      prompt: prompt,
      options: options,
      referenceImagePaths: referenceImagePaths,
      cancelSignal: cancelSignal,
    );
  }

  String _multimodalModelKey(AiDingTalkMultimodalCapability capability) {
    return switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration =>
        _settings.imageGenerationModelKey,
      AiDingTalkMultimodalCapability.videoGeneration =>
        _settings.videoGenerationModelKey,
      AiDingTalkMultimodalCapability.audioGeneration =>
        _settings.audioGenerationModelKey,
    };
  }

  bool _supportsMultimodalCapability(
    AiDingTalkMultimodalCapability capability,
    AiModelConfig model,
  ) {
    return switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration =>
        AiImageGenerationService.supportsImageGenerationForModel(model),
      AiDingTalkMultimodalCapability.videoGeneration =>
        AiImageGenerationService.supportsVideoGenerationForModel(model),
      AiDingTalkMultimodalCapability.audioGeneration =>
        AiImageGenerationService.supportsAudioGenerationForModel(model),
    };
  }

  List<String> _validMultimodalCapabilitiesForRuntime() {
    return _settings.enabledMultimodalCapabilities
        .where((capability) {
          final model = _resolveModelByKey(_multimodalModelKey(capability));
          return model != null &&
              _supportsMultimodalCapability(capability, model);
        })
        .map((capability) => capability.storageValue)
        .toList(growable: false);
  }

  AiModelConfig? _resolveModelByKey(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) return null;
    final separator = normalized.indexOf('::');
    if (separator <= 0 || separator >= normalized.length - 2) return null;
    final providerId = normalized.substring(0, separator);
    final modelId = normalized.substring(separator + 2);
    for (final provider in _settingsController.aiModels) {
      if (provider.id == providerId && modelId.trim().isNotEmpty) {
        return provider.copyWith(modelId: modelId.trim());
      }
    }
    return null;
  }

  String? _resolveDingTalkMediaInputPath(String root, String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return null;
    final candidate = p.normalize(
      p.isAbsolute(trimmed) ? trimmed : p.join(root, trimmed),
    );
    if (!p.equals(root, candidate) && !p.isWithin(root, candidate)) return null;
    return candidate;
  }

  List<String> _generatedMediaPaths(String markdown) {
    final result = <String>[];
    final pattern = RegExp(r'!?\[[^\]\r\n]{0,240}\]\(([^)\r\n]+)\)');
    final generatedRoot = p.normalize(
      p.join(Directory.systemTemp.path, 'openhand_media'),
    );
    for (final match in pattern.allMatches(markdown)) {
      var raw = match.group(1)?.trim() ?? '';
      if (raw.startsWith('<') && raw.endsWith('>')) {
        raw = raw.substring(1, raw.length - 1).trim();
      }
      if (raw.startsWith('file://')) {
        final uri = Uri.tryParse(raw);
        if (uri == null) continue;
        try {
          raw = uri.toFilePath();
        } on UnsupportedError {
          continue;
        }
      }
      final path = p.normalize(raw);
      if ((p.equals(generatedRoot, path) || p.isWithin(generatedRoot, path)) &&
          !result.contains(path)) {
        result.add(path);
      }
    }
    return result;
  }

  String _mediaMimeType(
    String path, {
    String fallback = 'application/octet-stream',
  }) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.wav' => 'audio/wav',
      '.m4a' => 'audio/mp4',
      '.ogg' => 'audio/ogg',
      '.aac' => 'audio/aac',
      _ => fallback,
    };
  }

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
    if (_isPolling && !_usingPollingFallback && _eventSubscription != null) {
      unawaited(_restartEventListening());
    }
  }

  /// 只移除 OpenHand 本地会话，不影响钉钉侧真实群聊或联系人。
  Future<void> deleteConversation(String conversationId) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return;
    await stopConversationResponse(conversationId);
    _conversations.remove(conversationId);
    _responseErrors.remove(conversationId);
    _conversationHistoryStates.remove(conversationId);
    _conversationReconcileFailures.remove(conversationId);
    if (!_responseDraining.contains(conversationId) &&
        !_responseInFlight.contains(conversationId) &&
        !_responseQueues.containsKey(conversationId)) {
      _responseCancellationVersions.remove(conversationId);
    }
    _queuePersist();
    _notify();
    if (_isPolling && !_usingPollingFallback && _eventSubscription != null) {
      unawaited(_restartEventListening());
    }
  }

  bool isConversationResponding(String conversationId) {
    final conversation = _conversations[conversationId];
    final sessionId = conversation?.aiSessionId;
    return _responseInFlight.contains(conversationId) ||
        _responsePreparingCounts.containsKey(conversationId) ||
        (_responseQueues[conversationId]?.isNotEmpty ?? false) ||
        (sessionId != null &&
            !_responseCancellationVersions.containsKey(conversationId) &&
            _sessionController.canStopResponding(sessionId));
  }

  String responseStatusText(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return '正在响应…';
    if (_responsePreparingCounts.containsKey(normalizedId) &&
        !_responseInFlight.contains(normalizedId)) {
      return '正在准备消息上下文…';
    }
    final sessionId = _conversations[normalizedId]?.aiSessionId;
    return switch (_sessionController.sendPhaseForSession(sessionId)) {
      AiSendPhase.compressing => '正在整理会话上下文…',
      AiSendPhase.sendingMessage => '正在发送请求…',
      AiSendPhase.responding => 'AI 正在生成回复…',
      AiSendPhase.awaitingApproval => '等待确认后继续…',
      AiSendPhase.idle => 'AI 正在处理…',
    };
  }

  Future<void> stopConversationResponse(String conversationId) async {
    if (_disposed) return;
    final nextVersion =
        (_responseCancellationVersions[conversationId] ?? 0) + 1;
    _responseCancellationVersions[conversationId] = nextVersion;
    final conversation = _conversations[conversationId];
    final sessionId = conversation?.aiSessionId;
    final queue = _responseQueues.remove(conversationId);
    if (queue != null) {
      for (final item in queue) {
        item.complete();
      }
      queue.clear();
    }
    _responsePreparingCounts.remove(conversationId);
    if (sessionId == null || !_sessionController.canStopResponding(sessionId)) {
      _responseInFlight.remove(conversationId);
      _notify();
      return;
    }
    try {
      await _sessionController
          .stopResponding(sessionId)
          .timeout(_stopResponseTimeout);
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '停止钉钉 AI 响应', error, stack);
    } finally {
      _responseInFlight.remove(conversationId);
      _notify();
    }
  }

  bool isMessageMediaCaching(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    return normalizedId.isNotEmpty &&
        _mediaHydrationTasks.containsKey(normalizedId);
  }

  bool isMessageMediaHydrationFailed(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    return normalizedId.isNotEmpty &&
        _mediaHydrationFailures.contains(normalizedId);
  }

  bool hasOlderConversationMessages(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return false;
    final conversation = _conversations[normalizedId];
    if (conversation == null) return false;
    final state = _conversationHistoryStates[normalizedId];
    if (state == null || !state.initialized) {
      return conversation.messages.isNotEmpty;
    }
    return state.hasMore;
  }

  bool isLoadingOlderConversationMessages(String conversationId) =>
      _conversationHistoryStates[conversationId.trim()]?.loading ?? false;

  Future<void> loadOlderConversationMessages(String conversationId) async {
    final normalizedId = conversationId.trim();
    final conversation = _conversations[normalizedId];
    if (conversation == null || !_isPolling || _disposed) return;
    final state = _conversationHistoryStates.putIfAbsent(
      normalizedId,
      () => _DingTalkConversationHistoryState(
        hasMore: conversation.messages.isNotEmpty,
      ),
    );
    if (state.loading || !hasOlderConversationMessages(normalizedId)) return;
    final oldest = conversation.messages.isEmpty
        ? null
        : conversation.messages.first.createdAt;
    if (oldest == null) {
      state.hasMore = false;
      state.initialized = true;
      _notify();
      return;
    }
    state.loading = true;
    _notify();
    try {
      final page = await _service.queryConversationPage(
        conversation: conversation,
        before: oldest,
      );
      if (_disposed ||
          !_isPolling ||
          !identical(_conversations[normalizedId], conversation)) {
        return;
      }
      final addedCount = _ingestReconciledMessages(conversation, page.messages);
      state.hasMore = page.hasMore && addedCount > 0;
      state.initialized = true;
    } catch (error, stack) {
      if (!_disposed) {
        silentLog('dingtalk_gateway', '加载钉钉更早消息', error, stack);
      }
    } finally {
      state.loading = false;
      _notify();
    }
  }

  /// 确保指定会话中的媒体文件已落地到本地缓存。缓存被用户清理或路径失效时，
  /// 下一次访问会重新调用 dws 下载。
  Future<DingTalkGatewayMessage?> ensureMessageMediaCached({
    required String conversationId,
    required String messageId,
  }) async {
    final normalizedConversationId = conversationId.trim();
    final normalizedMessageId = normalizeDingTalkMessageId(messageId);
    final conversation = _conversations[normalizedConversationId];
    if (conversation == null) return null;
    final message = conversation.messages
        .where(
          (item) => normalizeDingTalkMessageId(item.id) == normalizedMessageId,
        )
        .firstOrNull;
    if (message == null || message.media.isEmpty) return message;
    final taskKey = normalizedMessageId.isEmpty
        ? message.id
        : normalizedMessageId;
    final active = _mediaHydrationTasks[taskKey];
    if (active != null) return active;
    _mediaHydrationFailures.remove(taskKey);
    final task = (() async {
      try {
        final hydrated = await _hydrateMessageMedia(conversation, message);
        _setMediaHydrationFailure(
          taskKey,
          hydrated.media.any((item) => item.localPath.trim().isEmpty),
        );
        return hydrated;
      } catch (error, stack) {
        _setMediaHydrationFailure(taskKey, true);
        silentLog('dingtalk_gateway', '缓存钉钉媒体', error, stack);
        return conversation.messages
                .where((item) => normalizeDingTalkMessageId(item.id) == taskKey)
                .firstOrNull ??
            message;
      }
    })();
    _mediaHydrationTasks[taskKey] = task;
    _notify();
    try {
      return await task;
    } finally {
      if (identical(_mediaHydrationTasks[taskKey], task)) {
        _mediaHydrationTasks.remove(taskKey);
        _notify();
      }
    }
  }

  void _setMediaHydrationFailure(String messageId, bool failed) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (normalizedId.isEmpty) return;
    final changed = failed
        ? _mediaHydrationFailures.add(normalizedId)
        : _mediaHydrationFailures.remove(normalizedId);
    if (!changed) return;
    while (_mediaHydrationFailures.length > _maxMediaHydrationFailureIds) {
      _mediaHydrationFailures.remove(_mediaHydrationFailures.first);
    }
    _notify();
  }

  Future<DingTalkGatewayMessage> _hydrateMessageMedia(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) async {
    var changed = false;
    final media = <DingTalkGatewayMedia>[];
    for (final sourceItem in message.media) {
      if (isDingTalkResourceIdInUrlQuery(
        message.content,
        sourceItem.resourceId,
        resourceType: sourceItem.resourceType,
      )) {
        changed = true;
        continue;
      }
      final resourceId = normalizeDingTalkResourceId(sourceItem.resourceId);
      final item = resourceId == sourceItem.resourceId
          ? sourceItem
          : sourceItem.copyWith(resourceId: resourceId);
      if (!identical(item, sourceItem)) changed = true;
      if (resourceId.isEmpty) {
        final next = item.copyWith(localPath: '');
        media.add(next);
        if (next.localPath != sourceItem.localPath) changed = true;
        continue;
      }
      final currentPath = item.localPath.trim();
      if (currentPath.isNotEmpty) {
        try {
          final file = File(currentPath);
          if (await file.exists() && await file.length() > 0) {
            media.add(item);
            continue;
          }
        } catch (_) {}
      }
      if (item.resourceId.startsWith('local-')) {
        final next = item.copyWith(localPath: '');
        media.add(next);
        if (next.localPath != sourceItem.localPath) changed = true;
        continue;
      }
      final path = await _service.ensureMediaCached(item);
      final next = path == null || path.trim().isEmpty
          ? item.copyWith(localPath: '')
          : item.copyWith(localPath: path);
      media.add(next);
      if (next.localPath != sourceItem.localPath ||
          next.resourceId != sourceItem.resourceId) {
        changed = true;
      }
    }
    if (!changed) return message;
    final hydrated = message.copyWith(media: media);
    final index = conversation.messages.indexWhere(
      (item) => item.id == message.id,
    );
    if (index >= 0) {
      conversation.messages[index] = hydrated;
      _queuePersist();
      _notify();
    }
    return hydrated;
  }

  Future<void> ensureConversationMediaCached(String conversationId) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return;
    final messages = conversation.messages.reversed
        .where((message) => message.media.isNotEmpty)
        .take(_mediaWarmupMessageLimit)
        .toList(growable: false);
    if (messages.isEmpty) return;
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= messages.length) return;
        final message = messages[index];
        try {
          await ensureMessageMediaCached(
            conversationId: conversationId,
            messageId: message.id,
          );
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '加载钉钉会话媒体', error, stack);
        }
      }
    }

    final workerCount = messages.length < _mediaCacheConcurrency
        ? messages.length
        : _mediaCacheConcurrency;
    try {
      await Future.wait<void>(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      ).timeout(_mediaPreparationTimeout);
    } on TimeoutException catch (error, stack) {
      silentLog('dingtalk_gateway', '钉钉会话媒体预热超时', error, stack);
    }
  }

  Future<Object?> loadConversationDetails(String conversationId) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return null;
    return _service.conversationDetails(conversation: conversation);
  }

  Future<bool> updateMessageFeedback(
    String conversationId,
    String messageId,
    DingTalkGatewayMessageFeedback? feedback,
  ) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) {
      _errorMessage = '消息所属会话不存在或已失效。';
      _notify();
      return false;
    }
    final index = conversation.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) {
      _errorMessage = '消息不存在或已失效。';
      _notify();
      return false;
    }
    final current = conversation.messages[index];
    if (!current.isAssistant || current.recalled) {
      _errorMessage = '当前消息不支持反馈。';
      _notify();
      return false;
    }
    try {
      final session = _aiSessionForConversation(conversation);
      final source = _resolveAiSourceMessage(conversation, current);
      final storedSourceId = current.sourceAiMessageId.trim();
      final sourceId = storedSourceId.isNotEmpty
          ? storedSourceId
          : source?.id ?? '';
      if (session != null && sourceId.isNotEmpty) {
        final aiFeedback = switch (feedback) {
          DingTalkGatewayMessageFeedback.liked =>
            AiSessionMessageFeedback.liked,
          DingTalkGatewayMessageFeedback.needsImprovement =>
            AiSessionMessageFeedback.needsImprovement,
          null => null,
        };
        final saved = await _sessionController.updateMessageFeedback(
          sessionId: session.id,
          messageId: sourceId,
          feedback: aiFeedback,
        );
        if (!saved) {
          _errorMessage = '关联的 AI 消息反馈保存失败，请稍后重试。';
          _notify();
          return false;
        }
      }
      if (_disposed ||
          !identical(_conversations[conversationId], conversation)) {
        return false;
      }
      final latestIndex = conversation.messages.indexWhere(
        (message) => message.id == messageId,
      );
      if (latestIndex < 0) {
        _errorMessage = '消息在保存期间已失效，请刷新后重试。';
        _notify();
        return false;
      }
      final latest = conversation.messages[latestIndex];
      conversation.messages[latestIndex] = latest.copyWith(
        sourceAiMessageId: sourceId.isEmpty ? null : sourceId,
        feedback: feedback,
        clearFeedback: feedback == null,
      );
      _queuePersist();
      _clearError();
      _notify();
      return true;
    } catch (error, stack) {
      _setError('保存钉钉消息反馈', error, stack);
      _notify();
      return false;
    }
  }

  Future<DingTalkMessageAuditSnapshot?> loadMessageAuditSnapshot(
    String conversationId,
    String messageId,
  ) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return null;
    final message = conversation.messages
        .where((item) => item.id == messageId)
        .firstOrNull;
    if (message == null) return null;
    final session = _aiSessionForConversation(conversation);
    var aiMessage = _resolveAiSourceMessage(conversation, message);
    if (session != null) {
      final sourceId = message.sourceAiMessageId.trim();
      if (aiMessage == null && sourceId.isNotEmpty) {
        aiMessage = await _sessionController.store.loadMessage(
          session.id,
          sourceId,
        );
      } else if (aiMessage != null &&
          aiSessionMessageHasDeferredTelemetryMetadata(aiMessage.metadata)) {
        aiMessage = await _sessionController.store.loadMessage(
          session.id,
          aiMessage.id,
        );
      }
    }
    if (_disposed || !identical(_conversations[conversationId], conversation)) {
      return null;
    }
    final latestMessage = conversation.messages
        .where((item) => item.id == messageId)
        .firstOrNull;
    if (latestMessage == null) return null;
    return DingTalkMessageAuditSnapshot(
      conversation: conversation,
      message: latestMessage,
      aiSession: session,
      aiMessage: aiMessage,
    );
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
      final next = await _service.authStatus();
      final previousIdentity = _authStatus.identity;
      final nextIdentity = next.identity;
      if (previousIdentity.userId != nextIdentity.userId ||
          previousIdentity.openDingTalkId != nextIdentity.openDingTalkId ||
          previousIdentity.name != nextIdentity.name) {
        _selfSenderIds.clear();
      }
      _authStatus = next;
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
    final previousTargets = _eventSubscriptionTargetKeys(_settings);
    final normalized = _normalizeSettings(value);
    if (_settings.templateId != normalized.templateId) {
      for (final conversation in _conversations.values) {
        conversation.aiSessionId = null;
        conversation.aiContextCheckpointMessageId = null;
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
    final targetsChanged = !listEquals(
      previousTargets,
      _eventSubscriptionTargetKeys(_settings),
    );
    if (_isPolling && !_usingPollingFallback && targetsChanged) {
      await _restartEventListening();
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
    _service.resetMessageQueryCapability();
    _usingPollingFallback = false;
    _warningMessage = null;
    _lastPollAt = DateTime.now().subtract(_queryWindow);
    _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
    _conversationReconcileCursor = 0;
    _conversationReconcileFailures.clear();
    _schedulePolling(immediate: true);
    _notify();
    unawaited(_startEventListening());
  }

  Future<void> stopPolling() async {
    _isPolling = false;
    _usingPollingFallback = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
    _conversationReconcileCursor = 0;
    _conversationReconcileFailures.clear();
    _pendingRecalledMessageIds.clear();
    _pendingStatusEvents.clear();
    _notify();
    await _stopEventListening();
  }

  Future<void> pollNow() => _pollOnce();

  Future<bool> sendMessage(String conversationId, String text) async {
    return sendMessageWithAttachments(conversationId, text, const <String>[]);
  }

  Future<bool> sendMessageWithAttachments(
    String conversationId,
    String text,
    Iterable<String> filePaths,
  ) async {
    final conversation = _conversations[conversationId];
    final content = text.trim();
    final paths = <String>[];
    final seenPaths = <String>{};
    for (final rawPath in filePaths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seenPaths.add(path)) continue;
      if (paths.length >= kDingTalkMessageAttachmentLimit) break;
      paths.add(path);
    }
    if (conversation == null ||
        (content.isEmpty && paths.isEmpty) ||
        _isSending ||
        isConversationResponding(conversationId) ||
        _editingMessageInFlight ||
        !isAuthorized) {
      return false;
    }
    final responseVersion = _responseCancellationVersions[conversationId] ?? 0;
    final files = <({String path, FileStat stat})>[];
    try {
      for (final path in paths) {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size <= 0 ||
            stat.size > kDingTalkMessageAttachmentMaxBytes) {
          throw StateError('附件无效、为空或超过 512MB 上限：${p.basename(path)}。');
        }
        files.add((path: path, stat: stat));
      }
    } catch (error, stack) {
      _setError('发送钉钉附件', error, stack);
      _notify();
      return false;
    }
    _isSending = true;
    _notify();
    try {
      DingTalkGatewayMessage? lastSentMessage;
      for (final entry in files) {
        final name = p.basename(entry.path).trim().isEmpty
            ? '文件'
            : p.basename(entry.path).trim();
        final localMessage = _localFileMessage(
          conversation,
          path: entry.path,
          name: name,
          kind: DingTalkMediaKindX.fromFileName(name),
          sizeBytes: entry.stat.size,
        );
        _appendMessage(conversation, localMessage);
        _notify();
        final sent = await _service.sendFileWithDetails(
          conversation: conversation,
          filePath: entry.path,
          uuid: _uuid.v4(),
        );
        _rememberRemoteConversationId(conversation, sent?.conversationId);
        lastSentMessage = _bindSentMessageId(
          conversation,
          localMessage,
          sent?.messageId,
        );
      }
      if (content.isNotEmpty) {
        final localMessage = DingTalkGatewayMessage(
          id: 'local-${_uuid.v4()}',
          conversationId: conversation.id,
          conversationType: conversation.type,
          role: DingTalkGatewayMessageRole.user,
          content: content,
          createdAt: DateTime.now(),
          senderName: _authStatus.identity.label,
          senderId: _authStatus.identity.userId,
          fromSelf: true,
        );
        _appendMessage(conversation, localMessage);
        _notify();
        final sent = await _service.sendWithDetails(
          conversation: conversation,
          text: content,
          uuid: _uuid.v4(),
        );
        _rememberRemoteConversationId(conversation, sent?.conversationId);
        lastSentMessage = _bindSentMessageId(
          conversation,
          localMessage,
          sent?.messageId,
        );
      }
      final sourceMessage = lastSentMessage;
      if (sourceMessage == null) return false;
      final aiContent = content.isNotEmpty
          ? content
          : '用户发送了 ${files.length} 个文件附件，请结合附件内容处理。';
      await _enqueueAiResponse(
        conversation,
        aiContent,
        sourceMessageId: sourceMessage.id,
        responseVersion: responseVersion,
      );
      return true;
    } catch (error, stack) {
      _setError(files.isEmpty ? '发送钉钉消息' : '发送钉钉消息及附件', error, stack);
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  Future<bool> sendFile(
    String conversationId,
    String filePath, {
    bool audio = false,
  }) async {
    final conversation = _conversations[conversationId];
    final normalizedPath = filePath.trim();
    if (conversation == null || normalizedPath.isEmpty) return false;
    return _sendSingleFile(conversation, normalizedPath, audio: audio);
  }

  Future<bool> _sendSingleFile(
    DingTalkConversation conversation,
    String normalizedPath, {
    bool audio = false,
  }) async {
    if (normalizedPath.isEmpty ||
        _isSending ||
        _editingMessageInFlight ||
        isConversationResponding(conversation.id) ||
        !isAuthorized) {
      return false;
    }
    final file = File(normalizedPath);
    if (!await file.exists()) return false;
    final rawName = p.basename(normalizedPath).trim();
    final name = rawName.isEmpty ? (audio ? '语音.m4a' : '文件') : rawName;
    final kind = audio
        ? DingTalkMediaKind.audio
        : DingTalkMediaKindX.fromFileName(name);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > kDingTalkMessageAttachmentMaxBytes) {
      _setError(
        audio ? '发送钉钉语音' : '发送钉钉文件',
        StateError('文件无效、为空或超过 512MB 上限：$name。'),
        StackTrace.current,
      );
      _notify();
      return false;
    }
    final message = _localFileMessage(
      conversation,
      path: normalizedPath,
      name: name,
      kind: kind,
      sizeBytes: stat.size,
      audio: audio,
    );
    _isSending = true;
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    _appendMessage(conversation, message);
    _notify();
    try {
      final sent = await _service.sendFileWithDetails(
        conversation: conversation,
        filePath: normalizedPath,
        audio: audio,
        uuid: _uuid.v4(),
      );
      _rememberRemoteConversationId(conversation, sent?.conversationId);
      final sentMessage = _bindSentMessageId(
        conversation,
        message,
        sent?.messageId,
      );
      await _enqueueAiResponse(
        conversation,
        sentMessage.content,
        sourceMessageId: sentMessage.id,
        responseVersion: responseVersion,
      );
      return true;
    } catch (error, stack) {
      _setError(audio ? '发送钉钉语音' : '发送钉钉文件', error, stack);
      return false;
    } finally {
      _isSending = false;
      _notify();
    }
  }

  Future<bool> sendAudio(String conversationId, String filePath) =>
      sendFile(conversationId, filePath, audio: true);

  DingTalkGatewayMessage _localFileMessage(
    DingTalkConversation conversation, {
    required String path,
    required String name,
    required DingTalkMediaKind kind,
    required int sizeBytes,
    bool audio = false,
  }) {
    return DingTalkGatewayMessage(
      id: 'local-${_uuid.v4()}',
      conversationId: conversation.id,
      conversationType: conversation.type,
      role: DingTalkGatewayMessageRole.user,
      content: audio ? '[语音] $name' : '[文件] $name',
      createdAt: DateTime.now(),
      senderName: _authStatus.identity.label,
      senderId: _authStatus.identity.userId,
      media: <DingTalkGatewayMedia>[
        DingTalkGatewayMedia(
          resourceId: 'local-${_uuid.v4()}',
          kind: kind,
          name: name,
          sizeBytes: sizeBytes,
          localPath: path,
        ),
      ],
      fromSelf: true,
    );
  }

  Future<bool> editMessage(
    String conversationId,
    String messageId,
    String text,
  ) async {
    final conversation = _conversations[conversationId];
    final normalized = text.trim();
    if (conversation == null ||
        normalized.isEmpty ||
        messageId.trim().isEmpty ||
        _editingMessageInFlight ||
        _isSending ||
        !isAuthorized) {
      return false;
    }
    if (_responseInFlight.contains(conversation.id)) {
      _setError(
        '编辑钉钉消息',
        StateError('AI 正在响应，请等待本轮响应完成后再编辑消息。'),
        StackTrace.current,
      );
      _notify();
      return false;
    }
    final index = conversation.messages.indexWhere(
      (message) => message.id == messageId.trim(),
    );
    if (index < 0) return false;
    final current = conversation.messages[index];
    if (!_isSelf(current) ||
        current.recalled ||
        current.media.isNotEmpty ||
        current.content.trim() == normalized) {
      return false;
    }
    _editingMessageInFlight = true;
    _clearError();
    _notify();
    try {
      var remoteMessageId = current.id;
      if (_isTemporaryMessageId(remoteMessageId)) {
        final resolved = await _service
            .resolveRecentSentMessage(
              conversation: conversation,
              content: current.content,
              createdAt: current.createdAt,
              senderName: current.senderName.trim().isEmpty
                  ? _authStatus.identity.name
                  : current.senderName,
            )
            .timeout(const Duration(seconds: 10));
        final resolvedId = resolved?.messageId?.trim() ?? '';
        if (resolvedId.isEmpty) {
          throw StateError('未找到钉钉侧消息标识，请刷新会话后重试。');
        }
        remoteMessageId = resolvedId;
        _rememberRemoteConversationId(conversation, resolved?.conversationId);
        if (_disposed ||
            !identical(_conversations[conversation.id], conversation) ||
            index >= conversation.messages.length ||
            conversation.messages[index].id != current.id) {
          return false;
        }
        conversation.messages[index] = current.copyWith(id: remoteMessageId);
        _remember(remoteMessageId);
        _queuePersist();
        _notify();
      }
      await _service
          .editMessage(
            conversation: conversation,
            messageId: remoteMessageId,
            text: normalized,
          )
          .timeout(const Duration(seconds: 30));
      if (_disposed ||
          !identical(_conversations[conversation.id], conversation) ||
          index >= conversation.messages.length ||
          conversation.messages[index].id != remoteMessageId) {
        return false;
      }
      final latest = conversation.messages[index];
      final history = <DingTalkMessageEditRecord>[...latest.editHistory];
      if (history.isEmpty || history.last.content != latest.content) {
        history.add(
          DingTalkMessageEditRecord(
            content: latest.content,
            editedAt: DateTime.now(),
          ),
        );
      }
      if (history.length > _maxMessageEditHistoryEntries) {
        history.removeRange(0, history.length - _maxMessageEditHistoryEntries);
      }
      conversation.messages[index] = latest.copyWith(
        content: normalized,
        editHistory: history.toList(growable: false),
      );
      _queuePersist();
      _notify();
      return true;
    } catch (error, stack) {
      _setError('编辑钉钉消息', error, stack);
      _notify();
      return false;
    } finally {
      _editingMessageInFlight = false;
      _notify();
    }
  }

  bool _isTemporaryMessageId(String messageId) {
    return messageId.startsWith('local-') || messageId.startsWith('assistant-');
  }

  DingTalkGatewayMessage _mergeOutgoingMessage(
    DingTalkGatewayMessage local,
    DingTalkGatewayMessage remote,
    String remoteId,
  ) {
    return local.copyWith(
      id: remoteId,
      content: remote.content.isEmpty ? null : remote.content,
      media: remote.media.isEmpty
          ? null
          : _mergeMediaCache(local.media, remote.media),
      mentionedCurrentUser: remote.mentionedCurrentUser ? true : null,
      recalled: remote.recalled ? true : null,
      readByPeer: remote.readByPeer ? true : null,
    );
  }

  DingTalkGatewayMessage _bindSentMessageId(
    DingTalkConversation conversation,
    DingTalkGatewayMessage localMessage,
    String? remoteMessageId,
  ) {
    final id = remoteMessageId?.trim() ?? '';
    final localIndex = conversation.messages.indexWhere(
      (message) => message.id == localMessage.id,
    );
    final outgoingIndex = localIndex >= 0
        ? localIndex
        : conversation.messages.indexWhere(
            (message) =>
                message.fromSelf &&
                message.role == localMessage.role &&
                message.createdAt == localMessage.createdAt,
          );
    final outgoing = outgoingIndex >= 0
        ? conversation.messages[outgoingIndex]
        : localMessage;
    if (id.isEmpty || id == outgoing.id) return outgoing;
    final remoteIndex = conversation.messages.indexWhere(
      (message) => message.id == id && message.id != outgoing.id,
    );
    // 实时回流可能已先把临时消息替换成真实 ID，发送接口返回后直接复用该消息，
    // 避免 AI 请求继续引用已经不存在的 local-* 标识。
    if (outgoingIndex < 0) {
      if (remoteIndex >= 0) {
        final merged = _mergeOutgoingMessage(
          localMessage,
          conversation.messages[remoteIndex],
          id,
        );
        conversation.messages[remoteIndex] = merged;
        _remember(id);
        _queuePersist();
        _notify();
        return merged;
      }
      return localMessage;
    }
    if (remoteIndex >= 0) {
      final merged = _mergeOutgoingMessage(
        outgoing,
        conversation.messages[remoteIndex],
        id,
      );
      conversation.messages.removeAt(remoteIndex);
      final refreshedIndex = conversation.messages.indexWhere(
        (message) => message.id == outgoing.id,
      );
      if (refreshedIndex < 0) return merged;
      conversation.messages[refreshedIndex] = merged;
      _remember(id);
      _queuePersist();
      _notify();
      return merged;
    }
    final sentMessage = outgoing.copyWith(id: id);
    conversation.messages[outgoingIndex] = sentMessage;
    _remember(id);
    _queuePersist();
    _notify();
    return sentMessage;
  }

  void _rememberRemoteConversationId(
    DingTalkConversation conversation,
    String? remoteConversationId,
  ) {
    if (conversation.type != DingTalkConversationType.direct) return;
    final normalized = remoteConversationId?.trim() ?? '';
    if (normalized.isEmpty || conversation.openConversationId == normalized) {
      return;
    }
    conversation.openConversationId = normalized;
    _queuePersist();
    _notify();
  }

  Future<void> _pollOnce() async {
    if (!_isPolling || _pollInFlight || !isAuthorized || _disposed) return;
    _pollInFlight = true;
    try {
      final now = DateTime.now();
      Object? queryError;
      try {
        final result = await _service.query(start: _lastPollAt, end: now);
        _lastPollAt = now.subtract(const Duration(seconds: 2));
        _warningMessage = result.warning;
        for (final message in result.messages) {
          _handleIncomingMessage(message);
        }
      } catch (error, stack) {
        queryError = error;
        if (error is TimeoutException) {
          _warningMessage = '钉钉消息同步较慢，已跳过本轮，下一轮将继续重试。';
          _clearError();
          silentLog('dingtalk_gateway', '钉钉轮询超时，跳过本轮', error, stack);
        } else {
          _setError('轮询钉钉消息', error, stack);
        }
      }
      if (!now.isBefore(_nextConversationReconcileAt)) {
        _nextConversationReconcileAt = now.add(_conversationReconcileInterval);
        _scheduleRecentConversationReconcile();
      }
      if (queryError == null) {
        _clearError();
      } else {
        await refreshAuthStatus();
        if (!isAuthorized) await stopPolling();
      }
    } finally {
      _pollInFlight = false;
      _notify();
    }
  }

  void _scheduleRecentConversationReconcile() {
    if (_periodicReconcileFuture != null || _disposed || !_isPolling) return;
    late final Future<void> task;
    task = () async {
      try {
        await _reconcileRecentConversations();
      } catch (error, stack) {
        if (!_disposed) {
          silentLog('dingtalk_gateway', '执行钉钉会话定期对账', error, stack);
        }
      }
    }();
    _periodicReconcileFuture = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_periodicReconcileFuture, task)) {
          _periodicReconcileFuture = null;
        }
      }),
    );
  }

  Future<void> _reconcileRecentConversations() async {
    final conversations =
        _conversations.values
            .where((conversation) => conversation.id.trim().isNotEmpty)
            .toList(growable: true)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (conversations.isEmpty) return;
    final reconcileCount = math.min(
      conversations.length,
      _maxConversationReconcileCount,
    );
    final start = _conversationReconcileCursor % conversations.length;
    final batch = List<DingTalkConversation>.generate(
      reconcileCount,
      (index) => conversations[(start + index) % conversations.length],
      growable: false,
    );
    _conversationReconcileCursor =
        (start + reconcileCount) % conversations.length;

    var nextIndex = 0;
    Future<void> worker() async {
      while (!_disposed && _isPolling) {
        final index = nextIndex++;
        if (index >= batch.length) return;
        final conversation = batch[index];
        if (_conversationReconcileTasks.containsKey(conversation.id)) {
          continue;
        }
        final failure = _conversationReconcileFailures[conversation.id];
        if (failure != null && DateTime.now().isBefore(failure.retryAt)) {
          continue;
        }
        try {
          final page = await _queryRecentConversation(conversation);
          if (_disposed || !_isPolling) return;
          if (!identical(_conversations[conversation.id], conversation)) {
            continue;
          }
          _conversationReconcileFailures.remove(conversation.id);
          final state = _conversationHistoryStates.putIfAbsent(
            conversation.id,
            _DingTalkConversationHistoryState.new,
          );
          state
            ..hasMore = page.hasMore
            ..initialized = true;
          _ingestReconciledMessages(conversation, page.messages);
        } catch (error, stack) {
          if (_disposed || !_isPolling) return;
          if (!identical(_conversations[conversation.id], conversation)) {
            continue;
          }
          final now = DateTime.now();
          final previous = _conversationReconcileFailures[conversation.id];
          final failureCount = math.min(
            (previous?.failureCount ?? 0) + 1,
            _maxConversationReconcileFailureCount,
          );
          final commandError = error is DingTalkGatewayCommandException
              ? error
              : null;
          final retryAfterSeconds = commandError?.retryAfterSeconds;
          final exponentialSeconds = math.min(
            _conversationReconcileInitialBackoff.inSeconds *
                (1 << (failureCount - 1)),
            _conversationReconcileMaxBackoff.inSeconds,
          );
          final backoffSeconds =
              retryAfterSeconds != null && retryAfterSeconds > 0
              ? retryAfterSeconds
                    .clamp(
                      _conversationReconcileInitialBackoff.inSeconds,
                      _conversationReconcileMaxBackoff.inSeconds,
                    )
                    .toInt()
              : commandError != null && !commandError.isRetryable
              ? _conversationReconcileMaxBackoff.inSeconds
              : exponentialSeconds;
          final errorKey = commandError == null
              ? '${error.runtimeType}:$error'
              : '${commandError.reason}:${commandError.serverCode}:'
                    '${commandError.operation}:${commandError.message}';
          final shouldLog =
              commandError == null &&
              (previous == null ||
                  previous.errorKey != errorKey ||
                  now.difference(previous.lastLoggedAt) >=
                      _conversationReconcileLogInterval);
          _conversationReconcileFailures[conversation.id] =
              _ConversationReconcileFailure(
                failureCount: failureCount,
                retryAt: now.add(Duration(seconds: backoffSeconds)),
                errorKey: errorKey,
                lastLoggedAt: shouldLog ? now : previous?.lastLoggedAt ?? now,
              );
          if (shouldLog) {
            silentLog('dingtalk_gateway', '对账钉钉会话消息', error, stack);
          }
        }
      }
    }

    final workerCount = math.min(
      batch.length,
      _conversationReconcileConcurrency,
    );
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
  }

  Future<void> _startEventListening() async {
    try {
      final stream = await _service.startEventSubscription(
        targets: _eventSubscriptionTargets(),
      );
      if (!_isPolling || _disposed) {
        await _service.stopEventSubscription();
        return;
      }
      _eventSubscription = stream.listen(
        _handleIncomingEvent,
        onError: (Object error, StackTrace stack) {
          silentLog('dingtalk_gateway', '实时事件监听异常', error, stack);
          if (_eventRestartFuture == null) {
            unawaited(_fallbackToPolling());
          }
        },
        onDone: () {
          if (_eventRestartFuture == null) {
            unawaited(_fallbackToPolling());
          }
        },
      );
      _usingPollingFallback = false;
      _schedulePolling(interval: _realtimeReconcilePollInterval);
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

  Future<void> _restartEventListening() {
    final active = _eventRestartFuture;
    if (active != null) return active;
    final task = () async {
      await _stopEventListening();
      if (_isPolling && !_usingPollingFallback && !_disposed) {
        await _startEventListening();
      }
    }();
    _eventRestartFuture = task;
    return task.whenComplete(() {
      if (identical(_eventRestartFuture, task)) _eventRestartFuture = null;
    });
  }

  Future<void> _stopEventListening() async {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription != null) {
      await runAsyncCleanupBounded(
        subscription.cancel,
        timeout: _shutdownCleanupTimeout,
        onError: (error, stack) =>
            silentLog('dingtalk_gateway', '取消钉钉实时事件订阅', error, stack),
      );
    }
    await runAsyncCleanupBounded(
      _service.stopEventSubscription,
      timeout: _shutdownCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '停止钉钉实时事件订阅', error, stack),
    );
  }

  bool _mergeIncomingOutgoingEcho(
    DingTalkGatewayMessage incoming,
    DingTalkConversation conversation,
  ) {
    final incomingId = incoming.id.trim();
    if (incomingId.isEmpty) return false;
    final incomingContent = incoming.content.trim();
    final incomingSenderId = incoming.senderId.trim();
    final incomingSenderName = incoming.senderName.trim();
    final incomingIsSelf = _isSelf(incoming);
    final directPeerIds = conversation.type == DingTalkConversationType.direct
        ? (<String>{
            conversation.directUserId?.trim() ?? '',
            conversation.directOpenDingTalkId?.trim() ?? '',
          }..remove(''))
        : const <String>{};
    var localIndex = -1;
    Duration? closestAge;
    for (final entry in conversation.messages.asMap().entries) {
      final local = entry.value;
      if (!local.fromSelf ||
          local.id == incomingId ||
          local.role != DingTalkGatewayMessageRole.user ||
          local.conversationType != incoming.conversationType) {
        continue;
      }
      final localSenderId = local.senderId.trim();
      final localSenderName = local.senderName.trim();
      final senderNamesMatch =
          incomingSenderName.isNotEmpty &&
          localSenderName.isNotEmpty &&
          _sameIdentityName(incomingSenderName, localSenderName);
      if (!incomingIsSelf &&
          (directPeerIds.contains(incomingSenderId) ||
              (incomingSenderId.isNotEmpty &&
                  localSenderId.isNotEmpty &&
                  incomingSenderId != localSenderId &&
                  !senderNamesMatch) ||
              (incomingSenderId.isEmpty &&
                  incomingSenderName.isNotEmpty &&
                  localSenderName.isNotEmpty &&
                  !senderNamesMatch))) {
        continue;
      }
      final age = incoming.createdAt.difference(local.createdAt).abs();
      if (age > _outgoingEchoWindow) continue;
      final sameContent =
          incomingContent.isNotEmpty && local.content.trim() == incomingContent;
      final sameMedia = _outgoingMediaMatches(
        local.media,
        incoming.media,
        incomingContent,
      );
      if (!sameContent && !sameMedia) continue;
      if (closestAge == null || age < closestAge) {
        localIndex = entry.key;
        closestAge = age;
      }
    }
    if (localIndex < 0) return false;
    final local = conversation.messages[localIndex];
    final remoteIndex = conversation.messages.indexWhere(
      (message) => message.id == incomingId && message.id != local.id,
    );
    final merged = _mergeOutgoingMessage(local, incoming, incomingId);
    if (remoteIndex >= 0) conversation.messages.removeAt(remoteIndex);
    final refreshedIndex = conversation.messages.indexWhere(
      (message) => message.id == local.id,
    );
    if (refreshedIndex < 0) return false;
    conversation.messages[refreshedIndex] = merged;
    if (incomingSenderId.isNotEmpty) _selfSenderIds.add(incomingSenderId);
    _remember(incomingId);
    _queuePersist();
    return true;
  }

  bool _outgoingMediaMatches(
    List<DingTalkGatewayMedia> local,
    List<DingTalkGatewayMedia> incoming,
    String incomingContent,
  ) {
    final normalizedContent = incomingContent.toLowerCase();
    if (local.length == 1 && incoming.isEmpty) {
      final localName = local.single.name.trim().toLowerCase();
      return localName.isNotEmpty && normalizedContent.contains(localName);
    }
    if (local.isEmpty || local.length != incoming.length) return false;
    for (var index = 0; index < local.length; index++) {
      final expected = local[index];
      final actual = incoming[index];
      final expectedId = normalizeDingTalkResourceId(expected.resourceId);
      final actualId = normalizeDingTalkResourceId(actual.resourceId);
      if (!expectedId.startsWith('local-') &&
          expectedId.isNotEmpty &&
          expectedId == actualId &&
          expected.resourceType == actual.resourceType) {
        continue;
      }
      final expectedName = expected.name.trim().toLowerCase();
      final actualName = actual.name.trim().toLowerCase();
      final nameMatches =
          expectedName.isNotEmpty &&
          (expectedName == actualName ||
              normalizedContent.contains(expectedName));
      if (nameMatches) continue;
      final sizeConflicts =
          expected.sizeBytes > 0 &&
          actual.sizeBytes > 0 &&
          expected.sizeBytes != actual.sizeBytes;
      if (sizeConflicts ||
          expected.kind != actual.kind ||
          (expectedName.isNotEmpty && actualName.isNotEmpty)) {
        return false;
      }
    }
    return true;
  }

  void _handleIncomingMessage(
    DingTalkGatewayMessage message, {
    bool allowResponse = true,
    bool allowHistorical = false,
  }) {
    if (!_isPolling || _disposed) return;
    final messageId = normalizeDingTalkMessageId(message.id);
    if (messageId.isEmpty) return;
    final normalizedMessage = messageId == message.id
        ? message
        : message.copyWith(id: messageId);
    final incomingConversation = _conversationForIncomingMessage(
      normalizedMessage,
    );
    if (incomingConversation != null &&
        _mergeIncomingOutgoingEcho(normalizedMessage, incomingConversation)) {
      if (!allowHistorical && normalizedMessage.media.isNotEmpty) {
        unawaited(_cacheIncomingMedia(incomingConversation, normalizedMessage));
      }
      _notify();
      return;
    }
    final pendingRecall = _pendingRecalledMessageIds.remove(messageId);
    final incoming = pendingRecall && !normalizedMessage.recalled
        ? normalizedMessage.copyWith(recalled: true)
        : normalizedMessage;
    final existingConversation = _conversationContainingMessage(messageId);
    if (existingConversation != null) {
      final previous = existingConversation.messages
          .where((item) => normalizeDingTalkMessageId(item.id) == messageId)
          .firstOrNull;
      _mergeQueriedMessage(existingConversation, incoming);
      _applyPendingStatusEvents(existingConversation, messageId);
      _remember(messageId);
      if (!allowHistorical && incoming.media.isNotEmpty) {
        unawaited(_cacheIncomingMedia(existingConversation, incoming));
      }
      if (previous != null &&
          allowResponse &&
          !previous.mentionedCurrentUser &&
          incoming.mentionedCurrentUser &&
          !incoming.recalled &&
          !_isSelf(previous) &&
          !_isSelf(incoming) &&
          _canRespondToMessage(incoming)) {
        unawaited(
          _cacheAndEnqueueIncomingMessage(existingConversation, incoming),
        );
      }
      return;
    }
    final localConversation = _conversationForIncomingMessage(incoming);
    // 事件/全局消息查询可能在用户打开会话前先收到并记入 seen 集合。
    // 只要当前会话已经打开，仍需把这条消息补入本地列表；seen 只能阻止
    // 没有目标会话的重复事件，不能阻止已打开会话的历史补偿同步。
    if (_seenMessageIds.contains(messageId) && localConversation == null) {
      return;
    }
    final allowedTarget = _targetForIncomingMessage(
      incoming,
      localConversation,
    );
    if (allowedTarget == null) return;
    if (!allowHistorical &&
        localConversation != null &&
        incoming.createdAt.isBefore(
          localConversation.createdAt.subtract(_conversationStartSkew),
        )) {
      _remember(messageId);
      return;
    }
    _remember(messageId);
    if (_isSelf(incoming) && !allowHistorical) return;
    final conversationId =
        localConversation?.id ??
        (incoming.conversationType == DingTalkConversationType.group
            ? incoming.conversationId
            : allowedTarget.id);
    final conversation =
        localConversation ??
        _conversations.putIfAbsent(
          conversationId,
          () => DingTalkConversation(
            id: conversationId,
            type: incoming.conversationType,
            title: allowedTarget.title.trim().isNotEmpty
                ? allowedTarget.title
                : incoming.conversationTitle.trim().isNotEmpty
                ? incoming.conversationTitle
                : incoming.senderName.trim().isEmpty
                ? '钉钉会话'
                : incoming.senderName,
            createdAt: incoming.createdAt,
            directUserId: allowedTarget.userId.trim().isEmpty
                ? null
                : allowedTarget.userId.trim(),
            directOpenDingTalkId: allowedTarget.openDingTalkId.trim().isEmpty
                ? null
                : allowedTarget.openDingTalkId.trim(),
          ),
        );
    if (conversation.type == DingTalkConversationType.direct) {
      final remoteConversationId = incoming.conversationId.trim();
      if (remoteConversationId.isNotEmpty &&
          conversation.openConversationId != remoteConversationId) {
        conversation.openConversationId = remoteConversationId;
        _queuePersist();
      }
    }
    _appendMessage(conversation, incoming);
    _applyPendingStatusEvents(conversation, messageId);
    _unreadCount += 1;
    if (_settings.reminderMode == DingTalkReminderMode.sound) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    final shouldRespond = _canRespondToMessage(incoming);
    if (!allowHistorical && incoming.media.isNotEmpty && !shouldRespond) {
      unawaited(_cacheIncomingMedia(conversation, incoming));
    }
    if (!incoming.recalled && shouldRespond && allowResponse) {
      unawaited(_cacheAndEnqueueIncomingMessage(conversation, incoming));
    }
    _notify();
  }

  Future<void> _cacheIncomingMedia(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) async {
    try {
      await ensureMessageMediaCached(
        conversationId: conversation.id,
        messageId: message.id,
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '缓存钉钉实时媒体', error, stack);
    }
  }

  DingTalkConversation? _conversationContainingMessage(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (normalizedId.isEmpty) return null;
    for (final conversation in _conversations.values) {
      if (conversation.messages.any(
        (item) => normalizeDingTalkMessageId(item.id) == normalizedId,
      )) {
        return conversation;
      }
    }
    return null;
  }

  void _mergeQueriedMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage remote,
  ) {
    final remoteId = normalizeDingTalkMessageId(remote.id);
    final index = conversation.messages.indexWhere(
      (item) => normalizeDingTalkMessageId(item.id) == remoteId,
    );
    if (index < 0) return;
    final current = conversation.messages[index];
    final contentChanged =
        remote.content.isNotEmpty && remote.content != current.content;
    final recalledChanged = remote.recalled && !current.recalled;
    final mediaChanged =
        remote.media.isNotEmpty && !_sameMedia(current.media, remote.media);
    final mentionChanged =
        remote.mentionedCurrentUser && !current.mentionedCurrentUser;
    final readChanged = remote.readByPeer && !current.readByPeer;
    final reactionsChanged =
        remote.reactions.isNotEmpty &&
        !listEquals(remote.reactions, current.reactions);
    if (!contentChanged &&
        !recalledChanged &&
        !mediaChanged &&
        !mentionChanged &&
        !readChanged &&
        !reactionsChanged) {
      return;
    }

    var history = current.editHistory;
    if (contentChanged && current.content.trim().isNotEmpty) {
      final nextHistory = <DingTalkMessageEditRecord>[...history];
      if (nextHistory.isEmpty || nextHistory.last.content != current.content) {
        nextHistory.add(
          DingTalkMessageEditRecord(
            content: current.content,
            editedAt: DateTime.now(),
          ),
        );
      }
      if (nextHistory.length > _maxMessageEditHistoryEntries) {
        nextHistory.removeRange(
          0,
          nextHistory.length - _maxMessageEditHistoryEntries,
        );
      }
      history = nextHistory.toList(growable: false);
    }
    final media = mediaChanged
        ? _mergeMediaCache(current.media, remote.media)
        : null;
    if (mediaChanged) _mediaHydrationFailures.remove(remoteId);
    conversation.messages[index] = current.copyWith(
      content: contentChanged ? remote.content : null,
      media: media,
      mentionedCurrentUser: mentionChanged ? true : null,
      readByPeer: readChanged ? true : null,
      recalled: recalledChanged ? true : null,
      reactions: reactionsChanged ? remote.reactions : null,
      editHistory: history,
    );
    _queuePersist();
    _notify();
  }

  bool _sameMedia(
    List<DingTalkGatewayMedia> left,
    List<DingTalkGatewayMedia> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (normalizeDingTalkResourceId(a.resourceId) !=
              normalizeDingTalkResourceId(b.resourceId) ||
          a.resourceType != b.resourceType ||
          a.kind != b.kind ||
          a.name != b.name ||
          a.mimeType != b.mimeType ||
          a.sizeBytes != b.sizeBytes ||
          a.durationMs != b.durationMs) {
        return false;
      }
    }
    return true;
  }

  List<DingTalkGatewayMedia> _mergeMediaCache(
    List<DingTalkGatewayMedia> current,
    List<DingTalkGatewayMedia> remote,
  ) {
    return remote
        .map((item) {
          final normalizedId = normalizeDingTalkResourceId(item.resourceId);
          for (final previous in current) {
            final sameResource =
                normalizeDingTalkResourceId(previous.resourceId) ==
                    normalizedId &&
                previous.resourceType == item.resourceType;
            final previousName = previous.name.trim().toLowerCase();
            final itemName = item.name.trim().toLowerCase();
            final kindCompatible =
                previous.kind == item.kind ||
                (itemName.isEmpty &&
                    item.resourceType == DingTalkMediaResourceType.fileId);
            final sameLocalAttachment =
                previous.resourceId.startsWith('local-') &&
                kindCompatible &&
                (previousName.isNotEmpty && previousName == itemName ||
                    itemName.isEmpty ||
                    (previous.sizeBytes > 0 &&
                        item.sizeBytes > 0 &&
                        previous.sizeBytes == item.sizeBytes));
            if ((sameResource || sameLocalAttachment) &&
                previous.localPath.trim().isNotEmpty) {
              final kind =
                  item.kind == DingTalkMediaKind.file &&
                      previous.kind != DingTalkMediaKind.file
                  ? previous.kind
                  : item.kind;
              return item.copyWith(
                resourceId: normalizedId,
                kind: kind,
                name: item.name.trim().isEmpty ? previous.name : null,
                mimeType: item.mimeType.trim().isEmpty
                    ? previous.mimeType
                    : null,
                sizeBytes: item.sizeBytes > 0 ? null : previous.sizeBytes,
                localPath: previous.localPath,
              );
            }
          }
          return item.copyWith(resourceId: normalizedId);
        })
        .toList(growable: false);
  }

  void _handleIncomingEvent(DingTalkGatewayEvent event) {
    if (!_isPolling || _disposed) return;
    if (event.type == DingTalkGatewayEventType.message) {
      final message = event.message;
      if (message != null) _handleIncomingMessage(message);
      return;
    }
    final eventMessageId = normalizeDingTalkMessageId(event.messageId);
    if (eventMessageId.isEmpty) return;
    final conversation = _conversationForEvent(event);
    if (conversation == null) {
      if (event.type == DingTalkGatewayEventType.recall) {
        _rememberPendingRecall(eventMessageId);
      }
      _rememberPendingStatusEvent(event, eventMessageId);
      _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
      _reconcileConversationsForEvent(event);
      unawaited(_pollOnce());
      return;
    }
    _applyPendingStatusEvents(conversation, eventMessageId);
    if (_applyStatusEvent(conversation, event, eventMessageId)) return;
    if (event.type == DingTalkGatewayEventType.recall) {
      _rememberPendingRecall(eventMessageId);
    }
    _rememberPendingStatusEvent(event, eventMessageId);
    _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(_reconcileAndApplyEvent(conversation, event, eventMessageId));
    unawaited(_pollOnce());
  }

  bool _applyStatusEvent(
    DingTalkConversation conversation,
    DingTalkGatewayEvent event,
    String eventMessageId,
  ) {
    final index = conversation.messages.indexWhere(
      (message) => normalizeDingTalkMessageId(message.id) == eventMessageId,
    );
    if (index < 0) return false;
    final current = conversation.messages[index];
    DingTalkGatewayMessage? updated;
    switch (event.type) {
      case DingTalkGatewayEventType.read:
        if (!current.readByPeer) {
          updated = current.copyWith(readByPeer: true);
        }
      case DingTalkGatewayEventType.recall:
        _pendingRecalledMessageIds.remove(eventMessageId);
        if (!current.recalled) {
          updated = current.copyWith(recalled: true);
        }
      case DingTalkGatewayEventType.reaction:
        final reaction = event.reaction.trim();
        if (reaction.isEmpty) return true;
        final reactions = List<String>.from(current.reactions);
        if (event.reactionRemoved) {
          reactions.remove(reaction);
        } else if (!reactions.contains(reaction) &&
            reactions.length < _maxReactionTypes) {
          reactions.add(reaction);
        }
        if (!listEquals(reactions, current.reactions)) {
          updated = current.copyWith(
            reactions: reactions.toList(growable: false),
          );
        }
      case DingTalkGatewayEventType.message:
        return true;
    }
    if (updated == null) return true;
    conversation.messages[index] = updated;
    _queuePersist();
    _notify();
    return true;
  }

  void _rememberPendingStatusEvent(
    DingTalkGatewayEvent event,
    String messageId,
  ) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (normalizedId.isEmpty) return;
    final events = _pendingStatusEvents.putIfAbsent(
      normalizedId,
      () => <DingTalkGatewayEvent>[],
    );
    final duplicate = events.any(
      (item) =>
          item.type == event.type &&
          item.reaction == event.reaction &&
          item.reactionRemoved == event.reactionRemoved,
    );
    if (!duplicate) {
      events.add(event);
      if (events.length > _maxPendingStatusEventsPerMessage) {
        events.removeRange(
          0,
          events.length - _maxPendingStatusEventsPerMessage,
        );
      }
    }
    while (_pendingStatusEvents.length > _maxPendingStatusMessageIds) {
      _pendingStatusEvents.remove(_pendingStatusEvents.keys.first);
    }
  }

  void _applyPendingStatusEvents(
    DingTalkConversation conversation,
    String messageId,
  ) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    final events = _pendingStatusEvents.remove(normalizedId);
    if (events == null) return;
    for (final event in events) {
      _applyStatusEvent(conversation, event, normalizedId);
    }
  }

  Future<void> _reconcileAndApplyEvent(
    DingTalkConversation conversation,
    DingTalkGatewayEvent event,
    String eventMessageId,
  ) async {
    await _reconcileConversationNow(conversation);
    if (_disposed ||
        !_isPolling ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    _applyPendingStatusEvents(conversation, eventMessageId);
    _applyStatusEvent(conversation, event, eventMessageId);
  }

  void _reconcileConversationsForEvent(DingTalkGatewayEvent event) {
    final conversationId = event.conversationId.trim();
    final matching = _conversations.values
        .where((conversation) {
          if (conversation.type != event.conversationType) return false;
          if (conversationId.isEmpty) return true;
          if (conversation.id.trim() == conversationId ||
              conversation.openConversationId?.trim() == conversationId ||
              conversation.directUserId?.trim() == conversationId ||
              conversation.directOpenDingTalkId?.trim() == conversationId) {
            return true;
          }
          // 单聊事件的 conversation_id 可能在首次状态事件前才生成，
          // 此时按已订阅类型补偿查询，查询结果会回填真实会话 ID。
          return event.conversationType == DingTalkConversationType.direct;
        })
        .toList(growable: false);
    final candidates =
        (matching.isNotEmpty
                ? matching
                : _conversations.values.where(
                    (conversation) =>
                        conversation.type == event.conversationType,
                  ))
            .take(_maxConversationReconcileCount)
            .toList(growable: false);
    for (final conversation in candidates) {
      unawaited(
        _reconcileAndApplyEvent(
          conversation,
          event,
          normalizeDingTalkMessageId(event.messageId),
        ),
      );
    }
  }

  Future<DingTalkConversationMessagePage> _queryRecentConversation(
    DingTalkConversation conversation, {
    DateTime? before,
  }) async {
    return _service.queryConversationPage(
      conversation: conversation,
      before: before,
    );
  }

  Future<void> _reconcileConversationNow(DingTalkConversation conversation) {
    final active = _conversationReconcileTasks[conversation.id];
    if (active != null) return active;
    final failure = _conversationReconcileFailures[conversation.id];
    if (failure != null && DateTime.now().isBefore(failure.retryAt)) {
      return Future<void>.value();
    }
    final task = () async {
      try {
        final page = await _queryRecentConversation(conversation);
        if (_disposed ||
            !_isPolling ||
            !identical(_conversations[conversation.id], conversation)) {
          return;
        }
        _conversationReconcileFailures.remove(conversation.id);
        final state = _conversationHistoryStates.putIfAbsent(
          conversation.id,
          _DingTalkConversationHistoryState.new,
        );
        state
          ..hasMore = page.hasMore
          ..initialized = true;
        _ingestReconciledMessages(conversation, page.messages);
      } catch (error, stack) {
        if (_disposed || !_isPolling) return;
        final now = DateTime.now();
        final previous = _conversationReconcileFailures[conversation.id];
        final errorKey = '${error.runtimeType}:$error';
        final shouldLog =
            previous == null ||
            previous.errorKey != errorKey ||
            now.difference(previous.lastLoggedAt) >=
                _conversationReconcileLogInterval;
        _conversationReconcileFailures[conversation.id] =
            _ConversationReconcileFailure(
              failureCount: math.min(
                (previous?.failureCount ?? 0) + 1,
                _maxConversationReconcileFailureCount,
              ),
              retryAt: now.add(_conversationReconcileInitialBackoff),
              errorKey: errorKey,
              lastLoggedAt: shouldLog ? now : previous.lastLoggedAt,
            );
        if (shouldLog) {
          silentLog('dingtalk_gateway', '事件触发钉钉会话对账', error, stack);
        }
      }
    }();
    _conversationReconcileTasks[conversation.id] = task;
    return task.whenComplete(() {
      if (identical(_conversationReconcileTasks[conversation.id], task)) {
        _conversationReconcileTasks.remove(conversation.id);
      }
    });
  }

  int _ingestReconciledMessages(
    DingTalkConversation conversation,
    List<DingTalkGatewayMessage> messages,
  ) {
    if (conversation.type == DingTalkConversationType.direct &&
        (conversation.openConversationId?.trim().isEmpty ?? true)) {
      final remoteConversationId = messages
          .map((message) => message.conversationId.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      if (remoteConversationId.isNotEmpty) {
        conversation.openConversationId = remoteConversationId;
        _queuePersist();
      }
    }
    final knownIds = conversation.messages
        .map((message) => normalizeDingTalkMessageId(message.id))
        .where((id) => id.isNotEmpty)
        .toSet();
    final latestLocalTime = conversation.messages.isEmpty
        ? conversation.createdAt
        : conversation.updatedAt;
    final recentCutoff = latestLocalTime.subtract(_conversationStartSkew);
    var addedCount = 0;
    for (final message in messages) {
      final messageId = normalizeDingTalkMessageId(message.id);
      final isNew = messageId.isNotEmpty && !knownIds.contains(messageId);
      _handleIncomingMessage(
        message,
        allowResponse: !isNew || !message.createdAt.isBefore(recentCutoff),
        allowHistorical: true,
      );
      if (isNew && messageId.isNotEmpty) addedCount++;
    }
    return addedCount;
  }

  void _rememberPendingRecall(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (normalizedId.isEmpty) return;
    _pendingRecalledMessageIds.add(normalizedId);
    while (_pendingRecalledMessageIds.length > _maxPendingRecallIds) {
      _pendingRecalledMessageIds.remove(_pendingRecalledMessageIds.first);
    }
  }

  DingTalkConversation? _conversationForEvent(DingTalkGatewayEvent event) {
    final conversationId = event.conversationId.trim();
    final messageId = normalizeDingTalkMessageId(event.messageId);
    if (messageId.isEmpty) return null;
    // 消息 ID 是跨会话稳定标识，优先按 ID 定位，避免事件中的 chat_type
    // 缺失或版本差异导致撤回/已读事件被丢弃。
    for (final conversation in _conversations.values) {
      if (conversation.messages.any(
        (message) => normalizeDingTalkMessageId(message.id) == messageId,
      )) {
        return conversation;
      }
    }
    if (conversationId.isEmpty) return null;
    for (final conversation in _conversations.values) {
      if (conversation.type != event.conversationType) continue;
      if (conversation.type == DingTalkConversationType.group) {
        if (conversation.id.trim() == conversationId ||
            conversation.openConversationId?.trim() == conversationId) {
          return conversation;
        }
        continue;
      }
      if (conversation.id.trim() == conversationId ||
          conversation.openConversationId?.trim() == conversationId ||
          conversation.directUserId?.trim() == conversationId ||
          conversation.directOpenDingTalkId?.trim() == conversationId ||
          conversation.messages.any(
            (message) => message.conversationId.trim() == conversationId,
          )) {
        return conversation;
      }
    }
    return null;
  }

  List<DingTalkConversationTarget> _eventSubscriptionTargets({
    DingTalkGatewaySettings? settings,
  }) {
    final effectiveSettings = settings ?? _settings;
    final targets = <DingTalkConversationTarget>[
      ...effectiveSettings.allowedGroupTargets,
      ...effectiveSettings.allowedContactTargets,
      ..._conversations.values.map(_targetFromConversation),
    ];
    final seen = <String>{};
    return targets
        .where(
          (target) =>
              target.id.trim().isNotEmpty &&
              seen.add('${target.type.name}:${target.id.trim()}'),
        )
        .toList(growable: false);
  }

  List<String> _eventSubscriptionTargetKeys(DingTalkGatewaySettings settings) {
    final keys = <String>{};
    for (final target in _eventSubscriptionTargets(settings: settings)) {
      final id = target.id.trim();
      if (id.isEmpty) continue;
      final targetFlag = target.type == DingTalkConversationType.group
          ? '--group'
          : target.userId.trim().isNotEmpty ||
                target.openDingTalkId.trim().isEmpty
          ? '--user'
          : '--open-dingtalk-id';
      final subscriptionTarget = target.type == DingTalkConversationType.group
          ? id
          : target.userId.trim().isNotEmpty
          ? target.userId.trim()
          : target.openDingTalkId.trim().isNotEmpty
          ? target.openDingTalkId.trim()
          : id;
      keys.add('${target.type.name}:$targetFlag:$subscriptionTarget');
    }
    return keys.toList(growable: false)..sort();
  }

  Future<void> _cacheAndEnqueueIncomingMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) async {
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    if (_disposed) return;
    _beginResponsePreparing(conversation.id);
    try {
      await _ensureIncomingContextMedia(conversation, message.id);
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
      final hydrated = conversation.messages
          .where((item) => item.id == message.id)
          .firstOrNull;
      final effective = hydrated ?? message;
      await _enqueueAiResponse(
        conversation,
        effective.content,
        sourceMessageId: effective.id,
        responseVersion: responseVersion,
      );
    } catch (error, stack) {
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
      silentLog('dingtalk_gateway', '准备钉钉媒体消息', error, stack);
      await _enqueueAiResponse(
        conversation,
        message.content,
        sourceMessageId: message.id,
        responseVersion: responseVersion,
      );
    } finally {
      _endResponsePreparing(conversation.id);
    }
  }

  Future<void> _ensureIncomingContextMedia(
    DingTalkConversation conversation,
    String sourceMessageId,
  ) async {
    final sourceIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (sourceIndex < 0) return;
    final checkpointId =
        conversation.aiContextCheckpointMessageId?.trim() ?? '';
    final checkpointIndex = checkpointId.isEmpty
        ? -1
        : conversation.messages.indexWhere(
            (message) => message.id == checkpointId,
          );
    final candidates = <DingTalkGatewayMessage>[];
    for (var index = sourceIndex; index > checkpointIndex; index--) {
      final message = conversation.messages[index];
      if (message.isAssistant || message.media.isEmpty) continue;
      candidates.add(message);
      if (candidates.length >= 6) break;
    }
    if (candidates.isEmpty) return;
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= candidates.length) return;
        try {
          await ensureMessageMediaCached(
            conversationId: conversation.id,
            messageId: candidates[index].id,
          );
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '准备钉钉上下文媒体', error, stack);
        }
      }
    }

    final workerCount = math.min(candidates.length, _mediaCacheConcurrency);
    try {
      await Future.wait<void>(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      ).timeout(_mediaPreparationTimeout);
    } on TimeoutException catch (error, stack) {
      // 媒体准备超时后继续使用文本上下文，避免 @ 消息永久卡在准备阶段。
      silentLog('dingtalk_gateway', '准备钉钉上下文媒体超时，已降级为文本响应', error, stack);
    }
  }

  DingTalkConversation? _conversationForIncomingMessage(
    DingTalkGatewayMessage message,
  ) {
    final conversationId = message.conversationId.trim();
    final senderId = message.senderId.trim();
    for (final conversation in _conversations.values) {
      if (conversation.type != message.conversationType) continue;
      if (conversation.type == DingTalkConversationType.group) {
        if (conversation.id.trim() == conversationId ||
            conversation.openConversationId?.trim() == conversationId) {
          return conversation;
        }
        continue;
      }
      final identifiers = <String>{
        conversation.id.trim(),
        conversation.openConversationId?.trim() ?? '',
        conversation.directUserId?.trim() ?? '',
        conversation.directOpenDingTalkId?.trim() ?? '',
      }..remove('');
      if (identifiers.contains(conversationId) ||
          identifiers.contains(senderId) ||
          conversation.messages.any(
            (item) => item.conversationId.trim() == conversationId,
          )) {
        return conversation;
      }
    }
    return null;
  }

  DingTalkConversationTarget? _targetForIncomingMessage(
    DingTalkGatewayMessage message,
    DingTalkConversation? localConversation,
  ) {
    if (localConversation != null) {
      return _targetFromConversation(localConversation);
    }
    return _configuredTargetFor(message);
  }

  DingTalkConversationTarget? _configuredTargetFor(
    DingTalkGatewayMessage message,
  ) {
    if (_settings.responseMode == DingTalkResponseMode.all &&
        message.conversationId.trim().isNotEmpty) {
      return _targetFromIncomingMessage(message);
    }
    if (message.conversationType == DingTalkConversationType.group) {
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

  bool _canRespondToMessage(DingTalkGatewayMessage message) {
    if (_configuredTargetFor(message) == null) return false;
    return message.conversationType == DingTalkConversationType.direct ||
        message.mentionedCurrentUser;
  }

  DingTalkConversationTarget _targetFromIncomingMessage(
    DingTalkGatewayMessage message,
  ) {
    final conversationId = message.conversationId.trim();
    final title = message.conversationTitle.trim().isNotEmpty
        ? message.conversationTitle.trim()
        : message.senderName.trim().isNotEmpty
        ? message.senderName.trim()
        : message.conversationType == DingTalkConversationType.group
        ? '钉钉群聊'
        : '钉钉联系人';
    return DingTalkConversationTarget(
      id: conversationId,
      title: title,
      type: message.conversationType,
      userId: message.conversationType == DingTalkConversationType.direct
          ? message.senderId.trim()
          : '',
    );
  }

  DingTalkConversationTarget _targetFromConversation(
    DingTalkConversation conversation,
  ) {
    return DingTalkConversationTarget(
      id: conversation.id,
      title: conversation.title,
      type: conversation.type,
      userId: conversation.directUserId ?? '',
      openDingTalkId: conversation.directOpenDingTalkId ?? '',
      aliases: <String>[
        if (conversation.openConversationId?.trim().isNotEmpty == true)
          conversation.openConversationId!.trim(),
      ],
    );
  }

  void _schedulePolling({bool immediate = false, Duration? interval}) {
    _pollTimer?.cancel();
    final effectiveInterval = interval ?? _settings.pollInterval;
    _pollTimer = startNonOverlappingPeriodicTimer(
      effectiveInterval,
      (_) => _pollOnce(),
      callbackTimeout: _pollCallbackTimeout,
      cancelOnCallbackTimeout: false,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '执行钉钉轮询定时任务', error, stack),
    );
    if (immediate) unawaited(_pollOnce());
  }

  bool _isResponseCancelled(String conversationId, int version) {
    return _disposed ||
        // 未执行过“停止响应”时不会在 map 中写入版本，缺省版本为 0。
        // 直接比较可空值会把首次响应的 0 误判为已取消，导致 @ 消息
        // 只同步到列表却永远不会进入 AI 队列。
        (_responseCancellationVersions[conversationId] ?? 0) != version;
  }

  Future<void> _respondWithAi(
    DingTalkConversation conversation,
    String content,
    String sourceMessageId,
  ) async {
    if (_disposed || !_responseInFlight.add(conversation.id)) return;
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    _notify();
    try {
      final model = _resolveModel();
      final templates = _sessionController.availableTemplates;
      if (model == null) {
        _setResponseError(conversation.id, '未配置可用的 AI 模型，请先完善钉钉网关设置。');
        return;
      }
      if (templates.isEmpty) {
        _setResponseError(conversation.id, '没有可用的线程模板，暂时无法响应钉钉消息。');
        return;
      }
      final aiContent = _buildAiConversationTurn(
        conversation,
        sourceMessageId,
        fallbackContent: content,
      );
      await _mcpController.ensureRuntimeToolCatalogs(
        maxWait: const Duration(seconds: 6),
      );
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
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
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
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
      final dwsCatalog = _settings.allowedDingTalkDwsCommandIds.isEmpty
          ? const <AiDingTalkDwsCommand>[]
          : (await _service.loadDwsCommandCatalog())
                .where(
                  (command) => _settings.allowedDingTalkDwsCommandIds.contains(
                    command.cliPath,
                  ),
                )
                .toList(growable: false);
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
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
        availableDingTalkDwsCommands: dwsCatalog,
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
          'dingtalk_dws_executor': _executeDwsCommandForAi,
          'dingtalk_dws_selected_command_count': dwsCatalog.length,
          'dingtalk_multimodal_capabilities':
              _validMultimodalCapabilitiesForRuntime(),
          'dingtalk_media_generation_executor': _mediaExecutorForConversation(
            conversation,
          ),
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
        if (!created) {
          _setResponseError(
            conversation.id,
            _sessionController.lastErrorMessage ?? '创建钉钉 AI 会话失败，请查看运行日志。',
          );
          return;
        }
        for (final candidate in _sessionController.sessions.reversed) {
          if (candidate.isDingTalkGatewaySession &&
              candidate.metadata['dingtalk_conversation_id'] ==
                  conversation.id) {
            sessionId = candidate.id;
            break;
          }
        }
        conversation.aiSessionId = sessionId;
        if (_isResponseCancelled(conversation.id, responseVersion)) return;
      }
      if (sessionId == null) {
        _setResponseError(conversation.id, '未能建立钉钉 AI 会话，请查看运行日志。');
        return;
      }
      final attachmentPaths = _attachmentPathsForTurn(
        conversation,
        sourceMessageId,
      );
      await _sessionController.updateSessionFullAccessPermission(
        sessionId,
        _settings.fullAccessPermission,
      );
      if (_isResponseCancelled(conversation.id, responseVersion)) return;
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
      final echoCoordinator = _DingTalkEchoCoordinator(
        baselineMessageIds: baselineMessageIds,
        selectedTypes: _settings.responseEchoTypes.toSet(),
        typeOf: _echoTypeOf,
        textFor: _echoTextForMessage,
        isTerminal: _isEchoTerminal,
        isCancelled: () =>
            _isResponseCancelled(conversation.id, responseVersion),
        send: (source, text, uuid) => _sendDingTalkEcho(
          conversation: conversation,
          source: source,
          text: text,
          uuid: uuid,
        ),
        edit: (messageId, text) => _editDingTalkEcho(
          conversation: conversation,
          messageId: messageId,
          text: text,
        ),
        newUuid: _uuid.v4,
        onError: (action, error, stack) {
          silentLog('dingtalk_gateway', action, error, stack);
          _setResponseError(conversation.id, '$action失败，请查看钉钉网关运行日志。');
        },
      );

      AiSession? currentSession() {
        for (final item in _sessionController.sessions) {
          if (item.id == sessionId) return item;
        }
        return null;
      }

      void onSessionChanged() {
        if (_disposed ||
            _isResponseCancelled(conversation.id, responseVersion)) {
          return;
        }
        final session = currentSession();
        if (session != null) echoCoordinator.ingest(session);
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
        if (_isResponseCancelled(conversation.id, responseVersion)) return;
        final sent = await _sessionController.sendMessage(
          sessionId: sessionId,
          content: aiContent,
          model: model,
          runtimeContext: runtimeContext,
          attachmentFilePaths: attachmentPaths,
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
          userMessageMetadata: <String, Object?>{
            'sent_via': 'dingtalk_gateway',
            'dingtalk_source_message_id': sourceMessageId,
          },
        );
        if (!sent) {
          if (!_isResponseCancelled(conversation.id, responseVersion)) {
            _setResponseError(
              conversation.id,
              _sessionController.lastErrorMessageForSession(sessionId) ??
                  'AI 未返回响应，请检查模型配置与运行日志。',
            );
          }
          return;
        }
        if (_isResponseCancelled(conversation.id, responseVersion)) return;
        if (sourceMessageId.trim().isNotEmpty &&
            identical(_conversations[conversation.id], conversation)) {
          conversation.aiContextCheckpointMessageId = sourceMessageId.trim();
          _queuePersist();
        }
      } finally {
        _sessionController.removeListener(onSessionChanged);
        if (!_isResponseCancelled(conversation.id, responseVersion)) {
          final session = currentSession();
          if (session != null) echoCoordinator.ingest(session);
          try {
            await echoCoordinator.flush().timeout(const Duration(seconds: 45));
          } on TimeoutException {
            silentLog(
              'dingtalk_gateway',
              '收敛钉钉流式回显超时',
              TimeoutException('钉钉流式回显未在限定时间内完成。'),
              StackTrace.current,
            );
          }
        }
        echoCoordinator.dispose();
      }
    } catch (error, stack) {
      if (!_isResponseCancelled(conversation.id, responseVersion)) {
        _setResponseError(conversation.id, 'AI 响应失败，请查看钉钉网关运行日志。');
      }
      silentLog('dingtalk_gateway', '生成钉钉 AI 回复', error, stack);
    } finally {
      _responseInFlight.remove(conversation.id);
      if (_responseCancellationVersions[conversation.id] == responseVersion) {
        _responseCancellationVersions.remove(conversation.id);
      }
      _notify();
    }
  }

  String _buildAiConversationTurn(
    DingTalkConversation conversation,
    String sourceMessageId, {
    required String fallbackContent,
  }) {
    final sourceIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (sourceIndex < 0) return fallbackContent.trim();
    final checkpointId =
        conversation.aiContextCheckpointMessageId?.trim() ?? '';
    var startIndex = 0;
    if (checkpointId.isNotEmpty) {
      final checkpointIndex = conversation.messages.indexWhere(
        (message) => message.id == checkpointId,
      );
      if (checkpointIndex >= 0 && checkpointIndex < sourceIndex) {
        startIndex = checkpointIndex + 1;
      }
    }
    final pending = conversation.messages
        .sublist(startIndex, sourceIndex + 1)
        .where(
          (message) =>
              !message.isAssistant &&
              !message.recalled &&
              message.content.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (pending.isEmpty) return fallbackContent.trim();
    if (pending.length == 1 && pending.single.id == sourceMessageId) {
      return pending.single.content.trim();
    }

    final entries = <String>[];
    for (final message in pending) {
      final sender = message.senderName.trim().isEmpty
          ? '用户'
          : message.senderName.trim();
      final timestamp = message.createdAt.toLocal().toIso8601String();
      final timeLabel = timestamp.length >= 16
          ? timestamp.substring(0, 16).replaceFirst('T', ' ')
          : timestamp;
      final body = clipTextByCodeUnits(
        message.content.trim(),
        4000,
        suffix: '…',
      );
      entries.add('- [$timeLabel] $sender：$body');
    }
    var totalCharacters = 0;
    final retained = <String>[];
    for (final entry in entries.reversed) {
      final nextLength = totalCharacters + entry.length + 1;
      if (retained.length >= _maxAiConversationContextMessages ||
          nextLength > _maxAiConversationContextCharacters) {
        break;
      }
      retained.add(entry);
      totalCharacters = nextLength;
    }
    final ordered = retained.reversed.toList(growable: false);
    final omitted = entries.length - ordered.length;
    final buffer = StringBuffer()
      ..writeln('以下是本轮触发前尚未交给 Agent 的钉钉消息，仅用于上下文。')
      ..writeln('请只处理最后一条消息，其他消息不要单独回复。');
    if (omitted > 0) {
      buffer.writeln('较早的 $omitted 条消息因上下文窗口限制已省略。');
    }
    buffer
      ..writeln()
      ..write(ordered.join('\n'));
    return buffer.toString().trim();
  }

  List<String> _attachmentPathsForTurn(
    DingTalkConversation conversation,
    String sourceMessageId,
  ) {
    var endIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (endIndex < 0) endIndex = conversation.messages.length - 1;
    if (endIndex < 0) return const <String>[];
    final selected = <String>[];
    for (var index = endIndex; index >= 0; index--) {
      final message = conversation.messages[index];
      if (message.isAssistant) break;
      if (message.role != DingTalkGatewayMessageRole.user) continue;
      for (final media in message.media.reversed) {
        final path = media.localPath.trim();
        if (path.isEmpty || !File(path).existsSync()) continue;
        try {
          if (File(path).lengthSync() > aiMessageAttachmentMaxFileBytes) {
            continue;
          }
        } catch (_) {
          continue;
        }
        if (!selected.contains(path)) selected.add(path);
        if (selected.length >= 6) break;
      }
      if (selected.length >= 6) break;
    }
    return selected.reversed.toList(growable: false);
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
  static const int _maxMessageEditHistoryEntries = 32;

  DingTalkResponseEchoType? _echoTypeOf(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    if (message.isDeleted) return null;
    final isToolMessage =
        message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook;
    if (!isToolMessage && message.content.trim().isEmpty) return null;
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
      AiSessionMessageKind.toolCall ||
      AiSessionMessageKind.hook => DingTalkResponseEchoType.toolCall,
      _ => null,
    };
  }

  bool _isEchoTerminal(AiSessionMessage message) {
    if (message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook) {
      final status =
          '${message.metadata['tool_execution_status'] ?? message.metadata['tool_status'] ?? message.metadata['status'] ?? ''}'
              .trim()
              .toLowerCase();
      return _terminalToolEchoStatuses.contains(status);
    }
    return message.metadata[aiSessionMessageMetadataStreamingKey] != true;
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

  Future<String?> _sendDingTalkEcho({
    required DingTalkConversation conversation,
    required AiSessionMessage source,
    required String text,
    required String uuid,
  }) async {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final normalized = clipTextByCodeUnits(
      text.trim(),
      _maxDingTalkEchoCharacters,
      suffix: '\n\n…内容已截断',
    );
    if (normalized.isEmpty) return null;
    final sent = await _service
        .sendWithDetails(
          conversation: conversation,
          text: normalized,
          uuid: uuid,
        )
        .timeout(const Duration(seconds: 30));
    _rememberRemoteConversationId(conversation, sent?.conversationId);
    final remoteMessageId = sent?.messageId;
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final sentId = remoteMessageId?.trim() ?? '';
    final messageId = sentId.isEmpty ? 'assistant-${source.id}' : sentId;
    if (sentId.isNotEmpty) _remember(sentId);
    _appendMessage(
      conversation,
      DingTalkGatewayMessage(
        id: messageId,
        conversationId: conversation.id,
        conversationType: conversation.type,
        role: DingTalkGatewayMessageRole.assistant,
        content: normalized,
        createdAt: source.createdAt,
        sourceAiMessageId: source.id,
        feedback: switch (source.feedback) {
          AiSessionMessageFeedback.liked =>
            DingTalkGatewayMessageFeedback.liked,
          AiSessionMessageFeedback.needsImprovement =>
            DingTalkGatewayMessageFeedback.needsImprovement,
          null => null,
        },
      ),
    );
    _notify();
    return sentId.isEmpty ? null : sentId;
  }

  Future<void> _editDingTalkEcho({
    required DingTalkConversation conversation,
    required String messageId,
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
    if (normalized.isEmpty || messageId.trim().isEmpty) return;
    await _service
        .editMessage(
          conversation: conversation,
          messageId: messageId,
          text: normalized,
        )
        .timeout(const Duration(seconds: 20));
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final index = conversation.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index >= 0 && conversation.messages[index].content != normalized) {
      conversation.messages[index] = conversation.messages[index].copyWith(
        content: normalized,
      );
      _queuePersist();
      _notify();
    }
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
      'running' => '执行中',
      'pending' => '等待执行',
      'success' => '成功',
      'timed_out' => '超时',
      'cancelled' => '已取消',
      'denied' || 'rejected' => '已拒绝',
      'invalid_arguments' => '参数无效',
      'blocked' => '已阻止',
      'failed' => '失败',
      _ => status.isEmpty ? '等待执行' : status,
    };
    final durationLabel = durationMs <= 0
        ? '—'
        : durationMs >= 1000
        ? '${(durationMs / 1000).toStringAsFixed(2)} 秒'
        : '$durationMs 毫秒';
    return '''### 工具调用 · $toolName

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
    if (started == null) return 0;
    return (finished ?? DateTime.now().toUtc())
        .difference(started)
        .inMilliseconds
        .clamp(0, 86400000);
  }

  static const int _maxQueuedResponsesPerConversation = 256;

  Future<void> _enqueueAiResponse(
    DingTalkConversation conversation,
    String content, {
    String? sourceMessageId,
    int? responseVersion,
  }) {
    final normalized = content.trim();
    if (normalized.isEmpty ||
        _disposed ||
        (responseVersion != null &&
            _isResponseCancelled(conversation.id, responseVersion))) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    final requestedSourceId = sourceMessageId?.trim() ?? '';
    final sourceId = requestedSourceId.isEmpty
        ? conversation.messages.isEmpty
              ? ''
              : conversation.messages.last.id
        : requestedSourceId;
    final queue = _responseQueues.putIfAbsent(
      conversation.id,
      () => Queue<_QueuedDingTalkResponse>(),
    );
    if (queue.length >= _maxQueuedResponsesPerConversation) {
      // 极端突发消息时合并队尾，保留全部内容并限制内存增长。
      queue.last.merge(normalized, sourceId, completer);
      _warningMessage = '钉钉会话消息过多，已将突发消息合并后依次处理。';
    } else {
      queue.add(_QueuedDingTalkResponse(normalized, sourceId, completer));
    }
    _beginResponsePreparing(conversation.id);
    unawaited(
      completer.future.whenComplete(
        () => _endResponsePreparing(conversation.id),
      ),
    );
    _notify();
    if (_responseDraining.add(conversation.id)) {
      unawaited(_drainResponseQueue(conversation));
    }
    return completer.future;
  }

  void _beginResponsePreparing(String conversationId) {
    _responseErrors.remove(conversationId);
    _responsePreparingCounts.update(
      conversationId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _notify();
  }

  void _endResponsePreparing(String conversationId) {
    final count = _responsePreparingCounts[conversationId] ?? 0;
    if (count <= 1) {
      _responsePreparingCounts.remove(conversationId);
    } else {
      _responsePreparingCounts[conversationId] = count - 1;
    }
    _notify();
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
          await _respondWithAi(
            conversation,
            item.content,
            item.sourceMessageId,
          );
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '处理钉钉消息队列', error, stack);
        } finally {
          item.complete();
        }
      }
    } finally {
      _responseDraining.remove(conversation.id);
      if (identical(_responseQueues[conversation.id], queue) && queue.isEmpty) {
        _responseQueues.remove(conversation.id);
      }
      final pendingQueue = _responseQueues[conversation.id];
      if (!_disposed &&
          (pendingQueue?.isNotEmpty ?? false) &&
          _responseDraining.add(conversation.id)) {
        unawaited(_drainResponseQueue(conversation));
      }
      if (pendingQueue == null &&
          !_responseInFlight.contains(conversation.id) &&
          !_conversations.containsKey(conversation.id)) {
        _responseCancellationVersions.remove(conversation.id);
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

  /// 返回消息操作（朗读、翻译）应使用的模型，优先沿用该会话最近一次响应模型。
  AiModelConfig? messageActionFallbackModel(DingTalkConversation conversation) {
    final session = _aiSessionForConversation(conversation);
    final providerId = session?.lastUsedModelId?.trim() ?? '';
    final modelId = session?.lastUsedModelLabel?.trim() ?? '';
    if (providerId.isNotEmpty && modelId.isNotEmpty) {
      for (final provider in _settingsController.aiModels) {
        if (provider.id == providerId &&
            provider.allModelIds.contains(modelId)) {
          return provider.copyWith(modelId: modelId);
        }
      }
    }
    return _resolveModel();
  }

  AiSession? _aiSessionForConversation(DingTalkConversation conversation) {
    final sessionId = conversation.aiSessionId?.trim() ?? '';
    for (final session in _sessionController.sessions) {
      if ((sessionId.isNotEmpty && session.id == sessionId) ||
          (session.isDingTalkGatewaySession &&
              session.metadata['dingtalk_conversation_id'] ==
                  conversation.id)) {
        return session;
      }
    }
    return null;
  }

  AiSessionMessage? _resolveAiSourceMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    final session = _aiSessionForConversation(conversation);
    if (session == null) return null;
    final sourceId = message.sourceAiMessageId.trim();
    if (sourceId.isNotEmpty) {
      for (final candidate in session.messages) {
        if (candidate.id == sourceId) return candidate;
      }
    }
    const syntheticPrefix = 'assistant-';
    if (sourceId.isEmpty && message.id.startsWith(syntheticPrefix)) {
      final syntheticSourceId = message.id.substring(syntheticPrefix.length);
      if (syntheticSourceId.isNotEmpty) {
        for (final candidate in session.messages) {
          if (candidate.id == syntheticSourceId) return candidate;
        }
      }
    }
    if (!message.isAssistant) return null;
    AiSessionMessage? best;
    Duration? bestDistance;
    final content = message.content.trim();
    for (final candidate in session.messages) {
      if (candidate.isDeleted || candidate.role == AiSessionMessageRole.user) {
        continue;
      }
      if (content.isNotEmpty && candidate.content.trim() != content) continue;
      final distance = candidate.createdAt
          .toLocal()
          .difference(message.createdAt.toLocal())
          .abs();
      if (bestDistance == null || distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
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
    final currentOpenDingTalkId = _authStatus.identity.openDingTalkId.trim();
    final profile = _authStatus.identity.profile.trim();
    final profileUserId = profile.contains(':')
        ? profile.substring(profile.lastIndexOf(':') + 1)
        : profile;
    if (sender.isNotEmpty &&
        (_selfSenderIds.contains(sender) ||
            (current.isNotEmpty && sender == current) ||
            (currentOpenDingTalkId.isNotEmpty &&
                sender == currentOpenDingTalkId) ||
            (profile.isNotEmpty && sender == profile) ||
            (profileUserId.isNotEmpty && sender == profileUserId))) {
      return true;
    }
    final senderName = message.senderName.trim();
    final identityName = _authStatus.identity.name.trim();
    final identityLabel = _authStatus.identity.label.trim();
    return senderName.isNotEmpty &&
        ((identityName.isNotEmpty &&
                _sameIdentityName(senderName, identityName)) ||
            (identityLabel.isNotEmpty &&
                _sameIdentityName(senderName, identityLabel)));
  }

  bool _sameIdentityName(String left, String right) {
    String compact(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-－—]+'), '');

    String withoutNumericSuffix(String value) {
      if (value.length < 3) return value;
      final result = value.replaceFirst(RegExp(r'\d{1,3}$'), '');
      return result.length >= 2 ? result : value;
    }

    final leftCompact = compact(left);
    final rightCompact = compact(right);
    if (leftCompact.isEmpty || rightCompact.isEmpty) return false;
    if (leftCompact == rightCompact) return true;
    final leftBase = withoutNumericSuffix(leftCompact);
    final rightBase = withoutNumericSuffix(rightCompact);
    return (leftBase == rightCompact && leftBase != leftCompact) ||
        (rightBase == leftCompact && rightBase != rightCompact);
  }

  bool isMessageFromCurrentUser(DingTalkGatewayMessage message) =>
      _isSelf(message);

  void _appendMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    final messageId = normalizeDingTalkMessageId(message.id);
    if (messageId.isEmpty ||
        conversation.messages.any(
          (item) => normalizeDingTalkMessageId(item.id) == messageId,
        )) {
      return;
    }
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
    final normalizedId = normalizeDingTalkMessageId(id);
    if (normalizedId.isEmpty) return;
    _seenMessageIds.add(normalizedId);
    while (_seenMessageIds.length > _maxSeenIds) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }
  }

  void _setError(String action, Object error, StackTrace stack) {
    _errorMessage = '$action失败：$error';
    silentLog('dingtalk_gateway', action, error, stack);
  }

  void _setResponseError(String conversationId, String message) {
    final normalizedId = conversationId.trim();
    final normalizedMessage = message.trim();
    if (normalizedId.isEmpty || normalizedMessage.isEmpty || _disposed) return;
    _responseErrors[normalizedId] = clipTextByCodeUnits(
      normalizedMessage,
      300,
      suffix: '…',
    );
    _notify();
  }

  void _clearError() => _errorMessage = null;

  void _queuePersist() {
    if (_disposed || _shutdownRequested) return;
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
    while (_persistQueued && !_disposed) {
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
              createdAt: conversation.createdAt,
              openConversationId: conversation.openConversationId,
              directUserId: conversation.directUserId,
              directOpenDingTalkId: conversation.directOpenDingTalkId,
            );
            copy
              ..aiSessionId = conversation.aiSessionId
              ..aiContextCheckpointMessageId =
                  conversation.aiContextCheckpointMessageId;
            return copy;
          })
          .toList(growable: false);
      try {
        await _store
            .saveSnapshot(settings: _settings, conversations: conversations)
            .timeout(_shutdownCleanupTimeout);
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
    if (_disposed || _shutdownRequested || _notificationQueued) return;
    // dws 运行日志使用同步广播流，设置弹窗挂载/构建期间可能立即触发
    // 通知。合并到微任务，避免 Flutter 在 build 阶段标记组件重建。
    _notificationQueued = true;
    scheduleMicrotask(() {
      _notificationQueued = false;
      if (!_disposed && !_shutdownRequested) notifyListeners();
    });
  }

  Future<void> shutdown() {
    if (_disposed) return Future<void>.value();
    final active = _shutdownInFlight;
    if (active != null) return active;
    _shutdownRequested = true;
    late final Future<void> task;
    task = _shutdown().whenComplete(() {
      if (identical(_shutdownInFlight, task)) _shutdownInFlight = null;
    });
    _shutdownInFlight = task;
    return task;
  }

  Future<void> _shutdown() async {
    if (_disposed) return;
    _isPolling = false;
    _usingPollingFallback = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pendingRecalledMessageIds.clear();
    _pendingStatusEvents.clear();
    _conversationReconcileFailures.clear();
    _conversationHistoryStates.clear();
    _mediaHydrationFailures.clear();
    await _stopEventListening();
    final eventRestart = _eventRestartFuture;
    if (eventRestart != null) {
      await runAsyncCleanupBounded(
        () => eventRestart,
        timeout: _shutdownCleanupTimeout,
        onError: (error, stack) =>
            silentLog('dingtalk_gateway', '等待钉钉事件监听重启结束', error, stack),
      );
    }
    final activeResponseIds = _conversations.keys
        .where(isConversationResponding)
        .toList(growable: false);
    await Future.wait<void>(
      activeResponseIds.map(
        (conversationId) => runAsyncCleanupBounded(
          () => stopConversationResponse(conversationId),
          timeout: _shutdownCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', '停止钉钉会话响应', error, stack),
        ).then<void>((_) {}),
      ),
    );
    for (final queue in _responseQueues.values) {
      for (final item in queue) {
        item.complete();
      }
    }
    _responseQueues.clear();
    _responseDraining.clear();
    _responsePreparingCounts.clear();
    _responseErrors.clear();
    _responseCancellationVersions.clear();
    _writeApprovalHandler = null;
    final runtimeLogSubscription = _runtimeLogSubscription;
    _runtimeLogSubscription = null;
    if (runtimeLogSubscription != null) {
      await runAsyncCleanupBounded(
        runtimeLogSubscription.cancel,
        timeout: _shutdownCleanupTimeout,
        onError: (error, stack) =>
            silentLog('dingtalk_gateway', '取消钉钉运行日志订阅', error, stack),
      );
    }
    final persist = _persistInFlight;
    if (persist != null) {
      await runAsyncCleanupBounded(
        () => persist,
        timeout: _shutdownCleanupTimeout,
        onError: (error, stack) =>
            silentLog('dingtalk_gateway', '等待钉钉数据持久化结束', error, stack),
      );
    }
    _disposed = true;
    _mediaGenerationService.dispose();
    await runAsyncCleanupBounded(
      _service.cancelAuthorization,
      timeout: _shutdownCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '清理钉钉授权进程', error, stack),
    );
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}

class _ConversationReconcileFailure {
  const _ConversationReconcileFailure({
    required this.failureCount,
    required this.retryAt,
    required this.errorKey,
    required this.lastLoggedAt,
  });

  final int failureCount;
  final DateTime retryAt;
  final String errorKey;
  final DateTime lastLoggedAt;
}

typedef _DingTalkEchoTypeResolver =
    DingTalkResponseEchoType? Function(
      AiSessionMessage message,
      List<AiSessionMessage> messages,
    );
typedef _DingTalkEchoTextBuilder =
    String Function(AiSessionMessage message, List<AiSessionMessage> messages);
typedef _DingTalkEchoTerminalResolver = bool Function(AiSessionMessage message);
typedef _DingTalkEchoSender =
    Future<String?> Function(AiSessionMessage source, String text, String uuid);
typedef _DingTalkEchoEditor =
    Future<void> Function(String messageId, String text);
typedef _DingTalkEchoErrorHandler =
    void Function(String action, Object error, StackTrace stack);
typedef _DingTalkEchoCancellationChecker = bool Function();

/// 单轮钉钉 AI 回显协调器：首次发送后只编辑同一条消息，并合并高频流式增量。
class _DingTalkEchoCoordinator {
  _DingTalkEchoCoordinator({
    required Set<String> baselineMessageIds,
    required Set<DingTalkResponseEchoType> selectedTypes,
    required _DingTalkEchoTypeResolver typeOf,
    required _DingTalkEchoTextBuilder textFor,
    required _DingTalkEchoTerminalResolver isTerminal,
    required _DingTalkEchoCancellationChecker isCancelled,
    required _DingTalkEchoSender send,
    required _DingTalkEchoEditor edit,
    required String Function() newUuid,
    required _DingTalkEchoErrorHandler onError,
  }) : _baselineMessageIds = baselineMessageIds,
       _selectedTypes = selectedTypes,
       _typeOf = typeOf,
       _textFor = textFor,
       _isTerminal = isTerminal,
       _isCancelled = isCancelled,
       _send = send,
       _edit = edit,
       _newUuid = newUuid,
       _onError = onError;

  static const Duration _initialStreamDelay = Duration(milliseconds: 180);
  static const Duration _editInterval = Duration(seconds: 1);
  static const int _maxTrackedMessages = 96;

  final Set<String> _baselineMessageIds;
  final Set<DingTalkResponseEchoType> _selectedTypes;
  final _DingTalkEchoTypeResolver _typeOf;
  final _DingTalkEchoTextBuilder _textFor;
  final _DingTalkEchoTerminalResolver _isTerminal;
  final _DingTalkEchoCancellationChecker _isCancelled;
  final _DingTalkEchoSender _send;
  final _DingTalkEchoEditor _edit;
  final String Function() _newUuid;
  final _DingTalkEchoErrorHandler _onError;
  final LinkedHashMap<String, _PendingDingTalkEcho> _pending =
      LinkedHashMap<String, _PendingDingTalkEcho>();
  final LinkedHashMap<String, _DingTalkEchoDeliveryState> _states =
      LinkedHashMap<String, _DingTalkEchoDeliveryState>();
  Timer? _timer;
  DateTime? _scheduledAt;
  Future<void>? _activeDrain;
  bool _disposed = false;

  void ingest(AiSession session) {
    if (_disposed || _isCancelled() || _selectedTypes.isEmpty) return;
    final now = DateTime.now();
    for (final message in session.messages) {
      if (_baselineMessageIds.contains(message.id)) continue;
      final state = _states[message.id];
      final queued = _pending[message.id];
      final resolvedType = _typeOf(message, session.messages);
      // 未发送前允许消息类型随会话状态变化，避免助手消息由正式响应变为过程响应时
      // 仍沿用首次解析结果；已发送消息保持原卡片生命周期不变。
      final type = state?.type ?? resolvedType ?? queued?.type;
      if (type == null ||
          (state == null && queued == null && !_selectedTypes.contains(type))) {
        continue;
      }
      final text = _textFor(message, session.messages).trim();
      if (text.isEmpty) continue;
      if (state?.finished == true && state?.lastText == text) continue;
      final terminal = _isTerminal(message);
      if (state != null && state.lastText == text) {
        if (terminal) {
          state.finished = true;
          _pending.remove(message.id);
        }
        continue;
      }
      final readyAt = terminal
          ? now
          : queued?.readyAt ??
                _nextReadyAt(
                  now: now,
                  state: state,
                  immediate:
                      message.kind == AiSessionMessageKind.toolCall ||
                      message.kind == AiSessionMessageKind.hook,
                );
      _pending[message.id] = _PendingDingTalkEcho(
        source: message,
        type: type,
        text: text,
        terminal: terminal,
        readyAt: readyAt,
      );
    }
    _trimPending();
    _schedule();
  }

  DateTime _nextReadyAt({
    required DateTime now,
    required _DingTalkEchoDeliveryState? state,
    required bool immediate,
  }) {
    if (state == null) {
      return immediate ? now : now.add(_initialStreamDelay);
    }
    final next = state.lastMutationAt.add(_editInterval);
    return next.isAfter(now) ? next : now;
  }

  void _trimPending() {
    while (_pending.length > _maxTrackedMessages) {
      String? removableId;
      for (final entry in _pending.entries) {
        if (!entry.value.terminal) {
          removableId = entry.key;
          break;
        }
      }
      _pending.remove(removableId ?? _pending.keys.first);
    }
    while (_states.length > _maxTrackedMessages) {
      String? removableId;
      for (final entry in _states.entries) {
        if (entry.value.finished) {
          removableId = entry.key;
          break;
        }
      }
      removableId ??= _states.keys.first;
      _states.remove(removableId);
      _pending.remove(removableId);
    }
  }

  void _schedule() {
    if (_disposed || _activeDrain != null || _pending.isEmpty) return;
    final earliest = _pending.values
        .map((item) => item.readyAt)
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final scheduledAt = _scheduledAt;
    if (_timer != null &&
        scheduledAt != null &&
        !earliest.isBefore(scheduledAt)) {
      return;
    }
    _timer?.cancel();
    _scheduledAt = earliest;
    final delay = earliest.difference(DateTime.now());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, _startDrain);
  }

  void _startDrain() {
    if (_disposed || _isCancelled() || _activeDrain != null) return;
    _timer?.cancel();
    _timer = null;
    _scheduledAt = null;
    final task = _drainReady();
    _activeDrain = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_activeDrain, task)) _activeDrain = null;
        _schedule();
      }),
    );
  }

  Future<void> _drainReady() async {
    while (!_disposed && !_isCancelled() && _pending.isNotEmpty) {
      final now = DateTime.now();
      MapEntry<String, _PendingDingTalkEcho>? candidate;
      for (final entry in _pending.entries) {
        if (!entry.value.readyAt.isAfter(now)) {
          candidate = entry;
          break;
        }
      }
      if (candidate == null) return;
      _pending.remove(candidate.key);
      await _deliver(candidate.key, candidate.value);
    }
  }

  Future<void> _deliver(String sourceId, _PendingDingTalkEcho pending) async {
    if (_disposed || _isCancelled()) return;
    final state = _states.putIfAbsent(
      sourceId,
      () => _DingTalkEchoDeliveryState(type: pending.type, uuid: _newUuid()),
    );
    if (state.finished && state.lastText == pending.text) return;
    // 终态之后若工具结果或格式化字段补齐，允许再编辑一次同一条消息。
    state.finished = false;
    if (state.lastText == pending.text) {
      state.finished = pending.terminal;
      return;
    }
    try {
      if (_disposed || _isCancelled()) return;
      if (!state.sent) {
        state.remoteMessageId = await _send(
          pending.source,
          pending.text,
          state.uuid,
        );
        if (_disposed || _isCancelled()) return;
        state.sent = true;
      } else {
        final messageId = state.remoteMessageId?.trim() ?? '';
        if (messageId.isNotEmpty) {
          if (_disposed || _isCancelled()) return;
          await _edit(messageId, pending.text);
          if (_disposed || _isCancelled()) return;
        }
      }
      state.lastText = pending.text;
      state.lastMutationAt = DateTime.now();
      state.finished = pending.terminal;
    } catch (error, stack) {
      if (_disposed || _isCancelled()) return;
      state.lastMutationAt = DateTime.now();
      _onError(state.sent ? '编辑钉钉 AI 回显消息' : '发送钉钉 AI 回显消息', error, stack);
      if (pending.terminal &&
          state.sent &&
          (state.remoteMessageId?.trim().isNotEmpty ?? false)) {
        try {
          if (_disposed || _isCancelled()) return;
          state.remoteMessageId = await _send(
            pending.source,
            pending.text,
            _newUuid(),
          );
          if (_disposed || _isCancelled()) return;
          state.lastText = pending.text;
        } catch (fallbackError, fallbackStack) {
          _onError('补发钉钉 AI 终态回显消息', fallbackError, fallbackStack);
        }
      }
      state.finished = pending.terminal;
    }
  }

  Future<void> flush() async {
    if (_disposed || _isCancelled()) {
      _pending.clear();
      return;
    }
    _timer?.cancel();
    _timer = null;
    _scheduledAt = null;
    while (!_disposed &&
        !_isCancelled() &&
        (_pending.isNotEmpty || _activeDrain != null)) {
      final now = DateTime.now();
      for (final entry in _pending.entries.toList(growable: false)) {
        _pending[entry.key] = entry.value.copyWith(readyAt: now);
      }
      _startDrain();
      final task = _activeDrain;
      if (task == null) break;
      await task;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _states.clear();
  }
}

class _PendingDingTalkEcho {
  const _PendingDingTalkEcho({
    required this.source,
    required this.type,
    required this.text,
    required this.terminal,
    required this.readyAt,
  });

  final AiSessionMessage source;
  final DingTalkResponseEchoType type;
  final String text;
  final bool terminal;
  final DateTime readyAt;

  _PendingDingTalkEcho copyWith({DateTime? readyAt}) {
    return _PendingDingTalkEcho(
      source: source,
      type: type,
      text: text,
      terminal: terminal,
      readyAt: readyAt ?? this.readyAt,
    );
  }
}

class _DingTalkEchoDeliveryState {
  _DingTalkEchoDeliveryState({required this.type, required this.uuid});

  final DingTalkResponseEchoType type;
  final String uuid;
  String? remoteMessageId;
  String lastText = '';
  DateTime lastMutationAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool sent = false;
  bool finished = false;
}

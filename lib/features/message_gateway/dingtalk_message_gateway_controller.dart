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
import '../../shared/net/http_redirect_utils.dart';
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
import 'dingtalk_markdown_compat.dart';
import 'message_gateway_dependencies.dart';
import 'model/dingtalk_message_gateway.dart';
import 'service/dingtalk_message_gateway_service.dart';

const String _dingTalkResponseRoundIdMetadataKey = 'dingtalk_response_round_id';

enum DingTalkConversationResponseState {
  idle,
  active,
  awaitingApproval,
  failed,
}

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
    this.scheduledAt,
    this.sequence,
    this.forceResponse,
    this.automaticResponse,
    this.pollingGeneration,
    Completer<void> completer,
  ) : waiters = <Completer<void>>[completer];

  String content;
  String sourceMessageId;
  DateTime scheduledAt;
  final int sequence;
  bool forceResponse;
  final bool automaticResponse;
  final int? pollingGeneration;
  final List<Completer<void>> waiters;

  bool canMerge(bool nextAutomaticResponse, int? nextPollingGeneration) {
    return automaticResponse == nextAutomaticResponse &&
        (!automaticResponse || pollingGeneration == nextPollingGeneration);
  }

  void merge(
    String nextContent,
    String nextSourceMessageId,
    bool nextForceResponse,
    Completer<void> completer, {
    bool advanceSource = true,
    bool appendContent = false,
    bool trackWaiter = true,
  }) {
    if (advanceSource) {
      content = appendContent ? '$content\n\n$nextContent' : nextContent;
      sourceMessageId = nextSourceMessageId;
    }
    forceResponse = forceResponse || nextForceResponse;
    if (trackWaiter) waiters.add(completer);
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
       _gitSnapshotService = AiGitSnapshotService(),
       _workspaceInstructionService = AiWorkspaceInstructionService(),
       _mediaGenerationService = AiImageGenerationService() {
    _runtimeLogSubscription = _service.runtimeLogStream.listen((_) {
      if (_disposed || _shutdownRequested) return;
      _runtimeLogRevision.value = _service.runtimeLogRevision;
    });
  }

  static const Uuid _uuid = Uuid();
  static const int _mediaCacheConcurrency = 3;
  static const int _echoRestoreConcurrency = 4;
  static const int _targetSearchCacheMaxEntries = 20;
  static const int _targetSearchMaxConcurrentRequests = 8;
  static const Duration _targetSearchCacheTtl = Duration(seconds: 5);
  static const int _maxMediaHydrationFailureIds = 1024;
  static const int _maxSeenIds = 2000;
  static const int _maxPendingRecallIds = 512;
  static const int _maxPendingStatusMessageIds = 512;
  static const int _maxPendingStatusEventsPerMessage = 24;
  static const int _maxReactionTypes = 12;
  static const int _maxUnresolvedOutgoingMessageIds = 256;
  static const Duration _outgoingEchoWindow = Duration(seconds: 30);
  static const int _maxAiConversationContextCharacters = 48000;
  static const int _maxAiConversationContextMessages = 200;
  static const int _maxAiContextMessageCharacters = 4000;
  static const int _initialConversationHistoryMessageLimit = 20;
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
  static const String _groupResponseReminder =
      '钉钉群聊规则：围绕本轮最后一条 @我 消息回复；此前消息仅作上下文。仅输出一条适合发送的回复。';
  static const String _directResponseReminder =
      '钉钉私聊规则：综合本轮全部新消息，仅输出一条合并回复，不要逐条回复。';
  static const String _standardResponseReminder =
      '钉钉网关规则：仅回复本轮最后一条触发消息；此前消息仅作上下文，不逐条回复。直接输出适合发送给对方的回复。';
  static const String _forcedResponseReminder =
      '钉钉网关规则：回复本轮最后一条有效消息；此前消息仅作上下文。直接输出一条适合发送的回复。';
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
  final AiGitSnapshotService _gitSnapshotService;
  final AiWorkspaceInstructionService _workspaceInstructionService;
  final AiImageGenerationService _mediaGenerationService;
  final ValueNotifier<int> _runtimeLogRevision = ValueNotifier<int>(0);
  StreamSubscription<String>? _runtimeLogSubscription;
  final Map<String, DingTalkConversation> _conversations =
      <String, DingTalkConversation>{};
  final Set<String> _responseInFlight = <String>{};
  final Map<String, Set<String>> _activeResponseContextMessageIds =
      <String, Set<String>>{};
  final Map<String, int> _activeAutomaticResponseGenerations = <String, int>{};
  final Map<String, DateTime> _activeResponseLatestTriggerTimes =
      <String, DateTime>{};
  final Map<String, int> _responsePreparingCounts = <String, int>{};
  final Map<String, String> _responseErrors = <String, String>{};
  final Set<String> _pendingInitialContextHydration = <String>{};

  /// 每次停止响应都会递增。正在执行的响应携带启动时版本，前置异步
  /// 阶段完成后若版本已变化，立即结束本轮，避免停止后继续发起 AI 请求。
  final Map<String, int> _responseCancellationVersions = <String, int>{};
  final Map<String, Queue<_QueuedDingTalkResponse>> _responseQueues =
      <String, Queue<_QueuedDingTalkResponse>>{};
  final Set<String> _activeResponseConversationIds = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  final Set<String> _unresolvedOutgoingMessageIds = <String>{};
  // 正在流式回显中的源 AI 消息标识，驱动本地气泡的渐显动画与合并防回退。
  final Set<String> _streamingEchoSourceIds = <String>{};
  final Set<String> _selfSenderIds = <String>{};
  final Set<String> _pendingRecalledMessageIds = <String>{};
  final Map<String, List<DingTalkGatewayEvent>> _pendingStatusEvents =
      <String, List<DingTalkGatewayEvent>>{};
  final Map<String, (DateTime, List<DingTalkConversationTarget>)>
  _targetSearchCache = <String, (DateTime, List<DingTalkConversationTarget>)>{};
  final OpenHandKeyedSingleFlight<String, List<DingTalkConversationTarget>>
  _targetSearchFlights =
      OpenHandKeyedSingleFlight<String, List<DingTalkConversationTarget>>(
        maxConcurrentKeys: _targetSearchMaxConcurrentRequests,
      );
  final Map<String, Future<DingTalkGatewayMessage>> _mediaHydrationTasks =
      <String, Future<DingTalkGatewayMessage>>{};
  final Set<String> _mediaHydrationFailures = <String>{};
  final Map<String, _DingTalkConversationHistoryState>
  _conversationHistoryStates = <String, _DingTalkConversationHistoryState>{};
  final Map<String, _ConversationReconcileFailure>
  _conversationReconcileFailures = <String, _ConversationReconcileFailure>{};
  final Map<String, Future<int?>> _conversationReconcileTasks =
      <String, Future<int?>>{};
  final Set<String> _conversationRefreshInFlight = <String>{};
  Timer? _pollTimer;
  StreamSubscription<DingTalkGatewayEvent>? _eventSubscription;
  Future<void>? _eventRestartFuture;
  Future<void>? _periodicReconcileFuture;
  Future<void>? _pollingStopInFlight;
  Future<void>? _persistInFlight;
  Future<void>? _shutdownInFlight;
  bool _persistQueued = false;
  Object? _persistenceError;
  bool _pollInFlight = false;
  bool _usingPollingFallback = false;
  bool _responseSchedulingQueued = false;
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
  int _responseSequence = 0;
  int _unreadCount = 0;
  String? _errorMessage;
  String? _warningMessage;
  String? _deviceUrl;
  DingTalkAuthStatus _authStatus = const DingTalkAuthStatus(
    authenticated: false,
  );
  DingTalkGatewaySettings _settings = const DingTalkGatewaySettings();
  DateTime _lastPollAt = DateTime.now().subtract(_queryWindow);
  DateTime? _pollStartedAt;
  int _pollingGeneration = 0;
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

  DingTalkConversationResponseState conversationResponseState(
    String conversationId,
  ) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return DingTalkConversationResponseState.idle;
    final sessionId = _conversations[normalizedId]?.aiSessionId;
    final phase = _sessionController.sendPhaseForSession(sessionId);
    if (phase == AiSendPhase.awaitingApproval) {
      return DingTalkConversationResponseState.awaitingApproval;
    }
    if (isConversationResponding(normalizedId)) {
      return DingTalkConversationResponseState.active;
    }
    if (_responseErrors[normalizedId]?.trim().isNotEmpty ?? false) {
      return DingTalkConversationResponseState.failed;
    }
    return DingTalkConversationResponseState.idle;
  }

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
  ValueListenable<int> get runtimeLogListenable => _runtimeLogRevision;

  void clearRuntimeLogs() {
    if (_disposed || _shutdownRequested) return;
    _service.clearRuntimeLogs();
    _runtimeLogRevision.value = _service.runtimeLogRevision;
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
      'cancelled': result.cancelled,
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
    String fallback = kApplicationOctetStreamMimeType,
  }) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => kImagePngMimeType,
      '.jpg' || '.jpeg' => kImageJpegMimeType,
      '.webp' => kImageWebpMimeType,
      '.gif' => kImageGifMimeType,
      '.mp4' => kVideoMp4MimeType,
      '.mov' => kVideoQuickTimeMimeType,
      '.webm' => kVideoWebmMimeType,
      '.wav' => kAudioWavMimeType,
      '.m4a' => 'audio/mp4',
      '.ogg' => kAudioOggMimeType,
      '.aac' => kAudioAacMimeType,
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
    final keyword = query.trim();
    if (_disposed || _shutdownRequested || !isAuthorized || keyword.isEmpty) {
      return const <DingTalkConversationTarget>[];
    }
    final key = '${type.name}:${keyword.toLowerCase()}';
    final cached = _targetSearchCache[key];
    if (cached != null) {
      final age = DateTime.now().difference(cached.$1);
      if (!age.isNegative && age < _targetSearchCacheTtl) return cached.$2;
      _targetSearchCache.remove(key);
    }
    try {
      return await _targetSearchFlights.run(key, () async {
        if (_disposed || _shutdownRequested || !isAuthorized) {
          return const <DingTalkConversationTarget>[];
        }
        final results = List<DingTalkConversationTarget>.unmodifiable(
          await _service.searchTargets(type: type, query: keyword),
        );
        if (_disposed || _shutdownRequested) {
          return const <DingTalkConversationTarget>[];
        }
        _targetSearchCache[key] = (DateTime.now(), results);
        while (_targetSearchCache.length > _targetSearchCacheMaxEntries) {
          _targetSearchCache.remove(_targetSearchCache.keys.first);
        }
        return results;
      });
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '搜索钉钉会话', error, stack);
      return const <DingTalkConversationTarget>[];
    }
  }

  void openConversation(DingTalkConversationTarget target) {
    if (_conversations.containsKey(target.id)) return;
    final conversation = DingTalkConversation(
      id: target.id,
      type: target.type,
      title: target.title,
      directUserId: target.userId.trim().isEmpty ? null : target.userId.trim(),
      directOpenDingTalkId: target.openDingTalkId.trim().isEmpty
          ? null
          : target.openDingTalkId.trim(),
    );
    _conversations[target.id] = conversation;
    _queuePersist();
    _notify();
    unawaited(_loadInitialConversationMessages(conversation));
    if (_isPolling && !_usingPollingFallback && _eventSubscription != null) {
      unawaited(_restartEventListening());
    }
  }

  Future<void> _loadInitialConversationMessages(
    DingTalkConversation conversation,
  ) async {
    if (_disposed || !isAuthorized) return;
    if (!_conversationRefreshInFlight.add(conversation.id)) return;
    _notify();
    try {
      final page = await _service.queryConversationPage(
        conversation: conversation,
        limit: _initialConversationHistoryMessageLimit,
      );
      if (_disposed ||
          !identical(_conversations[conversation.id], conversation)) {
        return;
      }
      final initialMessages =
          page.messages.length <= _initialConversationHistoryMessageLimit
          ? page.messages
          : page.messages.sublist(
              page.messages.length - _initialConversationHistoryMessageLimit,
            );
      _ingestReconciledMessages(
        conversation,
        initialMessages,
        allowResponses: false,
      );
      final state = _conversationHistoryStates.putIfAbsent(
        conversation.id,
        _DingTalkConversationHistoryState.new,
      );
      // 首次建会话只导入最近 20 条已有消息，后续新消息不受此上限影响。
      state
        ..hasMore = false
        ..initialized = true;
    } catch (error, stack) {
      if (!_disposed) {
        _setError('同步钉钉新会话历史消息', error, stack);
      }
    } finally {
      _conversationRefreshInFlight.remove(conversation.id);
      _notify();
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
    _conversationRefreshInFlight.remove(conversationId);
    _pendingInitialContextHydration.remove(conversationId);
    if (!_activeResponseConversationIds.contains(conversationId) &&
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

  bool isRefreshingConversationMessages(String conversationId) =>
      _conversationRefreshInFlight.contains(conversationId.trim());

  Future<int?> refreshConversationMessages(String conversationId) async {
    final normalizedId = conversationId.trim();
    final conversation = _conversations[normalizedId];
    if (conversation == null || _disposed) return null;
    if (!isAuthorized || !_isPolling) {
      _errorMessage = '钉钉消息监听尚未启动，无法刷新当前会话。';
      _notify();
      return null;
    }
    if (!_conversationRefreshInFlight.add(normalizedId)) return 0;
    _clearError();
    _notify();
    try {
      final addedCount = await _reconcileConversationNow(
        conversation,
        force: true,
      );
      if (addedCount != null) {
        _nextConversationReconcileAt = DateTime.now().add(
          _conversationReconcileInterval,
        );
        _clearError();
      }
      return addedCount;
    } finally {
      _conversationRefreshInFlight.remove(normalizedId);
      _notify();
    }
  }

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
    bool forceRetry = false,
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
    if (forceRetry) _mediaHydrationFailures.remove(taskKey);
    final task = (() async {
      try {
        final hydrated = await _hydrateMessageMedia(
          conversation,
          message,
          forceRetry: forceRetry,
        );
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
    DingTalkGatewayMessage message, {
    bool forceRetry = false,
  }) async {
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
      final path = await _service.ensureMediaCached(
        item,
        forceRetry: forceRetry,
      );
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

  bool setMessageAiContextIgnored(
    String conversationId,
    String messageId,
    bool ignored,
  ) {
    final conversation = _conversations[conversationId];
    if (conversation == null) return false;
    final normalizedMessageId = messageId.trim();
    final index = conversation.messages.indexWhere(
      (message) => message.id == normalizedMessageId,
    );
    if (index < 0) return false;
    final current = conversation.messages[index];
    if (current.isAssistant || current.recalled) return false;
    if (current.ignoredForAiContext == ignored) return true;
    conversation.messages[index] = current.copyWith(
      ignoredForAiContext: ignored,
    );
    _queuePersist();
    _clearError();
    _notify();
    if (ignored) {
      _cancelResponseUsingExcludedMessage(conversationId, normalizedMessageId);
    }
    return true;
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
      final repairedEchoContent = await _restorePersistedAiEchoContent();
      await refreshAuthStatus();
      var repairedOutgoingEchoes = false;
      for (final conversation in _conversations.values) {
        repairedOutgoingEchoes =
            _collapseOutgoingEchoDuplicates(conversation) > 0 ||
            repairedOutgoingEchoes;
      }
      if (repairedEchoContent || repairedOutgoingEchoes) _queuePersist();
    } catch (error, stack) {
      _setError('初始化钉钉消息网关', error, stack);
    } finally {
      _initialized = true;
      _notify();
    }
  }

  Future<bool> _restorePersistedAiEchoContent() async {
    final candidates =
        <
          ({
            DingTalkConversation conversation,
            AiSession session,
            int messageIndex,
            DingTalkGatewayMessage message,
            AiSessionMessage? source,
          })
        >[];
    for (final conversation in _conversations.values) {
      final session = _aiSessionForConversation(conversation);
      if (session == null) continue;
      for (var index = 0; index < conversation.messages.length; index++) {
        final message = conversation.messages[index];
        final sourceId = message.sourceAiMessageId.trim();
        if (sourceId.isEmpty || !message.isAssistant) continue;
        AiSessionMessage? source;
        for (final candidate in session.messages) {
          if (candidate.id == sourceId) {
            source = candidate;
            break;
          }
        }
        if (source?.kind == AiSessionMessageKind.toolCall ||
            source?.kind == AiSessionMessageKind.hook) {
          continue;
        }
        candidates.add((
          conversation: conversation,
          session: session,
          messageIndex: index,
          message: message,
          source: source,
        ));
      }
    }
    final results = await runOrderedWithConcurrencyLimit<bool>(
      itemCount: candidates.length,
      maxConcurrency: _echoRestoreConcurrency,
      task: (index) async {
        final candidate = candidates[index];
        var source = candidate.source;
        try {
          source ??= await _sessionController.store.loadMessage(
            candidate.session.id,
            candidate.message.sourceAiMessageId,
          );
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '恢复钉钉 AI 回显正文', error, stack);
          return false;
        }
        if (source == null ||
            source.kind == AiSessionMessageKind.toolCall ||
            source.kind == AiSessionMessageKind.hook) {
          return false;
        }
        final sourceContent = _echoTextForMessage(
          source,
          candidate.session.messages,
        ).trim();
        final responseEchoType = source.kind == AiSessionMessageKind.reasoning
            ? DingTalkResponseEchoType.thinking
            : candidate.message.responseEchoType;
        if (sourceContent.isEmpty ||
            sourceContent == candidate.message.content &&
                responseEchoType == candidate.message.responseEchoType) {
          return false;
        }
        candidate.conversation.messages[candidate.messageIndex] = candidate
            .message
            .copyWith(
              content: sourceContent,
              responseEchoType: responseEchoType,
            );
        return true;
      },
    );
    return results.any((changed) => changed);
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
    _scheduleResponseWorkers();
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
    if (jsonEncode(normalized.toJson()) != jsonEncode(_settings.toJson())) {
      _settings = normalized;
      _queuePersist();
      final task = _persistInFlight;
      if (task != null) await task;
    }
    _notify();
  }

  Future<void> startPolling() async {
    if (_isPolling || !isAuthorized) return;
    final stopping = _pollingStopInFlight;
    if (stopping != null) await stopping;
    if (_isPolling || !isAuthorized || _disposed) return;
    final startedAt = DateTime.now();
    _isPolling = true;
    _pollStartedAt = startedAt;
    _pollingGeneration++;
    _service.resetMessageQueryCapability();
    _usingPollingFallback = false;
    _warningMessage = null;
    _lastPollAt = startedAt;
    _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
    _conversationReconcileCursor = 0;
    _conversationReconcileFailures.clear();
    _schedulePolling(immediate: true);
    _notify();
    unawaited(_startEventListening(_pollingGeneration));
  }

  Future<void> stopPolling() {
    final active = _pollingStopInFlight;
    if (active != null) return active;
    _isPolling = false;
    _pollStartedAt = null;
    _pollingGeneration++;
    final pollingGeneration = _pollingGeneration;
    final cancelAutomaticResponses = _cancelObsoleteAutomaticResponses();
    _usingPollingFallback = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
    _conversationReconcileCursor = 0;
    _conversationReconcileFailures.clear();
    _pendingRecalledMessageIds.clear();
    _pendingStatusEvents.clear();
    _pendingInitialContextHydration.clear();
    _unresolvedOutgoingMessageIds.clear();
    _notify();
    late final Future<void> task;
    task =
        Future.wait<void>(<Future<void>>[
          _stopEventListening(pollingGeneration: pollingGeneration),
          cancelAutomaticResponses,
        ]).whenComplete(() {
          if (identical(_pollingStopInFlight, task)) {
            _pollingStopInFlight = null;
          }
        });
    _pollingStopInFlight = task;
    return task;
  }

  bool forceRespondToConversation(String conversationId) {
    final conversation = _conversations[conversationId];
    if (conversation == null ||
        _disposed ||
        !isAuthorized ||
        _isSending ||
        _editingMessageInFlight ||
        isConversationResponding(conversationId)) {
      return false;
    }
    final source = conversation.messages.reversed
        .where(
          (message) =>
              !message.isAssistant &&
              !message.isExcludedFromAiContext &&
              _messageAiContextContent(message).isNotEmpty,
        )
        .firstOrNull;
    // 手动强制响应不受自动响应的白名单与群聊 @ 条件限制。
    if (source == null) return false;
    final responseVersion = _responseCancellationVersions[conversationId] ?? 0;
    unawaited(
      _enqueueAiResponse(
        conversation,
        _messageAiContextContent(source),
        sourceMessageId: source.id,
        responseVersion: responseVersion,
        forceResponse: true,
      ),
    );
    return true;
  }

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
        _rememberUnresolvedOutgoingMessage(localMessage.id);
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
        _rememberUnresolvedOutgoingMessage(localMessage.id);
        _appendMessage(conversation, localMessage);
        _notify();
        final sentAt = localMessage.createdAt;
        final sent = await _sendDingTalkTextWithResolvedId(
          conversation: conversation,
          text: content,
          uuid: _uuid.v4(),
          createdAt: sentAt,
          senderName: localMessage.senderName,
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
    _rememberUnresolvedOutgoingMessage(message.id);
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
    // 流式回显期间本地内容领先于远端（编辑节流 + 同步延迟），
    // 保留本地权威文本避免回退闪烁；远端稍后会被编辑追平。
    final keepLocalContent =
        remote.content.isEmpty ||
        isEchoStreaming(local) ||
        local.sourceAiMessageId.trim().isNotEmpty;
    return local.copyWith(
      id: remoteId,
      content: keepLocalContent ? null : remote.content,
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
    if (id.isEmpty) {
      if (outgoingIndex >= 0) return outgoing;
      for (final candidate in conversation.messages) {
        if (candidate.fromSelf &&
            candidate.role == localMessage.role &&
            candidate.createdAt == localMessage.createdAt &&
            normalizeDingTalkMessageContentForComparison(candidate.content) ==
                normalizeDingTalkMessageContentForComparison(
                  localMessage.content,
                )) {
          return candidate;
        }
      }
      return outgoing;
    }
    _unresolvedOutgoingMessageIds.remove(outgoing.id);
    if (id == outgoing.id) return outgoing;
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
    final pollingGeneration = _pollingGeneration;
    _pollInFlight = true;
    try {
      final now = DateTime.now();
      final queryStart = _lastPollAt.isBefore(now)
          ? _lastPollAt
          : now.subtract(const Duration(seconds: 2));
      final maxQueryEnd = queryStart.add(_queryWindow);
      final queryEnd = maxQueryEnd.isBefore(now) ? maxQueryEnd : now;
      Object? queryError;
      try {
        final result = await _service.query(start: queryStart, end: queryEnd);
        if (pollingGeneration != _pollingGeneration || !_isPolling) return;
        if (result.shouldAdvanceWindow) {
          _lastPollAt = queryEnd.subtract(const Duration(seconds: 2));
        }
        _warningMessage = result.warning;
        for (final message in result.messages) {
          _handleIncomingMessage(message);
        }
      } catch (error, stack) {
        if (pollingGeneration != _pollingGeneration || !_isPolling) return;
        queryError = error;
        final transientFailure =
            error is TimeoutException ||
            error is DingTalkGatewayCommandException && error.isRetryable;
        if (transientFailure) {
          _warningMessage = '钉钉消息同步较慢，已跳过本轮，下一轮将继续重试。';
          _clearError();
        } else {
          _setError('轮询钉钉消息', error, stack);
        }
      }
      if (pollingGeneration != _pollingGeneration || !_isPolling) return;
      if (!now.isBefore(_nextConversationReconcileAt)) {
        _nextConversationReconcileAt = now.add(_conversationReconcileInterval);
        _scheduleRecentConversationReconcile();
      }
      if (queryError == null) {
        _clearError();
      } else if (queryError is! TimeoutException &&
          (queryError is! DingTalkGatewayCommandException ||
              !queryError.isRetryable)) {
        await refreshAuthStatus();
        if (!isAuthorized) await stopPolling();
      }
    } finally {
      _pollInFlight = false;
      if (!_disposed && _isPolling && pollingGeneration != _pollingGeneration) {
        unawaited(_pollOnce());
      }
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
    await forEachIndexWithConcurrencyLimit(
      itemCount: batch.length,
      maxConcurrency: _conversationReconcileConcurrency,
      shouldContinue: () => !_disposed && _isPolling,
      task: (index) async {
        final conversation = batch[index];
        if (!identical(_conversations[conversation.id], conversation)) return;
        if (_conversationRefreshInFlight.contains(conversation.id) ||
            _conversationReconcileTasks.containsKey(conversation.id)) {
          return;
        }
        final failure = _conversationReconcileFailures[conversation.id];
        if (failure != null && DateTime.now().isBefore(failure.retryAt)) {
          return;
        }
        await _reconcileConversationNow(conversation);
      },
    );
  }

  Future<void> _startEventListening(int pollingGeneration) async {
    try {
      final stream = await _service.startEventSubscription(
        targets: _eventSubscriptionTargets(),
      );
      if (!_isPolling || _disposed || pollingGeneration != _pollingGeneration) {
        return;
      }
      _eventSubscription = stream.listen(
        (event) {
          if (pollingGeneration == _pollingGeneration) {
            _handleIncomingEvent(event);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (pollingGeneration != _pollingGeneration) return;
          silentLog('dingtalk_gateway', '实时事件监听异常', error, stack);
          if (_eventRestartFuture == null) {
            unawaited(_fallbackToPolling());
          }
        },
        onDone: () {
          if (pollingGeneration != _pollingGeneration) return;
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
      if (!_isPolling || _disposed || pollingGeneration != _pollingGeneration) {
        return;
      }
      silentLog('dingtalk_gateway', '启动实时事件监听', error, stack);
      await _fallbackToPolling();
    }
  }

  Future<void> _fallbackToPolling() async {
    if (!_isPolling || _disposed || _usingPollingFallback) return;
    final pollingGeneration = _pollingGeneration;
    _usingPollingFallback = true;
    await _stopEventListening(pollingGeneration: pollingGeneration);
    if (!_isPolling || _disposed || pollingGeneration != _pollingGeneration) {
      return;
    }
    _warningMessage = '实时事件监听暂不可用，已启用有界轮询兜底。';
    _clearError();
    _schedulePolling(immediate: true);
    _notify();
  }

  Future<void> _restartEventListening() {
    final active = _eventRestartFuture;
    if (active != null) return active;
    final pollingGeneration = _pollingGeneration;
    final task = () async {
      await _stopEventListening(pollingGeneration: pollingGeneration);
      if (_isPolling &&
          !_usingPollingFallback &&
          !_disposed &&
          pollingGeneration == _pollingGeneration) {
        await _startEventListening(pollingGeneration);
      }
    }();
    _eventRestartFuture = task;
    return task.whenComplete(() {
      if (identical(_eventRestartFuture, task)) _eventRestartFuture = null;
    });
  }

  Future<void> _stopEventListening({int? pollingGeneration}) async {
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
    if (pollingGeneration != null && pollingGeneration != _pollingGeneration) {
      return;
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
    final incomingContentComparison =
        normalizeDingTalkMessageContentForComparison(incomingContent);
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
          local.conversationType != incoming.conversationType) {
        continue;
      }
      final localSenderId = local.senderId.trim();
      final localSenderName = local.senderName.trim();
      final senderNamesMatch =
          incomingSenderName.isNotEmpty &&
          localSenderName.isNotEmpty &&
          _sameIdentityName(incomingSenderName, localSenderName);
      final unresolvedOutgoing = _unresolvedOutgoingMessageIds.contains(
        local.id,
      );
      if (!incomingIsSelf &&
          !unresolvedOutgoing &&
          (local.isAssistant ||
              directPeerIds.contains(incomingSenderId) ||
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
          incomingContentComparison.isNotEmpty &&
          (normalizeDingTalkMessageContentForComparison(local.content) ==
                  incomingContentComparison ||
              local.sourceAiMessageId.trim().isNotEmpty &&
                  normalizeDingTalkMessageContentForComparison(
                        _dingTalkRemoteEchoText(local.content),
                      ) ==
                      incomingContentComparison);
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
    _unresolvedOutgoingMessageIds.remove(local.id);
    if (incomingSenderId.isNotEmpty) _selfSenderIds.add(incomingSenderId);
    _remember(incomingId);
    _queuePersist();
    return true;
  }

  int _collapseOutgoingEchoDuplicates(DingTalkConversation conversation) {
    final localIds = conversation.messages
        .where(
          (message) =>
              message.fromSelf &&
              (_isTemporaryMessageId(message.id) ||
                  message.sourceAiMessageId.trim().isNotEmpty),
        )
        .map((message) => message.id)
        .toList(growable: false);
    var removedCount = 0;
    for (final localId in localIds) {
      final localIndex = conversation.messages.indexWhere(
        (message) => message.id == localId,
      );
      if (localIndex < 0) continue;
      final local = conversation.messages[localIndex];
      final localContentComparison =
          normalizeDingTalkMessageContentForComparison(local.content);
      var remoteIndex = -1;
      Duration? closestAge;
      for (final entry in conversation.messages.asMap().entries) {
        final remote = entry.value;
        if (entry.key == localIndex ||
            remote.isAssistant ||
            !_isSelf(remote) ||
            _isTemporaryMessageId(remote.id) ||
            remote.conversationType != local.conversationType) {
          continue;
        }
        final age = remote.createdAt.difference(local.createdAt).abs();
        if (age > _outgoingEchoWindow) continue;
        final remoteContentComparison =
            normalizeDingTalkMessageContentForComparison(remote.content);
        final sameContent =
            remoteContentComparison.isNotEmpty &&
            remoteContentComparison == localContentComparison;
        if (!sameContent &&
            !_outgoingMediaMatches(local.media, remote.media, remote.content)) {
          continue;
        }
        if (closestAge == null || age < closestAge) {
          remoteIndex = entry.key;
          closestAge = age;
        }
      }
      if (remoteIndex < 0) continue;
      final remote = conversation.messages[remoteIndex];
      final merged = _mergeOutgoingMessage(local, remote, remote.id);
      if (remoteIndex > localIndex) {
        conversation.messages[localIndex] = merged;
        conversation.messages.removeAt(remoteIndex);
      } else {
        conversation.messages.removeAt(remoteIndex);
        conversation.messages[localIndex - 1] = merged;
      }
      _unresolvedOutgoingMessageIds.remove(local.id);
      _remember(remote.id);
      removedCount++;
    }
    return removedCount;
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
    if (_disposed || (!_isPolling && !allowHistorical)) return;
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
          _isAutomaticResponseEligible(incoming) &&
          _canAutomaticallyRespondToMessage(incoming)) {
        _enqueueIncomingMessage(existingConversation, incoming);
      }
      return;
    }
    final localConversation = _conversationForIncomingMessage(incoming);
    final allowedTarget = _targetForIncomingMessage(
      incoming,
      localConversation,
    );
    if (allowedTarget == null) return;
    final shouldRespond = _shouldAutomaticallyRespondToMessage(
      incoming,
      allowResponse: allowResponse,
    );
    // 同一条群消息可能先从全量查询进入，再从 @我查询补齐标记。
    // 触发条件成立时允许穿透全局去重，避免漏建会话。
    if (_seenMessageIds.contains(messageId) &&
        localConversation == null &&
        !shouldRespond) {
      return;
    }
    // 未打开的会话只由启动后的有效响应消息创建；普通群消息不污染左侧列表。
    if (localConversation == null && !shouldRespond) {
      _remember(messageId);
      return;
    }
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
    final createdConversation = localConversation == null;
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
    if (createdConversation) {
      _pendingInitialContextHydration.add(conversation.id);
    }
    _applyPendingStatusEvents(conversation, messageId);
    if (allowResponse) {
      _unreadCount += 1;
      if (_settings.reminderMode == DingTalkReminderMode.sound) {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
    }
    if (!allowHistorical && incoming.media.isNotEmpty && !shouldRespond) {
      unawaited(_cacheIncomingMedia(conversation, incoming));
    }
    if (shouldRespond) {
      _enqueueIncomingMessage(conversation, incoming);
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
    // 流式回显期间远端内容滞后于本地，跳过覆盖以免回退闪烁并污染编辑历史。
    final contentChanged =
        remote.content.isNotEmpty &&
        !isEchoStreaming(current) &&
        current.sourceAiMessageId.trim().isEmpty &&
        normalizeDingTalkMessageContentForComparison(remote.content) !=
            normalizeDingTalkMessageContentForComparison(current.content);
    final recalledChanged = remote.recalled && !current.recalled;
    final mediaChanged =
        remote.media.isNotEmpty && !_sameMedia(current.media, remote.media);
    final forwardedMessagesChanged =
        remote.forwardedMessages.isNotEmpty &&
        (remote.forwardedMessageCount != current.forwardedMessageCount ||
            !_sameForwardedMessages(
              current.forwardedMessages,
              remote.forwardedMessages,
            ));
    final mentionChanged =
        remote.mentionedCurrentUser && !current.mentionedCurrentUser;
    final readChanged = remote.readByPeer && !current.readByPeer;
    final reactionsChanged =
        remote.reactions.isNotEmpty &&
        !listEquals(remote.reactions, current.reactions);
    if (!contentChanged &&
        !recalledChanged &&
        !mediaChanged &&
        !forwardedMessagesChanged &&
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
      forwardedMessages: forwardedMessagesChanged
          ? remote.forwardedMessages
          : null,
      forwardedMessageCount: forwardedMessagesChanged
          ? remote.forwardedMessageCount
          : null,
      mentionedCurrentUser: mentionChanged ? true : null,
      readByPeer: readChanged ? true : null,
      recalled: recalledChanged ? true : null,
      reactions: reactionsChanged ? remote.reactions : null,
      editHistory: history,
    );
    _queuePersist();
    _notify();
    if (recalledChanged) {
      _cancelResponseUsingExcludedMessage(conversation.id, remoteId);
    }
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

  bool _sameForwardedMessages(
    List<DingTalkForwardedMessage> left,
    List<DingTalkForwardedMessage> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (normalizeDingTalkMessageId(a.id) !=
              normalizeDingTalkMessageId(b.id) ||
          a.senderId != b.senderId ||
          a.senderName != b.senderName ||
          a.createdAt != b.createdAt ||
          normalizeDingTalkMessageContentForComparison(a.content) !=
              normalizeDingTalkMessageContentForComparison(b.content) ||
          !_sameMedia(a.media, b.media)) {
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
      if (message != null) {
        _handleIncomingMessage(message);
        return;
      }
      final eventMessageId = normalizeDingTalkMessageId(event.messageId);
      if (eventMessageId.isEmpty) return;
      final conversation = _conversationForEvent(event);
      _nextConversationReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
      if (conversation == null) {
        _reconcileConversationsForEvent(event);
      } else {
        unawaited(_reconcileAndApplyEvent(conversation, event, eventMessageId));
      }
      unawaited(_pollOnce());
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
    if (event.type == DingTalkGatewayEventType.recall) {
      _cancelResponseUsingExcludedMessage(conversation.id, eventMessageId);
    }
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

  Future<int?> _reconcileConversationNow(
    DingTalkConversation conversation, {
    bool force = false,
    bool allowResponses = true,
    bool reportError = true,
    DateTime? before,
    bool allowHistoricalBackfill = false,
  }) async {
    if (_disposed || !_isPolling) return null;
    if (force) {
      final active = _conversationReconcileTasks[conversation.id];
      if (active != null) {
        await active;
        if (identical(_conversationReconcileTasks[conversation.id], active)) {
          _conversationReconcileTasks.remove(conversation.id);
        }
      }
      if (_disposed ||
          !_isPolling ||
          !identical(_conversations[conversation.id], conversation)) {
        return null;
      }
    }
    final active = _conversationReconcileTasks[conversation.id];
    if (active != null) return active;
    final failure = _conversationReconcileFailures[conversation.id];
    if (!force && failure != null && DateTime.now().isBefore(failure.retryAt)) {
      return null;
    }
    final task = () async {
      try {
        final page = await _queryRecentConversation(
          conversation,
          before: before,
        );
        if (_disposed ||
            !_isPolling ||
            !identical(_conversations[conversation.id], conversation)) {
          return null;
        }
        _conversationReconcileFailures.remove(conversation.id);
        final state = _conversationHistoryStates.putIfAbsent(
          conversation.id,
          _DingTalkConversationHistoryState.new,
        );
        if (!state.initialized) state.hasMore = page.hasMore;
        state.initialized = true;
        return _ingestReconciledMessages(
          conversation,
          page.messages,
          allowResponses: allowResponses,
          historicalMessageFloor: allowHistoricalBackfill
              ? null
              : conversation.createdAt.subtract(_conversationStartSkew),
        );
      } catch (error, stack) {
        if (_disposed || !_isPolling) return null;
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
        if (force && reportError) {
          _setError('刷新当前钉钉会话', error, stack);
        } else if (shouldLog) {
          silentLog('dingtalk_gateway', '对账钉钉会话消息', error, stack);
        }
        return null;
      }
    }();
    _conversationReconcileTasks[conversation.id] = task;
    try {
      return await task;
    } finally {
      if (identical(_conversationReconcileTasks[conversation.id], task)) {
        _conversationReconcileTasks.remove(conversation.id);
      }
    }
  }

  int _ingestReconciledMessages(
    DingTalkConversation conversation,
    List<DingTalkGatewayMessage> messages, {
    bool allowResponses = true,
    DateTime? historicalMessageFloor,
  }) {
    final initialMessageCount = conversation.messages.length;
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
    for (final message in messages) {
      final messageId = normalizeDingTalkMessageId(message.id);
      final isNew = messageId.isNotEmpty && !knownIds.contains(messageId);
      if (isNew &&
          historicalMessageFloor != null &&
          message.createdAt.isBefore(historicalMessageFloor)) {
        continue;
      }
      _handleIncomingMessage(
        message,
        allowResponse:
            allowResponses &&
            (!isNew || !message.createdAt.isBefore(recentCutoff)),
        allowHistorical: true,
      );
    }
    if (_collapseOutgoingEchoDuplicates(conversation) > 0) {
      _queuePersist();
      _notify();
    }
    return math.max(0, conversation.messages.length - initialMessageCount);
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

  void _enqueueIncomingMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    final pollingGeneration = _pollingGeneration;
    if (!_isAutomaticResponseEligible(message, pollingGeneration)) return;
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    if (_disposed) return;
    unawaited(
      _enqueueAiResponse(
        conversation,
        _messageAiContextContent(message),
        sourceMessageId: message.id,
        responseVersion: responseVersion,
        automaticResponse: true,
        pollingGeneration: pollingGeneration,
      ),
    );
  }

  Future<void> _ensureIncomingContextMedia(
    DingTalkConversation conversation,
    String sourceMessageId, {
    bool forceResponse = false,
  }) async {
    final sourceIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (sourceIndex < 0) return;
    final startIndex = _conversationTurnStartIndex(
      conversation,
      sourceIndex,
      forceResponse: forceResponse,
    );
    final candidates = <DingTalkGatewayMessage>[];
    for (var index = sourceIndex; index >= startIndex; index--) {
      final message = conversation.messages[index];
      if (message.isAssistant ||
          message.isExcludedFromAiContext ||
          message.media.isEmpty) {
        continue;
      }
      candidates.add(message);
      if (candidates.length >= 6) break;
    }
    if (candidates.isEmpty) return;
    try {
      await forEachIndexWithConcurrencyLimit(
        itemCount: candidates.length,
        maxConcurrency: _mediaCacheConcurrency,
        shouldContinue: () =>
            !_disposed &&
            identical(_conversations[conversation.id], conversation),
        task: (index) async {
          try {
            await ensureMessageMediaCached(
              conversationId: conversation.id,
              messageId: candidates[index].id,
            );
          } catch (error, stack) {
            silentLog('dingtalk_gateway', '准备钉钉上下文媒体', error, stack);
          }
        },
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

  bool _canAutomaticallyRespondToMessage(DingTalkGatewayMessage message) {
    if (message.isAssistant ||
        message.isExcludedFromAiContext ||
        _configuredTargetFor(message) == null) {
      return false;
    }
    return message.conversationType == DingTalkConversationType.direct ||
        message.mentionedCurrentUser;
  }

  bool _shouldAutomaticallyRespondToMessage(
    DingTalkGatewayMessage message, {
    required bool allowResponse,
  }) {
    return allowResponse &&
        !message.recalled &&
        _canAutomaticallyRespondToMessage(message) &&
        _isAutomaticResponseEligible(message);
  }

  bool _isAutomaticResponseEligible(
    DingTalkGatewayMessage message, [
    int? pollingGeneration,
  ]) {
    final startedAt = _pollStartedAt;
    return _isPolling &&
        startedAt != null &&
        !_isSelf(message) &&
        (pollingGeneration == null ||
            pollingGeneration == _pollingGeneration) &&
        !message.createdAt.isBefore(startedAt);
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
    String sourceMessageId, {
    bool forceResponse = false,
    bool automaticResponse = false,
    int? pollingGeneration,
  }) async {
    final source = conversation.messages
        .where((message) => message.id == sourceMessageId)
        .firstOrNull;
    if (_disposed ||
        (automaticResponse &&
            (source == null ||
                !_isAutomaticResponseEligible(source, pollingGeneration))) ||
        !_responseInFlight.add(conversation.id)) {
      return;
    }
    _activeResponseContextMessageIds[conversation.id] = <String>{
      sourceMessageId,
    };
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    if (automaticResponse) {
      _activeAutomaticResponseGenerations[conversation.id] =
          pollingGeneration ?? _pollingGeneration;
    }
    bool responseCancelled() =>
        _isResponseCancelled(conversation.id, responseVersion) ||
        (automaticResponse &&
            (source == null ||
                !_isAutomaticResponseEligible(source, pollingGeneration)));
    _notify();
    try {
      if (source != null &&
          (source.isAssistant || source.isExcludedFromAiContext)) {
        return;
      }
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
      final resolvedTemplateId = _sessionController.templateRepository
          .resolveTemplate(_settings.templateId)
          .id;
      final templateId =
          templates.any((template) => template.id == resolvedTemplateId)
          ? resolvedTemplateId
          : templates.any((template) => template.id == 'default')
          ? 'default'
          : templates.first.id;
      final aiContent = _buildAiConversationTurn(
        conversation,
        sourceMessageId,
        fallbackContent: content,
        forceResponse: forceResponse,
      );
      if (aiContent.isEmpty) return;
      final contextMessageIds = _pendingAiConversationMessages(
        conversation,
        sourceMessageId,
        forceResponse: forceResponse,
      ).map((message) => message.id).toSet();
      _activeResponseContextMessageIds[conversation.id] = contextMessageIds;
      if (forceResponse) {
        await _ensureIncomingContextMedia(
          conversation,
          sourceMessageId,
          forceResponse: true,
        );
        if (responseCancelled()) return;
      }
      final selectedMemoryIds = _settings.allowedMemoryIds.toSet();
      _workspaceInstructionService.maxDocumentCharacters =
          _settingsController.aiMaxWorkspaceDocumentCharacters;
      final preparedResources = await Future.wait<Object?>(<Future<Object?>>[
        _mcpController
            .ensureRuntimeToolCatalogs(maxWait: const Duration(seconds: 6))
            .then<Object?>((_) => null),
        if (_settingsController.memoryEnabled && selectedMemoryIds.isNotEmpty)
          _memoryController
              .trustedEntriesSnapshot()
              .timeout(const Duration(seconds: 5), onTimeout: () => null)
              .then<Object?>((value) => value)
        else
          Future<Object?>.value(const <UserMemoryEntry>[]),
        if (_settings.allowedDingTalkDwsCommandIds.isEmpty)
          Future<Object?>.value(const <AiDingTalkDwsCommand>[])
        else
          _service.loadDwsCommandCatalog().then<Object?>((value) => value),
        _gitSnapshotService
            .loadSnapshot(workingDirectory: _settings.workingDirectory)
            .then<Object?>((value) => value),
        _workspaceInstructionService
            .loadDocuments(
              startDirectory: _settings.workingDirectory,
              homeDirectory: OpenHandPaths.homeDirectoryPath(),
            )
            .then<Object?>((value) => value),
      ]);
      if (responseCancelled()) return;
      final selectedMcp = _mcpController.runtimeServers
          .where(
            (server) => _settings.allowedMcpServerNames.contains(server.name),
          )
          .toList(growable: false);
      final selectedSkills = _skillsController.skills
          .where((skill) => _settings.allowedSkillNames.contains(skill.name))
          .toList(growable: false);
      final selectedMemory =
          (preparedResources[1] as List<UserMemoryEntry>? ??
                  const <UserMemoryEntry>[])
              .where((entry) => selectedMemoryIds.contains(entry.id))
              .toList(growable: false);
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
      final builtinToolConfigs = _dingtalkBuiltinToolConfigs(
        knowledgeBaseEnabled: selectedKnowledgeSourceIds.isNotEmpty,
      );
      final dwsCatalog = (preparedResources[2] as List<AiDingTalkDwsCommand>)
          .where(
            (command) => _settings.allowedDingTalkDwsCommandIds.contains(
              command.cliPath,
            ),
          )
          .toList(growable: false);
      final repositorySnapshot = preparedResources[3] as AiRepositorySnapshot;
      final workspaceInstructionDocuments =
          preparedResources[4] as List<AiWorkspaceInstructionDocument>;
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
        repositorySnapshot: repositorySnapshot,
        workspaceInstructionDocuments: workspaceInstructionDocuments,
        userInstructions: selectedInstructions,
        templateId: templateId,
        toolExecutionMetadata: <String, Object?>{
          'source': 'dingtalk_gateway',
          'dingtalk_excluded_message_ids': conversation.messages
              .where((message) => message.isExcludedFromAiContext)
              .map((message) => message.id)
              .toList(growable: false),
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
      final existingSession = sessionId == null
          ? null
          : _sessionController.sessionById(sessionId);
      if (existingSession == null || existingSession.templateId != templateId) {
        sessionId = null;
        conversation.aiSessionId = null;
        conversation.aiContextCheckpointMessageId = null;
      }
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
              candidate.templateId == templateId &&
              candidate.metadata['dingtalk_conversation_id'] ==
                  conversation.id) {
            sessionId = candidate.id;
            break;
          }
        }
        conversation.aiSessionId = sessionId;
        if (responseCancelled()) return;
      }
      if (sessionId == null) {
        _setResponseError(conversation.id, '未能建立钉钉 AI 会话，请查看运行日志。');
        return;
      }
      final attachmentPaths = _attachmentPathsForTurn(
        conversation,
        sourceMessageId,
        forceResponse: forceResponse,
      );
      await _sessionController.updateSessionFullAccessPermission(
        sessionId,
        _settings.fullAccessPermission,
      );
      if (responseCancelled()) return;
      final responseRoundId = _uuid.v4();
      final deliveredSourceMessageIds = conversation.messages
          .map((message) => message.sourceAiMessageId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final echoCoordinator = _DingTalkEchoCoordinator(
        responseRoundId: responseRoundId,
        deliveredSourceMessageIds: deliveredSourceMessageIds,
        selectedTypes: _settings.responseEchoTypes.toSet(),
        typeOf: _echoTypeOf,
        textFor: _echoTextForMessage,
        isTerminal: _isEchoTerminal,
        isCancelled: responseCancelled,
        send: (source, type, text, uuid) => _sendDingTalkEcho(
          conversation: conversation,
          source: source,
          type: type,
          text: text,
          uuid: uuid,
        ),
        edit: (sourceMessageId, messageId, text) => _editDingTalkEcho(
          conversation: conversation,
          sourceMessageId: sourceMessageId,
          messageId: messageId,
          text: text,
        ),
        resolveRemoteId: (sourceMessageId, sentText) =>
            _resolveEchoRemoteMessageId(
              conversation: conversation,
              sourceMessageId: sourceMessageId,
              sentText: sentText,
            ),
        syncLocal: (sourceMessageId, text) => _syncLocalEchoContent(
          conversation: conversation,
          sourceMessageId: sourceMessageId,
          text: text,
        ),
        markStreaming: _setEchoStreaming,
        newUuid: _uuid.v4,
        onError: (action, error, stack, {required bool notifyUser}) {
          silentLog('dingtalk_gateway', action, error, stack);
          if (notifyUser) {
            _setResponseError(conversation.id, '$action失败，请查看钉钉网关运行日志。');
          }
        },
      );

      AiSession? currentSession() {
        for (final item in _sessionController.sessions) {
          if (item.id == sessionId) return item;
        }
        return null;
      }

      var visiblePhase = _sessionController.sendPhaseForSession(sessionId);
      void onSessionChanged() {
        if (responseCancelled()) return;
        final nextPhase = _sessionController.sendPhaseForSession(sessionId);
        if (nextPhase != visiblePhase) {
          visiblePhase = nextPhase;
          _notify();
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
        if (responseCancelled()) return;
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
          additionalSystemReminders: <String>[
            forceResponse
                ? _forcedResponseReminder
                : !automaticResponse
                ? _standardResponseReminder
                : conversation.type == DingTalkConversationType.direct
                ? _directResponseReminder
                : _groupResponseReminder,
          ],
          userMessageMetadata: <String, Object?>{
            'sent_via': 'dingtalk_gateway',
            _dingTalkResponseRoundIdMetadataKey: responseRoundId,
            if (forceResponse) 'dingtalk_force_response': true,
            'dingtalk_source_message_id': sourceMessageId,
            'dingtalk_context_message_ids': contextMessageIds.toList(
              growable: false,
            ),
          },
        );
        if (!sent) {
          if (!responseCancelled()) {
            _setResponseError(
              conversation.id,
              _sessionController.lastErrorMessageForSession(sessionId) ??
                  'AI 未返回响应，请检查模型配置与运行日志。',
            );
          }
          return;
        }
        if (responseCancelled()) return;
        if (sourceMessageId.trim().isNotEmpty &&
            identical(_conversations[conversation.id], conversation)) {
          conversation.aiContextCheckpointMessageId = sourceMessageId.trim();
          _queuePersist();
        }
      } finally {
        _sessionController.removeListener(onSessionChanged);
        if (!responseCancelled()) {
          // 请求失败时同样收敛：已流式发出的消息应停留在最后已生成内容，
          // 避免钉钉端留下与本地不一致的半途文本。
          final session = currentSession();
          if (session != null) echoCoordinator.complete(session);
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
      if (!responseCancelled()) {
        _setResponseError(conversation.id, 'AI 响应失败，请查看钉钉网关运行日志。');
      }
      silentLog('dingtalk_gateway', '生成钉钉 AI 回复', error, stack);
    } finally {
      _responseInFlight.remove(conversation.id);
      _activeResponseContextMessageIds.remove(conversation.id);
      if (automaticResponse) {
        _activeAutomaticResponseGenerations.remove(conversation.id);
      }
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
    bool forceResponse = false,
  }) {
    final sourceIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (sourceIndex < 0) return '';
    final source = conversation.messages[sourceIndex];
    if (source.isAssistant || source.isExcludedFromAiContext) {
      return '';
    }
    final pending = _pendingAiConversationMessages(
      conversation,
      sourceMessageId,
      forceResponse: forceResponse,
    );
    if (pending.isEmpty) return fallbackContent.trim();
    if (!forceResponse &&
        pending.length == 1 &&
        pending.single.id == sourceMessageId) {
      return _messageAiContextContent(pending.single);
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
      final body = _messageAiContextContent(message);
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
    final buffer = StringBuffer()..writeln('钉钉会话消息（按时间顺序）：');
    if (omitted > 0) {
      buffer.writeln('较早的 $omitted 条消息因上下文窗口限制已省略。');
    }
    buffer
      ..writeln()
      ..write(ordered.join('\n'));
    return buffer.toString().trim();
  }

  List<DingTalkGatewayMessage> _pendingAiConversationMessages(
    DingTalkConversation conversation,
    String sourceMessageId, {
    bool forceResponse = false,
  }) {
    final sourceIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (sourceIndex < 0) return const <DingTalkGatewayMessage>[];
    final startIndex = _conversationTurnStartIndex(
      conversation,
      sourceIndex,
      forceResponse: forceResponse,
    );
    return conversation.messages
        .sublist(startIndex, sourceIndex + 1)
        .where(
          (message) =>
              !message.isAssistant &&
              !message.isExcludedFromAiContext &&
              _messageAiContextContent(message).isNotEmpty,
        )
        .toList(growable: false);
  }

  String _messageAiContextContent(DingTalkGatewayMessage message) {
    if (!message.isForwardedChatRecord) {
      return clipTextByCodeUnits(
        message.content.trim(),
        _maxAiContextMessageCharacters,
        suffix: '…',
      );
    }
    final buffer = StringBuffer()
      ..writeln('转发的聊天记录（共 ${message.forwardedMessageCount} 条）：');
    for (final item in message.forwardedMessages) {
      final sender = item.senderName.trim().isEmpty
          ? '用户'
          : item.senderName.trim();
      final text = item.content.trim().isNotEmpty
          ? item.content.trim()
          : item.media.map((media) => '[${media.displayName}]').join(' ');
      if (text.isEmpty) continue;
      buffer.writeln('$sender：$text');
      if (buffer.length >= _maxAiContextMessageCharacters) break;
    }
    return clipTextByCodeUnits(
      buffer.toString().trim(),
      _maxAiContextMessageCharacters,
      suffix: '…',
    );
  }

  int _conversationTurnStartIndex(
    DingTalkConversation conversation,
    int sourceIndex, {
    required bool forceResponse,
  }) {
    if (forceResponse) {
      for (var index = sourceIndex - 1; index >= 0; index--) {
        final message = conversation.messages[index];
        if (message.isAssistant && !message.isExcludedFromAiContext) {
          return index + 1;
        }
      }
      return 0;
    }
    final checkpointId =
        conversation.aiContextCheckpointMessageId?.trim() ?? '';
    if (checkpointId.isNotEmpty) {
      final checkpointIndex = conversation.messages.indexWhere(
        (message) => message.id == checkpointId,
      );
      if (checkpointIndex >= 0 && checkpointIndex < sourceIndex) {
        return checkpointIndex + 1;
      }
    }
    return 0;
  }

  List<String> _attachmentPathsForTurn(
    DingTalkConversation conversation,
    String sourceMessageId, {
    bool forceResponse = false,
  }) {
    var endIndex = conversation.messages.indexWhere(
      (message) => message.id == sourceMessageId,
    );
    if (endIndex < 0) endIndex = conversation.messages.length - 1;
    if (endIndex < 0) return const <String>[];
    final startIndex = _conversationTurnStartIndex(
      conversation,
      endIndex,
      forceResponse: forceResponse,
    );
    final selected = <String>[];
    for (var index = endIndex; index >= startIndex; index--) {
      final message = conversation.messages[index];
      if (message.isAssistant) {
        if (forceResponse) continue;
        break;
      }
      if (message.role != DingTalkGatewayMessageRole.user ||
          message.isExcludedFromAiContext) {
        continue;
      }
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
  static const int _maxDingTalkStructuredCharacters = 256 * 1024;
  static const int _maxDingTalkToolLabelCharacters = 512;
  static const int _maxDingTalkInlineFieldCharacters = 48;
  static const int _maxDingTalkStructuredDepth = 12;
  static const int _maxMessageEditHistoryEntries = 32;
  static final RegExp _markdownFenceLinePattern = RegExp(
    r'^ {0,3}(`{3,}|~{3,})',
  );
  static final RegExp _markdownBacktickRunPattern = RegExp(r'`+');
  static final RegExp _markdownLineBreakPattern = RegExp(r'[\r\n]+');
  static final RegExp _markdownInlineEscapePattern = RegExp(
    r'[\\`*_{}\[\]()<>#+.!|~-]',
  );

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
              (item.kind == AiSessionMessageKind.assistant ||
                  item.kind == AiSessionMessageKind.toolCall ||
                  item.kind == AiSessionMessageKind.hook),
        );
  }

  Future<String?> _sendDingTalkEcho({
    required DingTalkConversation conversation,
    required AiSessionMessage source,
    required DingTalkResponseEchoType type,
    required String text,
    required String uuid,
  }) async {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final completeText = text.trim();
    if (completeText.isEmpty) return null;
    final remoteText = _dingTalkRemoteEchoText(completeText);
    final sentAt = DateTime.now();
    final senderName = _authStatus.identity.label.trim();
    final localMessage = DingTalkGatewayMessage(
      id: 'assistant-${source.id}',
      conversationId: conversation.id,
      conversationType: conversation.type,
      role: DingTalkGatewayMessageRole.assistant,
      content: completeText,
      createdAt: sentAt,
      senderName: senderName,
      senderId: _authStatus.identity.userId,
      fromSelf: true,
      sourceAiMessageId: source.id,
      responseEchoType: type,
      feedback: switch (source.feedback) {
        AiSessionMessageFeedback.liked => DingTalkGatewayMessageFeedback.liked,
        AiSessionMessageFeedback.needsImprovement =>
          DingTalkGatewayMessageFeedback.needsImprovement,
        null => null,
      },
    );
    _rememberUnresolvedOutgoingMessage(localMessage.id);
    _appendMessage(conversation, localMessage);
    _notify();
    DingTalkSentMessage? sent;
    try {
      sent = await _sendDingTalkTextWithResolvedId(
        conversation: conversation,
        text: remoteText,
        uuid: uuid,
        createdAt: sentAt,
        senderName: senderName,
      );
    } catch (_) {
      conversation.messages.removeWhere(
        (message) => message.id == localMessage.id,
      );
      _unresolvedOutgoingMessageIds.remove(localMessage.id);
      rethrow;
    }
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    _rememberRemoteConversationId(conversation, sent?.conversationId);
    final sentId = sent?.messageId?.trim() ?? '';
    _bindSentMessageId(conversation, localMessage, sentId);
    _notify();
    return sentId.isEmpty ? null : sentId;
  }

  Future<DingTalkSentMessage?> _sendDingTalkTextWithResolvedId({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
    required DateTime createdAt,
    required String senderName,
  }) async {
    final sent = await _service
        .sendWithDetails(conversation: conversation, text: text, uuid: uuid)
        .timeout(const Duration(seconds: 30));
    return _resolveDingTalkSentMessageIdIfMissing(
      conversation: conversation,
      content: text,
      createdAt: createdAt,
      senderName: senderName,
      sent: sent,
    );
  }

  Future<DingTalkSentMessage?> _resolveDingTalkSentMessageIdIfMissing({
    required DingTalkConversation conversation,
    required String content,
    required DateTime createdAt,
    required String senderName,
    required DingTalkSentMessage? sent,
  }) async {
    if (sent?.messageId?.trim().isNotEmpty == true) return sent;
    try {
      final resolved = await _service
          .resolveRecentSentMessage(
            conversation: conversation,
            content: content,
            createdAt: createdAt,
            senderName: senderName,
          )
          .timeout(const Duration(seconds: 9));
      if (resolved?.messageId?.trim().isNotEmpty == true) {
        return DingTalkSentMessage(
          messageId: resolved!.messageId,
          conversationId: sent?.conversationId ?? resolved.conversationId,
        );
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '补齐钉钉已发送消息标识', error, stack);
    }
    return sent;
  }

  Future<void> _editDingTalkEcho({
    required DingTalkConversation conversation,
    required String sourceMessageId,
    required String messageId,
    required String text,
  }) async {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final completeText = text.trim();
    if (completeText.isEmpty || messageId.trim().isEmpty) return;
    await _service
        .editMessage(
          conversation: conversation,
          messageId: messageId,
          text: _dingTalkRemoteEchoText(completeText),
        )
        .timeout(const Duration(seconds: 20));
    _syncLocalEchoContent(
      conversation: conversation,
      sourceMessageId: sourceMessageId,
      text: completeText,
    );
  }

  /// 按源 AI 消息标识定位本地回显气泡；远端标识绑定前后该字段始终稳定。
  DingTalkGatewayMessage? _echoMessageBySourceId(
    DingTalkConversation conversation,
    String sourceMessageId,
  ) {
    final normalized = sourceMessageId.trim();
    if (normalized.isEmpty) return null;
    for (var index = conversation.messages.length - 1; index >= 0; index--) {
      final message = conversation.messages[index];
      if (message.sourceAiMessageId == normalized) return message;
    }
    return null;
  }

  /// 发送接口未返回消息标识时，通过会话消息列表补齐远端标识并绑定本地消息。
  Future<String?> _resolveEchoRemoteMessageId({
    required DingTalkConversation conversation,
    required String sourceMessageId,
    required String sentText,
  }) async {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final local = _echoMessageBySourceId(conversation, sourceMessageId);
    if (local == null) return null;
    final remoteText = _dingTalkRemoteEchoText(
      sentText.trim().isNotEmpty ? sentText : local.content,
    );
    final resolved = await _resolveDingTalkSentMessageIdIfMissing(
      conversation: conversation,
      // 本地保留完整正文，远端按平台预算发送；补标识时必须用远端文本匹配。
      content: remoteText,
      createdAt: local.createdAt,
      senderName: _authStatus.identity.label.trim(),
      sent: null,
    );
    final resolvedId = resolved?.messageId?.trim() ?? '';
    if (resolvedId.isEmpty ||
        _disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    _rememberRemoteConversationId(conversation, resolved?.conversationId);
    _bindSentMessageId(conversation, local, resolvedId);
    return resolvedId;
  }

  void _syncLocalEchoContent({
    required DingTalkConversation conversation,
    required String sourceMessageId,
    required String text,
  }) {
    if (_disposed ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final completeText = text.trim();
    if (completeText.isEmpty) return;
    final local = _echoMessageBySourceId(conversation, sourceMessageId);
    if (local == null || local.content == completeText) return;
    final index = conversation.messages.indexOf(local);
    if (index < 0) return;
    conversation.messages[index] = local.copyWith(content: completeText);
    _queuePersist();
    _notify();
  }

  String _dingTalkRemoteEchoText(String text) {
    final normalized = convertDingTalkMarkdownTables(text).trim();
    if (normalized.length <= _maxDingTalkEchoCharacters) return normalized;
    const notice = '\n\n…完整内容已保留在 OpenHand';
    final closingEmphasis =
        dingTalkMarkdownOuterEmphasisMarker(normalized) ?? '';
    var prefix = clipTextByCodeUnits(
      normalized,
      _maxDingTalkEchoCharacters - notice.length - closingEmphasis.length,
      suffix: '',
    );
    String? activeFence;
    var maxFenceLength = 0;
    // 远端正文截断后补齐未闭合围栏，避免后续提示被错误渲染为代码。
    void scanFences() {
      activeFence = null;
      final lines = prefix.split('\n');
      for (var index = 0; index < lines.length; index++) {
        final line =
            index == 0 &&
                closingEmphasis.isNotEmpty &&
                lines[index].startsWith(closingEmphasis)
            ? lines[index].substring(closingEmphasis.length)
            : lines[index];
        final match = _markdownFenceLinePattern.firstMatch(line);
        final fence = match?.group(1);
        if (fence == null) continue;
        if (fence.length > maxFenceLength) maxFenceLength = fence.length;
        if (activeFence == null) {
          activeFence = fence;
        } else if (fence.codeUnitAt(0) == activeFence!.codeUnitAt(0) &&
            fence.length >= activeFence!.length) {
          activeFence = null;
        }
      }
    }

    scanFences();
    if (activeFence != null) {
      prefix = clipTextByCodeUnits(
        normalized,
        _maxDingTalkEchoCharacters -
            notice.length -
            closingEmphasis.length -
            maxFenceLength -
            1,
        suffix: '',
      );
      scanFences();
    }
    return '$prefix${activeFence == null ? '' : '\n$activeFence'}$notice$closingEmphasis';
  }

  /// 该消息是否处于 AI 流式回显中（内容仍会持续更新）。
  bool isEchoStreaming(DingTalkGatewayMessage message) =>
      message.sourceAiMessageId.isNotEmpty &&
      _streamingEchoSourceIds.contains(message.sourceAiMessageId);

  void _setEchoStreaming(String sourceMessageId, bool streaming) {
    if (_disposed) return;
    final normalized = sourceMessageId.trim();
    if (normalized.isEmpty) return;
    final changed = streaming
        ? _streamingEchoSourceIds.add(normalized)
        : _streamingEchoSourceIds.remove(normalized);
    if (changed) _notify();
  }

  String _echoTextForMessage(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    if (message.kind == AiSessionMessageKind.toolCall ||
        message.kind == AiSessionMessageKind.hook) {
      return _formatDingTalkToolEcho(message, sessionMessages);
    }
    final content = message.content.trim();
    return message.kind == AiSessionMessageKind.reasoning
        ? wrapDingTalkThinkingMarkdown(content)
        : content;
  }

  String _formatDingTalkToolEcho(
    AiSessionMessage call,
    List<AiSessionMessage> sessionMessages,
  ) {
    final metadata = call.metadata;
    final toolCallId = _boundedToolLabel(metadata['tool_call_id'] ?? call.id);
    final toolName = _boundedToolLabel(metadata['tool_name'] ?? '工具');
    final arguments = _toolArgumentsValue(metadata);
    final matchingResult = _matchingToolResult(call, sessionMessages);
    final response = _toolResponseValue(metadata, matchingResult);
    final status =
        '${metadata['tool_execution_status'] ?? metadata['tool_status'] ?? metadata['status'] ?? ''}'
            .trim()
            .toLowerCase();
    final durationMs = _toolDurationMilliseconds(call);
    final statusLabel = switch (status) {
      'running' || 'executing' || 'in_progress' || 'processing' => '执行中',
      'pending' || 'queued' || 'waiting' || '' => '等待执行',
      'success' || 'succeeded' || 'completed' || 'complete' || 'ok' => '成功',
      'timed_out' || 'timeout' => '超时',
      'cancelled' || 'canceled' => '已取消',
      'denied' || 'rejected' => '已拒绝',
      'invalid_arguments' => '参数无效',
      'blocked' => '已阻止',
      'failed' || 'failure' || 'error' => '失败',
      _ => status,
    };
    final durationLabel = durationMs <= 0
        ? '—'
        : durationMs >= 1000
        ? '${(durationMs / 1000).toStringAsFixed(2)} 秒'
        : '$durationMs 毫秒';
    final summary = <String>[
      _markdownLabeledText(
        '工具调用',
        _markdownInlineText(toolName),
        valueCharacters: toolName.length,
      ),
      _markdownLabeledText(
        '状态',
        '${_toolStatusIndicator(status)} ${_markdownInlineText(statusLabel)}',
        valueCharacters: statusLabel.length + 2,
      ),
      _markdownLabeledText(
        '耗时',
        durationLabel,
        valueCharacters: durationLabel.length,
      ),
      _markdownLabeledText(
        '工具调用 ID',
        _markdownInlineCode(toolCallId),
        valueCharacters: toolCallId.length,
      ),
    ].join('  \n');
    return '''$summary

**工具参数：**

${_markdownStructuredFields(arguments)}

**工具响应：**

${_markdownStructuredFields(response)}''';
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
      matchingResult?.content,
      metadata['tool_execution_result'],
      metadata['result_text'],
      metadata['tool_execution_stdout'],
      metadata['tool_execution_stderr'],
    ];
    for (final candidate in candidates) {
      final value = _prettyToolValue(candidate);
      if (value.trim().isNotEmpty) return value;
    }
    return '—';
  }

  String _prettyToolValue(Object? raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    try {
      return jsonEncode(raw);
    } catch (_) {
      return '$raw'.trim();
    }
  }

  String _boundedToolLabel(Object? raw) {
    final value = '$raw'.trim();
    return clipTextByCodeUnits(
      value,
      _maxDingTalkToolLabelCharacters,
      suffix: '…',
    );
  }

  String _markdownInlineText(String value) => value
      .replaceAll(_markdownLineBreakPattern, ' ')
      .replaceAllMapped(
        _markdownInlineEscapePattern,
        (match) => '\\${match.group(0)}',
      )
      .trim();

  String _markdownInlineCode(String value) {
    final normalized = value.replaceAll(_markdownLineBreakPattern, ' ').trim();
    if (normalized.isEmpty) return '`—`';
    var fenceLength = 1;
    for (final match in _markdownBacktickRunPattern.allMatches(normalized)) {
      final runLength = match.end - match.start;
      if (runLength >= fenceLength) fenceLength = runLength + 1;
    }
    final fence = ''.padLeft(fenceLength, '`');
    return fenceLength == 1
        ? '$fence$normalized$fence'
        : '$fence $normalized $fence';
  }

  String _toolStatusIndicator(String status) {
    return switch (status.trim().toLowerCase()) {
      'success' ||
      'succeeded' ||
      'completed' ||
      'complete' ||
      'ok' ||
      'passed' => '🟢',
      'running' ||
      'pending' ||
      'queued' ||
      'waiting' ||
      'executing' ||
      'in_progress' ||
      'processing' ||
      'started' ||
      '' => '🟠',
      _ => '🔴',
    };
  }

  String _markdownLabeledText(
    String label,
    String value, {
    required int valueCharacters,
    int? listDepth,
  }) {
    final depth = listDepth ?? 0;
    final indentation = listDepth == null ? '' : '  ' * depth;
    final prefix =
        '$indentation${listDepth == null ? '' : '- '}**${_markdownInlineText(label)}：**';
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty ? '—' : trimmed;
    final fitsOneLine =
        !normalized.contains('\n') &&
        label.length + valueCharacters + depth * 2 + 2 <=
            _maxDingTalkInlineFieldCharacters;
    if (fitsOneLine) return '$prefix $normalized';
    final continuationIndent = listDepth == null ? '' : '  ' * (depth + 1);
    final lines = normalized
        .split('\n')
        .map((line) => '$continuationIndent$line')
        .join('  \n');
    return '$prefix  \n$lines';
  }

  String _markdownStructuredFields(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '- **内容：** —';
    Object? decoded;
    var structured = false;
    if (normalized.length <= _maxDingTalkStructuredCharacters) {
      try {
        decoded = jsonDecode(normalized);
        structured = true;
      } catch (_) {
        // 非 JSON 内容按普通多行字段展示。
      }
    }
    final buffer = StringBuffer();
    if (!structured) {
      _writeMarkdownField(buffer, '内容', normalized, 0);
    } else if (decoded is Map) {
      if (decoded.isEmpty) {
        _writeMarkdownField(buffer, '内容', const <String, Object?>{}, 0);
      } else {
        for (final entry in decoded.entries) {
          _writeMarkdownField(buffer, '${entry.key}', entry.value, 0);
        }
      }
    } else if (decoded is List) {
      if (decoded.isEmpty) {
        _writeMarkdownField(buffer, '内容', const <Object?>[], 0);
      } else {
        for (var index = 0; index < decoded.length; index++) {
          _writeMarkdownField(buffer, '第 ${index + 1} 项', decoded[index], 0);
        }
      }
    } else {
      _writeMarkdownField(buffer, '内容', decoded, 0);
    }
    return buffer.toString().trimRight();
  }

  void _writeMarkdownField(
    StringBuffer buffer,
    String label,
    Object? raw,
    int depth,
  ) {
    if (depth < _maxDingTalkStructuredDepth && raw is Map) {
      if (raw.isEmpty) {
        buffer.writeln(
          _markdownLabeledText(
            label,
            '{}',
            valueCharacters: 2,
            listDepth: depth,
          ),
        );
        return;
      }
      buffer.writeln('${'  ' * depth}- **${_markdownInlineText(label)}：**');
      for (final entry in raw.entries) {
        _writeMarkdownField(buffer, '${entry.key}', entry.value, depth + 1);
      }
      return;
    }
    if (depth < _maxDingTalkStructuredDepth && raw is List) {
      if (raw.isEmpty) {
        buffer.writeln(
          _markdownLabeledText(
            label,
            '[]',
            valueCharacters: 2,
            listDepth: depth,
          ),
        );
        return;
      }
      buffer.writeln('${'  ' * depth}- **${_markdownInlineText(label)}：**');
      for (var index = 0; index < raw.length; index++) {
        _writeMarkdownField(buffer, '第 ${index + 1} 项', raw[index], depth + 1);
      }
      return;
    }
    String scalar;
    if (raw is String) {
      scalar = raw;
    } else if (raw == null || raw is num || raw is bool) {
      scalar = '$raw';
    } else {
      try {
        scalar = jsonEncode(raw);
      } catch (_) {
        scalar = '$raw';
      }
    }
    final normalized = scalar.trim().isEmpty ? '—' : scalar.trim();
    var markdownValue = normalized
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_markdownInlineText)
        .join('\n');
    final normalizedLabel = label.trim().toLowerCase();
    if ((normalizedLabel == '状态' ||
            normalizedLabel == 'status' ||
            normalizedLabel.endsWith('_status')) &&
        !markdownValue.startsWith('🔴') &&
        !markdownValue.startsWith('🟠') &&
        !markdownValue.startsWith('🟢')) {
      markdownValue = '${_toolStatusIndicator(normalized)} $markdownValue';
    }
    buffer.writeln(
      _markdownLabeledText(
        label,
        markdownValue,
        valueCharacters: normalized.length,
        listDepth: depth,
      ),
    );
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
        .clamp(0, Duration.millisecondsPerDay);
  }

  static const int _maxQueuedResponsesPerConversation = 256;

  Future<void> _enqueueAiResponse(
    DingTalkConversation conversation,
    String content, {
    String? sourceMessageId,
    int? responseVersion,
    bool forceResponse = false,
    bool automaticResponse = false,
    int? pollingGeneration,
  }) {
    final normalized = content.trim();
    if (normalized.isEmpty ||
        _disposed ||
        (responseVersion != null &&
            _isResponseCancelled(conversation.id, responseVersion))) {
      return Future<void>.value();
    }
    final sourceMessageIdValue = sourceMessageId?.trim() ?? '';
    final sourceMessage = sourceMessageIdValue.isEmpty
        ? null
        : conversation.messages
              .where((message) => message.id == sourceMessageIdValue)
              .firstOrNull;
    if (automaticResponse &&
        (sourceMessage == null ||
            !_isAutomaticResponseEligible(sourceMessage, pollingGeneration))) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    final requestedSourceId = sourceMessageIdValue;
    final sourceId = requestedSourceId.isEmpty
        ? conversation.messages.isEmpty
              ? ''
              : conversation.messages.last.id
        : requestedSourceId;
    final source = conversation.messages
        .where((message) => message.id == sourceId)
        .firstOrNull;
    if (source != null &&
        (source.isAssistant || source.isExcludedFromAiContext)) {
      return Future<void>.value();
    }
    if (automaticResponse) {
      final checkpointId =
          conversation.aiContextCheckpointMessageId?.trim() ?? '';
      final checkpointIndex = checkpointId.isEmpty
          ? -1
          : conversation.messages.indexWhere(
              (message) => message.id == checkpointId,
            );
      final sourceIndex = conversation.messages.indexWhere(
        (message) => message.id == sourceId,
      );
      if (checkpointIndex >= 0 && sourceIndex <= checkpointIndex) {
        return Future<void>.value();
      }
      if (_activeResponseConversationIds.contains(conversation.id) &&
          source != null) {
        _activeResponseLatestTriggerTimes.update(
          conversation.id,
          (current) =>
              source.createdAt.isAfter(current) ? source.createdAt : current,
          ifAbsent: () => source.createdAt,
        );
      }
    }
    final queue = _responseQueues.putIfAbsent(
      conversation.id,
      () => Queue<_QueuedDingTalkResponse>(),
    );
    final pendingDirectResponse =
        automaticResponse &&
            conversation.type == DingTalkConversationType.direct
        ? queue
              .where(
                (item) =>
                    item.automaticResponse &&
                    item.pollingGeneration == pollingGeneration,
              )
              .lastOrNull
        : null;
    if (pendingDirectResponse != null) {
      final pendingSourceIndex = conversation.messages.indexWhere(
        (message) => message.id == pendingDirectResponse.sourceMessageId,
      );
      final sourceIndex = conversation.messages.indexWhere(
        (message) => message.id == sourceId,
      );
      pendingDirectResponse.merge(
        normalized,
        sourceId,
        forceResponse,
        completer,
        advanceSource: sourceIndex >= pendingSourceIndex,
        trackWaiter: false,
      );
      completer.complete();
      _notify();
      return completer.future;
    }
    if (queue.length >= _maxQueuedResponsesPerConversation) {
      final tail = queue.last;
      if ((!automaticResponse ||
              conversation.type != DingTalkConversationType.group) &&
          tail.canMerge(automaticResponse, pollingGeneration)) {
        tail.merge(
          normalized,
          sourceId,
          forceResponse,
          completer,
          appendContent: !automaticResponse,
        );
        _warningMessage = '钉钉会话消息过多，已将同类消息合并后依次处理。';
      } else {
        final discarded = queue
            .where((item) => item.automaticResponse)
            .firstOrNull;
        if (discarded == null) return Future<void>.value();
        queue.remove(discarded);
        discarded.complete();
        queue.add(
          _QueuedDingTalkResponse(
            normalized,
            sourceId,
            source?.createdAt ?? DateTime.now(),
            _responseSequence++,
            forceResponse,
            automaticResponse,
            pollingGeneration,
            completer,
          ),
        );
        _warningMessage = '钉钉会话消息过多，已跳过最早的自动响应任务。';
      }
    } else {
      final queuedResponse = _QueuedDingTalkResponse(
        normalized,
        sourceId,
        source?.createdAt ?? DateTime.now(),
        _responseSequence++,
        forceResponse,
        automaticResponse,
        pollingGeneration,
        completer,
      );
      if (automaticResponse &&
          conversation.type == DingTalkConversationType.group) {
        final sourceIndex = conversation.messages.indexWhere(
          (message) => message.id == sourceId,
        );
        final ordered = queue.toList(growable: true);
        final insertIndex = ordered.indexWhere((item) {
          if (!item.automaticResponse ||
              item.pollingGeneration != pollingGeneration) {
            return false;
          }
          final itemSourceIndex = conversation.messages.indexWhere(
            (message) => message.id == item.sourceMessageId,
          );
          return itemSourceIndex >= 0 && itemSourceIndex > sourceIndex;
        });
        if (insertIndex < 0) {
          queue.add(queuedResponse);
        } else {
          ordered.insert(insertIndex, queuedResponse);
          queue
            ..clear()
            ..addAll(ordered);
        }
      } else {
        queue.add(queuedResponse);
      }
    }
    _beginResponsePreparing(conversation.id);
    unawaited(
      completer.future.whenComplete(
        () => _endResponsePreparing(conversation.id),
      ),
    );
    _notify();
    _scheduleResponseWorkers();
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

  Future<void> _cancelActiveResponseForExcludedMessage(
    String conversationId,
  ) async {
    if (_disposed || !_responseInFlight.contains(conversationId)) return;
    _responseCancellationVersions[conversationId] =
        (_responseCancellationVersions[conversationId] ?? 0) + 1;
    final sessionId = _conversations[conversationId]?.aiSessionId;
    _notify();
    if (sessionId == null || !_sessionController.canStopResponding(sessionId)) {
      return;
    }
    try {
      await _sessionController
          .stopResponding(sessionId)
          .timeout(_stopResponseTimeout);
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '排除上下文消息时停止钉钉 AI 响应', error, stack);
    }
  }

  Future<void> _cancelObsoleteAutomaticResponses() async {
    final emptyConversationIds = <String>[];
    for (final entry in _responseQueues.entries) {
      final queue = entry.value;
      final obsolete = queue
          .where(
            (item) =>
                item.automaticResponse &&
                item.pollingGeneration != _pollingGeneration,
          )
          .toList(growable: false);
      for (final item in obsolete) {
        queue.remove(item);
        item.complete();
      }
      if (queue.isEmpty) emptyConversationIds.add(entry.key);
    }
    for (final conversationId in emptyConversationIds) {
      _responseQueues.remove(conversationId);
    }
    _scheduleResponseWorkers();
    final activeConversationIds = _activeAutomaticResponseGenerations.entries
        .where((entry) => entry.value != _pollingGeneration)
        .map((entry) => entry.key)
        .toList(growable: false);
    await Future.wait<void>(
      activeConversationIds.map((conversationId) async {
        _responseCancellationVersions[conversationId] =
            (_responseCancellationVersions[conversationId] ?? 0) + 1;
        final sessionId = _conversations[conversationId]?.aiSessionId;
        if (sessionId == null ||
            !_sessionController.canStopResponding(sessionId)) {
          return;
        }
        try {
          await _sessionController
              .stopResponding(sessionId)
              .timeout(_stopResponseTimeout);
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '停止旧周期钉钉自动响应', error, stack);
        }
      }),
    );
  }

  void _cancelResponseUsingExcludedMessage(
    String conversationId,
    String messageId,
  ) {
    if (_activeResponseContextMessageIds[conversationId]?.contains(messageId) ??
        false) {
      unawaited(_cancelActiveResponseForExcludedMessage(conversationId));
    }
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

  DingTalkGatewayMessage? _latestPendingDirectResponseSource(
    DingTalkConversation conversation,
    String preferredMessageId,
    int? pollingGeneration,
  ) {
    final preferredIndex = conversation.messages.indexWhere(
      (message) => message.id == preferredMessageId,
    );
    if (preferredIndex < 0) return null;
    final checkpointId =
        conversation.aiContextCheckpointMessageId?.trim() ?? '';
    final checkpointIndex = checkpointId.isEmpty
        ? -1
        : conversation.messages.indexWhere(
            (message) => message.id == checkpointId,
          );
    for (var index = preferredIndex; index > checkpointIndex; index--) {
      final candidate = conversation.messages[index];
      if (!candidate.isAssistant &&
          !candidate.isExcludedFromAiContext &&
          candidate.content.trim().isNotEmpty &&
          _isAutomaticResponseEligible(candidate, pollingGeneration)) {
        return candidate;
      }
    }
    return null;
  }

  void _scheduleResponseWorkers() {
    if (_disposed || _shutdownRequested || _responseSchedulingQueued) return;
    _responseSchedulingQueued = true;
    scheduleMicrotask(() {
      _responseSchedulingQueued = false;
      _dispatchResponseWorkers();
    });
  }

  void _dispatchResponseWorkers() {
    if (_disposed || _shutdownRequested) return;
    while (_activeResponseConversationIds.length <
        _settings.responseWorkerCount) {
      String? selectedConversationId;
      _QueuedDingTalkResponse? selectedItem;
      for (final entry in _responseQueues.entries) {
        if (entry.value.isEmpty ||
            _activeResponseConversationIds.contains(entry.key)) {
          continue;
        }
        final candidate = entry.value.first;
        if (selectedItem == null ||
            candidate.scheduledAt.isBefore(selectedItem.scheduledAt) ||
            (candidate.scheduledAt.isAtSameMomentAs(selectedItem.scheduledAt) &&
                candidate.sequence < selectedItem.sequence)) {
          selectedConversationId = entry.key;
          selectedItem = candidate;
        }
      }
      if (selectedConversationId == null || selectedItem == null) return;
      final conversation = _conversations[selectedConversationId];
      final queue = _responseQueues[selectedConversationId];
      if (conversation == null || queue == null || queue.isEmpty) {
        final discardedQueue = _responseQueues.remove(selectedConversationId);
        if (discardedQueue == null) {
          selectedItem.complete();
        } else {
          for (final item in discardedQueue) {
            item.complete();
          }
        }
        continue;
      }
      queue.removeFirst();
      if (queue.isEmpty) _responseQueues.remove(selectedConversationId);
      _activeResponseConversationIds.add(selectedConversationId);
      unawaited(_runResponseWorker(conversation, selectedItem));
    }
  }

  Future<void> _runResponseWorker(
    DingTalkConversation conversation,
    _QueuedDingTalkResponse item,
  ) async {
    try {
      if (!_disposed && !_shutdownRequested) {
        final preparationVersion =
            _responseCancellationVersions[conversation.id] ?? 0;
        if (item.automaticResponse &&
            _pendingInitialContextHydration.remove(conversation.id)) {
          await _reconcileConversationNow(
            conversation,
            force: true,
            allowResponses: false,
            reportError: false,
            before: item.scheduledAt,
            allowHistoricalBackfill: true,
          );
          if (_isResponseCancelled(conversation.id, preparationVersion)) {
            return;
          }
        }
        var source = conversation.messages
            .where((message) => message.id == item.sourceMessageId)
            .firstOrNull;
        if (item.automaticResponse && source != null) {
          final checkpointId =
              conversation.aiContextCheckpointMessageId?.trim() ?? '';
          final checkpointIndex = checkpointId.isEmpty
              ? -1
              : conversation.messages.indexWhere(
                  (message) => message.id == checkpointId,
                );
          final sourceIndex = conversation.messages.indexWhere(
            (message) => message.id == source!.id,
          );
          if (checkpointIndex >= 0 && sourceIndex <= checkpointIndex) {
            return;
          }
        }
        if (item.automaticResponse &&
            conversation.type == DingTalkConversationType.direct &&
            (source == null || source.isExcludedFromAiContext)) {
          source = _latestPendingDirectResponseSource(
            conversation,
            item.sourceMessageId,
            item.pollingGeneration,
          );
          if (source != null) {
            item
              ..sourceMessageId = source.id
              ..content = _messageAiContextContent(source);
          }
        }
        if (item.automaticResponse &&
            (source == null ||
                !_isAutomaticResponseEligible(
                  source,
                  item.pollingGeneration,
                ))) {
          return;
        }
        if (item.automaticResponse) {
          await _ensureIncomingContextMedia(conversation, item.sourceMessageId);
          if (_isResponseCancelled(conversation.id, preparationVersion)) {
            return;
          }
          source = conversation.messages
              .where((message) => message.id == item.sourceMessageId)
              .firstOrNull;
          if (conversation.type == DingTalkConversationType.direct &&
              (source == null || source.isExcludedFromAiContext)) {
            source = _latestPendingDirectResponseSource(
              conversation,
              item.sourceMessageId,
              item.pollingGeneration,
            );
            if (source != null) {
              item
                ..sourceMessageId = source.id
                ..content = _messageAiContextContent(source);
            }
          }
          if (source == null ||
              source.isAssistant ||
              source.isExcludedFromAiContext ||
              !_isAutomaticResponseEligible(source, item.pollingGeneration)) {
            return;
          }
        }
        await _respondWithAi(
          conversation,
          item.content,
          item.sourceMessageId,
          forceResponse: item.forceResponse,
          automaticResponse: item.automaticResponse,
          pollingGeneration: item.pollingGeneration,
        );
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '处理钉钉消息队列', error, stack);
    } finally {
      item.complete();
      _activeResponseConversationIds.remove(conversation.id);
      final latestTriggerAt = _activeResponseLatestTriggerTimes.remove(
        conversation.id,
      );
      final pendingQueue = _responseQueues[conversation.id];
      if (latestTriggerAt != null && (pendingQueue?.isNotEmpty ?? false)) {
        pendingQueue!.first.scheduledAt = latestTriggerAt;
      }
      if (!_responseQueues.containsKey(conversation.id) &&
          !_responseInFlight.contains(conversation.id) &&
          !_conversations.containsKey(conversation.id)) {
        _responseCancellationVersions.remove(conversation.id);
      }
      _scheduleResponseWorkers();
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
      if (content.isNotEmpty &&
          normalizeDingTalkMessageContentForComparison(candidate.content) !=
              normalizeDingTalkMessageContentForComparison(content)) {
        continue;
      }
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

  List<AiBuiltinToolConfig> _dingtalkBuiltinToolConfigs({
    required bool knowledgeBaseEnabled,
  }) {
    final configured = _settingsController.builtinToolConfigs;
    final source = configured.isEmpty
        ? AiBuiltinToolConfig.defaults()
        : configured;
    return source
        .map(
          (config) =>
              config.kind == AiBuiltinToolKind.knowledgeSearch ||
                  config.kind == AiBuiltinToolKind.knowledgeRead
              ? config.copyWith(enabled: knowledgeBaseEnabled)
              : config,
        )
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

  void _rememberUnresolvedOutgoingMessage(String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return;
    _unresolvedOutgoingMessageIds.add(normalized);
    while (_unresolvedOutgoingMessageIds.length >
        _maxUnresolvedOutgoingMessageIds) {
      _unresolvedOutgoingMessageIds.remove(_unresolvedOutgoingMessageIds.first);
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
    _conversationRefreshInFlight.clear();
    _pendingInitialContextHydration.clear();
    _mediaHydrationFailures.clear();
    _targetSearchCache.clear();
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
    _activeResponseConversationIds.clear();
    _activeResponseLatestTriggerTimes.clear();
    _activeResponseContextMessageIds.clear();
    _activeAutomaticResponseGenerations.clear();
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
    _runtimeLogRevision.dispose();
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
    Future<String?> Function(
      AiSessionMessage source,
      DingTalkResponseEchoType type,
      String text,
      String uuid,
    );
typedef _DingTalkEchoEditor =
    Future<void> Function(
      String sourceMessageId,
      String messageId,
      String text,
    );
typedef _DingTalkEchoRemoteIdResolver =
    Future<String?> Function(String sourceMessageId, String sentText);
typedef _DingTalkEchoLocalContentSync =
    void Function(String sourceMessageId, String text);
typedef _DingTalkEchoStreamingMarker =
    void Function(String sourceMessageId, bool streaming);
typedef _DingTalkEchoErrorHandler =
    void Function(
      String action,
      Object error,
      StackTrace stack, {
      required bool notifyUser,
    });
typedef _DingTalkEchoCancellationChecker = bool Function();

/// 单轮钉钉 AI 回显协调器：每类消息先发送首帧，随 AI 生成进度节流编辑同一条钉钉
/// 消息，营造流式输出效果；远端消息标识缺失时降级为仅同步本地气泡并在终态收敛。
class _DingTalkEchoCoordinator {
  _DingTalkEchoCoordinator({
    required String responseRoundId,
    required Set<String> deliveredSourceMessageIds,
    required Set<DingTalkResponseEchoType> selectedTypes,
    required _DingTalkEchoTypeResolver typeOf,
    required _DingTalkEchoTextBuilder textFor,
    required _DingTalkEchoTerminalResolver isTerminal,
    required _DingTalkEchoCancellationChecker isCancelled,
    required _DingTalkEchoSender send,
    required _DingTalkEchoEditor edit,
    required _DingTalkEchoRemoteIdResolver resolveRemoteId,
    required _DingTalkEchoLocalContentSync syncLocal,
    required _DingTalkEchoStreamingMarker markStreaming,
    required String Function() newUuid,
    required _DingTalkEchoErrorHandler onError,
  }) : _responseRoundId = responseRoundId,
       _deliveredSourceMessageIds = deliveredSourceMessageIds,
       _selectedTypes = selectedTypes,
       _typeOf = typeOf,
       _textFor = textFor,
       _isTerminal = isTerminal,
       _isCancelled = isCancelled,
       _send = send,
       _edit = edit,
       _resolveRemoteId = resolveRemoteId,
       _syncLocal = syncLocal,
       _markStreaming = markStreaming,
       _newUuid = newUuid,
       _onError = onError;

  static const Duration _initialStreamDelay = Duration(milliseconds: 180);
  // 钉钉单条消息最多编辑 99 次。流式阶段固定两秒更新一次，并为终态收敛
  // 与平台侧计数偏差保留余量，确保最终正文仍能完整追平。
  static const Duration _editInterval = Duration(seconds: 2);
  static const int _messageEditLimit = 99;
  static const int _editSafetyReserve = 12;
  static const int _finalEditReserve = 3;
  static const int _maxRemoteEditCount = _messageEditLimit - _editSafetyReserve;
  static const int _maxStreamingRemoteEditCount =
      _maxRemoteEditCount - _finalEditReserve;
  static const int _maxTrackedMessages = 96;
  static const int _maxRemoteIdResolveAttempts = 3;

  final String _responseRoundId;
  final Set<String> _deliveredSourceMessageIds;
  final Set<DingTalkResponseEchoType> _selectedTypes;
  final _DingTalkEchoTypeResolver _typeOf;
  final _DingTalkEchoTextBuilder _textFor;
  final _DingTalkEchoTerminalResolver _isTerminal;
  final _DingTalkEchoCancellationChecker _isCancelled;
  final _DingTalkEchoSender _send;
  final _DingTalkEchoEditor _edit;
  final _DingTalkEchoRemoteIdResolver _resolveRemoteId;
  final _DingTalkEchoLocalContentSync _syncLocal;
  final _DingTalkEchoStreamingMarker _markStreaming;
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

  void ingest(AiSession session, {bool finalizing = false}) {
    if (_disposed || _isCancelled() || _selectedTypes.isEmpty) return;
    final roundStartIndex = session.messages.lastIndexWhere(
      (message) =>
          message.kind == AiSessionMessageKind.user &&
          message.metadata['sent_via'] == 'dingtalk_gateway' &&
          message.metadata[_dingTalkResponseRoundIdMetadataKey] ==
              _responseRoundId,
    );
    if (roundStartIndex < 0) return;
    final roundStartedAt = session.messages[roundStartIndex].createdAt;
    final now = DateTime.now();
    for (final message in session.messages.skip(roundStartIndex + 1)) {
      if (message.createdAt.isBefore(roundStartedAt) ||
          _deliveredSourceMessageIds.contains(message.id)) {
        continue;
      }
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
          _markStreaming(message.id, false);
        }
        continue;
      }
      final readyAt = finalizing
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
        finalizing: finalizing,
        readyAt: readyAt,
      );
    }
    _trimPending();
    _schedule();
  }

  /// 轮次收敛：按会话最终状态做最后一次采集，确保终态文本在 flush 前入队。
  void complete(AiSession session) {
    if (_disposed || _isCancelled()) return;
    ingest(session, finalizing: true);
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
      _markStreaming(removableId, false);
    }
  }

  void _schedule() {
    if (_disposed ||
        _isCancelled() ||
        _activeDrain != null ||
        _pending.isEmpty) {
      return;
    }
    final earliest = _pending.values
        .map((item) => item.readyAt)
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final scheduledAt = _scheduledAt;
    if (_timer != null &&
        scheduledAt != null &&
        !earliest.isBefore(scheduledAt)) {
      return;
    }
    _cancelScheduledDrain();
    _scheduledAt = earliest;
    final delay = earliest.difference(DateTime.now());
    _timer = startSafeTimer(
      delay,
      _startDrain,
      onError: (error, stack) =>
          _onError('调度钉钉 AI 回显队列', error, stack, notifyUser: false),
    );
  }

  void _startDrain() {
    _cancelScheduledDrain();
    if (_disposed || _isCancelled() || _activeDrain != null) return;
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
      _settle(sourceId, state, pending);
      return;
    }
    final remoteEditBudgetExhausted =
        state.sent &&
        (state.successfulRemoteEditCount >= _maxRemoteEditCount ||
            !pending.finalizing &&
                state.successfulRemoteEditCount >=
                    _maxStreamingRemoteEditCount);
    if (state.remoteEditingDisabled || remoteEditBudgetExhausted) {
      _syncLocal(sourceId, pending.text);
      state.lastMutationAt = DateTime.now();
      if (state.remoteEditingDisabled || pending.finalizing) {
        state.lastText = pending.text;
      }
      _settle(sourceId, state, pending);
      return;
    }
    try {
      if (_disposed || _isCancelled()) return;
      if (!state.sent) {
        // 插入本地气泡前先标记流式，避免正文先完整展开再收缩渐显。
        _markStreaming(sourceId, !pending.terminal);
        state.remoteMessageId = await _send(
          pending.source,
          pending.type,
          pending.text,
          state.uuid,
        );
        if (_disposed || _isCancelled()) return;
        state.sent = true;
      } else {
        final messageId = await _remoteMessageIdForEdit(sourceId, state);
        if (_disposed || _isCancelled()) return;
        if (messageId.isEmpty) {
          // 拿不到远端消息标识时无法编辑，先保证本地气泡持续流式更新；
          // lastText 保持为远端已送达文本，等待后续补齐或终态收敛。
          _syncLocal(sourceId, pending.text);
          state.lastMutationAt = DateTime.now();
          if (pending.terminal) {
            state.lastText = pending.text;
            _onError(
              '编辑钉钉 AI 回显消息',
              StateError('缺少远端消息标识，终态内容已降级为仅同步本地会话。'),
              StackTrace.current,
              notifyUser: false,
            );
          }
          _settle(sourceId, state, pending);
          return;
        }
        await _edit(sourceId, messageId, pending.text);
        if (_disposed || _isCancelled()) return;
        state.successfulRemoteEditCount++;
      }
      state.lastText = pending.text;
      state.lastMutationAt = DateTime.now();
      _settle(sourceId, state, pending);
    } catch (error, stack) {
      if (_disposed || _isCancelled()) return;
      state.lastMutationAt = DateTime.now();
      final commandError = error is DingTalkGatewayCommandException
          ? error
          : null;
      if (state.sent && commandError != null && !commandError.isRetryable) {
        state.remoteEditingDisabled = true;
        state.lastText = pending.text;
        _syncLocal(sourceId, pending.text);
        _settle(sourceId, state, pending);
        if (!commandError.isMessageEditLimitReached) {
          _onError('编辑钉钉 AI 回显消息', error, stack, notifyUser: false);
        }
        return;
      }
      // 编辑失败无需打扰用户：后续增量会以全量文本自动追平。
      _onError(
        state.sent ? '编辑钉钉 AI 回显消息' : '发送钉钉 AI 回显消息',
        error,
        stack,
        notifyUser: !state.sent,
      );
      _settle(sourceId, state, pending);
    }
  }

  void _settle(
    String sourceId,
    _DingTalkEchoDeliveryState state,
    _PendingDingTalkEcho pending,
  ) {
    state.finished = pending.terminal;
    _markStreaming(sourceId, state.sent && !state.finished);
  }

  /// 部分 dws 版本发送接口不返回消息标识，编辑前按有限次数补齐远端标识。
  Future<String> _remoteMessageIdForEdit(
    String sourceId,
    _DingTalkEchoDeliveryState state,
  ) async {
    final known = state.remoteMessageId?.trim() ?? '';
    if (known.isNotEmpty) return known;
    if (state.remoteIdResolveAttempts >= _maxRemoteIdResolveAttempts) {
      return '';
    }
    state.remoteIdResolveAttempts++;
    final resolved =
        (await _resolveRemoteId(sourceId, state.lastText))?.trim() ?? '';
    if (resolved.isNotEmpty) state.remoteMessageId = resolved;
    return resolved;
  }

  Future<void> flush() async {
    if (_disposed || _isCancelled()) {
      _cancelScheduledDrain();
      _pending.clear();
      return;
    }
    _cancelScheduledDrain();
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
    _cancelScheduledDrain();
    for (final sourceId in _states.keys) {
      _markStreaming(sourceId, false);
    }
    _pending.clear();
    _states.clear();
  }

  void _cancelScheduledDrain() {
    _timer?.cancel();
    _timer = null;
    _scheduledAt = null;
  }
}

class _PendingDingTalkEcho {
  const _PendingDingTalkEcho({
    required this.source,
    required this.type,
    required this.text,
    required this.terminal,
    required this.finalizing,
    required this.readyAt,
  });

  final AiSessionMessage source;
  final DingTalkResponseEchoType type;
  final String text;
  final bool terminal;
  final bool finalizing;
  final DateTime readyAt;

  _PendingDingTalkEcho copyWith({DateTime? readyAt}) {
    return _PendingDingTalkEcho(
      source: source,
      type: type,
      text: text,
      terminal: terminal,
      finalizing: finalizing,
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
  int remoteIdResolveAttempts = 0;
  int successfulRemoteEditCount = 0;
  bool sent = false;
  bool finished = false;
  bool remoteEditingDisabled = false;
}

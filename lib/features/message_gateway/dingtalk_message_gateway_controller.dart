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
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/model/assistant_response_completion.dart';
import '../../shared/model/dingtalk_multimodal_capability.dart';
import '../../shared/net/http_redirect_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/physical_path_safety.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/tool_name_normalization.dart';
import '../ai/index.dart';
import '../instructions/index.dart';
import '../knowledge_base/index.dart';
import '../mcp/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import '../workflows/index.dart';
import 'data/dingtalk_message_gateway_store.dart';
import 'dingtalk_markdown_compat.dart';
import 'message_gateway_dependencies.dart';
import 'model/dingtalk_message_gateway.dart';
import 'service/dingtalk_message_gateway_service.dart';

const String _dingTalkResponseRoundIdMetadataKey = 'dingtalk_response_round_id';
final RegExp _dingTalkToolCallIdentityPattern = RegExp(
  r'\b(?:call|toolu|hook)[-_][A-Za-z0-9_-]{6,}\b',
  caseSensitive: false,
);

class _DingTalkEagerMcpTool {
  const _DingTalkEagerMcpTool({
    required this.name,
    required this.serverName,
    required this.description,
  });

  final String name;
  final String serverName;
  final String description;
}

String _sanitizeDingTalkVisibleText(String value) =>
    stripImageSummaryMarkup(value);

@visibleForTesting
bool canMergeDingTalkOutgoingEcho({
  required bool incomingIsSelf,
  required bool incomingIdentityUnresolved,
  required bool unresolvedOutgoing,
  required bool sameContent,
  required bool sameMedia,
  required bool withinUnverifiedMatchWindow,
}) =>
    unresolvedOutgoing &&
    (incomingIsSelf && (sameContent || sameMedia) ||
        incomingIdentityUnresolved &&
            withinUnverifiedMatchWindow &&
            sameContent);

@visibleForTesting
bool matchesDingTalkOutgoingMedia(
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
        expected.resourceType == actual.resourceType &&
        expected.kind == actual.kind) {
      continue;
    }
    if (expected.kind != actual.kind) return false;

    var matched = false;
    if (expected.sizeBytes > 0 && actual.sizeBytes > 0) {
      if (expected.sizeBytes != actual.sizeBytes) return false;
      matched = true;
    }
    final expectedName = expected.name.trim().toLowerCase();
    final actualName = actual.name.trim().toLowerCase();
    if (expectedName.isNotEmpty && actualName.isNotEmpty) {
      if (expectedName != actualName) return false;
      matched = true;
    } else if (expectedName.isNotEmpty &&
        normalizedContent.contains(expectedName)) {
      matched = true;
    }
    if (!matched) return false;
  }
  return true;
}

@visibleForTesting
List<DingTalkGatewayMedia> mergeDingTalkMediaCache(
  List<DingTalkGatewayMedia> current,
  List<DingTalkGatewayMedia> remote,
) {
  return remote
      .map((item) {
        final normalizedId = normalizeDingTalkResourceId(item.resourceId);
        for (final previous in current) {
          final previousId = normalizeDingTalkResourceId(previous.resourceId);
          final sameResource =
              previousId == normalizedId &&
              previous.resourceType == item.resourceType;
          final previousMessageId = normalizeDingTalkMessageId(
            previous.messageId,
          );
          final localReference =
              previousId.startsWith('local-') ||
              previousId.startsWith('assistant-media-') ||
              previousMessageId.isNotEmpty && previousId == previousMessageId;
          final previousName = previous.name.trim().toLowerCase();
          final itemName = item.name.trim().toLowerCase();
          final kindCompatible =
              previous.kind == item.kind ||
              (itemName.isEmpty &&
                  item.resourceType == DingTalkMediaResourceType.fileId);
          final sameLocalAttachment =
              localReference &&
              kindCompatible &&
              (previousName.isNotEmpty && previousName == itemName ||
                  itemName.isEmpty ||
                  previous.sizeBytes > 0 &&
                      item.sizeBytes > 0 &&
                      previous.sizeBytes == item.sizeBytes);
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
              mimeType: item.mimeType.trim().isEmpty ? previous.mimeType : null,
              sizeBytes: item.sizeBytes > 0 ? null : previous.sizeBytes,
              localPath: previous.localPath,
            );
          }
        }
        return item.copyWith(resourceId: normalizedId);
      })
      .toList(growable: false);
}

@visibleForTesting
bool canResumeDingTalkQueuedResponse({
  required bool serviceEnabled,
  required bool queuePaused,
  required bool responseActive,
  required bool itemExists,
}) => serviceEnabled && queuePaused && !responseActive && itemExists;

@visibleForTesting
bool prioritizeDingTalkQueuedResponse<T>(
  Queue<T> queue,
  bool Function(T item) matches,
) {
  final item = queue.where(matches).firstOrNull;
  if (item == null) return false;
  queue
    ..remove(item)
    ..addFirst(item);
  return true;
}

enum DingTalkConversationResponseState {
  idle,
  active,
  awaitingApproval,
  failed,
}

enum DingTalkGatewayResourceCatalog {
  mcp,
  skills,
  memories,
  instructions,
  knowledgeBase,
  workflows,
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

class DingTalkQueuedResponse {
  const DingTalkQueuedResponse({
    required this.sequence,
    required this.sourceMessageId,
    required this.content,
    required this.scheduledAt,
  });

  final int sequence;
  final String sourceMessageId;
  final String content;
  final DateTime scheduledAt;
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
    this.completer,
  );

  String content;
  String sourceMessageId;
  DateTime scheduledAt;
  final int sequence;
  bool forceResponse;
  bool manuallyPrioritized = false;
  final bool automaticResponse;
  final int? pollingGeneration;
  final Completer<void> completer;

  void complete() {
    if (!completer.isCompleted) completer.complete();
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
       _workflowsController = dependencies.workflowsController,
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
  static const int _maxUnresolvedOutgoingMessageIds = 256;
  static const int _maxOutgoingEchoSnapshotSources = 128;
  static const int _maxOutgoingEchoSnapshotsPerSource = 8;
  static const Duration _outgoingEchoWindow = Duration(seconds: 30);
  static const Duration _unverifiedOutgoingEchoWindow = Duration(seconds: 5);
  static const int _maxAiConversationContextCharacters = 48000;
  static const int _maxAiConversationContextMessages = 200;
  static const int _maxAiContextMessageCharacters = 4000;
  static const int _initialConversationHistoryMessageLimit = 20;
  static const Duration _conversationStartSkew = Duration(seconds: 2);
  static const Duration _queryWindow = Duration(minutes: 10);
  static const Duration _queryOverlap = Duration(seconds: 2);
  // 个人 IM 事件只覆盖收到的消息；当前账号自己发送的消息由短周期查询补齐。
  static const Duration _realtimeReconcilePollInterval = Duration(seconds: 3);
  // 编辑和本人发送消息没有独立的个人 IM 事件，保持有界快速对账。
  static const Duration _conversationReconcileInterval = Duration(seconds: 5);
  // 查询本身已有 40 秒服务端总时限；额外留出进程回收与结果解析时间。
  static const Duration _pollQueryTimeout = Duration(seconds: 45);
  static const Duration _pollAuthStatusTimeout = Duration(seconds: 10);
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
  static const int _minimumGeneratedMediaFileBytes = 16;
  static const String _groupResponseReminder =
      '钉钉群聊规则：围绕本轮最后一条 @我 消息回复；此前消息仅作上下文。仅输出一条适合发送的回复。';
  static const String _directResponseReminder =
      '钉钉私聊规则：综合本轮全部新消息，仅输出一条合并回复，不要逐条回复。';
  static const String _standardResponseReminder =
      '钉钉网关规则：仅回复本轮最后一条触发消息；此前消息仅作上下文，不逐条回复。直接输出适合发送给对方的回复。';
  static const String _forcedResponseReminder =
      '钉钉网关规则：回复本轮最后一条有效消息；此前消息仅作上下文。直接输出一条适合发送的回复。';
  static const String _responseCompletionReminder =
      '钉钉回复必须完整、可直接发送。若声明查询、调用、重试或继续，立即完成对应动作；不得以冒号、半句或未闭合结构结束。';
  static const String _overloadBusyReply = 'AI 当前较忙，请稍后再试。';
  static const String _responseFailureReply = 'AI 响应失败，请稍后重试。';
  static const int _maxConversationReconcileCount = 12;
  static const int _conversationReconcileConcurrency = 4;
  static const int _maxConversationReconcileFailureCount = 6;
  static final RegExp _mentionTrailingBoundary = RegExp(
    r'[\s，。！？、,:：;；）)\]】>…]',
  );
  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final InstructionsController _instructionsController;
  final KnowledgeBaseController? _knowledgeBaseController;
  final WorkflowsController _workflowsController;
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
  final Map<String, _QueuedDingTalkResponse> _activeAutomaticResponses =
      <String, _QueuedDingTalkResponse>{};
  final Map<String, int> _responsePreparingCounts = <String, int>{};
  final Map<String, String> _responseErrors = <String, String>{};
  final Set<String> _responseFailureReplySuppressed = <String>{};
  final Set<String> _pendingInitialContextHydration = <String>{};

  /// 每次停止响应都会递增。正在执行的响应携带启动时版本，前置异步
  /// 阶段完成后若版本已变化，立即结束本轮，避免停止后继续发起 AI 请求。
  final Map<String, int> _responseCancellationVersions = <String, int>{};
  final Map<String, Completer<void>> _activeMediaGenerationCancellations =
      <String, Completer<void>>{};
  final Map<String, Queue<_QueuedDingTalkResponse>> _responseQueues =
      <String, Queue<_QueuedDingTalkResponse>>{};
  final Set<String> _pausedResponseQueueConversationIds = <String>{};
  final Set<String> _activeResponseConversationIds = <String>{};
  final Set<String> _seenMessageIds = <String>{};
  final Set<String> _unresolvedOutgoingMessageIds = <String>{};
  final LinkedHashMap<String, Set<String>> _outgoingEchoContentSnapshots =
      LinkedHashMap<String, Set<String>>();
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
  bool _eventRestartQueued = false;
  Future<void>? _periodicReconcileFuture;
  Future<void>? _pollingStopInFlight;
  Completer<void>? _activePollCancellation;
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

  /// 消息窗口可用状态：必须已授权且消息监听正在运行。
  bool get isServiceEnabled =>
      !_disposed &&
      !_shutdownRequested &&
      _authStatus.authenticated &&
      _isPolling;
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
  List<WorkflowDefinition> get workflows => _workflowsController.workflows
      .where((item) => item.enabled)
      .toList(growable: false);
  Future<List<AiDingTalkDwsCommand>> loadDwsCommandCatalog({
    bool forceRefresh = false,
  }) => _service.loadDwsCommandCatalog(forceRefresh: forceRefresh);

  Future<Object?> _executeDwsCommandForAi({
    required AiDingTalkDwsCommand command,
    required Map<String, Object?> arguments,
    required String workingDirectory,
    Future<void>? cancelSignal,
  }) async {
    if (!isServiceEnabled) {
      throw StateError('钉钉消息服务未启用。');
    }
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
    if (!isServiceEnabled) {
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
      if (await _validatedDingTalkMediaFileSize(
            path,
            allowedRoot: root,
            maxBytes: 32 * kBytesPerMiB,
          ) ==
          null) {
        continue;
      }
      referenceParts.add(
        AiChatContentPart.imageFile(
          filePath: path,
          mimeType: _mediaMimeType(path, fallback: kImageJpegMimeType),
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
    if (!isServiceEnabled) {
      throw const AiMediaGenerationCancelledException();
    }
    final references = _generatedMediaReferences(
      generated.markdown,
    ).take(4).toList();
    if (references.isEmpty) {
      throw StateError('生成服务未返回可发送的媒体文件。');
    }
    final mediaKind = switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration => DingTalkMediaKind.image,
      AiDingTalkMultimodalCapability.videoGeneration => DingTalkMediaKind.video,
      AiDingTalkMultimodalCapability.audioGeneration => DingTalkMediaKind.audio,
    };
    final cacheKind = switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration => MediaCacheKind.image,
      AiDingTalkMultimodalCapability.videoGeneration => MediaCacheKind.video,
      AiDingTalkMultimodalCapability.audioGeneration => MediaCacheKind.audio,
    };
    String? firstRemoteId;
    String? firstPath;
    String? firstName;
    var sentCount = 0;
    var remoteDownloadFailed = false;
    var unsendableFileFound = false;
    final generatedRoot = p.normalize(
      p.join(Directory.systemTemp.path, 'openhand_media'),
    );
    final mediaCacheRoot = p.normalize(MediaCacheService.cacheDirectoryPath);
    for (final reference in references) {
      if (!isServiceEnabled || await isCancelSignalCompleted(cancelSignal)) {
        throw const AiMediaGenerationCancelledException();
      }
      var path = reference.path;
      var allowedRoot = generatedRoot;
      if (path == null) {
        path = await MediaCacheService.instance.ensureCached(
          reference.remoteUrl!,
          kind: cacheKind,
          cancelSignal: cancelSignal,
        );
        if (!isServiceEnabled || await isCancelSignalCompleted(cancelSignal)) {
          throw const AiMediaGenerationCancelledException();
        }
        if (path == null) {
          remoteDownloadFailed = true;
          continue;
        }
        allowedRoot = mediaCacheRoot;
      }
      final sizeBytes = await _validatedDingTalkMediaFileSize(
        path,
        allowedRoot: allowedRoot,
        minBytes: _minimumGeneratedMediaFileBytes,
        maxBytes: kDingTalkMessageAttachmentMaxBytes,
      );
      if (sizeBytes == null) {
        unsendableFileFound = true;
        continue;
      }
      final name = p.basename(path).trim().isEmpty ? '生成媒体' : p.basename(path);
      final remoteId = await _service.sendFile(
        conversation: conversation,
        filePath: path,
        audio: mediaKind == DingTalkMediaKind.audio,
        uuid: _uuid.v4(),
        cancelSignal: cancelSignal,
      );
      if (!isServiceEnabled) {
        throw const AiMediaGenerationCancelledException();
      }
      final normalizedRemoteId = remoteId?.trim() ?? '';
      final messageId = normalizedRemoteId.isNotEmpty
          ? normalizedRemoteId
          : 'assistant-media-${_uuid.v4()}';
      final media = DingTalkGatewayMedia(
        resourceId: messageId,
        messageId: messageId,
        conversationId: conversation.id,
        kind: mediaKind,
        name: name,
        mimeType: _mediaMimeType(
          path,
          fallback: switch (capability) {
            AiDingTalkMultimodalCapability.imageGeneration => kImagePngMimeType,
            AiDingTalkMultimodalCapability.videoGeneration => kVideoMp4MimeType,
            AiDingTalkMultimodalCapability.audioGeneration =>
              kAudioMpegMimeType,
          },
        ),
        sizeBytes: sizeBytes,
        localPath: path,
      );
      final localMessage = DingTalkGatewayMessage(
        id: messageId,
        conversationId: conversation.id,
        conversationType: conversation.type,
        role: DingTalkGatewayMessageRole.assistant,
        content: '[${media.displayName}]',
        createdAt: DateTime.now(),
        senderName: _authStatus.identity.label.trim().isEmpty
            ? 'OpenHand'
            : _authStatus.identity.label.trim(),
        senderId: _authStatus.identity.userId,
        media: <DingTalkGatewayMedia>[media],
        fromSelf: true,
      );
      if (normalizedRemoteId.isEmpty) {
        _rememberUnresolvedOutgoingMessage(messageId);
      } else {
        _remember(normalizedRemoteId);
      }
      final existingIndex = normalizedRemoteId.isEmpty
          ? -1
          : conversation.messages.indexWhere(
              (message) => message.id == normalizedRemoteId,
            );
      if (existingIndex < 0) {
        _appendMessage(conversation, localMessage);
      } else {
        conversation.messages[existingIndex] = _mergeOutgoingMessage(
          localMessage,
          conversation.messages[existingIndex],
          normalizedRemoteId,
        );
        _queuePersist();
      }
      if (_collapseOutgoingEchoDuplicates(conversation) > 0) {
        _queuePersist();
      }
      firstRemoteId ??= remoteId?.trim();
      firstPath ??= path;
      firstName ??= name;
      sentCount++;
    }
    if (!isServiceEnabled) {
      throw const AiMediaGenerationCancelledException();
    }
    if (firstPath == null) {
      if (unsendableFileFound) {
        throw StateError('生成媒体文件无效或超过 512MB 发送上限。');
      }
      if (remoteDownloadFailed) {
        throw StateError('生成媒体文件下载失败，请稍后重试。');
      }
      throw StateError('生成媒体文件不存在或无法发送。');
    }
    _notify();
    return <String, Object?>{
      'success': true,
      'file_path': firstPath,
      'file_name': firstName,
      'remote_message_id': firstRemoteId,
      'media_kind': mediaKind.name,
      'duration_ms': generated.durationMs,
      'sent_count': sentCount,
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

  ({bool attempted, bool succeeded}) _dingTalkMediaRoundState(
    AiSession? session,
    int startIndex,
    AiDingTalkMultimodalCapability capability,
  ) {
    final messages = session?.messages ?? const <AiSessionMessage>[];
    final safeStart = math.min(math.max(startIndex, 0), messages.length);
    return inspectDingTalkMultimodalRound(
      messages.skip(safeStart).map((message) => message.metadata),
      capability,
    );
  }

  Future<void> _executeDingTalkMediaGenerationFallback({
    required DingTalkConversation conversation,
    required AiDingTalkMultimodalCapability capability,
    required String prompt,
    required List<String> referenceImagePaths,
    required bool Function() responseCancelled,
  }) async {
    if (responseCancelled()) return;
    final cancellation = Completer<void>();
    final previous = _activeMediaGenerationCancellations[conversation.id];
    if (previous != null && !previous.isCompleted) previous.complete();
    _activeMediaGenerationCancellations[conversation.id] = cancellation;
    try {
      await _executeDingTalkMediaGenerationForAi(
        conversation: conversation,
        capability: capability,
        prompt: prompt,
        options: AiCreationOptions.empty,
        referenceImagePaths: referenceImagePaths,
        cancelSignal: cancellation.future,
      );
    } on AiMediaGenerationCancelledException {
      return;
    } catch (error, stack) {
      if (responseCancelled()) return;
      silentLog('dingtalk_gateway', '执行钉钉多模态生成兜底', error, stack);
      await _sendDingTalkMediaGenerationFailure(
        conversation: conversation,
        capability: capability,
        responseCancelled: responseCancelled,
      );
    } finally {
      if (identical(
        _activeMediaGenerationCancellations[conversation.id],
        cancellation,
      )) {
        _activeMediaGenerationCancellations.remove(conversation.id);
      }
    }
  }

  Future<void> _sendDingTalkMediaGenerationFailure({
    required DingTalkConversation conversation,
    required AiDingTalkMultimodalCapability capability,
    required bool Function() responseCancelled,
  }) async {
    final message = '${capability.displayName}失败，请检查生成模型配置后重试。';
    _setResponseError(conversation.id, message);
    if (responseCancelled() ||
        !_settings.responseEchoTypes.contains(
          DingTalkResponseEchoType.finalResponse,
        )) {
      return;
    }
    final now = DateTime.now();
    await _sendDingTalkEcho(
      conversation: conversation,
      source: AiSessionMessage.assistant(
        id: 'dingtalk-media-failure-${_uuid.v4()}',
        content: message,
        createdAt: now,
      ),
      type: DingTalkResponseEchoType.finalResponse,
      text: message,
      uuid: _uuid.v4(),
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

  Future<int?> _validatedDingTalkMediaFileSize(
    String path, {
    required String allowedRoot,
    int minBytes = 1,
    required int maxBytes,
  }) async {
    late final FileSystemEntityType type;
    try {
      type = await FileSystemEntity.type(
        path,
        followLinks: false,
      ).timeout(defaultBoundedFileReadIdleTimeout);
    } on FileSystemException {
      return null;
    } on TimeoutException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (type != FileSystemEntityType.file ||
        !await isPhysicalPathWithinOrEqual(allowedRoot, path)) {
      return null;
    }
    final size = await probeFileSizeBounded(File(path));
    return size != null && size >= minBytes && size <= maxBytes ? size : null;
  }

  List<({String? path, String? remoteUrl})> _generatedMediaReferences(
    String markdown,
  ) {
    final result = <({String? path, String? remoteUrl})>[];
    final seen = <String>{};
    final pattern = RegExp(r'!?\[[^\]\r\n]{0,240}\]\(([^)\r\n]+)\)');
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
      final uri = Uri.tryParse(raw);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final remoteUrl = uri.toString();
        if (seen.add(remoteUrl)) {
          result.add((path: null, remoteUrl: remoteUrl));
        }
        continue;
      }
      final path = p.normalize(raw);
      if (seen.add(path)) {
        result.add((path: path, remoteUrl: null));
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
      '.m4a' => kAudioMp4MimeType,
      '.ogg' => kAudioOggMimeType,
      '.aac' => kAudioAacMimeType,
      _ => fallback,
    };
  }

  List<DingTalkConversation> get conversations {
    final values = _conversations.values.toList(growable: false);
    return values..sort(compareDingTalkConversationsByRecent);
  }

  Future<List<DingTalkConversationTarget>> searchTargets({
    required DingTalkConversationType type,
    required String query,
  }) async {
    final keyword = query.trim();
    if (!isServiceEnabled || keyword.isEmpty) {
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
        if (_disposed || _shutdownRequested || !isServiceEnabled) {
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
    if (!isServiceEnabled || _conversations.containsKey(target.id)) return;
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
    if (!isServiceEnabled) return;
    if (!_conversationRefreshInFlight.add(conversation.id)) return;
    _notify();
    try {
      final page = await _service.queryConversationPage(
        conversation: conversation,
        limit: _initialConversationHistoryMessageLimit,
      );
      if (!isServiceEnabled ||
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
      // 首屏只导入最近 20 条，更早消息按需分页回溯。
      state
        ..hasMore = page.hasMore
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
    if (!isServiceEnabled) return;
    final conversation = _conversations[conversationId];
    if (conversation == null) return;
    await stopConversationResponse(conversationId);
    _discardQueuedResponses(conversationId, conversation: conversation);
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
    final hasActiveResponse =
        _responseInFlight.contains(conversationId) ||
        _activeResponseConversationIds.contains(conversationId) ||
        (sessionId != null &&
            !_responseCancellationVersions.containsKey(conversationId) &&
            _sessionController.canStopResponding(sessionId));
    if (_pausedResponseQueueConversationIds.contains(conversationId)) {
      return hasActiveResponse;
    }
    return hasActiveResponse ||
        _responsePreparingCounts.containsKey(conversationId) ||
        (_responseQueues[conversationId]?.isNotEmpty ?? false);
  }

  bool isResponseQueuePaused(String conversationId) =>
      _pausedResponseQueueConversationIds.contains(conversationId.trim()) &&
      (_responseQueues[conversationId.trim()]?.isNotEmpty ?? false);

  bool canRespondToQueuedResponse(String conversationId, int sequence) {
    final normalizedId = conversationId.trim();
    final queue = _responseQueues[normalizedId];
    return canResumeDingTalkQueuedResponse(
      serviceEnabled: isServiceEnabled,
      queuePaused: _pausedResponseQueueConversationIds.contains(normalizedId),
      responseActive: isConversationResponding(normalizedId),
      itemExists:
          queue != null && queue.any((item) => item.sequence == sequence),
    );
  }

  bool respondToQueuedResponse(String conversationId, int sequence) {
    final normalizedId = conversationId.trim();
    if (!canRespondToQueuedResponse(normalizedId, sequence)) return false;
    final queue = _responseQueues[normalizedId]!;
    if (!prioritizeDingTalkQueuedResponse(
      queue,
      (item) => item.sequence == sequence,
    )) {
      return false;
    }
    queue.first.manuallyPrioritized = true;
    _pausedResponseQueueConversationIds.remove(normalizedId);
    _responseErrors.remove(normalizedId);
    _scheduleResponseWorkers();
    _notify();
    return true;
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

  List<DingTalkQueuedResponse> queuedResponses(String conversationId) {
    final queue = _responseQueues[conversationId.trim()];
    if (queue == null || queue.isEmpty) {
      return const <DingTalkQueuedResponse>[];
    }
    return List<DingTalkQueuedResponse>.unmodifiable(
      queue.map(
        (item) => DingTalkQueuedResponse(
          sequence: item.sequence,
          sourceMessageId: item.sourceMessageId,
          content: item.content,
          scheduledAt: item.scheduledAt,
        ),
      ),
    );
  }

  bool removeQueuedResponse(String conversationId, int sequence) {
    final normalizedId = conversationId.trim();
    final queue = _responseQueues[normalizedId];
    if (queue == null || queue.isEmpty) return false;
    final item = queue
        .where((candidate) => candidate.sequence == sequence)
        .firstOrNull;
    if (item == null) return false;
    queue.remove(item);
    if (queue.isEmpty) {
      _responseQueues.remove(normalizedId);
      _pausedResponseQueueConversationIds.remove(normalizedId);
    }
    final conversation = _conversations[normalizedId];
    if (conversation != null) {
      _setMessageAiResponseState(
        conversation,
        item.sourceMessageId,
        DingTalkMessageAiResponseState.cancelled,
      );
    }
    item.complete();
    _scheduleResponseWorkers();
    _notify();
    return true;
  }

  bool moveQueuedResponse(String conversationId, int from, int to) {
    final queue = _responseQueues[conversationId.trim()];
    if (queue == null ||
        from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to >= queue.length ||
        from == to) {
      return false;
    }
    final ordered = queue.toList(growable: true);
    final item = ordered.removeAt(from);
    ordered.insert(to, item);
    queue
      ..clear()
      ..addAll(ordered);
    _notify();
    return true;
  }

  Future<void> stopConversationResponse(String conversationId) async {
    if (_disposed) return;
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) return;
    if (_responseQueues[normalizedId]?.isNotEmpty ?? false) {
      _pausedResponseQueueConversationIds.add(normalizedId);
    }
    final mediaCancellation = _activeMediaGenerationCancellations.remove(
      normalizedId,
    );
    if (mediaCancellation != null && !mediaCancellation.isCompleted) {
      mediaCancellation.complete();
    }
    final nextVersion = (_responseCancellationVersions[normalizedId] ?? 0) + 1;
    _responseCancellationVersions[normalizedId] = nextVersion;
    final conversation = _conversations[normalizedId];
    final sessionId = conversation?.aiSessionId;
    if (sessionId == null || !_sessionController.canStopResponding(sessionId)) {
      _responseInFlight.remove(normalizedId);
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
      _responseInFlight.remove(normalizedId);
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
    if (!isServiceEnabled) {
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
    if (conversation == null || !isServiceEnabled) return;
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
          !isServiceEnabled ||
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
    if (!isServiceEnabled) return null;
    final normalizedConversationId = conversationId.trim();
    final normalizedMessageId = normalizeDingTalkMessageId(messageId);
    final conversation = _conversations[normalizedConversationId];
    if (conversation == null) return null;
    final message = conversation.messages
        .where(
          (item) => normalizeDingTalkMessageId(item.id) == normalizedMessageId,
        )
        .firstOrNull;
    if (message == null || message.contextualMedia.isEmpty) return message;
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
          hydrated.contextualMedia.any((item) => item.localPath.trim().isEmpty),
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
        unawaited(_mediaHydrationTasks.remove(taskKey));
        _notify();
      }
    }
  }

  Future<DingTalkGatewayMedia> saveMessageMedia({
    required String conversationId,
    required String messageId,
    required DingTalkGatewayMedia media,
    required String destinationPath,
  }) async {
    if (!isServiceEnabled) {
      throw StateError('钉钉消息服务未启用。');
    }
    final normalizedConversationId = conversationId.trim();
    final normalizedMessageId = normalizeDingTalkMessageId(messageId);
    final resourceId = normalizeDingTalkResourceId(media.resourceId);
    final targetPath = destinationPath.trim();
    final conversation = _conversations[normalizedConversationId];
    if (conversation == null ||
        normalizedMessageId.isEmpty ||
        resourceId.isEmpty ||
        targetPath.isEmpty) {
      throw StateError('钉钉文件保存参数不完整。');
    }

    bool matches(DingTalkGatewayMedia item) =>
        item.resourceType == media.resourceType &&
        normalizeDingTalkResourceId(item.resourceId) == resourceId;

    final message = conversation.messages
        .where(
          (item) => normalizeDingTalkMessageId(item.id) == normalizedMessageId,
        )
        .firstOrNull;
    final sourceMedia = message?.contextualMedia.where(matches).firstOrNull;
    if (message == null || sourceMedia == null) {
      throw StateError('钉钉文件消息已失效，请刷新后重试。');
    }

    var sourcePath = sourceMedia.localPath.trim();
    final hasCachedSource =
        sourcePath.isNotEmpty &&
        await File(
          sourcePath,
        ).exists().timeout(defaultBoundedFileReadIdleTimeout);
    if (!hasCachedSource) {
      sourcePath =
          await _service.ensureMediaCached(sourceMedia, forceRetry: true) ?? '';
    }
    if (sourcePath.isEmpty) {
      throw const FileSystemException('钉钉文件下载失败，请稍后重试。');
    }

    final source = File(sourcePath);
    final sourceStat = await source.stat().timeout(
      defaultBoundedFileReadIdleTimeout,
    );
    if (sourceStat.type != FileSystemEntityType.file || sourceStat.size <= 0) {
      throw FileSystemException('钉钉文件不存在或内容为空。', sourcePath);
    }
    final target = File(p.normalize(p.absolute(targetPath)));
    if (!p.equals(p.normalize(p.absolute(source.path)), target.path)) {
      await copyFileAtomically(source, target, maxBytes: sourceStat.size);
    }

    DingTalkGatewayMedia savedMedia(DingTalkGatewayMedia item) =>
        item.copyWith(localPath: target.path, sizeBytes: sourceStat.size);
    final saved = savedMedia(sourceMedia);
    if (_disposed) return saved;

    final latestConversation = _conversations[normalizedConversationId];
    if (latestConversation == null) return saved;
    final index = latestConversation.messages.indexWhere(
      (item) => normalizeDingTalkMessageId(item.id) == normalizedMessageId,
    );
    if (index < 0 ||
        !latestConversation.messages[index].contextualMedia.any(matches)) {
      return saved;
    }

    final current = latestConversation.messages[index];
    final quotedMessage = current.quotedMessage;
    final updated = current.copyWith(
      media: current.media
          .map((item) => matches(item) ? savedMedia(item) : item)
          .toList(growable: false),
      quotedMessage: quotedMessage?.copyWith(
        media: quotedMessage.media
            .map((item) => matches(item) ? savedMedia(item) : item)
            .toList(growable: false),
      ),
      forwardedMessages: current.forwardedMessages
          .map(
            (item) => item.copyWith(
              media: item.media
                  .map((child) => matches(child) ? savedMedia(child) : child)
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
    latestConversation.messages[index] = updated;
    _mediaHydrationFailures.remove(normalizedMessageId);
    _queuePersist();
    _notify();
    return updated.contextualMedia.firstWhere(matches);
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
    final directResult = await _hydrateMediaItems(
      message.media,
      content: message.content,
      forceRetry: forceRetry,
    );
    final quotedMessage = message.quotedMessage;
    final quotedResult = quotedMessage == null
        ? null
        : await _hydrateMediaItems(
            quotedMessage.media,
            content: quotedMessage.content,
            forceRetry: forceRetry,
          );
    if (!directResult.changed && quotedResult?.changed != true) return message;
    final hydrated = message.copyWith(
      media: directResult.media,
      quotedMessage: quotedMessage?.copyWith(media: quotedResult?.media),
    );
    if (!identical(_conversations[conversation.id], conversation)) {
      return hydrated;
    }
    final normalizedMessageId = normalizeDingTalkMessageId(message.id);
    final index = conversation.messages.indexWhere(
      (item) => normalizeDingTalkMessageId(item.id) == normalizedMessageId,
    );
    if (index >= 0) {
      final current = conversation.messages[index];
      final currentQuoted = current.quotedMessage;
      final hydratedQuoted = hydrated.quotedMessage;
      final updated = current.copyWith(
        media: mergeDingTalkMediaCache(hydrated.media, current.media),
        quotedMessage: hydratedQuoted?.copyWith(
          media: currentQuoted == null
              ? hydratedQuoted.media
              : mergeDingTalkMediaCache(
                  hydratedQuoted.media,
                  currentQuoted.media,
                ),
        ),
      );
      conversation.messages[index] = updated;
      _queuePersist();
      _notify();
      return updated;
    }
    return hydrated;
  }

  Future<({List<DingTalkGatewayMedia> media, bool changed})> _hydrateMediaItems(
    List<DingTalkGatewayMedia> source, {
    required String content,
    required bool forceRetry,
  }) async {
    var changed = false;
    final media = <DingTalkGatewayMedia>[];
    for (final sourceItem in source) {
      if (isDingTalkResourceIdInUrlQuery(
        content,
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
        final sizeBytes = await probeFileSizeBounded(File(currentPath));
        if (sizeBytes != null && sizeBytes > 0) {
          final next = item.sizeBytes > 0
              ? item
              : item.copyWith(sizeBytes: sizeBytes);
          media.add(next);
          if (!identical(next, item)) changed = true;
          continue;
        }
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
      var sizeBytes = item.sizeBytes;
      if (sizeBytes <= 0 && path != null && path.trim().isNotEmpty) {
        sizeBytes = await probeFileSizeBounded(File(path)) ?? sizeBytes;
      }
      final next = path == null || path.trim().isEmpty
          ? item.copyWith(localPath: '')
          : item.copyWith(localPath: path, sizeBytes: sizeBytes);
      media.add(next);
      if (next.localPath != sourceItem.localPath ||
          next.resourceId != sourceItem.resourceId ||
          next.sizeBytes != sourceItem.sizeBytes) {
        changed = true;
      }
    }
    return (media: media, changed: changed);
  }

  Future<Object?> loadConversationDetails(String conversationId) async {
    if (!isServiceEnabled) return null;
    final conversation = _conversations[conversationId];
    if (conversation == null) return null;
    return _service.conversationDetails(conversation: conversation);
  }

  Future<bool> updateMessageFeedback(
    String conversationId,
    String messageId,
    DingTalkGatewayMessageFeedback? feedback,
  ) async {
    if (!isServiceEnabled) return false;
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
      _normalizeConversationMessages(conversation);
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
    if (!isServiceEnabled) return false;
    final conversation = _conversations[conversationId];
    if (conversation == null) return false;
    final normalizedMessageId = messageId.trim();
    final index = conversation.messages.indexWhere(
      (message) => message.id == normalizedMessageId,
    );
    if (index < 0) return false;
    final current = conversation.messages[index];
    if (current.isAssistant || current.recalled || current.isAutomaticReply) {
      return false;
    }
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

  bool setForwardedMessageAiContextIgnored(
    String conversationId,
    String messageId,
    DingTalkForwardedMessage forwardedMessage,
    bool ignored,
  ) {
    if (!isServiceEnabled) return false;
    final conversation = _conversations[conversationId];
    if (conversation == null) return false;
    final messageIndex = conversation.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) return false;
    final current = conversation.messages[messageIndex];
    if (current.isAssistant || current.recalled) return false;
    final forwardedIndex = current.forwardedMessages.indexWhere(
      (item) => _sameForwardedMessageIdentity(item, forwardedMessage),
    );
    if (forwardedIndex < 0) return false;
    final item = current.forwardedMessages[forwardedIndex];
    if (item.ignoredForAiContext == ignored) return true;
    final forwardedMessages = List<DingTalkForwardedMessage>.from(
      current.forwardedMessages,
    );
    forwardedMessages[forwardedIndex] = item.copyWith(
      ignoredForAiContext: ignored,
    );
    conversation.messages[messageIndex] = current.copyWith(
      forwardedMessages: forwardedMessages.toList(growable: false),
    );
    _queuePersist();
    _clearError();
    _notify();
    if (ignored) {
      _cancelResponseUsingExcludedMessage(conversationId, messageId);
    }
    return true;
  }

  Future<DingTalkMessageAuditSnapshot?> loadMessageAuditSnapshot(
    String conversationId,
    String messageId,
  ) async {
    if (!isServiceEnabled) return null;
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
    if (!isServiceEnabled ||
        !identical(_conversations[conversationId], conversation)) {
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
      var repairedMessageIdentities = false;
      var repairedResponseStates = false;
      for (final conversation in _conversations.values) {
        repairedMessageIdentities =
            _normalizeConversationMessages(conversation) ||
            repairedMessageIdentities;
        for (var index = 0; index < conversation.messages.length; index++) {
          final message = conversation.messages[index];
          if (message.aiResponseState !=
                  DingTalkMessageAiResponseState.queued &&
              message.aiResponseState !=
                  DingTalkMessageAiResponseState.responding) {
            continue;
          }
          conversation.messages[index] = message.copyWith(
            aiResponseState: DingTalkMessageAiResponseState.cancelled,
          );
          repairedResponseStates = true;
        }
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
      if (repairedMessageIdentities ||
          repairedResponseStates ||
          repairedEchoContent ||
          repairedOutgoingEchoes) {
        _queuePersist();
      }
    } catch (error, stack) {
      _setError('初始化钉钉消息网关', error, stack);
    } finally {
      _initialized = true;
      _notify();
    }
  }

  Future<bool> _restorePersistedAiEchoContent() async {
    var changed = false;
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
            source?.kind == AiSessionMessageKind.hook ||
            source?.kind.isToolResultKind == true ||
            source != null && _isToolEchoArtifact(source)) {
          if (message.responseEchoType ==
              DingTalkResponseEchoType.finalResponse) {
            conversation.messages.removeAt(index);
            index--;
            changed = true;
          }
          continue;
        }
        if (source == null && _isMalformedPersistedToolEcho(message)) {
          conversation.messages.removeAt(index);
          index--;
          changed = true;
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
            source.kind == AiSessionMessageKind.hook ||
            source.kind.isToolResultKind ||
            _isToolEchoArtifact(source)) {
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
    return changed || results.any((itemChanged) => itemChanged);
  }

  bool _isMalformedPersistedToolEcho(DingTalkGatewayMessage message) {
    return message.isAssistant &&
        message.sourceAiMessageId.trim().isNotEmpty &&
        message.responseEchoType == DingTalkResponseEchoType.finalResponse &&
        _toolEchoArtifactPattern.hasMatch(message.content.trimLeft());
  }

  Future<void> refreshAuthStatus({Future<void>? cancelSignal}) async {
    try {
      final next = await _service.authStatus(cancelSignal: cancelSignal);
      final previousIdentity = _authStatus.identity;
      final nextIdentity = next.identity;
      if (previousIdentity.userId != nextIdentity.userId ||
          previousIdentity.openDingTalkId != nextIdentity.openDingTalkId ||
          previousIdentity.name != nextIdentity.name) {
        _selfSenderIds.clear();
        _outgoingEchoContentSnapshots.clear();
      }
      _authStatus = next;
      if (_repairPersistedMessageOwnership()) _queuePersist();
      if (!_authStatus.authenticated && _isPolling) {
        unawaited(stopPolling());
      }
      _clearError();
    } catch (error, stack) {
      if (error is DingTalkGatewayCommandException && error.isCancelled) {
        return;
      }
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
    await _cancelMediaDownloads();
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
    final previousSettings = _settings;
    final previousTargets = _eventSubscriptionTargetKeys(_settings);
    final normalized = _normalizeSettings(value);
    if (_settings.templateId != normalized.templateId) {
      for (final conversation in _conversations.values) {
        conversation.aiSessionId = null;
        conversation.aiContextCheckpointMessageId = null;
      }
    }
    _settings = normalized;
    await _cancelDisallowedAutomaticResponses();
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
    _enqueueNewlyAllowedAutomaticResponses(previousSettings);
    _notify();
  }

  /// 刷新设置弹窗中的指定资源目录，避免影响其他资源的加载状态与选择。
  Future<void> refreshResourceCatalog(
    DingTalkGatewayResourceCatalog catalog,
  ) async {
    switch (catalog) {
      case DingTalkGatewayResourceCatalog.mcp:
        await _mcpController.refresh();
        await _mcpController.ensureRuntimeToolCatalogs(
          maxWait: const Duration(seconds: 6),
        );
      case DingTalkGatewayResourceCatalog.skills:
        await _skillsController.refresh();
      case DingTalkGatewayResourceCatalog.memories:
        await _memoryController.refresh();
      case DingTalkGatewayResourceCatalog.instructions:
        await _instructionsController.refresh();
      case DingTalkGatewayResourceCatalog.knowledgeBase:
        await _knowledgeBaseController?.initialize();
      case DingTalkGatewayResourceCatalog.workflows:
        await _workflowsController.refresh();
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
    _lastPollAt = startedAt.subtract(_queryOverlap);
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
    _cancelActivePoll();
    _pollStartedAt = null;
    _pollingGeneration++;
    final pollingGeneration = _pollingGeneration;
    final cancelResponses = _cancelObsoleteAutomaticResponses();
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
    _outgoingEchoContentSnapshots.clear();
    _selfSenderIds.clear();
    _eventRestartQueued = false;
    _notify();
    late final Future<void> task;
    task =
        Future.wait<void>(<Future<void>>[
          _stopEventListening(pollingGeneration: pollingGeneration),
          cancelResponses,
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
        !isServiceEnabled ||
        !isAuthorized ||
        _isSending ||
        _editingMessageInFlight ||
        isResponseQueuePaused(conversationId) ||
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
        !isServiceEnabled) {
      return false;
    }
    final files = <({String path, FileStat stat})>[];
    try {
      for (final path in paths) {
        final file = File(path);
        final stat = await file.stat().timeout(
          defaultBoundedFileReadIdleTimeout,
        );
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
      for (final entry in files) {
        if (!isServiceEnabled) return false;
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
        if (!isServiceEnabled) return false;
        _rememberRemoteConversationId(conversation, sent?.conversationId);
        _bindSentMessageId(conversation, localMessage, sent?.messageId);
      }
      if (content.isNotEmpty) {
        if (!isServiceEnabled) return false;
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
        if (!isServiceEnabled) return false;
        _rememberRemoteConversationId(conversation, sent?.conversationId);
        _bindSentMessageId(conversation, localMessage, sent?.messageId);
      }
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
    if (!isServiceEnabled || conversation == null || normalizedPath.isEmpty) {
      return false;
    }
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
        !isServiceEnabled) {
      return false;
    }
    final file = File(normalizedPath);
    if (!await file.exists().timeout(defaultBoundedFileReadIdleTimeout)) {
      return false;
    }
    final rawName = p.basename(normalizedPath).trim();
    final name = rawName.isEmpty ? (audio ? '语音.m4a' : '文件') : rawName;
    final kind = audio
        ? DingTalkMediaKind.audio
        : DingTalkMediaKindX.fromFileName(name);
    final stat = await file.stat().timeout(defaultBoundedFileReadIdleTimeout);
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
    _rememberUnresolvedOutgoingMessage(message.id);
    _appendMessage(conversation, message);
    _notify();
    try {
      if (!isServiceEnabled) return false;
      final sent = await _service.sendFileWithDetails(
        conversation: conversation,
        filePath: normalizedPath,
        audio: audio,
        uuid: _uuid.v4(),
      );
      if (!isServiceEnabled) return false;
      _rememberRemoteConversationId(conversation, sent?.conversationId);
      _bindSentMessageId(conversation, message, sent?.messageId);
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
        !isServiceEnabled) {
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
        if (!isServiceEnabled) return false;
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
      if (!isServiceEnabled ||
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
          : mergeDingTalkMediaCache(local.media, remote.media),
      quotedMessage: remote.quotedMessage,
      fromSelf:
          local.fromSelf || remote.fromSelf || _isGeneratedMediaLocalEcho(local)
          ? true
          : null,
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
    final id = normalizeDingTalkMessageId(remoteMessageId);
    final localMessageId = normalizeDingTalkMessageId(localMessage.id);
    final localIndex = conversation.messages.indexWhere(
      (message) => normalizeDingTalkMessageId(message.id) == localMessageId,
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
    if (id == normalizeDingTalkMessageId(outgoing.id)) return outgoing;
    final remoteIndex = conversation.messages.indexWhere(
      (message) =>
          normalizeDingTalkMessageId(message.id) == id &&
          normalizeDingTalkMessageId(message.id) !=
              normalizeDingTalkMessageId(outgoing.id),
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
        (message) =>
            normalizeDingTalkMessageId(message.id) ==
            normalizeDingTalkMessageId(outgoing.id),
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
    final pollCancellation = Completer<void>();
    _activePollCancellation = pollCancellation;
    try {
      final now = DateTime.now();
      final queryStart = _lastPollAt.isBefore(now)
          ? _lastPollAt
          : now.subtract(_queryOverlap);
      final maxQueryEnd = queryStart.add(_queryWindow);
      final queryEnd = maxQueryEnd.isBefore(now) ? maxQueryEnd : now;
      Object? queryError;
      try {
        final result = await _service
            .query(
              start: queryStart,
              end: queryEnd,
              cancelSignal: pollCancellation.future,
            )
            .timeout(
              _pollQueryTimeout,
              onTimeout: () {
                if (!pollCancellation.isCompleted) {
                  pollCancellation.complete();
                }
                throw TimeoutException('钉钉消息轮询超过总时限。', _pollQueryTimeout);
              },
            );
        if (pollingGeneration != _pollingGeneration || !_isPolling) return;
        if (result.shouldAdvanceWindow) {
          _lastPollAt = queryEnd.subtract(_queryOverlap);
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
          _warningMessage = '钉钉网络暂时不可用，已保留同步窗口并将在稍后重试。';
          _clearError();
        } else {
          _setError('轮询钉钉消息', error, stack);
        }
      }
      if (pollingGeneration != _pollingGeneration || !_isPolling) return;
      _scheduleRecentConversationReconcileIfDue(now);
      if (queryError == null) {
        _clearError();
      } else if (queryError is! TimeoutException &&
          (queryError is! DingTalkGatewayCommandException ||
              !queryError.isRetryable)) {
        try {
          await refreshAuthStatus(
            cancelSignal: pollCancellation.future,
          ).timeout(
            _pollAuthStatusTimeout,
            onTimeout: () {
              if (!pollCancellation.isCompleted) pollCancellation.complete();
            },
          );
        } on TimeoutException {
          if (_isPolling && pollingGeneration == _pollingGeneration) {
            _warningMessage = '钉钉授权状态暂时无法确认，下一轮将继续检查。';
          }
        }
        if (!isAuthorized) await stopPolling();
      }
    } finally {
      if (identical(_activePollCancellation, pollCancellation)) {
        _activePollCancellation = null;
      }
      _pollInFlight = false;
      if (!_disposed && _isPolling && pollingGeneration != _pollingGeneration) {
        unawaited(_pollOnce());
      }
      _notify();
    }
  }

  void _cancelActivePoll() {
    final cancellation = _activePollCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
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

  void _scheduleRecentConversationReconcileIfDue([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (current.isBefore(_nextConversationReconcileAt)) return;
    _nextConversationReconcileAt = current.add(_conversationReconcileInterval);
    _scheduleRecentConversationReconcile();
  }

  Future<void> _reconcileRecentConversations() async {
    final conversations =
        _conversations.values
            .where((conversation) => conversation.id.trim().isNotEmpty)
            .toList(growable: true)
          ..sort(compareDingTalkConversationsByRecent);
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
    if (active != null) {
      _eventRestartQueued = true;
      return active;
    }
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
      if (!identical(_eventRestartFuture, task)) return;
      _eventRestartFuture = null;
      final restartQueued = _eventRestartQueued;
      _eventRestartQueued = false;
      if (restartQueued &&
          _isPolling &&
          !_usingPollingFallback &&
          !_disposed &&
          pollingGeneration == _pollingGeneration) {
        unawaited(_restartEventListening());
      }
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
        normalizeDingTalkOutgoingEchoContentForComparison(incomingContent);
    final incomingSenderId = incoming.senderId.trim();
    final incomingSenderOpenDingTalkId = incoming.senderOpenDingTalkId.trim();
    final incomingIsSelf = _isSelf(incoming);
    final incomingIdentityUnresolved =
        !incomingIsSelf && _isIncomingIdentityUnresolved(incoming);
    if (!incomingIsSelf && !incomingIdentityUnresolved) return false;
    var localIndex = -1;
    Duration? closestAge;
    for (final entry in conversation.messages.asMap().entries) {
      final local = entry.value;
      final unresolvedOutgoing = _unresolvedOutgoingMessageIds.contains(
        local.id,
      );
      if (!local.fromSelf ||
          !unresolvedOutgoing ||
          local.id == incomingId ||
          local.conversationType != incoming.conversationType) {
        continue;
      }
      final age = incoming.createdAt.difference(local.createdAt).abs();
      if (age > _outgoingEchoWindow) continue;
      final sameContent =
          incomingContentComparison.isNotEmpty &&
          (_matchesOutgoingEchoContent(local, incomingContentComparison) ||
              _sharesDingTalkToolCallIdentity(local, incoming));
      final sameMedia = matchesDingTalkOutgoingMedia(
        local.media,
        incoming.media,
        incomingContent,
      );
      if (!canMergeDingTalkOutgoingEcho(
        incomingIsSelf: incomingIsSelf,
        incomingIdentityUnresolved: incomingIdentityUnresolved,
        unresolvedOutgoing: unresolvedOutgoing,
        sameContent: sameContent,
        sameMedia: sameMedia,
        withinUnverifiedMatchWindow: age <= _unverifiedOutgoingEchoWindow,
      )) {
        continue;
      }
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
    if (incomingSenderOpenDingTalkId.isNotEmpty) {
      _selfSenderIds.add(incomingSenderOpenDingTalkId);
    }
    _remember(incomingId);
    _queuePersist();
    return true;
  }

  int _collapseOutgoingEchoDuplicates(DingTalkConversation conversation) {
    final localIds = conversation.messages
        .where(
          (message) =>
              (message.fromSelf || _isGeneratedMediaLocalEcho(message)) &&
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
          normalizeDingTalkOutgoingEchoContentForComparison(local.content);
      var remoteIndex = -1;
      Duration? closestAge;
      for (final entry in conversation.messages.asMap().entries) {
        final remote = entry.value;
        final remoteIsSelf = _isSelf(remote);
        final remoteIdentityUnresolved = _isIncomingIdentityUnresolved(remote);
        if (entry.key == localIndex ||
            remote.isAssistant ||
            (!remoteIsSelf && !remoteIdentityUnresolved) ||
            _isTemporaryMessageId(remote.id) ||
            remote.conversationType != local.conversationType) {
          continue;
        }
        final age = remote.createdAt.difference(local.createdAt).abs();
        if (age > _outgoingEchoWindow) continue;
        final remoteContentComparison =
            normalizeDingTalkOutgoingEchoContentForComparison(remote.content);
        final sameContent =
            remoteContentComparison.isNotEmpty &&
            (remoteContentComparison == localContentComparison ||
                _matchesOutgoingEchoContent(local, remoteContentComparison) ||
                _sharesDingTalkToolCallIdentity(local, remote));
        if (!remoteIsSelf &&
            (!sameContent || age > _unverifiedOutgoingEchoWindow)) {
          continue;
        }
        if (!sameContent &&
            !matchesDingTalkOutgoingMedia(
              local.media,
              remote.media,
              remote.content,
            )) {
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
      final remoteSenderId = remote.senderId.trim();
      final remoteSenderOpenDingTalkId = remote.senderOpenDingTalkId.trim();
      if (remoteSenderId.isNotEmpty) _selfSenderIds.add(remoteSenderId);
      if (remoteSenderOpenDingTalkId.isNotEmpty) {
        _selfSenderIds.add(remoteSenderOpenDingTalkId);
      }
      _remember(remote.id);
      removedCount++;
    }
    return removedCount;
  }

  bool _matchesOutgoingEchoContent(
    DingTalkGatewayMessage local,
    String incomingComparison,
  ) {
    if (incomingComparison.isEmpty) return false;
    if (normalizeDingTalkOutgoingEchoContentForComparison(local.content) ==
            incomingComparison ||
        normalizeDingTalkOutgoingEchoContentForComparison(
              _dingTalkRemoteEchoText(local.content),
            ) ==
            incomingComparison) {
      return true;
    }
    final sourceId = local.sourceAiMessageId.trim();
    return sourceId.isNotEmpty &&
        (_outgoingEchoContentSnapshots[sourceId]?.contains(
              incomingComparison,
            ) ??
            false);
  }

  bool _sharesDingTalkToolCallIdentity(
    DingTalkGatewayMessage local,
    DingTalkGatewayMessage remote,
  ) {
    if (!local.isToolCallEcho) return false;
    final localId = _dingTalkToolCallIdentityPattern
        .firstMatch(local.content)
        ?.group(0)
        ?.toLowerCase();
    if (localId == null || localId.isEmpty) return false;
    return _dingTalkToolCallIdentityPattern
        .allMatches(remote.content)
        .any((match) => match.group(0)?.toLowerCase() == localId);
  }

  bool _isGeneratedMediaLocalEcho(DingTalkGatewayMessage message) {
    return message.id.startsWith('assistant-media-') &&
        message.isAssistant &&
        message.media.isNotEmpty;
  }

  void _handleIncomingMessage(
    DingTalkGatewayMessage message, {
    bool allowResponse = true,
    bool allowHistorical = false,
  }) {
    if (!isServiceEnabled) return;
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
      if (!allowHistorical && normalizedMessage.contextualMedia.isNotEmpty) {
        unawaited(_cacheIncomingMedia(incomingConversation, normalizedMessage));
      }
      _notify();
      return;
    }
    final subscriptionTargetUpdated =
        incomingConversation != null &&
        _updateDirectConversationPeerIdentity(
          incomingConversation,
          normalizedMessage,
        );
    final pendingRecall = _pendingRecalledMessageIds.remove(messageId);
    final incoming = pendingRecall && !normalizedMessage.recalled
        ? normalizedMessage.copyWith(recalled: true)
        : normalizedMessage;
    final existingConversation = _conversationContainingMessage(messageId);
    if (existingConversation != null) {
      _mergeQueriedMessage(existingConversation, incoming);
      _applyPendingStatusEvents(existingConversation, messageId);
      _remember(messageId);
      if (!allowHistorical && incoming.contextualMedia.isNotEmpty) {
        unawaited(_cacheIncomingMedia(existingConversation, incoming));
      }
      final current = existingConversation.messages
          .where((item) => normalizeDingTalkMessageId(item.id) == messageId)
          .firstOrNull;
      // 对账可能先以“只同步”模式写入消息。后续实时事件或轮询到达时，
      // 只要仍未调度就幂等补入队，避免依赖 @ 标记必须发生一次状态跳变。
      if (current != null &&
          current.aiResponseState == DingTalkMessageAiResponseState.none &&
          _shouldAutomaticallyRespondToMessage(
            current,
            allowResponse: allowResponse,
          )) {
        _enqueueIncomingMessage(existingConversation, current);
      }
      if (subscriptionTargetUpdated &&
          _isPolling &&
          !_usingPollingFallback &&
          _eventSubscription != null) {
        unawaited(_restartEventListening());
      }
      return;
    }
    // 轮询返回的本人消息可能来自未打开的会话；只有已配置目标的会话才允许建档，
    // 避免全量搜索把无关历史会话写入左侧列表。
    final localConversation = _conversationForIncomingMessage(incoming);
    final allowedTarget = _targetForIncomingMessage(
      incoming,
      localConversation,
    );
    if (allowedTarget == null) return;
    final isSelf = _isSelf(incoming);
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
    final peerIdentityUpdated = _updateDirectConversationPeerIdentity(
      conversation,
      incoming,
    );
    _appendMessage(conversation, incoming);
    if (createdConversation) {
      _pendingInitialContextHydration.add(conversation.id);
    }
    _applyPendingStatusEvents(conversation, messageId);
    if (allowResponse && !isSelf) {
      _unreadCount += 1;
      if (_settings.reminderMode == DingTalkReminderMode.sound) {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
    }
    if (!allowHistorical &&
        incoming.contextualMedia.isNotEmpty &&
        !shouldRespond) {
      unawaited(_cacheIncomingMedia(conversation, incoming));
    }
    if (shouldRespond) {
      _enqueueIncomingMessage(conversation, incoming);
    }
    if ((createdConversation ||
            subscriptionTargetUpdated ||
            peerIdentityUpdated) &&
        _isPolling &&
        !_usingPollingFallback &&
        _eventSubscription != null) {
      unawaited(_restartEventListening());
    }
    _notify();
  }

  bool _updateDirectConversationPeerIdentity(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (conversation.type != DingTalkConversationType.direct ||
        message.conversationType != DingTalkConversationType.direct ||
        _isSelf(message)) {
      return false;
    }
    final openDingTalkId = message.senderOpenDingTalkId.trim();
    final senderId = message.senderId.trim();
    final userId = senderId == openDingTalkId ? '' : senderId;
    var changed = false;
    if (openDingTalkId.isNotEmpty &&
        conversation.directOpenDingTalkId?.trim() != openDingTalkId) {
      conversation.directOpenDingTalkId = openDingTalkId;
      changed = true;
    }
    if (openDingTalkId.isNotEmpty &&
        conversation.directUserId?.trim() == openDingTalkId) {
      conversation.directUserId = null;
      changed = true;
    }
    if (userId.isNotEmpty && conversation.directUserId?.trim() != userId) {
      conversation.directUserId = userId;
      changed = true;
    }
    if (changed) _queuePersist();
    return changed;
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
    final remoteQuotedMessage = remote.quotedMessage;
    final currentQuotedMessage = current.quotedMessage;
    final quotedMessageChanged =
        remoteQuotedMessage != null &&
        (currentQuotedMessage == null ||
            !_sameQuotedMessage(currentQuotedMessage, remoteQuotedMessage));
    final automaticReplyChanged =
        remote.automaticReplyCard != null &&
        (current.messageType != remote.messageType ||
            jsonEncode(current.automaticReplyCard?.toJson()) !=
                jsonEncode(remote.automaticReplyCard!.toJson()));
    final mentionChanged =
        remote.mentionedCurrentUser && !current.mentionedCurrentUser;
    final readChanged = remote.readByPeer && !current.readByPeer;
    final remoteFromSelf = remote.fromSelf || _matchesCurrentIdentity(remote);
    final ownershipChanged =
        current.fromSelf != remoteFromSelf &&
        (remoteFromSelf || _hasResolvedOtherIdentity(remote));
    final reactions = remote.reactionSnapshotComplete
        ? remote.reactions
        : <String>{
            ...current.reactions,
            ...remote.reactions,
          }.take(kDingTalkMaxReactionTypes).toList(growable: false);
    final reactionsChanged = !listEquals(reactions, current.reactions);
    final reactionUsers = remote.reactionSnapshotComplete
        ? remote.reactionUsers
        : <String, List<String>>{
            for (final entry in current.reactionUsers.entries)
              entry.key: List<String>.from(entry.value),
            for (final entry in remote.reactionUsers.entries)
              entry.key: <String>{
                ...current.reactionUsers[entry.key] ?? const <String>[],
                ...entry.value,
              }.take(kDingTalkMaxReactionUsers).toList(growable: false),
          };
    final reactionUsersChanged =
        jsonEncode(reactionUsers) != jsonEncode(current.reactionUsers);
    if (!contentChanged &&
        !recalledChanged &&
        !mediaChanged &&
        !forwardedMessagesChanged &&
        !quotedMessageChanged &&
        !automaticReplyChanged &&
        !mentionChanged &&
        !readChanged &&
        !ownershipChanged &&
        !reactionsChanged &&
        !reactionUsersChanged) {
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
        ? mergeDingTalkMediaCache(current.media, remote.media)
        : null;
    if (mediaChanged) _mediaHydrationFailures.remove(remoteId);
    conversation.messages[index] = current.copyWith(
      content: contentChanged ? remote.content : null,
      messageType: automaticReplyChanged ? remote.messageType : null,
      automaticReplyCard: automaticReplyChanged
          ? remote.automaticReplyCard
          : null,
      media: media,
      quotedMessage: quotedMessageChanged
          ? remoteQuotedMessage.copyWith(
              media: currentQuotedMessage == null
                  ? remoteQuotedMessage.media
                  : mergeDingTalkMediaCache(
                      currentQuotedMessage.media,
                      remoteQuotedMessage.media,
                    ),
            )
          : null,
      forwardedMessages: forwardedMessagesChanged
          ? _preserveForwardedMessageState(
              current.forwardedMessages,
              remote.forwardedMessages,
            )
          : null,
      forwardedMessageCount: forwardedMessagesChanged
          ? remote.forwardedMessageCount
          : null,
      mentionedCurrentUser: mentionChanged ? true : null,
      readByPeer: readChanged ? true : null,
      fromSelf: ownershipChanged ? remoteFromSelf : null,
      recalled: recalledChanged ? true : null,
      reactions: reactionsChanged ? reactions : null,
      reactionUsers: reactionUsersChanged ? reactionUsers : null,
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

  bool _sameQuotedMessage(
    DingTalkQuotedMessage left,
    DingTalkQuotedMessage right,
  ) {
    return normalizeDingTalkMessageId(left.id) ==
            normalizeDingTalkMessageId(right.id) &&
        left.senderId == right.senderId &&
        left.senderName == right.senderName &&
        left.createdAt == right.createdAt &&
        normalizeDingTalkMessageContentForComparison(left.content) ==
            normalizeDingTalkMessageContentForComparison(right.content) &&
        _sameMedia(left.media, right.media);
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

  bool _sameForwardedMessageIdentity(
    DingTalkForwardedMessage left,
    DingTalkForwardedMessage right,
  ) {
    final leftId = normalizeDingTalkMessageId(left.id);
    final rightId = normalizeDingTalkMessageId(right.id);
    if (leftId.isNotEmpty && rightId.isNotEmpty) return leftId == rightId;
    return left.createdAt == right.createdAt &&
        left.senderId == right.senderId &&
        left.senderName == right.senderName &&
        normalizeDingTalkMessageContentForComparison(left.content) ==
            normalizeDingTalkMessageContentForComparison(right.content);
  }

  List<DingTalkForwardedMessage> _preserveForwardedMessageState(
    List<DingTalkForwardedMessage> current,
    List<DingTalkForwardedMessage> remote,
  ) {
    return remote
        .map((item) {
          final previous = current
              .where((value) => _sameForwardedMessageIdentity(value, item))
              .firstOrNull;
          return previous?.ignoredForAiContext == true
              ? item.copyWith(ignoredForAiContext: true)
              : item;
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
        final reaction = normalizeDingTalkReaction(event.reaction);
        if (reaction.isEmpty) return true;
        final reactions = List<String>.from(current.reactions);
        final reactionUsers = <String, List<String>>{
          for (final entry in current.reactionUsers.entries)
            entry.key: List<String>.from(entry.value),
        };
        final reactionUser = event.reactionUser.trim();
        if (event.reactionRemoved) {
          if (reactionUser.isEmpty) {
            reactions.remove(reaction);
            reactionUsers.remove(reaction);
          } else {
            final users = reactionUsers[reaction];
            users?.remove(reactionUser);
            if (users != null && users.isEmpty) {
              reactionUsers.remove(reaction);
              reactions.remove(reaction);
            }
          }
        } else if (!reactions.contains(reaction) &&
            reactions.length < kDingTalkMaxReactionTypes) {
          reactions.add(reaction);
        }
        if (!event.reactionRemoved && reactionUser.isNotEmpty) {
          final users = reactionUsers.putIfAbsent(reaction, () => <String>[]);
          if (!users.contains(reactionUser) &&
              users.length < kDingTalkMaxReactionUsers) {
            users.add(reactionUser);
          }
        }
        if (!listEquals(reactions, current.reactions) ||
            jsonEncode(reactionUsers) != jsonEncode(current.reactionUsers)) {
          updated = current.copyWith(
            reactions: reactions.toList(growable: false),
            reactionUsers: reactionUsers,
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
          item.reactionUser == event.reactionUser &&
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
          unawaited(_conversationReconcileTasks.remove(conversation.id));
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
        unawaited(_conversationReconcileTasks.remove(conversation.id));
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
    final recentConversations = _conversations.values.toList(growable: true)
      ..sort(compareDingTalkConversationsByRecent);
    final targets = <DingTalkConversationTarget>[
      ...effectiveSettings.allowedGroupTargets,
      ...effectiveSettings.allowedContactTargets,
      ...recentConversations.map(_eventTargetFromConversation),
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

  DingTalkConversationTarget _eventTargetFromConversation(
    DingTalkConversation conversation,
  ) {
    final target = _targetFromConversation(conversation);
    if (conversation.type != DingTalkConversationType.group) return target;
    final remoteId = conversation.dwsConversationId;
    if (remoteId.isEmpty || remoteId == target.id) return target;
    return DingTalkConversationTarget(
      id: remoteId,
      title: target.title,
      type: target.type,
      subtitle: target.subtitle,
      aliases: <String>{target.id, ...target.aliases}.toList(growable: false),
    );
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
          _isSkippedAiResponseMessage(message) ||
          message.contextualMedia.isEmpty) {
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
    final senderOpenDingTalkId = message.senderOpenDingTalkId.trim();
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
          identifiers.contains(senderOpenDingTalkId) ||
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
      message.senderOpenDingTalkId.trim(),
      message.conversationId.trim(),
    }..remove('');
    for (final target in _settings.allowedContactTargets) {
      if (target.identifiers.any(candidates.contains)) return target;
    }
    return null;
  }

  bool _canAutomaticallyRespondToMessage(DingTalkGatewayMessage message) {
    if (message.isAssistant ||
        message.fromSelf ||
        message.isExcludedFromAiContext ||
        message.conversationType == DingTalkConversationType.group &&
            !message.mentionedCurrentUser &&
            !_messageMentionsCurrentIdentity(message)) {
      return false;
    }
    return _settings.allowsAutomaticResponseFor(
      _targetFromIncomingMessage(message),
    );
  }

  void _enqueueNewlyAllowedAutomaticResponses(
    DingTalkGatewaySettings previousSettings,
  ) {
    if (!_isPolling) return;
    final pollingGeneration = _pollingGeneration;
    for (final conversation in _conversations.values) {
      final target = _targetFromConversation(conversation);
      if (previousSettings.allowsAutomaticResponseFor(target) ||
          !_settings.allowsAutomaticResponseFor(target)) {
        continue;
      }
      for (final message in conversation.messages) {
        if (message.aiResponseState != DingTalkMessageAiResponseState.none ||
            message.recalled ||
            !_canAutomaticallyRespondToMessage(message) ||
            !_isAutomaticResponseEligible(message, pollingGeneration)) {
          continue;
        }
        _enqueueIncomingMessage(conversation, message);
      }
    }
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
    final now = DateTime.now();
    final messageAt = message.createdAt;
    // 实时事件的业务时间偶尔会落后本机时钟数秒；仅拒绝明显早于启动前的历史消息，
    // 避免合法的刚到达消息因时钟偏差被静默丢弃。
    final isAfterPollingStart =
        startedAt != null &&
        !messageAt.isBefore(startedAt.subtract(const Duration(seconds: 30))) &&
        !messageAt.isAfter(now.add(const Duration(minutes: 2)));
    return _isPolling &&
        startedAt != null &&
        !_isSelf(message) &&
        (pollingGeneration == null ||
            pollingGeneration == _pollingGeneration) &&
        isAfterPollingStart;
  }

  DingTalkConversationTarget _targetFromIncomingMessage(
    DingTalkGatewayMessage message,
  ) {
    final conversationId = message.conversationId.trim();
    final senderOpenDingTalkId = message.senderOpenDingTalkId.trim();
    final senderId = message.senderId.trim();
    final userId = senderId == senderOpenDingTalkId ? '' : senderId;
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
          ? userId
          : '',
      openDingTalkId:
          message.conversationType == DingTalkConversationType.direct
          ? senderOpenDingTalkId
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
      (_) {
        // 全局消息查询可能较慢，打开会话的短周期对账独立触发，确保本人发送的消息
        // 不必等待下一次全量查询完成；任务自身仍由单飞和并发上限保护。
        _scheduleRecentConversationReconcileIfDue();
        return _pollOnce();
      },
      cancelOnCallbackTimeout: false,
      onError: (error, stack) {
        if (error is TimeoutException) _cancelActivePoll();
        silentLog('dingtalk_gateway', '执行钉钉轮询定时任务', error, stack);
      },
    );
    if (immediate) unawaited(_pollOnce());
  }

  bool _isResponseCancelled(String conversationId, int version) {
    return _disposed ||
        !isServiceEnabled ||
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
    if (!isServiceEnabled ||
        (automaticResponse &&
            (source == null ||
                !_canAutomaticallyRespondToMessage(source) ||
                !_isAutomaticResponseEligible(source, pollingGeneration))) ||
        !_responseInFlight.add(conversation.id)) {
      return;
    }
    var responseCompleted = false;
    _activeResponseContextMessageIds[conversation.id] = <String>{
      sourceMessageId,
    };
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    bool responseCancelled() =>
        _isResponseCancelled(conversation.id, responseVersion) ||
        (automaticResponse &&
            (source == null ||
                !_canAutomaticallyRespondToMessage(source) ||
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
      final enabledMultimodalCapabilities =
          _validMultimodalCapabilitiesForRuntime();
      final detectedMediaRequest = detectDingTalkMultimodalGenerationRequest(
        source == null ? content : _messageAiContextContent(source),
      );
      final mediaRequest =
          detectedMediaRequest != null &&
              enabledMultimodalCapabilities.contains(
                detectedMediaRequest.storageValue,
              )
          ? detectedMediaRequest
          : null;
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
            .ensureRuntimeToolCatalogs(
              maxWait: const Duration(seconds: 6),
              serverNames: _settings.allowedMcpServerNames,
            )
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
            (server) =>
                server.enabled &&
                _settings.allowedMcpServerNames.contains(server.name),
          )
          .toList(growable: false);
      final eagerMcpServerNames = _mcpController.matchedSmallRuntimeServerNames(
        query: source == null ? content : _messageAiContextContent(source),
        serverNames: selectedMcp.map((server) => server.name),
      );
      final eagerMcpTools = _resolvedEagerMcpTools(
        selectedMcp,
        eagerMcpServerNames.toSet(),
      );
      final expectedEagerMcpToolNames = eagerMcpTools
          .map((tool) => tool.name)
          .toSet();
      final selectedSkills = _skillsController.skills
          .where((skill) => _settings.allowedSkillNames.contains(skill.name))
          .toList(growable: false);
      final selectedWorkflows = _workflowsController.workflows
          .where(
            (workflow) =>
                workflow.enabled &&
                (_settings.allowedWorkflowIds.isEmpty ||
                    _settings.allowedWorkflowIds.contains(workflow.id)),
          )
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
        availableWorkflows: selectedWorkflows,
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
          if (eagerMcpServerNames.isNotEmpty)
            mcpEagerServerNamesMetadataKey: eagerMcpServerNames,
          'dingtalk_excluded_message_ids': conversation.messages
              .where((message) => message.isExcludedFromAiContext)
              .map((message) => message.id)
              .toList(growable: false),
          'dingtalk_working_directory_boundary': _settings.workingDirectory,
          'dingtalk_allowed_knowledge_source_ids': selectedKnowledgeSourceIds,
          'workflow_definitions_provider': () => _workflowsController.workflows,
          workflowCallSourceMetadataKey: 'dingtalk',
          'workflow_resources_provider':
              (
                WorkflowDefinition workflow,
                AiToolExecutionContext toolContext,
              ) async {
                final models = _settingsController.aiModels;
                if (models.isEmpty) return null;
                return WorkflowExecutionResources(
                  models: models,
                  templateRepository: _sessionController.templateRepository,
                  skills: selectedSkills,
                  memories: selectedMemory,
                  instructions: selectedInstructions,
                  knowledgeBaseController: _knowledgeBaseController,
                  mcpServers: selectedMcp,
                  mcpTools: <String, List<McpTool>>{
                    for (final server in selectedMcp)
                      server.name: _mcpController
                          .toolCatalogFor(server.name)
                          .tools,
                  },
                  codeRuntimes: workflowSystemCodeRuntimes(),
                );
              },
          'dingtalk_dws_executor': _executeDwsCommandForAi,
          'dingtalk_dws_selected_command_count': dwsCatalog.length,
          'dingtalk_multimodal_capabilities': enabledMultimodalCapabilities,
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
            nonBlankStringOr(
              _sessionController.lastErrorMessage,
              '创建钉钉 AI 会话失败，请查看运行日志。',
            ),
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
        expectToolActivity: selectedMcp.isNotEmpty || mediaRequest != null,
        isTypeEnabled: (type) => _settings.responseEchoTypes.contains(type),
        typeOf: (message, messages) {
          if (mediaRequest != null &&
              message.kind == AiSessionMessageKind.assistant) {
            return null;
          }
          return _echoTypeOf(message, messages);
        },
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
        resolveRemoteId: (sourceMessageId, sentText, taskId) =>
            _resolveEchoRemoteMessageId(
              conversation: conversation,
              sourceMessageId: sourceMessageId,
              sentText: sentText,
              taskId: taskId,
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
        final messageCountBeforeSend = currentSession()?.messages.length ?? 0;
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
            _responseCompletionReminder,
            if (mediaRequest != null) mediaRequest.routingReminder,
            if (selectedMcp.isNotEmpty)
              _dingTalkMcpRoutingReminder(selectedMcp, eagerMcpTools),
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
              nonBlankStringOr(
                _sessionController.lastErrorMessageForSession(sessionId),
                'AI 未返回响应，请检查模型配置与运行日志。',
              ),
            );
          }
          return;
        }
        if (responseCancelled()) return;
        if (expectedEagerMcpToolNames.isNotEmpty &&
            !_roundInvokedAnyTool(
              currentSession(),
              messageCountBeforeSend,
              expectedEagerMcpToolNames,
            )) {
          _setResponseError(conversation.id, 'AI 未调用已匹配的 MCP 工具，请重试。');
          return;
        }
        if (mediaRequest != null) {
          final roundState = _dingTalkMediaRoundState(
            currentSession(),
            messageCountBeforeSend,
            mediaRequest,
          );
          if (!roundState.attempted) {
            await _executeDingTalkMediaGenerationFallback(
              conversation: conversation,
              capability: mediaRequest,
              prompt: source == null
                  ? content.trim()
                  : _messageAiContextContent(source),
              referenceImagePaths: attachmentPaths,
              responseCancelled: responseCancelled,
            );
          } else if (!roundState.succeeded) {
            await _sendDingTalkMediaGenerationFailure(
              conversation: conversation,
              capability: mediaRequest,
              responseCancelled: responseCancelled,
            );
          }
          if (responseCancelled()) return;
        }
        if (sourceMessageId.trim().isNotEmpty &&
            identical(_conversations[conversation.id], conversation)) {
          final checkpointId =
              conversation.aiContextCheckpointMessageId?.trim() ?? '';
          final checkpointIndex = checkpointId.isEmpty
              ? -1
              : conversation.messages.indexWhere(
                  (message) => message.id == checkpointId,
                );
          final sourceIndex = conversation.messages.indexWhere(
            (message) => message.id == sourceMessageId,
          );
          if (sourceIndex > checkpointIndex) {
            conversation.aiContextCheckpointMessageId = sourceMessageId.trim();
            _queuePersist();
          }
        }
        responseCompleted = true;
      } finally {
        _sessionController.removeListener(onSessionChanged);
        if (!responseCancelled()) {
          // 请求失败时同样收敛：已流式发出的消息应停留在最后已生成内容，
          // 避免钉钉端留下与本地不一致的半途文本；未发送的正式响应仅在
          // 整轮成功后投递，失败场景统一发送明确的失败提示。
          final session = currentSession();
          if (session != null) {
            echoCoordinator.complete(
              session,
              includeUnsentFinalResponse: responseCompleted,
            );
          }
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
          if (echoCoordinator.hasDeliveryFailure) {
            responseCompleted = false;
            _responseFailureReplySuppressed.add(conversation.id);
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
      _setMessageAiResponseState(
        conversation,
        sourceMessageId,
        responseCancelled()
            ? DingTalkMessageAiResponseState.cancelled
            : responseCompleted
            ? DingTalkMessageAiResponseState.responded
            : _responseErrors.containsKey(conversation.id)
            ? DingTalkMessageAiResponseState.failed
            : DingTalkMessageAiResponseState.cancelled,
      );
      _responseInFlight.remove(conversation.id);
      _activeResponseContextMessageIds.remove(conversation.id);
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
              !_isSkippedAiResponseMessage(message) &&
              _messageAiContextContent(message).isNotEmpty,
        )
        .toList(growable: false);
  }

  bool _isSkippedAiResponseMessage(DingTalkGatewayMessage message) {
    return switch (message.aiResponseState) {
      DingTalkMessageAiResponseState.rejected ||
      DingTalkMessageAiResponseState.dropped ||
      DingTalkMessageAiResponseState.cancelled ||
      DingTalkMessageAiResponseState.failed => true,
      DingTalkMessageAiResponseState.none ||
      DingTalkMessageAiResponseState.queued ||
      DingTalkMessageAiResponseState.responding ||
      DingTalkMessageAiResponseState.responded => false,
    };
  }

  String _messageAiContextContent(DingTalkGatewayMessage message) {
    final buffer = StringBuffer();
    final quoted = message.quotedMessage;
    if (quoted != null) {
      final sender = quoted.senderName.trim().isEmpty
          ? '用户'
          : quoted.senderName.trim();
      final sanitizedContent = _sanitizeDingTalkVisibleText(quoted.content);
      final text = sanitizedContent.trim().isNotEmpty
          ? sanitizedContent.trim()
          : quoted.media.map((media) => '[${media.displayName}]').join(' ');
      if (text.isNotEmpty) buffer.writeln('引用消息（$sender）：$text');
    }
    if (!message.isForwardedChatRecord) {
      final content = _sanitizeDingTalkVisibleText(message.content).trim();
      if (content.isNotEmpty) {
        buffer.write(quoted == null ? content : '当前消息：$content');
      }
    } else {
      buffer.writeln('转发的聊天记录（共 ${message.forwardedMessageCount} 条）：');
      for (final item in message.forwardedMessages) {
        if (item.ignoredForAiContext) continue;
        final sender = item.senderName.trim().isEmpty
            ? '用户'
            : item.senderName.trim();
        final sanitizedContent = _sanitizeDingTalkVisibleText(item.content);
        final text = sanitizedContent.trim().isNotEmpty
            ? sanitizedContent.trim()
            : item.media.map((media) => '[${media.displayName}]').join(' ');
        if (text.isEmpty) continue;
        buffer.writeln('$sender：$text');
        if (buffer.length >= _maxAiContextMessageCharacters) break;
      }
    }
    if (buffer.isEmpty) return '';
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
          message.isExcludedFromAiContext ||
          _isSkippedAiResponseMessage(message)) {
        continue;
      }
      for (final media in message.contextualMedia.toList().reversed) {
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
  static const int _maxDingTalkStructuredCharacters = 256 * kBytesPerKiB;
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
  static final RegExp _toolEchoArtifactPattern = RegExp(
    r'^(?:tool|tool\s+(?:call|use))(?:\s*[:\n]|$)',
    caseSensitive: false,
  );

  DingTalkResponseEchoType? _echoTypeOf(
    AiSessionMessage message,
    List<AiSessionMessage> sessionMessages,
  ) {
    if (message.isDeleted) return null;
    if (message.metadata[assistantResponseContinuationMetadataKey] == true ||
        message.kind == AiSessionMessageKind.assistant &&
            assistantResponseNeedsContinuation(message.content)) {
      return null;
    }
    if (_isToolEchoArtifact(message)) return null;
    if (message.kind == AiSessionMessageKind.assistant &&
        isDingTalkMediaInvocationPreamble(message.content)) {
      return null;
    }
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

  bool _isToolEchoArtifact(AiSessionMessage message) {
    if (message.kind != AiSessionMessageKind.assistant) return false;
    const toolMetadataKeys = <String>{
      aiSessionMessageToolCallIdMetadataKey,
      'tool_name',
      'tool_arguments',
      'tool_calls',
      'tool_execution_status',
      'tool_status',
    };
    if (toolMetadataKeys.any(message.metadata.containsKey)) return true;
    return _toolEchoArtifactPattern.hasMatch(message.content.trimLeft());
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

  Future<DingTalkSentMessage?> _sendDingTalkEcho({
    required DingTalkConversation conversation,
    required AiSessionMessage source,
    required DingTalkResponseEchoType type,
    required String text,
    required String uuid,
    bool respectEchoTypeSettings = true,
  }) async {
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final isToolSource =
        source.kind == AiSessionMessageKind.toolCall ||
        source.kind == AiSessionMessageKind.hook ||
        source.kind.isToolResultKind ||
        _isToolEchoArtifact(source);
    if ((respectEchoTypeSettings &&
            !_settings.responseEchoTypes.contains(type)) ||
        (isToolSource && type != DingTalkResponseEchoType.toolCall)) {
      return null;
    }
    final completeText = _sanitizeDingTalkVisibleText(text).trim();
    if (completeText.isEmpty) return null;
    final remoteText = _dingTalkRemoteEchoText(completeText);
    _rememberOutgoingEchoContent(source.id, remoteText);
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
      if (!isServiceEnabled ||
          (respectEchoTypeSettings &&
              !_settings.responseEchoTypes.contains(type))) {
        conversation.messages.removeWhere(
          (message) => message.id == localMessage.id,
        );
        _unresolvedOutgoingMessageIds.remove(localMessage.id);
        _outgoingEchoContentSnapshots.remove(source.id);
        _notify();
        return null;
      }
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
      _outgoingEchoContentSnapshots.remove(source.id);
      rethrow;
    }
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    _rememberRemoteConversationId(conversation, sent?.conversationId);
    final sentId = sent?.messageId?.trim() ?? '';
    final bound = _bindSentMessageId(conversation, localMessage, sentId);
    _notify();
    var resolvedId = sentId;
    if (resolvedId.isEmpty && !_isTemporaryMessageId(bound.id)) {
      resolvedId = bound.id.trim();
    }
    final taskId = sent?.taskId?.trim() ?? '';
    if (resolvedId.isEmpty && taskId.isEmpty) return null;
    return DingTalkSentMessage(
      messageId: resolvedId.isEmpty ? null : resolvedId,
      conversationId: sent?.conversationId,
      taskId: taskId.isEmpty ? null : taskId,
    );
  }

  Future<DingTalkSentMessage?> _sendDingTalkTextWithResolvedId({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
    required DateTime createdAt,
    required String senderName,
  }) async {
    if (!isServiceEnabled) return null;
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
    if (!isServiceEnabled) return sent;
    if (sent?.messageId?.trim().isNotEmpty == true) return sent;
    var resolvedDetails = sent;
    final taskId = sent?.taskId?.trim() ?? '';
    if (taskId.isNotEmpty) {
      try {
        final taskResult = await _service.resolveSentMessageByTaskId(taskId);
        resolvedDetails = DingTalkSentMessage(
          messageId: taskResult?.messageId ?? sent?.messageId,
          conversationId: sent?.conversationId ?? taskResult?.conversationId,
          taskId: taskResult?.taskId ?? taskId,
        );
        if (resolvedDetails.messageId?.trim().isNotEmpty == true) {
          return resolvedDetails;
        }
      } on DingTalkGatewayCommandException catch (error, stack) {
        if (!error.isRetryable && !error.isCancelled) {
          silentLog('dingtalk_gateway', '查询钉钉消息发送状态', error, stack);
        }
      } on TimeoutException {
        // 状态查询超时后继续按会话正文反查。
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '查询钉钉消息发送状态', error, stack);
      }
    }
    try {
      final resolved = await _service.resolveRecentSentMessage(
        conversation: conversation,
        content: content,
        createdAt: createdAt,
        senderName: senderName,
      );
      if (resolved?.messageId?.trim().isNotEmpty == true) {
        return DingTalkSentMessage(
          messageId: resolved!.messageId,
          conversationId:
              resolvedDetails?.conversationId ?? resolved.conversationId,
          taskId: resolvedDetails?.taskId,
        );
      }
    } on DingTalkGatewayCommandException catch (error, stack) {
      if (!error.isRetryable && !error.isCancelled) {
        silentLog('dingtalk_gateway', '补齐钉钉已发送消息标识', error, stack);
      }
    } on TimeoutException {
      // 可选反查超时不影响消息已发送结果，后续流式更新会有限重试。
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '补齐钉钉已发送消息标识', error, stack);
    }
    return resolvedDetails;
  }

  Future<void> _editDingTalkEcho({
    required DingTalkConversation conversation,
    required String sourceMessageId,
    required String messageId,
    required String text,
  }) async {
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final completeText = text.trim();
    if (completeText.isEmpty || messageId.trim().isEmpty) return;
    final remoteText = _dingTalkRemoteEchoText(completeText);
    _rememberOutgoingEchoContent(sourceMessageId, remoteText);
    await _service
        .editMessage(
          conversation: conversation,
          messageId: messageId,
          text: remoteText,
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

  /// 发送接口未返回消息标识时，查询任务状态并保底精确反查。
  Future<String?> _resolveEchoRemoteMessageId({
    required DingTalkConversation conversation,
    required String sourceMessageId,
    required String sentText,
    required String taskId,
  }) async {
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return null;
    }
    final local = _echoMessageBySourceId(conversation, sourceMessageId);
    if (local == null) return null;
    final localId = local.id.trim();
    if (localId.isNotEmpty && !_isTemporaryMessageId(localId)) {
      return localId;
    }
    final remoteText = _dingTalkRemoteEchoText(
      sentText.trim().isNotEmpty ? sentText : local.content,
    );
    final resolved = await _resolveDingTalkSentMessageIdIfMissing(
      conversation: conversation,
      // 本地保留完整正文，远端按平台预算发送；补标识时必须用远端文本匹配。
      content: remoteText,
      createdAt: local.createdAt,
      senderName: _authStatus.identity.label.trim(),
      sent: taskId.trim().isEmpty
          ? null
          : DingTalkSentMessage(taskId: taskId.trim()),
    );
    final resolvedId = resolved?.messageId?.trim() ?? '';
    if (resolvedId.isEmpty ||
        !isServiceEnabled ||
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
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final completeText = _sanitizeDingTalkVisibleText(text).trim();
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
    final normalized = convertDingTalkMarkdownTables(
      _sanitizeDingTalkVisibleText(text),
    ).trim();
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
    final content = _sanitizeDingTalkVisibleText(message.content).trim();
    return message.kind == AiSessionMessageKind.reasoning
        ? wrapDingTalkThinkingMarkdown(content)
        : content;
  }

  String _formatDingTalkToolEcho(
    AiSessionMessage call,
    List<AiSessionMessage> sessionMessages,
  ) {
    final metadata = call.metadata;
    final toolCallId = _boundedToolLabel(
      metadata[aiSessionMessageToolCallIdMetadataKey] ?? call.id,
    );
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
    final id = '${call.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
        .trim();
    if (id.isEmpty) return null;
    for (final message in sessionMessages.reversed) {
      if (message.isDeleted || !message.kind.isToolResultKind) continue;
      if ('${message.metadata[aiSessionMessageToolCallIdMetadataKey] ?? ''}'
              .trim() ==
          id) {
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

  bool _canStartResponseImmediately(String conversationId) {
    if (_activeResponseConversationIds.contains(conversationId) ||
        _pausedResponseQueueConversationIds.contains(conversationId)) {
      return false;
    }
    final availableWorkers =
        _settings.responseWorkerCount - _activeResponseConversationIds.length;
    if (availableWorkers <= 0) return false;
    var readyQueues = 0;
    for (final entry in _responseQueues.entries) {
      if (entry.value.isEmpty ||
          _pausedResponseQueueConversationIds.contains(entry.key) ||
          _activeResponseConversationIds.contains(entry.key)) {
        continue;
      }
      if (entry.key == conversationId) return false;
      readyQueues++;
      if (readyQueues >= availableWorkers) return false;
    }
    return true;
  }

  Future<void> _sendOverloadReply(DingTalkConversation conversation) async {
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    final sentAt = DateTime.now();
    final senderName = _authStatus.identity.label.trim().isEmpty
        ? 'OpenHand'
        : _authStatus.identity.label.trim();
    final localMessage = DingTalkGatewayMessage(
      id: 'assistant-overload-${_uuid.v4()}',
      conversationId: conversation.id,
      conversationType: conversation.type,
      role: DingTalkGatewayMessageRole.assistant,
      content: _overloadBusyReply,
      createdAt: sentAt,
      senderName: senderName,
      senderId: _authStatus.identity.userId,
      fromSelf: true,
      responseEchoType: DingTalkResponseEchoType.finalResponse,
    );
    _rememberUnresolvedOutgoingMessage(localMessage.id);
    _appendMessage(conversation, localMessage);
    _notify();
    try {
      final sent = await _sendDingTalkTextWithResolvedId(
        conversation: conversation,
        text: _overloadBusyReply,
        uuid: _uuid.v4(),
        createdAt: sentAt,
        senderName: senderName,
      );
      if (!isServiceEnabled ||
          !identical(_conversations[conversation.id], conversation)) {
        return;
      }
      _rememberRemoteConversationId(conversation, sent?.conversationId);
      _bindSentMessageId(conversation, localMessage, sent?.messageId);
    } catch (error, stack) {
      conversation.messages.removeWhere(
        (message) => message.id == localMessage.id,
      );
      _unresolvedOutgoingMessageIds.remove(localMessage.id);
      _setResponseError(conversation.id, 'AI 忙碌提示发送失败，请查看钉钉网关运行日志。');
      silentLog('dingtalk_gateway', '发送钉钉忙碌提示', error, stack);
    } finally {
      _queuePersist();
      _notify();
    }
  }

  Future<void> _sendResponseFailureReply(
    DingTalkConversation conversation,
  ) async {
    if (!isServiceEnabled ||
        !identical(_conversations[conversation.id], conversation)) {
      return;
    }
    try {
      await _sendDingTalkEcho(
        conversation: conversation,
        source: AiSessionMessage.assistant(
          id: 'dingtalk-response-failure-${_uuid.v4()}',
          content: _responseFailureReply,
          createdAt: DateTime.now(),
        ),
        type: DingTalkResponseEchoType.finalResponse,
        text: _responseFailureReply,
        uuid: _uuid.v4(),
        respectEchoTypeSettings: false,
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '发送钉钉 AI 响应失败提示', error, stack);
    }
  }

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
        !isServiceEnabled ||
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
            sourceMessage.aiResponseState !=
                DingTalkMessageAiResponseState.none ||
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
    if (automaticResponse &&
        ((_activeResponseContextMessageIds[conversation.id]?.contains(
                  sourceId,
                ) ??
                false) ||
            (_responseQueues[conversation.id]?.any(
                  (item) => item.sourceMessageId == sourceId,
                ) ??
                false))) {
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
    }
    if (automaticResponse && !_canStartResponseImmediately(conversation.id)) {
      switch (_settings.overloadStrategy) {
        case DingTalkOverloadStrategy.queue:
          break;
        case DingTalkOverloadStrategy.reject:
          _setMessageAiResponseState(
            conversation,
            sourceId,
            DingTalkMessageAiResponseState.rejected,
          );
          return _sendOverloadReply(conversation);
        case DingTalkOverloadStrategy.drop:
          _setMessageAiResponseState(
            conversation,
            sourceId,
            DingTalkMessageAiResponseState.dropped,
          );
          return Future<void>.value();
      }
    }
    _setMessageAiResponseState(
      conversation,
      sourceId,
      DingTalkMessageAiResponseState.queued,
    );
    final queue = _responseQueues.putIfAbsent(
      conversation.id,
      () => Queue<_QueuedDingTalkResponse>(),
    );
    if (queue.length >= _maxQueuedResponsesPerConversation) {
      _warningMessage = '钉钉会话等待队列已满，新消息未进入队列。';
      if (automaticResponse) {
        _setMessageAiResponseState(
          conversation,
          sourceId,
          DingTalkMessageAiResponseState.rejected,
        );
        return _sendOverloadReply(conversation);
      }
      _setMessageAiResponseState(
        conversation,
        sourceId,
        DingTalkMessageAiResponseState.failed,
      );
      _setResponseError(conversation.id, '当前会话等待队列已满，请稍后重试。');
      return Future<void>.value();
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
      if (automaticResponse) {
        final ordered = queue.toList(growable: true);
        final insertIndex = ordered.indexWhere((item) {
          if (!item.automaticResponse ||
              item.pollingGeneration != pollingGeneration) {
            return false;
          }
          final timeOrder = queuedResponse.scheduledAt.compareTo(
            item.scheduledAt,
          );
          return timeOrder < 0 ||
              timeOrder == 0 && queuedResponse.sequence < item.sequence;
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
    // 停止消息服务后，自动响应和手动响应都必须立即退出，不能留下后台任务。
    final queuedConversationIds = _responseQueues.keys.toList(growable: false);
    for (final conversationId in queuedConversationIds) {
      _discardQueuedResponses(
        conversationId,
        conversation: _conversations[conversationId],
      );
    }
    _scheduleResponseWorkers();
    for (final cancellation in _activeMediaGenerationCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _activeMediaGenerationCancellations.clear();
    final activeConversationIds = _conversations.keys
        .where(isConversationResponding)
        .toSet();
    activeConversationIds.addAll(_activeResponseConversationIds);
    activeConversationIds.addAll(_responseInFlight);
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
    _activeAutomaticResponses.clear();
  }

  Future<void> _cancelDisallowedAutomaticResponses() async {
    final disallowedConversationIds = _conversations.values
        .where(
          (conversation) => !_settings.allowsAutomaticResponseFor(
            _targetFromConversation(conversation),
          ),
        )
        .map((conversation) => conversation.id)
        .toSet();
    if (disallowedConversationIds.isEmpty) return;

    final stopTasks = <Future<void>>[];
    for (final conversationId in disallowedConversationIds) {
      final queue = _responseQueues[conversationId];
      final conversation = _conversations[conversationId];
      if (queue != null) {
        for (final item in queue.toList(growable: false)) {
          if (!item.automaticResponse) continue;
          queue.remove(item);
          if (conversation != null) {
            _setMessageAiResponseState(
              conversation,
              item.sourceMessageId,
              DingTalkMessageAiResponseState.cancelled,
            );
          }
          item.complete();
        }
        if (queue.isEmpty) {
          _responseQueues.remove(conversationId);
          _pausedResponseQueueConversationIds.remove(conversationId);
        }
      }

      final activeItem = _activeAutomaticResponses[conversationId];
      if (activeItem == null) continue;
      _responseCancellationVersions[conversationId] =
          (_responseCancellationVersions[conversationId] ?? 0) + 1;
      if (conversation != null) {
        _setMessageAiResponseState(
          conversation,
          activeItem.sourceMessageId,
          DingTalkMessageAiResponseState.cancelled,
        );
      }
      final mediaCancellation = _activeMediaGenerationCancellations.remove(
        conversationId,
      );
      if (mediaCancellation != null && !mediaCancellation.isCompleted) {
        mediaCancellation.complete();
      }
      final sessionId = conversation?.aiSessionId;
      if (sessionId == null ||
          !_sessionController.canStopResponding(sessionId)) {
        continue;
      }
      stopTasks.add(() async {
        try {
          await _sessionController
              .stopResponding(sessionId)
              .timeout(_stopResponseTimeout);
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '撤销白名单后停止钉钉自动响应', error, stack);
        }
      }());
    }
    await Future.wait(stopTasks);
    _scheduleResponseWorkers();
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
          !_isSkippedAiResponseMessage(candidate) &&
          candidate.content.trim().isNotEmpty &&
          _canAutomaticallyRespondToMessage(candidate) &&
          _isAutomaticResponseEligible(candidate, pollingGeneration)) {
        return candidate;
      }
    }
    return null;
  }

  void _scheduleResponseWorkers() {
    if (!isServiceEnabled || _responseSchedulingQueued) return;
    _responseSchedulingQueued = true;
    scheduleMicrotask(() {
      _responseSchedulingQueued = false;
      _dispatchResponseWorkers();
    });
  }

  void _dispatchResponseWorkers() {
    if (!isServiceEnabled) return;
    while (_activeResponseConversationIds.length <
        _settings.responseWorkerCount) {
      String? selectedConversationId;
      _QueuedDingTalkResponse? selectedItem;
      for (final entry in _responseQueues.entries) {
        if (entry.value.isEmpty ||
            _pausedResponseQueueConversationIds.contains(entry.key) ||
            _activeResponseConversationIds.contains(entry.key)) {
          continue;
        }
        final candidate = entry.value.first;
        final selected = selectedItem;
        if (selected == null ||
            (candidate.manuallyPrioritized && !selected.manuallyPrioritized) ||
            (candidate.manuallyPrioritized == selected.manuallyPrioritized &&
                (candidate.scheduledAt.isBefore(selected.scheduledAt) ||
                    (candidate.scheduledAt.isAtSameMomentAs(
                          selected.scheduledAt,
                        ) &&
                        candidate.sequence < selected.sequence)))) {
          selectedConversationId = entry.key;
          selectedItem = candidate;
        }
      }
      if (selectedConversationId == null || selectedItem == null) return;
      final conversation = _conversations[selectedConversationId];
      final queue = _responseQueues[selectedConversationId];
      if (conversation == null || queue == null || queue.isEmpty) {
        _pausedResponseQueueConversationIds.remove(selectedConversationId);
        final discardedQueue = _responseQueues.remove(selectedConversationId);
        if (discardedQueue == null) {
          selectedItem.complete();
        } else {
          for (final item in discardedQueue) {
            if (conversation != null) {
              _setMessageAiResponseState(
                conversation,
                item.sourceMessageId,
                DingTalkMessageAiResponseState.cancelled,
              );
            }
            item.complete();
          }
        }
        continue;
      }
      queue.removeFirst();
      if (queue.isEmpty) {
        _responseQueues.remove(selectedConversationId);
        _pausedResponseQueueConversationIds.remove(selectedConversationId);
      }
      _activeResponseConversationIds.add(selectedConversationId);
      unawaited(_runResponseWorker(conversation, selectedItem));
    }
  }

  void _discardQueuedResponses(
    String conversationId, {
    DingTalkConversation? conversation,
  }) {
    final normalizedId = conversationId.trim();
    final queue = _responseQueues.remove(normalizedId);
    _pausedResponseQueueConversationIds.remove(normalizedId);
    if (queue == null) return;
    for (final item in queue) {
      if (conversation != null) {
        _setMessageAiResponseState(
          conversation,
          item.sourceMessageId,
          DingTalkMessageAiResponseState.cancelled,
        );
      }
      item.complete();
    }
  }

  Future<void> _runResponseWorker(
    DingTalkConversation conversation,
    _QueuedDingTalkResponse item,
  ) async {
    final responseVersion = _responseCancellationVersions[conversation.id] ?? 0;
    if (item.automaticResponse) {
      _activeAutomaticResponses[conversation.id] = item;
    }
    try {
      if (isServiceEnabled) {
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
          if (_isResponseCancelled(conversation.id, responseVersion)) {
            return;
          }
        }
        var source = conversation.messages
            .where((message) => message.id == item.sourceMessageId)
            .firstOrNull;
        if (item.automaticResponse &&
            conversation.type == DingTalkConversationType.direct &&
            (source == null || source.isExcludedFromAiContext)) {
          source = _latestPendingDirectResponseSource(
            conversation,
            item.sourceMessageId,
            item.pollingGeneration,
          );
          if (source != null) {
            _setMessageAiResponseState(
              conversation,
              item.sourceMessageId,
              DingTalkMessageAiResponseState.cancelled,
            );
            item
              ..sourceMessageId = source.id
              ..content = _messageAiContextContent(source);
          }
        }
        if (item.automaticResponse &&
            (source == null ||
                !_canAutomaticallyRespondToMessage(source) ||
                !_isAutomaticResponseEligible(
                  source,
                  item.pollingGeneration,
                ))) {
          return;
        }
        if (item.automaticResponse) {
          await _ensureIncomingContextMedia(conversation, item.sourceMessageId);
          if (_isResponseCancelled(conversation.id, responseVersion)) {
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
              _setMessageAiResponseState(
                conversation,
                item.sourceMessageId,
                DingTalkMessageAiResponseState.cancelled,
              );
              item
                ..sourceMessageId = source.id
                ..content = _messageAiContextContent(source);
            }
          }
          if (source == null ||
              source.isAssistant ||
              source.isExcludedFromAiContext ||
              !_canAutomaticallyRespondToMessage(source) ||
              !_isAutomaticResponseEligible(source, item.pollingGeneration)) {
            return;
          }
        }
        _setMessageAiResponseState(
          conversation,
          item.sourceMessageId,
          DingTalkMessageAiResponseState.responding,
        );
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
      final cancelled =
          _messageAiResponseState(conversation, item.sourceMessageId) ==
              DingTalkMessageAiResponseState.cancelled ||
          _isResponseCancelled(conversation.id, responseVersion);
      _setMessageAiResponseState(
        conversation,
        item.sourceMessageId,
        cancelled
            ? DingTalkMessageAiResponseState.cancelled
            : DingTalkMessageAiResponseState.failed,
      );
      if (!cancelled) {
        _setResponseError(conversation.id, 'AI 响应失败，请查看钉钉网关运行日志。');
      }
      silentLog('dingtalk_gateway', '处理钉钉消息队列', error, stack);
    } finally {
      var sourceState = _messageAiResponseState(
        conversation,
        item.sourceMessageId,
      );
      if (sourceState == DingTalkMessageAiResponseState.queued ||
          sourceState == DingTalkMessageAiResponseState.responding) {
        _setMessageAiResponseState(
          conversation,
          item.sourceMessageId,
          DingTalkMessageAiResponseState.cancelled,
        );
        sourceState = DingTalkMessageAiResponseState.cancelled;
      }
      final suppressFailureReply = _responseFailureReplySuppressed.remove(
        conversation.id,
      );
      if (sourceState == DingTalkMessageAiResponseState.failed &&
          !suppressFailureReply) {
        await _sendResponseFailureReply(conversation);
      }
      item.complete();
      if (identical(_activeAutomaticResponses[conversation.id], item)) {
        _activeAutomaticResponses.remove(conversation.id);
      }
      _activeResponseConversationIds.remove(conversation.id);
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
      availableWorkflowIds: _workflowsController.workflows
          .where((workflow) => workflow.enabled)
          .map((workflow) => workflow.id),
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

  List<_DingTalkEagerMcpTool> _resolvedEagerMcpTools(
    List<McpServer> selectedServers,
    Set<String> eagerServerNames,
  ) {
    if (eagerServerNames.isEmpty) return const <_DingTalkEagerMcpTool>[];
    final servers = List<McpServer>.from(selectedServers)
      ..sort(
        (left, right) => compareToolNamesForAiRequest(left.name, right.name),
      );
    final reservedNames = <String>{};
    final result = <_DingTalkEagerMcpTool>[];
    for (final server in servers) {
      final tools = List<McpTool>.from(
        _mcpController.toolCatalogFor(server.name).tools,
      )..sort((left, right) => compareToolNamesForAiRequest(left.id, right.id));
      for (final tool in tools) {
        final baseName = compactToolName(
          prefix: 'mcp__${server.name}',
          token: tool.id,
        );
        var name = baseName;
        var suffix = 1;
        while (!reservedNames.add(name)) {
          name = appendUniqueToolNameSuffix(baseName, suffix++);
        }
        if (!eagerServerNames.contains(server.name)) continue;
        result.add(
          _DingTalkEagerMcpTool(
            name: name,
            serverName: server.name,
            description: clipTextByCodeUnits(
              tool.description.replaceAll(RegExp(r'\s+'), ' ').trim(),
              160,
              suffix: '…',
            ),
          ),
        );
      }
    }
    return result;
  }

  String _dingTalkMcpRoutingReminder(
    List<McpServer> selectedServers,
    List<_DingTalkEagerMcpTool> eagerTools,
  ) {
    final enabledNames = selectedServers.map((server) => server.name).join('、');
    if (eagerTools.isEmpty) {
      return '钉钉 MCP 路由：已启用 $enabledNames。请求命中其能力时必须调用 MCP；'
          '仅延迟工具使用 ToolSearch。取得结果前不得输出前导语或结论。';
    }
    final directTools = eagerTools
        .map(
          (tool) => tool.description.isEmpty
              ? '${tool.name}（${tool.serverName}）'
              : '${tool.name}（${tool.serverName}：${tool.description}）',
        )
        .join('；');
    return '钉钉 MCP 路由：已直接加载 $directTools。请求命中时直接调用准确工具名，'
        '禁止通过 ToolSearch 查找；仅其他延迟工具使用 ToolSearch。取得结果前不得输出前导语或结论。';
  }

  bool _roundInvokedAnyTool(
    AiSession? session,
    int startIndex,
    Set<String> expectedToolNames,
  ) {
    if (session == null || expectedToolNames.isEmpty) return false;
    final safeStart = startIndex.clamp(0, session.messages.length);
    return session.messages
        .skip(safeStart)
        .any(
          (message) =>
              !message.isDeleted &&
              message.kind == AiSessionMessageKind.toolCall &&
              expectedToolNames.contains(
                '${message.metadata['tool_name'] ?? ''}'.trim(),
              ),
        );
  }

  bool _matchesCurrentIdentity(DingTalkGatewayMessage message) {
    final sender = message.senderId.trim();
    final senderOpenDingTalkId = message.senderOpenDingTalkId.trim();
    final current = _authStatus.identity.userId.trim();
    final currentOpenDingTalkId = _authStatus.identity.openDingTalkId.trim();
    final profile = _authStatus.identity.profile.trim();
    final profileUserId = profile.contains(':')
        ? profile.substring(profile.lastIndexOf(':') + 1)
        : profile;
    if (sender.isNotEmpty &&
        ((current.isNotEmpty && sender == current) ||
            (currentOpenDingTalkId.isNotEmpty &&
                sender == currentOpenDingTalkId) ||
            (profile.isNotEmpty && sender == profile) ||
            (profileUserId.isNotEmpty && sender == profileUserId))) {
      return true;
    }
    if (senderOpenDingTalkId.isNotEmpty &&
        currentOpenDingTalkId.isNotEmpty &&
        senderOpenDingTalkId == currentOpenDingTalkId) {
      return true;
    }
    final senderName = message.senderName.trim();
    final identityName = _authStatus.identity.name.trim();
    final identityLabel = _authStatus.identity.label.trim();
    final senderNameMatches =
        senderName.isNotEmpty &&
        ((identityName.isNotEmpty &&
                _sameIdentityName(senderName, identityName)) ||
            (identityLabel.isNotEmpty &&
                _sameIdentityName(senderName, identityLabel)));
    return senderNameMatches;
  }

  bool _messageMentionsCurrentIdentity(DingTalkGatewayMessage message) {
    final content = message.content.toLowerCase();
    if (content.isEmpty) return false;
    final names = <String>{
      _authStatus.identity.name.trim().toLowerCase(),
      _authStatus.identity.label.trim().toLowerCase(),
    }..remove('');
    for (final name in names) {
      for (final marker in <String>['@$name', '＠$name']) {
        var index = content.indexOf(marker);
        while (index >= 0) {
          final end = index + marker.length;
          if (end == content.length ||
              _mentionTrailingBoundary.hasMatch(content[end])) {
            return true;
          }
          index = content.indexOf(marker, index + marker.length);
        }
      }
    }
    return false;
  }

  bool _hasResolvedOtherIdentity(DingTalkGatewayMessage message) {
    final senderName = message.senderName.trim();
    final identityName = _authStatus.identity.name.trim();
    return senderName.isNotEmpty &&
        identityName.isNotEmpty &&
        !_sameIdentityName(senderName, identityName);
  }

  bool _repairPersistedMessageOwnership() {
    var changed = false;
    for (final conversation in _conversations.values) {
      for (var index = 0; index < conversation.messages.length; index++) {
        final message = conversation.messages[index];
        if (message.isAssistant ||
            !message.fromSelf ||
            _matchesCurrentIdentity(message) ||
            !_hasResolvedOtherIdentity(message)) {
          continue;
        }
        _selfSenderIds
          ..remove(message.senderId.trim())
          ..remove(message.senderOpenDingTalkId.trim());
        conversation.messages[index] = message.copyWith(fromSelf: false);
        changed = true;
      }
    }
    return changed;
  }

  bool _isSelf(DingTalkGatewayMessage message) {
    if (message.isAssistant || message.fromSelf) return true;
    if (_matchesCurrentIdentity(message)) return true;
    final sender = message.senderId.trim();
    final senderOpenDingTalkId = message.senderOpenDingTalkId.trim();
    if (senderOpenDingTalkId.isNotEmpty &&
        _selfSenderIds.contains(senderOpenDingTalkId)) {
      return true;
    }
    final senderName = message.senderName.trim();
    final identityName = _authStatus.identity.name.trim();
    final identityLabel = _authStatus.identity.label.trim();
    final senderNameMatches =
        senderName.isNotEmpty &&
        ((identityName.isNotEmpty &&
                _sameIdentityName(senderName, identityName)) ||
            (identityLabel.isNotEmpty &&
                _sameIdentityName(senderName, identityLabel)));
    if (sender.isNotEmpty && _selfSenderIds.contains(sender)) {
      if (senderName.isEmpty || senderNameMatches) return true;
      _selfSenderIds.remove(sender);
    }
    return false;
  }

  bool _isIncomingIdentityUnresolved(DingTalkGatewayMessage message) {
    if (message.senderName.trim().isNotEmpty) return false;
    return message.senderId.trim().isNotEmpty ||
        message.senderOpenDingTalkId.trim().isNotEmpty;
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

  bool _normalizeConversationMessages(DingTalkConversation conversation) {
    final normalized = normalizeDingTalkConversationMessages(
      conversation.messages,
    );
    if (!normalized.changed) return false;
    conversation.messages
      ..clear()
      ..addAll(normalized.messages);
    return true;
  }

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
    final sourceId = message.isAssistant
        ? message.sourceAiMessageId.trim()
        : '';
    final normalizedMessage =
        message.id == messageId && message.sourceAiMessageId == sourceId
        ? message
        : message.copyWith(id: messageId, sourceAiMessageId: sourceId);
    conversation.messages.add(normalizedMessage);
    _normalizeConversationMessages(conversation);
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

  void _rememberOutgoingEchoContent(String sourceMessageId, String content) {
    final sourceId = sourceMessageId.trim();
    final comparison = normalizeDingTalkOutgoingEchoContentForComparison(
      content,
    );
    if (sourceId.isEmpty || comparison.isEmpty) return;
    final snapshots =
        _outgoingEchoContentSnapshots.remove(sourceId) ?? <String>{};
    snapshots
      ..remove(comparison)
      ..add(comparison);
    while (snapshots.length > _maxOutgoingEchoSnapshotsPerSource) {
      snapshots.remove(snapshots.first);
    }
    _outgoingEchoContentSnapshots[sourceId] = snapshots;
    while (_outgoingEchoContentSnapshots.length >
        _maxOutgoingEchoSnapshotSources) {
      _outgoingEchoContentSnapshots.remove(
        _outgoingEchoContentSnapshots.keys.first,
      );
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

  DingTalkMessageAiResponseState _messageAiResponseState(
    DingTalkConversation conversation,
    String messageId,
  ) {
    return conversation.messages
            .where((message) => message.id == messageId)
            .firstOrNull
            ?.aiResponseState ??
        DingTalkMessageAiResponseState.none;
  }

  void _setMessageAiResponseState(
    DingTalkConversation conversation,
    String messageId,
    DingTalkMessageAiResponseState state,
  ) {
    final normalizedId = messageId.trim();
    if (normalizedId.isEmpty) return;
    final index = conversation.messages.indexWhere(
      (message) => message.id == normalizedId,
    );
    if (index < 0 || conversation.messages[index].aiResponseState == state) {
      return;
    }
    conversation.messages[index] = conversation.messages[index].copyWith(
      aiResponseState: state,
    );
    _queuePersist();
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
          .map((conversation) => conversation.snapshot())
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
    _cancelActivePoll();
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
    _outgoingEchoContentSnapshots.clear();
    await _cancelMediaDownloads();
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
    _pausedResponseQueueConversationIds.clear();
    _activeResponseConversationIds.clear();
    _activeResponseContextMessageIds.clear();
    _activeAutomaticResponses.clear();
    _responsePreparingCounts.clear();
    _responseErrors.clear();
    _responseFailureReplySuppressed.clear();
    _responseCancellationVersions.clear();
    for (final cancellation in _activeMediaGenerationCancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _activeMediaGenerationCancellations.clear();
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
      _service.dispose,
      timeout: _shutdownCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '释放钉钉消息服务', error, stack),
    );
    _runtimeLogRevision.dispose();
  }

  Future<void> _cancelMediaDownloads() async {
    await runAsyncCleanupBounded(
      _service.cancelMediaDownloads,
      timeout: _shutdownCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '取消钉钉媒体下载', error, stack),
    );
  }

  @override
  void dispose() {
    unawaited(
      shutdown().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            silentLog('dingtalk_gateway', '释放钉钉网关控制器', error, stack),
      ),
    );
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
    Future<DingTalkSentMessage?> Function(
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
    Future<String?> Function(
      String sourceMessageId,
      String sentText,
      String taskId,
    );
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
/// 消息，营造流式输出效果；终态编辑失败时保留最后一次远端成功内容并报告交付失败。
class _DingTalkEchoCoordinator {
  _DingTalkEchoCoordinator({
    required this._responseRoundId,
    required this._deliveredSourceMessageIds,
    required this._expectToolActivity,
    required this._isTypeEnabled,
    required this._typeOf,
    required this._textFor,
    required this._isTerminal,
    required this._isCancelled,
    required this._send,
    required this._edit,
    required this._resolveRemoteId,
    required this._markStreaming,
    required this._newUuid,
    required this._onError,
  });

  static const Duration _initialStreamDelay = Duration(milliseconds: 180);
  static const Duration _remoteIdResolveRetryDelay = Duration(
    milliseconds: 800,
  );
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
  static const int _maxRemoteIdResolveAttempts = 4;
  static const int _maxRemoteEditRetryAttempts = 3;

  final String _responseRoundId;
  final Set<String> _deliveredSourceMessageIds;
  final bool _expectToolActivity;
  final bool Function(DingTalkResponseEchoType type) _isTypeEnabled;
  final _DingTalkEchoTypeResolver _typeOf;
  final _DingTalkEchoTextBuilder _textFor;
  final _DingTalkEchoTerminalResolver _isTerminal;
  final _DingTalkEchoCancellationChecker _isCancelled;
  final _DingTalkEchoSender _send;
  final _DingTalkEchoEditor _edit;
  final _DingTalkEchoRemoteIdResolver _resolveRemoteId;
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
  final Set<String> _deliveryFailures = <String>{};

  bool get hasDeliveryFailure => _deliveryFailures.isNotEmpty;

  void ingest(
    AiSession session, {
    bool finalizing = false,
    bool includeUnsentFinalResponse = true,
  }) {
    if (_disposed || _isCancelled()) return;
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
    var hasPriorToolActivity = false;
    for (final message in session.messages.skip(roundStartIndex + 1)) {
      final followsToolActivity = hasPriorToolActivity;
      if (message.kind == AiSessionMessageKind.toolCall ||
          message.kind == AiSessionMessageKind.hook ||
          message.kind.isToolResultKind) {
        hasPriorToolActivity = true;
      }
      if (message.createdAt.isBefore(roundStartedAt) ||
          _deliveredSourceMessageIds.contains(message.id)) {
        continue;
      }
      final state = _states[message.id];
      final queued = _pending[message.id];
      final resolvedType = _typeOf(message, session.messages);
      final terminal = _isTerminal(message);
      // 正式回复至少等待当前模型流完成；否则未完整的中间文本会先被当成
      // 最终答案发送，后续即使自动续接也会留下突兀的半句。
      if (state == null &&
          resolvedType == DingTalkResponseEchoType.finalResponse &&
          !finalizing &&
          (!terminal || _expectToolActivity && !followsToolActivity)) {
        _pending.remove(message.id);
        continue;
      }
      if (state == null &&
          resolvedType == DingTalkResponseEchoType.finalResponse &&
          finalizing &&
          !includeUnsentFinalResponse) {
        _pending.remove(message.id);
        continue;
      }
      // 未发送前允许消息类型随会话状态变化，避免助手消息由正式响应变为过程响应时
      // 仍沿用首次解析结果；已发送消息保持原卡片生命周期不变。
      if (state == null &&
          (resolvedType == null || !_isTypeEnabled(resolvedType))) {
        _pending.remove(message.id);
        continue;
      }
      final type = state?.type ?? resolvedType ?? queued?.type;
      if (type == null) continue;
      final text = _textFor(message, session.messages).trim();
      if (text.isEmpty) continue;
      if (state?.finished == true && state?.lastText == text) continue;
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
  void complete(AiSession session, {bool includeUnsentFinalResponse = true}) {
    if (_disposed || _isCancelled()) return;
    ingest(
      session,
      finalizing: true,
      includeUnsentFinalResponse: includeUnsentFinalResponse,
    );
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
    if (!_isTypeEnabled(pending.type)) return;
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
      state.lastMutationAt = DateTime.now();
      if (pending.terminal && _deliveryFailures.add(sourceId)) {
        _onError(
          '编辑钉钉 AI 回显消息',
          StateError(
            state.remoteEditingDisabled
                ? '钉钉已拒绝继续编辑，无法同步终态内容。'
                : '钉钉消息编辑次数已达安全上限，无法同步终态内容。',
          ),
          StackTrace.current,
          notifyUser: false,
        );
      }
      _settle(sourceId, state, pending);
      return;
    }
    try {
      if (_disposed || _isCancelled()) return;
      if (!state.sent) {
        // 插入本地气泡前先标记流式，避免正文先完整展开再收缩渐显。
        _markStreaming(sourceId, true);
        final sent = await _send(
          pending.source,
          pending.type,
          pending.text,
          state.uuid,
        );
        state.remoteMessageId = sent?.messageId;
        state.remoteTaskId = sent?.taskId;
        if (_disposed || _isCancelled()) return;
        state.sent = true;
        _deliveryFailures.remove(sourceId);
      } else {
        final messageId = await _remoteMessageIdForEdit(sourceId, state);
        if (_disposed || _isCancelled()) return;
        if (messageId.isEmpty) {
          // 发送任务和消息列表均可能短暂不可见，终态更新保留并做有限补偿，
          // 避免本地已成功而钉钉仍停在等待状态。
          state.lastMutationAt = DateTime.now();
          if (state.remoteIdResolveAttempts < _maxRemoteIdResolveAttempts) {
            _pending[sourceId] = pending.copyWith(
              readyAt: DateTime.now().add(_remoteIdResolveRetryDelay),
            );
            state.finished = false;
            _markStreaming(sourceId, true);
            return;
          }
          if (pending.terminal) {
            _deliveryFailures.add(sourceId);
            _onError(
              '编辑钉钉 AI 回显消息',
              StateError('多次查询后仍缺少远端消息标识，无法同步终态内容。'),
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
        state.remoteEditRetryAttempts = 0;
        _deliveryFailures.remove(sourceId);
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
        if (pending.terminal) _deliveryFailures.add(sourceId);
        _settle(sourceId, state, pending);
        if (!commandError.isMessageEditLimitReached &&
            !commandError.isUnsupportedMessageEditType) {
          _onError('编辑钉钉 AI 回显消息', error, stack, notifyUser: false);
        }
        return;
      }
      if (state.sent &&
          pending.terminal &&
          state.remoteEditRetryAttempts < _maxRemoteEditRetryAttempts) {
        state.remoteEditRetryAttempts++;
        _pending[sourceId] = pending.copyWith(
          readyAt: DateTime.now().add(_remoteIdResolveRetryDelay),
        );
        state.finished = false;
        _markStreaming(sourceId, true);
        return;
      }
      if (state.sent && pending.terminal) {
        _deliveryFailures.add(sourceId);
      }
      _onError(
        state.sent ? '编辑钉钉 AI 回显消息' : '发送钉钉 AI 回显消息',
        error,
        stack,
        notifyUser: !state.sent,
      );
      if (!state.sent) _deliveryFailures.add(sourceId);
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

  /// 发送接口先返回任务标识时，编辑前按有限次数补齐远端消息标识。
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
        (await _resolveRemoteId(
          sourceId,
          state.lastText,
          state.remoteTaskId?.trim() ?? '',
        ))?.trim() ??
        '';
    if (resolved.isNotEmpty) {
      state.remoteMessageId = resolved;
      state.remoteTaskId = null;
    }
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
    _deliveryFailures.clear();
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
  String? remoteTaskId;
  String lastText = '';
  DateTime lastMutationAt = DateTime.fromMillisecondsSinceEpoch(0);
  int remoteIdResolveAttempts = 0;
  int successfulRemoteEditCount = 0;
  int remoteEditRetryAttempts = 0;
  bool sent = false;
  bool finished = false;
  bool remoteEditingDisabled = false;
}

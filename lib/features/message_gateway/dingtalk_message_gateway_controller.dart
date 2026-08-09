import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

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
  static const int _maxSeenIds = 2000;
  static const int _maxReactionTypes = 12;
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
  final AiImageGenerationService _mediaGenerationService;
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
  final Map<String, Future<DingTalkGatewayMessage>> _mediaHydrationTasks =
      <String, Future<DingTalkGatewayMessage>>{};
  Timer? _pollTimer;
  StreamSubscription<DingTalkGatewayEvent>? _eventSubscription;
  Future<void>? _persistInFlight;
  bool _persistQueued = false;
  Object? _persistenceError;
  bool _pollInFlight = false;
  bool _usingPollingFallback = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _notificationQueued = false;
  DingTalkWriteApprovalHandler? _writeApprovalHandler;
  bool _isAuthenticating = false;
  bool _isPolling = false;
  bool _isSending = false;
  bool _editingMessageInFlight = false;
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

  bool isMessageMediaCaching(String messageId) =>
      _mediaHydrationTasks.containsKey(messageId);

  /// 确保指定会话中的媒体文件已落地到本地缓存。缓存被用户清理或路径失效时，
  /// 下一次访问会重新调用 dws 下载。
  Future<DingTalkGatewayMessage?> ensureMessageMediaCached({
    required String conversationId,
    required String messageId,
  }) async {
    final conversation = _conversations[conversationId];
    if (conversation == null) return null;
    final message = conversation.messages
        .where((item) => item.id == messageId)
        .firstOrNull;
    if (message == null || message.media.isEmpty) return message;
    final active = _mediaHydrationTasks[message.id];
    if (active != null) return active;
    final task = _hydrateMessageMedia(conversation, message);
    _mediaHydrationTasks[message.id] = task;
    try {
      return await task;
    } finally {
      if (identical(_mediaHydrationTasks[message.id], task)) {
        _mediaHydrationTasks.remove(message.id);
      }
    }
  }

  Future<DingTalkGatewayMessage> _hydrateMessageMedia(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) async {
    var changed = false;
    final media = <DingTalkGatewayMedia>[];
    for (final item in message.media) {
      final currentPath = item.localPath.trim();
      if (currentPath.isNotEmpty) {
        try {
          if (await File(currentPath).exists()) {
            media.add(item);
            continue;
          }
        } catch (_) {}
      }
      if (item.resourceId.startsWith('local-')) {
        media.add(item.copyWith(localPath: ''));
        changed = true;
        continue;
      }
      final path = await _service.ensureMediaCached(item);
      if (path == null || path.trim().isEmpty) {
        media.add(item.copyWith(localPath: ''));
      } else {
        media.add(item.copyWith(localPath: path));
      }
      changed = true;
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
    final messages = conversation.messages
        .where((message) => message.media.isNotEmpty)
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
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
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
    final previousTargets = _eventSubscriptionTargetKeys(_settings);
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
    final targetsChanged = !listEquals(
      previousTargets,
      _eventSubscriptionTargetKeys(_settings),
    );
    if (_isPolling && !_usingPollingFallback && targetsChanged) {
      await _stopEventListening();
      if (_isPolling && !_disposed) unawaited(_startEventListening());
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
        _editingMessageInFlight ||
        !isAuthorized) {
      return false;
    }
    _isSending = true;
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
    try {
      final sent = await _service.sendWithDetails(
        conversation: conversation,
        text: content,
        uuid: _uuid.v4(),
      );
      _rememberRemoteConversationId(conversation, sent?.conversationId);
      final sentMessage = _bindSentMessageId(
        conversation,
        localMessage,
        sent?.messageId,
      );
      await _enqueueAiResponse(
        conversation,
        content,
        sourceMessageId: sentMessage.id,
      );
      return true;
    } catch (error, stack) {
      _setError('发送钉钉消息', error, stack);
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
    if (conversation == null ||
        normalizedPath.isEmpty ||
        _isSending ||
        _editingMessageInFlight ||
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
    final message = DingTalkGatewayMessage(
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
          sizeBytes: stat.size,
          localPath: normalizedPath,
        ),
      ],
      fromSelf: true,
    );
    _isSending = true;
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
        current.id.startsWith('local-') ||
        current.id.startsWith('assistant-') ||
        current.content.trim() == normalized) {
      return false;
    }
    _editingMessageInFlight = true;
    _clearError();
    _notify();
    try {
      await _service
          .editMessage(
            conversation: conversation,
            messageId: current.id,
            text: normalized,
          )
          .timeout(const Duration(seconds: 30));
      if (_disposed ||
          !identical(_conversations[conversation.id], conversation) ||
          index >= conversation.messages.length ||
          conversation.messages[index].id != current.id) {
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

  DingTalkGatewayMessage _bindSentMessageId(
    DingTalkConversation conversation,
    DingTalkGatewayMessage localMessage,
    String? remoteMessageId,
  ) {
    final id = remoteMessageId?.trim() ?? '';
    if (id.isEmpty || id == localMessage.id) return localMessage;
    final index = conversation.messages.indexWhere(
      (message) => message.id == localMessage.id,
    );
    if (index < 0) return localMessage;
    final sentMessage = localMessage.copyWith(id: id);
    conversation.messages[index] = sentMessage;
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
      final stream = await _service.startEventSubscription(
        targets: <DingTalkConversationTarget>[
          ..._settings.allowedGroupTargets,
          ..._settings.allowedContactTargets,
        ],
      );
      if (!_isPolling || _disposed) {
        await _service.stopEventSubscription();
        return;
      }
      _eventSubscription = stream.listen(
        _handleIncomingEvent,
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
    if (conversation.type == DingTalkConversationType.direct) {
      final remoteConversationId = message.conversationId.trim();
      if (remoteConversationId.isNotEmpty &&
          conversation.openConversationId != remoteConversationId) {
        conversation.openConversationId = remoteConversationId;
        _queuePersist();
      }
    }
    _appendMessage(conversation, message);
    _unreadCount += 1;
    if (_settings.reminderMode == DingTalkReminderMode.sound) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    unawaited(_cacheAndEnqueueIncomingMessage(conversation, message));
    _notify();
  }

  void _handleIncomingEvent(DingTalkGatewayEvent event) {
    if (!_isPolling || _disposed) return;
    if (event.type == DingTalkGatewayEventType.message) {
      final message = event.message;
      if (message != null) _handleIncomingMessage(message);
      return;
    }
    final conversation = _conversationForEvent(event);
    if (conversation == null) return;
    final index = conversation.messages.indexWhere(
      (message) => message.id == event.messageId,
    );
    if (index < 0) return;
    final current = conversation.messages[index];
    DingTalkGatewayMessage? updated;
    switch (event.type) {
      case DingTalkGatewayEventType.read:
        if (!current.readByPeer) {
          updated = current.copyWith(readByPeer: true);
        }
      case DingTalkGatewayEventType.recall:
        if (!current.recalled) {
          updated = current.copyWith(recalled: true);
        }
      case DingTalkGatewayEventType.reaction:
        final reaction = event.reaction.trim();
        if (reaction.isEmpty) return;
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
        return;
    }
    if (updated == null) return;
    conversation.messages[index] = updated;
    _queuePersist();
    _notify();
  }

  DingTalkConversation? _conversationForEvent(DingTalkGatewayEvent event) {
    final conversationId = event.conversationId.trim();
    if (conversationId.isEmpty) return null;
    for (final conversation in _conversations.values) {
      if (conversation.type != event.conversationType) continue;
      if (conversation.messages.any(
        (message) => message.id == event.messageId,
      )) {
        return conversation;
      }
      if (conversation.type == DingTalkConversationType.group) {
        if (conversation.id == conversationId) return conversation;
        continue;
      }
      if (conversation.id == conversationId ||
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

  List<String> _eventSubscriptionTargetKeys(DingTalkGatewaySettings settings) {
    final keys = <String>{};
    for (final target in <DingTalkConversationTarget>[
      ...settings.allowedGroupTargets,
      ...settings.allowedContactTargets,
    ]) {
      final id = target.id.trim();
      if (id.isEmpty) continue;
      final subscriptionTarget = target.type == DingTalkConversationType.group
          ? id
          : target.openDingTalkId.trim().isNotEmpty
          ? target.openDingTalkId.trim()
          : target.userId.trim().isNotEmpty
          ? target.userId.trim()
          : id;
      keys.add('${target.type.name}:$subscriptionTarget');
    }
    return keys.toList(growable: false)..sort();
  }

  Future<void> _cacheAndEnqueueIncomingMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) async {
    try {
      final hydrated = await ensureMessageMediaCached(
        conversationId: conversation.id,
        messageId: message.id,
      );
      final effective = hydrated ?? message;
      await _enqueueAiResponse(
        conversation,
        effective.content,
        sourceMessageId: effective.id,
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '准备钉钉媒体消息', error, stack);
      await _enqueueAiResponse(
        conversation,
        message.content,
        sourceMessageId: message.id,
      );
    }
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
    String sourceMessageId,
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
      final dwsCatalog = _settings.allowedDingTalkDwsCommandIds.isEmpty
          ? const <AiDingTalkDwsCommand>[]
          : (await _service.loadDwsCommandCatalog())
                .where(
                  (command) => _settings.allowedDingTalkDwsCommandIds.contains(
                    command.cliPath,
                  ),
                )
                .toList(growable: false);
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
      final attachmentPaths = _attachmentPathsForTurn(
        conversation,
        sourceMessageId,
      );
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
      final echoCoordinator = _DingTalkEchoCoordinator(
        baselineMessageIds: baselineMessageIds,
        selectedTypes: _settings.responseEchoTypes.toSet(),
        typeOf: _echoTypeOf,
        textFor: _echoTextForMessage,
        isTerminal: _isEchoTerminal,
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
        },
      );

      AiSession? currentSession() {
        for (final item in _sessionController.sessions) {
          if (item.id == sessionId) return item;
        }
        return null;
      }

      void onSessionChanged() {
        if (_disposed) return;
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
        final sent = await _sessionController.sendMessage(
          sessionId: sessionId,
          content: content,
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
          userMessageMetadata: const <String, Object?>{
            'sent_via': 'dingtalk_gateway',
          },
        );
        if (!sent) return;
      } finally {
        _sessionController.removeListener(onSessionChanged);
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
        } finally {
          echoCoordinator.dispose();
        }
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '生成钉钉 AI 回复', error, stack);
    } finally {
      _responseInFlight.remove(conversation.id);
      _notify();
    }
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
  }) {
    final normalized = content.trim();
    if (normalized.isEmpty || _disposed) return Future<void>.value();
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
              openConversationId: conversation.openConversationId,
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
    if (_disposed || _notificationQueued) return;
    // dws 运行日志使用同步广播流，设置弹窗挂载/构建期间可能立即触发
    // 通知。合并到微任务，避免 Flutter 在 build 阶段标记组件重建。
    _notificationQueued = true;
    scheduleMicrotask(() {
      _notificationQueued = false;
      if (!_disposed) notifyListeners();
    });
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
    _mediaGenerationService.dispose();
    await _service.cancelAuthorization();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
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

/// 单轮钉钉 AI 回显协调器：首次发送后只编辑同一条消息，并合并高频流式增量。
class _DingTalkEchoCoordinator {
  _DingTalkEchoCoordinator({
    required Set<String> baselineMessageIds,
    required Set<DingTalkResponseEchoType> selectedTypes,
    required _DingTalkEchoTypeResolver typeOf,
    required _DingTalkEchoTextBuilder textFor,
    required _DingTalkEchoTerminalResolver isTerminal,
    required _DingTalkEchoSender send,
    required _DingTalkEchoEditor edit,
    required String Function() newUuid,
    required _DingTalkEchoErrorHandler onError,
  }) : _baselineMessageIds = baselineMessageIds,
       _selectedTypes = selectedTypes,
       _typeOf = typeOf,
       _textFor = textFor,
       _isTerminal = isTerminal,
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
    if (_disposed || _selectedTypes.isEmpty) return;
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
    if (_disposed || _activeDrain != null) return;
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
    while (!_disposed && _pending.isNotEmpty) {
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
      if (!state.sent) {
        state.remoteMessageId = await _send(
          pending.source,
          pending.text,
          state.uuid,
        );
        state.sent = true;
      } else {
        final messageId = state.remoteMessageId?.trim() ?? '';
        if (messageId.isNotEmpty) {
          await _edit(messageId, pending.text);
        }
      }
      state.lastText = pending.text;
      state.lastMutationAt = DateTime.now();
      state.finished = pending.terminal;
    } catch (error, stack) {
      state.lastMutationAt = DateTime.now();
      _onError(state.sent ? '编辑钉钉 AI 回显消息' : '发送钉钉 AI 回显消息', error, stack);
      if (pending.terminal &&
          state.sent &&
          (state.remoteMessageId?.trim().isNotEmpty ?? false)) {
        try {
          state.remoteMessageId = await _send(
            pending.source,
            pending.text,
            _newUuid(),
          );
          state.lastText = pending.text;
        } catch (fallbackError, fallbackStack) {
          _onError('补发钉钉 AI 终态回显消息', fallbackError, fallbackStack);
        }
      }
      state.finished = pending.terminal;
    }
  }

  Future<void> flush() async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _scheduledAt = null;
    while (!_disposed && (_pending.isNotEmpty || _activeDrain != null)) {
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

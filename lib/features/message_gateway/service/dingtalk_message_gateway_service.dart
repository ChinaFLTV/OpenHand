import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/bounded_log_buffer.dart';
import '../../plugin_service/index.dart';
import '../model/dingtalk_message_gateway.dart';

class DingTalkGatewayQueryResult {
  const DingTalkGatewayQueryResult({required this.messages, this.warning});

  final List<DingTalkGatewayMessage> messages;
  final String? warning;
}

/// dws 返回的业务错误。可选详情接口失败时由调用方按错误类别降级处理。
class DingTalkGatewayCommandException implements Exception {
  const DingTalkGatewayCommandException({
    required this.message,
    this.category,
    this.reason,
    this.serverCode,
    this.operation,
  });

  final String message;
  final String? category;
  final String? reason;
  final String? serverCode;
  final String? operation;

  bool get isBusinessError =>
      category == 'api' ||
      reason == 'business_error' ||
      (serverCode != null && serverCode!.trim().isNotEmpty);

  bool get isPermissionDenied =>
      serverCode == '2001' ||
      message.contains('无花名册管理权限') ||
      message.contains('权限不足') ||
      message.contains('无权限');

  @override
  String toString() => message;
}

class DingTalkMessageGatewayService {
  static const Duration _commandTimeout = Duration(seconds: 25);
  static const Duration _authTimeout = Duration(minutes: 15);
  static const Duration _eventProcessStartTimeout = Duration(seconds: 10);
  static const Duration _eventReadyTimeout = Duration(seconds: 30);
  static const Duration _mediaDownloadTimeout = Duration(minutes: 3);
  static const int _batchSize = 30;
  static const int _detailConcurrency = 4;
  static const int _maxMediaCacheFiles = 512;
  static const int _maxMediaCacheBytes = 1024 * 1024 * 1024;
  static const int _maxMediaFileBytes = 512 * 1024 * 1024;
  Process? _authProcess;
  Process? _eventProcess;
  StreamController<DingTalkGatewayMessage>? _eventController;
  StreamSubscription<String>? _eventStdoutSubscription;
  StreamSubscription<String>? _eventStderrSubscription;
  Future<Stream<DingTalkGatewayMessage>>? _eventStartFuture;
  int _eventGeneration = 0;
  String? _executable;
  bool _authCancelled = false;
  bool _rosterAccessDenied = false;
  final BoundedLogBuffer _runtimeLogs = BoundedLogBuffer(
    maxLines: 3000,
    maxCharacters: 300000,
  );
  final StreamController<String> _runtimeLogController =
      StreamController<String>.broadcast(sync: true);
  final Map<String, Future<String?>> _mediaDownloadTasks =
      <String, Future<String?>>{};
  int _runtimeLogSequence = 0;

  List<String> get runtimeLogs => _runtimeLogs.snapshot();
  int get runtimeLogRevision => _runtimeLogs.revision;
  Stream<String> get runtimeLogStream => _runtimeLogController.stream;

  String get mediaCacheDirectoryPath =>
      p.join(OpenHandPaths.defaultMessageGatewayDirectoryPath(), 'media');

  void clearRuntimeLogs() => _runtimeLogs.clear();

  void _logRuntime(String level, String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final stamp = DateTime.now().toLocal().toIso8601String();
    final line = '[$stamp] [$level] [$_runtimeLogSequence] $normalized';
    _runtimeLogSequence += 1;
    _runtimeLogs.add(line);
    if (!_runtimeLogController.isClosed) {
      _runtimeLogController.add(line);
    }
  }

  String _safeProcessLogLine(String line) {
    var value = line.trim();
    if (value.length > 2000) value = '${value.substring(0, 2000)}…';
    // dws 输出可能包含授权码、令牌或密钥，日志只保留诊断所需的结构。
    value = value.replaceAll(
      RegExp(
        r'''((?:access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization|user[_-]?code|secret)\s*[:=]\s*)([^,\s}"']+)''',
        caseSensitive: false,
      ),
      r'$1<已脱敏>',
    );
    return value;
  }

  String? get cachedExecutable => _executable;

  Future<Stream<DingTalkGatewayMessage>> startEventSubscription() {
    final current = _eventController;
    if (current != null) {
      return Future<Stream<DingTalkGatewayMessage>>.value(current.stream);
    }
    final pending = _eventStartFuture;
    if (pending != null) return pending;
    final future = _startEventSubscription();
    _eventStartFuture = future;
    return future.whenComplete(() {
      if (identical(_eventStartFuture, future)) _eventStartFuture = null;
    });
  }

  Future<Stream<DingTalkGatewayMessage>> _startEventSubscription() async {
    final generation = _eventGeneration;
    final executable = await _requireExecutable();
    _logRuntime('INFO', '启动钉钉实时事件监听。');
    if (generation != _eventGeneration) {
      throw StateError('钉钉实时事件监听已取消。');
    }
    final controller = StreamController<DingTalkGatewayMessage>();
    final ready = Completer<void>();
    _eventController = controller;
    Process? process;
    try {
      process = await startTrackedProcessBounded(
        executable,
        // 仅监听 @ 当前账号的群消息与全部单聊，群聊未 @ 时不触发响应。
        const <String>[
          'event',
          'consume',
          'user_im_message_receive_at',
          'user_im_message_receive_o2o_all',
          '--flatten',
          '--format',
          'ndjson',
          '--ephemeral',
        ],
        timeout: _eventProcessStartTimeout,
        tag: 'dingtalk.event.consume',
        startInNewProcessGroup: true,
      );
      if (generation != _eventGeneration) {
        await terminateTrackedProcessTree(
          process,
          gracefulTimeout: const Duration(seconds: 2),
        );
        await controller.close();
        throw StateError('钉钉实时事件监听已取消。');
      }
      _eventProcess = process;
      _logRuntime('INFO', '实时事件监听进程已启动（PID ${process.pid}）。');
      _eventStdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              _logRuntime('DEBUG', '实时事件标准输出一行（${line.length} 字符）。');
              _consumeEventLine(line);
            },
            onError: (Object error, StackTrace stack) {
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
          );
      _eventStderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final normalized = line.trim();
              if (normalized.isNotEmpty &&
                  !normalized.contains('[event] ready')) {
                _logRuntime(
                  'WARN',
                  '实时事件标准错误：${_safeProcessLogLine(normalized)}',
                );
              }
              if (normalized.contains('[event] ready')) {
                if (!ready.isCompleted) ready.complete();
                _logRuntime('SUCCESS', '实时事件监听已就绪。');
              } else if (normalized.startsWith('Error:') &&
                  !ready.isCompleted) {
                ready.completeError(StateError(normalized));
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
          );
      unawaited(_watchEventProcess(process, ready, generation));
      await ready.future.timeout(_eventReadyTimeout);
      if (generation != _eventGeneration) {
        throw StateError('钉钉实时事件监听已取消。');
      }
      return controller.stream;
    } catch (_) {
      _logRuntime('ERROR', '启动钉钉实时事件监听失败。');
      if (generation == _eventGeneration) {
        await stopEventSubscription();
      } else {
        if (process != null && identical(_eventProcess, process)) {
          _eventProcess = null;
          await terminateTrackedProcessTree(
            process,
            gracefulTimeout: const Duration(seconds: 2),
          );
        }
        await controller.close();
      }
      rethrow;
    }
  }

  Future<void> _watchEventProcess(
    Process process,
    Completer<void> ready,
    int generation,
  ) async {
    final exitCode = await process.exitCode;
    if (!ready.isCompleted) {
      ready.completeError(StateError('钉钉实时事件监听进程提前退出（退出码 $exitCode）。'));
    }
    if (generation != _eventGeneration || !identical(_eventProcess, process)) {
      return;
    }
    if (exitCode != 0) {
      _logRuntime('ERROR', '实时事件监听进程退出，退出码 $exitCode。');
      silentLog('dingtalk_gateway', '实时事件监听进程退出', StateError('退出码 $exitCode'));
    } else {
      _logRuntime('INFO', '实时事件监听进程已退出。');
    }
    _eventProcess = null;
    final controller = _eventController;
    _eventController = null;
    final stdoutSubscription = _eventStdoutSubscription;
    final stderrSubscription = _eventStderrSubscription;
    _eventStdoutSubscription = null;
    _eventStderrSubscription = null;
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    await controller?.close();
  }

  Future<void> stopEventSubscription() async {
    _eventGeneration++;
    _eventStartFuture = null;
    final process = _eventProcess;
    _eventProcess = null;
    final controller = _eventController;
    _eventController = null;
    final stdoutSubscription = _eventStdoutSubscription;
    final stderrSubscription = _eventStderrSubscription;
    _eventStdoutSubscription = null;
    _eventStderrSubscription = null;
    await stdoutSubscription?.cancel();
    await stderrSubscription?.cancel();
    if (process != null) {
      _logRuntime('INFO', '正在停止钉钉实时事件监听。');
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: const Duration(seconds: 2),
      );
    }
    if (process != null) _logRuntime('SUCCESS', '钉钉实时事件监听已停止。');
    await controller?.close();
  }

  /// 将钉钉消息中的媒体资源下载到确定性本地缓存。缓存文件不存在时会自动重取，
  /// 同一资源并发请求会合并为一次 dws 调用，避免切换会话时重复下载。
  Future<String?> ensureMediaCached(DingTalkGatewayMedia media) async {
    final resourceId = media.resourceId.trim();
    if (resourceId.isEmpty) return null;
    final taskKey = '${media.resourceType.name}:$resourceId';
    final active = _mediaDownloadTasks[taskKey];
    if (active != null) return active;
    final task = _ensureMediaCached(media);
    _mediaDownloadTasks[taskKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_mediaDownloadTasks[taskKey], task)) {
        _mediaDownloadTasks.remove(taskKey);
      }
    }
  }

  Future<String?> _ensureMediaCached(DingTalkGatewayMedia media) async {
    final directory = Directory(mediaCacheDirectoryPath);
    await directory.create(recursive: true);
    final extension = _mediaCacheExtension(media);
    final filename = '${_stableMediaCacheName(media)}$extension';
    final output = File(p.join(directory.path, filename));
    try {
      if (await output.exists() && await output.length() > 0) {
        return output.path;
      }
      if (await output.exists()) await output.delete();
      if (media.resourceType == DingTalkMediaResourceType.mediaId &&
          (media.messageId.trim().isEmpty ||
              media.conversationId.trim().isEmpty)) {
        _logRuntime('WARN', '钉钉媒体缺少消息或会话上下文，暂不下载：${media.displayName}。');
        return null;
      }
      final args = <String>[
        'chat',
        '+messages-resource-download',
        '--resource-id',
        media.resourceId.trim(),
        '--output',
        filename,
        '--format',
        'json',
      ];
      if (media.resourceType == DingTalkMediaResourceType.mediaId) {
        args.addAll(<String>[
          '--message-id',
          media.messageId,
          '--open-conversation-id',
          media.conversationId,
        ]);
      } else {
        args.addAll(<String>['--type', 'fileId']);
      }
      await _runJson(
        args,
        workingDirectory: directory.path,
        timeout: _mediaDownloadTimeout,
      );
      if (!await output.exists()) {
        throw StateError('钉钉媒体下载完成但未找到本地文件。');
      }
      final outputBytes = await output.length();
      if (outputBytes <= 0) {
        throw StateError('钉钉媒体下载完成但文件为空。');
      }
      if (outputBytes > _maxMediaFileBytes) {
        await output.delete();
        throw StateError('钉钉媒体超过 512MB 本地缓存上限。');
      }
      _logRuntime('SUCCESS', '钉钉媒体已缓存：${media.displayName}。');
      unawaited(_pruneMediaCache(directory));
      return output.path;
    } catch (error, stack) {
      // dws 超时或中断时可能留下半截文件，不能让下一次请求误认为缓存有效。
      try {
        if (await output.exists()) await output.delete();
      } catch (cleanupError, cleanupStack) {
        silentLog(
          'dingtalk_gateway',
          '清理损坏的钉钉媒体缓存',
          cleanupError,
          cleanupStack,
        );
      }
      _logRuntime('WARN', '缓存钉钉媒体失败：${media.displayName}。');
      silentLog('dingtalk_gateway', '缓存钉钉媒体', error, stack);
      return null;
    }
  }

  String _stableMediaCacheName(DingTalkGatewayMedia media) {
    final raw = '${media.resourceType.name}:${media.resourceId}';
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'media-${digest.substring(0, 24)}';
  }

  String _mediaCacheExtension(DingTalkGatewayMedia media) {
    final source = p.extension(media.name.trim()).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(source)) return source;
    return switch (media.kind) {
      DingTalkMediaKind.image => '.jpg',
      DingTalkMediaKind.video => '.mp4',
      DingTalkMediaKind.audio => '.m4a',
      DingTalkMediaKind.file => '.bin',
    };
  }

  Future<void> _pruneMediaCache(Directory directory) async {
    try {
      final files = await directory
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .take(_maxMediaCacheFiles + 128)
          .toList();
      final entries = <(File, int, DateTime)>[];
      var totalBytes = 0;
      for (final file in files) {
        try {
          final stat = await file.stat();
          totalBytes += stat.size;
          entries.add((file, stat.size, stat.modified));
        } catch (_) {}
      }
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      while (entries.length > _maxMediaCacheFiles ||
          totalBytes > _maxMediaCacheBytes) {
        final entry = entries.removeAt(0);
        totalBytes -= entry.$2;
        try {
          await entry.$1.delete();
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '清理钉钉媒体缓存', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '扫描钉钉媒体缓存', error, stack);
    }
  }

  Future<String?> executable() async {
    return _executable ??= await resolvePluginDingtalkWorkspaceCliExecutable();
  }

  Future<DingTalkAuthStatus> authStatus() async {
    final decoded = await _runJson(const <String>[
      'auth',
      'status',
      '--format',
      'json',
    ]);
    final map = _asMap(decoded);
    final authenticated =
        _asBool(map['authenticated']) ||
        _asBool(_asMap(map['data'])['authenticated']);
    final identityMap = _asMap(map['identity']).isNotEmpty
        ? _asMap(map['identity'])
        : _asMap(map['profile']);
    return DingTalkAuthStatus(
      authenticated: authenticated,
      identity: DingTalkIdentity(
        profile: '${identityMap['profile'] ?? map['profile'] ?? ''}',
        userId:
            '${identityMap['userId'] ?? identityMap['user_id'] ?? identityMap['openDingTalkId'] ?? ''}',
        name:
            '${identityMap['name'] ?? identityMap['nick'] ?? identityMap['userName'] ?? ''}',
      ),
    );
  }

  Future<DingTalkAuthStatus> authorize({
    required Future<void> Function(String url) onDeviceUrl,
  }) async {
    _authCancelled = false;
    _rosterAccessDenied = false;
    _logRuntime('INFO', '启动钉钉设备流授权。');
    late final String executable;
    try {
      executable = await _requireExecutable();
    } catch (error) {
      _logRuntime('ERROR', '启动授权失败，未找到 dws：$error');
      rethrow;
    }
    final process = await startTrackedProcessBounded(
      executable,
      const <String>[
        'auth',
        'login',
        '--device',
        '--no-browser',
        '--format',
        'json',
      ],
      timeout: const Duration(seconds: 8),
      tag: 'dingtalk.auth.login',
      startInNewProcessGroup: true,
    );
    _authProcess = process;
    _logRuntime('INFO', '钉钉设备流授权进程已启动（PID ${process.pid}）。');
    final output = StringBuffer();
    late final StreamSubscription<String> stdoutSub;
    late final StreamSubscription<String> stderrSub;
    var opened = false;
    String? authorizationCode;
    String? pendingUrl;

    Future<void> openPendingUrl() async {
      if (opened || pendingUrl == null) return;
      final rawUrl = pendingUrl!;
      final code = authorizationCode;
      var url = rawUrl;
      if (code != null && code.isNotEmpty) {
        final parsed = Uri.tryParse(rawUrl);
        if (parsed != null) {
          final query = <String, String>{
            ...parsed.queryParameters,
            'user_code': code,
          };
          url = parsed.replace(queryParameters: query).toString();
        }
      }
      opened = true;
      await onDeviceUrl(url);
    }

    void consume(String line) {
      output.writeln(line);
      if (opened) return;
      final code = RegExp(
        r'authorization\s+code\s*:\s*([A-Za-z0-9]+(?:-[A-Za-z0-9]+)?)',
        caseSensitive: false,
      ).firstMatch(line)?.group(1);
      if (code != null && code.trim().isNotEmpty) {
        authorizationCode = code.trim();
      }
      final url = RegExp(r'https?://[^\s]+').firstMatch(line)?.group(0);
      if (url != null) {
        pendingUrl = url.replaceAll(RegExp(r'[),.]+$'), '');
      }
      if (pendingUrl != null &&
          (authorizationCode != null || pendingUrl!.contains('user_code='))) {
        unawaited(openPendingUrl());
      }
    }

    stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _logRuntime('DEBUG', '授权标准输出：${_safeProcessLogLine(line)}');
            consume(line);
          },
          onError: (Object error, StackTrace stack) {
            _logRuntime('ERROR', '读取授权标准输出失败：$error');
            silentLog('dingtalk_gateway', '读取授权输出', error, stack);
          },
        );
    stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _logRuntime('WARN', '授权标准错误：${_safeProcessLogLine(line)}');
            consume(line);
          },
          onError: (Object error, StackTrace stack) {
            _logRuntime('ERROR', '读取授权标准错误失败：$error');
            silentLog('dingtalk_gateway', '读取授权错误输出', error, stack);
          },
        );
    try {
      final exitCode = await process.exitCode.timeout(
        _authTimeout,
        onTimeout: () async {
          await terminateTrackedProcessTree(
            process,
            gracefulTimeout: const Duration(seconds: 2),
          );
          return -1;
        },
      );
      if (exitCode != 0) {
        _logRuntime('ERROR', '钉钉设备流授权进程退出，退出码 $exitCode。');
        if (_authCancelled) return authStatus();
        throw StateError(
          output.toString().trim().isEmpty
              ? '钉钉授权未完成。'
              : output.toString().trim(),
        );
      }
      _logRuntime('SUCCESS', '钉钉设备流授权进程已完成。');
      return await authStatus();
    } finally {
      _authProcess = null;
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  Future<void> cancelAuthorization() async {
    _authCancelled = true;
    _logRuntime('WARN', '正在取消钉钉设备流授权。');
    final process = _authProcess;
    _authProcess = null;
    if (process != null) {
      await terminateTrackedProcessTree(
        process,
        gracefulTimeout: const Duration(seconds: 1),
      );
    }
    _logRuntime('INFO', '钉钉设备流授权已取消。');
  }

  Future<DingTalkAuthStatus> logout({String? profile}) async {
    _rosterAccessDenied = false;
    final args = <String>['auth', 'logout'];
    if (profile != null && profile.trim().isNotEmpty) {
      args.addAll(<String>['--profile', profile.trim()]);
    }
    args.addAll(const <String>['--yes', '--format', 'json']);
    await _runJson(args);
    return authStatus();
  }

  Future<DingTalkGatewayQueryResult> query({
    required DateTime start,
    required DateTime end,
  }) async {
    final startText = start.toIso8601String();
    final endText = end.toIso8601String();
    final allStartText = _formatChatDateTime(start);
    final allEndText = _formatChatDateTime(end);
    final mentions = await _runJson(<String>[
      'chat',
      'message',
      'list-mentions',
      '--start',
      startText,
      '--end',
      endText,
      '--limit',
      '50',
      '--cursor',
      '0',
      '--format',
      'json',
    ]);
    final all = await _runJson(<String>[
      'chat',
      'message',
      'list-all',
      '--start',
      allStartText,
      '--end',
      allEndText,
      '--limit',
      '50',
      '--cursor',
      '0',
      '--format',
      'json',
    ]);
    final messages = <DingTalkGatewayMessage>[
      ..._parseMessages(mentions, mentionedCurrentUser: true),
      ..._parseMessages(all),
    ];
    final allMap = _asMap(all);
    final warning =
        allMap['friendly_hint']?.toString() ??
        _asMap(allMap['data'])['friendly_hint']?.toString();
    return DingTalkGatewayQueryResult(messages: messages, warning: warning);
  }

  Future<List<DingTalkConversationTarget>> searchTargets({
    required DingTalkConversationType type,
    required String query,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const <DingTalkConversationTarget>[];
    final arguments = type == DingTalkConversationType.group
        ? <String>[
            'chat',
            '+chat-search',
            '--query',
            keyword,
            '--limit',
            '20',
            '--format',
            'json',
          ]
        : <String>[
            'contact',
            '+search-user',
            '--query',
            keyword,
            '--format',
            'json',
          ];
    final decoded = await _runJson(arguments);
    return _parseTargets(decoded, type: type);
  }

  Future<void> send({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
  }) async {
    await _runJson(<String>[
      'chat',
      'message',
      'send',
      ..._targetArguments(conversation),
      '--text',
      text,
      '--uuid',
      uuid,
      '--format',
      'json',
    ]);
  }

  Future<void> sendFile({
    required DingTalkConversation conversation,
    required String filePath,
    required String uuid,
    bool audio = false,
  }) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) throw const FormatException('文件路径为空。');
    await _runJson(<String>[
      'chat',
      'message',
      'send',
      ..._targetArguments(conversation),
      '--msg-type',
      audio ? 'audio' : 'file',
      '--file-path',
      normalizedPath,
      '--uuid',
      uuid,
      '--format',
      'json',
    ]);
  }

  List<String> _targetArguments(DingTalkConversation conversation) {
    final directOpenId = conversation.directOpenDingTalkId?.trim() ?? '';
    final targetFlag = conversation.type == DingTalkConversationType.group
        ? '--group'
        : directOpenId.isNotEmpty
        ? '--open-dingtalk-id'
        : '--user';
    final target = conversation.type == DingTalkConversationType.group
        ? conversation.id
        : directOpenId.isNotEmpty
        ? directOpenId
        : (conversation.directUserId ?? conversation.id);
    return <String>[targetFlag, target];
  }

  /// 查询会话及其关联资料。返回原始 JSON，调用方负责结构化展示字段。
  Future<Object?> conversationDetails({
    required DingTalkConversation conversation,
  }) async {
    final result = <String, Object?>{};
    if (conversation.type == DingTalkConversationType.group) {
      final initialDetails = await Future.wait(
        <Future<MapEntry<String, Object?>?>>[
          _loadDetail('会话信息', () => _loadConversationInfo(conversation)),
          _loadDetail(
            '群聊设置',
            () => _runJson(<String>[
              'chat',
              'group',
              'user-settings',
              'query',
              '--groups',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '禁言配置',
            () => _runJson(<String>[
              'chat',
              'group',
              'get-mute-config',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '群机器人',
            () => _runJson(<String>[
              'chat',
              'group',
              'bots',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail(
            '群身份',
            () => _runJson(<String>[
              'chat',
              'group-role',
              'list',
              '--group',
              conversation.id,
              '--format',
              'json',
            ]),
          ),
          _loadDetail('群成员', () => _loadAllGroupMembers(conversation.id)),
        ],
      );
      for (final entry in initialDetails.nonNulls) {
        result[entry.key] = entry.value;
      }

      final members = result['群成员'];
      final memberUserIds = _extractUserIds(members);
      Object? memberProfiles;
      if (memberUserIds.isNotEmpty) {
        final profileEntry = await _loadDetail(
          '群成员资料',
          () => _loadUserDetails(memberUserIds),
        );
        if (profileEntry != null) {
          memberProfiles = profileEntry.value;
          result[profileEntry.key] = profileEntry.value;
        }
      }
      final memberOpenIds = <String>{
        ..._extractOpenDingTalkIds(members),
        ..._extractOpenDingTalkIds(memberProfiles),
      }.toList(growable: false);
      final enrichmentDetails =
          await Future.wait(<Future<MapEntry<String, Object?>?>>[
            if (memberOpenIds.isNotEmpty)
              _loadDetail(
                '群成员详情',
                () => _loadGroupMemberDetails(conversation.id, memberOpenIds),
              ),
            if (_extractGroupRoleIds(result['群身份']).isNotEmpty &&
                (memberUserIds.isNotEmpty || memberOpenIds.isNotEmpty))
              _loadDetail(
                '群成员身份',
                () => _loadGroupMemberRoles(
                  conversation.id,
                  memberUserIds.isNotEmpty ? memberUserIds : memberOpenIds,
                ),
              ),
          ]);
      for (final entry in enrichmentDetails.nonNulls) {
        result[entry.key] = entry.value;
      }
    } else {
      final initialDetails = await Future.wait(
        <Future<MapEntry<String, Object?>?>>[
          _loadDetail('会话信息', () => _loadConversationInfo(conversation)),
          _loadDetail('联系人信息', () => _loadContact(conversation)),
          if (!_rosterAccessDenied) _loadDetail('可见花名册字段', _loadRosterFields),
          _loadDetail(
            '特别关注列表',
            () => _runJson(const <String>[
              'contact',
              'relation',
              'list-my-followings',
              '--format',
              'json',
            ]),
          ),
        ],
      );
      for (final entry in initialDetails.nonNulls) {
        result[entry.key] = entry.value;
      }

      final contact = result['联系人信息'];
      final staffId = _extractFirstStaffId(contact);
      final departmentIds = _extractDepartmentIds(contact);
      final contactDetails =
          await Future.wait(<Future<MapEntry<String, Object?>?>>[
            if (staffId.isNotEmpty && !_rosterAccessDenied)
              _loadDetail('联系人档案', () => _loadRosterProfile(staffId)),
            if (departmentIds.isNotEmpty)
              _loadDetail('部门资料', () => _loadDepartmentDetails(departmentIds)),
          ]);
      for (final entry in contactDetails.nonNulls) {
        result[entry.key] = entry.value;
      }
      final following = result.remove('特别关注列表');
      if (following != null) {
        result['关注状态'] = _matchFollowingContact(following, <String>{
          conversation.id,
          ..._extractContactIds(contact),
        });
      }
    }
    return result;
  }

  Future<MapEntry<String, Object?>?> _loadDetail(
    String name,
    Future<Object?> Function() loader,
  ) async {
    try {
      final value = await loader();
      return MapEntry<String, Object?>(name, value);
    } catch (error, stack) {
      final normalizedError = _normalizeCommandException(error);
      if (normalizedError?.isPermissionDenied == true &&
          (name.contains('花名册') || name.contains('联系人档案'))) {
        _rosterAccessDenied = true;
      }
      if (normalizedError?.isBusinessError == true ||
          _looksLikeBusinessError(error)) {
        return null;
      }
      silentLog('dingtalk_gateway', '读取$name', error, stack);
      return null;
    }
  }

  Future<Object?> _loadContact(DingTalkConversation conversation) async {
    try {
      return await _runJson(<String>[
        'contact',
        'user',
        'get',
        '--ids',
        conversation.directUserId ?? conversation.id,
        '--format',
        'json',
      ]);
    } catch (error, stack) {
      try {
        return await _runJson(<String>[
          'contact',
          '+lookup',
          '--name',
          conversation.title,
          '--format',
          'json',
        ]);
      } catch (fallbackError, fallbackStack) {
        if (!_looksLikeBusinessError(error)) {
          silentLog('dingtalk_gateway', '按标识读取联系人', error, stack);
        }
        if (!_looksLikeBusinessError(fallbackError)) {
          silentLog(
            'dingtalk_gateway',
            '按名称读取联系人',
            fallbackError,
            fallbackStack,
          );
        }
        rethrow;
      }
    }
  }

  Future<Object?> _loadRosterFields() async {
    try {
      return await _runJson(const <String>[
        'contact',
        'user',
        'profile',
        'fields',
        '--format',
        'json',
      ]);
    } catch (error) {
      if (_isPermissionDeniedError(error)) _rosterAccessDenied = true;
      rethrow;
    }
  }

  Future<Object?> _loadRosterProfile(String staffId) async {
    try {
      return await _runJson(<String>[
        'contact',
        'user',
        'profile',
        'get',
        '--staff-id',
        staffId,
        '--format',
        'json',
      ]);
    } catch (error) {
      if (_isPermissionDeniedError(error)) _rosterAccessDenied = true;
      rethrow;
    }
  }

  bool _isPermissionDeniedError(Object error) {
    final normalized = _normalizeCommandException(error);
    if (normalized != null) return normalized.isPermissionDenied;
    final text = '$error';
    return text.contains('无花名册管理权限') ||
        text.contains('权限不足') ||
        text.contains('无权限') ||
        text.contains('server_error_code') && text.contains('2001');
  }

  bool _looksLikeBusinessError(Object error) {
    if (error is DingTalkGatewayCommandException) {
      return error.isBusinessError;
    }
    final text = '$error';
    return text.contains('"category"') &&
        (text.contains('"reason"') || text.contains('server_error_code'));
  }

  DingTalkGatewayCommandException? _normalizeCommandException(Object error) {
    if (error is DingTalkGatewayCommandException) return error;
    final text = '$error';
    final start = text.indexOf('{');
    if (start < 0) return null;
    final payload = _asMap(_decodeJson(text.substring(start)));
    final details = _asMap(payload['error']);
    if (details.isEmpty) return null;
    final message = details['message']?.toString().trim();
    return DingTalkGatewayCommandException(
      message: message == null || message.isEmpty ? 'dws 业务调用失败。' : message,
      category: details['category']?.toString(),
      reason: details['reason']?.toString(),
      serverCode: details['server_error_code']?.toString(),
      operation: details['operation']?.toString(),
    );
  }

  Future<Object?> _loadConversationInfo(
    DingTalkConversation conversation,
  ) async {
    final directOpenId = conversation.directOpenDingTalkId?.trim() ?? '';
    final primaryFlag = conversation.type == DingTalkConversationType.group
        ? '--group'
        : directOpenId.isNotEmpty
        ? '--open-dingtalk-id'
        : '--user';
    final primaryTarget = conversation.type == DingTalkConversationType.group
        ? conversation.id
        : directOpenId.isNotEmpty
        ? directOpenId
        : (conversation.directUserId ?? conversation.id);
    try {
      return await _runJson(<String>[
        'chat',
        'conversation-info',
        primaryFlag,
        primaryTarget,
        '--format',
        'json',
      ]);
    } catch (error, stack) {
      if (conversation.type == DingTalkConversationType.direct) {
        try {
          return await _runJson(<String>[
            'chat',
            'conversation-info',
            '--open-dingtalk-id',
            directOpenId.isNotEmpty ? directOpenId : conversation.id,
            '--format',
            'json',
          ]);
        } catch (fallbackError, fallbackStack) {
          if (!_looksLikeBusinessError(error)) {
            silentLog('dingtalk_gateway', '读取会话基础信息', error, stack);
          }
          if (!_looksLikeBusinessError(fallbackError)) {
            silentLog(
              'dingtalk_gateway',
              '读取会话基础信息备用标识',
              fallbackError,
              fallbackStack,
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<Object?> _loadUserDetails(List<String> userIds) async {
    final batches = <List<String>>[];
    for (var offset = 0; offset < userIds.length; offset += _batchSize) {
      final end = math.min(offset + _batchSize, userIds.length);
      batches.add(userIds.sublist(offset, end));
    }
    final pages = await _mapBounded<List<String>, Object?>(
      batches,
      (batch) => _runJson(<String>[
        'contact',
        'user',
        'get',
        '--ids',
        batch.join(','),
        '--format',
        'json',
      ]),
      onError: '读取群成员组织资料',
    );
    if (pages.isEmpty) return null;
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  Future<Object?> _loadGroupMemberDetails(
    String groupId,
    List<String> openDingTalkIds,
  ) async {
    final batches = <List<String>>[];
    for (
      var offset = 0;
      offset < openDingTalkIds.length;
      offset += _batchSize
    ) {
      final end = math.min(offset + _batchSize, openDingTalkIds.length);
      batches.add(openDingTalkIds.sublist(offset, end));
    }
    final pages = await _mapBounded<List<String>, Object?>(
      batches,
      (batch) => _runJson(<String>[
        'chat',
        'group',
        'members',
        'list-by-ids',
        '--id',
        groupId,
        '--users',
        batch.join(','),
        '--format',
        'json',
      ]),
      onError: '读取群成员群内详情',
    );
    if (pages.isEmpty) return null;
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  Future<Object?> _loadGroupMemberRoles(
    String groupId,
    List<String> userIds,
  ) async {
    final values = await _mapBounded<String, Object?>(userIds, (userId) async {
      final value = await _runJson(<String>[
        'chat',
        '+chat-role-query-user',
        '--group',
        groupId,
        '--user',
        userId,
        '--format',
        'json',
      ]);
      return <String, Object?>{'userId': userId, 'roles': value};
    }, onError: '读取群成员身份');
    return values.isEmpty ? null : values;
  }

  Future<Object?> _loadDepartmentDetails(List<String> departmentIds) async {
    final values = await _mapBounded<String, Object?>(departmentIds, (
      departmentId,
    ) async {
      final details = await Future.wait<Object?>(<Future<Object?>>[
        _runOptionalJson(<String>[
          'contact',
          'dept',
          'get-info',
          '--dept',
          departmentId,
          '--format',
          'json',
        ], '读取部门详情'),
        _runOptionalJson(<String>[
          'contact',
          'dept',
          'list-children',
          '--dept',
          departmentId,
          '--format',
          'json',
        ], '读取直属子部门'),
      ]);
      return <String, Object?>{
        'deptId': departmentId,
        if (details[0] != null) 'departmentInfo': details[0],
        if (details[1] != null) 'directSubdepartments': details[1],
      };
    }, onError: '读取所属部门资料');
    return values.isEmpty ? null : values;
  }

  Future<Object?> _runOptionalJson(List<String> arguments, String name) async {
    try {
      return await _runJson(arguments);
    } catch (error, stack) {
      if (_looksLikeBusinessError(error)) {
        return null;
      }
      silentLog('dingtalk_gateway', name, error, stack);
      return null;
    }
  }

  Future<List<R>> _mapBounded<T, R>(
    List<T> values,
    Future<R> Function(T value) action, {
    required String onError,
  }) async {
    if (values.isEmpty) return List<R>.empty();
    final results = List<R?>.filled(values.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= values.length) return;
        try {
          results[index] = await action(values[index]);
        } catch (error, stack) {
          if (_looksLikeBusinessError(error)) {
            continue;
          }
          silentLog('dingtalk_gateway', onError, error, stack);
        }
      }
    }

    final workerCount = math.min(_detailConcurrency, values.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return results
        .where((item) => item != null)
        .cast<R>()
        .toList(growable: false);
  }

  List<String> _extractUserIds(Object? value) {
    final ids = <String>{};
    void visit(Object? current) {
      if (current is Map) {
        final map = _asMap(current);
        for (final key in const <String>[
          'userId',
          'user_id',
          'orgUserId',
          'org_user_id',
          'memberUserId',
          'member_user_id',
        ]) {
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final id = '$raw'.trim();
          if (id.isNotEmpty && id != 'null') ids.add(id);
        }
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(value);
    return ids.toList(growable: false);
  }

  List<String> _extractOpenDingTalkIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'openDingTalkId',
      'openDingtalkId',
      'open_dingtalk_id',
    });
  }

  List<String> _extractContactIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'userId',
      'user_id',
      'openDingTalkId',
      'openDingtalkId',
      'open_dingtalk_id',
      'unionId',
      'union_id',
    });
  }

  List<String> _extractDepartmentIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'deptId',
      'dept_id',
      'departmentId',
      'department_id',
    });
  }

  List<String> _extractGroupRoleIds(Object? value) {
    return _extractValuesByKeys(value, const <String>{
      'openRoleId',
      'open_role_id',
      'roleId',
      'role_id',
    });
  }

  List<String> _extractValuesByKeys(Object? value, Set<String> keys) {
    final values = <String>{};
    void visit(Object? current) {
      if (current is Map) {
        final map = _asMap(current);
        for (final key in keys) {
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final candidate = '$raw'.trim();
          if (candidate.isNotEmpty && candidate != 'null') {
            values.add(candidate);
          }
        }
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(value);
    return values.toList(growable: false);
  }

  Object _matchFollowingContact(Object? following, Set<String> contactIds) {
    final matches = <Object?>[];
    void visit(Object? current) {
      if (current is Map) {
        final map = _asMap(current);
        final ids = _extractContactIds(map);
        if (ids.any(contactIds.contains)) matches.add(current);
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(following);
    return <String, Object?>{
      'isFollowing': matches.isNotEmpty,
      if (matches.isNotEmpty) 'details': matches,
    };
  }

  String _extractFirstUserId(Object? value) {
    return _extractUserIds(value).firstOrNull ?? '';
  }

  String _extractFirstStaffId(Object? value) {
    String? found;
    void visit(Object? current) {
      if (found != null) return;
      if (current is Map) {
        final map = _asMap(current);
        for (final key in const <String>['staffId', 'staff_id']) {
          final raw = map[key];
          if (raw is Map || raw is List) continue;
          final candidate = '$raw'.trim();
          if (candidate.isNotEmpty && candidate != 'null') {
            found = candidate;
            return;
          }
        }
        for (final item in map.values) {
          visit(item);
        }
      } else if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(value);
    return found ?? _extractFirstUserId(value);
  }

  Future<Object?> _loadAllGroupMembers(String conversationId) async {
    const maxPages = 100;
    final pages = <Object?>[];
    var cursor = '0';
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final page = await _runJson(<String>[
        'chat',
        'group',
        'members',
        '--id',
        conversationId,
        '--cursor',
        cursor,
        '--format',
        'json',
      ]);
      pages.add(page);
      final map = _asMap(page);
      final data = _asMap(map['data']);
      final result = _asMap(map['result']);
      final hasMore =
          _asBool(map['hasMore']) ||
          _asBool(data['hasMore']) ||
          _asBool(result['hasMore']);
      final nextCursor = _firstValues(<Object?>[
        map['nextCursor'],
        map['next_cursor'],
        data['nextCursor'],
        data['next_cursor'],
        result['nextCursor'],
        result['next_cursor'],
      ]);
      if (!hasMore || nextCursor.isEmpty || nextCursor == cursor) break;
      cursor = nextCursor;
    }
    return pages.length == 1 ? pages.first : <String, Object?>{'pages': pages};
  }

  Future<String> _requireExecutable() async {
    final path = await executable();
    if (path == null || path.trim().isEmpty) {
      throw StateError('未找到 DingTalk Workspace CLI（dws），请先在插件板块安装。');
    }
    return path;
  }

  Future<Object?> _runJson(
    List<String> arguments, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final operation = arguments.take(3).join(' ');
    _logRuntime('INFO', '执行 dws：$operation。');
    late final String executable;
    try {
      executable = await _requireExecutable();
    } catch (error) {
      _logRuntime('ERROR', '未找到 dws，无法执行：$error');
      rethrow;
    }
    late final TrackedProcessLineLogResult result;
    try {
      result = await runTrackedProcessWithLineLogging(
        executable,
        arguments,
        timeout: timeout ?? _commandTimeout,
        tag: 'dingtalk_gateway.command',
        workingDirectory: workingDirectory,
        maxCapturedLinesPerStream: 4096,
        onStdoutLine: (line) {
          final trimmed = line.trimLeft();
          final isStructured =
              trimmed.startsWith('{') || trimmed.startsWith('[');
          _logRuntime(
            'DEBUG',
            isStructured
                ? 'dws 返回结构化输出（${line.length} 字符）。'
                : 'dws 标准输出：${_safeProcessLogLine(line)}',
          );
        },
        onStderrLine: (line) =>
            _logRuntime('WARN', 'dws 标准错误：${_safeProcessLogLine(line)}'),
        onTimeout: () => _logRuntime('ERROR', 'dws 执行超时：$operation。'),
      );
    } catch (error) {
      _logRuntime('ERROR', 'dws 启动或执行异常：$error');
      rethrow;
    }
    _logRuntime(
      result.exitCode == 0 ? 'SUCCESS' : 'ERROR',
      'dws 执行结束：$operation，退出码 ${result.exitCode}。',
    );
    final decoded = _decodeJson(result.stdout);
    final payload = _asMap(decoded);
    final error = _asMap(payload['error']);
    if (result.stdout.trim().isNotEmpty && decoded is Map && payload.isEmpty) {
      _logRuntime('WARN', 'dws 返回内容无法解析为有效 JSON。');
    }
    if (result.exitCode != 0 || error.isNotEmpty) {
      final message =
          error['message']?.toString().trim().ifEmpty('dws 执行失败。') ??
          payload['message']?.toString().trim().ifEmpty('dws 执行失败。') ??
          result.stderr.trim().ifEmpty('dws 执行失败。');
      _logRuntime('ERROR', 'dws 业务调用失败：${_safeProcessLogLine(message)}');
      throw DingTalkGatewayCommandException(
        message: message,
        category: error['category']?.toString(),
        reason: error['reason']?.toString(),
        serverCode: error['server_error_code']?.toString(),
        operation: error['operation']?.toString(),
      );
    }
    return decoded;
  }

  Object? _decodeJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const <String, Object?>{};
    try {
      return jsonDecode(text);
    } catch (_) {
      for (final line in text.split(RegExp(r'\r?\n')).reversed) {
        final candidate = line.trim();
        if (!(candidate.startsWith('{') || candidate.startsWith('['))) continue;
        try {
          return jsonDecode(candidate);
        } catch (_) {}
      }
    }
    return const <String, Object?>{};
  }

  List<DingTalkGatewayMessage> _parseMessages(
    Object? raw, {
    bool mentionedCurrentUser = false,
  }) {
    final values = <Object?>[];
    void collect(Object? value) {
      if (value is List) {
        values.addAll(value);
        return;
      }
      if (value is Map) {
        final map = _asMap(value);
        final hasMessageIdentity = _first(map, const <String>[
          'openMessageId',
          'messageId',
          'id',
        ]).isNotEmpty;
        if (hasMessageIdentity) {
          values.add(value);
          return;
        }
        for (final key in const <String>[
          'messages',
          'items',
          'records',
          'data',
          'result',
        ]) {
          final child = value[key];
          if (child is List) values.addAll(child);
          if (child is Map) collect(child);
        }
      }
    }

    collect(raw);
    final result = <DingTalkGatewayMessage>[];
    for (final value in values) {
      if (value is! Map) continue;
      final map = _asMap(value);
      final id = _first(map, const <String>[
        'openMessageId',
        'messageId',
        'id',
      ]);
      final content = _content(map);
      final conversationId = _first(map, const <String>[
        'openConversationId',
        'conversationId',
        'conversation_id',
      ]);
      final media = _extractMedia(map)
          .map(
            (item) =>
                item.copyWith(messageId: id, conversationId: conversationId),
          )
          .toList(growable: false);
      if (id.isEmpty ||
          (content.isEmpty && media.isEmpty) ||
          conversationId.isEmpty) {
        continue;
      }
      final typeText = _first(map, const <String>[
        'conversationType',
        'conversation_type',
        'chatType',
      ]).toLowerCase();
      result.add(
        DingTalkGatewayMessage(
          id: id,
          conversationId: conversationId,
          conversationType: typeText.contains('group') || typeText == '2'
              ? DingTalkConversationType.group
              : DingTalkConversationType.direct,
          role: DingTalkGatewayMessageRole.user,
          content: content.isEmpty ? _mediaSummary(media) : content,
          createdAt:
              DateTime.tryParse(
                _first(map, const <String>[
                  'createTime',
                  'createdAt',
                  'create_time',
                ]),
              )?.toLocal() ??
              DateTime.now(),
          senderName: _eventString(map, const <String>[
            'senderName',
            'senderNick',
            'sender_name',
            'nick',
            'sender',
          ]),
          senderId: _eventString(map, const <String>[
            'senderId',
            'senderUserId',
            'senderOpenDingTalkId',
            'sender_id',
            'sender_open_dingtalk_id',
            'sender',
          ]),
          conversationTitle: _first(map, const <String>[
            'conversationTitle',
            'groupName',
            'title',
          ]),
          media: media,
          fromSelf: _asBool(map['isSelf']) || _asBool(map['isMine']),
          mentionedCurrentUser:
              mentionedCurrentUser ||
              _asBool(map['mentionedCurrentUser']) ||
              _asBool(map['mentioned_current_user']),
        ),
      );
    }
    return result;
  }

  void _consumeEventLine(String line) {
    final text = line.trim();
    if (text.isEmpty || !(text.startsWith('{') || text.startsWith('['))) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      _logRuntime('WARN', '实时事件输出不是有效 JSON，已忽略。');
      return;
    }
    final message = _parseEventMessage(decoded);
    if (message != null) _eventController?.add(message);
  }

  DingTalkGatewayMessage? _parseEventMessage(Object? raw) {
    if (raw is! Map) return null;
    final map = _asMap(raw);
    final content = _content(map);
    final conversationId = _eventString(map, const <String>[
      'conversation_id',
      'conversationId',
      'openConversationId',
      'open_conversation_id',
      'chat_id',
    ]);
    final chatType = _eventString(map, const <String>[
      'chat_type',
      'chatType',
      'conversation_type',
      'conversationType',
    ]).toLowerCase();
    final eventType = _eventString(map, const <String>[
      'event_type',
      'eventType',
      'type',
    ]).toLowerCase();
    final messageId = _eventString(map, const <String>[
      'message_id',
      'messageId',
      'openMessageId',
      'open_message_id',
      'event_id',
      'eventId',
    ]);
    if (messageId.isEmpty || conversationId.isEmpty) return null;
    final media = _extractMedia(map)
        .map(
          (item) => item.copyWith(
            messageId: messageId,
            conversationId: conversationId,
          ),
        )
        .toList(growable: false);
    if (content.isEmpty && media.isEmpty) return null;
    final mentionedCurrentUser =
        _eventString(map, const <String>[
          'event_key',
          'eventKey',
          'rule_type',
          'ruleType',
          'type',
        ]).toLowerCase().contains('receive_at') ||
        _asBool(map['mentionedCurrentUser']) ||
        _asBool(map['mentioned_current_user']);
    final conversationType =
        chatType.contains('group') ||
            chatType == '2' ||
            eventType.contains('group') ||
            eventType.contains('receive_at') ||
            eventType == '2' ||
            _asBool(map['is_group']) ||
            _asBool(map['isGroup'])
        ? DingTalkConversationType.group
        : DingTalkConversationType.direct;
    return DingTalkGatewayMessage(
      id: messageId,
      conversationId: conversationId,
      conversationType: conversationType,
      role: DingTalkGatewayMessageRole.user,
      content: content.isEmpty ? _mediaSummary(media) : content,
      createdAt: _eventDateTime(map),
      senderName: _eventString(map, const <String>[
        'sender_name',
        'senderName',
        'sender_nick',
        'senderNick',
        'sender',
        'nick',
        'name',
      ]),
      senderId: _eventString(map, const <String>[
        'sender_open_dingtalk_id',
        'senderOpenDingTalkId',
        'sender_user_id',
        'senderUserId',
        'sender_id',
        'sender',
      ]),
      conversationTitle: _eventString(map, const <String>[
        'conversation_title',
        'conversationTitle',
        'group_name',
        'groupName',
        'title',
      ]),
      media: media,
      fromSelf:
          _asBool(map['isSelf']) ||
          _asBool(map['is_self']) ||
          _asBool(map['isMine']) ||
          _asBool(map['is_self_loop']),
      mentionedCurrentUser: mentionedCurrentUser,
    );
  }

  String _eventString(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is Map) {
        final nested = _asMap(value);
        final nestedValue = _eventString(nested, const <String>[
          'nick',
          'name',
          'title',
          'displayName',
          'id',
          'userId',
          'user_id',
          'openDingTalkId',
          'open_dingtalk_id',
          'value',
        ]);
        if (nestedValue.isNotEmpty) return nestedValue;
        continue;
      }
      if (value is List || value == null) continue;
      final text = '$value'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  DateTime _eventDateTime(Map<String, Object?> map) {
    final value =
        map['create_time'] ??
        map['createTime'] ??
        map['created_at'] ??
        map['createdAt'] ??
        map['event_time'] ??
        map['timestamp'];
    if (value is num) {
      final milliseconds = value.abs() < 100000000000
          ? value.toInt() * 1000
          : value.toInt();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    }
    final text = '$value'.trim();
    final numeric = num.tryParse(text);
    if (numeric != null) {
      final milliseconds = numeric.abs() < 100000000000
          ? numeric.toInt() * 1000
          : numeric.toInt();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    }
    return DateTime.tryParse(text)?.toLocal() ?? DateTime.now();
  }

  List<DingTalkConversationTarget> _parseTargets(
    Object? raw, {
    required DingTalkConversationType type,
  }) {
    final result = <DingTalkConversationTarget>[];
    final seen = <String>{};
    void visit(Object? value, int depth) {
      if (depth > 4 || result.length >= 50) return;
      if (value is List) {
        for (final item in value) {
          visit(item, depth + 1);
          if (result.length >= 50) return;
        }
        return;
      }
      if (value is! Map) return;
      final map = _asMap(value);
      final userId = type == DingTalkConversationType.direct
          ? _first(map, const <String>['userId', 'user_id'])
          : '';
      final openDingTalkId = type == DingTalkConversationType.direct
          ? _first(map, const <String>[
              'openDingTalkId',
              'openDingtalkId',
              'open_dingtalk_id',
            ])
          : '';
      final id = type == DingTalkConversationType.group
          ? _first(map, const <String>[
              'openConversationId',
              'conversationId',
              'conversation_id',
              'id',
            ])
          : userId.isNotEmpty
          ? userId
          : openDingTalkId.isNotEmpty
          ? openDingTalkId
          : '';
      final title = type == DingTalkConversationType.group
          ? _first(map, const <String>['name', 'groupName', 'title'])
          : _first(map, const <String>['name', 'nick', 'userName', 'title']);
      if (id.isNotEmpty && title.isNotEmpty && seen.add(id)) {
        result.add(
          DingTalkConversationTarget(
            id: id,
            title: title,
            type: type,
            subtitle: _first(map, const <String>[
              'subtitle',
              'departmentName',
              'department',
              'description',
            ]),
            aliases: <String>{userId, openDingTalkId}
                .where((item) => item.isNotEmpty && item != id)
                .toList(growable: false),
            userId: userId,
            openDingTalkId: openDingTalkId,
          ),
        );
      }
      for (final child in map.values) {
        if (child is Map || child is List) visit(child, depth + 1);
      }
    }

    visit(raw, 0);
    return result;
  }

  String _content(Map<String, Object?> map) {
    final value = map['content'] ?? map['text'] ?? map['msgContent'];
    if (value is String) {
      final raw = value.trim();
      if (raw.startsWith('{') || raw.startsWith('[')) {
        final decoded = _decodeJson(raw);
        if (decoded is Map) return _content(_asMap(decoded));
      }
      return raw;
    }
    if (value is Map) {
      return '${value['text'] ?? value['content'] ?? ''}'.trim();
    }
    return '';
  }

  List<DingTalkGatewayMedia> _extractMedia(Map<String, Object?> map) {
    final result = <DingTalkGatewayMedia>[];
    final seen = <String>{};

    void addCandidate({
      required String resourceId,
      required DingTalkMediaResourceType resourceType,
      required Object? type,
      required Object? name,
      required Object? mimeType,
      required Object? size,
      required Object? duration,
    }) {
      final normalizedId = resourceId.trim();
      if (normalizedId.isEmpty || result.length >= 12) return;
      final key = '${resourceType.name}:$normalizedId';
      if (!seen.add(key)) return;
      final rawName = '$name'.trim();
      final mime = '$mimeType'.trim();
      var kind = DingTalkMediaKindX.fromStorage(type);
      if (kind == DingTalkMediaKind.file && rawName.isNotEmpty) {
        kind = DingTalkMediaKindX.fromFileName(rawName);
      }
      if (kind == DingTalkMediaKind.file && mime.isNotEmpty) {
        kind = DingTalkMediaKindX.fromStorage(mime);
      }
      result.add(
        DingTalkGatewayMedia(
          resourceId: normalizedId,
          resourceType: resourceType,
          kind: kind,
          name: rawName,
          mimeType: mime,
          sizeBytes: int.tryParse('$size') ?? 0,
          durationMs: int.tryParse('$duration'),
        ),
      );
    }

    void visit(Object? value, {int depth = 0}) {
      if (depth > 6 || result.length >= 12 || value == null) return;
      if (value is String) {
        final raw = value.trim();
        if (raw.startsWith('{') || raw.startsWith('[')) {
          final decoded = _decodeJson(raw);
          if (decoded is Map || decoded is List) {
            visit(decoded, depth: depth + 1);
          }
        }
        final match = RegExp(
          r'''(?:media[_-]?id|file[_-]?id)\s*["'=:]\s*["']?([^,"'\s}]+)''',
          caseSensitive: false,
        ).firstMatch(raw);
        if (match != null) {
          final isFile =
              raw.toLowerCase().contains('fileid') ||
              raw.toLowerCase().contains('file_id');
          addCandidate(
            resourceId: match.group(1) ?? '',
            resourceType: isFile
                ? DingTalkMediaResourceType.fileId
                : DingTalkMediaResourceType.mediaId,
            type: null,
            name: null,
            mimeType: null,
            size: null,
            duration: null,
          );
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          visit(item, depth: depth + 1);
          if (result.length >= 12) break;
        }
        return;
      }
      if (value is! Map) return;
      final current = _asMap(value);
      final mediaId = _first(current, const <String>[
        'mediaId',
        'media_id',
        'downloadCode',
        'download_code',
      ]);
      final fileId = _first(current, const <String>['fileId', 'file_id']);
      if (mediaId.isNotEmpty || fileId.isNotEmpty) {
        addCandidate(
          resourceId: mediaId.isNotEmpty ? mediaId : fileId,
          resourceType: mediaId.isNotEmpty
              ? DingTalkMediaResourceType.mediaId
              : DingTalkMediaResourceType.fileId,
          type: _first(current, const <String>[
            'messageType',
            'msgType',
            'msgtype',
            'msg_type',
            'mediaType',
            'media_type',
            'type',
          ]),
          name: _first(current, const <String>[
            'fileName',
            'filename',
            'file_name',
            'name',
            'title',
          ]),
          mimeType: _first(current, const <String>[
            'mimeType',
            'mime_type',
            'contentType',
          ]),
          size:
              current['sizeBytes'] ?? current['size_bytes'] ?? current['size'],
          duration:
              current['durationMs'] ??
              current['duration_ms'] ??
              current['duration'],
        );
      }
      for (final key in const <String>[
        'content',
        'msgContent',
        'messageContent',
        'body',
        'payload',
        'message',
        'media',
        'image',
        'photo',
        'video',
        'audio',
        'voice',
        'file',
        'attachment',
        'attachments',
      ]) {
        visit(current[key], depth: depth + 1);
      }
    }

    // 资源字段既可能位于 content 内，也可能直接位于事件顶层；统一从根节点扫描，
    // 同时通过 seen 去重，避免同一媒体被重复附加。
    visit(map);
    return result;
  }

  String _mediaSummary(List<DingTalkGatewayMedia> media) {
    if (media.isEmpty) return '媒体消息';
    return media.map((item) => '[${item.displayName}]').join(' ');
  }

  String _formatChatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _first(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final text = '$value'.trim();
      if (value != null && text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  String _firstValues(Iterable<Object?> values) {
    for (final value in values) {
      if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    }
    return '';
  }

  Map<String, Object?> _asMap(Object? value) => value is Map
      ? value.map((key, value) => MapEntry('$key', value))
      : <String, Object?>{};
  bool _asBool(Object? value) =>
      value == true || '$value'.toLowerCase() == 'true';
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

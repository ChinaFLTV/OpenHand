import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_log_buffer.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../ai/index.dart';
import '../../plugin_service/index.dart';
import '../model/dingtalk_message_gateway.dart';

class DingTalkGatewayQueryResult {
  const DingTalkGatewayQueryResult({
    required this.messages,
    this.warning,
    this.shouldAdvanceWindow = true,
  });

  final List<DingTalkGatewayMessage> messages;
  final String? warning;
  final bool shouldAdvanceWindow;
}

class DingTalkConversationMessagePage {
  const DingTalkConversationMessagePage({
    required this.messages,
    required this.hasMore,
    this.oldestMessageAt,
  });

  final List<DingTalkGatewayMessage> messages;
  final bool hasMore;
  final DateTime? oldestMessageAt;
}

class _DingTalkMessagePageResult {
  const _DingTalkMessagePageResult({
    required this.pages,
    this.warning,
    this.shouldAdvanceWindow = true,
  });

  final List<Object?> pages;
  final String? warning;
  final bool shouldAdvanceWindow;
}

class DingTalkSentMessage {
  const DingTalkSentMessage({this.messageId, this.conversationId});

  final String? messageId;
  final String? conversationId;
}

class DingTalkDwsCommandExecution {
  const DingTalkDwsCommandExecution({
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.timedOut,
    required this.cancelled,
    required this.durationMs,
  });

  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int exitCode;
  final bool timedOut;
  final bool cancelled;
  final int durationMs;
}

/// dws 返回的业务错误。可选详情接口失败时由调用方按错误类别降级处理。
class DingTalkGatewayCommandException implements Exception {
  const DingTalkGatewayCommandException({
    required this.message,
    this.category,
    this.reason,
    this.serverCode,
    this.operation,
    this.retryable = false,
    this.retryAfterSeconds,
  });

  final String message;
  final String? category;
  final String? reason;
  final String? serverCode;
  final String? operation;
  final bool retryable;
  final int? retryAfterSeconds;

  bool get isBusinessError =>
      category?.trim().toLowerCase() == 'api' ||
      reason?.trim().toLowerCase() == 'business_error' ||
      (serverCode != null && serverCode!.trim().isNotEmpty) ||
      message.toLowerCase().contains('business error: success=false');

  bool get isPermissionDenied =>
      serverCode == '2001' ||
      message.contains('无花名册管理权限') ||
      message.contains('权限不足') ||
      message.contains('无权限');

  bool get isResourceNotFound =>
      serverCode?.trim().toUpperCase() == 'RESOURCE_NOT_FOUND' ||
      message.toUpperCase().contains('RESOURCE_NOT_FOUND');

  bool get isInvalidInput =>
      serverCode?.trim().toLowerCase() == 'invalidrequest.inputargs.invalid' ||
      message.contains('参数') && message.contains('缺少必要信息');

  bool get isDependencyUnavailable {
    final normalized = message.toLowerCase();
    return normalized.contains('mcp 后端依赖暂时不可用') ||
        normalized.contains('mcp backend dependency temporarily unavailable');
  }

  bool get isCancelled => reason?.trim().toLowerCase() == 'cancelled';

  /// dws 将网络请求失败包装为进程退出时，通常不会提供结构化 retryable 字段。
  bool get isTransientNetworkFailure {
    final normalized = message.trim().toLowerCase();
    final normalizedServerCode = serverCode?.trim().toLowerCase() ?? '';
    return normalizedServerCode == 'network_timeout' ||
        const <String>[
          '[network_timeout]',
          'network timeout',
          'request timed out',
          'connection reset',
          'connection closed',
          'connection refused',
          'broken pipe',
          'network is unreachable',
          'no route to host',
          'tls handshake timeout',
        ].any(normalized.contains) ||
        normalized.contains('sending request') &&
            RegExp(r'\beof\b').hasMatch(normalized);
  }

  bool get isMessageEditLimitReached {
    final normalized = message.toLowerCase();
    return isMessageEditOperation &&
        (message.contains('编辑次数已达上限') ||
            normalized.contains('message edit limit reached') ||
            normalized.contains('maximum number of edits'));
  }

  /// 钉钉编辑接口对消息类型有明确限制，命中后应停止远端编辑并保留本地同步。
  /// 仅匹配稳定的接口标识和错误文案，避免把其他编辑失败误判为能力降级。
  bool get isUnsupportedMessageEditType {
    if (!isMessageEditOperation) return false;
    final normalized = message.trim().toLowerCase();
    return message.contains('仅支持编辑文本、富文本、回复消息') ||
        normalized.contains(
          'only supports editing text, rich text, reply messages',
        ) ||
        normalized.contains(
          'only supports editing text, rich text, and reply messages',
        );
  }

  bool get isMessageEditOperation {
    final normalizedOperation = operation?.trim().toLowerCase() ?? '';
    return normalizedOperation == 'im/edit_message' ||
        message.toLowerCase().contains('im/edit_message');
  }

  bool get isRetryable =>
      retryable ||
      reason?.trim().toLowerCase() == 'timeout' ||
      isDependencyUnavailable ||
      isTransientNetworkFailure;

  @override
  String toString() => message;
}

class _DingTalkEventSubscriptionSpec {
  const _DingTalkEventSubscriptionSpec({
    required this.arguments,
    required this.required,
    required this.label,
  });

  final List<String> arguments;
  final bool required;
  final String label;
}

class _DingTalkEventProcessHandle {
  _DingTalkEventProcessHandle({
    required this.process,
    required this.required,
    required this.label,
  });

  final Process process;
  final bool required;
  final String label;
  StreamSubscription<String>? stdoutSubscription;
  StreamSubscription<String>? stderrSubscription;
}

class DingTalkMessageGatewayService {
  static const Duration _commandTimeout = Duration(seconds: 25);
  static const Duration _commandCleanupReserve = Duration(seconds: 3);
  static const Duration _fileSendTimeout = Duration(minutes: 5);
  static const Duration _authTimeout = Duration(minutes: 15);
  static const Duration _eventProcessStartTimeout = Duration(seconds: 10);
  static const Duration _eventReadyTimeout = Duration(seconds: 30);
  static const Duration _eventCleanupTimeout = Duration(seconds: 5);
  static const int _eventProcessStartConcurrency = 4;
  static const int _maxEventTargetSubscriptions = 32;
  static const int _maxEventOutputLineCharacters = 512 * kBytesPerKiB;
  static const Duration _mediaDownloadTimeout = Duration(minutes: 3);
  static const Duration _mediaDownloadQueueTimeout = Duration(seconds: 30);
  static const Duration _sentMessageLookupWindow = Duration(minutes: 2);
  // 为网络请求和子进程回收保留充足时间，避免反查消息标识频繁超时。
  static const Duration _sentMessageLookupTimeout = Duration(seconds: 15);
  static const int _sentMessageLookupLimit = 50;
  static const int _messageQueryPageSize = 50;
  static const Duration _minimumMessageQueryWindow = Duration(seconds: 1);
  // 轮询窗口只取有限页数，避免两个并行查询在慢 dws 环境下拖住轮询回调；
  // 更早消息由会话对账和用户主动加载历史补齐。
  static const int _messageQueryMaxPages = 3;
  static const Duration _messageQueryTotalTimeout = Duration(seconds: 40);
  static const Duration _messageQueryRetryCooldown = Duration(seconds: 30);
  static const Duration _messageQueryUnavailableCooldown = Duration(
    minutes: 10,
  );
  static const Duration _messageQueryDependencyCooldown = Duration(minutes: 2);
  static const Duration _conversationQueryUnavailableCooldown = Duration(
    minutes: 10,
  );
  static const int _maxConversationQueryFailures = 512;
  static const String _messageSearchFallbackWarning =
      '钉钉消息搜索能力暂不可用，已依赖实时事件和会话对账。';
  static const int _batchSize = 30;
  static const int _detailConcurrency = 4;
  static const int _maxMediaCacheFiles = 512;
  static const int _maxMediaCacheScanEntries = _maxMediaCacheFiles + 128;
  static const int _maxPendingMediaDownloads = 64;
  static const int _maxMediaCacheBytes = kBytesPerGiB;
  static const int _maxMediaFileBytes = 512 * kBytesPerMiB;
  static const Duration _mediaCacheFileOperationTimeout = Duration(seconds: 3);
  static const int _maxAuthOutputLines = 256;
  static const int _maxAuthOutputCharacters = 32 * kBytesPerKiB;
  static const Duration _transientMediaFailureCooldown = Duration(minutes: 10);
  // 媒体资源一旦被钉钉明确判定不存在，在当前进程内短期内不会恢复。
  // 设定 TTL 和容量上限，既避免无效资源无限重试，也避免负缓存无限增长。
  static const Duration _unavailableMediaTtl = Duration(hours: 6);
  static const int _maxUnavailableMediaEntries = 512;
  static const List<String> _messageEventKeys = <String>[
    'user_im_message_receive_at',
    'user_im_message_receive_o2o_all',
    'user_im_message_receive_group_all',
  ];
  static const List<String> _directStatusEventKeys = <String>[
    'user_im_message_receive_o2o',
    'user_im_message_read_o2o',
    'user_im_message_recall_o2o',
    'user_im_message_reaction_o2o',
  ];
  static const List<String> _groupStatusEventKeys = <String>[
    'user_im_message_receive_group',
    'user_im_message_read_group',
    'user_im_message_recall_group',
    'user_im_message_reaction_group',
  ];
  Process? _authProcess;
  final List<_DingTalkEventProcessHandle> _eventProcesses =
      <_DingTalkEventProcessHandle>[];
  final Map<String, DateTime> _messageQueryUnavailableUntil =
      <String, DateTime>{};
  final Set<String> _messageQueryWindowPreserved = <String>{};
  final Map<String, DateTime> _conversationQueryUnavailableUntil =
      <String, DateTime>{};
  StreamController<DingTalkGatewayEvent>? _eventController;
  Future<Stream<DingTalkGatewayEvent>>? _eventStartFuture;
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
  final Set<String> _activeMediaCacheBasenames = <String>{};
  final OpenHandSingleFlight<void> _mediaCachePruneFlight =
      OpenHandSingleFlight<void>();
  Completer<void> _mediaDownloadCancelSignal = Completer<void>();
  final OpenHandAsyncSemaphore _mediaDownloadSemaphore = OpenHandAsyncSemaphore(
    3,
    maxWaiters: _maxPendingMediaDownloads,
  );
  final OpenHandAsyncOnce _disposeOnce = OpenHandAsyncOnce();
  final Map<String, DateTime> _unavailableMediaUntil = <String, DateTime>{};
  final Map<String, DateTime> _mediaContextWarningAt = <String, DateTime>{};
  List<AiDingTalkDwsCommand>? _dwsCommandCatalog;
  DateTime? _dwsCommandCatalogLoadedAt;
  String? _dwsCommandCatalogError;
  int _runtimeLogSequence = 0;

  List<String> get runtimeLogs => _runtimeLogs.snapshot();
  int get runtimeLogRevision => _runtimeLogs.revision;
  Stream<String> get runtimeLogStream => _runtimeLogController.stream;
  String? get dwsCommandCatalogError => _dwsCommandCatalogError;

  String get mediaCacheDirectoryPath =>
      p.join(OpenHandPaths.defaultMessageGatewayDirectoryPath(), 'media');

  Future<List<AiDingTalkDwsCommand>> loadDwsCommandCatalog({
    bool forceRefresh = false,
  }) async {
    final cached = _dwsCommandCatalog;
    final loadedAt = _dwsCommandCatalogLoadedAt;
    if (!forceRefresh &&
        cached != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 10)) {
      return cached;
    }
    _dwsCommandCatalogError = null;
    try {
      final raw = await _runJson(const <String>[
        'schema',
        '--all',
        '--compact',
        '--format',
        'json',
      ], timeout: const Duration(seconds: 45));
      final root = _asMap(raw);
      final products = root['products'];
      if (products is! List) {
        throw const FormatException('DWS 返回的命令目录缺少 products 字段。');
      }
      final result = <AiDingTalkDwsCommand>[];
      for (final productValue in products) {
        if (productValue is! Map) continue;
        final product = _asMap(productValue);
        final productId = _first(product, const <String>['id', 'product_id']);
        if (productId.isEmpty || productId == 'chat' || productId == 'event') {
          continue;
        }
        final productName = _first(product, const <String>[
          'name',
          'display',
          'description',
        ]);
        final tools = product['tools'];
        if (tools is! List) continue;
        for (final toolValue in tools) {
          if (toolValue is! Map) continue;
          final tool = _asMap(toolValue);
          final cliPath = _first(tool, const <String>[
            'cli_path',
            'primary_cli_path',
          ]);
          final declaredName = _first(tool, const <String>['name', 'cli_name']);
          final name = declaredName.isEmpty
              ? cliPath.split(' ').last
              : declaredName;
          if (cliPath.isEmpty || name.isEmpty) continue;
          try {
            result.add(
              AiDingTalkDwsCommand.fromJson(<String, Object?>{
                'product_id': productId,
                'product_name': productName,
                'cli_path': cliPath,
                'name': name,
                'description': tool['description'] ?? tool['title'] ?? '',
                'summary': tool['agent_summary'] ?? tool['summary'] ?? '',
                'effect': tool['effect'] ?? 'read',
                'risk': tool['risk'] ?? 'low',
                'confirmation': tool['confirmation'] ?? 'not_required',
                'parameters': tool['parameters'],
                'positionals': tool['positionals'],
                'examples': tool['examples'],
              }),
            );
          } on FormatException {
            continue;
          }
        }
      }
      if (products.isNotEmpty && result.isEmpty) {
        throw const FormatException('DWS 命令目录未包含可用命令。');
      }
      final deduped = <String, AiDingTalkDwsCommand>{
        for (final command in result) command.cliPath: command,
      };
      final catalog = deduped.values.toList(growable: false)
        ..sort((a, b) => a.cliPath.compareTo(b.cliPath));
      _dwsCommandCatalog = List<AiDingTalkDwsCommand>.unmodifiable(catalog);
      _dwsCommandCatalogLoadedAt = DateTime.now();
      _dwsCommandCatalogError = null;
      _logRuntime('SUCCESS', '已加载 ${catalog.length} 个钉钉 DWS 扩展命令。');
      return _dwsCommandCatalog!;
    } catch (error, stack) {
      _dwsCommandCatalogError = _safeProcessLogLine(
        error.toString().replaceFirst('FormatException: ', ''),
      );
      _logRuntime('ERROR', '加载钉钉 DWS 扩展命令失败：$error');
      silentLog('dingtalk_gateway', '加载 DWS 命令目录', error, stack);
      return cached ?? const <AiDingTalkDwsCommand>[];
    }
  }

  Future<DingTalkDwsCommandExecution> executeDwsCommand({
    required AiDingTalkDwsCommand command,
    required List<String> arguments,
    required String workingDirectory,
    Future<void>? cancelSignal,
  }) async {
    final startedAt = Stopwatch()..start();
    final executable = await _requireExecutable();
    final processArguments = <String>[
      ...command.cliPath.split(kInlineWhitespacePattern),
    ];
    processArguments.addAll(arguments);
    processArguments.addAll(const <String>['--format', 'json']);
    final result = await runTrackedProcessWithLineLogging(
      executable,
      processArguments,
      timeout: const Duration(minutes: 2),
      workingDirectory: workingDirectory,
      tag: 'dingtalk_gateway.dws_tool',
      cancelSignal: cancelSignal,
      maxCapturedLinesPerStream: 4096,
      onStderrLine: (line) =>
          _logRuntime('WARN', 'DWS 扩展命令：${_safeProcessLogLine(line)}'),
      onTimeout: () => _logRuntime('ERROR', 'DWS 扩展命令执行超时：${command.cliPath}。'),
    );
    return DingTalkDwsCommandExecution(
      command: processArguments.join(' '),
      workingDirectory: workingDirectory,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      timedOut: result.timedOut,
      cancelled: result.cancelled,
      durationMs: startedAt.elapsedMilliseconds,
    );
  }

  void clearRuntimeLogs() => _runtimeLogs.clear();

  void resetMessageQueryCapability() {
    _messageQueryUnavailableUntil.clear();
    _messageQueryWindowPreserved.clear();
    _conversationQueryUnavailableUntil.clear();
  }

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

  Future<Stream<DingTalkGatewayEvent>> startEventSubscription({
    Iterable<DingTalkConversationTarget> targets =
        const <DingTalkConversationTarget>[],
  }) {
    final current = _eventController;
    if (current != null) {
      return Future<Stream<DingTalkGatewayEvent>>.value(current.stream);
    }
    final Future<Stream<DingTalkGatewayEvent>>? pending = _eventStartFuture;
    if (pending != null) return pending;
    final future = _startEventSubscription(targets: targets);
    _eventStartFuture = future;
    return future.whenComplete(() {
      if (identical(_eventStartFuture, future)) _eventStartFuture = null;
    });
  }

  Future<Stream<DingTalkGatewayEvent>> _startEventSubscription({
    required Iterable<DingTalkConversationTarget> targets,
  }) async {
    final generation = _eventGeneration;
    final executable = await _requireExecutable();
    _logRuntime('INFO', '启动钉钉实时事件监听。');
    if (generation != _eventGeneration) {
      throw StateError('钉钉实时事件监听已取消。');
    }
    final controller = StreamController<DingTalkGatewayEvent>();
    _eventController = controller;
    try {
      final specs = _eventSubscriptionSpecs(targets);
      await _startEventProcess(
        executable: executable,
        spec: specs.first,
        generation: generation,
      );
      final optionalSpecs = specs.skip(1).toList(growable: false);
      await forEachIndexWithConcurrencyLimit(
        itemCount: optionalSpecs.length,
        maxConcurrency: _eventProcessStartConcurrency,
        shouldContinue: () => generation == _eventGeneration,
        task: (index) async {
          final spec = optionalSpecs[index];
          try {
            await _startEventProcess(
              executable: executable,
              spec: spec,
              generation: generation,
            );
          } catch (error, stack) {
            _logRuntime('WARN', '实时事件${spec.label}监听启动失败，已跳过该目标。');
            silentLog(
              'dingtalk_gateway',
              '启动实时事件${spec.label}监听',
              error,
              stack,
            );
          }
        },
      );
      if (generation != _eventGeneration) {
        throw StateError('钉钉实时事件监听已取消。');
      }
      return controller.stream;
    } catch (_) {
      _logRuntime('ERROR', '启动钉钉实时事件监听失败。');
      if (generation == _eventGeneration) {
        await stopEventSubscription();
      }
      rethrow;
    }
  }

  List<_DingTalkEventSubscriptionSpec> _eventSubscriptionSpecs(
    Iterable<DingTalkConversationTarget> targets,
  ) {
    final specs = <_DingTalkEventSubscriptionSpec>[
      const _DingTalkEventSubscriptionSpec(
        arguments: <String>[
          'event',
          'consume',
          ..._messageEventKeys,
          '--flatten',
          '--format',
          'ndjson',
          '--ephemeral',
        ],
        required: true,
        label: '消息',
      ),
    ];
    final seen = <String>{};
    var truncated = false;
    for (final target in targets) {
      final id = target.id.trim();
      if (id.isEmpty) continue;
      final isGroup = target.type == DingTalkConversationType.group;
      final targetFlag = isGroup
          ? '--group'
          : target.userId.trim().isNotEmpty ||
                target.openDingTalkId.trim().isEmpty
          ? '--user'
          : '--open-dingtalk-id';
      final targetValue = isGroup
          ? id
          : target.userId.trim().isNotEmpty
          ? target.userId.trim()
          : target.openDingTalkId.trim().isNotEmpty
          ? target.openDingTalkId.trim()
          : id;
      if (targetValue.isEmpty) continue;
      final key = '${target.type.name}:$targetFlag:$targetValue';
      if (!seen.add(key)) continue;
      if (seen.length > _maxEventTargetSubscriptions) {
        truncated = true;
        break;
      }
      final eventKeys = isGroup
          ? _groupStatusEventKeys
          : _directStatusEventKeys;
      specs.add(
        _DingTalkEventSubscriptionSpec(
          arguments: <String>[
            'event',
            'consume',
            ...eventKeys,
            targetFlag,
            targetValue,
            '--flatten',
            '--format',
            'ndjson',
            '--ephemeral',
          ],
          required: false,
          label: '${isGroup ? '群聊' : '单聊'} $targetValue',
        ),
      );
    }
    if (specs.length > 1) {
      _logRuntime('INFO', '已为 ${specs.length - 1} 个会话目标订阅状态事件。');
    }
    if (truncated) {
      _logRuntime(
        'WARN',
        '实时状态事件仅订阅前 $_maxEventTargetSubscriptions 个目标，其余目标由会话对账补偿。',
      );
    }
    return specs;
  }

  Future<void> _cancelTextSubscriptions(
    Iterable<StreamSubscription<String>?> subscriptions, {
    required String action,
  }) async {
    await Future.wait<bool>(
      subscriptions.whereType<StreamSubscription<String>>().map(
        (subscription) => cancelStreamSubscriptionBounded<String>(
          subscription,
          timeout: _eventCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', action, error, stack),
        ),
      ),
    );
  }

  Future<void> _cancelEventProcessSubscriptions(
    _DingTalkEventProcessHandle handle,
  ) {
    final stdoutSubscription = handle.stdoutSubscription;
    final stderrSubscription = handle.stderrSubscription;
    handle.stdoutSubscription = null;
    handle.stderrSubscription = null;
    return _cancelTextSubscriptions(<StreamSubscription<String>?>[
      stdoutSubscription,
      stderrSubscription,
    ], action: '取消钉钉实时事件${handle.label}输出订阅');
  }

  Future<void> _terminateEventProcess(
    _DingTalkEventProcessHandle handle,
  ) async {
    await runAsyncCleanupBounded(
      () => terminateTrackedProcessTree(
        handle.process,
        gracefulTimeout: const Duration(seconds: 2),
      ),
      timeout: _eventCleanupTimeout,
      onError: (error, stack) => silentLog(
        'dingtalk_gateway',
        '停止钉钉实时事件${handle.label}进程',
        error,
        stack,
      ),
    );
    await _cancelEventProcessSubscriptions(handle);
  }

  Future<void> _startEventProcess({
    required String executable,
    required _DingTalkEventSubscriptionSpec spec,
    required int generation,
  }) async {
    final ready = Completer<void>();
    Process? process;
    _DingTalkEventProcessHandle? handle;
    try {
      process = await startTrackedProcessBounded(
        executable,
        spec.arguments,
        timeout: _eventProcessStartTimeout,
        tag: 'dingtalk.event.consume',
        startInNewProcessGroup: true,
      );
      if (generation != _eventGeneration) {
        await terminateTrackedProcessTree(
          process,
          gracefulTimeout: const Duration(seconds: 2),
        );
        throw StateError('钉钉实时事件监听已取消。');
      }
      handle = _DingTalkEventProcessHandle(
        process: process,
        required: spec.required,
        label: spec.label,
      );
      _eventProcesses.add(handle);
      _logRuntime('INFO', '实时事件${spec.label}进程已启动（PID ${process.pid}）。');
      final stdoutDecoder = BoundedProcessLineDecoder(
        maxCharacters: _maxEventOutputLineCharacters,
        onLine: (line) => _consumeEventLine(line, generation),
      );
      handle.stdoutSubscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stdoutDecoder.add,
            onError: (Object error, StackTrace stack) {
              stdoutDecoder.close();
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
            onDone: stdoutDecoder.close,
          );
      final stderrDecoder = BoundedProcessLineDecoder(
        maxCharacters: _maxEventOutputLineCharacters,
        onLine: (line) {
          final normalized = line.trim();
          if (normalized.isNotEmpty && !normalized.contains('[event] ready')) {
            _logRuntime(
              'WARN',
              '实时事件${spec.label}标准错误：${_safeProcessLogLine(normalized)}',
            );
          }
          if (normalized.contains('[event] ready')) {
            if (!ready.isCompleted) ready.complete();
            _logRuntime('SUCCESS', '实时事件${spec.label}监听已就绪。');
          } else if (normalized.startsWith('Error:') && !ready.isCompleted) {
            ready.completeError(StateError(normalized));
          }
        },
      );
      handle.stderrSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            stderrDecoder.add,
            onError: (Object error, StackTrace stack) {
              stderrDecoder.close();
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
            onDone: stderrDecoder.close,
          );
      unawaited(_watchEventProcess(handle, ready, generation));
      await ready.future.timeout(_eventReadyTimeout);
    } catch (_) {
      if (handle != null) {
        _eventProcesses.remove(handle);
      }
      if (process != null) {
        await runAsyncCleanupBounded(
          () => terminateTrackedProcessTree(
            process!,
            gracefulTimeout: const Duration(seconds: 2),
          ),
          timeout: _eventCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', '清理启动失败的钉钉实时事件进程', error, stack),
        );
      }
      if (handle != null) await _cancelEventProcessSubscriptions(handle);
      rethrow;
    }
  }

  Future<void> _watchEventProcess(
    _DingTalkEventProcessHandle handle,
    Completer<void> ready,
    int generation,
  ) async {
    final process = handle.process;
    final exitCode = await process.exitCode;
    if (!ready.isCompleted) {
      ready.completeError(
        StateError('钉钉实时事件${handle.label}进程提前退出（退出码 $exitCode）。'),
      );
    }
    if (generation != _eventGeneration || !_eventProcesses.contains(handle)) {
      return;
    }
    if (exitCode != 0) {
      _logRuntime(
        handle.required ? 'ERROR' : 'WARN',
        '实时事件${handle.label}进程退出，退出码 $exitCode。',
      );
      silentLog(
        'dingtalk_gateway',
        '实时事件${handle.label}进程退出',
        StateError('退出码 $exitCode'),
      );
    } else {
      _logRuntime('INFO', '实时事件${handle.label}进程已退出。');
    }
    _eventProcesses.remove(handle);
    await _cancelEventProcessSubscriptions(handle);
    if (handle.required) {
      await stopEventSubscription();
    }
  }

  Future<void> stopEventSubscription() async {
    _eventGeneration++;
    _eventStartFuture = null;
    final processes = List<_DingTalkEventProcessHandle>.from(_eventProcesses);
    _eventProcesses.clear();
    final controller = _eventController;
    _eventController = null;
    if (processes.isNotEmpty) {
      _logRuntime('INFO', '正在停止钉钉实时事件监听。');
      await Future.wait<void>(processes.map(_terminateEventProcess));
      _logRuntime('SUCCESS', '钉钉实时事件监听已停止。');
    }
    await runAsyncCleanupBounded(
      () => controller?.close(),
      timeout: _eventCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '关闭钉钉实时事件流', error, stack),
    );
  }

  /// 将钉钉消息中的媒体资源下载到确定性本地缓存。缓存文件不存在时会自动重取，
  /// 同一资源并发请求会合并为一次 dws 调用，避免切换会话时重复下载。
  Future<String?> ensureMediaCached(
    DingTalkGatewayMedia media, {
    bool forceRetry = false,
  }) async {
    final resourceId = normalizeDingTalkResourceId(media.resourceId);
    if (resourceId.isEmpty) return null;
    final normalizedMedia = resourceId == media.resourceId
        ? media
        : media.copyWith(resourceId: resourceId);
    final taskKey = _mediaTaskKey(normalizedMedia);
    if (forceRetry) {
      _unavailableMediaUntil.remove(taskKey);
    } else if (_isMediaUnavailable(taskKey)) {
      return null;
    }
    final active = _mediaDownloadTasks[taskKey];
    if (active != null) return active;
    final cancelSignal = _mediaDownloadCancelSignal.future;
    final task = () async {
      bool acquired;
      try {
        acquired = await _mediaDownloadSemaphore.acquireWithin(
          _mediaDownloadQueueTimeout,
          cancelSignal: cancelSignal,
        );
      } on StateError {
        acquired = false;
      }
      if (!acquired) return null;
      try {
        return await _ensureMediaCached(
          normalizedMedia,
          taskKey: taskKey,
          cancelSignal: cancelSignal,
        );
      } finally {
        _mediaDownloadSemaphore.release();
      }
    }();
    _mediaDownloadTasks[taskKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_mediaDownloadTasks[taskKey], task)) {
        _mediaDownloadTasks.remove(taskKey);
      }
    }
  }

  Future<String?> _ensureMediaCached(
    DingTalkGatewayMedia media, {
    required String taskKey,
    required Future<void> cancelSignal,
  }) async {
    final extension = _mediaCacheExtension(media);
    final basename = _stableMediaCacheName(media);
    final filename = '$basename$extension';
    final directory = Directory(mediaCacheDirectoryPath);
    final output = File(p.join(directory.path, filename));
    _activeMediaCacheBasenames.add(basename);
    try {
      await directory
          .create(recursive: true)
          .timeout(_mediaCacheFileOperationTimeout);
      final cachedStat = await _statMediaCacheFileIfPresent(output);
      if (cachedStat != null) {
        if (cachedStat.size > 0 && cachedStat.size <= _maxMediaFileBytes) {
          return output.path;
        }
        await _deleteMediaCacheFileIfPresent(output);
      }
      final cached = await _findCachedMediaFile(directory, basename);
      if (cached != null) return cached.path;
      if (media.resourceType == DingTalkMediaResourceType.mediaId &&
          (media.messageId.trim().isEmpty ||
              media.conversationId.trim().isEmpty)) {
        _logMediaContextWarning(taskKey, media.displayName);
        return null;
      }
      final args = <String>[
        'chat',
        '+messages-resource-download',
        '--resource-id',
        media.resourceId.trim(),
        '--output',
        // dws 只接受工作目录内的相对输出路径。
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
        cancelSignal: cancelSignal,
      );
      final outputStat = await _statMediaCacheFileIfPresent(output);
      if (outputStat == null) {
        throw StateError('钉钉媒体下载完成但未找到本地文件。');
      }
      final outputBytes = outputStat.size;
      if (outputBytes <= 0) {
        throw StateError('钉钉媒体下载完成但文件为空。');
      }
      if (outputBytes > _maxMediaFileBytes) {
        await _deleteMediaCacheFileIfPresent(output);
        throw StateError('钉钉媒体超过 512MB 本地缓存上限。');
      }
      _logRuntime('SUCCESS', '钉钉媒体已缓存：${media.displayName}。');
      unawaited(_pruneMediaCache(directory));
      return output.path;
    } catch (error, stack) {
      // dws 超时或中断时可能留下半截文件，不能让下一次请求误认为缓存有效。
      try {
        await _deleteMediaCacheFileIfPresent(output);
      } catch (cleanupError, cleanupStack) {
        silentLog(
          'dingtalk_gateway',
          '清理损坏的钉钉媒体缓存',
          cleanupError,
          cleanupStack,
        );
      }
      final commandError = _normalizeCommandException(error);
      if (commandError?.isCancelled ?? false) return null;
      if (commandError?.isInvalidInput ?? false) {
        _markMediaUnavailable(taskKey);
        _logRuntime('WARN', '钉钉媒体资源参数无效，已跳过缓存：${media.displayName}。');
        return null;
      }
      if ((commandError?.isResourceNotFound ?? false) ||
          _isResourceNotFoundError(error)) {
        _markMediaUnavailable(taskKey);
        _logRuntime('WARN', '钉钉媒体资源不可用，已停止重复下载：${media.displayName}。');
        // RESOURCE_NOT_FOUND 属于服务端明确的永久业务失败，输出一次简洁日志即可，
        // 不再把完整异常堆栈交给 silentLog，避免实时事件持续刷屏。
        return null;
      }
      if (commandError?.isPermissionDenied ?? false) {
        _markMediaUnavailable(taskKey);
        _logRuntime('WARN', '钉钉媒体资源无下载权限，已暂停自动重试：${media.displayName}。');
        return null;
      }
      if ((commandError?.isBusinessError ?? false) ||
          (commandError?.isRetryable ?? false)) {
        _markMediaUnavailable(taskKey, ttl: _transientMediaFailureCooldown);
        _logRuntime('WARN', '钉钉媒体暂时无法下载，已延后自动重试：${media.displayName}。');
        return null;
      }
      _markMediaUnavailable(taskKey, ttl: _transientMediaFailureCooldown);
      _logRuntime('WARN', '缓存钉钉媒体失败：${media.displayName}。');
      silentLog('dingtalk_gateway', '缓存钉钉媒体', error, stack);
      return null;
    } finally {
      _activeMediaCacheBasenames.remove(basename);
    }
  }

  Future<void> cancelMediaDownloads() async {
    final cancelSignal = _mediaDownloadCancelSignal;
    _mediaDownloadCancelSignal = Completer<void>();
    if (!cancelSignal.isCompleted) cancelSignal.complete();
    _mediaDownloadSemaphore.cancelWaiters();
    final tasks = _mediaDownloadTasks.values.toList(growable: false);
    if (tasks.isNotEmpty) await Future.wait<String?>(tasks);
  }

  Future<void> dispose() {
    return _disposeOnce.run(() async {
      _mediaDownloadSemaphore.cancelWaiters();
      await Future.wait<bool>(<Future<bool>>[
        runAsyncCleanupBounded(
          stopEventSubscription,
          timeout: _eventCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', '停止钉钉实时事件监听', error, stack),
        ),
        runAsyncCleanupBounded(
          cancelMediaDownloads,
          timeout: _eventCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', '取消钉钉媒体下载', error, stack),
        ),
        runAsyncCleanupBounded(
          cancelAuthorization,
          timeout: _eventCleanupTimeout,
          onError: (error, stack) =>
              silentLog('dingtalk_gateway', '取消钉钉设备流授权', error, stack),
        ),
      ]);
      await runAsyncCleanupBounded(
        _runtimeLogController.close,
        timeout: _eventCleanupTimeout,
        onError: (error, stack) =>
            silentLog('dingtalk_gateway', '关闭钉钉运行日志流', error, stack),
      );
    });
  }

  Future<File?> _findCachedMediaFile(
    Directory directory,
    String basename,
  ) async {
    try {
      final listing = await listDirectoryBounded(
        directory,
        maxEntries: _maxMediaCacheScanEntries,
      );
      for (final entity in listing.entries) {
        if (entity is! File ||
            p.basenameWithoutExtension(entity.path) != basename) {
          continue;
        }
        final stat = await _statMediaCacheFileIfPresent(entity);
        if (stat == null) continue;
        if (stat.size > 0 && stat.size <= _maxMediaFileBytes) return entity;
        try {
          await _deleteMediaCacheFileIfPresent(entity);
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '清理损坏的钉钉媒体缓存', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '查找钉钉媒体缓存', error, stack);
    }
    return null;
  }

  String _mediaTaskKey(DingTalkGatewayMedia media) =>
      '${media.resourceType.name}:${normalizeDingTalkResourceId(media.resourceId)}';

  bool _isMediaUnavailable(String key) {
    final until = _unavailableMediaUntil[key];
    if (until == null) return false;
    if (until.isAfter(DateTime.now())) return true;
    _unavailableMediaUntil.remove(key);
    return false;
  }

  void _markMediaUnavailable(
    String key, {
    Duration ttl = _unavailableMediaTtl,
  }) {
    _unavailableMediaUntil[key] = DateTime.now().add(ttl);
    _trimMediaFailureCaches();
  }

  void _logMediaContextWarning(String key, String displayName) {
    final now = DateTime.now();
    final previous = _mediaContextWarningAt[key];
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 5)) {
      return;
    }
    _mediaContextWarningAt[key] = now;
    _trimMediaFailureCaches();
    _logRuntime('WARN', '钉钉媒体缺少消息或会话上下文，暂不下载：$displayName。');
  }

  void _trimMediaFailureCaches() {
    final now = DateTime.now();
    _unavailableMediaUntil.removeWhere((_, until) => !until.isAfter(now));
    _mediaContextWarningAt.removeWhere(
      (_, at) => now.difference(at) >= const Duration(minutes: 5),
    );
    while (_unavailableMediaUntil.length > _maxUnavailableMediaEntries) {
      final oldest = _unavailableMediaUntil.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _unavailableMediaUntil.remove(oldest.key);
    }
    while (_mediaContextWarningAt.length > _maxUnavailableMediaEntries) {
      final oldest = _mediaContextWarningAt.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _mediaContextWarningAt.remove(oldest.key);
    }
  }

  bool _isResourceNotFoundError(Object error) {
    final text = '$error'.toUpperCase();
    return text.contains('RESOURCE_NOT_FOUND') ||
        text.contains('FAILED TO GET DOWNLOAD URL');
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

  Future<void> _deleteMediaCacheFileIfPresent(File file) async {
    try {
      await file.delete().timeout(_mediaCacheFileOperationTimeout);
    } on PathNotFoundException {
      return;
    }
  }

  Future<FileStat?> _statMediaCacheFileIfPresent(File file) async {
    try {
      final stat = await file.stat().timeout(_mediaCacheFileOperationTimeout);
      return stat.type == FileSystemEntityType.file ? stat : null;
    } on PathNotFoundException {
      return null;
    }
  }

  Future<void> _pruneMediaCache(Directory directory) {
    return _mediaCachePruneFlight.run(() async {
      final activeBasenames = Set<String>.of(_activeMediaCacheBasenames);
      try {
        final listing = await listDirectoryBounded(
          directory,
          maxEntries: _maxMediaCacheScanEntries,
        );
        final files = listing.entries.whereType<File>();
        final entries = <(File, int, DateTime)>[];
        var totalBytes = 0;
        for (final file in files) {
          try {
            final stat = await _statMediaCacheFileIfPresent(file);
            if (stat == null) continue;
            totalBytes += stat.size;
            entries.add((file, stat.size, stat.modified));
          } catch (error, stack) {
            silentLog('dingtalk_gateway', '读取钉钉媒体缓存状态', error, stack);
          }
        }
        entries.sort((a, b) => a.$3.compareTo(b.$3));
        var retainedFiles = entries.length;
        while (entries.isNotEmpty &&
            (retainedFiles > _maxMediaCacheFiles ||
                totalBytes > _maxMediaCacheBytes)) {
          final entry = entries.removeAt(0);
          final basename = p.basenameWithoutExtension(entry.$1.path);
          if (activeBasenames.contains(basename) ||
              _activeMediaCacheBasenames.contains(basename)) {
            continue;
          }
          try {
            await _deleteMediaCacheFileIfPresent(entry.$1);
            retainedFiles -= 1;
            totalBytes -= entry.$2;
          } catch (error, stack) {
            silentLog('dingtalk_gateway', '清理钉钉媒体缓存', error, stack);
          }
        }
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '扫描钉钉媒体缓存', error, stack);
      }
    });
  }

  Future<String?> executable() async {
    return _executable ??= await resolvePluginDingtalkWorkspaceCliExecutable();
  }

  Future<DingTalkAuthStatus> authStatus({Future<void>? cancelSignal}) async {
    final decoded = await _runJson(const <String>[
      'auth',
      'status',
      '--format',
      'json',
    ], cancelSignal: cancelSignal);
    final map = _asMap(decoded);
    final data = _asMap(map['data']);
    final authenticated =
        _asBool(map['authenticated']) || _asBool(data['authenticated']);
    final identityMap = _asMap(map['identity']).isNotEmpty
        ? _asMap(map['identity'])
        : _asMap(data['identity']).isNotEmpty
        ? _asMap(data['identity'])
        : _asMap(map['profile']).isNotEmpty
        ? _asMap(map['profile'])
        : _asMap(data['profile']);
    String identityValue(List<String> keys) => _firstValues(<Object?>[
      for (final key in keys) identityMap[key],
      for (final key in keys) data[key],
      for (final key in keys) map[key],
    ]);
    final userId = identityValue(const <String>['userId', 'user_id']);
    final openDingTalkId = identityValue(const <String>[
      'openDingTalkId',
      'open_dingtalk_id',
    ]);
    return DingTalkAuthStatus(
      authenticated: authenticated,
      identity: DingTalkIdentity(
        profile: identityValue(const <String>['profile']),
        userId: userId.isEmpty ? openDingTalkId : userId,
        openDingTalkId: openDingTalkId,
        name: identityValue(const <String>[
          'name',
          'nick',
          'userName',
          'user_name',
        ]),
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
    final output = BoundedLogBuffer(
      maxLines: _maxAuthOutputLines,
      maxCharacters: _maxAuthOutputCharacters,
    );
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
      output.add(line);
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
        unawaited(
          openPendingUrl().then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) =>
                silentLog('dingtalk_gateway', '打开钉钉设备授权地址', error, stack),
          ),
        );
      }
    }

    final stdoutDecoder = BoundedProcessLineDecoder(
      maxCharacters: _maxAuthOutputCharacters,
      onLine: consume,
    );
    stdoutSub = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stdoutDecoder.add,
          onError: (Object error, StackTrace stack) {
            stdoutDecoder.close();
            _logRuntime('ERROR', '读取授权标准输出失败：$error');
            silentLog('dingtalk_gateway', '读取授权输出', error, stack);
          },
          onDone: stdoutDecoder.close,
        );
    final stderrDecoder = BoundedProcessLineDecoder(
      maxCharacters: _maxAuthOutputCharacters,
      onLine: (line) {
        _logRuntime('WARN', '授权标准错误：${_safeProcessLogLine(line)}');
        consume(line);
      },
    );
    stderrSub = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stderrDecoder.add,
          onError: (Object error, StackTrace stack) {
            stderrDecoder.close();
            _logRuntime('ERROR', '读取授权标准错误失败：$error');
            silentLog('dingtalk_gateway', '读取授权错误输出', error, stack);
          },
          onDone: stderrDecoder.close,
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
        final errorOutput = output.snapshot().join('\n').trim();
        throw StateError(errorOutput.isEmpty ? '钉钉授权未完成。' : errorOutput);
      }
      _logRuntime('SUCCESS', '钉钉设备流授权进程已完成。');
      return await authStatus();
    } finally {
      _authProcess = null;
      await _cancelTextSubscriptions(<StreamSubscription<String>>[
        stdoutSub,
        stderrSub,
      ], action: '取消钉钉授权输出订阅');
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
    Future<void>? cancelSignal,
  }) async {
    final now = DateTime.now();
    for (final capabilityKey in _messageQueryWindowPreserved) {
      final retryAt = _messageQueryUnavailableUntil[capabilityKey];
      if (retryAt != null && now.isBefore(retryAt)) {
        return const DingTalkGatewayQueryResult(
          messages: <DingTalkGatewayMessage>[],
          warning: _messageSearchFallbackWarning,
          shouldAdvanceWindow: false,
        );
      }
    }
    final effectiveEnd = end.isBefore(now) ? end : now;
    var effectiveStart = start.isBefore(effectiveEnd)
        ? start
        : effectiveEnd.subtract(_minimumMessageQueryWindow);
    final allEndText = formatYearMonthDayHmsLocal(effectiveEnd);
    var allStartText = formatYearMonthDayHmsLocal(effectiveStart);
    if (allStartText.compareTo(allEndText) >= 0) {
      effectiveStart = effectiveEnd.subtract(_minimumMessageQueryWindow);
      allStartText = formatYearMonthDayHmsLocal(effectiveStart);
      if (allStartText.compareTo(allEndText) >= 0) {
        final localEnd = effectiveEnd.toLocal();
        final wallClockEnd = DateTime.utc(
          localEnd.year,
          localEnd.month,
          localEnd.day,
          localEnd.hour,
          localEnd.minute,
          localEnd.second,
        );
        allStartText = formatYearMonthDayHms(
          wallClockEnd.subtract(_minimumMessageQueryWindow),
        );
      }
    }
    final startText = effectiveStart.toIso8601String();
    final endText = effectiveEnd.toIso8601String();
    final deadline = MonotonicDeadline(
      _messageQueryTotalTimeout,
      timeoutMessage: '钉钉消息轮询超过总时限。',
    );
    late final List<_DingTalkMessagePageResult> pageResults;
    try {
      pageResults = await Future.wait<_DingTalkMessagePageResult>(
        <Future<_DingTalkMessagePageResult>>[
          _queryMessagePages(
            (cursor) => <String>[
              'chat',
              'message',
              'list-mentions',
              '--start',
              startText,
              '--end',
              endText,
              '--limit',
              '$_messageQueryPageSize',
              '--cursor',
              cursor,
              '--format',
              'json',
            ],
            capabilityKey: 'mentions',
            label: '@我消息',
            deadline: deadline,
            cancelSignal: cancelSignal,
          ),
          _queryMessagePages(
            (cursor) => <String>[
              'chat',
              'message',
              'list-all',
              '--start',
              allStartText,
              '--end',
              allEndText,
              '--limit',
              '$_messageQueryPageSize',
              '--cursor',
              cursor,
              '--format',
              'json',
            ],
            capabilityKey: 'all',
            label: '全部消息',
            deadline: deadline,
            cancelSignal: cancelSignal,
          ),
        ],
      );
    } finally {
      deadline.stop();
    }
    final mentions = pageResults[0].pages;
    final all = pageResults[1].pages;
    final messages = <DingTalkGatewayMessage>[
      for (final page in mentions)
        ..._parseMessages(page, mentionedCurrentUser: true),
      for (final page in all) ..._parseMessages(page),
    ];
    final warnings = <String>{};
    for (final pageResult in pageResults) {
      final warning = pageResult.warning?.trim() ?? '';
      if (warning.isNotEmpty) warnings.add(warning);
    }
    for (final page in all) {
      final candidate = _findPageField(page, const <String>[
        'friendly_hint',
        'friendlyHint',
      ])?.toString().trim();
      if (candidate != null && candidate.isNotEmpty) warnings.add(candidate);
    }
    return DingTalkGatewayQueryResult(
      messages: messages,
      warning: warnings.isEmpty ? null : warnings.join('；'),
      shouldAdvanceWindow: pageResults.every(
        (result) => result.shouldAdvanceWindow,
      ),
    );
  }

  Future<_DingTalkMessagePageResult> _queryMessagePages(
    List<String> Function(String cursor) buildArguments, {
    required String capabilityKey,
    required String label,
    required MonotonicDeadline deadline,
    Future<void>? cancelSignal,
  }) async {
    final now = DateTime.now();
    final unavailableUntil = _messageQueryUnavailableUntil[capabilityKey];
    if (unavailableUntil != null) {
      if (now.isBefore(unavailableUntil)) {
        return _DingTalkMessagePageResult(
          pages: const <Object?>[],
          warning: _messageSearchFallbackWarning,
          shouldAdvanceWindow: !_messageQueryWindowPreserved.contains(
            capabilityKey,
          ),
        );
      }
      _messageQueryUnavailableUntil.remove(capabilityKey);
    }
    final pages = <Object?>[];
    var cursor = '0';
    for (var pageIndex = 0; pageIndex < _messageQueryMaxPages; pageIndex++) {
      late final Object? page;
      try {
        page = await _runJson(
          buildArguments(cursor),
          timeout: deadline.limit(_commandTimeout),
          cancelSignal: cancelSignal,
        );
      } catch (error, stack) {
        final commandError = _normalizeCommandException(error);
        if (commandError?.isCancelled == true) rethrow;
        final dependencyUnavailable =
            commandError?.isDependencyUnavailable == true;
        final transientFailure =
            error is TimeoutException || commandError?.isRetryable == true;
        final unavailableBusinessError =
            commandError?.isBusinessError == true &&
            commandError?.isRetryable != true;
        if (dependencyUnavailable ||
            transientFailure ||
            unavailableBusinessError) {
          _messageQueryUnavailableUntil[capabilityKey] = DateTime.now().add(
            dependencyUnavailable
                ? _messageQueryDependencyCooldown
                : transientFailure
                ? _messageQueryRetryCooldown
                : _messageQueryUnavailableCooldown,
          );
          if (dependencyUnavailable || transientFailure) {
            _messageQueryWindowPreserved.add(capabilityKey);
          } else {
            _messageQueryWindowPreserved.remove(capabilityKey);
          }
          _logRuntime(
            'WARN',
            dependencyUnavailable
                ? '钉钉$label搜索后端暂不可用，已暂缓查询并切换事件流和会话对账。'
                : transientFailure
                ? '钉钉$label同步超时，已暂停 ${_messageQueryRetryCooldown.inSeconds} 秒并保留同步窗口。'
                : '钉钉$label搜索暂不可用，已切换事件流和会话对账。',
          );
          return _DingTalkMessagePageResult(
            pages: pages,
            warning: _messageSearchFallbackWarning,
            shouldAdvanceWindow: !dependencyUnavailable && !transientFailure,
          );
        }
        if (pages.isEmpty) rethrow;
        _messageQueryUnavailableUntil[capabilityKey] = DateTime.now().add(
          _messageQueryRetryCooldown,
        );
        _messageQueryWindowPreserved.add(capabilityKey);
        _logRuntime('WARN', '钉钉$label后续分页失败，已保留前面已同步的消息。');
        silentLog('dingtalk_gateway', '读取钉钉$label后续分页', error, stack);
        return _DingTalkMessagePageResult(
          pages: pages,
          warning: _messageSearchFallbackWarning,
          shouldAdvanceWindow: false,
        );
      }
      pages.add(page);
      final nextCursor = _nextPageCursor(page);
      if (nextCursor.isEmpty || nextCursor == cursor) break;
      if (!_hasMorePages(page)) break;
      if (pageIndex + 1 == _messageQueryMaxPages) {
        _logRuntime('WARN', '钉钉$label分页达到上限，较早消息将在后续对账中补齐。');
        break;
      }
      cursor = nextCursor;
    }
    _messageQueryWindowPreserved.remove(capabilityKey);
    return _DingTalkMessagePageResult(pages: pages);
  }

  bool _hasMorePages(Object? raw) {
    return _asBool(_findPageField(raw, const <String>['hasMore', 'has_more']));
  }

  String _nextPageCursor(Object? raw) {
    return _firstValues(<Object?>[
      _findPageField(raw, const <String>['nextCursor', 'next_cursor']),
    ]);
  }

  Object? _findPageField(Object? raw, List<String> keys, {int depth = 0}) {
    if (depth > 4 || raw is! Map) return null;
    final map = _asMap(raw);
    for (final key in keys) {
      final value = map[key];
      if (value != null) return value;
    }
    for (final key in const <String>['result', 'data', 'page', 'pagination']) {
      final value = map[key];
      final found = _findPageField(value, keys, depth: depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  /// 回读指定会话的最近消息。消息编辑不会产生个人 IM 事件，
  /// 因此由控制器以低频、有界的方式调用此接口做状态对账。
  Future<DingTalkConversationMessagePage> queryConversationPage({
    required DingTalkConversation conversation,
    int limit = 50,
    DateTime? before,
  }) async {
    final normalizedLimit = limit.clamp(1, 50);
    final queryKey = _conversationQueryKey(conversation);
    final unavailableUntil = _conversationQueryUnavailableUntil[queryKey];
    if (unavailableUntil != null) {
      if (DateTime.now().isBefore(unavailableUntil)) {
        return const DingTalkConversationMessagePage(
          messages: <DingTalkGatewayMessage>[],
          hasMore: false,
        );
      }
      _conversationQueryUnavailableUntil.remove(queryKey);
    }
    final fallbackConversationId = conversation.dwsConversationId.isNotEmpty
        ? conversation.dwsConversationId
        : conversation.id;
    final boundary = before ?? DateTime.now();
    late final Object? result;
    try {
      result = await _runJson(<String>[
        'chat',
        'message',
        'list',
        ..._targetArguments(conversation),
        '--time',
        formatYearMonthDayHmsLocal(boundary),
        '--limit',
        '$normalizedLimit',
        '--direction',
        'older',
        '--format',
        'json',
      ], timeout: const Duration(seconds: 25));
    } catch (error) {
      final commandError = _normalizeCommandException(error);
      if (commandError != null &&
          (commandError.isDependencyUnavailable ||
              commandError.isBusinessError && !commandError.isRetryable)) {
        _markConversationQueryUnavailable(
          queryKey,
          cooldown: commandError.isDependencyUnavailable
              ? _messageQueryDependencyCooldown
              : _conversationQueryUnavailableCooldown,
        );
        _logRuntime('WARN', '钉钉会话消息搜索暂不可用，已依赖实时事件和其他对账。');
        return const DingTalkConversationMessagePage(
          messages: <DingTalkGatewayMessage>[],
          hasMore: false,
        );
      }
      rethrow;
    }
    final parsed = _parseMessages(
      result,
      fallbackConversationId: fallbackConversationId,
      fallbackMediaConversationId: conversation.dwsConversationId,
      fallbackConversationType: conversation.type,
    );
    final indexed = parsed.asMap().entries.toList(growable: true);
    indexed.sort((left, right) {
      final created = left.value.createdAt.compareTo(right.value.createdAt);
      return created != 0 ? created : left.key.compareTo(right.key);
    });
    final messages = indexed
        .map((entry) => entry.value)
        .toList(growable: false);
    final hasMoreValue = _findPageField(result, const <String>[
      'hasMore',
      'has_more',
    ]);
    final hasMore = hasMoreValue == null
        ? messages.length >= normalizedLimit
        : _asBool(hasMoreValue);
    final oldestMessageAt = messages.isEmpty ? null : messages.first.createdAt;
    return DingTalkConversationMessagePage(
      messages: messages,
      hasMore: hasMore,
      oldestMessageAt: oldestMessageAt,
    );
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

  Future<String?> send({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
  }) async => (await sendWithDetails(
    conversation: conversation,
    text: text,
    uuid: uuid,
  ))?.messageId;

  Future<DingTalkSentMessage?> sendWithDetails({
    required DingTalkConversation conversation,
    required String text,
    required String uuid,
  }) async {
    final result = await _runJson(<String>[
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
    return _sentMessageDetails(result);
  }

  /// dws 发送接口部分版本只返回 success/result=[]，通过会话消息列表补齐真实消息标识。
  Future<DingTalkSentMessage?> resolveRecentSentMessage({
    required DingTalkConversation conversation,
    required String content,
    required DateTime createdAt,
    String senderName = '',
  }) async {
    final normalizedContent = normalizeDingTalkMessageContentForComparison(
      content,
    );
    if (normalizedContent.isEmpty) return null;
    final result = await _runJson(<String>[
      'chat',
      'message',
      'list',
      ..._targetArguments(conversation),
      '--time',
      formatYearMonthDayHms(
        createdAt.subtract(_sentMessageLookupWindow).toLocal(),
      ),
      '--limit',
      '$_sentMessageLookupLimit',
      '--direction',
      'newer',
      '--format',
      'json',
    ], timeout: _sentMessageLookupTimeout);
    var candidates = _parseMessages(result)
        .where((message) {
          final distance = message.createdAt.difference(createdAt).abs();
          return distance <= _sentMessageLookupWindow &&
              message.id.trim().isNotEmpty;
        })
        .toList(growable: true);
    if (candidates.isEmpty) return null;
    final expectedSender = senderName.trim();
    if (expectedSender.isNotEmpty) {
      final senderMatches = candidates
          .where((message) {
            final candidateSender = message.senderName.trim();
            return candidateSender.isNotEmpty &&
                (candidateSender == expectedSender ||
                    candidateSender.startsWith(expectedSender) ||
                    expectedSender.startsWith(candidateSender));
          })
          .toList(growable: false);
      if (senderMatches.isNotEmpty) {
        candidates = senderMatches;
      } else if (candidates.every(
        (message) => message.senderName.trim().isNotEmpty,
      )) {
        return null;
      }
    }
    final selfMatches = candidates
        .where((message) => message.fromSelf)
        .toList(growable: false);
    if (selfMatches.isNotEmpty) candidates = selfMatches;
    final exact = candidates
        .where(
          (message) =>
              normalizeDingTalkMessageContentForComparison(message.content) ==
              normalizedContent,
        )
        .toList(growable: true);
    // 只允许精确正文命中，避免并发发送时误绑定并编辑其他消息。
    if (exact.isEmpty) return null;
    exact.sort(
      (a, b) => a.createdAt
          .difference(createdAt)
          .abs()
          .compareTo(b.createdAt.difference(createdAt).abs()),
    );
    final selected = exact.first;
    return DingTalkSentMessage(
      messageId: selected.id,
      conversationId: selected.conversationId,
    );
  }

  Future<void> editMessage({
    required DingTalkConversation conversation,
    required String messageId,
    required String text,
  }) async {
    final normalizedId = messageId.trim();
    final normalizedText = text.trim();
    if (normalizedId.isEmpty) throw const FormatException('消息标识为空。');
    if (normalizedText.isEmpty) throw const FormatException('消息内容为空。');
    final conversationId = conversation.dwsConversationId;
    if (conversationId.isEmpty) {
      throw StateError('缺少钉钉开放会话标识，暂时无法编辑消息。');
    }
    await _runJson(<String>[
      'chat',
      'message',
      'edit',
      '--conversation-id',
      conversationId,
      '--msg-id',
      normalizedId,
      '--text',
      normalizedText,
      '--format',
      'json',
    ]);
  }

  Future<String?> sendFile({
    required DingTalkConversation conversation,
    required String filePath,
    required String uuid,
    bool audio = false,
    Future<void>? cancelSignal,
  }) async => (await sendFileWithDetails(
    conversation: conversation,
    filePath: filePath,
    uuid: uuid,
    audio: audio,
    cancelSignal: cancelSignal,
  ))?.messageId;

  Future<DingTalkSentMessage?> sendFileWithDetails({
    required DingTalkConversation conversation,
    required String filePath,
    required String uuid,
    bool audio = false,
    Future<void>? cancelSignal,
  }) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) throw const FormatException('文件路径为空。');
    final result = await _runJson(
      <String>[
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
      ],
      timeout: _fileSendTimeout,
      cancelSignal: cancelSignal,
    );
    return _sentMessageDetails(result);
  }

  DingTalkSentMessage? _sentMessageDetails(Object? value) {
    String find(Object? current, int depth) {
      if (depth > 4) return '';
      if (current is List) {
        for (final item in current) {
          final id = find(item, depth + 1);
          if (id.isNotEmpty) return id;
        }
        return '';
      }
      if (current is! Map) return '';
      final map = _asMap(current);
      for (final key in const <String>[
        'open_message_id',
        'openMessageId',
        'open_msg_id',
        'openMsgId',
        'message_id',
        'messageId',
        'msg_id',
        'msgId',
      ]) {
        final id = '${map[key] ?? ''}'.trim();
        if (id.isNotEmpty && id != 'null') return id;
      }
      for (final child in map.values) {
        final id = find(child, depth + 1);
        if (id.isNotEmpty) return id;
      }
      return '';
    }

    String findOpenConversationId(Object? current, int depth) {
      if (depth > 4) return '';
      if (current is List) {
        for (final item in current) {
          final id = findOpenConversationId(item, depth + 1);
          if (id.isNotEmpty) return id;
        }
        return '';
      }
      if (current is! Map) return '';
      final map = _asMap(current);
      for (final key in const <String>[
        'open_conversation_id',
        'openConversationId',
      ]) {
        final id = '${map[key] ?? ''}'.trim();
        if (id.isNotEmpty && id != 'null') return id;
      }
      for (final child in map.values) {
        final id = findOpenConversationId(child, depth + 1);
        if (id.isNotEmpty) return id;
      }
      return '';
    }

    final messageId = find(value, 0);
    final conversationId = findOpenConversationId(value, 0);
    if (messageId.isEmpty && conversationId.isEmpty) return null;
    return DingTalkSentMessage(
      messageId: messageId.isEmpty ? null : messageId,
      conversationId: conversationId.isEmpty ? null : conversationId,
    );
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

  String _conversationQueryKey(DingTalkConversation conversation) =>
      '${conversation.type.name}:${_targetArguments(conversation).join(':')}';

  void _markConversationQueryUnavailable(
    String queryKey, {
    Duration cooldown = _conversationQueryUnavailableCooldown,
  }) {
    final now = DateTime.now();
    _conversationQueryUnavailableUntil
      ..removeWhere((_, until) => !until.isAfter(now))
      ..[queryKey] = now.add(cooldown);
    while (_conversationQueryUnavailableUntil.length >
        _maxConversationQueryFailures) {
      final oldest = _conversationQueryUnavailableUntil.entries.reduce(
        (left, right) => left.value.isBefore(right.value) ? left : right,
      );
      _conversationQueryUnavailableUntil.remove(oldest.key);
    }
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
          _isExpectedCommandFailure(error)) {
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
      } catch (_) {
        if (!_isExpectedCommandFailure(error)) {
          silentLog('dingtalk_gateway', '按标识读取联系人', error, stack);
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

  bool _isExpectedCommandFailure(Object error) {
    if (error is DingTalkGatewayCommandException) {
      return error.isBusinessError || error.isDependencyUnavailable;
    }
    final text = '$error';
    final normalized = text.toLowerCase();
    return normalized.contains('mcp 后端依赖暂时不可用') ||
        normalized.contains('mcp backend dependency temporarily unavailable') ||
        text.contains('"category"') &&
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
      retryable:
          _asBool(details['retryable']) || _asBool(details['is_retryable']),
      retryAfterSeconds: int.tryParse(
        '${details['retry_after_seconds'] ?? details['retryAfterSeconds'] ?? ''}',
      ),
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
        } catch (_) {
          if (!_isExpectedCommandFailure(error)) {
            silentLog('dingtalk_gateway', '读取会话基础信息', error, stack);
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
      if (_isExpectedCommandFailure(error)) {
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
    final results = await runOrderedWithConcurrencyLimit<R?>(
      itemCount: values.length,
      maxConcurrency: _detailConcurrency,
      task: (index) async {
        try {
          return await action(values[index]);
        } catch (error, stack) {
          if (_isExpectedCommandFailure(error)) {
            return null;
          }
          silentLog('dingtalk_gateway', onError, error, stack);
          return null;
        }
      },
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
    Future<void>? cancelSignal,
  }) async {
    final operation = arguments.take(3).join(' ');
    final effectiveTimeout = timeout ?? _commandTimeout;
    final commandArguments = List<String>.of(arguments);
    if (!commandArguments.contains('--timeout')) {
      final dwsTimeoutSeconds = math.max(
        1,
        effectiveTimeout.inSeconds - _commandCleanupReserve.inSeconds,
      );
      commandArguments.addAll(<String>['--timeout', '$dwsTimeoutSeconds']);
    }
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
        commandArguments,
        timeout: effectiveTimeout,
        tag: 'dingtalk_gateway.command',
        workingDirectory: workingDirectory,
        // Schema 是多行 JSON，命令目录可能超过四万行，且描述行可能超过
        // 默认 4,000 字符；截断行或丢弃前面的行都会破坏整体 JSON。
        maxCapturedLinesPerStream: 65536,
        maxLineCharacters: 64 * kBytesPerKiB,
        cancelSignal: cancelSignal,
        onStderrLine: (line) =>
            _logRuntime('WARN', 'dws 标准错误：${_safeProcessLogLine(line)}'),
      );
    } catch (error) {
      _logRuntime('ERROR', 'dws 启动或执行异常：$error');
      rethrow;
    }
    final isMessageQuery = _isMessageQueryCommand(commandArguments);
    if (result.timedOut) {
      final message = 'dws 执行超时并已终止：$operation。';
      _logRuntime(isMessageQuery ? 'WARN' : 'ERROR', message);
      throw DingTalkGatewayCommandException(
        message: message,
        reason: 'timeout',
        operation: operation,
        retryable: true,
      );
    }
    if (result.cancelled) {
      throw DingTalkGatewayCommandException(
        message: 'dws 执行已取消：$operation。',
        reason: 'cancelled',
        operation: operation,
        retryable: true,
      );
    }
    final structuredOutput = result.stdout.trim().isNotEmpty
        ? result.stdout
        : result.stderr;
    final decoded = _decodeJson(structuredOutput);
    final payload = _asMap(decoded);
    final error = _asMap(payload['error']);
    final explicitFailure =
        payload.containsKey('success') && !_asBool(payload['success']);
    final executionFailed =
        result.exitCode != 0 || error.isNotEmpty || explicitFailure;
    _logRuntime(
      executionFailed
          ? isMessageQuery
                ? 'WARN'
                : 'ERROR'
          : 'SUCCESS',
      'dws 执行结束：$operation，退出码 ${result.exitCode}。',
    );
    if (result.stdout.trim().isNotEmpty && decoded is Map && payload.isEmpty) {
      _logRuntime('WARN', 'dws 返回内容无法解析为有效 JSON。');
    }
    if (result.exitCode != 0 || error.isNotEmpty || explicitFailure) {
      var fallbackMessage = result.exitCode == 0
          ? 'dws 执行失败。'
          : 'dws 执行失败（退出码 ${result.exitCode}）。';
      if (explicitFailure) fallbackMessage = 'dws 返回 success=false。';
      final message =
          nullIfBlank(error['message']?.toString()) ??
          nullIfBlank(payload['message']?.toString()) ??
          nonBlankStringOr(result.stderr, fallbackMessage);
      final retryAfterSeconds = int.tryParse(
        '${error['retry_after_seconds'] ?? error['retryAfterSeconds'] ?? ''}',
      );
      final hasStructuredError = error.isNotEmpty;
      _logRuntime(
        isMessageQuery ? 'WARN' : 'ERROR',
        'dws 业务调用失败：${_safeProcessLogLine(message)}',
      );
      String? fallbackReason;
      if (explicitFailure) {
        fallbackReason = 'business_error';
      } else if (!hasStructuredError && result.exitCode != 0) {
        fallbackReason = 'process_exit';
      }
      throw DingTalkGatewayCommandException(
        message: message,
        category: error['category']?.toString(),
        reason: error['reason']?.toString() ?? fallbackReason,
        serverCode: error['server_error_code']?.toString(),
        operation: error['operation']?.toString(),
        retryable:
            _asBool(error['retryable']) || _asBool(error['is_retryable']),
        retryAfterSeconds: retryAfterSeconds,
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
    String fallbackConversationId = '',
    String fallbackMediaConversationId = '',
    DingTalkConversationType? fallbackConversationType,
  }) {
    final values = <Object?>[];
    DingTalkConversationType? inferConversationType(Map<String, Object?> map) {
      final typeText = _first(map, const <String>[
        'conversationType',
        'conversation_type',
        'chatType',
        'chat_type',
      ]).toLowerCase();
      if (typeText.contains('group') || typeText == '2') {
        return DingTalkConversationType.group;
      }
      if (typeText.contains('direct') || typeText == '1') {
        return DingTalkConversationType.direct;
      }
      if (map.containsKey('singleChat')) {
        return _asBool(map['singleChat'])
            ? DingTalkConversationType.direct
            : DingTalkConversationType.group;
      }
      if (map.containsKey('single_chat')) {
        return _asBool(map['single_chat'])
            ? DingTalkConversationType.direct
            : DingTalkConversationType.group;
      }
      return null;
    }

    void collect(
      Object? value, {
      String inheritedConversationId = '',
      DingTalkConversationType? inheritedConversationType,
      String inheritedConversationTitle = '',
    }) {
      if (value is List) {
        for (final item in value) {
          collect(
            item,
            inheritedConversationId: inheritedConversationId,
            inheritedConversationType: inheritedConversationType,
            inheritedConversationTitle: inheritedConversationTitle,
          );
        }
        return;
      }
      if (value is Map) {
        final map = _asMap(value);
        final explicitMessageId = _first(map, const <String>[
          'openMessageId',
          'open_message_id',
          'openMsgId',
          'open_msg_id',
          'messageId',
          'message_id',
          'msgId',
          'msg_id',
        ]);
        final hasMessageIdentity =
            explicitMessageId.isNotEmpty ||
            (_first(map, const <String>['id']).isNotEmpty &&
                _looksLikeMessageRecord(
                  map,
                  inheritedConversationId: inheritedConversationId,
                ));
        if (hasMessageIdentity) {
          final enriched = Map<String, Object?>.from(map);
          if (_first(enriched, const <String>[
                'openConversationId',
                'open_conversation_id',
                'conversationId',
                'conversation_id',
                'chatId',
                'chat_id',
              ]).isEmpty &&
              inheritedConversationId.isNotEmpty) {
            enriched['conversationId'] = inheritedConversationId;
          }
          if (inferConversationType(enriched) == null &&
              inheritedConversationType != null) {
            enriched['conversationType'] =
                inheritedConversationType == DingTalkConversationType.group
                ? 'group'
                : 'direct';
          }
          if (_first(enriched, const <String>[
                'conversationTitle',
                'groupName',
                'title',
              ]).isEmpty &&
              inheritedConversationTitle.isNotEmpty) {
            enriched['conversationTitle'] = inheritedConversationTitle;
          }
          values.add(enriched);
          return;
        }
        final nextConversationId = _first(map, const <String>[
          'openConversationId',
          'open_conversation_id',
          'conversationId',
          'conversation_id',
          'chatId',
          'chat_id',
        ]);
        final nextConversationType =
            inferConversationType(map) ?? inheritedConversationType;
        final nextConversationTitle = _first(map, const <String>[
          'conversationTitle',
          'groupName',
          'title',
        ]);
        for (final key in const <String>[
          'messages',
          'conversationMessagesList',
          'conversation_messages_list',
          'conversationMessages',
          'conversation_messages',
          'items',
          'records',
          'data',
          'result',
        ]) {
          final child = value[key];
          if (child is List || child is Map) {
            collect(
              child,
              inheritedConversationId: nextConversationId.isEmpty
                  ? inheritedConversationId
                  : nextConversationId,
              inheritedConversationType: nextConversationType,
              inheritedConversationTitle: nextConversationTitle.isEmpty
                  ? inheritedConversationTitle
                  : nextConversationTitle,
            );
          }
        }
      }
    }

    collect(raw);
    final result = <DingTalkGatewayMessage>[];
    for (final value in values) {
      if (value is! Map) continue;
      final map = _asMap(value);
      final id = normalizeDingTalkMessageId(
        _first(map, const <String>[
          'openMessageId',
          'open_message_id',
          'openMsgId',
          'open_msg_id',
          'messageId',
          'message_id',
          'msgId',
          'msg_id',
          'id',
        ]),
      );
      final content = _content(map);
      final automaticReplyCard = _automaticReplyCard(map);
      final typedContent = automaticReplyCard == null
          ? content
          : automaticReplyCard.plainText.isNotEmpty
          ? automaticReplyCard.plainText
          : automaticReplyCard.title;
      final parsedConversationId = _first(map, const <String>[
        'openConversationId',
        'open_conversation_id',
        'conversationId',
        'conversation_id',
        'chatId',
        'chat_id',
      ]);
      final conversationId = parsedConversationId.isNotEmpty
          ? parsedConversationId
          : fallbackConversationId.trim();
      final mediaConversationId = parsedConversationId.isNotEmpty
          ? conversationId
          : fallbackMediaConversationId.trim().isNotEmpty
          ? fallbackMediaConversationId.trim()
          : fallbackConversationType == DingTalkConversationType.group
          ? conversationId
          : '';
      final media = _extractMedia(map)
          .map(
            (item) => item.copyWith(
              messageId: item.messageId.trim().isEmpty ? id : item.messageId,
              conversationId: item.conversationId.trim().isEmpty
                  ? mediaConversationId
                  : item.conversationId,
            ),
          )
          .toList(growable: false);
      final createdAt = _parseDateTime(
        map['createTime'] ??
            map['createdAt'] ??
            map['create_time'] ??
            map['created_at'] ??
            map['createAt'] ??
            map['create_at'] ??
            map['messageCreateTime'] ??
            map['message_create_time'] ??
            map['messageCreateAt'] ??
            map['message_create_at'] ??
            map['msgCreateTime'] ??
            map['msg_create_time'] ??
            map['msgCreateAt'] ??
            map['msg_create_at'] ??
            map['sendTime'] ??
            map['send_time'] ??
            map['msgTime'] ??
            map['msg_time'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final forwarded = _parseForwardedMessages(
        map,
        fallbackConversationId: mediaConversationId,
        fallbackCreatedAt: createdAt,
      );
      final quotedMessage = _parseQuotedMessage(
        map,
        fallbackConversationId: mediaConversationId,
        fallbackCreatedAt: createdAt,
      );
      final displayContent = media.isEmpty
          ? typedContent
          : _mediaDisplayContent(typedContent, media);
      if (id.isEmpty ||
          (content.isEmpty &&
              automaticReplyCard == null &&
              media.isEmpty &&
              quotedMessage == null &&
              forwarded.messages.isEmpty &&
              !_messageRecalled(map)) ||
          conversationId.isEmpty) {
        continue;
      }
      final typeText = _first(map, const <String>[
        'conversationType',
        'conversation_type',
        'chatType',
      ]).toLowerCase();
      final conversationType = typeText.contains('group') || typeText == '2'
          ? DingTalkConversationType.group
          : typeText.isNotEmpty
          ? DingTalkConversationType.direct
          : fallbackConversationType ?? DingTalkConversationType.direct;
      final recalled = _messageRecalled(map);
      result.add(
        DingTalkGatewayMessage(
          id: id,
          conversationId: conversationId,
          conversationType: conversationType,
          role: DingTalkGatewayMessageRole.user,
          content: displayContent.isEmpty && !recalled
              ? forwarded.messages.isNotEmpty
                    ? '转发的聊天记录'
                    : _mediaSummary(media)
              : displayContent,
          createdAt: createdAt,
          senderName: _eventString(map, const <String>[
            'senderName',
            'senderNick',
            'sender_name',
            'nick',
            'sender',
          ]),
          senderId: _eventSenderId(map),
          senderOpenDingTalkId: _eventSenderOpenDingTalkId(map),
          conversationTitle: _first(map, const <String>[
            'conversationTitle',
            'groupName',
            'title',
          ]),
          messageType: automaticReplyCard == null
              ? DingTalkGatewayMessageType.text
              : DingTalkGatewayMessageType.automaticReply,
          automaticReplyCard: automaticReplyCard,
          media: media,
          quotedMessage: quotedMessage,
          forwardedMessages: forwarded.messages,
          forwardedMessageCount: forwarded.totalCount,
          fromSelf:
              _asBool(map['isSelf']) ||
              _asBool(map['is_self']) ||
              _asBool(map['isMine']) ||
              _asBool(map['is_mine']) ||
              _asBool(map['isSelfLoop']) ||
              _asBool(map['is_self_loop']),
          readByPeer: _asBool(
            map['readByPeer'] ??
                map['read_by_peer'] ??
                map['isRead'] ??
                map['is_read'] ??
                map['read'],
          ),
          recalled: recalled,
          reactions: parseDingTalkMessageReactions(map),
          reactionSnapshotComplete: true,
          mentionedCurrentUser:
              mentionedCurrentUser ||
              _asBool(map['mentionedCurrentUser']) ||
              _asBool(map['mentioned_current_user']),
        ),
      );
    }
    return result;
  }

  ({List<DingTalkForwardedMessage> messages, int totalCount})
  _parseForwardedMessages(
    Map<String, Object?> map, {
    required String fallbackConversationId,
    required DateTime fallbackCreatedAt,
  }) {
    final raw = map['forwardMessages'] ?? map['forward_messages'];
    if (raw is! List || raw.isEmpty) {
      return (messages: const <DingTalkForwardedMessage>[], totalCount: 0);
    }
    final messages = <DingTalkForwardedMessage>[];
    for (final value in raw.take(kDingTalkForwardedMessageLimit)) {
      if (value is! Map) continue;
      final child = _asMap(value);
      final id = normalizeDingTalkMessageId(
        _first(child, const <String>[
          'openMessageId',
          'open_message_id',
          'openMsgId',
          'open_msg_id',
          'messageId',
          'message_id',
          'msgId',
          'msg_id',
          'id',
        ]),
      );
      final conversationId = _first(child, const <String>[
        'openConversationId',
        'open_conversation_id',
        'conversationId',
        'conversation_id',
      ]);
      final mediaConversationId = conversationId.isEmpty
          ? fallbackConversationId
          : conversationId;
      final media = _extractMedia(child)
          .map(
            (item) => item.copyWith(
              messageId: item.messageId.trim().isEmpty ? id : item.messageId,
              conversationId: item.conversationId.trim().isEmpty
                  ? mediaConversationId
                  : item.conversationId,
            ),
          )
          .toList(growable: false);
      final content = _content(child);
      final displayContent = media.isEmpty
          ? content
          : _mediaDisplayContent(content, media);
      if (displayContent.isEmpty && media.isEmpty) continue;
      messages.add(
        DingTalkForwardedMessage(
          id: id,
          content: displayContent,
          createdAt: _parseDateTime(
            child['createTime'] ??
                child['createdAt'] ??
                child['create_time'] ??
                child['created_at'],
            fallback: fallbackCreatedAt,
          ),
          senderName: _eventString(child, const <String>[
            'senderName',
            'senderNick',
            'sender_name',
            'nick',
            'sender',
          ]),
          senderId: _eventString(child, const <String>[
            'senderId',
            'senderUserId',
            'senderOpenDingTalkId',
            'sender_id',
            'sender_open_dingtalk_id',
            'sender',
          ]),
          media: media,
        ),
      );
    }
    return (messages: messages.toList(growable: false), totalCount: raw.length);
  }

  DingTalkQuotedMessage? _parseQuotedMessage(
    Map<String, Object?> map, {
    required String fallbackConversationId,
    required DateTime fallbackCreatedAt,
  }) {
    Object? raw = map['quotedMessage'] ?? map['quoted_message'];
    if (raw is String) {
      final decoded = _decodeJson(raw);
      if (decoded is Map) raw = decoded;
    }
    if (raw is! Map) return null;
    final quoted = _asMap(raw);
    final id = normalizeDingTalkMessageId(
      _first(quoted, const <String>[
        'openMessageId',
        'open_message_id',
        'openMsgId',
        'open_msg_id',
        'messageId',
        'message_id',
        'msgId',
        'msg_id',
        'id',
      ]),
    );
    final conversationId = _first(quoted, const <String>[
      'openConversationId',
      'open_conversation_id',
      'conversationId',
      'conversation_id',
      'chatId',
      'chat_id',
    ]);
    final mediaConversationId = conversationId.isEmpty
        ? fallbackConversationId
        : conversationId;
    final media = _extractMedia(quoted, includeResourceRefs: true)
        .map(
          (item) => item.copyWith(
            messageId: item.messageId.trim().isEmpty ? id : item.messageId,
            conversationId: item.conversationId.trim().isEmpty
                ? mediaConversationId
                : item.conversationId,
          ),
        )
        .toList(growable: false);
    final content = _content(quoted);
    final displayContent = media.isEmpty
        ? content
        : _mediaDisplayContent(content, media);
    if (id.isEmpty && displayContent.isEmpty && media.isEmpty) return null;
    return DingTalkQuotedMessage(
      id: id,
      content: displayContent.isEmpty ? _mediaSummary(media) : displayContent,
      createdAt: _parseDateTime(
        quoted['createTime'] ??
            quoted['createdAt'] ??
            quoted['create_time'] ??
            quoted['created_at'],
        fallback: fallbackCreatedAt,
      ),
      senderName: _eventString(quoted, const <String>[
        'senderName',
        'senderNick',
        'sender_name',
        'nick',
        'sender',
      ]),
      senderId: _eventSenderId(quoted),
      media: media,
    );
  }

  bool _looksLikeMessageRecord(
    Map<String, Object?> map, {
    required String inheritedConversationId,
  }) {
    const nestedMessageKeys = <String>{
      'messages',
      'conversationMessagesList',
      'conversation_messages_list',
      'conversationMessages',
      'conversation_messages',
      'items',
      'records',
    };
    if (map.keys.any(nestedMessageKeys.contains)) return false;
    const messageFields = <String>{
      'content',
      'text',
      'msgContent',
      'msg_content',
      'richText',
      'rich_text',
      'markdown',
      'createTime',
      'create_time',
      'createdAt',
      'created_at',
      'senderId',
      'sender_id',
      'senderUserId',
      'sender_user_id',
      'msgType',
      'msg_type',
      'mediaId',
      'media_id',
      'fileId',
      'file_id',
    };
    if (!map.keys.any(messageFields.contains)) return false;
    final conversationId = _first(map, const <String>[
      'openConversationId',
      'open_conversation_id',
      'conversationId',
      'conversation_id',
      'chatId',
      'chat_id',
    ]);
    return conversationId.isNotEmpty || inheritedConversationId.isNotEmpty;
  }

  void _consumeEventLine(String line, int generation) {
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
    final event = _parseEvent(decoded);
    if (event != null && generation == _eventGeneration) {
      _eventController?.add(event);
    }
  }

  DingTalkGatewayEvent? _parseEvent(Object? raw) {
    if (raw is! Map) return null;
    final map = _eventEnvelopeMap(raw);
    final eventKey = _eventKey(map);
    final eventType = eventKey.isNotEmpty
        ? _eventTypeFromKey(eventKey)
        : _eventTypeFromPayload(map);
    final conversationId = _eventString(map, const <String>[
      'conversation_id',
      'conversationId',
      'openConversationId',
      'open_conversation_id',
      'open_conv_id',
      'openConvId',
      'chat_id',
      'chatId',
    ]);
    final chatType = _eventString(map, const <String>[
      'chat_type',
      'chatType',
      'conversation_type',
      'conversationType',
    ]).toLowerCase();
    var messageId = normalizeDingTalkMessageId(
      _eventString(map, const <String>[
        'message_id',
        'messageId',
        'openMessageId',
        'open_message_id',
        'openMsgId',
        'open_msg_id',
        'msg_id',
        'msgId',
      ]),
    );
    if (messageId.isEmpty && eventType == DingTalkGatewayEventType.message) {
      messageId = normalizeDingTalkMessageId(
        _eventString(map, const <String>['event_id', 'eventId']),
      );
    }
    // 撤回、已读事件有些版本只带消息 ID；控制器可按消息 ID在本地定位会话。
    if (messageId.isEmpty) return null;
    final conversationType =
        chatType.contains('group') ||
            chatType == '2' ||
            eventKey.contains('group') ||
            eventKey.contains('receive_at') ||
            _asBool(map['is_group']) ||
            _asBool(map['isGroup'])
        ? DingTalkConversationType.group
        : DingTalkConversationType.direct;
    if (eventType == DingTalkGatewayEventType.message &&
        conversationId.isEmpty) {
      return null;
    }
    if (eventType != DingTalkGatewayEventType.message) {
      if (eventType == DingTalkGatewayEventType.reaction) {
        final reaction = _eventReaction(map);
        if (reaction.isEmpty) return null;
        final action = _eventString(map, const <String>[
          'action',
          'operation',
          'operation_type',
          'operationType',
          'reaction_action',
          'reactionAction',
          'reaction_status',
          'reactionStatus',
          'status',
        ]).toLowerCase();
        return DingTalkGatewayEvent(
          type: eventType,
          messageId: messageId,
          conversationId: conversationId,
          conversationType: conversationType,
          reaction: reaction,
          reactionRemoved:
              _asBool(map['removed']) ||
              _asBool(map['is_removed']) ||
              action.contains('remove') ||
              action.contains('delete') ||
              action.contains('cancel') ||
              action.contains('revoke') ||
              action.contains('撤回'),
        );
      }
      return DingTalkGatewayEvent(
        type: eventType,
        messageId: messageId,
        conversationId: conversationId,
        conversationType: conversationType,
      );
    }
    final content = _content(map);
    final automaticReplyCard = _automaticReplyCard(map);
    final typedContent = automaticReplyCard == null
        ? content
        : automaticReplyCard.plainText.isNotEmpty
        ? automaticReplyCard.plainText
        : automaticReplyCard.title;
    final media = _extractMedia(map)
        .map(
          (item) => item.copyWith(
            messageId: item.messageId.trim().isEmpty
                ? messageId
                : item.messageId,
            conversationId: item.conversationId.trim().isEmpty
                ? conversationId
                : item.conversationId,
          ),
        )
        .toList(growable: false);
    final createdAt = _eventDateTime(map);
    final forwarded = _parseForwardedMessages(
      map,
      fallbackConversationId: conversationId,
      fallbackCreatedAt: createdAt,
    );
    final quotedMessage = _parseQuotedMessage(
      map,
      fallbackConversationId: conversationId,
      fallbackCreatedAt: createdAt,
    );
    final displayContent = media.isEmpty
        ? typedContent
        : _mediaDisplayContent(typedContent, media);
    if (content.isEmpty &&
        automaticReplyCard == null &&
        media.isEmpty &&
        quotedMessage == null &&
        forwarded.messages.isEmpty) {
      return DingTalkGatewayEvent(
        type: DingTalkGatewayEventType.message,
        messageId: messageId,
        conversationId: conversationId,
        conversationType: conversationType,
      );
    }
    final mentionedCurrentUser =
        _eventString(map, const <String>[
          'event_key',
          'eventKey',
          'event_type',
          'eventType',
          'rule_type',
          'ruleType',
          'type',
        ]).toLowerCase().contains('receive_at') ||
        _eventString(map, const <String>[
              'rule_type',
              'ruleType',
            ]).trim().toLowerCase() ==
            'at' ||
        _asBool(map['mentionedCurrentUser']) ||
        _asBool(map['mentioned_current_user']) ||
        _asBool(map['isAtMe']) ||
        _asBool(map['is_at_me']) ||
        _asBool(map['atMe']) ||
        _asBool(map['at_me']) ||
        _asBool(map['isInAtList']) ||
        _asBool(map['is_in_at_list']);
    final message = DingTalkGatewayMessage(
      id: messageId,
      conversationId: conversationId,
      conversationType: conversationType,
      role: DingTalkGatewayMessageRole.user,
      content: displayContent.isEmpty
          ? forwarded.messages.isNotEmpty
                ? '转发的聊天记录'
                : _mediaSummary(media)
          : displayContent,
      createdAt: createdAt,
      senderName: _eventString(map, const <String>[
        'sender_name',
        'senderName',
        'sender_nick',
        'senderNick',
        'sender',
        'nick',
        'name',
      ]),
      senderId: _eventSenderId(map),
      senderOpenDingTalkId: _eventSenderOpenDingTalkId(map),
      conversationTitle: _eventString(map, const <String>[
        'conversation_title',
        'conversationTitle',
        'group_name',
        'groupName',
        'title',
      ]),
      messageType: automaticReplyCard == null
          ? DingTalkGatewayMessageType.text
          : DingTalkGatewayMessageType.automaticReply,
      automaticReplyCard: automaticReplyCard,
      media: media,
      quotedMessage: quotedMessage,
      forwardedMessages: forwarded.messages,
      forwardedMessageCount: forwarded.totalCount,
      fromSelf:
          _asBool(map['isSelf']) ||
          _asBool(map['is_self']) ||
          _asBool(map['isMine']) ||
          _asBool(map['is_mine']) ||
          _asBool(map['isSelfLoop']) ||
          _asBool(map['is_self_loop']),
      mentionedCurrentUser: mentionedCurrentUser,
    );
    return DingTalkGatewayEvent(
      type: DingTalkGatewayEventType.message,
      messageId: messageId,
      conversationId: conversationId,
      conversationType: conversationType,
      message: message,
    );
  }

  Map<String, Object?> _eventEnvelopeMap(Map raw) {
    final root = _asMap(raw);
    final result = Map<String, Object?>.from(root);

    void merge(Object? value, int depth) {
      if (depth > 3 || value == null) return;
      final Object? current;
      if (value is String) {
        final text = value.trim();
        if (!text.startsWith('{')) return;
        current = _decodeJson(text);
      } else {
        current = value;
      }
      if (current is! Map) return;
      final map = _asMap(current);
      for (final entry in map.entries) {
        result.putIfAbsent(entry.key, () => entry.value);
      }
      for (final key in const <String>['data', 'payload', 'event', 'message']) {
        merge(map[key], depth + 1);
      }
    }

    for (final key in const <String>['data', 'payload', 'event', 'message']) {
      merge(root[key], 1);
    }
    return result;
  }

  String _eventKey(Map<String, Object?> map, {int depth = 0}) {
    const keys = <String>[
      'event_key',
      'eventKey',
      'event_type',
      'eventType',
      'event_name',
      'eventName',
      'type',
      'event',
    ];
    for (final key in keys) {
      final value = map[key];
      if (value is Map || value is List) continue;
      final text = '$value'.trim();
      if (text.startsWith('user_im_')) return text.toLowerCase();
    }
    if (depth >= 4) return '';
    for (final key in const <String>['data', 'payload', 'event', 'message']) {
      final value = map[key];
      if (value is Map) {
        final nested = _eventKey(_asMap(value), depth: depth + 1);
        if (nested.isNotEmpty) return nested;
      } else if (value is String) {
        final decoded = _decodeJson(value);
        if (decoded is Map) {
          final nested = _eventKey(_asMap(decoded), depth: depth + 1);
          if (nested.isNotEmpty) return nested;
        }
      }
    }
    return '';
  }

  DingTalkGatewayEventType _eventTypeFromKey(String key) {
    if (key.contains('reaction')) return DingTalkGatewayEventType.reaction;
    if (key.contains('recall')) return DingTalkGatewayEventType.recall;
    if (key.contains('read')) return DingTalkGatewayEventType.read;
    return DingTalkGatewayEventType.message;
  }

  DingTalkGatewayEventType _eventTypeFromPayload(Map<String, Object?> map) {
    if (_messageRecalled(map)) return DingTalkGatewayEventType.recall;
    final reaction = _eventReaction(map);
    if (reaction.isNotEmpty ||
        _eventString(map, const <String>[
          'operation_type',
          'operationType',
          'reaction_name',
          'reactionName',
        ]).isNotEmpty) {
      return DingTalkGatewayEventType.reaction;
    }
    if (_eventString(map, const <String>[
      'reader',
      'reader_open_dingtalk_id',
      'readerOpenDingTalkId',
      'read_time',
      'readTime',
    ]).isNotEmpty) {
      return DingTalkGatewayEventType.read;
    }
    return DingTalkGatewayEventType.message;
  }

  String _eventReaction(Map<String, Object?> map, {int depth = 0}) {
    for (final key in const <String>[
      'emoji',
      'emoji_code',
      'emojiCode',
      'reaction',
      'reaction_text',
      'reactionText',
      'reaction_name',
      'reactionName',
      'reaction_type',
      'reactionType',
      'reaction_content',
      'reactionContent',
    ]) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return normalizeDingTalkReaction(value);
      }
      if (value is Map) {
        final nested = _eventReaction(_asMap(value), depth: depth + 1);
        if (nested.isNotEmpty) return nested;
      }
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final nested = _eventReaction(_asMap(item), depth: depth + 1);
            if (nested.isNotEmpty) return nested;
          } else if (item is String && item.trim().isNotEmpty) {
            return normalizeDingTalkReaction(item);
          }
        }
      }
    }
    if (depth >= 3) return '';
    for (final value in map.values) {
      if (value is Map) {
        final nested = _eventReaction(_asMap(value), depth: depth + 1);
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  bool _messageRecalled(Map<String, Object?> map, {int depth = 0}) {
    for (final key in const <String>[
      'recalled',
      'isRecalled',
      'is_recalled',
      'recall',
      'isRecall',
      'is_recall',
      'withdrawn',
      'isWithdrawn',
      'is_withdrawn',
    ]) {
      if (_asBool(map[key])) return true;
    }
    final status = _first(map, const <String>[
      'messageStatus',
      'message_status',
      'status',
    ]).toLowerCase();
    if (status.contains('recall') ||
        status.contains('withdraw') ||
        status.contains('revoke') ||
        status.contains('撤回')) {
      return true;
    }
    if (depth >= 2) return false;
    for (final key in const <String>['data', 'payload', 'message']) {
      final value = map[key];
      if (value is Map && _messageRecalled(_asMap(value), depth: depth + 1)) {
        return true;
      }
    }
    return false;
  }

  String _eventString(
    Map<String, Object?> map,
    List<String> keys, {
    int depth = 0,
  }) {
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
    if (depth >= 3) return '';
    for (final value in map.values) {
      if (value is! Map) continue;
      final nested = _eventString(_asMap(value), keys, depth: depth + 1);
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _eventSenderId(Map<String, Object?> map) {
    const identifierKeys = <String>[
      'sender_staff_id',
      'senderStaffId',
      'sender_user_id',
      'senderUserId',
      'senderId',
      'sender_id',
      'staffId',
      'staff_id',
      'sender_open_dingtalk_id',
      'senderOpenDingTalkId',
      'senderOpenId',
      'sender_open_id',
    ];
    const nestedIdentifierKeys = <String>[
      ...identifierKeys,
      'userId',
      'user_id',
      'openDingTalkId',
      'open_dingtalk_id',
      'id',
    ];

    String read(Object? value) {
      if (value == null || value is List) return '';
      if (value is Map) {
        final nested = _asMap(value);
        for (final key in nestedIdentifierKeys) {
          final result = read(nested[key]);
          if (result.isNotEmpty) return result;
        }
        for (final key in const <String>[
          'sender',
          'senderInfo',
          'sender_info',
          'user',
          'from',
        ]) {
          final result = read(nested[key]);
          if (result.isNotEmpty) return result;
        }
        return '';
      }
      final text = '$value'.trim();
      return text.isEmpty || text == 'null' ? '' : text;
    }

    for (final key in identifierKeys) {
      final result = read(map[key]);
      if (result.isNotEmpty) return result;
    }
    return read(map['sender']);
  }

  String _eventSenderOpenDingTalkId(Map<String, Object?> map) {
    const keys = <String>[
      'sender_open_dingtalk_id',
      'senderOpenDingTalkId',
      'senderOpenId',
      'sender_open_id',
      'openDingTalkId',
      'open_dingtalk_id',
    ];

    String read(Map<String, Object?> source) {
      for (final key in keys) {
        final value = source[key];
        if (value == null || value is Map || value is List) continue;
        final text = '$value'.trim();
        if (text.isNotEmpty && text != 'null') return text;
      }
      return '';
    }

    final direct = read(map);
    if (direct.isNotEmpty) return direct;
    for (final key in const <String>[
      'sender',
      'senderInfo',
      'sender_info',
      'user',
      'from',
    ]) {
      final value = map[key];
      if (value is! Map) continue;
      final nested = read(_asMap(value));
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  DateTime _eventDateTime(Map<String, Object?> map) => _parseDateTime(
    map['create_time'] ??
        map['createTime'] ??
        map['created_at'] ??
        map['createdAt'] ??
        map['createAt'] ??
        map['create_at'] ??
        map['message_create_time'] ??
        map['messageCreateTime'] ??
        map['message_create_at'] ??
        map['messageCreateAt'] ??
        map['msg_create_time'] ??
        map['msgCreateTime'] ??
        map['msg_create_at'] ??
        map['msgCreateAt'] ??
        map['send_time'] ??
        map['sendTime'] ??
        map['msg_time'] ??
        map['msgTime'] ??
        map['event_time'] ??
        map['eventTime'] ??
        map['event_born_time'] ??
        map['eventBornTime'] ??
        map['received_at_unix_ms'] ??
        map['receivedAtUnixMs'] ??
        map['timestamp'],
    // 实时事件缺少业务时间时按接收时刻处理，避免被启动时间过滤误丢。
    fallback: DateTime.now(),
  );

  DateTime _parseDateTime(Object? value, {DateTime? fallback}) {
    return dateTimeFromValue(
          value,
          numericTimestampMode:
              DateTimeNumericTimestampMode.secondsOrMilliseconds,
          parseNumericText: true,
        )?.toLocal() ??
        fallback ??
        DateTime.now();
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

  String _content(Map<String, Object?> map, {int depth = 0}) {
    const primaryContentKeys = <String>[
      'content',
      'text',
      'msgContent',
      'msg_content',
      'messageContent',
      'richText',
      'rich_text',
      'markdown',
    ];
    const structuredContentKeys = <String>[
      ...primaryContentKeys,
      'title',
      'summary',
      'description',
    ];

    String merge(Iterable<String> values) {
      final result = <String>[];
      final seen = <String>{};
      for (final value in values) {
        final normalized = value.trim();
        if (normalized.isEmpty) {
          continue;
        }
        final comparison = normalizeDingTalkMessageContentForComparison(
          normalized,
        );
        if (comparison.isEmpty || !seen.add(comparison)) continue;
        result.add(normalized);
      }
      return result.join('\n');
    }

    String read(Object? value, int currentDepth) {
      if (value == null || currentDepth > 5) return '';
      if (value is String) {
        final raw = value.trim();
        if (raw.isEmpty) return '';
        final normalized = normalizeDingTalkMessageContent(raw);
        if (!(raw.startsWith('{') || raw.startsWith('['))) {
          return normalized;
        }
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map || decoded is List) {
            return read(decoded, currentDepth + 1);
          }
        } on FormatException {
          // 非 JSON 的方括号文本继续按普通消息处理。
        }
        return normalized;
      }
      if (value is List) {
        return merge(value.map((item) => read(item, currentDepth + 1)));
      }
      if (value is Map) {
        final nested = _asMap(value);
        return merge(
          structuredContentKeys.map(
            (key) => read(nested[key], currentDepth + 1),
          ),
        );
      }
      return '';
    }

    // 顶层 title/summary/description 通常属于会话或卡片元数据，不能混入消息正文；
    // 只有进入 content/text 对应的结构化对象后，才读取这些正文属性。
    return merge(primaryContentKeys.map((key) => read(map[key], depth + 1)));
  }

  DingTalkAutomaticReplyCard? _automaticReplyCard(Map<String, Object?> map) {
    const contentKeys = <String>[
      'content',
      'text',
      'msgContent',
      'msg_content',
      'messageContent',
      'richText',
      'rich_text',
      'markdown',
    ];
    final nativeType = _first(map, const <String>[
      'messageType',
      'message_type',
      'msgType',
      'msgtype',
      'msg_type',
    ]);
    for (final key in contentKeys) {
      final card = parseDingTalkAutomaticReplyCard(
        map[key],
        nativeType: nativeType,
      );
      if (card != null) return card;
    }
    return null;
  }

  List<DingTalkGatewayMedia> _extractMedia(
    Map<String, Object?> map, {
    bool includeResourceRefs = false,
  }) {
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
      String messageId = '',
      String conversationId = '',
      DingTalkMediaKind? inheritedKind,
    }) {
      final normalizedId = normalizeDingTalkResourceId(resourceId);
      if (normalizedId.isEmpty || result.length >= 12) return;
      final key = '${resourceType.name}:$normalizedId';
      if (!seen.add(key)) return;
      final rawName = _mediaText(name);
      final mime = _mediaText(mimeType);
      var kind = _mediaKindHint(type) ?? inheritedKind;
      kind ??= DingTalkMediaKindX.fromStorage(type);
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
          sizeBytes: int.tryParse(_mediaText(size)) ?? 0,
          durationMs: int.tryParse(_mediaText(duration)),
          messageId: messageId.trim(),
          conversationId: conversationId.trim(),
        ),
      );
    }

    void visit(
      Object? value, {
      int depth = 0,
      String inheritedMessageId = '',
      String inheritedConversationId = '',
      DingTalkMediaKind? inheritedKind,
    }) {
      if (depth > 6 || result.length >= 12 || value == null) return;
      if (value is String) {
        final raw = value.trim();
        final fileProjection = parseDingTalkDwsFileProjection(raw);
        if (fileProjection != null) {
          addCandidate(
            resourceId: fileProjection.resourceId,
            resourceType: DingTalkMediaResourceType.fileId,
            type: DingTalkMediaKind.file,
            name: fileProjection.name,
            mimeType: null,
            size: null,
            duration: null,
            messageId: inheritedMessageId,
            conversationId: inheritedConversationId,
          );
          return;
        }
        if (raw.startsWith('{') || raw.startsWith('[')) {
          final decoded = _decodeJson(raw);
          if (decoded is Map || decoded is List) {
            visit(
              decoded,
              depth: depth + 1,
              inheritedMessageId: inheritedMessageId,
              inheritedConversationId: inheritedConversationId,
              inheritedKind: inheritedKind,
            );
          }
        }
        final match = RegExp(
          r'''(?:media[_-]?id|file[_-]?id)\s*["'=:]\s*["']?([^,"'\s}\)\]]+)''',
          caseSensitive: false,
        ).firstMatch(raw);
        if (match != null) {
          final isFile =
              raw.toLowerCase().contains('fileid') ||
              raw.toLowerCase().contains('file_id');
          final resourceType = isFile
              ? DingTalkMediaResourceType.fileId
              : DingTalkMediaResourceType.mediaId;
          final resourceId = match.group(1) ?? '';
          if (isDingTalkResourceIdInUrlQuery(
            raw,
            resourceId,
            resourceType: resourceType,
          )) {
            return;
          }
          final prefix = raw.substring(0, match.start).trimRight();
          final isMediaProjection =
              prefix.isEmpty ||
              prefix.endsWith('(') ||
              prefix.endsWith('[') ||
              prefix.endsWith('{') ||
              prefix.endsWith(',') ||
              prefix.endsWith(':');
          if (!isMediaProjection) return;
          addCandidate(
            resourceId: resourceId,
            resourceType: resourceType,
            type: _mediaKindHint(raw),
            name: null,
            mimeType: null,
            size: null,
            duration: null,
            messageId: inheritedMessageId,
            conversationId: inheritedConversationId,
            inheritedKind: inheritedKind,
          );
        }
        return;
      }
      if (value is List) {
        for (final item in value) {
          visit(
            item,
            depth: depth + 1,
            inheritedMessageId: inheritedMessageId,
            inheritedConversationId: inheritedConversationId,
            inheritedKind: inheritedKind,
          );
          if (result.length >= 12) break;
        }
        return;
      }
      if (value is! Map) return;
      final current = _asMap(value);
      final currentMessageId = _first(current, const <String>[
        'messageId',
        'message_id',
        'openMessageId',
        'open_message_id',
      ]);
      final currentConversationId = _first(current, const <String>[
        'conversationId',
        'conversation_id',
        'openConversationId',
        'open_conversation_id',
      ]);
      final messageContext = currentMessageId.isEmpty
          ? inheritedMessageId
          : currentMessageId;
      final conversationContext = currentConversationId.isEmpty
          ? inheritedConversationId
          : currentConversationId;
      final currentKind =
          _mediaKindHint(
            _first(current, const <String>[
              'messageType',
              'msgType',
              'msgtype',
              'msg_type',
              'mediaType',
              'media_type',
              'type',
              'kind',
            ]),
          ) ??
          inheritedKind;
      final mediaId = _first(current, const <String>[
        'mediaId',
        'media_id',
        'downloadCode',
        'download_code',
      ]);
      final fileId = _first(current, const <String>['fileId', 'file_id']);
      final resourceId = includeResourceRefs
          ? _first(current, const <String>['resourceId', 'resource_id'])
          : '';
      if (mediaId.isNotEmpty || fileId.isNotEmpty || resourceId.isNotEmpty) {
        final resourceType = _first(current, const <String>[
          'resourceType',
          'resource_type',
          'type',
        ]).toLowerCase();
        addCandidate(
          resourceId: mediaId.isNotEmpty
              ? mediaId
              : fileId.isNotEmpty
              ? fileId
              : resourceId,
          resourceType: fileId.isNotEmpty || resourceType.contains('fileid')
              ? DingTalkMediaResourceType.fileId
              : DingTalkMediaResourceType.mediaId,
          type: _first(current, const <String>[
            'messageType',
            'msgType',
            'msgtype',
            'msg_type',
            'mediaType',
            'media_type',
            'type',
            'kind',
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
          messageId: messageContext,
          conversationId: conversationContext,
          inheritedKind: currentKind,
        );
      }
      for (final key in <String>[
        'content',
        'text',
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
        'forward_messages',
        'forwardMessages',
        if (includeResourceRefs) 'resourceRefs',
        if (includeResourceRefs) 'resource_refs',
      ]) {
        final childKind = _mediaKindHint(key) ?? currentKind;
        visit(
          current[key],
          depth: depth + 1,
          inheritedMessageId: messageContext,
          inheritedConversationId: conversationContext,
          inheritedKind: childKind,
        );
      }
    }

    // 资源字段既可能位于 content 内，也可能直接位于事件顶层；统一从根节点扫描，
    // 同时通过 seen 去重，避免同一媒体被重复附加。
    visit(map);
    return result;
  }

  String _mediaText(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  DingTalkMediaKind? _mediaKindHint(Object? value) {
    final normalized = _mediaText(value).toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized.contains('image') ||
        normalized.contains('photo') ||
        normalized.contains('picture') ||
        normalized.contains('图片') ||
        normalized.contains('照片') ||
        normalized.contains('图像')) {
      return DingTalkMediaKind.image;
    }
    if (normalized.contains('video') || normalized.contains('视频')) {
      return DingTalkMediaKind.video;
    }
    if (normalized.contains('audio') ||
        normalized.contains('voice') ||
        normalized.contains('语音') ||
        normalized.contains('音频')) {
      return DingTalkMediaKind.audio;
    }
    if (normalized.contains('file') ||
        normalized.contains('document') ||
        normalized.contains('attachment') ||
        normalized.contains('文件') ||
        normalized.contains('附件')) {
      return DingTalkMediaKind.file;
    }
    return null;
  }

  String _mediaSummary(List<DingTalkGatewayMedia> media) {
    if (media.isEmpty) return '媒体消息';
    return media.map((item) => '[${item.displayName}]').join(' ');
  }

  String _mediaDisplayContent(
    String content,
    List<DingTalkGatewayMedia> media,
  ) {
    final text = normalizeDingTalkMediaText(content, media);
    return text.isEmpty ? _mediaSummary(media) : text;
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

  bool _isMessageQueryCommand(Iterable<String> arguments) {
    final values = arguments.toList(growable: false);
    return values.length >= 3 &&
        values[0] == 'chat' &&
        values[1] == 'message' &&
        (values[2] == 'list' ||
            values[2] == 'list-all' ||
            values[2] == 'list-mentions');
  }

  Map<String, Object?> _asMap(Object? value) => value is Map
      ? value.map((key, value) => MapEntry('$key', value))
      : <String, Object?>{};
  bool _asBool(Object? value) {
    if (value == true || value == 1) return true;
    final normalized = '$value'.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../app/state/settings_controller.dart'
    show aiStreamThrottleConfigSchemaVersion, migrateAiStreamThrottleConfig;
import '../../../app/support/silent_log.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/net/http_error_message.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

final class _ThrottleHttpResponse {
  const _ThrottleHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// 节流配置云端同步 provider 类型。
///
/// 支持自定义 HTTP、iCloud 原生桥接和 GitHub Gist。
enum ThrottleCloudSyncProvider {
  custom,
  iCloud,
  gistGitHub;

  String get storageValue => switch (this) {
    ThrottleCloudSyncProvider.custom => 'custom',
    ThrottleCloudSyncProvider.iCloud => 'icloud',
    ThrottleCloudSyncProvider.gistGitHub => 'gist_github',
  };

  static ThrottleCloudSyncProvider fromStorage(String value) {
    switch ((nullIfBlank(value) ?? '').toLowerCase()) {
      case 'icloud':
        return ThrottleCloudSyncProvider.iCloud;
      case 'gist_github':
      case 'gist':
      case 'github_gist':
        return ThrottleCloudSyncProvider.gistGitHub;
      case 'custom':
      default:
        return ThrottleCloudSyncProvider.custom;
    }
  }
}

/// 同步操作结果。`ok=false` 时 `message` 给可读错误信息。
///
/// 增补 `updatedAtMs` 字段：拉取成功且远端 payload 内含
/// `updated_at_ms` 时透传给上层，自动同步以此判定是否覆盖本地。
class ThrottleCloudSyncResult {
  const ThrottleCloudSyncResult._({
    required this.ok,
    this.message = '',
    this.config,
    this.fetchedAt,
    this.updatedAtMs = 0,
    this.createdGistId = '',
  });

  factory ThrottleCloudSyncResult.success({
    String message = '',
    Map<String, Object?>? config,
    DateTime? fetchedAt,
    int updatedAtMs = 0,
    String createdGistId = '',
  }) {
    return ThrottleCloudSyncResult._(
      ok: true,
      message: message,
      config: config,
      fetchedAt: fetchedAt,
      updatedAtMs: updatedAtMs,
      createdGistId: createdGistId,
    );
  }

  factory ThrottleCloudSyncResult.failure(String message) {
    return ThrottleCloudSyncResult._(ok: false, message: message);
  }

  final bool ok;
  final String message;
  final Map<String, Object?>? config;
  final DateTime? fetchedAt;

  /// 远端最近一次 push 的本地 epoch ms。0 表示未携带或解析失败。
  final int updatedAtMs;

  /// 首次推送新建的 Gist ID；更新已有 Gist 或其他同步方式时为空。
  final String createdGistId;
}

/// 节流配置云端同步 service。
///
/// 服务不感知 SettingsController 的存在；调用方负责
/// 序列化要推送的 config，并把拉取到的 Map 传给
/// `SettingsController.importAiStreamThrottleConfig`。这样服务
/// 只处理“网络 IO + JSON 编解码”，方便被脚本工具复用。
///
/// [cloudChanges] 在 native 端收到
/// `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`（即用户
/// 在另一台设备改了节流配置，iCloud 推送过来）时主动调
/// `cloudConfigChanged` 方法，服务转换为 Stream 事件让上层
/// 自动同步服务感知并触发一次拉取。
class ThrottleCloudSyncService {
  ThrottleCloudSyncService({
    http.Client? client,
    http.Client Function()? clientFactory,
    this._registerCloudChangeHandler = true,
  }) : _client = client,
       _clientFactory = clientFactory ?? http.Client.new {
    requireAtMostOneProvided(
      firstValue: client,
      firstName: 'client',
      secondValue: clientFactory,
      secondName: 'clientFactory',
    );
    if (_registerCloudChangeHandler) {
      _icloudChannel.setMethodCallHandler(_handleNativeCall);
    }
  }

  final http.Client? _client;
  final http.Client Function() _clientFactory;
  final bool _registerCloudChangeHandler;
  final OpenHandAsyncSemaphore _requestSlots = OpenHandAsyncSemaphore(
    _maxConcurrentRequests,
    maxWaiters: _maxQueuedRequests,
  );
  final Set<http.Client> _activeOwnedClients = <http.Client>{};
  final Set<Completer<void>> _activeRequestAborts = <Completer<void>>{};
  final OpenHandAsyncOnce _disposeOnce = OpenHandAsyncOnce();
  bool _disposed = false;

  final StreamController<void> _cloudChangesController =
      StreamController<void>.broadcast();

  /// 远端配置发生变更时的广播流（无 payload）。订阅方收到事件后
  /// 应主动调 [pull] 拉取最新配置；为防抖动，事件可能在短时间内
  /// 多次发出，订阅方需自行 debounce / dedup。
  Stream<void> get cloudChanges => _cloudChangesController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (_disposed) return null;
    switch (call.method) {
      case 'cloudConfigChanged':
        if (!_cloudChangesController.isClosed) {
          _cloudChangesController.add(null);
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> dispose() => _disposeOnce.run(_dispose);

  Future<void> _dispose() async {
    _disposed = true;
    _requestSlots.cancelWaiters();
    for (final abort in _activeRequestAborts.toList(growable: false)) {
      if (!abort.isCompleted) abort.complete();
    }
    _activeRequestAborts.clear();
    for (final client in _activeOwnedClients.toList(growable: false)) {
      client.close();
    }
    _activeOwnedClients.clear();
    if (_registerCloudChangeHandler) {
      _icloudChannel.setMethodCallHandler(null);
    }
    if (!_cloudChangesController.isClosed) {
      await runAsyncCleanupBounded(
        _cloudChangesController.close,
        onError: (error, stack) =>
            silentLog('throttle_cloud_sync', '关闭云端变更流', error, stack),
      );
    }
  }

  /// 与 macOS / iOS native 端 CloudSyncBridge 共用的 method channel。
  static const MethodChannel _icloudChannel = MethodChannel(
    'openhand/cloud_sync',
  );

  /// 所有云端 HTTP 请求的统一超时阈值。15s 兼顾跨国 Gist / S3 链路上
  /// 偶发的 TCP RTT 抖动，又能在用户网络明显异常时尽快回到 UI 兜底
  /// 提示，避免长时间无反馈。
  static const Duration _remoteRequestTimeout = Duration(seconds: 15);
  static const int _maxConcurrentRequests = 4;
  static const int _maxQueuedRequests = 32;
  static const Duration _responseIdleTimeout = Duration(seconds: 5);
  static const int _maxRequestBytes = kBytesPerMiB;
  static const int _maxResponseBytes = 2 * kBytesPerMiB;
  static const int _httpErrorPreviewLength = 256;
  static const String _payloadKind = 'openhand.throttle_config';
  static const String _gistFileName = 'openhand_throttle.json';
  static const String _gistApiHost = 'api.github.com';
  static const String _githubApiVersion = '2022-11-28';
  static const String _githubUserAgent = 'OpenHand-throttle-sync/1';
  static const String _customClientHeader = 'throttle-sync/1';
  static const String _disposedMessage = '云同步服务已释放。';
  static const Set<String> _configFieldKeys = <String>{
    'throttle_enabled',
    'auto_mode',
    'duration_seconds',
    'max_chars_per_second',
    'max_message_cards_per_second',
  };

  /// 把 [config] 推送到云端。`provider == iCloud` 时走 native 端的
  /// NSUbiquitousKeyValueStore。
  ///
  /// [updatedAtMs] 由调用方传入本地最近一次配置修改的 epoch ms，会写
  /// 入 payload 顶层 `updated_at_ms` 字段供后续 pull 解析比较。
  Future<ThrottleCloudSyncResult> push({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
    required Map<String, Object?> config,
    int updatedAtMs = 0,
    String gistId = '',
  }) async {
    if (_disposed) return ThrottleCloudSyncResult.failure(_disposedMessage);
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pushIcloud(config, updatedAtMs);
      case ThrottleCloudSyncProvider.gistGitHub:
        return _pushGist(
          gistId: gistId,
          token: token,
          config: config,
          updatedAtMs: updatedAtMs,
        );
      case ThrottleCloudSyncProvider.custom:
        break;
    }
    final target = _resolveCustomHttpTarget(endpoint, token);
    if (target.error != null) {
      return ThrottleCloudSyncResult.failure(target.error!);
    }
    return _runHttpRequest('推送自定义端点配置', (client, cancelSignal) async {
      final body = jsonEncode(_configPayload(config, updatedAtMs));
      final bodyBytes = utf8.encode(body);
      final resp = await _sendHttpRequest(
        client,
        method: 'PUT',
        uri: target.uri!,
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
          if (target.bearerToken != null)
            HttpHeaders.authorizationHeader: 'Bearer ${target.bearerToken}',
          'X-OpenHand-Client': _customClientHeader,
        },
        bodyBytes: bodyBytes,
        cancelSignal: cancelSignal,
      );
      if (isHttpFailureStatus(resp.statusCode)) {
        return _httpFailure(resp, '自定义端点');
      }
      return ThrottleCloudSyncResult.success(
        message: '已推送 ${bodyBytes.length} 字节。',
      );
    });
  }

  /// 从云端拉取 [config]。返回 [ThrottleCloudSyncResult.config]。
  Future<ThrottleCloudSyncResult> pull({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
    String gistId = '',
  }) async {
    if (_disposed) return ThrottleCloudSyncResult.failure(_disposedMessage);
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pullIcloud();
      case ThrottleCloudSyncProvider.gistGitHub:
        return _pullGist(gistId: gistId, token: token);
      case ThrottleCloudSyncProvider.custom:
        break;
    }
    final target = _resolveCustomHttpTarget(endpoint, token);
    if (target.error != null) {
      return ThrottleCloudSyncResult.failure(target.error!);
    }
    return _runHttpRequest('拉取自定义端点配置', (client, cancelSignal) async {
      final resp = await _sendHttpRequest(
        client,
        method: 'GET',
        uri: target.uri!,
        headers: <String, String>{
          HttpHeaders.acceptHeader: kApplicationJsonMimeType,
          if (target.bearerToken != null)
            HttpHeaders.authorizationHeader: 'Bearer ${target.bearerToken}',
          'X-OpenHand-Client': _customClientHeader,
        },
        cancelSignal: cancelSignal,
      );
      if (isHttpFailureStatus(resp.statusCode)) {
        return _httpFailure(resp, '自定义端点');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return ThrottleCloudSyncResult.failure('云端响应不是 JSON 对象。');
      }
      final remote = _readRemoteConfig(decoded);
      return ThrottleCloudSyncResult.success(
        config: remote.config,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: remote.updatedAtMs,
        message: '已拉取云端配置。',
      );
    });
  }

  ({Uri? uri, String? bearerToken, String? error}) _resolveCustomHttpTarget(
    String endpoint,
    String token,
  ) {
    final url = nullIfBlank(endpoint);
    if (url == null) {
      return (uri: null, bearerToken: null, error: '请填写同步地址。');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.scheme != 'https' && uri.scheme != 'http') {
      return (uri: null, bearerToken: null, error: '同步地址必须是有效的 HTTP(S) 地址。');
    }
    return (uri: uri, bearerToken: nullIfBlank(token), error: null);
  }

  Future<ThrottleCloudSyncResult> _runHttpRequest(
    String logAction,
    Future<ThrottleCloudSyncResult> Function(
      http.Client client,
      Future<void> cancelSignal,
    )
    request,
  ) async {
    if (_disposed) return ThrottleCloudSyncResult.failure(_disposedMessage);
    late final bool acquired;
    try {
      acquired = await _requestSlots.acquireWithin(_remoteRequestTimeout);
    } on StateError {
      return ThrottleCloudSyncResult.failure('云同步请求排队已满，请稍后再试。');
    }
    if (!acquired) {
      return ThrottleCloudSyncResult.failure(
        _disposed ? _disposedMessage : '云同步请求排队超时。',
      );
    }
    if (_disposed) {
      _requestSlots.release();
      return ThrottleCloudSyncResult.failure(_disposedMessage);
    }
    try {
      return await _runAcquiredHttpRequest(logAction, request);
    } finally {
      _requestSlots.release();
    }
  }

  Future<ThrottleCloudSyncResult> _runAcquiredHttpRequest(
    String logAction,
    Future<ThrottleCloudSyncResult> Function(
      http.Client client,
      Future<void> cancelSignal,
    )
    request,
  ) async {
    final ownsClient = _client == null;
    late final http.Client client;
    try {
      client = _client ?? _clientFactory();
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', '创建云同步客户端', error, stack);
      return ThrottleCloudSyncResult.failure('无法创建云同步客户端。');
    }
    final requestAbort = Completer<void>();
    _activeRequestAborts.add(requestAbort);
    if (_disposed) {
      requestAbort.complete();
      _activeRequestAborts.remove(requestAbort);
      if (ownsClient) client.close();
      return ThrottleCloudSyncResult.failure(_disposedMessage);
    }
    if (ownsClient) _activeOwnedClients.add(client);
    try {
      final result = await request(
        client,
        requestAbort.future,
      ).timeout(_remoteRequestTimeout);
      return _disposed
          ? ThrottleCloudSyncResult.failure(_disposedMessage)
          : result;
    } on http.RequestAbortedException {
      return ThrottleCloudSyncResult.failure(
        _disposed ? _disposedMessage : '云同步请求已取消。',
      );
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure(
        '云同步请求超过 ${_remoteRequestTimeout.inSeconds} 秒。',
      );
    } on ByteStreamSizeLimitException catch (error) {
      return ThrottleCloudSyncResult.failure(error.message);
    } on FormatException catch (error) {
      return ThrottleCloudSyncResult.failure(
        '云端 JSON 无效：${clipTextWithEllipsis(error.message.toString(), _httpErrorPreviewLength)}',
      );
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', logAction, error, stack);
      return ThrottleCloudSyncResult.failure('云同步请求失败，请检查网络与同步配置。');
    } finally {
      if (!requestAbort.isCompleted) requestAbort.complete();
      _activeRequestAborts.remove(requestAbort);
      if (ownsClient && _activeOwnedClients.remove(client)) {
        client.close();
      }
    }
  }

  Future<_ThrottleHttpResponse> _sendHttpRequest(
    http.Client client, {
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Future<void> cancelSignal,
    List<int>? bodyBytes,
  }) async {
    if (bodyBytes != null && bodyBytes.length > _maxRequestBytes) {
      throw ByteStreamSizeLimitException(_maxRequestBytes);
    }
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (bodyBytes != null) request.bodyBytes = bodyBytes;
    final response = await sendAbortableHttpRequest(
      client: client,
      request: request,
      connectionTimeout: _remoteRequestTimeout,
      cancelSignal: cancelSignal,
    );
    final body = await readBoundedByteStreamText(
      response.stream,
      maxBytes: _maxResponseBytes,
      idleTimeout: _responseIdleTimeout,
      totalTimeout: _remoteRequestTimeout,
    );
    return _ThrottleHttpResponse(statusCode: response.statusCode, body: body);
  }

  Map<String, Object?> _configPayload(
    Map<String, Object?> config,
    int updatedAtMs,
  ) => <String, Object?>{
    'kind': _payloadKind,
    'version': aiStreamThrottleConfigSchemaVersion,
    'config': config,
    'updated_at_ms': updatedAtMs,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  ({Map<String, Object?> config, int updatedAtMs}) _readRemoteConfig(
    Map<dynamic, dynamic> payload,
  ) {
    final inner = payload['config'];
    if (inner != null && inner is! Map) {
      throw const FormatException('云端配置的 config 字段不是 JSON 对象。');
    }
    final kind = optionalStringFromValue(payload['kind']);
    if (kind != null && kind != _payloadKind) {
      throw FormatException('云端配置类型不受支持：$kind');
    }
    final config = stringKeyedMapFromValue(inner is Map ? inner : payload);
    _validateRemoteConfig(config);
    return (
      config: migrateAiStreamThrottleConfig(config),
      updatedAtMs: _readUpdatedAtMs(payload, config),
    );
  }

  static void _validateRemoteConfig(Map<String, Object?> config) {
    if (!_configFieldKeys.any(config.containsKey)) {
      throw const FormatException('云端配置缺少可识别的节流字段。');
    }
    for (final key in const <String>['throttle_enabled', 'auto_mode']) {
      if (config.containsKey(key) && config[key] is! bool) {
        throw FormatException('云端配置字段 $key 必须是布尔值。');
      }
    }
    for (final key in const <String>[
      'duration_seconds',
      'max_chars_per_second',
      'max_message_cards_per_second',
    ]) {
      if (config.containsKey(key) && config[key] is! int) {
        throw FormatException('云端配置字段 $key 必须是整数。');
      }
    }
  }

  ThrottleCloudSyncResult _httpFailure(
    _ThrottleHttpResponse response,
    String source,
  ) {
    final detail = extractApiErrorMessage(
      response.body,
      maxLength: _httpErrorPreviewLength,
      emptyFallback: '服务器未返回错误详情。',
    );
    return ThrottleCloudSyncResult.failure(
      '$source请求失败（HTTP ${response.statusCode}）：$detail',
    );
  }

  /// 兼容多层级位置：顶层 `updated_at_ms`、内层 `config.updated_at_ms`。
  static int _readUpdatedAtMs(Map outer, Map<String, Object?>? inner) {
    final outerVal = outer['updated_at_ms'];
    if (outerVal is num && outerVal.isFinite && outerVal > 0) {
      return outerVal.toInt();
    }
    if (inner != null) {
      final innerVal = inner['updated_at_ms'];
      if (innerVal is num && innerVal.isFinite && innerVal > 0) {
        return innerVal.toInt();
      }
    }
    return 0;
  }

  /// iCloud 桥接：调 native CloudSyncBridge。
  /// macOS / iOS 走 NSUbiquitousKeyValueStore（key-value，1MB 上限）；
  /// 其他平台没有实现，channel 抛 MissingPluginException → 转换为
  /// 友好错误信息。
  Future<ThrottleCloudSyncResult> _pushIcloud(
    Map<String, Object?> config,
    int updatedAtMs,
  ) async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return ThrottleCloudSyncResult.failure('iCloud 同步仅支持 macOS 和 iOS。');
    }
    try {
      final json = prettyPrintJson(_configPayload(config, updatedAtMs));
      final payloadBytes = utf8.encode(json).length;
      if (payloadBytes > _maxRequestBytes) {
        return ThrottleCloudSyncResult.failure(
          'iCloud 配置超过 $_maxRequestBytes 字节上限。',
        );
      }
      final result = await _icloudChannel
          .invokeMapMethod<String, dynamic>('pushIcloud', <String, dynamic>{
            'config_json': json,
          })
          .timeout(_remoteRequestTimeout);
      if (_disposed) {
        return ThrottleCloudSyncResult.failure(_disposedMessage);
      }
      final ok = result?['ok'] == true;
      final synced = result?['synchronized'] == true;
      if (!ok) {
        return ThrottleCloudSyncResult.failure(
          synced ? 'iCloud 拒绝了配置。' : 'iCloud 同步已延后，网络恢复后将重试。',
        );
      }
      return ThrottleCloudSyncResult.success(
        message: synced ? 'iCloud 已同步 $payloadBytes 字节。' : 'iCloud 同步已进入队列。',
      );
    } on MissingPluginException {
      return ThrottleCloudSyncResult.failure('当前平台未注册 iCloud 同步桥接。');
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure(
        'iCloud 同步超过 ${_remoteRequestTimeout.inSeconds} 秒。',
      );
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', '推送 iCloud 配置', error, stack);
      return ThrottleCloudSyncResult.failure('iCloud 推送失败。');
    }
  }

  Future<ThrottleCloudSyncResult> _pullIcloud() async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return ThrottleCloudSyncResult.failure('iCloud 同步仅支持 macOS 和 iOS。');
    }
    try {
      final result = await _icloudChannel
          .invokeMapMethod<String, dynamic>('pullIcloud')
          .timeout(_remoteRequestTimeout);
      if (_disposed) {
        return ThrottleCloudSyncResult.failure(_disposedMessage);
      }
      final ok = result?['ok'] == true;
      final raw = (result?['config_json'] as String?) ?? '';
      if (!ok || raw.isEmpty) {
        return ThrottleCloudSyncResult.failure('当前 iCloud 账户尚无节流配置。');
      }
      if (utf8.encode(raw).length > _maxResponseBytes) {
        return ThrottleCloudSyncResult.failure(
          'iCloud 配置超过 $_maxResponseBytes 字节上限。',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return ThrottleCloudSyncResult.failure('iCloud 配置不是 JSON 对象。');
      }
      final remote = _readRemoteConfig(decoded);
      return ThrottleCloudSyncResult.success(
        config: remote.config,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: remote.updatedAtMs,
        message: '已拉取 iCloud 配置。',
      );
    } on MissingPluginException {
      return ThrottleCloudSyncResult.failure('当前平台未注册 iCloud 同步桥接。');
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure(
        'iCloud 同步超过 ${_remoteRequestTimeout.inSeconds} 秒。',
      );
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', '拉取 iCloud 配置', error, stack);
      return ThrottleCloudSyncResult.failure('iCloud 拉取失败。');
    }
  }

  /// GitHub Gist 同步实现：
  ///   * 已配置 [gistId] → PATCH /gists/{id} 更新指定 gist 的
  ///     `openhand_throttle.json` 文件；
  ///   * [gistId] 为空 → POST /gists 新建一个 secret gist，并把
  ///     新分配的 id 通过 message 返回（调用方可以选择持久化）。
  /// 鉴权：personal access token 走 `Authorization: Bearer ...`，
  /// 仅 `gist` scope 即可。
  Future<ThrottleCloudSyncResult> _pushGist({
    required String gistId,
    required String token,
    required Map<String, Object?> config,
    required int updatedAtMs,
  }) async {
    final pat = nullIfBlank(token);
    if (pat == null) {
      return ThrottleCloudSyncResult.failure('请填写 GitHub PAT。');
    }
    return _runHttpRequest('推送 GitHub Gist 配置', (client, cancelSignal) async {
      final fileContent = prettyPrintJson(_configPayload(config, updatedAtMs));
      final body = jsonEncode(<String, Object?>{
        'description': 'OpenHand 节流配置（自动同步）',
        'public': false,
        'files': <String, Object?>{
          _gistFileName: <String, Object?>{'content': fileContent},
        },
      });
      final bodyBytes = utf8.encode(body);
      final headers = <String, String>{
        HttpHeaders.acceptHeader: kGitHubApiAcceptHeader,
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.authorizationHeader: 'Bearer $pat',
        'X-GitHub-Api-Version': _githubApiVersion,
        HttpHeaders.userAgentHeader: _githubUserAgent,
      };
      final id = nullIfBlank(gistId);
      final _ThrottleHttpResponse resp;
      if (id == null) {
        resp = await _sendHttpRequest(
          client,
          method: 'POST',
          uri: _gistApiUri(),
          headers: headers,
          bodyBytes: bodyBytes,
          cancelSignal: cancelSignal,
        );
      } else {
        resp = await _sendHttpRequest(
          client,
          method: 'PATCH',
          uri: _gistApiUri(id),
          headers: headers,
          bodyBytes: bodyBytes,
          cancelSignal: cancelSignal,
        );
      }
      if (isHttpFailureStatus(resp.statusCode)) {
        return _httpFailure(resp, 'GitHub Gist');
      }
      String createdId = '';
      if (id == null) {
        createdId =
            optionalStringFromValue(
              optionalStringKeyedMapFromJsonText(resp.body)?['id'],
            ) ??
            '';
        if (createdId.isEmpty) {
          return ThrottleCloudSyncResult.failure(
            'GitHub 未返回新建 Gist 的 ID，请在 GitHub 中确认结果。',
          );
        }
      }
      return ThrottleCloudSyncResult.success(
        message: id == null ? '已新建 Gist：$createdId' : '已更新 Gist：$id',
        createdGistId: createdId,
      );
    });
  }

  Future<ThrottleCloudSyncResult> _pullGist({
    required String gistId,
    required String token,
  }) async {
    final id = nullIfBlank(gistId);
    if (id == null) {
      return ThrottleCloudSyncResult.failure('请填写 Gist ID。');
    }
    final pat = nullIfBlank(token);
    if (pat == null) {
      return ThrottleCloudSyncResult.failure('请填写 GitHub PAT。');
    }
    return _runHttpRequest('拉取 GitHub Gist 配置', (client, cancelSignal) async {
      final resp = await _sendHttpRequest(
        client,
        method: 'GET',
        uri: _gistApiUri(id),
        headers: <String, String>{
          HttpHeaders.acceptHeader: kGitHubApiAcceptHeader,
          HttpHeaders.authorizationHeader: 'Bearer $pat',
          'X-GitHub-Api-Version': _githubApiVersion,
          HttpHeaders.userAgentHeader: _githubUserAgent,
        },
        cancelSignal: cancelSignal,
      );
      if (isHttpFailureStatus(resp.statusCode)) {
        return _httpFailure(resp, 'GitHub Gist');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return ThrottleCloudSyncResult.failure('GitHub Gist 响应不是 JSON 对象。');
      }
      final files = decoded['files'];
      if (files is! Map) {
        return ThrottleCloudSyncResult.failure('GitHub Gist 响应缺少 files 字段。');
      }
      final entry = files[_gistFileName];
      if (entry is! Map) {
        return ThrottleCloudSyncResult.failure(
          'GitHub Gist 中不存在 $_gistFileName。',
        );
      }
      final content = entry['content'];
      // GitHub 在文件 > 1MB 时会把内容截断并填 truncated=true，此处
      // 仅做安全提示，不再二次拉取（节流配置不会到 1MB）。
      if (entry['truncated'] == true) {
        return ThrottleCloudSyncResult.failure('GitHub Gist 文件已被截断，配置过大。');
      }
      if (content is! String) {
        return ThrottleCloudSyncResult.failure('GitHub Gist 文件内容不是字符串。');
      }
      final inner = jsonDecode(content);
      if (inner is! Map) {
        return ThrottleCloudSyncResult.failure('GitHub Gist 文件不是 JSON 对象。');
      }
      final remote = _readRemoteConfig(inner);
      return ThrottleCloudSyncResult.success(
        config: remote.config,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: remote.updatedAtMs,
        message: '已拉取 GitHub Gist 配置。',
      );
    });
  }

  Uri _gistApiUri([String? id]) {
    return Uri(
      scheme: 'https',
      host: _gistApiHost,
      pathSegments: <String>['gists', if (id != null) id],
    );
  }
}

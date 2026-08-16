import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/sse_line_parsing.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../model/ai_exposure_models.dart';

const Duration _kAiJunglerRequestTimeout = Duration(seconds: 15);
const Duration _kAiJunglerSseIdleTimeout = Duration(seconds: 45);
const int _kAiJunglerMaxRequestBytes = 2 * kBytesPerMiB;
const int _kAiJunglerMaxJsonResponseBytes = 8 * kBytesPerMiB;
const int _kAiJunglerMaxErrorResponseBytes = 64 * kBytesPerKiB;
const int _kAiJunglerMaxSseLineBytes = 256 * kBytesPerKiB;
const int _kAiJunglerDefaultHistoryLimit = 500;
const int _kAiJunglerDefaultLogLimit = 2000;
const int _kAiJunglerDefaultResultLimit = 1000;

class AiJunglerApiException implements Exception {
  const AiJunglerApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AiJunglerClient {
  AiJunglerClient({
    required this.baseUri,
    required this.accessToken,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = _kAiJunglerRequestTimeout;
  }

  final Uri baseUri;
  final String accessToken;
  final HttpClient _httpClient;

  Future<AiExposureHealth> health() async =>
      AiExposureHealth.fromJson(await _jsonRequest('GET', '/v1/health'));

  Future<String> createJob(AiExposureScanRequest request) async {
    final json = await _jsonRequest('POST', '/v1/jobs', body: request.toJson());
    final jobId = json['jobId'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw const AiJunglerApiException('扫描引擎未返回任务编号。');
    }
    return jobId;
  }

  Future<void> stopJob(String jobId) =>
      _emptyRequest('POST', _jobPath(jobId, suffix: '/stop'));

  Future<String> resumeJob(String jobId) async {
    final json = await _jsonRequest('POST', _jobPath(jobId, suffix: '/resume'));
    final resumedId = json['jobId'] as String?;
    if (resumedId == null || resumedId.isEmpty) {
      throw const AiJunglerApiException('扫描引擎未返回恢复后的任务编号。');
    }
    return resumedId;
  }

  Future<AiExposureProgress> progress(String jobId) async =>
      AiExposureProgress.fromJson(await _jsonRequest('GET', _jobPath(jobId)));

  Future<List<AiExposureHistoryEntry>> history({
    int limit = _kAiJunglerDefaultHistoryLimit,
  }) async => _jsonList(
    await _request('GET', '/v1/history?limit=$limit'),
  ).map(AiExposureHistoryEntry.fromJson).toList(growable: false);

  Future<List<AiExposureLogEntry>> logs(
    String jobId, {
    int limit = _kAiJunglerDefaultLogLimit,
  }) async => _jsonList(
    await _request('GET', '${_jobPath(jobId, suffix: '/logs')}?limit=$limit'),
  ).map(AiExposureLogEntry.fromJson).toList(growable: false);

  Future<List<AiExposureResult>> results({
    String? jobId,
    int limit = _kAiJunglerDefaultResultLimit,
  }) async {
    final query = <String>[
      'limit=$limit',
      if (jobId != null && jobId.isNotEmpty)
        'jobId=${Uri.encodeQueryComponent(jobId)}',
    ].join('&');
    return _jsonList(
      await _request('GET', '/v1/results?$query'),
    ).map(AiExposureResult.fromJson).toList(growable: false);
  }

  Future<void> deleteHistory(String jobId) =>
      _emptyRequest('DELETE', _jobPath(jobId, root: '/v1/history'));

  Future<List<AiExposureScanRule>> rules() async => _jsonList(
    await _request('GET', '/v1/rules'),
  ).map(AiExposureScanRule.fromJson).toList(growable: false);

  Future<void> saveRules(List<AiExposureScanRule> rules) => _emptyRequest(
    'PUT',
    '/v1/rules',
    body: rules.map((rule) => rule.toJson()).toList(growable: false),
  );

  Future<Map<String, bool>> sourceStatus() async {
    final json = await _jsonRequest('GET', '/v1/sources');
    return <String, bool>{
      for (final entry in json.entries) entry.key: entry.value == true,
    };
  }

  Future<void> updateSourceCredentials({
    String? githubToken,
    String? giteeToken,
    String? gitcodeToken,
    String? fofaEmail,
    String? fofaKey,
    String? shodanKey,
  }) => _emptyRequest(
    'PUT',
    '/v1/sources',
    body: <String, Object?>{
      if (githubToken?.trim().isNotEmpty == true)
        'githubToken': githubToken!.trim(),
      if (giteeToken?.trim().isNotEmpty == true)
        'giteeToken': giteeToken!.trim(),
      if (gitcodeToken?.trim().isNotEmpty == true)
        'gitcodeToken': gitcodeToken!.trim(),
      if (fofaEmail?.trim().isNotEmpty == true) 'fofaEmail': fofaEmail!.trim(),
      if (fofaKey?.trim().isNotEmpty == true) 'fofaKey': fofaKey!.trim(),
      if (shodanKey?.trim().isNotEmpty == true) 'shodanKey': shodanKey!.trim(),
    },
  );

  Future<List<AiExposureQuota>> quotas() async => _jsonList(
    await _request('GET', '/v1/sources/quotas'),
  ).map(AiExposureQuota.fromJson).toList(growable: false);

  Future<AiExposureProxyStatus> proxyStatus() async =>
      AiExposureProxyStatus.fromJson(await _jsonRequest('GET', '/v1/proxy'));

  Future<void> updateProxy(
    AiExposureProxyConfiguration configuration, {
    Map<String, Object?> systemProxy = const <String, Object?>{},
  }) => _emptyRequest(
    'PUT',
    '/v1/proxy',
    body: configuration.toRuntimeJson(systemProxy: systemProxy),
  );

  Future<AiExposureAiExtractorStatus> aiExtractorStatus() async =>
      AiExposureAiExtractorStatus.fromJson(
        await _jsonRequest('GET', '/v1/ai-extractor'),
      );

  Future<void> configureAiExtractor({
    required String endpoint,
    required String model,
    required Map<String, String> headers,
  }) => _emptyRequest(
    'PUT',
    '/v1/ai-extractor',
    body: <String, Object?>{
      'endpoint': endpoint,
      'model': model,
      'headers': headers,
    },
  );

  Future<AiExposureDependencyStatus> dependencyStatus() async =>
      AiExposureDependencyStatus.fromJson(
        await _jsonRequest('GET', '/v1/dependencies'),
      );

  Future<void> updateDependencies({
    String? postgresqlUrl,
    String? redisUrl,
    Map<String, Object?>? playwright,
  }) => _emptyRequest(
    'PUT',
    '/v1/dependencies',
    body: <String, Object?>{
      if (postgresqlUrl != null) 'postgresqlUrl': postgresqlUrl.trim(),
      if (redisUrl != null) 'redisUrl': redisUrl.trim(),
      if (playwright != null) 'playwright': playwright,
    },
  );

  Future<Map<String, Object?>> dependencyDataOverview() =>
      _jsonRequest('GET', '/v1/dependencies/data');

  Future<Map<String, Object?>> postgresqlRows(
    String table, {
    int limit = 50,
    int offset = 0,
  }) => _jsonRequest(
    'GET',
    '/v1/dependencies/postgresql/${Uri.encodeComponent(table)}'
        '?limit=${limit.clamp(1, 500)}&offset=${offset.clamp(0, 0x7fffffff)}',
  );

  Future<Map<String, Object?>> insertPostgresqlRow(
    String table,
    Map<String, Object?> values,
  ) => _jsonRequest(
    'POST',
    '/v1/dependencies/postgresql/${Uri.encodeComponent(table)}',
    body: <String, Object?>{'values': values},
  );

  Future<Map<String, Object?>> updatePostgresqlRow(
    String table, {
    required Map<String, Object?> keys,
    required Map<String, Object?> values,
  }) => _jsonRequest(
    'PUT',
    '/v1/dependencies/postgresql/${Uri.encodeComponent(table)}',
    body: <String, Object?>{'keys': keys, 'values': values},
  );

  Future<Map<String, Object?>> deletePostgresqlRow(
    String table,
    Map<String, Object?> keys,
  ) => _jsonRequest(
    'DELETE',
    '/v1/dependencies/postgresql/${Uri.encodeComponent(table)}',
    body: <String, Object?>{'keys': keys},
  );

  Future<Map<String, Object?>> queryPostgresql(
    String statement, {
    int limit = 200,
  }) => _jsonRequest(
    'POST',
    '/v1/dependencies/postgresql/query',
    body: <String, Object?>{'statement': statement, 'limit': limit},
  );

  Future<Map<String, Object?>> redisRecords({
    int cursor = 0,
    String search = '',
    int limit = 50,
  }) => _jsonRequest(
    'GET',
    '/v1/dependencies/redis'
        '?cursor=${cursor.clamp(0, 0x7fffffff)}'
        '&limit=${limit.clamp(1, 500)}'
        '&search=${Uri.encodeQueryComponent(search)}',
  );

  Future<Map<String, Object?>> putRedisRecord({
    required String key,
    required String type,
    required Object? value,
    required int? ttlSeconds,
  }) => _jsonRequest(
    'PUT',
    '/v1/dependencies/redis',
    body: <String, Object?>{
      'key': key,
      'type': type,
      'value': value,
      'ttlSeconds': ttlSeconds,
    },
  );

  Future<bool> deleteRedisRecord(String key) async =>
      (await _jsonRequest(
        'DELETE',
        '/v1/dependencies/redis',
        body: <String, Object?>{'key': key},
      ))['deleted'] ==
      true;

  Stream<Map<String, Object?>> events(String jobId) async* {
    final handshakeDeadline = MonotonicDeadline(
      _kAiJunglerRequestTimeout,
      timeoutMessage: '连接扫描引擎实时事件超时。',
    );
    HttpClientResponse? response;
    try {
      final request = await _open(
        'GET',
        _jobPath(jobId, suffix: '/events'),
        deadline: handshakeDeadline,
      );
      request.headers.set(HttpHeaders.acceptHeader, kTextEventStreamMimeType);
      response = await _closeWithinDeadline(request, handshakeDeadline);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = await _responseError(
          response,
          totalTimeout: handshakeDeadline.remaining(),
        );
        await cancelByteStream(response);
        response = null;
        throw error;
      }
      handshakeDeadline.stop();
      await for (final line in _boundedUtf8Lines(
        response.timeout(_kAiJunglerSseIdleTimeout),
      )) {
        final payload = sseDataPayload(line);
        if (payload == null || payload.isEmpty) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(payload);
        } on FormatException {
          // 跳过格式错误的 SSE 行而非终止整个事件流，
          // 避免单条坏行导致扫描实时监控中断。
          continue;
        }
        if (decoded is Map) {
          yield aiExposureJsonMap(decoded);
        }
        // 非 Map 类型的 JSON payload（如标量、数组）静默跳过，
        // SSE 事件约定为 JSON 对象，非对象 payload 无消费方。
      }
    } on TimeoutException {
      throw const AiJunglerApiException('扫描引擎实时事件长时间无响应。');
    } finally {
      handshakeDeadline.stop();
      if (response != null) await cancelByteStream(response);
    }
  }

  Future<Map<String, Object?>> _jsonRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    final decoded = await _request(method, path, body: body);
    if (decoded is! Map) {
      throw const AiJunglerApiException('扫描引擎返回的数据格式无效。');
    }
    return aiExposureJsonMap(decoded);
  }

  Future<void> _emptyRequest(String method, String path, {Object? body}) async {
    await _request(method, path, body: body);
  }

  Future<Object?> _request(String method, String path, {Object? body}) async {
    final payload = body == null ? null : utf8.encode(jsonEncode(body));
    if (payload != null && payload.length > _kAiJunglerMaxRequestBytes) {
      throw const AiJunglerApiException('提交内容超过 2 MB，请减少配置项后重试。');
    }
    final deadline = MonotonicDeadline(
      _kAiJunglerRequestTimeout,
      timeoutMessage: '扫描引擎请求超过总时限。',
    );
    try {
      final request = await _open(method, path, deadline: deadline);
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.add(payload);
      }
      final response = await _closeWithinDeadline(request, deadline);
      final success = response.statusCode >= 200 && response.statusCode < 300;
      final text = await _readUtf8Response(
        response,
        maxBytes: success
            ? _kAiJunglerMaxJsonResponseBytes
            : _kAiJunglerMaxErrorResponseBytes,
        totalTimeout: deadline.remaining(),
      );
      if (!success) {
        throw _textError(response.statusCode, text);
      }
      if (text.trim().isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        throw AiJunglerApiException(
          '扫描引擎返回了无法解析的数据。',
          statusCode: response.statusCode,
        );
      }
    } finally {
      deadline.stop();
    }
  }

  Future<HttpClientRequest> _open(
    String method,
    String path, {
    required MonotonicDeadline deadline,
  }) async {
    final uri = baseUri.resolve(path);
    final request = await _httpClient
        .openUrl(method, uri)
        .timeout(deadline.remaining());
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    return request;
  }

  Future<HttpClientResponse> _closeWithinDeadline(
    HttpClientRequest request,
    MonotonicDeadline deadline,
  ) {
    final timeout = deadline.remaining();
    return request.close().timeout(
      timeout,
      onTimeout: () {
        final error = deadline.timeoutException();
        request.abort(error);
        throw error;
      },
    );
  }

  String _jobPath(
    String jobId, {
    String root = '/v1/jobs',
    String suffix = '',
  }) {
    final normalized = jobId.trim();
    if (normalized.isEmpty) {
      throw const AiJunglerApiException('扫描任务编号不能为空。');
    }
    return '$root/${Uri.encodeComponent(normalized)}$suffix';
  }

  Future<AiJunglerApiException> _responseError(
    HttpClientResponse response, {
    required Duration totalTimeout,
  }) async => _textError(
    response.statusCode,
    await _readUtf8Response(
      response,
      maxBytes: _kAiJunglerMaxErrorResponseBytes,
      totalTimeout: totalTimeout,
    ),
  );

  AiJunglerApiException _textError(int statusCode, String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] is String) {
        return AiJunglerApiException(
          decoded['error'] as String,
          statusCode: statusCode,
        );
      }
    } on FormatException {
      // 统一回退到状态码，不透传服务端 HTML。
    }
    return AiJunglerApiException(
      '扫描引擎请求失败：HTTP $statusCode。',
      statusCode: statusCode,
    );
  }

  void close() => _httpClient.close(force: true);
}

Future<String> _readUtf8Response(
  HttpClientResponse response, {
  required int maxBytes,
  required Duration totalTimeout,
}) async {
  try {
    return await readBoundedHttpResponseText(
      response,
      maxBytes: maxBytes,
      idleTimeout: totalTimeout,
      totalTimeout: totalTimeout,
    );
  } on ByteStreamSizeLimitException {
    throw AiJunglerApiException(
      '扫描引擎响应超过 $maxBytes 字节限制。',
      statusCode: response.statusCode,
    );
  } on FormatException {
    throw AiJunglerApiException(
      '扫描引擎返回了无效的 UTF-8 数据。',
      statusCode: response.statusCode,
    );
  }
}

Stream<String> _boundedUtf8Lines(Stream<List<int>> response) async* {
  final pending = BytesBuilder(copy: false);
  await for (final chunk in response) {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      if (chunk[index] != 0x0a) continue;
      final length = index - start;
      if (pending.length + length > _kAiJunglerMaxSseLineBytes) {
        throw const AiJunglerApiException('扫描引擎实时事件超过大小限制。');
      }
      if (length > 0) pending.add(chunk.sublist(start, index));
      yield _decodeSseLine(pending.takeBytes());
      start = index + 1;
    }
    if (start < chunk.length) {
      final length = chunk.length - start;
      if (pending.length + length > _kAiJunglerMaxSseLineBytes) {
        throw const AiJunglerApiException('扫描引擎实时事件超过大小限制。');
      }
      pending.add(chunk.sublist(start));
    }
  }
  if (pending.length > 0) yield _decodeSseLine(pending.takeBytes());
}

String _decodeSseLine(Uint8List bytes) {
  final end = bytes.isNotEmpty && bytes.last == 0x0d
      ? bytes.length - 1
      : bytes.length;
  try {
    return utf8.decode(Uint8List.sublistView(bytes, 0, end));
  } on FormatException {
    throw const AiJunglerApiException('扫描引擎返回了无效的实时事件。');
  }
}

List<Map<String, Object?>> _jsonList(Object? value) => value is List
    ? value.map(aiExposureJsonMap).toList(growable: false)
    : throw const AiJunglerApiException('扫描引擎返回的数据格式无效。');

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/ai_exposure_models.dart';

const Duration _kAiJunglerRequestTimeout = Duration(seconds: 15);
const int _kAiJunglerMaxJsonResponseBytes = 8 * 1024 * 1024;
const int _kAiJunglerMaxErrorResponseBytes = 64 * 1024;
const int _kAiJunglerMaxSseLineBytes = 256 * 1024;

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
      _emptyRequest('POST', '/v1/jobs/$jobId/stop');

  Future<String> resumeJob(String jobId) async {
    final json = await _jsonRequest('POST', '/v1/jobs/$jobId/resume');
    final resumedId = json['jobId'] as String?;
    if (resumedId == null || resumedId.isEmpty) {
      throw const AiJunglerApiException('扫描引擎未返回恢复后的任务编号。');
    }
    return resumedId;
  }

  Future<AiExposureProgress> progress(String jobId) async =>
      AiExposureProgress.fromJson(await _jsonRequest('GET', '/v1/jobs/$jobId'));

  Future<List<AiExposureHistoryEntry>> history({int limit = 200}) async =>
      _jsonList(
        await _request('GET', '/v1/history?limit=$limit'),
      ).map(AiExposureHistoryEntry.fromJson).toList(growable: false);

  Future<List<AiExposureLogEntry>> logs(
    String jobId, {
    int limit = 2000,
  }) async => _jsonList(
    await _request('GET', '/v1/jobs/$jobId/logs?limit=$limit'),
  ).map(AiExposureLogEntry.fromJson).toList(growable: false);

  Future<List<AiExposureResult>> results({
    String? jobId,
    int limit = 1000,
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
      _emptyRequest('DELETE', '/v1/history/$jobId');

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
    String? fofaEmail,
    String? fofaKey,
    String? shodanKey,
  }) => _emptyRequest(
    'PUT',
    '/v1/sources',
    body: <String, Object?>{
      if (githubToken?.trim().isNotEmpty == true)
        'githubToken': githubToken!.trim(),
      if (fofaEmail?.trim().isNotEmpty == true) 'fofaEmail': fofaEmail!.trim(),
      if (fofaKey?.trim().isNotEmpty == true) 'fofaKey': fofaKey!.trim(),
      if (shodanKey?.trim().isNotEmpty == true) 'shodanKey': shodanKey!.trim(),
    },
  );

  Future<List<AiExposureQuota>> quotas() async => _jsonList(
    await _request('GET', '/v1/sources/quotas'),
  ).map(AiExposureQuota.fromJson).toList(growable: false);

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

  Future<void> clearAiExtractor() =>
      _emptyRequest('DELETE', '/v1/ai-extractor');

  Future<AiExposureDependencyStatus> dependencyStatus() async =>
      AiExposureDependencyStatus.fromJson(
        await _jsonRequest('GET', '/v1/dependencies'),
      );

  Future<void> updateDependencies({String? postgresqlUrl, String? redisUrl}) =>
      _emptyRequest(
        'PUT',
        '/v1/dependencies',
        body: <String, Object?>{
          if (postgresqlUrl != null) 'postgresqlUrl': postgresqlUrl.trim(),
          if (redisUrl != null) 'redisUrl': redisUrl.trim(),
        },
      );

  Stream<Map<String, Object?>> events(String jobId) async* {
    final request = await _open('GET', '/v1/jobs/$jobId/events');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close().timeout(_kAiJunglerRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw await _responseError(response);
    }
    await for (final line in _boundedUtf8Lines(response)) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        throw const AiJunglerApiException('扫描引擎返回了无效的实时事件。');
      }
      if (decoded is Map) yield aiExposureJsonMap(decoded);
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
    final request = await _open(method, path);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(_kAiJunglerRequestTimeout);
    final success = response.statusCode >= 200 && response.statusCode < 300;
    final text = await _readUtf8Response(
      response,
      maxBytes: success
          ? _kAiJunglerMaxJsonResponseBytes
          : _kAiJunglerMaxErrorResponseBytes,
    ).timeout(_kAiJunglerRequestTimeout);
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
  }

  Future<HttpClientRequest> _open(String method, String path) async {
    final uri = baseUri.resolve(path);
    final request = await _httpClient
        .openUrl(method, uri)
        .timeout(_kAiJunglerRequestTimeout);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    return request;
  }

  Future<AiJunglerApiException> _responseError(
    HttpClientResponse response,
  ) async => _textError(
    response.statusCode,
    await _readUtf8Response(
      response,
      maxBytes: _kAiJunglerMaxErrorResponseBytes,
    ).timeout(_kAiJunglerRequestTimeout),
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
}) async {
  if (response.contentLength > maxBytes) {
    await response.listen((_) {}).cancel();
    throw AiJunglerApiException(
      '扫描引擎响应超过 $maxBytes 字节限制。',
      statusCode: response.statusCode,
    );
  }
  final body = BytesBuilder(copy: false);
  await for (final chunk in response) {
    if (body.length + chunk.length > maxBytes) {
      throw AiJunglerApiException(
        '扫描引擎响应超过 $maxBytes 字节限制。',
        statusCode: response.statusCode,
      );
    }
    body.add(chunk);
  }
  try {
    return utf8.decode(body.takeBytes());
  } on FormatException {
    throw AiJunglerApiException(
      '扫描引擎返回了无效的 UTF-8 数据。',
      statusCode: response.statusCode,
    );
  }
}

Stream<String> _boundedUtf8Lines(HttpClientResponse response) async* {
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

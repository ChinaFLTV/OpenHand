import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../../app/support/system_proxy.dart';
import '../../../../shared/util/input_value_parsing.dart';

const String _contentTypeHeaderName = 'content-type';

class AiMultipartUploadFile {
  const AiMultipartUploadFile({required this.filePath, this.filename});

  final String filePath;
  final String? filename;
}

class AiTransportClient {
  AiTransportClient({http.Client? client})
    : _client = client ?? SystemProxyResolver.instance.createHttpClient();

  final http.Client _client;

  Future<http.Response> sendJson({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    final request = http.Request(method.toUpperCase(), uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
  }

  Future<http.Response> sendMultipart({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    final request = http.MultipartRequest(method.toUpperCase(), uri);
    headers.forEach((key, value) {
      if (lowercaseStringFromValue(key) == _contentTypeHeaderName) return;
      request.headers[key] = value;
    });
    for (final entry in body.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;
      if (value is AiMultipartUploadFile) {
        request.files.add(
          await http.MultipartFile.fromPath(
            key,
            value.filePath,
            filename: value.filename ?? p.basename(value.filePath),
          ),
        );
        continue;
      }
      if (value is List<AiMultipartUploadFile>) {
        for (final item in value) {
          request.files.add(
            await http.MultipartFile.fromPath(
              key,
              item.filePath,
              filename: item.filename ?? p.basename(item.filePath),
            ),
          );
        }
        continue;
      }
      final fieldValue = value is String
          ? value
          : (value is num || value is bool
                ? value.toString()
                : jsonEncode(value));
      request.fields[key] = fieldValue;
    }
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
  }

  Future<http.Response> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    return _client.get(uri, headers: headers).timeout(timeout);
  }

  Future<List<int>> downloadBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final response = await _client.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  void dispose() {
    _client.close();
  }
}

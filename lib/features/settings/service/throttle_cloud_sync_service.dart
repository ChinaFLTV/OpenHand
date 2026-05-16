import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../app/support/silent_log.dart';

/// 节流配置云端同步 provider 类型。
///
/// 2026-05-18 — 三种供选：
///   * [custom]：自定义 HTTP endpoint（PUT 推、GET 拉，Bearer token），
///     当前版本的真实实现，零依赖、零鉴权耦合，可指向 Gist / S3 /
///     Cloudflare KV 等任何裸 HTTP 后端；
///   * [iCloud]：iCloud Drive 文档同步，需要 native 端 NSDocument /
///     UbiquitousKeyValueStore 桥接，本期作为占位入口预留；
///   * [oauth]：OAuth 鉴权 (例如 Google Drive / GitHub Gist)，需要
///     native sdk 嵌入与跳转流，本期作为占位入口预留。
enum ThrottleCloudSyncProvider {
  custom,
  iCloud,
  oauth;

  String get storageValue => switch (this) {
        ThrottleCloudSyncProvider.custom => 'custom',
        ThrottleCloudSyncProvider.iCloud => 'icloud',
        ThrottleCloudSyncProvider.oauth => 'oauth',
      };

  static ThrottleCloudSyncProvider fromStorage(String value) {
    switch (value.trim().toLowerCase()) {
      case 'icloud':
        return ThrottleCloudSyncProvider.iCloud;
      case 'oauth':
        return ThrottleCloudSyncProvider.oauth;
      case 'custom':
      default:
        return ThrottleCloudSyncProvider.custom;
    }
  }
}

/// 同步操作结果。`ok=false` 时 `message` 给可读错误信息。
class ThrottleCloudSyncResult {
  const ThrottleCloudSyncResult._({
    required this.ok,
    this.message = '',
    this.config,
    this.fetchedAt,
  });

  factory ThrottleCloudSyncResult.success({
    String message = '',
    Map<String, Object?>? config,
    DateTime? fetchedAt,
  }) {
    return ThrottleCloudSyncResult._(
      ok: true,
      message: message,
      config: config,
      fetchedAt: fetchedAt,
    );
  }

  factory ThrottleCloudSyncResult.failure(String message) {
    return ThrottleCloudSyncResult._(ok: false, message: message);
  }

  final bool ok;
  final String message;
  final Map<String, Object?>? config;
  final DateTime? fetchedAt;
}

/// 节流配置云端同步 service。
///
/// 2026-05-18 — service 不感知 SettingsController 的存在；调用方负责
/// 把要 push 的 config 序列化好，把 pull 回来的 Map 喂给
/// `SettingsController.importAiStreamThrottleConfig`。这样 service
/// 单纯做"网络 IO + JSON 编解码"，方便被脚本工具复用。
class ThrottleCloudSyncService {
  ThrottleCloudSyncService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// 与 macOS / iOS native 端 CloudSyncBridge 共用的 method channel。
  static const MethodChannel _icloudChannel = MethodChannel('openhand/cloud_sync');

  /// 把 [config] 推送到云端。`provider == iCloud` 时走 native 端的
  /// NSUbiquitousKeyValueStore；`oauth` 仍未实现，直接 fail-fast。
  Future<ThrottleCloudSyncResult> push({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
    required Map<String, Object?> config,
  }) async {
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pushIcloud(config);
      case ThrottleCloudSyncProvider.oauth:
        return ThrottleCloudSyncResult.failure(
          'OAuth sync requires native SDK; not yet wired up.',
        );
      case ThrottleCloudSyncProvider.custom:
        break;
    }
    final url = endpoint.trim();
    if (url.isEmpty) {
      return ThrottleCloudSyncResult.failure('endpoint is required');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' && uri.scheme != 'http') {
      return ThrottleCloudSyncResult.failure(
        'endpoint must be http(s) URL',
      );
    }
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final body = jsonEncode(<String, Object?>{
        'kind': 'openhand.throttle_config',
        'version': 1,
        'config': config,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      final resp = await client
          .put(
            uri,
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
              if (token.trim().isNotEmpty)
                HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
              'X-OpenHand-Client': 'throttle-sync/1',
            },
            body: utf8.encode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ThrottleCloudSyncResult.failure(
          'HTTP ${resp.statusCode}: ${_truncate(resp.body, 256)}',
        );
      }
      return ThrottleCloudSyncResult.success(
        message: 'Pushed ${utf8.encode(body).length} bytes',
      );
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure('timeout after 15s');
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'push', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// 从云端拉取 [config]。返回 [ThrottleCloudSyncResult.config]。
  Future<ThrottleCloudSyncResult> pull({
    required ThrottleCloudSyncProvider provider,
    required String endpoint,
    required String token,
  }) async {
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pullIcloud();
      case ThrottleCloudSyncProvider.oauth:
        return ThrottleCloudSyncResult.failure(
          'OAuth sync requires native SDK; not yet wired up.',
        );
      case ThrottleCloudSyncProvider.custom:
        break;
    }
    final url = endpoint.trim();
    if (url.isEmpty) {
      return ThrottleCloudSyncResult.failure('endpoint is required');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' && uri.scheme != 'http') {
      return ThrottleCloudSyncResult.failure(
        'endpoint must be http(s) URL',
      );
    }
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final resp = await client
          .get(
            uri,
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'application/json',
              if (token.trim().isNotEmpty)
                HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
              'X-OpenHand-Client': 'throttle-sync/1',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ThrottleCloudSyncResult.failure(
          'HTTP ${resp.statusCode}: ${_truncate(resp.body, 256)}',
        );
      }
      final decoded = jsonDecode(resp.body);
      Map<String, Object?>? cfg;
      if (decoded is Map) {
        final inner = decoded['config'];
        if (inner is Map) {
          cfg = Map<String, Object?>.from(inner);
        } else {
          // 兼容裸格式：整体即配置文档
          cfg = Map<String, Object?>.from(decoded);
        }
      }
      if (cfg == null) {
        return ThrottleCloudSyncResult.failure(
          'response is not a JSON object',
        );
      }
      return ThrottleCloudSyncResult.success(
        config: cfg,
        fetchedAt: DateTime.now().toUtc(),
        message: 'OK',
      );
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure('timeout after 15s');
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'pull', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    } finally {
      if (ownsClient) client.close();
    }
  }

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}…';
  }

  /// 2026-05-18 — iCloud 桥接：调 native CloudSyncBridge。
  /// macOS / iOS 走 NSUbiquitousKeyValueStore（key-value，1MB 上限）；
  /// 其他平台没有实现，channel 抛 MissingPluginException → 转换为
  /// 友好错误信息。
  Future<ThrottleCloudSyncResult> _pushIcloud(
    Map<String, Object?> config,
  ) async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return ThrottleCloudSyncResult.failure(
        'iCloud sync is only supported on macOS / iOS.',
      );
    }
    try {
      final json = const JsonEncoder.withIndent('  ').convert(config);
      final result = await _icloudChannel.invokeMapMethod<String, dynamic>(
        'pushIcloud',
        <String, dynamic>{'config_json': json},
      );
      final ok = result?['ok'] == true;
      final synced = result?['synchronized'] == true;
      if (!ok) {
        return ThrottleCloudSyncResult.failure(
          synced
              ? 'iCloud rejected payload'
              : 'iCloud sync deferred (will retry when connectivity returns)',
        );
      }
      return ThrottleCloudSyncResult.success(
        message: synced
            ? 'iCloud sync ${utf8.encode(json).length} bytes'
            : 'iCloud sync queued',
      );
    } on MissingPluginException {
      return ThrottleCloudSyncResult.failure(
        'iCloud channel not registered (host platform missing bridge).',
      );
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'pushIcloud', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    }
  }

  Future<ThrottleCloudSyncResult> _pullIcloud() async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return ThrottleCloudSyncResult.failure(
        'iCloud sync is only supported on macOS / iOS.',
      );
    }
    try {
      final result = await _icloudChannel.invokeMapMethod<String, dynamic>(
        'pullIcloud',
      );
      final ok = result?['ok'] == true;
      final raw = (result?['config_json'] as String?) ?? '';
      if (!ok || raw.isEmpty) {
        return ThrottleCloudSyncResult.failure(
          'iCloud has no throttle config yet for this account.',
        );
      }
      final decoded = jsonDecode(raw);
      Map<String, Object?>? cfg;
      if (decoded is Map) {
        final inner = decoded['config'];
        if (inner is Map) {
          cfg = Map<String, Object?>.from(inner);
        } else {
          cfg = Map<String, Object?>.from(decoded);
        }
      }
      if (cfg == null) {
        return ThrottleCloudSyncResult.failure(
          'iCloud payload is not a JSON object',
        );
      }
      return ThrottleCloudSyncResult.success(
        config: cfg,
        fetchedAt: DateTime.now().toUtc(),
        message: 'iCloud OK',
      );
    } on MissingPluginException {
      return ThrottleCloudSyncResult.failure(
        'iCloud channel not registered (host platform missing bridge).',
      );
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'pullIcloud', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    }
  }
}

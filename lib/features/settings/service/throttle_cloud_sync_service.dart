import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../app/state/settings_controller.dart'
    show aiStreamThrottleConfigSchemaVersion, migrateAiStreamThrottleConfig;
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
///   * [gistGitHub]：GitHub Gist 同步（personal access token + gist id），
///     纯 HTTPS，0 依赖，2026-05-19 新增；token 应为细粒度 PAT，仅授
///     `gist` scope。
enum ThrottleCloudSyncProvider {
  custom,
  iCloud,
  oauth,
  gistGitHub;

  String get storageValue => switch (this) {
        ThrottleCloudSyncProvider.custom => 'custom',
        ThrottleCloudSyncProvider.iCloud => 'icloud',
        ThrottleCloudSyncProvider.oauth => 'oauth',
        ThrottleCloudSyncProvider.gistGitHub => 'gist_github',
      };

  static ThrottleCloudSyncProvider fromStorage(String value) {
    switch (value.trim().toLowerCase()) {
      case 'icloud':
        return ThrottleCloudSyncProvider.iCloud;
      case 'oauth':
        return ThrottleCloudSyncProvider.oauth;
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
/// 2026-05-19 — 增补 `updatedAtMs` 字段：拉取成功且远端 payload 内含
/// `updated_at_ms` 时透传给上层，自动同步以此判定是否覆盖本地。
class ThrottleCloudSyncResult {
  const ThrottleCloudSyncResult._({
    required this.ok,
    this.message = '',
    this.config,
    this.fetchedAt,
    this.updatedAtMs = 0,
  });

  factory ThrottleCloudSyncResult.success({
    String message = '',
    Map<String, Object?>? config,
    DateTime? fetchedAt,
    int updatedAtMs = 0,
  }) {
    return ThrottleCloudSyncResult._(
      ok: true,
      message: message,
      config: config,
      fetchedAt: fetchedAt,
      updatedAtMs: updatedAtMs,
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
}

/// 节流配置云端同步 service。
///
/// 2026-05-18 — service 不感知 SettingsController 的存在；调用方负责
/// 把要 push 的 config 序列化好，把 pull 回来的 Map 喂给
/// `SettingsController.importAiStreamThrottleConfig`。这样 service
/// 单纯做"网络 IO + JSON 编解码"，方便被脚本工具复用。
///
/// 2026-05-19 — 新增 [cloudChanges] Stream：当 native 端收到
/// `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`（即用户
/// 在另一台设备改了节流配置，iCloud 推送过来）时主动调
/// `cloudConfigChanged` method，service 转换为 Stream 事件让上层
/// 自动同步服务感知并触发一次拉取。
class ThrottleCloudSyncService {
  ThrottleCloudSyncService({http.Client? client}) : _client = client {
    _icloudChannel.setMethodCallHandler(_handleNativeCall);
  }

  final http.Client? _client;

  final StreamController<void> _cloudChangesController =
      StreamController<void>.broadcast();

  /// 远端配置发生变更时的广播流（无 payload）。订阅方收到事件后
  /// 应主动调 [pull] 拉取最新配置；为防抖动，事件可能在短时间内
  /// 多次发出，订阅方需自行 debounce / dedup。
  Stream<void> get cloudChanges => _cloudChangesController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
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

  Future<void> dispose() async {
    if (!_cloudChangesController.isClosed) {
      await _cloudChangesController.close();
    }
    _icloudChannel.setMethodCallHandler(null);
  }

  /// 与 macOS / iOS native 端 CloudSyncBridge 共用的 method channel。
  static const MethodChannel _icloudChannel = MethodChannel('openhand/cloud_sync');

  /// 把 [config] 推送到云端。`provider == iCloud` 时走 native 端的
  /// NSUbiquitousKeyValueStore；`oauth` 仍未实现，直接 fail-fast。
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
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pushIcloud(config, updatedAtMs);
      case ThrottleCloudSyncProvider.oauth:
        return ThrottleCloudSyncResult.failure(
          'OAuth sync requires native SDK; use Gist instead.',
        );
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
        'version': aiStreamThrottleConfigSchemaVersion,
        'config': config,
        'updated_at_ms': updatedAtMs,
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
    String gistId = '',
  }) async {
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        return _pullIcloud();
      case ThrottleCloudSyncProvider.oauth:
        return ThrottleCloudSyncResult.failure(
          'OAuth sync requires native SDK; use Gist instead.',
        );
      case ThrottleCloudSyncProvider.gistGitHub:
        return _pullGist(gistId: gistId, token: token);
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
      int updatedAtMs = 0;
      if (decoded is Map) {
        final inner = decoded['config'];
        if (inner is Map) {
          cfg = Map<String, Object?>.from(inner);
        } else {
          // 兼容裸格式：整体即配置文档
          cfg = Map<String, Object?>.from(decoded);
        }
        updatedAtMs = _readUpdatedAtMs(decoded, cfg);
      }
      if (cfg == null) {
        return ThrottleCloudSyncResult.failure(
          'response is not a JSON object',
        );
      }
      // 跨版本兼容：远端可能仍是 v1 文档（无 duration_seconds），
      // 在这里统一升级到当前 schema 再上抛。
      cfg = migrateAiStreamThrottleConfig(cfg);
      return ThrottleCloudSyncResult.success(
        config: cfg,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: updatedAtMs,
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

  /// 兼容多层级位置：顶层 `updated_at_ms`、内层 `config.updated_at_ms`。
  static int _readUpdatedAtMs(Map outer, Map<String, Object?>? inner) {
    final outerVal = outer['updated_at_ms'];
    if (outerVal is int && outerVal > 0) return outerVal;
    if (outerVal is num) return outerVal.toInt();
    if (inner != null) {
      final innerVal = inner['updated_at_ms'];
      if (innerVal is int && innerVal > 0) return innerVal;
      if (innerVal is num) return innerVal.toInt();
    }
    return 0;
  }

  /// 2026-05-18 — iCloud 桥接：调 native CloudSyncBridge。
  /// macOS / iOS 走 NSUbiquitousKeyValueStore（key-value，1MB 上限）；
  /// 其他平台没有实现，channel 抛 MissingPluginException → 转换为
  /// 友好错误信息。
  Future<ThrottleCloudSyncResult> _pushIcloud(
    Map<String, Object?> config,
    int updatedAtMs,
  ) async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return ThrottleCloudSyncResult.failure(
        'iCloud sync is only supported on macOS / iOS.',
      );
    }
    try {
      // payload 顶层带 updated_at_ms，方便另一端 pull 后比对时间戳。
      final payload = <String, Object?>{
        'config': config,
        'updated_at_ms': updatedAtMs,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);
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
      int updatedAtMs = 0;
      if (decoded is Map) {
        final inner = decoded['config'];
        if (inner is Map) {
          cfg = Map<String, Object?>.from(inner);
        } else {
          cfg = Map<String, Object?>.from(decoded);
        }
        updatedAtMs = _readUpdatedAtMs(decoded, cfg);
      }
      if (cfg == null) {
        return ThrottleCloudSyncResult.failure(
          'iCloud payload is not a JSON object',
        );
      }
      cfg = migrateAiStreamThrottleConfig(cfg);
      return ThrottleCloudSyncResult.success(
        config: cfg,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: updatedAtMs,
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

  /// 2026-05-19 — GitHub Gist 同步实现：
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
    final pat = token.trim();
    if (pat.isEmpty) {
      return ThrottleCloudSyncResult.failure('GitHub PAT is required');
    }
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final fileContent = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'kind': 'openhand.throttle_config',
          'version': aiStreamThrottleConfigSchemaVersion,
          'config': config,
          'updated_at_ms': updatedAtMs,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final body = jsonEncode(<String, Object?>{
        'description': 'OpenHand throttle config (auto-synced)',
        'public': false,
        'files': <String, Object?>{
          'openhand_throttle.json': <String, Object?>{
            'content': fileContent,
          },
        },
      });
      final headers = <String, String>{
        HttpHeaders.acceptHeader: 'application/vnd.github+json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.authorizationHeader: 'Bearer $pat',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'OpenHand-throttle-sync/1',
      };
      final id = gistId.trim();
      final http.Response resp;
      if (id.isEmpty) {
        resp = await client
            .post(
              Uri.parse('https://api.github.com/gists'),
              headers: headers,
              body: utf8.encode(body),
            )
            .timeout(const Duration(seconds: 15));
      } else {
        resp = await client
            .patch(
              Uri.parse('https://api.github.com/gists/$id'),
              headers: headers,
              body: utf8.encode(body),
            )
            .timeout(const Duration(seconds: 15));
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ThrottleCloudSyncResult.failure(
          'Gist HTTP ${resp.statusCode}: ${_truncate(resp.body, 256)}',
        );
      }
      String createdId = '';
      if (id.isEmpty) {
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['id'] is String) {
            createdId = decoded['id'] as String;
          }
        } catch (_) {/* ignore */}
      }
      return ThrottleCloudSyncResult.success(
        message: id.isEmpty
            ? 'Created gist ${createdId.isEmpty ? "(id missing)" : createdId}'
            : 'Updated gist ($id)',
      );
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure('timeout after 15s');
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'pushGist', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    } finally {
      if (ownsClient) client.close();
    }
  }

  Future<ThrottleCloudSyncResult> _pullGist({
    required String gistId,
    required String token,
  }) async {
    final id = gistId.trim();
    if (id.isEmpty) {
      return ThrottleCloudSyncResult.failure('Gist ID is required');
    }
    final pat = token.trim();
    if (pat.isEmpty) {
      return ThrottleCloudSyncResult.failure('GitHub PAT is required');
    }
    final ownsClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final resp = await client
          .get(
            Uri.parse('https://api.github.com/gists/$id'),
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'application/vnd.github+json',
              HttpHeaders.authorizationHeader: 'Bearer $pat',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'OpenHand-throttle-sync/1',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return ThrottleCloudSyncResult.failure(
          'Gist HTTP ${resp.statusCode}: ${_truncate(resp.body, 256)}',
        );
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return ThrottleCloudSyncResult.failure(
          'Gist response is not a JSON object',
        );
      }
      final files = decoded['files'];
      if (files is! Map) {
        return ThrottleCloudSyncResult.failure(
          'Gist payload missing files field',
        );
      }
      final entry = files['openhand_throttle.json'];
      if (entry is! Map) {
        return ThrottleCloudSyncResult.failure(
          'Gist does not contain openhand_throttle.json',
        );
      }
      var content = entry['content'];
      // GitHub 在文件 > 1MB 时会把内容截断并填 truncated=true，此处
      // 仅做安全提示，不再二次拉取（节流配置不会到 1MB）。
      if (entry['truncated'] == true) {
        return ThrottleCloudSyncResult.failure(
          'Gist file is truncated; payload too large.',
        );
      }
      if (content is! String) {
        return ThrottleCloudSyncResult.failure(
          'Gist file content is not a string',
        );
      }
      final inner = jsonDecode(content);
      if (inner is! Map) {
        return ThrottleCloudSyncResult.failure(
          'Gist file is not a JSON object',
        );
      }
      Map<String, Object?>? cfg;
      final innerCfg = inner['config'];
      if (innerCfg is Map) {
        cfg = Map<String, Object?>.from(innerCfg);
      } else {
        cfg = Map<String, Object?>.from(inner);
      }
      final updatedAtMs = _readUpdatedAtMs(inner, cfg);
      cfg = migrateAiStreamThrottleConfig(cfg);
      return ThrottleCloudSyncResult.success(
        config: cfg,
        fetchedAt: DateTime.now().toUtc(),
        updatedAtMs: updatedAtMs,
        message: 'Gist OK',
      );
    } on TimeoutException {
      return ThrottleCloudSyncResult.failure('timeout after 15s');
    } catch (error, stack) {
      silentLog('throttle_cloud_sync', 'pullGist', error, stack);
      return ThrottleCloudSyncResult.failure('$error');
    } finally {
      if (ownsClient) client.close();
    }
  }
}

// 代理配置持久化在设置记录中；密码当前按原值存储。
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../shared/net/tcp_port_utils.dart';
import '../../shared/util/input_value_parsing.dart';

enum AppProxyMode { disabled, automatic, manual }

enum AppProxyProtocol { http, https, socks }

extension AppProxyModeJson on AppProxyMode {
  String get jsonValue {
    switch (this) {
      case AppProxyMode.disabled:
        return 'disabled';
      case AppProxyMode.automatic:
        return 'automatic';
      case AppProxyMode.manual:
        return 'manual';
    }
  }

  static AppProxyMode fromJson(Object? raw) {
    switch (stringFromValue(raw).toLowerCase()) {
      case 'disabled':
      case 'none':
      case 'off':
        return AppProxyMode.disabled;
      case 'manual':
        return AppProxyMode.manual;
      case 'automatic':
      case 'auto':
      case 'system':
      default:
        return AppProxyMode.automatic;
    }
  }
}

extension AppProxyProtocolJson on AppProxyProtocol {
  String get jsonValue {
    switch (this) {
      case AppProxyProtocol.http:
        return 'http';
      case AppProxyProtocol.https:
        return 'https';
      case AppProxyProtocol.socks:
        return 'socks';
    }
  }

  static AppProxyProtocol? tryFromJson(Object? raw) {
    switch (stringFromValue(raw).toLowerCase()) {
      case 'http':
        return AppProxyProtocol.http;
      case 'https':
        return AppProxyProtocol.https;
      case 'socks':
      case 'socks5':
      case 'socks4':
        return AppProxyProtocol.socks;
    }
    return null;
  }
}

/// 代理配置卡片的不可变设置，通过 `copyWith` 创建更新后的实例。
class AppProxySettings {
  const AppProxySettings({
    required this.mode,
    required this.protocols,
    required this.host,
    required this.port,
    required this.authEnabled,
    required this.username,
    required this.password,
    required this.exceptions,
    this.testEndpoint = defaultTestEndpoint,
  });

  factory AppProxySettings.defaults() => const AppProxySettings(
    mode: AppProxyMode.automatic,
    protocols: <AppProxyProtocol>{
      AppProxyProtocol.http,
      AppProxyProtocol.https,
    },
    host: '',
    port: defaultPort,
    authEnabled: false,
    username: '',
    password: '',
    exceptions: <String>[],
  );

  /// 宽容解析 JSON：忽略未知字段，结构无效时回退默认值，避免损坏的设置文件
  /// 中断应用启动。
  factory AppProxySettings.fromJson(Object? rawJson) {
    final json = optionalStringKeyedMapFromValueOrJsonText(rawJson);
    if (json == null) {
      return AppProxySettings.defaults();
    }
    final defaults = AppProxySettings.defaults();
    final mode = AppProxyModeJson.fromJson(json['mode']);

    final rawProtocols = json['protocols'];
    final protocols = <AppProxyProtocol>{};
    if (rawProtocols is List) {
      for (final entry in rawProtocols) {
        final parsed = AppProxyProtocolJson.tryFromJson(entry);
        if (parsed != null) {
          protocols.add(parsed);
        }
      }
    }
    final usableProtocols = _normalizeProtocols(
      protocols,
      fallback: defaults.protocols,
    );

    final host = stringFromValue(json['host'], fallback: defaults.host);
    final port = portFromValue(json['port']);
    final authEnabled = boolFromValue(json['auth_enabled']);
    final username = _credentialFromValue(json['username']);
    final password = _credentialFromValue(json['password']);
    final exceptions = _normalizeExceptions(
      stringListFromValue(json['exceptions']),
    );

    final testEndpoint = _normalizeTestEndpoint(
      stringFromValue(json['test_endpoint']),
    );

    return AppProxySettings(
      mode: mode,
      protocols: usableProtocols,
      host: host,
      port: port,
      authEnabled: authEnabled,
      username: username,
      password: password,
      exceptions: List<String>.unmodifiable(exceptions),
      testEndpoint: testEndpoint,
    );
  }

  final AppProxyMode mode;
  final Set<AppProxyProtocol> protocols;
  final String host;
  final int port;
  final bool authEnabled;
  final String username;
  final String password;
  final List<String> exceptions;

  /// 代理连通性测试使用的 URL。空字符串同于默认值。
  final String testEndpoint;

  static const int defaultPort = 7890;

  /// 代理连通性测试默认 URL。Google generate_204
  /// 是历史上最稳的 "204 No Content" 探针，响应体 0 字节、
  /// 不会被透明压缩、不会被 UA 鉴权拦截。
  static const String defaultTestEndpoint =
      'https://www.google.com/generate_204';

  static int portFromValue(Object? value) {
    return clampedTcpPortFromValue(value, fallback: defaultPort);
  }

  static int normalizePort(int value) {
    return clampTcpPort(value);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.jsonValue,
    'protocols': _normalizeProtocols(
      protocols,
    ).map((p) => p.jsonValue).toList(growable: false),
    'host': host,
    'port': normalizePort(port),
    'auth_enabled': authEnabled,
    'username': username,
    'password': password,
    'exceptions': _normalizeExceptions(exceptions),
    'test_endpoint': _normalizeTestEndpoint(testEndpoint),
  };

  AppProxySettings copyWith({
    AppProxyMode? mode,
    Set<AppProxyProtocol>? protocols,
    String? host,
    int? port,
    bool? authEnabled,
    String? username,
    String? password,
    List<String>? exceptions,
    String? testEndpoint,
  }) {
    return AppProxySettings(
      mode: mode ?? this.mode,
      protocols: _normalizeProtocols(protocols ?? this.protocols),
      host: host ?? this.host,
      port: port == null ? normalizePort(this.port) : normalizePort(port),
      authEnabled: authEnabled ?? this.authEnabled,
      username: username ?? this.username,
      password: password ?? this.password,
      exceptions: _normalizeExceptions(exceptions ?? this.exceptions),
      testEndpoint: _normalizeTestEndpoint(testEndpoint ?? this.testEndpoint),
    );
  }

  @override
  String toString() {
    return jsonEncode(<String, Object?>{
      ...toJson(),
      'password': password.isEmpty ? '' : '***',
    });
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppProxySettings &&
        other.mode == mode &&
        other.host == host &&
        other.port == port &&
        other.authEnabled == authEnabled &&
        other.username == username &&
        other.password == password &&
        other.protocols.length == protocols.length &&
        other.protocols.containsAll(protocols) &&
        listEquals(other.exceptions, exceptions) &&
        other.testEndpoint == testEndpoint;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    host,
    port,
    authEnabled,
    username,
    password,
    Object.hashAllUnordered(protocols),
    Object.hashAll(exceptions),
    testEndpoint,
  );
}

String _credentialFromValue(Object? value) {
  if (value is String) return value;
  return stringFromValue(value);
}

Set<AppProxyProtocol> _normalizeProtocols(
  Iterable<AppProxyProtocol> protocols, {
  Set<AppProxyProtocol>? fallback,
}) {
  final source = protocols.toSet();
  if (source.isEmpty) {
    return Set<AppProxyProtocol>.unmodifiable(
      fallback ?? AppProxySettings.defaults().protocols,
    );
  }
  return Set<AppProxyProtocol>.unmodifiable(
    AppProxyProtocol.values.where(source.contains),
  );
}

List<String> _normalizeExceptions(Iterable<String> exceptions) {
  final seen = <String>{};
  final out = <String>[];
  for (final item in exceptions) {
    final normalized = nullIfBlank(item);
    if (normalized == null || !seen.add(normalized)) continue;
    out.add(normalized);
  }
  return List<String>.unmodifiable(out);
}

String _normalizeTestEndpoint(String value) {
  return nullIfBlank(value) ?? AppProxySettings.defaultTestEndpoint;
}

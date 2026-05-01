// 2026-05-03: Proxy configuration model. Backs the new "系统 / System"
// settings card and is consumed by `SystemProxyResolver`. Persisted as
// a JSON object under the `proxy` key in `app_settings.json`.
//
// Privacy: the password field is stored verbatim in the settings file
// (same JSON shape as every other secret in this app today). If the
// surrounding storage strategy ever upgrades to keychain-backed
// secrets, this is the place to plug in.
import 'dart:convert';

enum AppProxyMode {
  disabled,
  automatic,
  manual,
}

enum AppProxyProtocol {
  http,
  https,
  socks,
}

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
    switch ('$raw'.toLowerCase()) {
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
    switch ('$raw'.toLowerCase()) {
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

/// Settings backing the proxy configuration card. Immutable; mutate via
/// `copyWith`.
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
  });

  factory AppProxySettings.defaults() => const AppProxySettings(
        mode: AppProxyMode.automatic,
        protocols: <AppProxyProtocol>{
          AppProxyProtocol.http,
          AppProxyProtocol.https,
        },
        host: '',
        port: 7890,
        authEnabled: false,
        username: '',
        password: '',
        exceptions: <String>[],
      );

  /// Lenient JSON decoder. Unknown fields are ignored. Bad shapes fall
  /// back to defaults() so a corrupted settings file never crashes the
  /// app boot.
  factory AppProxySettings.fromJson(Object? rawJson) {
    if (rawJson is! Map) {
      return AppProxySettings.defaults();
    }
    final defaults = AppProxySettings.defaults();
    final mode = AppProxyModeJson.fromJson(rawJson['mode']);

    final rawProtocols = rawJson['protocols'];
    final protocols = <AppProxyProtocol>{};
    if (rawProtocols is List) {
      for (final entry in rawProtocols) {
        final parsed = AppProxyProtocolJson.tryFromJson(entry);
        if (parsed != null) {
          protocols.add(parsed);
        }
      }
    }
    final usableProtocols = protocols.isEmpty ? defaults.protocols : protocols;

    final host = rawJson['host'] is String
        ? (rawJson['host'] as String).trim()
        : defaults.host;
    final port = rawJson['port'] is int
        ? (rawJson['port'] as int).clamp(1, 65535)
        : (rawJson['port'] is String && int.tryParse(rawJson['port'] as String) != null
            ? int.parse(rawJson['port'] as String).clamp(1, 65535)
            : defaults.port);
    final authEnabled =
        rawJson['auth_enabled'] is bool ? rawJson['auth_enabled'] as bool : false;
    final username = rawJson['username'] is String
        ? (rawJson['username'] as String)
        : '';
    final password = rawJson['password'] is String
        ? (rawJson['password'] as String)
        : '';
    final rawExceptions = rawJson['exceptions'];
    final exceptions = <String>[];
    if (rawExceptions is List) {
      for (final entry in rawExceptions) {
        if (entry is String) {
          final trimmed = entry.trim();
          if (trimmed.isNotEmpty) {
            exceptions.add(trimmed);
          }
        }
      }
    }

    return AppProxySettings(
      mode: mode,
      protocols: usableProtocols,
      host: host,
      port: port,
      authEnabled: authEnabled,
      username: username,
      password: password,
      exceptions: List<String>.unmodifiable(exceptions),
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

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.jsonValue,
        'protocols':
            protocols.map((p) => p.jsonValue).toList(growable: false),
        'host': host,
        'port': port,
        'auth_enabled': authEnabled,
        'username': username,
        'password': password,
        'exceptions': List<String>.unmodifiable(exceptions),
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
  }) {
    return AppProxySettings(
      mode: mode ?? this.mode,
      protocols: protocols ?? this.protocols,
      host: host ?? this.host,
      port: port ?? this.port,
      authEnabled: authEnabled ?? this.authEnabled,
      username: username ?? this.username,
      password: password ?? this.password,
      exceptions: exceptions ?? this.exceptions,
    );
  }

  /// Convenience: stable string representation for debug prints. Hides
  /// the password.
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
        other.exceptions.length == exceptions.length &&
        _listEquals(other.exceptions, exceptions);
  }

  @override
  int get hashCode => Object.hash(
        mode,
        host,
        port,
        authEnabled,
        username,
        password,
        Object.hashAll(protocols),
        Object.hashAll(exceptions),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../model/app_proxy_settings.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

/// Resolves the host's HTTP/HTTPS proxy configuration so internal HTTP
/// clients (WebSearch / WebFetch and friends) can transparently follow
/// the user's system proxy — required for users whose only path to
/// `duckduckgo.com`, `github.com`, …, etc. goes through a local Clash /
/// V2Ray-style proxy.
///
/// Detection order (later wins; sources are merged so env overrides for
/// specific schemes don't lose the others):
///   1. Process environment (`HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` /
///      `NO_PROXY` and lowercase variants). Useful when launched from a
///      shell that already has the variables set.
///   2. macOS only: `scutil --proxy` output (the system-wide proxy
///      pane), so GUI launches that don't inherit shell env still pick
///      up the user's actual proxy.
///
/// Initialization is best-effort: any failure falls back to "no proxy"
/// without surfacing errors to the user.
class SystemProxyResolver {
  SystemProxyResolver._();

  static final SystemProxyResolver instance = SystemProxyResolver._();

  /// 来自设置中心的代理配置（模式 / 协议 / 主机 / 端口 / 鉴权 / 例外）。
  /// 默认值是 `automatic`，与历史行为兼容。
  AppProxySettings _settings = AppProxySettings.defaults();

  /// 自动模式下从环境变量与 `scutil --proxy` 解析出来的端点。
  String? _httpProxy; // host:port
  String? _httpsProxy;
  String? _socksProxy;
  final List<String> _noProxyHosts = <String>[];

  AppProxySettings get effectiveSettings => _settings;

  /// 来自设置中心的代理配置变更。立即生效——后续 `findProxyFor` 立刻
  /// 使用新配置。`settings.mode` 可能是 `manual` 或 `automatic`，本方法
  /// 都接受；命名沿用历史 API 但日志按实际 mode 输出，避免误导。
  void applyConfig(AppProxySettings settings) {
    _settings = settings;
  }

  /// Backwards-compatible alias for callers still on the old name.
  @Deprecated('Use applyConfig instead — accepts both manual & automatic')
  void applyManualConfig(AppProxySettings settings) => applyConfig(settings);

  /// True once [initialize] has run at least once. Until then, callers
  /// fall back to env-only detection synchronously (good enough for
  /// shell launches; the macOS scutil refresh kicks in shortly after).
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Best-effort discovery. Safe to call multiple times — each call
  /// re-reads env + scutil so callers can refresh on demand.
  Future<void> initialize() async {
    _resolveFromEnvironment();
    if (Platform.isMacOS) {
      await _resolveFromMacScutil();
    }
    _initialized = true;
  }

  void _resolveFromEnvironment() {
    final env = Platform.environment;
    String? pick(List<String> keys) {
      for (final key in keys) {
        final raw = env[key];
        if (raw != null && raw.trim().isNotEmpty) {
          return _stripScheme(raw.trim());
        }
      }
      return null;
    }

    _httpProxy = pick(<String>[
      'HTTP_PROXY',
      'http_proxy',
      'ALL_PROXY',
      'all_proxy',
    ]);
    _httpsProxy = pick(<String>[
      'HTTPS_PROXY',
      'https_proxy',
      'ALL_PROXY',
      'all_proxy',
    ]);
    _socksProxy = pick(<String>[
      'SOCKS_PROXY',
      'socks_proxy',
      'ALL_PROXY',
      'all_proxy',
    ]);

    final noProxy = env['NO_PROXY'] ?? env['no_proxy'] ?? '';
    _noProxyHosts
      ..clear()
      ..addAll(
        noProxy
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty),
      );
  }

  Future<void> _resolveFromMacScutil() async {
    final result = await runProcessWithTimeout(
      '/usr/sbin/scutil',
      <String>['--proxy'],
      timeout: const Duration(seconds: 3),
      tag: 'system_proxy',
    );
    if (result == null || result.exitCode != 0) {
      return;
    }
    try {
      final stdout = result.stdout?.toString() ?? '';
      final parsed = _parseScutilProxyDictionary(stdout);
      // Env wins only when scutil reports nothing for that scheme so a
      // user who explicitly set `https_proxy` in their shell still gets
      // their override — but a GUI launch where env is empty falls
      // through to scutil cleanly.
      _httpProxy ??= parsed.http;
      _httpsProxy ??= parsed.https;
      _socksProxy ??= parsed.socks;
      for (final host in parsed.exceptions) {
        final lower = host.toLowerCase();
        if (!_noProxyHosts.contains(lower)) {
          _noProxyHosts.add(lower);
        }
      }
    } catch (error, stack) {
      silentLog('system_proxy', 'parse_scutil', error, stack);
    }
  }

  /// Returns the `findProxy` directive string for the given URI, or
  /// `'DIRECT'` when no proxy applies. Mode-aware: 反映设置中心当前选择。
  String findProxyFor(Uri uri) {
    switch (_settings.mode) {
      case AppProxyMode.disabled:
        return 'DIRECT';
      case AppProxyMode.manual:
        return _findProxyManual(uri);
      case AppProxyMode.automatic:
        return _findProxyAutomatic(uri);
    }
  }

  String _findProxyManual(Uri uri) {
    if (_settings.host.trim().isEmpty || _settings.port <= 0) {
      return 'DIRECT';
    }
    if (_isExemptManual(uri.host)) {
      return 'DIRECT';
    }
    final scheme = uri.scheme.toLowerCase();
    final wantsHttp =
        scheme == 'http' && _settings.protocols.contains(AppProxyProtocol.http);
    final wantsHttps =
        scheme == 'https' &&
        _settings.protocols.contains(AppProxyProtocol.https);
    final wantsSocks = _settings.protocols.contains(AppProxyProtocol.socks);
    final endpoint = '${_settings.host}:${_settings.port}';
    if (wantsHttp || wantsHttps) {
      return 'PROXY $endpoint';
    }
    if (wantsSocks) {
      return 'SOCKS $endpoint';
    }
    return 'DIRECT';
  }

  String _findProxyAutomatic(Uri uri) {
    if (_isExempt(uri.host)) {
      return 'DIRECT';
    }
    final scheme = uri.scheme.toLowerCase();
    final picked = scheme == 'https'
        ? (_httpsProxy ?? _httpProxy)
        : (_httpProxy ?? _httpsProxy);
    if (picked != null && picked.isNotEmpty) {
      return 'PROXY $picked';
    }
    if (_socksProxy != null && _socksProxy!.isNotEmpty) {
      return 'SOCKS $_socksProxy';
    }
    return 'DIRECT';
  }

  bool _isExempt(String host) {
    if (host.isEmpty) return true;
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower == '127.0.0.1' || lower == '::1') {
      return true;
    }
    for (final pattern in _noProxyHosts) {
      if (_matchesExceptionPattern(lower, pattern)) return true;
    }
    return false;
  }

  bool _isExemptManual(String host) {
    if (host.isEmpty) return true;
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower == '127.0.0.1' || lower == '::1') {
      return true;
    }
    for (final pattern in _settings.exceptions) {
      if (_matchesExceptionPattern(lower, pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Builds an `http.Client` whose underlying [HttpClient] follows the
  /// resolved system proxy. Each created client is independent — callers
  /// may keep one long-lived instance per service.
  http.Client createHttpClient({
    Duration connectionTimeout = const Duration(seconds: 15),
  }) {
    return IOClient(createRawHttpClient(connectionTimeout: connectionTimeout));
  }

  /// Builds a raw `dart:io` [HttpClient] configured with the resolver's
  /// proxy + credentials. Useful for callers that need fine-grained
  /// control (cancellation via `close(force: true)`, response stream
  /// access, …) and can't use the higher-level `http.Client` wrapper.
  HttpClient createRawHttpClient({
    Duration connectionTimeout = const Duration(seconds: 15),
  }) {
    final inner = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..findProxy = findProxyFor;
    if (_settings.mode == AppProxyMode.manual &&
        _settings.authEnabled &&
        _settings.username.isNotEmpty &&
        _settings.host.isNotEmpty &&
        _settings.port > 0) {
      try {
        inner.addProxyCredentials(
          _settings.host,
          _settings.port,
          'Basic',
          HttpClientBasicCredentials(_settings.username, _settings.password),
        );
      } catch (error, stack) {
        silentLog('system_proxy', 'addProxyCredentials', error, stack);
      }
    }
    return inner;
  }
}

String _stripScheme(String raw) {
  final lower = raw.toLowerCase();
  for (final prefix in const <String>[
    'http://',
    'https://',
    'socks5://',
    'socks4://',
    'socks://',
  ]) {
    if (lower.startsWith(prefix)) {
      return raw.substring(prefix.length).replaceAll(RegExp(r'/+$'), '');
    }
  }
  return raw.replaceAll(RegExp(r'/+$'), '');
}

/// 通用例外匹配。支持：
///   * `*` —— 全匹配
///   * `/regex/` 或 `/regex/i` —— Dart [RegExp]
///   * `192.168.0.0/16` —— IPv4 CIDR（仅当 host 是 IPv4 字面量时）
///   * `*.example.com` —— 后缀 glob（含裸 apex `example.com`）
///   * `example.com` —— 精确或子域
@visibleForTesting
bool matchesProxyException(String host, String pattern) {
  return _matchesExceptionPattern(host.toLowerCase(), pattern.toLowerCase());
}

bool _matchesExceptionPattern(String lowerHost, String lowerPattern) {
  if (lowerPattern.isEmpty) return false;
  if (lowerPattern == '*') return true;

  // /regex/ or /regex/i
  if (lowerPattern.startsWith('/') && lowerPattern.length >= 2) {
    final lastSlash = lowerPattern.lastIndexOf('/');
    if (lastSlash > 0) {
      final body = lowerPattern.substring(1, lastSlash);
      final flags = lowerPattern.substring(lastSlash + 1);
      try {
        final regex = RegExp(body, caseSensitive: !flags.contains('i'));
        return regex.hasMatch(lowerHost);
      } catch (_) {
        return false;
      }
    }
  }

  // CIDR (IPv4)
  if (lowerPattern.contains('/')) {
    final cidr = _tryMatchIpv4Cidr(lowerHost, lowerPattern);
    if (cidr != null) return cidr;
  }

  // Glob *.suffix
  if (lowerPattern.startsWith('*.')) {
    final suffix = lowerPattern.substring(1); // ".example.com"
    if (lowerHost.endsWith(suffix)) return true;
    if (lowerHost == suffix.substring(1)) return true;
    return false;
  }

  if (lowerHost == lowerPattern) return true;
  if (lowerHost.endsWith('.$lowerPattern')) return true;
  return false;
}

bool? _tryMatchIpv4Cidr(String host, String pattern) {
  final slash = pattern.indexOf('/');
  if (slash <= 0) return null;
  final base = pattern.substring(0, slash);
  final maskStr = pattern.substring(slash + 1);
  final maskBits = int.tryParse(maskStr);
  if (maskBits == null || maskBits < 0 || maskBits > 32) return null;

  final baseBytes = _tryParseIpv4(base);
  if (baseBytes == null) return null;
  final hostBytes = _tryParseIpv4(host);
  if (hostBytes == null) return false;

  final baseInt = ByteData.sublistView(baseBytes).getUint32(0);
  final hostInt = ByteData.sublistView(hostBytes).getUint32(0);
  if (maskBits == 0) return true;
  final mask = ((1 << maskBits) - 1) << (32 - maskBits);
  return (baseInt & mask) == (hostInt & mask);
}

Uint8List? _tryParseIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final result = Uint8List(4);
  for (var i = 0; i < 4; i++) {
    final n = int.tryParse(parts[i]);
    if (n == null || n < 0 || n > 255) return null;
    result[i] = n;
  }
  return result;
}

class _ScutilProxyConfig {
  _ScutilProxyConfig({
    this.http,
    this.https,
    this.socks,
    List<String> exceptions = const <String>[],
  }) : exceptions = List<String>.from(exceptions);

  final String? http;
  final String? https;
  final String? socks;
  final List<String> exceptions;
}

/// Parse the indented block emitted by `scutil --proxy`.
///
/// Sample (truncated):
///
/// ```
/// <dictionary> {
///   ExceptionsList : <array> {
///     0 : *.local
///     1 : 169.254/16
///   }
///   HTTPEnable : 1
///   HTTPProxy : 127.0.0.1
///   HTTPPort : 7890
///   HTTPSEnable : 1
///   HTTPSProxy : 127.0.0.1
///   HTTPSPort : 7890
///   SOCKSEnable : 0
/// }
/// ```
_ScutilProxyConfig _parseScutilProxyDictionary(String stdout) {
  String? readKey(RegExp r) {
    final m = r.firstMatch(stdout);
    return m?.group(1)?.trim();
  }

  String? combine(String prefix) {
    final enable = readKey(RegExp('${prefix}Enable\\s*:\\s*(\\d+)'));
    if (enable != '1') return null;
    final host = readKey(RegExp('${prefix}Proxy\\s*:\\s*([^\\s\\n]+)'));
    if (host == null || host.isEmpty) return null;
    final port = readKey(RegExp('${prefix}Port\\s*:\\s*(\\d+)'));
    if (port == null || port.isEmpty) return host;
    return '$host:$port';
  }

  final exceptions = <String>[];
  final exMatch = RegExp(
    r'ExceptionsList\s*:\s*<array>\s*\{([\s\S]*?)\}',
  ).firstMatch(stdout);
  if (exMatch != null) {
    for (final line in exMatch.group(1)!.split('\n')) {
      final m = RegExp(r'^\s*\d+\s*:\s*(\S+)\s*$').firstMatch(line);
      if (m != null) {
        exceptions.add(m.group(1)!);
      }
    }
  }

  return _ScutilProxyConfig(
    http: combine('HTTP'),
    https: combine('HTTPS'),
    socks: combine('SOCKS'),
    exceptions: exceptions,
  );
}

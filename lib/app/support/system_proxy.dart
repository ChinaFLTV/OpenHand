import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

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

  String? _httpProxy; // host:port
  String? _httpsProxy;
  String? _socksProxy;
  final List<String> _noProxyHosts = <String>[];

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
    if (kDebugMode) {
      debugPrint(
        '[system_proxy] http=$_httpProxy https=$_httpsProxy '
        'socks=$_socksProxy noProxy=${_noProxyHosts.length}',
      );
    }
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

    _httpProxy = pick(<String>['HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy']);
    _httpsProxy = pick(<String>['HTTPS_PROXY', 'https_proxy', 'ALL_PROXY', 'all_proxy']);
    _socksProxy = pick(<String>['SOCKS_PROXY', 'socks_proxy', 'ALL_PROXY', 'all_proxy']);

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
  /// `'DIRECT'` when no proxy applies. Safe to call before [initialize]
  /// finishes — falls back to env-only detection.
  String findProxyFor(Uri uri) {
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
      if (pattern.isEmpty) continue;
      if (pattern == '*') return true;
      if (pattern.startsWith('*.')) {
        final suffix = pattern.substring(1);
        if (lower.endsWith(suffix)) return true;
      } else if (lower == pattern || lower.endsWith('.$pattern')) {
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
    final inner = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..findProxy = findProxyFor;
    return IOClient(inner);
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

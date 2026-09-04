import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../shared/net/loopback_hosts.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../model/app_proxy_settings.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

export '../../shared/net/loopback_hosts.dart'
    show isLoopbackHost, kLoopbackHosts;

/// 解析系统 HTTP/HTTPS 代理，供内部网络客户端透明复用。
///
/// 优先读取进程环境变量，再用 macOS `scutil --proxy` 补全缺失协议。
/// 探测失败时回退直连，不向用户暴露非关键错误。
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
  final OpenHandSingleFlight<void> _initializeFlight =
      OpenHandSingleFlight<void>();

  AppProxySettings get effectiveSettings => _settings;

  /// 应用设置中心的代理配置变更，并立即生效。
  void applyConfig(AppProxySettings settings) {
    if (_settings == settings) return;
    _settings = settings;
    _revision.value = _revision.value + 1;
  }

  /// 代理决策变更后的版本号，供依赖代理环境的资源重启。
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  ValueListenable<int> get revision => _revision;

  /// 是否已至少完成一次自动代理探测。
  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 自动模式下探测到的端点，优先级为 HTTPS、HTTP、SOCKS。
  String? get detectedAutomaticEndpoint {
    return _normalizedProxyEndpoint(_httpsProxy ?? _httpProxy ?? _socksProxy);
  }

  /// 供受管本地服务复用的 HTTP/HTTPS 路由快照。
  SystemProxyRouteSnapshot resolveRuntimeRoute() {
    String? httpProxy;
    String? httpsProxy;
    Iterable<String> exceptions = const <String>[];
    switch (_settings.mode) {
      case AppProxyMode.disabled:
        break;
      case AppProxyMode.manual:
        final proxy = _manualProxyUrl('http');
        final socks = _manualProxyUrl('socks5');
        if (_settings.protocols.contains(AppProxyProtocol.http)) {
          httpProxy = proxy;
        } else if (_settings.protocols.contains(AppProxyProtocol.socks)) {
          httpProxy = socks;
        }
        if (_settings.protocols.contains(AppProxyProtocol.https)) {
          httpsProxy = proxy;
        } else if (_settings.protocols.contains(AppProxyProtocol.socks)) {
          httpsProxy = socks;
        }
        exceptions = _settings.exceptions;
      case AppProxyMode.automatic:
        httpProxy = _automaticProxyUrl(_httpProxy ?? _httpsProxy, _socksProxy);
        httpsProxy = _automaticProxyUrl(_httpsProxy ?? _httpProxy, _socksProxy);
        exceptions = _noProxyHosts;
    }
    return SystemProxyRouteSnapshot(
      httpProxy: httpProxy,
      httpsProxy: httpsProxy,
      exceptions: List<String>.unmodifiable(exceptions),
    );
  }

  /// 自动模式探测端点拆分为 (host, port)；解析失败返回 null。
  ({String host, int port})? get detectedAutomaticHostPort {
    final raw = detectedAutomaticEndpoint;
    return raw == null ? null : _parseHostPortEndpoint(raw);
  }

  /// 探测自动代理；并发调用共享同一轮任务，完成后可再次刷新。
  Future<void> initialize() => _initializeFlight.run(_initialize);

  Future<void> _initialize() async {
    _resolveFromEnvironment();
    if (Platform.isMacOS) {
      await _resolveFromMacScutil();
    }
    _initialized = true;
    _revision.value = _revision.value + 1;
  }

  void _resolveFromEnvironment() {
    final env = Platform.environment;
    String? pickRaw(List<String> keys) {
      for (final key in keys) {
        final value = nullIfBlank(env[key]);
        if (value != null) return value;
      }
      return null;
    }

    _httpProxy = null;
    _httpsProxy = null;
    _socksProxy = null;
    final httpProxyRaw = pickRaw(<String>['HTTP_PROXY', 'http_proxy']);
    final httpsProxyRaw = pickRaw(<String>['HTTPS_PROXY', 'https_proxy']);
    final socksProxyRaw = pickRaw(<String>['SOCKS_PROXY', 'socks_proxy']);
    final allProxyRaw = pickRaw(<String>['ALL_PROXY', 'all_proxy']);
    final httpProxy = _normalizedProxyEndpoint(httpProxyRaw);
    final httpsProxy = _normalizedProxyEndpoint(httpsProxyRaw);
    if (_isSocksProxyValue(httpProxyRaw)) {
      _socksProxy = httpProxy;
    } else {
      _httpProxy = httpProxy;
    }
    if (_isSocksProxyValue(httpsProxyRaw)) {
      _socksProxy ??= httpsProxy;
    } else {
      _httpsProxy = httpsProxy;
    }
    _socksProxy ??= _normalizedProxyEndpoint(socksProxyRaw);
    final allProxy = _normalizedProxyEndpoint(allProxyRaw);
    if (allProxy != null) {
      if (_isSocksProxyValue(allProxyRaw)) {
        _socksProxy ??= allProxy;
      } else {
        _httpProxy ??= allProxy;
        _httpsProxy ??= allProxy;
      }
    }

    final noProxy = env['NO_PROXY'] ?? env['no_proxy'] ?? '';
    _noProxyHosts
      ..clear()
      ..addAll(splitTrimmedNonEmpty(noProxy).map((s) => s.toLowerCase()));
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
      // 环境变量优先，`scutil` 只补全缺失协议。
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
      silentLog('system_proxy', '解析 scutil 输出', error, stack);
    }
  }

  /// 返回指定地址的代理指令；无需代理时返回 `DIRECT`。
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
    final endpoint = _manualEndpoint;
    if (endpoint == null) {
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
    final picked = _normalizedProxyEndpoint(
      scheme == 'https'
          ? (_httpsProxy ?? _httpProxy)
          : (_httpProxy ?? _httpsProxy),
    );
    if (picked != null) {
      return 'PROXY $picked';
    }
    final socksProxy = _normalizedProxyEndpoint(_socksProxy);
    if (socksProxy != null) {
      return 'SOCKS $socksProxy';
    }
    return 'DIRECT';
  }

  bool _isExempt(String host) {
    if (host.isEmpty || isLoopbackHost(host)) return true;
    final lower = host.toLowerCase();
    for (final pattern in _noProxyHosts) {
      if (_matchesExceptionPattern(lower, pattern)) return true;
    }
    return false;
  }

  bool _isExemptManual(String host) {
    if (host.isEmpty || isLoopbackHost(host)) return true;
    final lower = host.toLowerCase();
    for (final pattern in _settings.exceptions) {
      if (_matchesExceptionPattern(lower, pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// 创建遵循当前代理设置的独立 HTTP 客户端。
  http.Client createHttpClient({
    Duration connectionTimeout = const Duration(seconds: 15),
    String? userAgent,
  }) {
    return IOClient(
      createRawHttpClient(
        connectionTimeout: connectionTimeout,
        userAgent: userAgent,
      ),
    );
  }

  /// 将当前代理配置转换为子进程环境变量。无可用代理时返回空映射，
  /// 同时提供大小写两种键名以兼容不同 CLI。
  Map<String, String> resolveSubprocessEnvironment({
    bool includeNoProxy = true,
  }) {
    String? httpEndpoint;
    String? httpsEndpoint;
    String? socksEndpoint;
    final exceptions = <String>{};

    switch (_settings.mode) {
      case AppProxyMode.disabled:
        return const <String, String>{};
      case AppProxyMode.manual:
        final proxy = _manualProxyUrl('http');
        final socks = _manualProxyUrl('socks5');
        if (proxy == null || socks == null) {
          return const <String, String>{};
        }
        final wantsHttp = _settings.protocols.contains(AppProxyProtocol.http);
        final wantsHttps = _settings.protocols.contains(AppProxyProtocol.https);
        final wantsSocks = _settings.protocols.contains(AppProxyProtocol.socks);
        if (wantsHttp) httpEndpoint = proxy;
        if (wantsHttps) httpsEndpoint = proxy;
        if (wantsSocks) socksEndpoint = socks;
        for (final pattern in _settings.exceptions) {
          final trimmed = nullIfBlank(pattern);
          if (trimmed != null) exceptions.add(trimmed);
        }
      case AppProxyMode.automatic:
        httpEndpoint = _normalizedProxyEndpoint(_httpProxy);
        httpsEndpoint = _normalizedProxyEndpoint(_httpsProxy);
        socksEndpoint = _normalizedProxyEndpoint(_socksProxy);
        for (final pattern in _noProxyHosts) {
          if (pattern.isNotEmpty) exceptions.add(pattern);
        }
    }

    // 未单独配置 HTTP 或 HTTPS 时，复用另一个 HTTP 端点。
    if (httpEndpoint == null && httpsEndpoint != null) {
      httpEndpoint = httpsEndpoint;
    } else if (httpsEndpoint == null && httpEndpoint != null) {
      httpsEndpoint = httpEndpoint;
    }

    final result = <String, String>{};
    if (httpEndpoint != null && httpEndpoint.isNotEmpty) {
      final url = httpEndpoint.contains('://')
          ? httpEndpoint
          : 'http://$httpEndpoint';
      result['HTTP_PROXY'] = url;
      result['http_proxy'] = url;
    }
    if (httpsEndpoint != null && httpsEndpoint.isNotEmpty) {
      final url = httpsEndpoint.contains('://')
          ? httpsEndpoint
          : 'http://$httpsEndpoint';
      result['HTTPS_PROXY'] = url;
      result['https_proxy'] = url;
    }
    if (socksEndpoint != null && socksEndpoint.isNotEmpty) {
      final url = socksEndpoint.contains('://')
          ? socksEndpoint
          : 'socks5://$socksEndpoint';
      result['ALL_PROXY'] = url;
      result['all_proxy'] = url;
    } else if (httpEndpoint != null && httpEndpoint.isNotEmpty) {
      result['ALL_PROXY'] = result['HTTP_PROXY']!;
      result['all_proxy'] = result['HTTP_PROXY']!;
    }

    if (includeNoProxy && result.isNotEmpty) {
      // 例外清单中的正则 / CIDR 形式 CLI 无法识别，仅保留普通主机/域名/glob。
      final compatibleHosts = <String>[];
      for (final pattern in exceptions) {
        if (pattern.startsWith('/') || pattern.contains('/')) {
          continue; // 跳过 regex 与 CIDR
        }
        compatibleHosts.add(pattern);
      }
      // 加上常见本机 host 让 CLI 默认绕开。
      compatibleHosts.addAll(kLoopbackHosts);
      final dedup = LinkedHashSet<String>.from(compatibleHosts);
      final joined = dedup.join(',');
      result['NO_PROXY'] = joined;
      result['no_proxy'] = joined;
    }

    return result;
  }

  /// 创建支持代理、凭据和强制取消的底层 HTTP 客户端。
  HttpClient createRawHttpClient({
    Duration connectionTimeout = const Duration(seconds: 15),
    String? userAgent,
  }) {
    final inner = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..findProxy = findProxyFor;
    if (userAgent?.trim().isNotEmpty ?? false) {
      inner.userAgent = userAgent!.trim();
    }
    final manualHostPort = _manualHostPort;
    final username = nullIfBlank(_settings.username);
    if (_settings.mode == AppProxyMode.manual &&
        _settings.authEnabled &&
        username != null &&
        manualHostPort != null) {
      try {
        inner.addProxyCredentials(
          manualHostPort.host,
          manualHostPort.port,
          'Basic',
          HttpClientBasicCredentials(username, _settings.password),
        );
      } catch (error, stack) {
        silentLog('system_proxy', '添加代理凭据', error, stack);
      }
    }
    return inner;
  }

  ({String host, int port})? get _manualHostPort {
    final rawHost = nullIfBlank(_settings.host);
    final port = validTcpPort(_settings.port);
    if (rawHost == null || port == null) return null;
    return (host: _withoutIpv6Brackets(rawHost), port: port);
  }

  String? get _manualEndpoint {
    final hostPort = _manualHostPort;
    return hostPort == null
        ? null
        : _proxyAuthority(hostPort.host, hostPort.port);
  }

  String? _manualProxyUrl(String scheme) {
    final hostPort = _manualHostPort;
    if (hostPort == null) return null;
    var userInfo = '';
    final username = nullIfBlank(_settings.username);
    if (_settings.authEnabled && username != null) {
      userInfo =
          '${Uri.encodeComponent(username)}:'
          '${Uri.encodeComponent(_settings.password)}';
    }
    return Uri(
      scheme: scheme,
      userInfo: userInfo,
      host: hostPort.host,
      port: hostPort.port,
    ).toString();
  }
}

class SystemProxyRouteSnapshot {
  const SystemProxyRouteSnapshot({
    required this.httpProxy,
    required this.httpsProxy,
    required this.exceptions,
  });

  final String? httpProxy;
  final String? httpsProxy;
  final List<String> exceptions;

  bool get hasProxy => httpProxy != null || httpsProxy != null;

  Map<String, Object?> toJson() => <String, Object?>{
    if (httpProxy != null) 'http': httpProxy,
    if (httpsProxy != null) 'https': httpsProxy,
    if (exceptions.isNotEmpty) 'exceptions': exceptions,
  };
}

String? _automaticProxyUrl(String? endpoint, String? socksEndpoint) {
  final proxy = _normalizedProxyEndpoint(endpoint);
  if (proxy != null) return 'http://$proxy';
  final socks = _normalizedProxyEndpoint(socksEndpoint);
  return socks == null ? null : 'socks5://$socks';
}

String? _normalizedProxyEndpoint(String? raw) {
  final trimmed = nullIfBlank(raw);
  if (trimmed == null) return null;
  return nullIfBlank(_stripScheme(trimmed));
}

bool _isSocksProxyValue(String? raw) {
  final value = raw?.trim().toLowerCase();
  return value != null &&
      (value.startsWith('socks://') ||
          value.startsWith('socks4://') ||
          value.startsWith('socks5://'));
}

String _stripScheme(String raw) {
  final trimmed = raw.trim();
  final lower = trimmed.toLowerCase();
  for (final prefix in const <String>[
    'http://',
    'https://',
    'socks5://',
    'socks4://',
    'socks://',
  ]) {
    if (lower.startsWith(prefix)) {
      return trimmed.substring(prefix.length).replaceAll(RegExp(r'/+$'), '');
    }
  }
  return trimmed.replaceAll(RegExp(r'/+$'), '');
}

({String host, int port})? _parseHostPortEndpoint(String raw) {
  final idx = raw.lastIndexOf(':');
  if (idx <= 0 || idx == raw.length - 1) return null;
  final host = nullIfBlank(raw.substring(0, idx));
  final port = tcpPortFromValue(raw.substring(idx + 1));
  if (host == null || port == null) return null;
  return (host: _withoutIpv6Brackets(host), port: port);
}

String _withoutIpv6Brackets(String host) {
  final value = host.trim();
  return value.length >= 2 && value.startsWith('[') && value.endsWith(']')
      ? value.substring(1, value.length - 1)
      : value;
}

String _proxyAuthority(String host, int port) {
  final normalized = _withoutIpv6Brackets(host);
  return '${normalized.contains(':') ? '[$normalized]' : normalized}:$port';
}

/// 通用例外匹配。支持：
///   * `*` —— 全匹配
///   * `/regex/` 或 `/regex/i` —— Dart [RegExp]
///   * `192.168.0.0/16` —— IPv4 CIDR（仅当 host 是 IPv4 字面量时）
///   * `*.example.com` —— 后缀 glob（含裸 apex `example.com`）
///   * `example.com` —— 精确或子域
bool _matchesExceptionPattern(String lowerHost, String lowerPattern) {
  if (lowerPattern.isEmpty) return false;
  if (lowerPattern == '*') return true;

  // 正则表达式。
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

  // IPv4 CIDR。
  if (lowerPattern.contains('/')) {
    final cidr = _tryMatchIpv4Cidr(lowerHost, lowerPattern);
    if (cidr != null) return cidr;
  }

  // 域名后缀通配符。
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

/// 解析 `scutil --proxy` 输出的缩进字典。
///
/// 示例：
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
    final host = nullIfBlank(
      readKey(RegExp('${prefix}Proxy\\s*:\\s*([^\\s\\n]+)')),
    );
    if (host == null) return null;
    final port = validTcpPort(
      optionalIntFromValue(readKey(RegExp('${prefix}Port\\s*:\\s*(\\d+)'))),
    );
    return port == null ? host : _proxyAuthority(host, port);
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

// 代理连通性诊断控制台。按时间线展示 URL 解析、代理决策、DNS、TCP、
// HTTPS 请求/响应等关键事件；弹窗动画由 [showAnimatedDialog] 统一控制。
part of 'settings_view.dart';

class _ProxyTestOutcome {
  const _ProxyTestOutcome({required this.succeeded, required this.summary});

  final bool succeeded;
  final String summary;
}

// 代理诊断控制台固定色板：绿/红/琥珀/天蓝/灰，与主题主色解耦，
// 保证成功/失败/运行中的辨识度不受预设主色干扰。
const Color _kProxyTestAmber = Color(0xFFFCD34D);
const Color _kProxyTestAmberDark = Color(0xFFFACC15);
const Color _kProxyTestRed300 = Color(0xFFFCA5A5);
const Color _kProxyTestSky300 = Color(0xFF7DD3FC);
const Color _kProxyTestGreen = Color(0xFF8AE234);
const Color _kProxyTestGray = Color(0xFF6B7280);
const Color _kProxyTestLightGray = Color(0xFFE5E7EB);
const Color _kProxyTestLightGreen = Color(0xFF86EFAC);
const Color _kProxyTestNeutralGray = Color(0xFF9CA3AF);

enum _ProxyTestLogLevel { head, info, ok, warn, err, debug }

class _ProxyTestLogEntry {
  _ProxyTestLogEntry({
    required this.level,
    required this.tag,
    required this.body,
    required this.elapsedMs,
  });

  final _ProxyTestLogLevel level;
  final String tag;
  final String body;
  final int elapsedMs;
}

class _ProxyTestConsoleDialog extends StatefulWidget {
  const _ProxyTestConsoleDialog({
    required this.endpoint,
    required this.proxySettings,
  });

  final Uri endpoint;
  final AppProxySettings proxySettings;

  @override
  State<_ProxyTestConsoleDialog> createState() =>
      _ProxyTestConsoleDialogState();
}

class _ProxyTestConsoleDialogState extends State<_ProxyTestConsoleDialog>
    with SingleTickerProviderStateMixin {
  final List<_ProxyTestLogEntry> _entries = <_ProxyTestLogEntry>[];
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final Stopwatch _totalStopwatch = Stopwatch();
  late final AnimationController _cursorBlinkController;
  HttpClient? _activeHttpClient;
  int _diagnosticGeneration = 0;

  // 记录上一段 head 日志的 tag 与耗时，供顶部 chip 展示热点耗时。
  final Map<String, int> _sectionDurations = <String, int>{};
  String? _currentSectionTag;
  int _currentSectionStartMs = 0;

  bool _running = true;
  bool _finishedSucceeded = false;
  String? _finalSummary;
  final ValueNotifier<int> _completionPulse = ValueNotifier<int>(0);
  bool _selectionHeld = false;
  List<_ProxyTestLogEntry>? _selectionSnapshot;
  bool _selectionSnapshotRunning = false;
  bool _selectionUpdateScheduled = false;
  bool _pendingSelectionHeld = false;
  List<_ProxyTestLogEntry>? _pendingSelectionSnapshot;
  bool _pendingSelectionRunning = false;

  // head 是阶段锚点，永远不参与底部等级过滤。
  // 单段 DNS/TCP/TLS 超过该阈值时标记为慢路径。
  final Set<_ProxyTestLogLevel> _hiddenLevels = <_ProxyTestLogLevel>{};
  bool _maximized = false;
  static const int _slowSectionThresholdMs = 50;
  static const int _maxHttpBodyProbeBytes = 64 * kBytesPerKiB;
  static const Duration _networkInterfaceTimeout = Duration(seconds: 2);
  static const Duration _dnsLookupTimeout = Duration(seconds: 5);
  static const Duration _reverseDnsLookupTimeout = Duration(seconds: 3);
  static const Duration _tcpConnectTimeout = Duration(seconds: 6);
  static const Duration _tlsHandshakeTimeout = Duration(seconds: 8);
  static const Duration _httpConnectionTimeout = Duration(seconds: 8);
  static const Duration _httpRequestTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    // 600 ms blink 周期让繁忙状态的光标反馈更明确。
    _cursorBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _totalStopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runDiagnostics();
    });
  }

  @override
  void dispose() {
    _diagnosticGeneration += 1;
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    _totalStopwatch.stop();
    _cursorBlinkController.dispose();
    _scrollController.dispose();
    _completionPulse.dispose();
    super.dispose();
  }

  void _log(_ProxyTestLogLevel level, String tag, String body) {
    if (!mounted) return;
    final nowMs = _totalStopwatch.elapsedMilliseconds;
    if (level == _ProxyTestLogLevel.head) {
      _finalizeCurrentSection(nowMs);
      _currentSectionTag = tag;
      _currentSectionStartMs = nowMs;
    }
    setState(() {
      _entries.add(
        _ProxyTestLogEntry(
          level: level,
          tag: tag,
          body: body,
          elapsedMs: nowMs,
        ),
      );
    });
    _scrollGuard.scheduleFollowToBottom(_scrollController, animated: true);
  }

  List<_ProxyTestLogEntry> _visibleLogEntries() {
    return _entries
        .where(
          (entry) =>
              entry.level == _ProxyTestLogLevel.head ||
              !_hiddenLevels.contains(entry.level),
        )
        .toList(growable: false);
  }

  void _queueSelectionUpdate(
    bool held, {
    List<_ProxyTestLogEntry>? snapshot,
    bool running = false,
  }) {
    _pendingSelectionHeld = held;
    _pendingSelectionSnapshot = snapshot;
    _pendingSelectionRunning = running;
    if (_selectionUpdateScheduled) return;
    _selectionUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionUpdateScheduled = false;
      if (!mounted) return;
      final nextHeld = _pendingSelectionHeld;
      final nextSnapshot = _pendingSelectionSnapshot;
      final nextRunning = _pendingSelectionRunning;
      _pendingSelectionSnapshot = null;
      if (_selectionHeld == nextHeld &&
          (nextHeld || _selectionSnapshot == null)) {
        return;
      }
      setState(() {
        _selectionHeld = nextHeld;
        _selectionSnapshot = nextHeld ? nextSnapshot : null;
        _selectionSnapshotRunning = nextHeld && nextRunning;
      });
    });
  }

  void _handleConsoleSelectionChanged(SelectedContent? content) {
    final hasContent = content?.plainText.trim().isNotEmpty ?? false;
    if (hasContent) {
      // 选区存在期间冻结日志快照，避免诊断输出和等级过滤同时修改列表。
      _queueSelectionUpdate(
        true,
        snapshot: _visibleLogEntries(),
        running: _running,
      );
    } else if (_selectionHeld || _pendingSelectionHeld) {
      _queueSelectionUpdate(false);
    }
  }

  void _finalizeCurrentSection(int nowMs) {
    final tag = _currentSectionTag;
    if (tag == null) return;
    final dur = nowMs - _currentSectionStartMs;
    if (dur <= 0) return;
    _sectionDurations[tag] = math.max(_sectionDurations[tag] ?? 0, dur);
  }

  MapEntry<String, int>? _slowestSection() {
    if (_sectionDurations.isEmpty) return null;
    MapEntry<String, int>? slowest;
    for (final e in _sectionDurations.entries) {
      if (slowest == null || e.value > slowest.value) {
        slowest = e;
      }
    }
    return slowest;
  }

  Future<void> _runDiagnostics() async {
    final generation = ++_diagnosticGeneration;
    final l10n = AppLocalizations.of(context)!;
    final uri = widget.endpoint;
    final settings = widget.proxySettings;
    final resolver = SystemProxyResolver.instance;

    HttpClient? httpClient;
    MonotonicDeadline? httpDeadline;
    var ok = false;
    String summary;
    try {
      _log(_ProxyTestLogLevel.head, '探测', '════ 代理连通性诊断 ════');
      _log(_ProxyTestLogLevel.info, '探测', '目标 = $uri');
      _log(
        _ProxyTestLogLevel.debug,
        '探测',
        '协议=${uri.scheme}  主机=${uri.host}  端口=${uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80)}  路径=${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
      );

      _log(_ProxyTestLogLevel.head, '配置', '────────  代理配置  ────────');
      _log(
        _ProxyTestLogLevel.info,
        '配置',
        '模式 = ${_describeMode(settings.mode)}',
      );
      if (settings.mode == AppProxyMode.manual) {
        final protos = settings.protocols.map((p) => p.name).join(',');
        _log(_ProxyTestLogLevel.info, '配置', '协议 = [$protos]');
        _log(
          _ProxyTestLogLevel.info,
          '配置',
          '端点 = ${settings.host.isEmpty ? '<空>' : settings.host}:${settings.port}',
        );
        if (settings.authEnabled) {
          final maskedPwd = settings.password.isEmpty
              ? '<空>'
              : '*' * settings.password.length;
          _log(
            _ProxyTestLogLevel.info,
            '配置',
            '认证 = 开启  用户="${settings.username}"  密码=$maskedPwd',
          );
        } else {
          _log(_ProxyTestLogLevel.info, '配置', '认证 = 关闭');
        }
        _log(
          _ProxyTestLogLevel.info,
          '配置',
          '例外规则 = ${settings.exceptions.length} 条',
        );
      }

      _log(_ProxyTestLogLevel.head, '路由', '────────  代理解析  ────────');
      final via = resolver.findProxyFor(uri);
      _log(_ProxyTestLogLevel.ok, '路由', '结果 = "$via"');
      final useProxy = via.startsWith('PROXY ');
      final viaLabel = useProxy
          ? l10n.proxyTestVerdictProxy(via.substring('PROXY '.length).trim())
          : l10n.proxyTestVerdictDirect;

      // 解析首个实际连接的主机和端口。
      String hopHost;
      int hopPort;
      if (useProxy) {
        final spec = via.substring('PROXY '.length).trim();
        final colon = spec.lastIndexOf(':');
        final parsedPort = colon <= 0
            ? null
            : int.tryParse(spec.substring(colon + 1));
        if (!isValidPort(parsedPort)) {
          throw FormatException('代理指令格式无效："$via"');
        }
        hopHost = spec.substring(0, colon);
        hopPort = parsedPort!;
        _log(
          _ProxyTestLogLevel.info,
          '路由',
          '首跳 -> 代理@$hopHost:$hopPort（目标主机交由代理解析）',
        );
      } else {
        hopHost = uri.host;
        hopPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
        _log(_ProxyTestLogLevel.info, '路由', '首跳 -> 直连@$hopHost:$hopPort');
      }

      // 枚举本地网卡，辅助判断分流链路。
      _log(_ProxyTestLogLevel.head, '网卡', '────────  本地网卡  ────────');
      try {
        final ifaces = await NetworkInterface.list().timeout(
          _networkInterfaceTimeout,
        );
        if (!mounted || generation != _diagnosticGeneration) return;
        if (ifaces.isEmpty) {
          _log(_ProxyTestLogLevel.warn, '网卡', '<未发现活动的非回环网卡>');
        } else {
          for (final iface in ifaces) {
            final v4 = iface.addresses
                .where((a) => a.type == InternetAddressType.IPv4)
                .map((a) => a.address)
                .toList();
            final v6 = iface.addresses
                .where((a) => a.type == InternetAddressType.IPv6)
                .map((a) => a.address)
                .toList();
            _log(
              _ProxyTestLogLevel.info,
              '网卡',
              '${iface.name}  IPv4=[${v4.join(",")}]  IPv6=[${v6.length} 个地址]',
            );
          }
        }
      } catch (error, stack) {
        silentLog('settings_proxy_test_dialog', '枚举本地网卡', error, stack);
        if (!mounted || generation != _diagnosticGeneration) return;
        _log(
          _ProxyTestLogLevel.warn,
          '网卡',
          userFailureMessage(error, fallback: '枚举失败。'),
        );
      }

      // 分别解析 DNS A 与 AAAA 记录。
      _log(_ProxyTestLogLevel.head, 'DNS', '────────  解析 $hopHost  ────────');
      InternetAddress? selectedAddr;
      for (final family in const <InternetAddressType>[
        InternetAddressType.IPv4,
        InternetAddressType.IPv6,
      ]) {
        final famName = family == InternetAddressType.IPv4 ? 'A' : 'AAAA';
        final dnsStart = _totalStopwatch.elapsedMilliseconds;
        try {
          final addrs = await InternetAddress.lookup(
            hopHost,
            type: family,
          ).timeout(_dnsLookupTimeout);
          if (!mounted || generation != _diagnosticGeneration) return;
          final dnsMs = _totalStopwatch.elapsedMilliseconds - dnsStart;
          if (addrs.isEmpty) {
            _log(
              _ProxyTestLogLevel.debug,
              'DNS',
              '$famName -> <无记录>（${dnsMs}ms）',
            );
          } else {
            for (final addr in addrs.take(4)) {
              _log(
                _ProxyTestLogLevel.ok,
                'DNS',
                '$famName -> ${addr.address}（${dnsMs}ms）',
              );
            }
            if (addrs.length > 4) {
              _log(
                _ProxyTestLogLevel.debug,
                'DNS',
                '另有 ${addrs.length - 4} 条 $famName 记录',
              );
            }
            selectedAddr ??= addrs.first;
          }
        } on TimeoutException {
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.warn,
            'DNS',
            '$famName 解析超时（${_dnsLookupTimeout.inMilliseconds}ms）',
          );
        } catch (error, stack) {
          silentLog(
            'settings_proxy_test_dialog',
            '解析 DNS $famName 记录',
            error,
            stack,
          );
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.warn,
            'DNS',
            userFailureMessage(error, fallback: '$famName 解析失败。'),
          );
        }
      }
      if (selectedAddr != null) {
        final preferredFamily = selectedAddr.type == InternetAddressType.IPv6
            ? 'IPv6 (AAAA)'
            : 'IPv4 (A)';
        _log(_ProxyTestLogLevel.info, 'DNS', '首选地址族 = $preferredFamily（首条响应）');
        // 对首选地址执行反向 DNS（PTR）解析。
        try {
          final ptr = await selectedAddr.reverse().timeout(
            _reverseDnsLookupTimeout,
          );
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.ok,
            'PTR',
            '${selectedAddr.address} <- ${ptr.host}',
          );
        } on TimeoutException {
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.debug,
            'PTR',
            '${selectedAddr.address} <- <${_reverseDnsLookupTimeout.inMilliseconds}ms 超时>',
          );
        } catch (error, stack) {
          silentLog('settings_proxy_test_dialog', '执行反向 DNS 解析', error, stack);
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.debug,
            'PTR',
            '${selectedAddr.address} <- <不可用>',
          );
        }
      } else {
        _log(_ProxyTestLogLevel.warn, 'DNS', '未解析到可用地址');
      }
      // 执行原始 TCP 探测。
      _log(_ProxyTestLogLevel.head, 'TCP', '────────  套接字连接  ────────');
      final tcpStart = _totalStopwatch.elapsedMilliseconds;
      Socket? socket;
      try {
        final connected = await Socket.connect(
          hopHost,
          hopPort,
          timeout: _tcpConnectTimeout,
        );
        socket = connected;
        if (!mounted || generation != _diagnosticGeneration) {
          return;
        }
        final tcpMs = _totalStopwatch.elapsedMilliseconds - tcpStart;
        _log(
          _ProxyTestLogLevel.ok,
          'TCP',
          '握手成功  远端=${connected.remoteAddress.address}:${connected.remotePort}  本地=${connected.address.address}:${connected.port}  往返=${tcpMs}ms',
        );
      } on SocketException catch (e) {
        if (!mounted || generation != _diagnosticGeneration) return;
        _log(
          _ProxyTestLogLevel.err,
          'TCP',
          '连接失败：${e.message}${e.osError == null ? '' : '（错误码=${e.osError!.errorCode}）'}',
        );
        rethrow;
      } on TimeoutException {
        if (!mounted || generation != _diagnosticGeneration) return;
        _log(
          _ProxyTestLogLevel.err,
          'TCP',
          '连接超时（${_tcpConnectTimeout.inMilliseconds}ms）',
        );
        rethrow;
      } finally {
        socket?.destroy();
      }

      // 仅直连 HTTPS 时单独探测 TLS；代理模式下握手发生在 CONNECT 隧道内，
      // 由后续 HttpClient 请求统一验证。
      if (!useProxy && uri.scheme == 'https') {
        _log(_ProxyTestLogLevel.head, 'TLS', '────────  安全套接字握手  ────────');
        final tlsStart = _totalStopwatch.elapsedMilliseconds;
        SecureSocket? secure;
        try {
          final connected = await SecureSocket.connect(
            hopHost,
            hopPort,
            timeout: _tlsHandshakeTimeout,
            supportedProtocols: const <String>['h2', 'http/1.1'],
          );
          secure = connected;
          if (!mounted || generation != _diagnosticGeneration) {
            return;
          }
          final tlsMs = _totalStopwatch.elapsedMilliseconds - tlsStart;
          _log(
            _ProxyTestLogLevel.ok,
            'TLS',
            '握手成功  ALPN=${connected.selectedProtocol ?? "<无>"}  往返=${tlsMs}ms',
          );
          final cert = connected.peerCertificate;
          if (cert != null) {
            _log(
              _ProxyTestLogLevel.info,
              'TLS',
              '证书主题 = ${cert.subject.replaceAll("\n", " / ").trim()}',
            );
            _log(
              _ProxyTestLogLevel.info,
              'TLS',
              '证书颁发者 = ${cert.issuer.replaceAll("\n", " / ").trim()}',
            );
            _log(
              _ProxyTestLogLevel.debug,
              'TLS',
              '证书有效期 = ${cert.startValidity.toIso8601String()} -> ${cert.endValidity.toIso8601String()}',
            );
          } else {
            _log(_ProxyTestLogLevel.warn, 'TLS', '对端证书 = <空>（异常）');
          }
        } on HandshakeException catch (e) {
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(_ProxyTestLogLevel.err, 'TLS', '握手失败：${e.message}');
          rethrow;
        } on TimeoutException {
          if (!mounted || generation != _diagnosticGeneration) return;
          _log(
            _ProxyTestLogLevel.err,
            'TLS',
            '握手超时（${_tlsHandshakeTimeout.inMilliseconds}ms）',
          );
          rethrow;
        } finally {
          secure?.destroy();
        }
      } else if (useProxy && uri.scheme == 'https') {
        _log(
          _ProxyTestLogLevel.debug,
          'TLS',
          '已跳过：TLS 握手将通过代理 CONNECT 隧道进行，并由 HTTP 探测验证',
        );
      }

      // 使用 HttpClient 验证 TLS、CONNECT 与正向代理语义。
      _log(_ProxyTestLogLevel.head, 'HTTP', '────────  请求  ────────');
      httpClient = resolver.createRawHttpClient(
        connectionTimeout: _httpConnectionTimeout,
      );
      _activeHttpClient = httpClient;
      _log(
        _ProxyTestLogLevel.info,
        'HTTP',
        '> GET ${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1',
      );
      _log(
        _ProxyTestLogLevel.info,
        'HTTP',
        '> Host: ${uri.host}${uri.hasPort ? ':${uri.port}' : ''}',
      );
      _log(
        _ProxyTestLogLevel.info,
        'HTTP',
        '> User-Agent: OpenHand-ProxyDiag/1.0',
      );
      _log(_ProxyTestLogLevel.info, 'HTTP', '> Accept: */*');

      final httpStart = _totalStopwatch.elapsedMilliseconds;
      httpDeadline = MonotonicDeadline(
        _httpRequestTimeout,
        timeoutMessage: 'HTTP 探测超过总时限。',
      );
      final request = await httpClient
          .getUrl(uri)
          .timeout(httpDeadline.remaining());
      if (!mounted || generation != _diagnosticGeneration) return;
      request.headers.set('User-Agent', 'OpenHand-ProxyDiag/1.0');
      request.headers.set('Accept', '*/*');
      final response = await request.close().timeout(httpDeadline.remaining());
      if (!mounted || generation != _diagnosticGeneration) return;
      final ttfb = _totalStopwatch.elapsedMilliseconds - httpStart;
      _log(
        _ProxyTestLogLevel.ok,
        'HTTP',
        '< HTTP/${response.persistentConnection ? '1.1' : '1.0'} ${response.statusCode} ${response.reasonPhrase}',
      );
      response.headers.forEach((name, values) {
        for (final v in values) {
          _log(_ProxyTestLogLevel.debug, 'HTTP', '< $name: $v');
        }
      });
      final remainingHttpBudget = httpDeadline.remaining();
      final bodyResult = await readBoundedByteStreamPrefix(
        response,
        maxBytes: _maxHttpBodyProbeBytes,
        idleTimeout: remainingHttpBudget,
        totalTimeout: remainingHttpBudget,
      );
      if (!mounted || generation != _diagnosticGeneration) return;
      final bodyBytes = bodyResult.bytes.length;
      _log(
        _ProxyTestLogLevel.info,
        'HTTP',
        '首字节=${ttfb}ms  正文=$bodyBytes${bodyResult.truncated ? '+' : ''} 字节  声明长度=${response.contentLength}',
      );

      ok = response.statusCode >= 200 && response.statusCode < 400;
      summary = ok
          ? l10n.proxyTestSuccess(_totalStopwatch.elapsedMilliseconds, viaLabel)
          : l10n.proxyTestFailure('HTTP ${response.statusCode}');
    } catch (error, stack) {
      if (!mounted || generation != _diagnosticGeneration) return;
      silentLog('settings_proxy_test_dialog', '执行连通性测试', error, stack);
      ok = false;
      final detail = userFailureMessage(error, fallback: '连通性测试失败。');
      summary = l10n.proxyTestFailure(detail);
      _log(_ProxyTestLogLevel.err, '错误', detail);
    } finally {
      httpDeadline?.stop();
      if (identical(_activeHttpClient, httpClient)) {
        _activeHttpClient = null;
      }
      try {
        httpClient?.close(force: true);
      } catch (error, stack) {
        silentLog('settings_proxy_test_dialog', '关闭 HTTP 客户端', error, stack);
      }
    }
    if (!mounted || generation != _diagnosticGeneration) return;
    _totalStopwatch.stop();
    _finalizeCurrentSection(_totalStopwatch.elapsedMilliseconds);
    _log(
      ok ? _ProxyTestLogLevel.ok : _ProxyTestLogLevel.err,
      '完成',
      '════ ${ok ? '成功' : '失败'}  总耗时=${_totalStopwatch.elapsedMilliseconds}ms ════',
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _finishedSucceeded = ok;
      _finalSummary = summary;
    });
    _completionPulse.value = _completionPulse.value + 1;
    _cursorBlinkController.stop();
  }

  String _describeMode(AppProxyMode mode) {
    switch (mode) {
      case AppProxyMode.disabled:
        return '禁用';
      case AppProxyMode.automatic:
        return '自动（系统）';
      case AppProxyMode.manual:
        return '手动';
    }
  }

  Future<void> _copyLogs() async {
    final buffer = StringBuffer();
    for (final entry in _entries) {
      buffer.writeln(_formatEntryAsPlainText(entry));
    }
    await copyOpenHandTextToClipboard(
      logTag: 'settings',
      context: context,
      text: buffer.toString(),
      successMessage: AppLocalizations.of(context)!.proxyTestConsoleCopied,
      logAction: '复制代理测试日志',
      successDuration: const Duration(milliseconds: 1400),
    );
  }

  String _formatEntryAsPlainText(_ProxyTestLogEntry e) {
    final ts = (e.elapsedMs / 1000).toStringAsFixed(3).padLeft(7);
    final lvl = switch (e.level) {
      _ProxyTestLogLevel.head => '阶段',
      _ProxyTestLogLevel.info => '信息',
      _ProxyTestLogLevel.ok => '成功',
      _ProxyTestLogLevel.warn => '警告',
      _ProxyTestLogLevel.err => '错误',
      _ProxyTestLogLevel.debug => '调试',
    }.padRight(5);
    return '[+${ts}s] $lvl ${e.tag.padRight(7)} | ${e.body}';
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = _settingsMotionEnabled(context);
    _syncCursorBlinkController(motionEnabled);
    final l10n = AppLocalizations.of(context)!;
    final mediaSize = MediaQuery.sizeOf(context);
    // 最大化/还原通过同一动画因子插值尺寸与边距，避免窗口生硬跳变。
    final wMin = math.min(840.0, mediaSize.width - 48);
    final hMin = math.min(560.0, mediaSize.height - 96);
    final wMax = mediaSize.width - 24;
    final hMax = mediaSize.height - 32;
    final dialog = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _maximized ? 1.0 : 0.0),
      duration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 380),
      ),
      curve: Curves.easeOutBack,
      builder: (context, t, _) {
        // easeOutBack 会短暂越界；保留少量弹性，最终仍由外层约束兜底。
        final tt = t.clamp(0.0, 1.06);
        final w = ui.lerpDouble(wMin, wMax, tt)!;
        final h = ui.lerpDouble(hMin, hMax, tt)!;
        final inset = ui.lerpDouble(24, 12, tt.clamp(0.0, 1.0))!;
        return buildOpenHandDialog(
          insetPadding: EdgeInsets.all(inset),
          maxWidth: w,
          height: h,
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildHeader(context),
                  if (_running)
                    SizedBox(
                      height: 2,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        value: motionEnabled ? null : 1,
                      ),
                    )
                  else
                    const Divider(height: 1),
                  Expanded(child: _buildConsole(context)),
                  const Divider(height: 1),
                  _buildFooter(context, l10n),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: HighlightPulse(
                    signal: _completionPulse,
                    color: _finishedSucceeded
                        ? OpenHandStatusColors.success
                        : OpenHandStatusColors.error,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return PopScope(canPop: !_running, child: dialog);
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 状态色固定为绿/红/琥珀，避免主题主色削弱成功/失败辨识度。
    const successColor = OpenHandStatusColors.success; // 绿色
    const errorColor = OpenHandStatusColors.error; // 红色
    const runningColor = _kProxyTestAmberDark;
    final IconData statusIcon;
    final Color statusColor;
    final String statusText;
    if (_running) {
      statusIcon = Icons.sync;
      statusColor = runningColor;
      statusText = l10n.proxyTestConsoleRunning;
    } else if (_finishedSucceeded) {
      statusIcon = Icons.check_circle;
      statusColor = successColor;
      statusText = l10n.proxyTestConsoleSucceeded;
    } else {
      statusIcon = Icons.error;
      statusColor = errorColor;
      statusText = l10n.proxyTestConsoleFailed;
    }
    final slowest = _slowestSection();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        children: <Widget>[
          Icon(statusIcon, color: statusColor, size: 22),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.proxyTestConsoleTitle,
                  style: theme.textTheme.titleMedium,
                ),
                kOpenHandGap4,
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      statusText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                      ),
                    ),
                    if (_entries.isNotEmpty)
                      _buildHeaderChip(
                        theme: theme,
                        icon: Icons.timer_outlined,
                        label: '总计 ${_entries.last.elapsedMs}ms',
                        tone: theme.colorScheme.secondaryContainer,
                        fg: theme.colorScheme.onSecondaryContainer,
                      ),
                    if (slowest != null && slowest.value > 0)
                      _buildHeaderChip(
                        theme: theme,
                        icon: Icons.local_fire_department_outlined,
                        label: '最慢 ${slowest.key} ${slowest.value}ms',
                        tone: theme.colorScheme.tertiaryContainer,
                        fg: theme.colorScheme.onTertiaryContainer,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _maximized
                ? l10n.proxyTestConsoleRestore
                : l10n.proxyTestConsoleMaximize,
            onPressed: () => setState(() => _maximized = !_maximized),
            icon: Icon(
              _maximized ? Icons.close_fullscreen : Icons.open_in_full,
              size: 18,
            ),
          ),
          // 工具按钮之间保留固定间距，窄宽度下仍维持可点按的视觉分隔。
          kOpenHandHGap6,
          IconButton(
            tooltip: l10n.proxyTestConsoleClear,
            // 运行中允许清空历史行；不重置总计时，也不打断诊断流程。
            onPressed: _entries.isEmpty ? null : _clearConsole,
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          ),
          kOpenHandHGap6,
          IconButton(
            tooltip: l10n.proxyTestConsoleCopy,
            onPressed: _entries.isEmpty ? null : _copyLogs,
            icon: const Icon(Icons.copy_all_outlined, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color tone,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: fg),
          kOpenHandHGap4,
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsole(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF101218) : const Color(0xFF1B1F27);
    // head 行是阶段锚点，始终保留；过滤器只遮蔽数据行。
    final filtered = _visibleLogEntries();
    final visible = _selectionHeld && _selectionSnapshot != null
        ? _selectionSnapshot!
        : filtered;
    final showCursor = _selectionHeld ? _selectionSnapshotRunning : _running;
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      // 整片包一层 SelectionArea，避免每行独立选择区扰动 SliverList 尺寸。
      child: SelectionArea(
        onSelectionChanged: _handleConsoleSelectionChanged,
        child: OpenHandSafeScrollbar(
          controller: _scrollController,
          child: NotificationListener<ScrollNotification>(
            onNotification: _scrollGuard.handleNotification,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: visible.length + (showCursor ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == visible.length) {
                  return _buildBlinkingCursor();
                }
                return _buildEntryRow(visible[i]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlinkingCursor() {
    final motionEnabled = _settingsMotionEnabled(context);
    if (!motionEnabled) {
      return _buildCursor(t: 0.5);
    }
    // 双色闪烁用于传达诊断仍在运行。
    return AnimatedBuilder(
      animation: _cursorBlinkController,
      builder: (_, _) {
        return _buildCursor(t: _cursorBlinkController.value);
      },
    );
  }

  Widget _buildCursor({required double t}) {
    final color = Color.lerp(
      _kProxyTestGreen, // 绿色
      _kProxyTestAmber, // 琥珀色
      t,
    )!;
    // 纯色块的透明度直接折进颜色：Opacity 会为每个色块开一层 saveLayer，
    // 而这里是列表项，行数一多就是每帧几十次离屏合成。
    final opacity = 0.35 + 0.65 * t;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 9,
            height: 16,
            color: color.withValues(alpha: color.a * opacity),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(_ProxyTestLogEntry entry) {
    final ts = (entry.elapsedMs / 1000).toStringAsFixed(3).padLeft(7);
    final levelColor = _colorFor(entry.level);
    final textStyle = TextStyle(
      fontFamily: _consoleFontFamily,
      fontSize: 12,
      height: 1.45,
      color: levelColor,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    // 左侧色条使用边框实现，避免 IntrinsicHeight 在 SliverList 中引发尺寸抖动。
    final isHead = entry.level == _ProxyTestLogLevel.head;
    final levelBg = switch (entry.level) {
      _ProxyTestLogLevel.head => _kProxyTestSky300.withValues(alpha: 0.12),
      _ProxyTestLogLevel.err => _kProxyTestRed300.withValues(alpha: 0.08),
      _ProxyTestLogLevel.warn => _kProxyTestAmber.withValues(alpha: 0.06),
      _ => Colors.transparent,
    };
    final headSlowMs = isHead ? (_sectionDurations[entry.tag] ?? 0) : 0;
    final headSlowMark = headSlowMs >= _slowSectionThresholdMs
        ? '  ⚠ ${headSlowMs}ms'
        : '';

    final rowText = Padding(
      padding: const EdgeInsets.fromLTRB(11, 1.5, 0, 1.5),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '+${ts}s ',
              style: textStyle.copyWith(color: _kProxyTestGray),
            ),
            TextSpan(
              text: '${entry.tag.padRight(7)} │ ',
              style: textStyle.copyWith(
                color: levelColor,
                fontWeight: isHead ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            TextSpan(
              text: entry.body,
              style: textStyle.copyWith(
                fontWeight: isHead ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (headSlowMark.isNotEmpty)
              TextSpan(
                text: headSlowMark,
                style: textStyle.copyWith(
                  color: _kProxyTestAmber,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
    final decorated = _ProxyHoverableRow(
      baseColor: levelBg,
      hoverColor: Colors.white.withValues(alpha: 0.06),
      isHead: isHead,
      headBorderColor: _kProxyTestSky300.withValues(alpha: 0.30),
      leftBarColor: levelColor.withValues(alpha: 0.85),
      onDoubleTap: () => _copyEntryLine(entry),
      child: rowText,
    );
    // 入场动画：fade-in + 由下方 6px 上滑到位（200ms easeOutCubic），
    // TweenAnimationBuilder 仅在条目首次挂载时由 0→1 一次性触发，
    // 已挂载的旧条目重建时 begin 与 end 一致不会再次播放。
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(identityHashCode(entry)),
      tween: Tween<double>(begin: 0, end: 1),
      duration: openHandMotionDuration(context, kOpenHandMotion200),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: decorated,
    );
  }

  Future<void> _copyEntryLine(_ProxyTestLogEntry entry) async {
    await copyOpenHandTextToClipboard(
      logTag: 'settings',
      context: context,
      text: _formatEntryAsPlainText(entry),
      successMessage: AppLocalizations.of(context)!.proxyTestConsoleCopied,
      logAction: '复制代理测试记录',
      successDuration: const Duration(milliseconds: 1200),
    );
  }

  static const String _consoleFontFamily = 'Menlo';

  Color _colorFor(_ProxyTestLogLevel level) {
    switch (level) {
      case _ProxyTestLogLevel.head:
        return _kProxyTestSky300; // sky-300
      case _ProxyTestLogLevel.info:
        return _kProxyTestLightGray; // 浅灰色
      case _ProxyTestLogLevel.ok:
        return _kProxyTestLightGreen; // 浅绿色
      case _ProxyTestLogLevel.warn:
        return _kProxyTestAmber; // 琥珀色
      case _ProxyTestLogLevel.err:
        return _kProxyTestRed300; // red-300
      case _ProxyTestLogLevel.debug:
        return _kProxyTestNeutralGray; // 灰色
    }
  }

  Widget _buildFooter(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 底部过滤器只暴露常用等级；head 是阶段锚点，不参与过滤。
          Row(
            children: <Widget>[
              Icon(
                Icons.filter_list,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              kOpenHandHGap6,
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _buildLevelFilterChip(_ProxyTestLogLevel.info, 'info'),
                    _buildLevelFilterChip(_ProxyTestLogLevel.ok, 'ok'),
                    _buildLevelFilterChip(_ProxyTestLogLevel.warn, 'warn'),
                    _buildLevelFilterChip(_ProxyTestLogLevel.err, 'err'),
                  ],
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          buildOpenHandDialogActionsBar(
            padding: EdgeInsets.zero,
            leading: _finalSummary == null
                ? null
                : Text(
                    _finalSummary!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            actions: <Widget>[
              if (!_running)
                OpenHandDialogActionButton.secondary(
                  onPressed: _rerun,
                  icon: Icons.refresh,
                  label: l10n.proxyTestConsoleRerun,
                ),
              OpenHandDialogActionButton.primary(
                onPressed: _running
                    ? null
                    : () => Navigator.of(context).pop(
                        _ProxyTestOutcome(
                          succeeded: _finishedSucceeded,
                          summary: _finalSummary ?? '',
                        ),
                      ),
                label: l10n.proxyTestConsoleClose,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLevelFilterChip(_ProxyTestLogLevel level, String label) {
    final visible = !_hiddenLevels.contains(level);
    final levelColor = _colorFor(level);
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        setState(() {
          if (visible) {
            _hiddenLevels.add(level);
          } else {
            _hiddenLevels.remove(level);
          }
        });
      },
      borderRadius: BorderRadius.circular(kOpenHandRadius10),
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: visible
              ? levelColor.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
          borderRadius: BorderRadius.circular(kOpenHandRadius10),
          border: Border.all(
            color: visible
                ? levelColor.withValues(alpha: 0.45)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              size: 12,
              color: visible
                  ? levelColor
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            kOpenHandHGap4,
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: visible
                    ? levelColor
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                decoration: visible ? null : TextDecoration.lineThrough,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearConsole() {
    if (_entries.isEmpty) return;
    setState(() {
      _entries.clear();
      _sectionDurations.clear();
      // 仅清显示，不动 _currentSectionTag / startMs：当前在跑的
      // section 时长仍按真实计时累加，下一条 head 收尾时正常 finalize。
    });
  }

  void _rerun() {
    if (_running) return;
    setState(() {
      _entries.clear();
      _sectionDurations.clear();
      _currentSectionTag = null;
      _currentSectionStartMs = 0;
      _running = true;
      _finishedSucceeded = false;
      _finalSummary = null;
    });
    _totalStopwatch
      ..reset()
      ..start();
    _syncCursorBlinkController(_settingsMotionEnabled(context));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runDiagnostics();
    });
  }

  void _syncCursorBlinkController(bool motionEnabled) {
    if (_running && motionEnabled) {
      if (!_cursorBlinkController.isAnimating) {
        _cursorBlinkController.repeat(reverse: true);
      }
      return;
    }
    _cursorBlinkController.stop();
  }
}

/// 单条日志行的悬停高亮 + 双击复制 + head 段分隔线 + 左侧色条包装。
///
/// 拆成独立 StatefulWidget 是为了让 hover 状态局部化：直接放到
/// `_buildEntryRow` 里需要每行单独一个 setState 索引，rebuild 整
/// 个 ListView 性能差也容易过度刷新。这里只 rebuild 自身。
///
/// 左侧色条以 `Border(left: BorderSide)` 实现而不是单独 Container
/// 子项 —— 边框跟随容器自身高度，避免 IntrinsicHeight + Row(stretch)
/// 在 ListView.builder 的 unbounded main-axis 中触发 SliverList
/// 'child.hasSize' 断言。
class _ProxyHoverableRow extends StatefulWidget {
  const _ProxyHoverableRow({
    required this.baseColor,
    required this.hoverColor,
    required this.isHead,
    required this.headBorderColor,
    required this.leftBarColor,
    required this.onDoubleTap,
    required this.child,
  });

  final Color baseColor;
  final Color hoverColor;
  final bool isHead;
  final Color headBorderColor;
  final Color leftBarColor;
  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_ProxyHoverableRow> createState() => _ProxyHoverableRowState();
}

class _ProxyHoverableRowState extends State<_ProxyHoverableRow>
    with OpenHandHoverState {
  @override
  Widget build(BuildContext context) {
    final leftSide = BorderSide(color: widget.leftBarColor, width: 3);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setOpenHandHovered(true),
      onExit: (_) => setOpenHandHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion120),
          decoration: BoxDecoration(
            color: openHandHovered
                ? Color.alphaBlend(widget.hoverColor, widget.baseColor)
                : widget.baseColor,
            border: widget.isHead
                ? Border(
                    top: BorderSide(color: widget.headBorderColor),
                    bottom: BorderSide(color: widget.headBorderColor),
                    left: leftSide,
                  )
                : Border(left: leftSide),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

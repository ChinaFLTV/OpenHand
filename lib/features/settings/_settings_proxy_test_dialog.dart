// 2026-05-04: 代理连通性诊断控制台弹窗。
//
// 把原先一行 inline 状态升级成完整的"全链路探针"：将 URL 解析、
// 代理配置摘要、SystemProxyResolver 决策、DNS 查询、TCP 握手、
// HTTPS 请求/响应全过程的关键事件以彩色等宽日志的形式滚动输出，
// 等价于在终端里跑一次 `curl -v --proxy ...` 的可视化版本。
//
// 弹窗本体使用 [showAnimatedDialog]，自动继承用户在"设置 → 弹窗
// 动画"里配置的 entrance/exit/duration/curve，与系统其它弹窗
// 进退场动画完全一致，无需额外 transitionBuilder。
part of 'settings_view.dart';

class _ProxyTestOutcome {
  const _ProxyTestOutcome({required this.succeeded, required this.summary});

  final bool succeeded;
  final String summary;
}

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
  final Stopwatch _totalStopwatch = Stopwatch();
  late final AnimationController _cursorBlinkController;

  // 2026-05-04 (UI \u8c03\u4f18): \u6bcf\u5f53\u4e00\u6761 head \u65e5\u5fd7\u51fa\u73b0\u65f6\u5c06\u4e0a\u4e00\u4e2a\u5c0f\u8282
  // \u7684 tag \u4e0e\u8017\u65f6\u8bb0\u5165 _sectionDurations\uff0c\u4f9b\u9876\u90e8 chip \u5c55\u793a "\u70ed\u70b9
  // \u8017\u65f6 = TAG (Xms)" \u4f7f\u7528\u3002
  final Map<String, int> _sectionDurations = <String, int>{};
  String? _currentSectionTag;
  int _currentSectionStartMs = 0;

  bool _running = true;
  bool _finishedSucceeded = false;
  String? _finalSummary;

  // 2026-05-04 (UI 调优 v2):
  // - _hiddenLevels：底部 mini 过滤器开关，被点选的 level 会从
  //   控制台 ListView 中过滤掉（仍写入 _entries，仅渲染遮蔽）。
  //   head 永远不被过滤——它是阶段锚点，藏掉会让整个时序错乱。
  // - _maximized：header 上的最大化按钮切换；最大化时弹窗几乎
  //   占满屏幕，便于看长 trace。
  // - _slowSectionThresholdMs：≥ 此值的 section head 会在文本后
  //   缀上 ⚠ ms 警告标。50 ms 是经验阈值——DNS / TCP / TLS 握手
  //   单段如果超过这个量级，基本就是网络/代理路径异常的信号。
  final Set<_ProxyTestLogLevel> _hiddenLevels = <_ProxyTestLogLevel>{};
  bool _maximized = false;
  static const int _slowSectionThresholdMs = 50;

  @override
  void initState() {
    super.initState();
    // 2026-05-04 (UI \u8c03\u4f18): \u5c06 blink \u5468\u671f\u4ece 900\u2192600 ms\uff0c\u8ba9\u7e41\u5fd9
    // \u4e2d\u7684\u5149\u6807\u51fa\u73b0\u51fa "\u7e41\u5fd9" \u54cd\u5e94\u3002\u80cc\u666f\u4ece\u9ec4\u7eff\u8272\u8fc7\u5ea6
    // \u5230\u9752\u9752\u7684\u8b66\u9192\u8272\uff0c\u8df3\u52a8\u8282\u594f\u4e2d\u5b8c\u6210"\u8272\u5f69+\u4eae\u5ea6"\u53cc\u91cd\u63d0\u793a\u3002
    _cursorBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _totalStopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runDiagnostics();
    });
  }

  @override
  void dispose() {
    _cursorBlinkController.dispose();
    _scrollController.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
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
    final l10n = AppLocalizations.of(context)!;
    final uri = widget.endpoint;
    final settings = widget.proxySettings;
    final resolver = SystemProxyResolver.instance;

    HttpClient? httpClient;
    var ok = false;
    String summary;
    try {
      _log(_ProxyTestLogLevel.head, 'PROBE', '════ Connectivity Diagnostic ════');
      _log(_ProxyTestLogLevel.info, 'PROBE', 'target  = ${uri.toString()}');
      _log(_ProxyTestLogLevel.debug, 'PROBE',
          'scheme=${uri.scheme}  host=${uri.host}  port=${uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80)}  path=${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');

      _log(_ProxyTestLogLevel.head, 'CONFIG', '────────  Proxy Configuration  ────────');
      _log(_ProxyTestLogLevel.info, 'CONFIG', 'mode = ${_describeMode(settings.mode)}');
      if (settings.mode == AppProxyMode.manual) {
        final protos = settings.protocols.map((p) => p.name).join(',');
        _log(_ProxyTestLogLevel.info, 'CONFIG', 'protocols = [$protos]');
        _log(_ProxyTestLogLevel.info, 'CONFIG',
            'endpoint  = ${settings.host.isEmpty ? '<empty>' : settings.host}:${settings.port}');
        if (settings.authEnabled) {
          final maskedPwd = settings.password.isEmpty
              ? '<empty>'
              : '*' * settings.password.length;
          _log(_ProxyTestLogLevel.info, 'CONFIG',
              'auth = on  user="${settings.username}"  pwd=$maskedPwd');
        } else {
          _log(_ProxyTestLogLevel.info, 'CONFIG', 'auth = off');
        }
        _log(_ProxyTestLogLevel.info, 'CONFIG',
            'exceptions = ${settings.exceptions.length} entr${settings.exceptions.length == 1 ? "y" : "ies"}');
      }

      _log(_ProxyTestLogLevel.head, 'RESOLVE', '────────  findProxyFor()  ────────');
      final via = resolver.findProxyFor(uri);
      _log(_ProxyTestLogLevel.ok, 'RESOLVE', 'verdict = "$via"');
      final useProxy = via.startsWith('PROXY ');
      final viaLabel = useProxy
          ? l10n.proxyTestVerdictProxy(via.substring('PROXY '.length).trim())
          : l10n.proxyTestVerdictDirect;

      // Determine the host:port we will physically connect to.
      String hopHost;
      int hopPort;
      if (useProxy) {
        final spec = via.substring('PROXY '.length).trim();
        final colon = spec.lastIndexOf(':');
        if (colon <= 0) {
          throw FormatException('Malformed PROXY directive: "$via"');
        }
        hopHost = spec.substring(0, colon);
        hopPort = int.parse(spec.substring(colon + 1));
        _log(_ProxyTestLogLevel.info, 'RESOLVE',
            'first hop → proxy@$hopHost:$hopPort  (target host left to proxy)');
      } else {
        hopHost = uri.host;
        hopPort = uri.hasPort
            ? uri.port
            : (uri.scheme == 'https' ? 443 : 80);
        _log(_ProxyTestLogLevel.info, 'RESOLVE',
            'first hop → direct@$hopHost:$hopPort');
      }

      // ── Local network interfaces (split-tunnel diagnostic) ────────────
      _log(_ProxyTestLogLevel.head, 'NIC',
          '────────  Local Interfaces  ────────');
      try {
        final ifaces = await NetworkInterface.list().timeout(
          const Duration(seconds: 2),
        );
        if (ifaces.isEmpty) {
          _log(_ProxyTestLogLevel.warn, 'NIC',
              '<no active non-loopback interfaces detected>');
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
            _log(_ProxyTestLogLevel.info, 'NIC',
                '${iface.name}  v4=[${v4.join(",")}]  v6=[${v6.length} addr]');
          }
        }
      } catch (e) {
        _log(_ProxyTestLogLevel.warn, 'NIC', 'enumeration failed: $e');
      }

      // ── DNS resolution: A + AAAA separately ──────────────────────────
      _log(_ProxyTestLogLevel.head, 'DNS',
          '────────  Lookup ($hopHost)  ────────');
      InternetAddress? selectedAddr;
      for (final family in const <InternetAddressType>[
        InternetAddressType.IPv4,
        InternetAddressType.IPv6,
      ]) {
        final famName = family == InternetAddressType.IPv4 ? 'A' : 'AAAA';
        final dnsStart = _totalStopwatch.elapsedMilliseconds;
        try {
          final addrs = await InternetAddress.lookup(hopHost, type: family)
              .timeout(const Duration(seconds: 5));
          final dnsMs = _totalStopwatch.elapsedMilliseconds - dnsStart;
          if (addrs.isEmpty) {
            _log(_ProxyTestLogLevel.debug, 'DNS',
                '$famName → <none>  (${dnsMs}ms)');
          } else {
            for (final addr in addrs.take(4)) {
              _log(_ProxyTestLogLevel.ok, 'DNS',
                  '$famName → ${addr.address}  (${dnsMs}ms)');
            }
            if (addrs.length > 4) {
              _log(_ProxyTestLogLevel.debug, 'DNS',
                  '… +${addrs.length - 4} more $famName record${addrs.length - 4 == 1 ? "" : "s"}');
            }
            selectedAddr ??= addrs.first;
          }
        } on TimeoutException {
          _log(_ProxyTestLogLevel.warn, 'DNS',
              '$famName lookup timed out (5000ms)');
        } catch (e) {
          _log(_ProxyTestLogLevel.warn, 'DNS', '$famName lookup failed: $e');
        }
      }
      if (selectedAddr != null) {
        final preferredFamily = selectedAddr.type == InternetAddressType.IPv6
            ? 'IPv6 (AAAA)'
            : 'IPv4 (A)';
        _log(_ProxyTestLogLevel.info, 'DNS',
            'preferred family = $preferredFamily  (first answer)');
        // Reverse DNS (PTR) for selected address.
        try {
          final ptr = await selectedAddr
              .reverse()
              .timeout(const Duration(seconds: 3));
          _log(_ProxyTestLogLevel.ok, 'PTR',
              '${selectedAddr.address} ← ${ptr.host}');
        } on TimeoutException {
          _log(_ProxyTestLogLevel.debug, 'PTR',
              '${selectedAddr.address} ← <timeout 3000ms>');
        } catch (e) {
          _log(_ProxyTestLogLevel.debug, 'PTR',
              '${selectedAddr.address} ← <unavailable: $e>');
        }
      } else {
        _log(_ProxyTestLogLevel.warn, 'DNS', 'no usable address resolved');
      }

      // Raw TCP probe
      _log(_ProxyTestLogLevel.head, 'TCP',
          '────────  Socket Connect  ────────');
      final tcpStart = _totalStopwatch.elapsedMilliseconds;
      try {
        final socket = await Socket.connect(hopHost, hopPort,
                timeout: const Duration(seconds: 6))
            .timeout(const Duration(seconds: 6));
        final tcpMs = _totalStopwatch.elapsedMilliseconds - tcpStart;
        _log(_ProxyTestLogLevel.ok, 'TCP',
            'handshake ok  remote=${socket.remoteAddress.address}:${socket.remotePort}  local=${socket.address.address}:${socket.port}  rtt=${tcpMs}ms');
        await socket.close();
      } on SocketException catch (e) {
        _log(_ProxyTestLogLevel.err, 'TCP',
            'connect failed: ${e.message}${e.osError == null ? '' : ' (errno=${e.osError!.errorCode})'}');
        rethrow;
      } on TimeoutException {
        _log(_ProxyTestLogLevel.err, 'TCP',
            'connect timed out after 6000 ms');
        rethrow;
      }

      // ── TLS handshake (only if we go directly to an HTTPS target) ────
      // For a proxied request the TLS handshake happens against the
      // *target* after a CONNECT tunnel which we cannot easily observe
      // from outside HttpClient; so we only run a stand-alone SecureSocket
      // probe in the direct-to-https case.
      if (!useProxy && uri.scheme == 'https') {
        _log(_ProxyTestLogLevel.head, 'TLS',
            '────────  SecureSocket Handshake  ────────');
        final tlsStart = _totalStopwatch.elapsedMilliseconds;
        try {
          final secure = await SecureSocket.connect(
            hopHost,
            hopPort,
            timeout: const Duration(seconds: 8),
            supportedProtocols: const <String>['h2', 'http/1.1'],
          );
          final tlsMs = _totalStopwatch.elapsedMilliseconds - tlsStart;
          _log(_ProxyTestLogLevel.ok, 'TLS',
              'handshake ok  alpn=${secure.selectedProtocol ?? "<none>"}  rtt=${tlsMs}ms');
          final cert = secure.peerCertificate;
          if (cert != null) {
            _log(_ProxyTestLogLevel.info, 'TLS', 'cert.subject = ${cert.subject.replaceAll("\n", " / ").trim()}');
            _log(_ProxyTestLogLevel.info, 'TLS', 'cert.issuer  = ${cert.issuer.replaceAll("\n", " / ").trim()}');
            _log(_ProxyTestLogLevel.debug, 'TLS',
                'cert.validity = ${cert.startValidity.toIso8601String()} → ${cert.endValidity.toIso8601String()}');
          } else {
            _log(_ProxyTestLogLevel.warn, 'TLS',
                'peerCertificate = <null>  (unexpected)');
          }
          await secure.close();
        } on HandshakeException catch (e) {
          _log(_ProxyTestLogLevel.err, 'TLS',
              'handshake failed: ${e.message}');
          rethrow;
        } on TimeoutException {
          _log(_ProxyTestLogLevel.err, 'TLS',
              'handshake timed out after 8000 ms');
          rethrow;
        }
      } else if (useProxy && uri.scheme == 'https') {
        _log(_ProxyTestLogLevel.debug, 'TLS',
            'skipped — TLS handshake will tunnel through proxy CONNECT (observed via HTTP step)');
      }

      // Real HTTP request via HttpClient (handles TLS + CONNECT/forward proxy semantics).
      _log(_ProxyTestLogLevel.head, 'HTTP', '────────  Request  ────────');
      httpClient = resolver.createRawHttpClient(
        connectionTimeout: const Duration(seconds: 8),
      );
      _log(_ProxyTestLogLevel.info, 'HTTP', '> GET ${uri.path.isEmpty ? '/' : uri.path}${uri.hasQuery ? '?${uri.query}' : ''} HTTP/1.1');
      _log(_ProxyTestLogLevel.info, 'HTTP', '> Host: ${uri.host}${uri.hasPort ? ':${uri.port}' : ''}');
      _log(_ProxyTestLogLevel.info, 'HTTP', '> User-Agent: OpenHand-ProxyDiag/1.0');
      _log(_ProxyTestLogLevel.info, 'HTTP', '> Accept: */*');

      final httpStart = _totalStopwatch.elapsedMilliseconds;
      final request = await httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set('User-Agent', 'OpenHand-ProxyDiag/1.0');
      request.headers.set('Accept', '*/*');
      final response = await request.close()
          .timeout(const Duration(seconds: 12));
      final ttfb = _totalStopwatch.elapsedMilliseconds - httpStart;
      _log(_ProxyTestLogLevel.ok, 'HTTP',
          '< HTTP/${response.persistentConnection ? '1.1' : '1.0'} ${response.statusCode} ${response.reasonPhrase}');
      response.headers.forEach((name, values) {
        for (final v in values) {
          _log(_ProxyTestLogLevel.debug, 'HTTP', '< $name: $v');
        }
      });
      // Drain body (small responses only).
      var bodyBytes = 0;
      await for (final chunk in response) {
        bodyBytes += chunk.length;
        if (bodyBytes > 64 * 1024) break;
      }
      _log(_ProxyTestLogLevel.info, 'HTTP',
          'ttfb=${ttfb}ms  body=$bodyBytes byte${bodyBytes == 1 ? '' : 's'}  contentLength=${response.contentLength}');

      ok = response.statusCode >= 200 && response.statusCode < 400;
      summary = ok
          ? l10n.proxyTestSuccess(_totalStopwatch.elapsedMilliseconds.toString(), viaLabel)
          : l10n.proxyTestFailure('HTTP ${response.statusCode}');
    } catch (error, stack) {
      silentLog('settings_proxy', 'connectivityTest', error, stack);
      ok = false;
      if (mounted) {
        summary = AppLocalizations.of(context)!
            .proxyTestFailure(error.toString());
      } else {
        summary = error.toString();
      }
      _log(_ProxyTestLogLevel.err, 'FATAL', error.toString());
    } finally {
      try {
        httpClient?.close(force: true);
      } catch (_) {}
    }
    _totalStopwatch.stop();
    _finalizeCurrentSection(_totalStopwatch.elapsedMilliseconds);
    _log(
      ok ? _ProxyTestLogLevel.ok : _ProxyTestLogLevel.err,
      'DONE',
      '════ ${ok ? 'SUCCESS' : 'FAILURE'}  total=${_totalStopwatch.elapsedMilliseconds}ms ════',
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _finishedSucceeded = ok;
      _finalSummary = summary;
    });
    _cursorBlinkController.stop();
  }

  String _describeMode(AppProxyMode mode) {
    switch (mode) {
      case AppProxyMode.disabled:
        return 'disabled';
      case AppProxyMode.automatic:
        return 'automatic (system)';
      case AppProxyMode.manual:
        return 'manual';
    }
  }

  Future<void> _copyLogs() async {
    final buffer = StringBuffer();
    for (final entry in _entries) {
      buffer.writeln(_formatEntryAsPlainText(entry));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.proxyTestConsoleCopied),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  String _formatEntryAsPlainText(_ProxyTestLogEntry e) {
    final ts = (e.elapsedMs / 1000).toStringAsFixed(3).padLeft(7);
    final lvl = e.level.name.toUpperCase().padRight(5);
    return '[+${ts}s] $lvl ${e.tag.padRight(7)} | ${e.body}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mediaSize = MediaQuery.sizeOf(context);
    final w = _maximized
        ? mediaSize.width - 24
        : math.min(840.0, mediaSize.width - 48);
    final h = _maximized
        ? mediaSize.height - 32
        : math.min(560.0, mediaSize.height - 96);
    return Dialog(
      insetPadding: EdgeInsets.all(_maximized ? 12 : 24),
      child: ConstrainedBox(
        // 2026-05-04 (Bug 修复): 将 maxHeight 升级为 tight 高度
        // ——`Column(mainAxisSize: min)` + 内部 `Expanded` 在
        // 仅给 maxHeight (loose) 时，Column 会按 min 收缩到非
        // Expanded 子项的总高，Expanded 拿到 0 高度，控制台
        // 整片为空（用户反馈"终端啥也没有"）。改用 minHeight
        // == maxHeight + MainAxisSize.max，保证 Expanded 永远
        // 拿到 (h - header - footer) 的可视高度。
        constraints: BoxConstraints(
          maxWidth: w,
          minHeight: h,
          maxHeight: h,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(context),
            // 2026-05-04 (UI 调优 v2): 顶部薄进度条 — 运行中显示
            // 一条 indeterminate LinearProgressIndicator (高度 2)
            // 紧贴在 header 下面，给"还在跑"加一个细水长流的视
            // 觉提示，光标负责"在打字"，进度条负责"长流程感"。
            if (_running)
              const SizedBox(
                height: 2,
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              const Divider(height: 1),
            Expanded(child: _buildConsole(context)),
            const Divider(height: 1),
            _buildFooter(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 2026-05-04 (UI 调优 v2): 把状态色从主题 primary/error 改为
    // 显式的绿/红/琥珀，避免 primary 在某些主题下表现成粉/紫导
    // 致"看不出成功失败"。
    const successColor = Color(0xFF22C55E); // green-500
    const errorColor = Color(0xFFEF4444); // red-500
    const runningColor = Color(0xFFFACC15); // amber-400
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.proxyTestConsoleTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      statusText,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: statusColor),
                    ),
                    if (_entries.isNotEmpty)
                      _buildHeaderChip(
                        theme: theme,
                        icon: Icons.timer_outlined,
                        label:
                            'total ${_entries.last.elapsedMs}ms',
                        tone: theme.colorScheme.secondaryContainer,
                        fg: theme.colorScheme.onSecondaryContainer,
                      ),
                    if (slowest != null && slowest.value > 0)
                      _buildHeaderChip(
                        theme: theme,
                        icon: Icons.local_fire_department_outlined,
                        label:
                            'hot ${slowest.key} ${slowest.value}ms',
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
              _maximized
                  ? Icons.close_fullscreen
                  : Icons.open_in_full,
              size: 18,
            ),
          ),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
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
    // 2026-05-04 (UI 调优 v2): 过滤器仅遮蔽 info / ok / warn / err
    // / debug 这五种数据行；head 永远不被过滤——它是阶段锚点，藏
    // 掉会让整个时序错乱。
    final visible = _entries
        .where(
          (e) =>
              e.level == _ProxyTestLogLevel.head ||
              !_hiddenLevels.contains(e.level),
        )
        .toList(growable: false);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: visible.length + (_running ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == visible.length) {
              return _buildBlinkingCursor();
            }
            return _buildEntryRow(visible[i]);
          },
        ),
      ),
    );
  }

  Widget _buildBlinkingCursor() {
    // 2026-05-04 (UI 调优): 双色 + 双频闪烁 — 控制器自身在
    // 600 ms 内做 0→1 一次，颜色在绿色和琥珀色之间交替，
    // 视觉上传递"正在工作"的活力，比单色淡入淡出更有"机器
    // 在跑"的临场感。
    return AnimatedBuilder(
      animation: _cursorBlinkController,
      builder: (_, _) {
        final t = _cursorBlinkController.value;
        final color = Color.lerp(
          const Color(0xFF8AE234), // green
          const Color(0xFFFCD34D), // amber
          t,
        )!;
        final opacity = 0.35 + 0.65 * t;
        return Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: opacity,
                child: Container(width: 9, height: 16, color: color),
              ),
            ],
          ),
        );
      },
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
    // 2026-05-04 (UI 调优 v2):
    // - level 背景：err / warn 微弱色块 (alpha 0.08 / 0.06)，
    //   让眼睛在长 trace 中能"一扫就找到红黄"。
    // - head 行：上下加一根 1px 细分隔线 + 比 err/warn 更显眼的
    //   bg (alpha 0.12)，作为阶段锥型分段。
    // - hover：MouseRegion 鼠标悬停时背景再加一层 0.06 白色，叠
    //   在已有 level bg 之上，是体验细节而不是结构信息。
    // - ≥ 50 ms 的 head：在 body 后缀拼一个 ⚠ Xms，肉眼一眼看到
    //   慢段。
    final isHead = entry.level == _ProxyTestLogLevel.head;
    final levelBg = switch (entry.level) {
      _ProxyTestLogLevel.head => const Color(0xFF7DD3FC).withValues(alpha: 0.12),
      _ProxyTestLogLevel.err => const Color(0xFFFCA5A5).withValues(alpha: 0.08),
      _ProxyTestLogLevel.warn => const Color(0xFFFCD34D).withValues(alpha: 0.06),
      _ => Colors.transparent,
    };
    final headSlowMs =
        isHead ? (_sectionDurations[entry.tag] ?? 0) : 0;
    final headSlowMark =
        headSlowMs >= _slowSectionThresholdMs ? '  ⚠ ${headSlowMs}ms' : '';

    final rowBody = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 左侧色条：与 tag 同色，加强可视分组。
          // IntrinsicHeight 必须包住 Row 才能让色条 stretch 到
          // 文本行的真实高度——ListView.builder 的 item 在 cross
          // 轴 (Row 的 main 轴) 是宽度受限、在 main 轴 (Row 的
          // cross 轴) 是高度无界，没有 IntrinsicHeight 兜底时
          // CrossAxisAlignment.stretch 会让 Container 撑成无穷
          // 高度并整行坍缩为 0，于是控制台终端区"什么都看不到"。
          Container(
            width: 3,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '+${ts}s ',
                      style:
                          textStyle.copyWith(color: const Color(0xFF6B7280)),
                    ),
                    TextSpan(
                      text: '${entry.tag.padRight(7)} │ ',
                      style: textStyle.copyWith(
                        color: levelColor,
                        fontWeight: isHead
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: entry.body,
                      style: textStyle.copyWith(
                        fontWeight: isHead
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (headSlowMark.isNotEmpty)
                      TextSpan(
                        text: headSlowMark,
                        style: textStyle.copyWith(
                          color: const Color(0xFFFCD34D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final decorated = _ProxyHoverableRow(
      baseColor: levelBg,
      hoverColor: Colors.white.withValues(alpha: 0.06),
      isHead: isHead,
      headBorderColor: const Color(0xFF7DD3FC).withValues(alpha: 0.30),
      onDoubleTap: () => _copyEntryLine(entry),
      child: SelectionArea(child: rowBody),
    );
    // 入场动画：fade-in + 由下方 6px 上滑到位（200ms easeOutCubic），
    // TweenAnimationBuilder 仅在条目首次挂载时由 0→1 一次性触发，
    // 已挂载的旧条目重建时 begin 与 end 一致不会再次播放。
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(identityHashCode(entry)),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
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
    await Clipboard.setData(
      ClipboardData(text: _formatEntryAsPlainText(entry)),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.proxyTestConsoleCopied),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  static const String _consoleFontFamily = 'Menlo';

  Color _colorFor(_ProxyTestLogLevel level) {
    switch (level) {
      case _ProxyTestLogLevel.head:
        return const Color(0xFF7DD3FC); // sky-300
      case _ProxyTestLogLevel.info:
        return const Color(0xFFE5E7EB); // gray-200
      case _ProxyTestLogLevel.ok:
        return const Color(0xFF86EFAC); // green-300
      case _ProxyTestLogLevel.warn:
        return const Color(0xFFFCD34D); // amber-300
      case _ProxyTestLogLevel.err:
        return const Color(0xFFFCA5A5); // red-300
      case _ProxyTestLogLevel.debug:
        return const Color(0xFF9CA3AF); // gray-400
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
          // 2026-05-04 (UI 调优 v2): 底部 mini 过滤器 — 4 个等级
          // chip (info/ok/warn/err)，被 untoggled 后该 level 的
          // 行从 ListView 中过滤掉。head/debug 不进过滤器：head
          // 是阶段锚不能藏，debug 默认就极少出现，没必要加按钮。
          Row(
            children: <Widget>[
              Icon(
                Icons.filter_list,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
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
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (_finalSummary != null)
                Expanded(
                  child: Text(
                    _finalSummary!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 8),
              if (!_running)
                TextButton.icon(
                  onPressed: _rerun,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.proxyTestConsoleRerun),
                ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _running
                    ? null
                    : () => Navigator.of(context).pop(
                        _ProxyTestOutcome(
                          succeeded: _finishedSucceeded,
                          summary: _finalSummary ?? '',
                        ),
                      ),
                child: Text(l10n.proxyTestConsoleClose),
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
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: visible
              ? levelColor.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: visible
                ? levelColor.withValues(alpha: 0.45)
                : theme.colorScheme.outlineVariant
                    .withValues(alpha: 0.4),
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
                  : theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: visible
                    ? levelColor
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                decoration: visible ? null : TextDecoration.lineThrough,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    _cursorBlinkController.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runDiagnostics();
    });
  }
}

/// 单条日志行的悬停高亮 + 双击复制 + head 段分隔线包装。
///
/// 拆成独立 StatefulWidget 是为了让 hover 状态局部化：直接放到
/// `_buildEntryRow` 里需要每行单独一个 setState 索引，rebuild 整
/// 个 ListView 性能差也容易过度刷新。这里只 rebuild 自身。
class _ProxyHoverableRow extends StatefulWidget {
  const _ProxyHoverableRow({
    required this.baseColor,
    required this.hoverColor,
    required this.isHead,
    required this.headBorderColor,
    required this.onDoubleTap,
    required this.child,
  });

  final Color baseColor;
  final Color hoverColor;
  final bool isHead;
  final Color headBorderColor;
  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_ProxyHoverableRow> createState() => _ProxyHoverableRowState();
}

class _ProxyHoverableRowState extends State<_ProxyHoverableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) {
        if (!_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover
                ? Color.alphaBlend(widget.hoverColor, widget.baseColor)
                : widget.baseColor,
            border: widget.isHead
                ? Border(
                    top: BorderSide(color: widget.headBorderColor),
                    bottom: BorderSide(
                      color: widget.headBorderColor,
                    ),
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

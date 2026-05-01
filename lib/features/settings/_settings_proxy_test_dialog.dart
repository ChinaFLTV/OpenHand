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

  bool _running = true;
  bool _finishedSucceeded = false;
  String? _finalSummary;

  @override
  void initState() {
    super.initState();
    _cursorBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
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
    setState(() {
      _entries.add(
        _ProxyTestLogEntry(
          level: level,
          tag: tag,
          body: body,
          elapsedMs: _totalStopwatch.elapsedMilliseconds,
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

      // DNS resolution (best-effort, may be skipped if proxy resolves remotely).
      _log(_ProxyTestLogLevel.head, 'DNS', '────────  Lookup  ────────');
      final dnsStart = _totalStopwatch.elapsedMilliseconds;
      try {
        final addrs = await InternetAddress.lookup(hopHost)
            .timeout(const Duration(seconds: 5));
        final dnsMs = _totalStopwatch.elapsedMilliseconds - dnsStart;
        if (addrs.isEmpty) {
          _log(_ProxyTestLogLevel.warn, 'DNS',
              '$hopHost → <no records>  (${dnsMs}ms)');
        } else {
          for (final addr in addrs.take(4)) {
            _log(_ProxyTestLogLevel.ok, 'DNS',
                '$hopHost → ${addr.address}  (${addr.type.name})');
          }
          if (addrs.length > 4) {
            _log(_ProxyTestLogLevel.debug, 'DNS',
                '… and ${addrs.length - 4} more record${addrs.length - 4 == 1 ? "" : "s"}');
          }
          _log(_ProxyTestLogLevel.info, 'DNS', 'lookup elapsed = ${dnsMs}ms');
        }
      } on TimeoutException {
        _log(_ProxyTestLogLevel.err, 'DNS',
            'lookup timed out after 5000 ms');
      } catch (e) {
        _log(_ProxyTestLogLevel.err, 'DNS', 'lookup failed: $e');
      }

      // Raw TCP probe
      _log(_ProxyTestLogLevel.head, 'TCP', '────────  Socket Connect  ────────');
      final tcpStart = _totalStopwatch.elapsedMilliseconds;
      try {
        final socket = await Socket.connect(hopHost, hopPort,
            timeout: const Duration(seconds: 6));
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
    final w = math.min(840.0, mediaSize.width - 48);
    final h = math.min(560.0, mediaSize.height - 96);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(context),
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
    final IconData statusIcon;
    final Color statusColor;
    final String statusText;
    if (_running) {
      statusIcon = Icons.sync;
      statusColor = theme.colorScheme.primary;
      statusText = l10n.proxyTestConsoleRunning;
    } else if (_finishedSucceeded) {
      statusIcon = Icons.check_circle;
      statusColor = theme.colorScheme.primary;
      statusText = l10n.proxyTestConsoleSucceeded;
    } else {
      statusIcon = Icons.error;
      statusColor = theme.colorScheme.error;
      statusText = l10n.proxyTestConsoleFailed;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
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
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
                ),
              ],
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

  Widget _buildConsole(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF101218) : const Color(0xFF1B1F27);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _entries.length + (_running ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == _entries.length) {
              return _buildBlinkingCursor();
            }
            return _buildEntryRow(_entries[i]);
          },
        ),
      ),
    );
  }

  Widget _buildBlinkingCursor() {
    return AnimatedBuilder(
      animation: _cursorBlinkController,
      builder: (_, _) {
        return Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: _cursorBlinkController.value,
                child: Container(
                  width: 9,
                  height: 16,
                  color: const Color(0xFF8AE234),
                ),
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
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: '+${ts}s ',
                style: textStyle.copyWith(color: const Color(0xFF6B7280)),
              ),
              TextSpan(
                text: '${entry.tag.padRight(7)} │ ',
                style: textStyle.copyWith(
                  color: levelColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: entry.body, style: textStyle),
            ],
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: <Widget>[
          if (_finalSummary != null)
            Expanded(
              child: Text(
                _finalSummary!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
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
    );
  }
}

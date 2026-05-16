part of 'web_reverse_dashboard_dialog.dart';

/// 单条请求的右侧详情面板，5 个 tab 与 Chrome DevTools 一致：
/// Headers / Preview / Response / Initiator / Timing
enum _DetailTab { headers, preview, response, initiator, timing }

class _RequestDetailPanel extends StatefulWidget {
  const _RequestDetailPanel({
    required this.controller,
    required this.entry,
    required this.isZh,
    required this.reduceMotion,
    required this.onClose,
  });

  final WebReverseSessionController controller;
  final CdpNetworkEntry entry;
  final bool isZh;
  final bool reduceMotion;
  final VoidCallback onClose;

  @override
  State<_RequestDetailPanel> createState() => _RequestDetailPanelState();
}

class _RequestDetailPanelState extends State<_RequestDetailPanel> {
  _DetailTab _tab = _DetailTab.headers;
  bool _bodyLoading = false;
  String? _bodyText;
  bool _bodyBase64 = false;

  @override
  void initState() {
    super.initState();
    // 进入详情面板时预热一次 body 拉取，让 Preview / Response 切换无感。
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureBody());
  }

  @override
  void didUpdateWidget(covariant _RequestDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.entry.requestId != widget.entry.requestId) {
      _bodyText = null;
      _bodyBase64 = false;
      _bodyLoading = false;
      _ensureBody();
    }
  }

  Future<void> _ensureBody() async {
    if (_bodyLoading || _bodyText != null) return;
    if (widget.entry.cachedBody != null) {
      _bodyText = widget.entry.cachedBody;
      _bodyBase64 = widget.entry.cachedBodyBase64;
      if (mounted) setState(() {});
      return;
    }
    setState(() => _bodyLoading = true);
    final result =
        await widget.controller.fetchResponseBody(widget.entry.requestId);
    if (!mounted) return;
    setState(() {
      _bodyLoading = false;
      _bodyText = result?.$1;
      _bodyBase64 = result?.$2 ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Column(
      children: [
        _buildHeader(theme, cs, isZh),
        Divider(height: 1, color: cs.outlineVariant),
        _buildTabBar(theme, cs, isZh),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: AnimatedSwitcher(
            duration:
                widget.reduceMotion ? Duration.zero : _kSwitchDuration,
            switchInCurve: _kSwitchInCurve,
            switchOutCurve: _kSwitchOutCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey<_DetailTab>(_tab),
              child: _buildBody(theme, cs, isZh),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: isZh ? '关闭详情' : 'Close detail',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: SelectableText(
              widget.entry.url,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: isZh ? '复制 URL' : 'Copy URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.entry.url));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(isZh ? '已复制 URL' : 'URL copied'),
                duration: const Duration(seconds: 1),
              ));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme, ColorScheme cs, bool isZh) {
    const tabs = _DetailTab.values;
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final t in tabs) ...[
              _DetailTabButton(
                label: _detailTabLabel(t, isZh),
                active: _tab == t,
                onTap: () => setState(() => _tab = t),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  static String _detailTabLabel(_DetailTab t, bool isZh) => switch (t) {
        _DetailTab.headers => 'Headers',
        _DetailTab.preview => 'Preview',
        _DetailTab.response => 'Response',
        _DetailTab.initiator => 'Initiator',
        _DetailTab.timing => 'Timing',
      };

  Widget _buildBody(ThemeData theme, ColorScheme cs, bool isZh) {
    return switch (_tab) {
      _DetailTab.headers => _HeadersTab(entry: widget.entry, isZh: isZh),
      _DetailTab.preview => _BodyTab(
          loading: _bodyLoading,
          text: _bodyText,
          base64: _bodyBase64,
          mimeType: widget.entry.mimeType,
          preview: true,
          isZh: isZh,
        ),
      _DetailTab.response => _BodyTab(
          loading: _bodyLoading,
          text: _bodyText,
          base64: _bodyBase64,
          mimeType: widget.entry.mimeType,
          preview: false,
          isZh: isZh,
        ),
      _DetailTab.initiator => _InitiatorTab(entry: widget.entry, isZh: isZh),
      _DetailTab.timing => _TimingTab(entry: widget.entry, isZh: isZh),
    };
  }
}

class _DetailTabButton extends StatelessWidget {
  const _DetailTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: active ? 2 : 0,
              color: active ? cs.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: active ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HeadersTab extends StatelessWidget {
  const _HeadersTab({required this.entry, required this.isZh});
  final CdpNetworkEntry entry;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final general = <(String, String)>[
      ('Request URL', entry.url),
      ('Request Method', entry.method),
      (
        'Status Code',
        entry.statusCode == null
            ? (entry.failed
                ? '(${entry.errorText ?? "failed"})'
                : '(pending)')
            : '${entry.statusCode} ${entry.statusText ?? ''}'.trim(),
      ),
      if (entry.remoteAddress != null) ('Remote Address', entry.remoteAddress!),
      if (entry.protocol != null) ('Protocol', entry.protocol!),
      ('Resource Type', entry.resourceType),
      if (entry.fromCache) ('From Cache', 'true'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _HeaderSection(title: 'General', rows: general),
        const SizedBox(height: 12),
        _HeaderSection(
          title: 'Response Headers',
          rows: entry.responseHeaders.entries
              .map((e) => (e.key, e.value))
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        _HeaderSection(
          title: 'Request Headers',
          rows: entry.requestHeaders.entries
              .map((e) => (e.key, e.value))
              .toList(growable: false),
        ),
        if (entry.requestPostData != null && entry.requestPostData!.isNotEmpty)
          ...[
          const SizedBox(height: 12),
          Text(
            isZh ? '请求体' : 'Request Payload',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 6),
          _CodeBlock(text: entry.requestPostData!),
        ],
      ],
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              '(empty)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(
                      k,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      v,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _BodyTab extends StatelessWidget {
  const _BodyTab({
    required this.loading,
    required this.text,
    required this.base64,
    required this.mimeType,
    required this.preview,
    required this.isZh,
  });

  final bool loading;
  final String? text;
  final bool base64;
  final String? mimeType;
  final bool preview;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (text == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isZh
                ? '响应体不可用（可能已被回收，或服务端返回了空 body）。'
                : 'Response body unavailable (already evicted or empty).',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (base64) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh ? '二进制响应' : 'Binary Response',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isZh
                  ? '类型 ${mimeType ?? "(未知)"} · 大小约 ${text!.length ~/ 4 * 3} 字节（base64）'
                  : 'Type ${mimeType ?? "unknown"} · ~${text!.length ~/ 4 * 3} bytes (base64)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _CodeBlock(text: text!)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _CodeBlock(text: preview ? _prettify(text!, mimeType) : text!),
    );
  }

  String _prettify(String body, String? mime) {
    final m = (mime ?? '').toLowerCase();
    if (!m.contains('json')) return body;
    // 极简 JSON 美化：不引入额外依赖。失败时返回原文。
    final trimmed = body.trim();
    if (trimmed.isEmpty) return body;
    try {
      final s = StringBuffer();
      var indent = 0;
      var inString = false;
      var prev = '';
      for (var i = 0; i < trimmed.length; i++) {
        final ch = trimmed[i];
        if (ch == '"' && prev != r'\') inString = !inString;
        if (inString) {
          s.write(ch);
        } else {
          switch (ch) {
            case '{':
            case '[':
              s.write(ch);
              indent++;
              s.write('\n');
              s.write('  ' * indent);
            case '}':
            case ']':
              indent--;
              s.write('\n');
              s.write('  ' * indent);
              s.write(ch);
            case ',':
              s.write(ch);
              s.write('\n');
              s.write('  ' * indent);
            case ':':
              s.write(': ');
            case ' ':
            case '\n':
            case '\t':
            case '\r':
              break;
            default:
              s.write(ch);
          }
        }
        prev = ch;
      }
      return s.toString();
    } catch (_) {
      return body;
    }
  }
}

class _InitiatorTab extends StatelessWidget {
  const _InitiatorTab({required this.entry, required this.isZh});
  final CdpNetworkEntry entry;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = entry.initiatorType ?? '-';
    final stack = entry.initiatorStack;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Initiator',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 6),
        _MetaRow(label: 'Type', value: type),
        if (entry.initiatorUrl != null && entry.initiatorUrl!.isNotEmpty)
          _MetaRow(label: 'URL', value: entry.initiatorUrl!),
        if (entry.initiatorLineNumber != null)
          _MetaRow(label: 'Line', value: '${entry.initiatorLineNumber}'),
        const SizedBox(height: 14),
        Text(
          isZh ? '调用栈' : 'Call Stack',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (stack.isEmpty)
          Text(
            isZh ? '(无堆栈，可能由解析器或预加载触发)' : '(no stack — parser/preload-triggered)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          for (final frame in stack) _StackFrame(frame: frame),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackFrame extends StatelessWidget {
  const _StackFrame({required this.frame});
  final Map<String, Object?> frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fn = '${frame['functionName'] ?? '(anonymous)'}';
    final url = '${frame['url'] ?? ''}';
    final line = frame['lineNumber'];
    final col = frame['columnNumber'];
    final loc = url.isEmpty ? '' : '$url:$line:$col';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fn.isEmpty ? '(anonymous)' : fn,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (loc.isNotEmpty)
            Text(
              loc,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}

class _TimingTab extends StatelessWidget {
  const _TimingTab({required this.entry, required this.isZh});
  final CdpNetworkEntry entry;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final start = entry.timestamp;
    final responseAt = entry.responseReceivedAt;
    final finishedAt = entry.loadingFinishedAt;
    final ttfb = responseAt?.difference(start).inMilliseconds;
    final total = finishedAt?.difference(start).inMilliseconds;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Timing',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 6),
        _MetaRow(label: 'Started', value: _fmt(start)),
        _MetaRow(
          label: 'Response',
          value: responseAt == null ? '-' : _fmt(responseAt),
        ),
        _MetaRow(
          label: 'Finished',
          value: finishedAt == null ? '-' : _fmt(finishedAt),
        ),
        const Divider(height: 24),
        _MetaRow(
          label: isZh ? '首字节时间' : 'TTFB',
          value: ttfb == null ? '-' : '$ttfb ms',
        ),
        _MetaRow(
          label: isZh ? '总耗时' : 'Total',
          value: total == null ? '-' : '$total ms',
        ),
        if (entry.encodedDataLength != null)
          _MetaRow(
            label: isZh ? '编码后大小' : 'Encoded',
            value: '${entry.encodedDataLength} bytes',
          ),
      ],
    );
  }

  String _fmt(DateTime t) =>
      '${t.toIso8601String().split('T').last.split('.').first} (${t.toIso8601String().split('T').first})';
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: cs.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

part of 'web_reverse_dashboard_dialog.dart';

const int _kImageInlinePreviewMaxDecodedBytes = 3 * kBytesPerMiB;

/// 单条请求的右侧详情面板，6 个 tab 与 Chrome DevTools 一致：
/// Headers / Preview / Response / Initiator / Timing / Messages（仅 WS）。
enum _DetailTab { headers, preview, response, initiator, timing, messages }

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
  int _bodyLoadSerial = 0;

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
      _bodyLoadSerial++;
      _bodyText = null;
      _bodyBase64 = false;
      _bodyLoading = false;
      _ensureBody();
    }
  }

  @override
  void dispose() {
    _bodyLoadSerial++;
    super.dispose();
  }

  Future<void> _ensureBody() async {
    if (!mounted || _bodyLoading || _bodyText != null) return;
    if (widget.entry.cachedBody != null) {
      _bodyText = widget.entry.cachedBody;
      _bodyBase64 = widget.entry.cachedBodyBase64;
      if (mounted) setState(() {});
      return;
    }
    final serial = ++_bodyLoadSerial;
    final requestId = widget.entry.requestId;
    setState(() => _bodyLoading = true);
    final result = await widget.controller.fetchResponseBody(requestId);
    if (!mounted ||
        serial != _bodyLoadSerial ||
        widget.entry.requestId != requestId) {
      return;
    }
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
            duration: widget.reduceMotion ? Duration.zero : _kSwitchDuration,
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
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
    // 关闭按钮 + URL + 复制菜单同一行；显式 center 对齐确
    // 保关闭图标永远视觉居中，URL 限制为单行 + 省略号避免双行换行后
    // 图标看起来偏上；给 URL 一个固定 height + center 包裹再加一道
    // 双层保险，即便后续主题字体变更也能稳定居中。
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '关闭详情',
                zhHant: '關閉詳情',
                en: 'Close detail',
                fr: 'Fermer le détail',
                de: 'Detail schließen',
                ja: '詳細を閉じる',
              ),
              child: InkResponse(
                onTap: widget.onClose,
                radius: 18,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          kOpenHandHGap8,
          Expanded(
            child: SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  widget.entry.url,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          kOpenHandHGap4,
          SizedBox(
            width: 32,
            height: 32,
            child: Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '重放 / 改包',
                zhHant: '重放 / 改包',
                en: 'Resend / Edit',
                fr: 'Renvoyer / modifier',
                de: 'Erneut senden / bearbeiten',
                ja: '再送信 / 編集',
              ),
              child: InkResponse(
                radius: 18,
                onTap: () => showWebReverseResendRequestDialog(
                  context,
                  controller: widget.controller,
                  entry: widget.entry,
                ),
                child: Center(
                  child: Icon(
                    Icons.replay_circle_filled_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          ),
          kOpenHandHGap4,
          SizedBox(
            width: 32,
            height: 32,
            child: Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '复制为...',
                zhHant: '複製為...',
                en: 'Copy as...',
                fr: 'Copier comme...',
                de: 'Kopieren als...',
                ja: '形式を指定してコピー...',
              ),
              child: AnimatedPopupMenuButton<String>(
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                onSelected: (kind) => unawaited(_copyAs(kind)),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'url', child: Text('URL')),
                  PopupMenuItem(value: 'curl', child: Text('cURL (POSIX)')),
                  PopupMenuItem(
                    value: 'curl-cmd',
                    child: Text('cURL (Windows)'),
                  ),
                  PopupMenuItem(value: 'fetch', child: Text('fetch')),
                  PopupMenuItem(
                    value: 'fetch-node',
                    child: Text('fetch (Node.js)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAs(String kind) async {
    final text = switch (kind) {
      'url' => widget.entry.url,
      'curl' => _asCurl(widget.entry, windows: false),
      'curl-cmd' => _asCurl(widget.entry, windows: true),
      'fetch' => _asFetch(widget.entry, node: false),
      'fetch-node' => _asFetch(widget.entry, node: true),
      _ => widget.entry.url,
    };
    await copyWebReverseTextToClipboard(
      context: context,
      text: text,
      successBase: openHandLocalizedText(
        context,
        zh: '已复制为 $kind',
        zhHant: '已複製為 $kind',
        en: 'Copied as $kind',
        fr: 'Copié en $kind',
        de: 'Als $kind kopiert',
        ja: '$kind としてコピーしました',
      ),
      logTag: 'web_reverse_detail_panel',
      logAction: '复制 $kind',
      successDuration: const Duration(seconds: 1),
    );
  }

  Widget _buildTabBar(ThemeData theme, ColorScheme cs, bool isZh) {
    final tabs = <_DetailTab>[
      _DetailTab.headers,
      _DetailTab.preview,
      _DetailTab.response,
      _DetailTab.initiator,
      _DetailTab.timing,
      if (widget.entry.isWebSocket) _DetailTab.messages,
    ];
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final t in tabs) ...[
              _DetailTabButton(
                label: _detailTabLabel(context, t),
                active: _tab == t,
                onTap: () => setState(() => _tab = t),
              ),
              kOpenHandHGap4,
            ],
          ],
        ),
      ),
    );
  }

  static String _detailTabLabel(BuildContext context, _DetailTab t) =>
      switch (t) {
        _DetailTab.headers => openHandLocalizedText(
          context,
          zh: '标头',
          zhHant: '標頭',
          en: 'Headers',
          fr: 'En-têtes',
          de: 'Header',
          ja: 'ヘッダー',
        ),
        _DetailTab.preview => openHandPreviewLabel(context),
        _DetailTab.response => _webReverseDashResponseLabel(context),
        _DetailTab.initiator => _webReverseDashInitiatorLabel(context),
        _DetailTab.timing => openHandLocalizedText(
          context,
          zh: '耗时',
          zhHant: '耗時',
          en: 'Timing',
          fr: 'Temps',
          de: 'Timing',
          ja: 'タイミング',
        ),
        _DetailTab.messages => openHandLocalizedText(
          context,
          zh: '消息',
          zhHant: '訊息',
          en: 'Messages',
          fr: 'Messages',
          de: 'Nachrichten',
          ja: 'メッセージ',
        ),
      };

  Widget _buildBody(ThemeData theme, ColorScheme cs, bool isZh) {
    return switch (_tab) {
      _DetailTab.headers => _HeadersTab(entry: widget.entry, isZh: isZh),
      _DetailTab.preview => _BodyTab(
        entry: widget.entry,
        loading: _bodyLoading,
        text: _bodyText,
        base64: _bodyBase64,
        mimeType: widget.entry.mimeType,
        preview: true,
        isZh: isZh,
      ),
      _DetailTab.response => _BodyTab(
        entry: widget.entry,
        loading: _bodyLoading,
        text: _bodyText,
        base64: _bodyBase64,
        mimeType: widget.entry.mimeType,
        preview: false,
        isZh: isZh,
      ),
      _DetailTab.initiator => _InitiatorTab(
        controller: widget.controller,
        entry: widget.entry,
        isZh: isZh,
      ),
      _DetailTab.timing => _TimingTab(entry: widget.entry, isZh: isZh),
      _DetailTab.messages => _MessagesTab(entry: widget.entry, isZh: isZh),
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
      borderRadius: kOpenHandBorderRadius8,
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
      (
        openHandLocalizedText(
          context,
          zh: '请求 URL',
          zhHant: '請求 URL',
          en: 'Request URL',
          fr: 'URL de requête',
          de: 'Anfrage-URL',
          ja: 'リクエスト URL',
        ),
        entry.url,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '请求方法',
          zhHant: '請求方法',
          en: 'Request Method',
          fr: 'Méthode',
          de: 'Anfragemethode',
          ja: 'リクエストメソッド',
        ),
        entry.method,
      ),
      (
        openHandLocalizedText(
          context,
          zh: '状态码',
          zhHant: '狀態碼',
          en: 'Status Code',
          fr: 'Code d’état',
          de: 'Statuscode',
          ja: 'ステータスコード',
        ),
        entry.statusCode == null
            ? (entry.failed
                  ? '(${entry.errorText ?? openHandLocalizedText(context, zh: "失败", zhHant: "失敗", en: "failed", fr: "échec", de: "fehlgeschlagen", ja: "失敗")})'
                  : openHandLocalizedText(
                      context,
                      zh: '(等待中)',
                      zhHant: '(等待中)',
                      en: '(pending)',
                      fr: '(en attente)',
                      de: '(ausstehend)',
                      ja: '(保留中)',
                    ))
            : '${entry.statusCode} ${entry.statusText ?? ''}'.trim(),
      ),
      if (entry.remoteAddress != null)
        (
          openHandLocalizedText(
            context,
            zh: '远端地址',
            zhHant: '遠端位址',
            en: 'Remote Address',
            fr: 'Adresse distante',
            de: 'Remote-Adresse',
            ja: 'リモートアドレス',
          ),
          entry.remoteAddress!,
        ),
      if (entry.protocol != null)
        (openHandProtocolLabel(context), entry.protocol!),
      (
        openHandLocalizedText(
          context,
          zh: '资源类型',
          zhHant: '資源類型',
          en: 'Resource Type',
          fr: 'Type de ressource',
          de: 'Ressourcentyp',
          ja: 'リソース種別',
        ),
        entry.resourceType,
      ),
      if (entry.fromCache)
        (
          openHandLocalizedText(
            context,
            zh: '来自缓存',
            zhHant: '來自快取',
            en: 'From Cache',
            fr: 'Depuis le cache',
            de: 'Aus Cache',
            ja: 'キャッシュから',
          ),
          openHandLocalizedText(
            context,
            zh: '是',
            zhHant: '是',
            en: 'true',
            fr: 'oui',
            de: 'ja',
            ja: 'はい',
          ),
        ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _HeaderSection(
          title: openHandLocalizedText(
            context,
            zh: '常规',
            zhHant: '一般',
            en: 'General',
            fr: 'Général',
            de: 'Allgemein',
            ja: '一般',
          ),
          rows: general,
        ),
        kOpenHandGap12,
        _HeaderSection(
          title: openHandLocalizedText(
            context,
            zh: '响应标头',
            zhHant: '回應標頭',
            en: 'Response Headers',
            fr: 'En-têtes de réponse',
            de: 'Antwortheader',
            ja: 'レスポンスヘッダー',
          ),
          rows: entry.responseHeaders.entries
              .map((e) => (e.key, e.value))
              .toList(growable: false),
        ),
        kOpenHandGap12,
        _HeaderSection(
          title: openHandLocalizedText(
            context,
            zh: '请求标头',
            zhHant: '請求標頭',
            en: 'Request Headers',
            fr: 'En-têtes de requête',
            de: 'Anfrageheader',
            ja: 'リクエストヘッダー',
          ),
          rows: entry.requestHeaders.entries
              .map((e) => (e.key, e.value))
              .toList(growable: false),
        ),
        if (entry.requestPostData != null &&
            entry.requestPostData!.isNotEmpty) ...[
          kOpenHandGap12,
          Text(
            openHandLocalizedText(
              context,
              zh: '请求体',
              zhHant: '請求本文',
              en: 'Request Payload',
              fr: 'Corps de requête',
              de: 'Anfrageinhalt',
              ja: 'リクエスト本文',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          kOpenHandGap6,
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
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ),
        kOpenHandGap6,
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              openHandLocalizedText(
                context,
                zh: '(空)',
                zhHant: '(空)',
                en: '(empty)',
                fr: '(vide)',
                de: '(leer)',
                ja: '(空)',
              ),
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
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      v,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
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
    required this.entry,
    required this.loading,
    required this.text,
    required this.base64,
    required this.mimeType,
    required this.preview,
    required this.isZh,
  });

  final CdpNetworkEntry entry;
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
    final mime = (mimeType ?? '').toLowerCase();
    // ── Preview tab：图片 / 音频 / 视频用嵌入式预览 + 点击大图 / 全屏 ─────
    // Preview tab 是 Chrome DevTools 的 "Preview"，主要给媒体类型用；
    // Response tab 仍走文本/二进制兜底，方便复制原始 body。
    if (preview) {
      if (isImageMimeType(mime)) {
        return _ImageInlinePreview(entry: entry, bytesText: text, isZh: isZh);
      }
      if (isAudioMimeType(mime)) {
        return _MediaInlinePreview(
          entry: entry,
          kind: MediaPreviewKind.audio,
          isZh: isZh,
        );
      }
      if (isVideoMimeType(mime)) {
        return _MediaInlinePreview(
          entry: entry,
          kind: MediaPreviewKind.video,
          isZh: isZh,
        );
      }
    }
    if (text == null) {
      return OpenHandInlineEmptyState(
        message: openHandLocalizedText(
          context,
          zh: '响应体不可用（可能已被回收，或服务端返回了空 body）。',
          zhHant: '回應本文不可用（可能已被回收，或伺服器回傳了空 body）。',
          en: 'Response body unavailable (already evicted or empty).',
          fr: 'Corps de réponse indisponible (déjà évincé ou vide).',
          de: 'Antwortinhalt nicht verfügbar (bereits verworfen oder leer).',
          ja: 'レスポンス本文は利用できません（回収済み、または空の body の可能性があります）。',
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
              openHandLocalizedText(
                context,
                zh: '二进制响应',
                zhHant: '二進位回應',
                en: 'Binary Response',
                fr: 'Réponse binaire',
                de: 'Binäre Antwort',
                ja: 'バイナリレスポンス',
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            kOpenHandGap4,
            Text(
              openHandLocalizedText(
                context,
                zh: '类型 ${mimeType ?? "(未知)"} · 大小约 ${text!.length ~/ 4 * 3} 字节（base64）',
                zhHant:
                    '類型 ${mimeType ?? "(未知)"} · 大小約 ${text!.length ~/ 4 * 3} 位元組（base64）',
                en: 'Type ${mimeType ?? "unknown"} · ~${text!.length ~/ 4 * 3} bytes (base64)',
                fr: 'Type ${mimeType ?? "inconnu"} · ~${text!.length ~/ 4 * 3} octets (base64)',
                de: 'Typ ${mimeType ?? "unbekannt"} · ~${text!.length ~/ 4 * 3} Byte (base64)',
                ja: '種類 ${mimeType ?? "不明"} · 約 ${text!.length ~/ 4 * 3} バイト（base64）',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            kOpenHandGap12,
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
  const _InitiatorTab({
    required this.controller,
    required this.entry,
    required this.isZh,
  });
  final WebReverseSessionController controller;
  final CdpNetworkEntry entry;
  final bool isZh;

  void _jumpToSource(String url, [int? line, int? col]) {
    if (url.isEmpty) return;
    controller.requestSourceJump(url: url, line: line ?? 0, col: col ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = entry.initiatorType ?? '-';
    final stack = entry.initiatorStack;
    final chain = entry.redirectChain;
    final initUrl = entry.initiatorUrl ?? '';
    final initLine = entry.initiatorLineNumber;
    final initCol = entry.initiatorColumnNumber;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _webReverseDashInitiatorLabel(context),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        kOpenHandGap6,
        _MetaRow(label: openHandTypeLabel(context), value: type),
        if (initUrl.isNotEmpty)
          _ClickableSourceRow(
            label: 'URL',
            url: initUrl,
            line: initLine,
            col: initCol,
            onTap: () => _jumpToSource(initUrl, initLine, initCol),
            isZh: isZh,
          ),
        if (initLine != null && initUrl.isEmpty)
          _MetaRow(
            label: openHandLocalizedText(
              context,
              zh: '行',
              zhHant: '行',
              en: 'Line',
              fr: 'Ligne',
              de: 'Zeile',
              ja: '行',
            ),
            value: '${initLine + 1}',
          ),
        kOpenHandGap14,
        Text(
          openHandLocalizedText(
            context,
            zh: '调用栈',
            zhHant: '呼叫堆疊',
            en: 'Call Stack',
            fr: 'Pile d’appels',
            de: 'Aufrufstack',
            ja: 'コールスタック',
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        kOpenHandGap6,
        if (stack.isEmpty)
          Text(
            openHandLocalizedText(
              context,
              zh: '(无堆栈，可能由解析器或预加载触发)',
              zhHant: '(無堆疊，可能由解析器或預載觸發)',
              en: '(no stack — parser/preload-triggered)',
              fr: '(aucune pile — déclenché par parseur/préchargement)',
              de: '(kein Stack — durch Parser/Vorladen ausgelöst)',
              ja: '(スタックなし — パーサーまたはプリロードによる可能性)',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          for (final frame in stack)
            _StackFrame(frame: frame, onJump: _jumpToSource, isZh: isZh),
        kOpenHandGap16,
        // Request Initiator Chain：重定向链按时间顺序展示，与 Chrome
        // DevTools 同名区段对齐。每一跳显示状态码 + URL + 跳转时间。
        Text(
          openHandLocalizedText(
            context,
            zh: '请求发起链（重定向）',
            zhHant: '請求發起鏈（重新導向）',
            en: 'Request Initiator Chain',
            fr: 'Chaîne d’initiateur',
            de: 'Auslöserkette',
            ja: 'リクエスト発起チェーン',
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        kOpenHandGap6,
        if (chain.isEmpty)
          Text(
            openHandLocalizedText(
              context,
              zh: '(此请求未发生重定向)',
              zhHant: '(此請求未發生重新導向)',
              en: '(no redirect — request reached origin directly)',
              fr: '(aucune redirection — requête directe)',
              de: '(keine Weiterleitung — Anfrage ging direkt zum Ursprung)',
              ja: '(リダイレクトなし — 直接到達)',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else ...[
          for (var i = 0; i < chain.length; i++)
            _RedirectStepRow(
              index: i + 1,
              step: chain[i],
              isFinal: false,
              isZh: isZh,
            ),
          _RedirectStepRow(
            index: chain.length + 1,
            // 最后一跳就是当前请求自己；用 entry 当前 url / status 复用同
            // 一渲染卡片，状态码取 entry.statusCode 让用户清楚最终结果。
            step: CdpRedirectStep(
              url: entry.url,
              status: entry.statusCode,
              statusText: entry.statusText,
              responseHeaders: entry.responseHeaders,
              at: entry.responseReceivedAt ?? entry.timestamp,
            ),
            isFinal: true,
            isZh: isZh,
          ),
        ],
      ],
    );
  }
}

/// 重定向链中的一跳。状态码彩色徽章 + URL 单击复制。
class _RedirectStepRow extends StatelessWidget {
  const _RedirectStepRow({
    required this.index,
    required this.step,
    required this.isFinal,
    required this.isZh,
  });

  final int index;
  final CdpRedirectStep step;
  final bool isFinal;
  final bool isZh;

  Color _statusColor(ColorScheme cs) {
    final s = step.status ?? 0;
    if (s >= 500) return cs.error;
    if (s >= 400) return cs.error.withValues(alpha: 0.8);
    if (s >= 300) return cs.tertiary;
    if (s >= 200) return cs.primary;
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _statusColor(cs);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '#$index',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8, top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: kOpenHandBorderRadius6,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
            child: Text(
              step.status?.toString() ?? '-',
              style: theme.textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  step.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: isFinal ? cs.primary : cs.onSurface,
                    fontWeight: isFinal ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  isFinal
                      ? openHandLocalizedText(
                          context,
                          zh: '当前请求（最终目标）',
                          zhHant: '目前請求（最終目標）',
                          en: 'final destination',
                          fr: 'destination finale',
                          de: 'Endziel',
                          ja: '最終宛先',
                        )
                      : '${step.statusText ?? ''}  ·  ${_timeOnly(step.at)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeOnly(DateTime t) {
    final s = t.toIso8601String().split('T').last.split('.').first;
    return s;
  }
}

/// 可点击跳转源码的元信息行。点击 URL 整体或行号箭头都会触发 onTap。
class _ClickableSourceRow extends StatelessWidget {
  const _ClickableSourceRow({
    required this.label,
    required this.url,
    required this.line,
    required this.col,
    required this.onTap,
    required this.isZh,
  });

  final String label;
  final String url;
  final int? line;
  final int? col;
  final VoidCallback onTap;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lineText = line == null ? '' : ':${line! + 1}';
    final colText = (col == null || col == 0) ? '' : ':${col! + 1}';
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
            child: Tooltip(
              message: _webReverseDashOpenInSourcesLabel(context),
              child: InkWell(
                onTap: onTap,
                borderRadius: kOpenHandBorderRadius4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 1,
                    horizontal: 2,
                  ),
                  child: Text(
                    '$url$lineText$colText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      color: cs.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: cs.primary.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
                fontFamily: kOpenHandMonospaceFontFamily,
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
  const _StackFrame({
    required this.frame,
    required this.onJump,
    required this.isZh,
  });
  final Map<String, Object?> frame;
  final void Function(String url, [int? line, int? col]) onJump;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fn = '${frame['functionName'] ?? '(anonymous)'}';
    final url = '${frame['url'] ?? ''}';
    final line = optionalIntFromValue(frame['lineNumber']);
    final col = optionalIntFromValue(frame['columnNumber']);
    final hasJump = url.isNotEmpty;
    final lineDisp = line == null ? '' : ':${line + 1}';
    final colDisp = (col == null || col == 0) ? '' : ':${col + 1}';
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasJump)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.arrow_outward_rounded,
                    size: 11,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                ),
              Flexible(
                child: Text(
                  fn.isEmpty ? '(anonymous)' : fn,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: hasJump ? cs.primary : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (hasJump)
            Text(
              '$url$lineDisp$colDisp',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: kOpenHandMonospaceFontFamily,
                decoration: TextDecoration.underline,
                decorationColor: cs.outlineVariant,
              ),
            ),
        ],
      ),
    );
    if (!hasJump) return body;
    return Tooltip(
      message: _webReverseDashOpenInSourcesLabel(context),
      child: InkWell(
        onTap: () => onJump(url, line, col),
        borderRadius: kOpenHandBorderRadius6,
        child: body,
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
    final phases = _computePhases(context, entry);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          openHandLocalizedText(
            context,
            zh: '阶段瀑布（Resource Timing）',
            zhHant: '階段瀑布（Resource Timing）',
            en: 'Phase Waterfall',
            fr: 'Cascade des phases',
            de: 'Phasen-Wasserfall',
            ja: 'フェーズウォーターフォール',
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        kOpenHandGap8,
        if (phases == null)
          Text(
            openHandLocalizedText(
              context,
              zh: '(浏览器尚未上报 ResourceTiming，常见于 service worker / from-cache / data: URL)',
              zhHant:
                  '(瀏覽器尚未上報 ResourceTiming，常見於 service worker / from-cache / data: URL)',
              en: '(no ResourceTiming reported — typical for service-worker / cached / data: URLs)',
              fr: '(ResourceTiming non reporté — fréquent avec service worker / cache / data: URL)',
              de: '(kein ResourceTiming gemeldet — typisch bei Service Worker / Cache / data: URL)',
              ja: '(ResourceTiming が未報告です。service worker / キャッシュ / data: URL でよく発生します)',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          _TimingWaterfall(phases: phases),
        kOpenHandGap18,
        Text(
          openHandLocalizedText(
            context,
            zh: '汇总',
            zhHant: '彙總',
            en: 'Summary',
            fr: 'Résumé',
            de: 'Zusammenfassung',
            ja: '概要',
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        kOpenHandGap6,
        _MetaRow(
          label: openHandLocalizedText(
            context,
            zh: '开始',
            zhHant: '開始',
            en: 'Started',
            fr: 'Début',
            de: 'Gestartet',
            ja: '開始',
          ),
          value: _fmt(start),
        ),
        _MetaRow(
          label: _webReverseDashResponseLabel(context),
          value: responseAt == null ? '-' : _fmt(responseAt),
        ),
        _MetaRow(
          label: openHandLocalizedText(
            context,
            zh: '完成',
            zhHant: '完成',
            en: 'Finished',
            fr: 'Fin',
            de: 'Beendet',
            ja: '完了',
          ),
          value: finishedAt == null ? '-' : _fmt(finishedAt),
        ),
        const Divider(height: 24),
        _MetaRow(
          label: openHandLocalizedText(
            context,
            zh: '首字节时间',
            zhHant: '首位元組時間',
            en: 'TTFB',
            fr: 'TTFB',
            de: 'TTFB',
            ja: 'TTFB',
          ),
          value: ttfb == null ? '-' : '$ttfb ms',
        ),
        _MetaRow(
          label: openHandLocalizedText(
            context,
            zh: '总耗时',
            zhHant: '總耗時',
            en: 'Total',
            fr: 'Total',
            de: 'Gesamt',
            ja: '合計',
          ),
          value: total == null ? '-' : '$total ms',
        ),
        if (entry.encodedDataLength != null)
          _MetaRow(
            label: openHandLocalizedText(
              context,
              zh: '编码后大小',
              zhHant: '編碼後大小',
              en: 'Encoded',
              fr: 'Encodé',
              de: 'Kodiert',
              ja: 'エンコード後',
            ),
            value: '${entry.encodedDataLength} bytes',
          ),
        if (entry.protocol != null && entry.protocol!.isNotEmpty)
          _MetaRow(
            label: openHandProtocolLabel(context),
            value: entry.protocol!,
          ),
        if (entry.remoteAddress != null && entry.remoteAddress!.isNotEmpty)
          _MetaRow(
            label: openHandLocalizedText(
              context,
              zh: '远端',
              zhHant: '遠端',
              en: 'Remote',
              fr: 'Distant',
              de: 'Remote',
              ja: 'リモート',
            ),
            value: entry.remoteAddress!,
          ),
      ],
    );
  }

  String _fmt(DateTime t) =>
      '${t.toIso8601String().split('T').last.split('.').first} (${t.toIso8601String().split('T').first})';

  /// 解析 CDP `Network.ResourceTiming` 为 Chrome 风格阶段列表。所有时间
  /// 字段除 requestTime（单调时钟秒）外都是相对 requestTime 的毫秒偏移；
  /// -1 / null 表示该阶段不存在（如纯 HTTP 时 sslStart/End 为 -1）。
  ///
  /// Chrome DevTools 的 9 个标准阶段：
  ///   Queueing / Stalled / Proxy / DNS Lookup / Initial Connection /
  ///   SSL / Request Sent / Waiting (TTFB) / Content Download
  static List<_TimingPhase>? _computePhases(
    BuildContext context,
    CdpNetworkEntry entry,
  ) {
    final t = entry.resourceTiming;
    if (t == null || t.isEmpty) return null;
    double? f(String k) {
      final v = t[k];
      if (v == null) return null;
      final d = v.toDouble();
      // CDP 用 -1 表示「该阶段未发生」。
      if (d < 0) return null;
      return d;
    }

    final phases = <_TimingPhase>[];
    void add(
      String label,
      double? from,
      double? to,
      Color Function(ColorScheme cs) color,
    ) {
      if (from == null || to == null) return;
      final dur = to - from;
      if (dur < 0) return;
      phases.add(
        _TimingPhase(label: label, startMs: from, endMs: to, color: color),
      );
    }

    // requestTime 是单调时钟秒，所有其余字段都相对它（毫秒）。
    // 我们直接在「相对毫秒」域里画图，不需要 wall clock。
    final proxyStart = f('proxyStart');
    final proxyEnd = f('proxyEnd');
    final dnsStart = f('dnsStart');
    final dnsEnd = f('dnsEnd');
    final connectStart = f('connectStart');
    final connectEnd = f('connectEnd');
    final sslStart = f('sslStart');
    final sslEnd = f('sslEnd');
    final sendStart = f('sendStart');
    final sendEnd = f('sendEnd');
    final receiveHeadersStart = f('receiveHeadersStart');
    final receiveHeadersEnd = f('receiveHeadersEnd');

    add(
      openHandLocalizedText(
        context,
        zh: '代理协商',
        zhHant: '代理協商',
        en: 'Proxy',
        fr: 'Proxy',
        de: 'Proxy',
        ja: 'プロキシ',
      ),
      proxyStart,
      proxyEnd,
      (cs) => cs.tertiary.withValues(alpha: 0.75),
    );
    add(
      openHandLocalizedText(
        context,
        zh: 'DNS 解析',
        zhHant: 'DNS 解析',
        en: 'DNS Lookup',
        fr: 'Résolution DNS',
        de: 'DNS-Auflösung',
        ja: 'DNS ルックアップ',
      ),
      dnsStart,
      dnsEnd,
      (cs) => Colors.indigo.shade400,
    );
    add(
      openHandLocalizedText(
        context,
        zh: '初始连接',
        zhHant: '初始連線',
        en: 'Initial Connection',
        fr: 'Connexion initiale',
        de: 'Erste Verbindung',
        ja: '初期接続',
      ),
      connectStart,
      connectEnd,
      (cs) => Colors.orange.shade400,
    );
    add(
      openHandLocalizedText(
        context,
        zh: 'SSL 握手',
        zhHant: 'SSL 握手',
        en: 'SSL',
        fr: 'SSL',
        de: 'SSL',
        ja: 'SSL',
      ),
      sslStart,
      sslEnd,
      (cs) => Colors.purple.shade400,
    );
    add(
      openHandLocalizedText(
        context,
        zh: '请求发送',
        zhHant: '請求傳送',
        en: 'Request Sent',
        fr: 'Requête envoyée',
        de: 'Anfrage gesendet',
        ja: 'リクエスト送信',
      ),
      sendStart,
      sendEnd,
      (cs) => Colors.teal.shade400,
    );
    // Waiting / TTFB：从 sendEnd 到 receiveHeadersEnd（如有 start 用之）。
    add(
      openHandLocalizedText(
        context,
        zh: '等待响应（TTFB）',
        zhHant: '等待回應（TTFB）',
        en: 'Waiting (TTFB)',
        fr: 'Attente (TTFB)',
        de: 'Warten (TTFB)',
        ja: '待機（TTFB）',
      ),
      sendEnd,
      receiveHeadersStart ?? receiveHeadersEnd,
      (cs) => Colors.green.shade400,
    );
    // 内容下载：headersEnd 到 loadingFinished 的相对偏移
    if (receiveHeadersEnd != null && entry.loadingFinishedAt != null) {
      final reqStartMs = entry.timestamp.millisecondsSinceEpoch.toDouble();
      final endMs = entry.loadingFinishedAt!.millisecondsSinceEpoch.toDouble();
      final downloadMs = endMs - reqStartMs - 0; // 近似：start = requestWillBeSent
      if (downloadMs > receiveHeadersEnd) {
        add(
          openHandLocalizedText(
            context,
            zh: '内容下载',
            zhHant: '內容下載',
            en: 'Content Download',
            fr: 'Téléchargement',
            de: 'Inhalt laden',
            ja: 'コンテンツダウンロード',
          ),
          receiveHeadersEnd,
          downloadMs,
          (cs) => Colors.blue.shade400,
        );
      }
    }
    if (phases.isEmpty) return null;
    return phases;
  }
}

class _TimingPhase {
  const _TimingPhase({
    required this.label,
    required this.startMs,
    required this.endMs,
    required this.color,
  });
  final String label;
  final double startMs;
  final double endMs;
  final Color Function(ColorScheme cs) color;
  double get durationMs => endMs - startMs;
}

/// Chrome 风格阶段瀑布图：每行 = 一个阶段，水平条按相对时间偏移定位，
/// 右侧列显示阶段耗时；末尾的 Total 行给出总跨度。
class _TimingWaterfall extends StatelessWidget {
  const _TimingWaterfall({required this.phases});
  final List<_TimingPhase> phases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = phases.map((p) => p.endMs).reduce((a, b) => a > b ? a : b);
    final firstStart = phases
        .map((p) => p.startMs)
        .reduce((a, b) => a < b ? a : b);
    final span = (total - firstStart).abs();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 左 label 列 130px，右 duration 列 80px，中间瀑布占剩余宽度。
          const labelW = 130.0;
          const durW = 80.0;
          final barTrackW = (constraints.maxWidth - labelW - durW - 16).clamp(
            40.0,
            700.0,
          );
          Widget row(_TimingPhase p) {
            final relStart = p.startMs - firstStart;
            final ratioStart = span <= 0 ? 0.0 : (relStart / span);
            final ratioEnd = span <= 0 ? 1.0 : ((p.endMs - firstStart) / span);
            final left = (ratioStart * barTrackW).clamp(0.0, barTrackW);
            final width = ((ratioEnd - ratioStart) * barTrackW).clamp(
              2.0,
              barTrackW,
            );
            final color = p.color(cs);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  SizedBox(
                    width: labelW,
                    child: Text(
                      p.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                  SizedBox(
                    width: barTrackW,
                    height: 12,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(kOpenHandRadius2),
                          ),
                        ),
                        Positioned(
                          left: left,
                          top: 0,
                          bottom: 0,
                          width: width,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(kOpenHandRadius2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: durW,
                    child: Text(
                      '${p.durationMs.toStringAsFixed(1)} ms',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in phases) row(p),
              kOpenHandGap6,
              Divider(height: 1, color: cs.outlineVariant),
              kOpenHandGap4,
              Row(
                children: [
                  const SizedBox(width: 130),
                  SizedBox(
                    width: barTrackW,
                    child: Text(
                      '0 ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${span.toStringAsFixed(1)} ms',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.text});
  final String text;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  // 内层水平 / 外层垂直各持一个 controller，避免 Scrollbar 蹭 Primary 又找不到
  // attached ScrollPosition 时抛 "Scrollbar's ScrollController has no
  // ScrollPosition attached"。两个轴分别独立的 controller 是正确做法。
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
      padding: const EdgeInsets.all(12),
      child: OpenHandSafeScrollbar(
        controller: _vCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _vCtrl,
          child: OpenHandSafeScrollbar(
            controller: _hCtrl,
            notificationPredicate: (n) => n.depth == 1,
            child: SingleChildScrollView(
              controller: _hCtrl,
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把请求序列化为 cURL 命令字符串。POSIX 模式用单引号 + `\'` 转义；
/// Windows cmd 用 `^"` 折行，简化处理沿用单行 + 双引号转义。
String _asCurl(CdpNetworkEntry e, {required bool windows}) {
  String quote(String s) {
    if (windows) {
      return '"${s.replaceAll('"', r'\"')}"';
    }
    return "'${s.replaceAll(r"'", r"'\''")}'";
  }

  final lineCont = windows ? ' ^\n  ' : ' \\\n  ';
  final buf = StringBuffer('curl ${quote(e.url)}');
  if (e.method.toUpperCase() != 'GET') {
    buf.write('$lineCont-X ${quote(e.method)}');
  }
  for (final entry in e.requestHeaders.entries) {
    final k = entry.key;
    if (k.startsWith(':')) continue; // HTTP/2 伪头
    buf.write('$lineCont-H ${quote("${entry.key}: ${entry.value}")}');
  }
  if (e.requestPostData != null && e.requestPostData!.isNotEmpty) {
    buf.write('$lineCont--data-raw ${quote(e.requestPostData!)}');
  }
  return buf.toString();
}

/// 把请求序列化为 fetch 调用。Node.js 模式不带 credentials/redirect 默认值。
String _asFetch(CdpNetworkEntry e, {required bool node}) {
  String esc(String s) =>
      '"${s.replaceAll(r'\\', r'\\\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';
  final headers = <String>[];
  e.requestHeaders.forEach((k, v) {
    if (k.startsWith(':')) return;
    headers.add('    ${esc(k)}: ${esc(v)}');
  });
  final init = <String>[];
  init.add('  "method": ${esc(e.method)}');
  if (headers.isNotEmpty) {
    init.add('  "headers": {\n${headers.join(',\n')}\n  }');
  }
  if (e.requestPostData != null && e.requestPostData!.isNotEmpty) {
    init.add('  "body": ${esc(e.requestPostData!)}');
  }
  if (!node) {
    init.add('  "credentials": "include"');
  }
  return 'fetch(${esc(e.url)}, {\n${init.join(',\n')}\n});';
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab({required this.entry, required this.isZh});
  final CdpNetworkEntry entry;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final frames = entry.wsFrames;
    if (frames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            openHandLocalizedText(
              context,
              zh: '尚未抓到 WebSocket 帧。在浏览器中触发动作后此处会实时刷新。',
              zhHant: '尚未抓到 WebSocket 訊框。在瀏覽器中觸發動作後此處會即時更新。',
              en: 'No WebSocket frames yet.',
              fr: 'Aucune trame WebSocket pour le moment.',
              de: 'Noch keine WebSocket-Frames.',
              ja: 'WebSocket フレームはまだありません。',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      reverse: true,
      itemCount: frames.length,
      itemBuilder: (_, idx) {
        final f = frames[frames.length - 1 - idx];
        final isSent = f.direction == CdpWebSocketDirection.sent;
        final isErr = f.direction == CdpWebSocketDirection.error;
        final color = isErr
            ? cs.errorContainer
            : (isSent ? cs.tertiaryContainer : cs.surfaceContainerHigh);
        final onColor = isErr
            ? cs.onErrorContainer
            : (isSent ? cs.onTertiaryContainer : cs.onSurface);
        final ts = f.timestamp
            .toIso8601String()
            .split('T')
            .last
            .split('.')
            .first;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: kOpenHandBorderRadius8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isErr
                          ? Icons.error_outline_rounded
                          : (isSent
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded),
                      size: 14,
                      color: onColor,
                    ),
                    kOpenHandHGap6,
                    Text(
                      _opcodeLabel(f.opcode),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        color: onColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandHGap12,
                    Text(
                      ts,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onColor.withValues(alpha: 0.7),
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${f.payload.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: onColor.withValues(alpha: 0.7),
                        fontFamily: kOpenHandMonospaceFontFamily,
                      ),
                    ),
                  ],
                ),
                kOpenHandGap4,
                SelectableText(
                  f.errorMessage ?? f.payload,
                  maxLines: 8,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: onColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _opcodeLabel(int op) => switch (op) {
    1 => 'TEXT',
    2 => 'BIN',
    8 => 'CLOSE',
    9 => 'PING',
    10 => 'PONG',
    _ => 'OP$op',
  };
}

/// Preview tab 内的图片预览：缩略图直接展示在面板中，
/// 点击弹出 `MediaPreviewDialog.bytes` 大图（与会话气泡里的图片预览复用）。
/// 优先使用已缓存的 base64 body 解码；缓存为空时降级到 [Image.network]
/// 的 URL 直拉模式（很多媒体站要求 referer，可能 401，这是预期行为）。
class _ImageInlinePreview extends StatelessWidget {
  const _ImageInlinePreview({
    required this.entry,
    required this.bytesText,
    required this.isZh,
  });

  final CdpNetworkEntry entry;
  final String? bytesText;
  final bool isZh;

  Uint8List? _decodeBytes() {
    final t = bytesText;
    if (t == null || t.isEmpty) return null;
    try {
      return decodeBase64Bounded(
        t,
        maxDecodedBytes: _kImageInlinePreviewMaxDecodedBytes,
      );
    } on BoundedBase64Exception {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bytes = _decodeBytes();
    final fallbackName = entry.url.split('?').first.split('/').last;
    final image = bytes != null
        ? Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (c, _, _) => _broken(cs),
          )
        : Image.network(
            entry.url,
            fit: BoxFit.contain,
            errorBuilder: (c, _, _) => _broken(cs),
          );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_rounded, size: 16, color: cs.primary),
              kOpenHandHGap6,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '点击图片可全屏预览',
                  zhHant: '點擊圖片可全螢幕預覽',
                  en: 'Tap to open large preview',
                  fr: 'Touchez l’image pour l’agrandir',
                  de: 'Bild antippen für große Vorschau',
                  ja: '画像をクリックして大きく表示',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          Expanded(
            child: Center(
              child: OpenHandTapRegion(
                onTap: () {
                  webReverseToolDialogs.show<void>(
                    context: context,
                    builder: (_) => bytes != null
                        ? MediaPreviewDialog.bytes(
                            bytes: bytes,
                            title: fallbackName.isEmpty
                                ? entry.url
                                : fallbackName,
                            sourceUrl: entry.url,
                            mimeType: entry.mimeType,
                          )
                        : MediaPreviewDialog.network(
                            url: entry.url,
                            title: fallbackName.isEmpty
                                ? entry.url
                                : fallbackName,
                            mimeType: entry.mimeType,
                          ),
                  );
                },
                child: Container(
                  decoration: webReverseSurfaceCardDecoration(cs),
                  padding: const EdgeInsets.all(8),
                  child: image,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _broken(ColorScheme cs) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Icon(Icons.broken_image_outlined, color: cs.error, size: 48),
    ),
  );
}

/// Preview tab 内的音频 / 视频预览：直接复用 MediaPreviewDialog 的内嵌
/// player surface 给一个紧凑控件；同时提供"全屏预览"按钮。
class _MediaInlinePreview extends StatelessWidget {
  const _MediaInlinePreview({
    required this.entry,
    required this.kind,
    required this.isZh,
  });

  final CdpNetworkEntry entry;
  final MediaPreviewKind kind;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fallbackName = entry.url.split('?').first.split('/').last;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                kind == MediaPreviewKind.audio
                    ? Icons.audiotrack_rounded
                    : Icons.movie_rounded,
                size: 16,
                color: cs.primary,
              ),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  fallbackName.isEmpty ? entry.url : fallbackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: cs.onSurface,
                  ),
                ),
              ),
              kOpenHandHGap8,
              FilledButton.tonalIcon(
                onPressed: () => webReverseToolDialogs.show<void>(
                  context: context,
                  builder: (_) => MediaPreviewDialog.network(
                    url: entry.url,
                    title: fallbackName.isEmpty ? entry.url : fallbackName,
                    mimeType: entry.mimeType,
                    kind: kind,
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '全屏预览',
                    zhHant: '全螢幕預覽',
                    en: 'Open large',
                    fr: 'Agrandir',
                    de: 'Groß öffnen',
                    ja: '大きく開く',
                  ),
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          // 紧凑播放器：直接走 MediaPreviewDialog.network 的核心 surface。
          // 这里我们简化为弹大图的入口已存在，inline 仅给一个引导 banner，
          // 避免对外置 Chrome 网络鉴权（Referer/Cookie）做无意义的二次 fetch。
          Container(
            height: kind == MediaPreviewKind.audio ? 96 : 220,
            decoration: webReverseSurfaceCardDecoration(cs),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '此请求识别为${kind == MediaPreviewKind.audio ? "音频" : "视频"}流，点击右上方「全屏预览」按钮即可在内嵌播放器中播放',
                    zhHant:
                        '此請求識別為${kind == MediaPreviewKind.audio ? "音訊" : "影片"}串流，點擊右上方「全螢幕預覽」即可在內嵌播放器中播放',
                    en: 'Detected as ${kind == MediaPreviewKind.audio ? "audio" : "video"} stream. Tap "Open large" to play in the embedded player.',
                    fr: 'Flux ${kind == MediaPreviewKind.audio ? "audio" : "vidéo"} détecté. Cliquez sur « Agrandir » pour lire dans le lecteur intégré.',
                    de: '${kind == MediaPreviewKind.audio ? "Audio" : "Video"}-Stream erkannt. Mit „Groß öffnen“ im eingebetteten Player abspielen.',
                    ja: '${kind == MediaPreviewKind.audio ? "音声" : "動画"}ストリームとして検出されました。「大きく開く」で内蔵プレーヤー再生できます。',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _webReverseDashInitiatorLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '发起方',
    zhHant: '發起方',
    en: 'Initiator',
    fr: 'Initiateur',
    de: 'Auslöser',
    ja: 'イニシエーター',
  );
}

String _webReverseDashOpenInSourcesLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '在 Sources 中打开',
    zhHant: '在 Sources 中開啟',
    en: 'Open in Sources',
    fr: 'Ouvrir dans Sources',
    de: 'In Sources öffnen',
    ja: 'Sources で開く',
  );
}

String _webReverseDashResponseLabel(BuildContext context) {
  return openHandResponseLabel(context);
}

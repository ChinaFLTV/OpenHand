part of 'web_reverse_dashboard_dialog.dart';

/// 资源类型筛选条的固定高度。
const double _kResourceFilterBarHeight = 38;

const double _kReplayResultDialogWidth = 640;
const double _kReplayResultDialogHeight = 360;
const double _kNetworkMethodColumnWidth = 78;
const double _kNetworkStatusColumnWidth = 48;
const double _kNetworkTypeColumnWidth = 88;
const Duration _kReplaySnackBarDuration = Duration(seconds: 2);
const Duration _kNetworkCopySnackBarDuration = Duration(seconds: 1);

Future<void> _copyNetworkText(
  BuildContext context, {
  required String text,
  required String base,
  Duration duration = _kNetworkCopySnackBarDuration,
}) async {
  await copyWebReverseTextToClipboard(
    context: context,
    text: text,
    successBase: base,
    logTag: 'web_reverse_network_panel',
    logAction: '复制文本',
    successDuration: duration,
  );
}

/// Network 资源类型过滤——对标 Chrome DevTools 顶部的 All / Fetch+XHR / JS / CSS
/// / Img / Media / Manifest / WS / Wasm / Doc / Other 按钮组。
///
/// `match` 直接接收一条 entry 的 resourceType（CDP `type`）以及 mimeType，
/// 返回是否命中该过滤项。这样一份过滤规则就能覆盖 Network 列表 + 所有视图统计。
enum _ResourceFilter {
  all,
  fetchXhr,
  doc,
  css,
  js,
  font,
  img,
  media,
  manifest,
  ws,
  wasm,
  other;

  String label(BuildContext context) => switch (this) {
    _ResourceFilter.all => openHandAllLabel(context),
    _ResourceFilter.fetchXhr => 'Fetch/XHR',
    _ResourceFilter.doc => openHandLocalizedText(
      context,
      zh: '文档',
      zhHant: '文件',
      en: 'Doc',
      fr: 'Doc',
      de: 'Dok.',
      ja: '文書',
    ),
    _ResourceFilter.css => 'CSS',
    _ResourceFilter.js => 'JS',
    _ResourceFilter.font => openHandLocalizedText(
      context,
      zh: '字体',
      zhHant: '字型',
      en: 'Font',
      fr: 'Police',
      de: 'Font',
      ja: 'フォント',
    ),
    _ResourceFilter.img => openHandLocalizedText(
      context,
      zh: '图片',
      zhHant: '圖片',
      en: 'Img',
      fr: 'Img',
      de: 'Bild',
      ja: '画像',
    ),
    _ResourceFilter.media => openHandLocalizedText(
      context,
      zh: '媒体',
      zhHant: '媒體',
      en: 'Media',
      fr: 'Média',
      de: 'Medien',
      ja: 'メディア',
    ),
    _ResourceFilter.manifest => 'Manifest',
    _ResourceFilter.ws => 'WS',
    _ResourceFilter.wasm => 'Wasm',
    _ResourceFilter.other => openHandLocalizedText(
      context,
      zh: '其他',
      zhHant: '其他',
      en: 'Other',
      fr: 'Autre',
      de: 'Andere',
      ja: 'その他',
    ),
  };

  bool matches(CdpNetworkEntry e) {
    final t = e.resourceType.toLowerCase();
    final m = (e.mimeType ?? '').toLowerCase();
    return switch (this) {
      _ResourceFilter.all => true,
      _ResourceFilter.fetchXhr => t == 'fetch' || t == 'xhr',
      _ResourceFilter.doc => t == 'document',
      _ResourceFilter.css => t == 'stylesheet',
      _ResourceFilter.js => t == 'script' || m.contains('javascript'),
      _ResourceFilter.font => t == 'font' || m.startsWith('font/'),
      _ResourceFilter.img => t == 'image' || isImageMimeType(m),
      _ResourceFilter.media =>
        t == 'media' || isAudioMimeType(m) || isVideoMimeType(m),
      _ResourceFilter.manifest => t == 'manifest',
      _ResourceFilter.ws => t == 'websocket' || t == 'eventsource',
      _ResourceFilter.wasm => t == 'wasm' || m.contains('wasm'),
      _ResourceFilter.other => !<String>[
        'fetch',
        'xhr',
        'document',
        'stylesheet',
        'script',
        'font',
        'image',
        'media',
        'manifest',
        'websocket',
        'eventsource',
        'wasm',
      ].contains(t),
    };
  }
}

class _NetworkBody extends StatelessWidget {
  const _NetworkBody({
    required this.state,
    required this.controller,
    required this.isZh,
    required this.reduceMotion,
  });

  final _WebReverseDashboardDialogState state;
  final WebReverseSessionController controller;
  final bool isZh;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = controller.networkRequests;
    final filterText = state._networkFilter.toLowerCase();
    final resourceFilter = state._resourceFilter;

    bool match(CdpNetworkEntry e) {
      if (!resourceFilter.matches(e)) return false;
      if (filterText.isEmpty) return true;
      return e.url.toLowerCase().contains(filterText) ||
          e.method.toLowerCase().contains(filterText);
    }

    final filtered = all.where(match).toList(growable: false);
    final selected = state._selectedRequest;
    final hasSelection =
        selected != null && _networkByIdContains(all, selected.requestId);
    return Column(
      children: [
        if (controller.isFetchInterceptEnabled)
          _PendingFetchBanner(controller: controller),
        _ResourceFilterBar(
          value: resourceFilter,
          onChanged: (v) => state.rebuildFromExternal(() {
            state._resourceFilter = v;
            // 切过滤后选中条目可能被过滤掉，自动收起详情。
            if (state._selectedRequest != null &&
                !v.matches(state._selectedRequest!)) {
              state._selectedRequest = null;
            }
          }),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          // 详情面板进出动画：用 AnimatedSwitcher 把"列表
          // 独占" 与 "列表 + 详情" 两种 layout 之间的切换包裹起来，
          // 详情侧从右滑入并淡入；关闭时反向滑出。同时面板宽度由
          // AnimatedSize 缓动，避免直接 size jump 导致的视觉硬切。
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : kOpenHandMotion280,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final fade = FadeTransition(opacity: animation, child: child);
              if (child.key == const ValueKey<String>('with-detail')) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: fade,
                );
              }
              return fade;
            },
            child: hasSelection
                ? ResizableSplitter(
                    key: const ValueKey<String>('with-detail'),
                    initialLeftFraction: 0.4,
                    minLeft: 320,
                    minRight: 360,
                    left: _NetworkList(
                      items: filtered,
                      listKey: state._networkListKey,
                      selectedId: selected.requestId,
                      onSelect: (e) => state.rebuildFromExternal(
                        () => state._selectedRequest = e,
                      ),
                      onCopyUrl: (e) => _copyUrl(context, e),
                      controller: controller,
                      reduceMotion: reduceMotion,
                    ),
                    right: _RequestDetailPanel(
                      controller: controller,
                      entry: selected,
                      isZh: isZh,
                      reduceMotion: reduceMotion,
                      onClose: () => state.rebuildFromExternal(
                        () => state._selectedRequest = null,
                      ),
                    ),
                  )
                : _NetworkList(
                    key: const ValueKey<String>('list-only'),
                    items: filtered,
                    listKey: state._networkListKey,
                    selectedId: null,
                    onSelect: (e) => state.rebuildFromExternal(
                      () => state._selectedRequest = e,
                    ),
                    onCopyUrl: (e) => _copyUrl(context, e),
                    controller: controller,
                    reduceMotion: reduceMotion,
                  ),
          ),
        ),
      ],
    );
  }

  bool _networkByIdContains(List<CdpNetworkEntry> all, String id) {
    for (final e in all) {
      if (e.requestId == id) return true;
    }
    return false;
  }

  Future<void> _copyUrl(BuildContext context, CdpNetworkEntry e) async {
    await _copyNetworkText(
      context,
      text: e.url,
      base: _webReverseDashUrlCopiedLabel(context),
    );
  }
}

/// 资源类型过滤栏：水平滚动的胶囊组。
class _ResourceFilterBar extends StatelessWidget {
  const _ResourceFilterBar({required this.value, required this.onChanged});

  final _ResourceFilter value;
  final ValueChanged<_ResourceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kResourceFilterBarHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (final f in _ResourceFilter.values) ...[
              _TextTabPill(
                label: f.label(context),
                active: f == value,
                onTap: () => onChanged(f),
                dense: true,
              ),
              kOpenHandHGap6,
            ],
          ],
        ),
      ),
    );
  }
}

class _NetworkList extends StatelessWidget {
  const _NetworkList({
    super.key,
    required this.items,
    required this.listKey,
    required this.selectedId,
    required this.onSelect,
    required this.onCopyUrl,
    required this.controller,
    required this.reduceMotion,
  });

  final List<CdpNetworkEntry> items;
  final GlobalKey<AnimatedListState> listKey;
  final String? selectedId;
  final ValueChanged<CdpNetworkEntry> onSelect;
  final ValueChanged<CdpNetworkEntry> onCopyUrl;
  final WebReverseSessionController controller;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return OpenHandInlineEmptyState(
        message: openHandLocalizedText(
          context,
          zh: '暂无网络请求。在浏览器中操作页面后此处会实时刷新。',
          zhHant: '暫無網路請求。在瀏覽器中操作頁面後此處會即時更新。',
          en: 'No network requests yet. Interact with the page to populate this view.',
          fr: 'Aucune requête réseau. Interagissez avec la page pour remplir cette vue.',
          de: 'Noch keine Netzwerkanfragen. Interagieren Sie mit der Seite, um diese Ansicht zu füllen.',
          ja: 'ネットワークリクエストはまだありません。ページを操作するとここに表示されます。',
        ),
      );
    }
    // 计算 Waterfall 时间窗：取列表中最早的 timestamp 与最晚的 finishedAt 作为
    // 总轴；不足 200ms 时强制拉到 200ms 避免短请求条带塌缩。
    final earliest = items
        .map((e) => e.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = items.fold<DateTime>(earliest, (acc, e) {
      final tail = e.loadingFinishedAt ?? e.responseReceivedAt ?? e.timestamp;
      return tail.isAfter(acc) ? tail : acc;
    });
    var totalMs = latest.difference(earliest).inMilliseconds;
    if (totalMs < 200) totalMs = 200;
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (_, idx) {
        final e = items[items.length - 1 - idx];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: AppearOnce(
            duration: _kSwitchDuration,
            child: _NetworkRow(
              entry: e,
              earliest: earliest,
              totalMs: totalMs,
              selected: e.requestId == selectedId,
              onTap: () => onSelect(e),
              onCopyUrl: () => onCopyUrl(e),
              controller: controller,
            ),
          ),
        );
      },
    );
  }
}

class _NetworkMetaCell extends StatelessWidget {
  const _NetworkMetaCell({
    required this.width,
    required this.text,
    required this.style,
  });

  final double width;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: style,
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.entry,
    required this.earliest,
    required this.totalMs,
    required this.selected,
    required this.onTap,
    required this.onCopyUrl,
    required this.controller,
  });

  final CdpNetworkEntry entry;
  final DateTime earliest;
  final int totalMs;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyUrl;
  final WebReverseSessionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = selected
        ? cs.primaryContainer
        : entry.isError
        ? cs.errorContainer
        : (entry.statusCode != null && entry.statusCode! >= 300
              ? cs.tertiaryContainer
              : cs.surfaceContainerHigh);
    final onColor = selected
        ? cs.onPrimaryContainer
        : entry.isError
        ? cs.onErrorContainer
        : (entry.statusCode != null && entry.statusCode! >= 300
              ? cs.onTertiaryContainer
              : cs.onSurface);
    final fileName = _extractFileName(entry.url);
    final blocked = controller.blockedUrls.contains(entry.url);
    return Material(
      color: color,
      borderRadius: kOpenHandBorderRadius8,
      child: InkWell(
        onTap: onTap,
        onLongPress: onCopyUrl,
        onSecondaryTapUp: (d) => _showRowMenu(context, d.globalPosition),
        borderRadius: kOpenHandBorderRadius8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              _NetworkMetaCell(
                width: _kNetworkMethodColumnWidth,
                text: entry.method,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  color: onColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _NetworkMetaCell(
                width: _kNetworkStatusColumnWidth,
                text:
                    entry.statusCode?.toString() ??
                    (entry.failed ? 'ERR' : '...'),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  color: onColor,
                ),
              ),
              _NetworkMetaCell(
                width: _kNetworkTypeColumnWidth,
                text: entry.resourceType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onColor.withValues(alpha: 0.75),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    color: onColor,
                  ),
                ),
              ),
              kOpenHandHGap8,
              // Waterfall：宽 140，按整窗 totalMs 推算条带 left/width。
              Expanded(
                flex: 2,
                child: _Waterfall(
                  entry: entry,
                  earliest: earliest,
                  totalMs: totalMs,
                  selected: selected,
                ),
              ),
              if (blocked)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: openHandLocalizedText(
                      context,
                      zh: '已屏蔽',
                      zhHant: '已封鎖',
                      en: 'Blocked',
                      fr: 'Bloqué',
                      de: 'Blockiert',
                      ja: 'ブロック済み',
                    ),
                    child: Icon(Icons.block_rounded, size: 14, color: cs.error),
                  ),
                ),
              if (entry.fromCache)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.cached_rounded,
                    size: 14,
                    color: onColor.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRowMenu(BuildContext context, Offset position) async {
    final blocked = controller.blockedUrls.contains(entry.url);
    final selected = await showAnimatedPointerMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        PopupMenuItem(
          value: 'copy_url',
          child: Row(
            children: [
              const Icon(Icons.link_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制 URL',
                  zhHant: '複製 URL',
                  en: 'Copy URL',
                  fr: 'Copier l’URL',
                  de: 'URL kopieren',
                  ja: 'URL をコピー',
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_curl',
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制为 cURL',
                  zhHant: '複製為 cURL',
                  en: 'Copy as cURL',
                  fr: 'Copier en cURL',
                  de: 'Als cURL kopieren',
                  ja: 'cURL としてコピー',
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_fetch',
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '复制为 fetch',
                  zhHant: '複製為 fetch',
                  en: 'Copy as fetch',
                  fr: 'Copier en fetch',
                  de: 'Als fetch kopieren',
                  ja: 'fetch としてコピー',
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'replay',
          child: Row(
            children: [
              const Icon(Icons.replay_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '重放此请求',
                  zhHant: '重放此請求',
                  en: 'Replay XHR',
                  fr: 'Rejouer la requête',
                  de: 'Anfrage wiederholen',
                  ja: 'このリクエストを再実行',
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'replayEdit',
          child: Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 16),
              kOpenHandHGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '编辑后重放（改 URL / Header）',
                  zhHant: '編輯後重放（改 URL / Header）',
                  en: 'Edit & replay',
                  fr: 'Modifier et rejouer',
                  de: 'Bearbeiten & wiederholen',
                  ja: '編集して再実行',
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (blocked)
          PopupMenuItem(
            value: 'unblock',
            child: Row(
              children: [
                const Icon(Icons.lock_open_rounded, size: 16),
                kOpenHandHGap8,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '取消屏蔽该 URL',
                    zhHant: '取消封鎖該 URL',
                    en: 'Unblock URL',
                    fr: 'Débloquer l’URL',
                    de: 'URL entsperren',
                    ja: 'URL のブロックを解除',
                  ),
                ),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'block',
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 16),
                kOpenHandHGap8,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '屏蔽此 URL',
                    zhHant: '封鎖此 URL',
                    en: 'Block this URL',
                    fr: 'Bloquer cette URL',
                    de: 'Diese URL blockieren',
                    ja: 'この URL をブロック',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'copy_url':
        await _copyNetworkText(
          context,
          text: entry.url,
          base: _webReverseDashUrlCopiedLabel(context),
        );
      case 'copy_curl':
        await _copyNetworkText(
          context,
          text: _asCurl(entry, windows: false),
          base: openHandLocalizedText(
            context,
            zh: '已复制 cURL',
            zhHant: '已複製 cURL',
            en: 'cURL copied',
            fr: 'cURL copié',
            de: 'cURL kopiert',
            ja: 'cURL をコピーしました',
          ),
        );
      case 'copy_fetch':
        await _copyNetworkText(
          context,
          text: _asFetch(entry, node: false),
          base: openHandLocalizedText(
            context,
            zh: '已复制 fetch',
            zhHant: '已複製 fetch',
            en: 'fetch copied',
            fr: 'fetch copié',
            de: 'fetch kopiert',
            ja: 'fetch をコピーしました',
          ),
        );
      case 'block':
        await controller.blockUrl(entry.url);
        if (!context.mounted) return;
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已屏蔽该 URL',
            zhHant: '已封鎖該 URL',
            en: 'URL blocked',
            fr: 'URL bloquée',
            de: 'URL blockiert',
            ja: 'URL をブロックしました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      case 'unblock':
        await controller.unblockUrl(entry.url);
        if (!context.mounted) return;
        showOpenHandInfoSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已取消屏蔽',
            zhHant: '已取消封鎖',
            en: 'URL unblocked',
            fr: 'URL débloquée',
            de: 'URL entsperrt',
            ja: 'URL のブロックを解除しました',
          ),
          duration: kOpenHandSnackBarBriefDuration,
        );
      case 'replay':
        if (!context.mounted) return;
        await _replayAndShow(context);
      case 'replayEdit':
        if (!context.mounted) return;
        await _replayWithOverridesAndShow(context);
    }
  }

  Future<void> _replayWithOverridesAndShow(BuildContext context) async {
    final overrides = await webReverseToolDialogs
        .show<({String url, Map<String, String> headers})>(
          context: context,
          builder: (_) => _ReplayOverrideEditor(entry: entry),
        );
    if (overrides == null || !context.mounted) return;
    await _runReplayAndShow(
      context,
      overrideUrl: overrides.url,
      overrideHeaders: overrides.headers,
    );
  }

  Future<void> _replayAndShow(BuildContext context) async {
    await _runReplayAndShow(context);
  }

  Future<void> _runReplayAndShow(
    BuildContext context, {
    String? overrideUrl,
    Map<String, String>? overrideHeaders,
  }) async {
    final result = await _replayRequestWithLoading(
      context,
      overrideUrl: overrideUrl,
      overrideHeaders: overrideHeaders,
    );
    if (!context.mounted) return;
    if (result == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '重放失败',
          zhHant: '重放失敗',
          en: 'Replay failed',
          fr: 'Échec de la relecture',
          de: 'Wiederholung fehlgeschlagen',
          ja: '再実行に失敗しました',
        ),
        duration: _kReplaySnackBarDuration,
      );
      return;
    }
    await _showReplayResultDialog(context, result);
  }

  Future<({int status, String body})?> _replayRequestWithLoading(
    BuildContext context, {
    String? overrideUrl,
    Map<String, String>? overrideHeaders,
  }) async {
    final loadingDialog = showOpenHandTrackedLoadingDialog(
      context: context,
      message: openHandLocalizedText(
        context,
        zh: '重放中...',
        zhHant: '重放中...',
        en: 'Replaying...',
        fr: 'Relecture...',
        de: 'Wiederholung läuft...',
        ja: '再実行中...',
      ),
    );
    try {
      return await controller.replayRequest(
        entry,
        overrideUrl: overrideUrl,
        overrideHeaders: overrideHeaders,
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '重放网络请求记录', error, stack);
      return null;
    } finally {
      await loadingDialog.dismiss(
        logTag: 'web_reverse_dashboard_dialog',
        logAction: '关闭重放加载对话框',
      );
    }
  }

  Future<void> _showReplayResultDialog(
    BuildContext context,
    ({int status, String body}) result,
  ) {
    final body = result.body;
    final bodyText = body.isEmpty
        ? openHandLocalizedText(
            context,
            zh: '(响应体为空)',
            zhHant: '(回應體為空)',
            en: '(empty body)',
            fr: '(corps vide)',
            de: '(leerer Body)',
            ja: '(レスポンス本文は空です)',
          )
        : body;
    return webReverseToolDialogs.show<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandAlertDialog(
        title: Text(
          openHandLocalizedText(
            dialogContext,
            zh: '重放结果（HTTP ${result.status}）',
            zhHant: '重放結果（HTTP ${result.status}）',
            en: 'Replay (HTTP ${result.status})',
            fr: 'Relecture (HTTP ${result.status})',
            de: 'Wiederholung (HTTP ${result.status})',
            ja: '再実行結果（HTTP ${result.status}）',
          ),
        ),
        content: SizedBox(
          width: _kReplayResultDialogWidth,
          height: _kReplayResultDialogHeight,
          child: SingleChildScrollView(
            child: SelectableText(
              bodyText,
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
              ),
            ),
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              await _copyNetworkText(
                dialogContext,
                text: body,
                base: openHandLocalizedText(
                  dialogContext,
                  zh: '响应体已复制',
                  zhHant: '已複製回應體',
                  en: 'Body copied',
                  fr: 'Corps copié',
                  de: 'Body kopiert',
                  ja: '本文をコピーしました',
                ),
              );
            },
            label: openHandLocalizedText(
              dialogContext,
              zh: '复制响应体',
              zhHant: '複製回應體',
              en: 'Copy body',
              fr: 'Copier le corps',
              de: 'Body kopieren',
              ja: '本文をコピー',
            ),
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: openHandCloseLabel(dialogContext),
          ),
        ],
      ),
    );
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      if (segs.isNotEmpty && segs.last.isNotEmpty) {
        final qs = uri.hasQuery ? '?${uri.query}' : '';
        return '${segs.last}$qs';
      }
      return uri.host;
    } catch (_) {
      return url;
    }
  }
}

/// Waterfall 单行：用两段条带表示「请求—响应」「响应—结束」两个时间区间。
/// 颜色随选中态切换；总轴长度由父级算好的 totalMs 控制。
class _Waterfall extends StatelessWidget {
  const _Waterfall({
    required this.entry,
    required this.earliest,
    required this.totalMs,
    required this.selected,
  });

  final CdpNetworkEntry entry;
  final DateTime earliest;
  final int totalMs;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final start = entry.timestamp.difference(earliest).inMilliseconds;
    final mid =
        (entry.responseReceivedAt ?? entry.loadingFinishedAt ?? entry.timestamp)
            .difference(earliest)
            .inMilliseconds;
    final end =
        (entry.loadingFinishedAt ?? entry.responseReceivedAt ?? entry.timestamp)
            .difference(earliest)
            .inMilliseconds;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w <= 0 || totalMs <= 0) return const SizedBox.shrink();
        double xOf(int ms) => (ms.clamp(0, totalMs) / totalMs) * w;
        final leftX = xOf(start);
        final midX = xOf(mid);
        final endX = xOf(end);
        final waitW = (midX - leftX).clamp(2.0, w);
        final downloadW = (endX - midX).clamp(0.0, w);
        return SizedBox(
          height: 16,
          child: Stack(
            children: [
              Positioned(
                left: leftX,
                top: 5,
                child: Container(
                  width: waitW,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                        : cs.primary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(kOpenHandRadius3),
                  ),
                ),
              ),
              if (downloadW > 0)
                Positioned(
                  left: midX,
                  top: 5,
                  child: Container(
                    width: downloadW,
                    height: 6,
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.tertiary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(kOpenHandRadius3),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 拦截模式横幅：列出待决策请求 + 全部放行/逐条 abort。
/// 仅在 controller.isFetchInterceptEnabled 时显示。
class _PendingFetchBanner extends StatelessWidget {
  const _PendingFetchBanner({required this.controller});

  final WebReverseSessionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = controller.pendingFetchRequests;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 16, color: cs.onTertiaryContainer),
          kOpenHandHGap6,
          Expanded(
            child: Text(
              openHandLocalizedText(
                context,
                zh: '请求拦截已启用：${pending.length} 个请求待决策，超过 ${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds} 秒自动放行。',
                zhHant:
                    '請求攔截已啟用：${pending.length} 個請求待決策，超過 ${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds} 秒自動放行。',
                en: 'Request intercept on: ${pending.length} pending; auto-continue after ${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds}s.',
                fr: 'Interception activée : ${pending.length} en attente ; poursuite automatique après ${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds} s.',
                de: 'Request-Interception aktiv: ${pending.length} ausstehend; nach ${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds} s automatisch fortsetzen.',
                ja: 'リクエスト傍受中: ${pending.length} 件。${WebReverseSessionController.fetchInterceptPendingTimeoutSeconds} 秒後に自動続行します。',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (pending.isNotEmpty) ...[
            FilledButton.tonal(
              onPressed: controller.continueAllFetch,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '全部放行',
                  zhHant: '全部放行',
                  en: 'Continue all',
                  fr: 'Tout continuer',
                  de: 'Alle fortsetzen',
                  ja: 'すべて続行',
                ),
              ),
            ),
            kOpenHandHGap6,
            AnimatedPopupMenuButton<String>(
              tooltip: openHandLocalizedText(
                context,
                zh: '查看待决策请求',
                zhHant: '查看待決策請求',
                en: 'Pending requests',
                fr: 'Requêtes en attente',
                de: 'Ausstehende Anfragen',
                ja: '保留中のリクエスト',
              ),
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              itemBuilder: (_) => [
                for (final p in pending.take(20))
                  PopupMenuItem(
                    value: p.requestId,
                    onTap: () => _showActions(context, p),
                    child: Text(
                      '${p.method} ${p.url}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showActions(
    BuildContext context,
    ({String requestId, String method, String url}) p,
  ) {
    startSafeTimer(
      Duration.zero,
      () async {
        if (!context.mounted) return;
        final action = await webReverseToolDialogs.show<String>(
          context: context,
          builder: (dialogContext) => buildOpenHandAlertDialog(
            title: Text(
              openHandLocalizedText(
                dialogContext,
                zh: '处理拦截请求',
                zhHant: '處理攔截請求',
                en: 'Handle intercepted request',
                fr: 'Traiter la requête interceptée',
                de: 'Abgefangene Anfrage bearbeiten',
                ja: '傍受リクエストを処理',
              ),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.method} ${p.url}',
                    style: const TextStyle(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop('Aborted'),
                label: openHandLocalizedText(
                  dialogContext,
                  zh: '中止',
                  zhHant: '中止',
                  en: 'Abort',
                  fr: 'Abandonner',
                  de: 'Abbrechen',
                  ja: '中止',
                ),
              ),
              OpenHandDialogActionButton.secondary(
                onPressed: () =>
                    Navigator.of(dialogContext).pop('AccessDenied'),
                label: 'AccessDenied',
              ),
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop('TimedOut'),
                label: 'TimedOut',
              ),
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(dialogContext).pop('edit'),
                label: openHandLocalizedText(
                  dialogContext,
                  zh: '修改放行',
                  zhHant: '修改後放行',
                  en: 'Modify & continue',
                  fr: 'Modifier et continuer',
                  de: 'Ändern & fortsetzen',
                  ja: '変更して続行',
                ),
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(dialogContext).pop('continue'),
                label: openHandLocalizedText(
                  dialogContext,
                  zh: '继续',
                  zhHant: '繼續',
                  en: 'Continue',
                  fr: 'Continuer',
                  de: 'Fortsetzen',
                  ja: '続行',
                ),
              ),
            ],
          ),
        );
        if (action == null || !context.mounted) return;
        if (action == 'continue') {
          await controller.continueFetchRequest(p.requestId);
        } else if (action == 'edit') {
          await _showEditDialog(context, p);
        } else {
          await controller.abortFetchRequest(p.requestId, reason: action);
        }
      },
      onError: (error, stack) =>
          silentLog('web_reverse_dashboard_dialog', '处理被拦截的网络请求', error, stack),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    ({String requestId, String method, String url}) p,
  ) async {
    final urlCtrl = TextEditingController(text: p.url);
    final methodCtrl = TextEditingController(text: p.method);
    final headersCtrl = TextEditingController(); // 一行 key:value
    final bodyCtrl = TextEditingController();
    try {
      final result = await showOpenHandFormDialog<bool>(
        context: context,
        title: openHandLocalizedText(
          context,
          zh: '修改请求后放行',
          zhHant: '修改請求後放行',
          en: 'Modify and continue',
          fr: 'Modifier et continuer',
          de: 'Ändern und fortsetzen',
          ja: '変更して続行',
        ),
        submitLabel: openHandLocalizedText(
          context,
          zh: '放行',
          zhHant: '放行',
          en: 'Send',
          fr: 'Envoyer',
          de: 'Senden',
          ja: '送信',
        ),
        cancelLabel: openHandCancelLabel(context),
        maxWidth: 560,
        onSubmit: (_) => true,
        contentBuilder: (_) => SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  maxLength: WebReverseSessionController.maxBreakpointTextChars,
                  decoration: const InputDecoration(labelText: 'URL'),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                kOpenHandGap8,
                TextField(
                  controller: methodCtrl,
                  maxLength: WebReverseSessionController.maxRuleMethodChars,
                  decoration: const InputDecoration(labelText: 'Method'),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                kOpenHandGap8,
                TextField(
                  controller: headersCtrl,
                  maxLength: WebReverseSessionController.maxRuleHeadersChars,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: 'Headers（每行 Key: Value，留空则保持原样）',
                      zhHant: 'Headers（每行 Key: Value，留空則保持原樣）',
                      en: 'Headers (Key: Value per line; empty = keep original)',
                      fr: 'Headers (Key: Value par ligne ; vide = conserver)',
                      de: 'Headers (Key: Value pro Zeile; leer = beibehalten)',
                      ja: 'Headers（1 行 Key: Value、空なら維持）',
                    ),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
                kOpenHandGap8,
                TextField(
                  controller: bodyCtrl,
                  maxLength:
                      WebReverseSessionController.maxEditedRequestBodyChars,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: openHandLocalizedText(
                      context,
                      zh: 'Body（留空则保持原样）',
                      zhHant: 'Body（留空則保持原樣）',
                      en: 'Body (empty = keep original)',
                      fr: 'Body (vide = conserver)',
                      de: 'Body (leer = beibehalten)',
                      ja: 'Body（空なら維持）',
                    ),
                  ),
                  style: const TextStyle(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (result != true) return;
      final headersRaw = headersCtrl.text.trim();
      final headers = headersRaw.isEmpty ? null : _parseHeaderLines(headersRaw);
      final body = bodyCtrl.text;
      final bodyB64 = body.isEmpty ? null : base64Encode(utf8.encode(body));
      await controller.continueFetchRequestEdited(
        p.requestId,
        url: nullIfBlank(urlCtrl.text),
        method: nullIfBlank(methodCtrl.text),
        headers: headers,
        postDataBase64: bodyB64,
      );
    } finally {
      urlCtrl.dispose();
      methodCtrl.dispose();
      headersCtrl.dispose();
      bodyCtrl.dispose();
    }
  }
}

/// 编辑后重放对话框：直接复刻 _InterceptRuleEditor 的字段设计（URL +
/// header overrides），让用户先 rewrite 再 replay 一次单条请求；与拦截规则
/// editor 行为一致，区别在 block 路径不暴露（重放只关心 url / headers）。
class _ReplayOverrideEditor extends StatefulWidget {
  const _ReplayOverrideEditor({required this.entry});

  final CdpNetworkEntry entry;

  @override
  State<_ReplayOverrideEditor> createState() => _ReplayOverrideEditorState();
}

class _ReplayOverrideEditorState extends State<_ReplayOverrideEditor> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.entry.url);
    _headersCtrl = TextEditingController(
      text: _formatHeaderLines(widget.entry.requestHeaders),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return buildOpenHandDialogFormShell(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '编辑后重放',
        zhHant: '編輯後重放',
        en: 'Edit & replay',
        fr: 'Modifier et rejouer',
        de: 'Bearbeiten & wiederholen',
        ja: '編集して再実行',
      ),
      maxWidth: 600,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: '重放 URL',
                  zhHant: '重放 URL',
                  en: 'URL',
                  fr: 'URL',
                  de: 'URL',
                  ja: 'URL',
                ),
              ),
            ),
            kOpenHandGap8,
            TextField(
              controller: _headersCtrl,
              maxLines: 8,
              minLines: 4,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: 'Request Headers（每行 Key: Value，留空保留原值）',
                  zhHant: 'Request Headers（每行 Key: Value，留空保留原值）',
                  en: 'Request headers (Key: Value per line)',
                  fr: 'Request headers (Key: Value par ligne)',
                  de: 'Request headers (Key: Value pro Zeile)',
                  ja: 'Request headers（1 行 Key: Value）',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCancelLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            Navigator.of(context).pop((
              url: _urlCtrl.text.trim(),
              headers: _parseHeaderLines(_headersCtrl.text),
            ));
          },
          label: openHandLocalizedText(
            context,
            zh: '重放',
            zhHant: '重放',
            en: 'Replay',
            fr: 'Rejouer',
            de: 'Wiederholen',
            ja: '再実行',
          ),
        ),
      ],
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _webReverseDashUrlCopiedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已复制 URL',
    zhHant: '已複製 URL',
    en: 'URL copied',
    fr: 'URL copiée',
    de: 'URL kopiert',
    ja: 'URL をコピーしました',
  );
}

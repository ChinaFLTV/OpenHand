import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_document_markdown_preview.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_safe_markdown_body.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../data/mcp_market_client.dart';
import '../model/mcp_market.dart';

Future<void> showMcpMarketDialog(
  BuildContext context, {
  required Future<void> Function(String name) onConfigure,
  McpMarketClient? client,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => _McpMarketDialog(onConfigure: onConfigure, client: client),
);

const double _marketWidth = 1220;
const double _marketHeight = 840;
const Duration _searchDelay = Duration(milliseconds: 320);

class _McpMarketDialog extends StatefulWidget {
  const _McpMarketDialog({required this.onConfigure, this.client});
  final McpMarketClient? client;
  final Future<void> Function(String name) onConfigure;

  @override
  State<_McpMarketDialog> createState() => _McpMarketDialogState();
}

class _McpMarketDialogState extends State<_McpMarketDialog> {
  late final McpMarketClient _client;
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _detailScroll = ScrollController();
  final _debounce = OpenHandDebouncer(delay: _searchDelay);
  List<(String, int)> _categories = [];
  McpMarketPage? _result;
  McpMarketServer? _selected;
  McpMarketServer? _detail;
  String _category = '';
  String? _listError, _categoryError, _detailError, _readmeError, _readme;
  int _page = 1, _pageSize = McpMarketClient.defaultPageSize;
  int _searchToken = 0, _detailToken = 0;
  bool _loading = true, _loadingDetail = false, _loadingReadme = false;
  bool _configuring = false, _loadingCategories = false;
  bool _compactDetail = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? McpMarketClient();
    unawaited(_loadCategories());
    unawaited(_loadList());
  }

  @override
  void dispose() {
    _debounce.dispose();
    _client.close();
    _search.dispose();
    _listScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (_loadingCategories) return;
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final categories = await _client.categories();
      if (mounted) setState(() => _categories = categories);
    } catch (error) {
      if (mounted) setState(() => _categoryError = '分类加载失败');
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _scheduleSearch() {
    _debounce.cancel();
    ++_searchToken;
    _client.cancel('search');
    setState(() {
      _loading = true;
      _listError = null;
    });
    _debounce.schedule(() => _loadList(resetPage: true));
  }

  Future<void> _loadList({
    bool resetPage = false,
    bool correctedPage = false,
  }) async {
    _debounce.cancel();
    final token = ++_searchToken;
    setState(() {
      if (resetPage) _page = 1;
      _loading = true;
      _listError = null;
    });
    try {
      final result = await _client.search(
        page: _page,
        pageSize: _pageSize,
        keyword: _search.text,
        category: _category,
      );
      if (!mounted || token != _searchToken) return;
      // 数据减少导致当前页越界时，只跳转到有效末页。
      final lastPage = math.max(1, (result.total / _pageSize).ceil());
      if (_page > lastPage && !correctedPage) {
        _page = lastPage;
        await _loadList(correctedPage: true);
        return;
      }
      setState(() {
        _result = result;
        _loading = false;
      });
      if (_listScroll.hasClients) _listScroll.jumpTo(0);
      final selected = result.items
          .where((item) => item.slug == _selected?.slug)
          .firstOrNull;
      _select(selected ?? result.items.firstOrNull);
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _listError = userFailureMessage(error, fallback: '市场加载失败，请检查网络后重试。');
      });
    }
  }

  void _select(McpMarketServer? server) {
    final token = ++_detailToken;
    _client.cancel('detail');
    _client.cancel('readme');
    setState(() {
      _selected = server;
      _detail = null;
      _readme = null;
      _detailError = _readmeError = null;
      _loadingDetail = _loadingReadme = server != null;
    });
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
    if (server != null) {
      unawaited(_loadDetail(server.slug, token));
      unawaited(_loadReadme(server.slug, token));
    }
  }

  Future<void> _loadDetail(String slug, int token) async {
    try {
      final detail = await _client.detail(slug);
      if (!mounted || token != _detailToken) return;
      if (detail.slug != slug) throw const FormatException('服务详情与所选条目不一致。');
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
    } catch (error) {
      if (!mounted || token != _detailToken) return;
      setState(() {
        _loadingDetail = false;
        _detailError = userFailureMessage(error, fallback: '服务详情加载失败，请重试。');
      });
    }
  }

  Future<void> _loadReadme(String slug, int token) async {
    setState(() {
      _loadingReadme = true;
      _readmeError = null;
    });
    try {
      final readme = await _client.readme(slug);
      if (!mounted || token != _detailToken) return;
      setState(() {
        _readme = readme;
        _loadingReadme = false;
      });
    } catch (error) {
      if (!mounted || token != _detailToken) return;
      setState(() {
        _loadingReadme = false;
        _readmeError = userFailureMessage(error, fallback: '使用说明加载失败，请重试。');
      });
    }
  }

  Future<void> _configure() async {
    final server = _detail;
    if (_configuring || server == null || !server.canConfigure) return;
    setState(() => _configuring = true);
    try {
      await widget.onConfigure(server.displayName);
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 668;
    return PopScope(
      canPop: !_configuring,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: _marketWidth,
        maxHeight: _marketHeight,
        minAvailableWidth: 320,
        minAvailableHeight: 420,
        horizontalMargin: compact ? 24 : 48,
        verticalMargin: 24,
        safeAreaMinimum: const EdgeInsets.all(12),
        expandToMax: true,
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      color: colors.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MCP 市场',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '发现 SkillHub 服务，连接工具与灵感。',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('浏览服务'),
                                icon: Icon(Icons.grid_view_rounded),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('服务详情'),
                                icon: Icon(Icons.article_outlined),
                              ),
                            ],
                            selected: {_compactDetail},
                            onSelectionChanged: (value) =>
                                setState(() => _compactDetail = value.single),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _switchContent(
                              KeyedSubtree(
                                key: ValueKey(_compactDetail),
                                child: _compactDetail
                                    ? _detailPane()
                                    : _listPane(compact: true),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 980 ? 340 : 392,
                          child: _listPane(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _detailPane()),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() => LayoutBuilder(
    builder: (context, constraints) {
      final hint = Text(
        '查看使用说明后，填写连接参数。',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      );
      final buttons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: OpenHandDialogActionButton.secondary(
              label: '关闭',
              onPressed: _configuring
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: OpenHandDialogActionButton.primary(
              label: '添加配置',
              icon: Icons.add_link_rounded,
              busy: _configuring,
              onPressed:
                  !_configuring &&
                      !_loading &&
                      _listError == null &&
                      _detail?.canConfigure == true
                  ? _configure
                  : null,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [hint, const SizedBox(height: 12), buttons],
        );
      }
      return Row(
        children: [
          Expanded(child: hint),
          const SizedBox(width: 16),
          buttons,
        ],
      );
    },
  );

  Widget _switchContent(Widget child, {bool sizeToCurrentChild = false}) {
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    if (motion.disablesAnimation) return child;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: motion.durationMs),
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: (current, previous) =>
          buildCollisionSafeAnimatedSwitcherLayout(
            current,
            previous,
            alignment: Alignment.topCenter,
            sizeToCurrentChild: sizeToCurrentChild,
          ),
      child: child,
    );
  }

  Widget _panel({required Widget child}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _listPane({bool compact = false}) {
    return _panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SearchBar(
              controller: _search,
              hintText: '搜索 MCP 服务',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                IconButton(
                  tooltip: '刷新市场',
                  onPressed: () {
                    unawaited(_loadCategories());
                    unawaited(_loadList());
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
              onChanged: (_) => _scheduleSearch(),
              onSubmitted: (_) => _loadList(resetPage: true),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _categoryChip('', '全部'),
                  for (final category in _categories)
                    _categoryChip(
                      category.$1,
                      '${category.$1} · ${category.$2}',
                    ),
                  if (_categoryError != null)
                    TextButton(
                      onPressed: _loadCategories,
                      child: Text('$_categoryError · 重试'),
                    ),
                  if (_loadingCategories)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            OpenHandDialogBusyBar(busy: _loading, topGap: 8),
            const SizedBox(height: 8),
            Expanded(
              child: _listError != null
                  ? _notice(_listError!, retry: _loadList)
                  : _result?.items.isEmpty == true
                  ? _notice('没有找到匹配的服务，试试其他关键词或分类。')
                  : ListView.builder(
                      controller: _listScroll,
                      itemCount: _result?.items.length ?? 0,
                      itemBuilder: (context, index) =>
                          _serverCard(_result!.items[index]),
                    ),
            ),
            const SizedBox(height: 8),
            OpenHandTablePagination(
              total: _result?.total ?? 0,
              page: _page,
              pageSize: _pageSize,
              pageSizes: const [12, 24, 48, 96],
              enabled: !_loading && _listError == null,
              showJumper: !compact,
              showPageSize: !compact,
              showPageNumbers: !compact,
              onPageChanged: (page) {
                _page = page;
                unawaited(_loadList());
              },
              onPageSizeChanged: (size) {
                _pageSize = size;
                unawaited(_loadList(resetPage: true));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: _category == value,
      onSelected: (_) {
        if (_category == value) return;
        setState(() => _category = value);
        unawaited(_loadList(resetPage: true));
      },
    ),
  );

  Widget _avatar(McpMarketServer server, {double size = 46}) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.hub_rounded,
      color: colors.primary,
      size: size * .55,
    );
    final uri = Uri.tryParse(server.iconUrl);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: uri?.scheme == 'https' && uri!.host.isNotEmpty
          ? Image.network(
              server.iconUrl,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => fallback,
            )
          : fallback,
    );
  }

  Widget _serverCard(McpMarketServer server) {
    final colors = Theme.of(context).colorScheme;
    final selected = server.slug == _selected?.slug;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MicroPressFeedback(
        child: AnimatedContainer(
          duration: motion.disablesAnimation
              ? Duration.zero
              : Duration(milliseconds: motion.durationMs),
          curve: kOpenHandSwitchInCurve,
          decoration: BoxDecoration(
            color: selected
                ? OpenHandStatusColors.info.withValues(alpha: .14)
                : colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? OpenHandStatusColors.info
                  : colors.outlineVariant,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _loading
                  ? null
                  : () {
                      if (!selected) _select(server);
                      setState(() => _compactDetail = true);
                    },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatar(server),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            server.publisher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            server.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            server.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailPane() {
    final server = _detail ?? _selected;
    final colors = Theme.of(context).colorScheme;
    if (server == null) {
      return _panel(child: _notice(_loading ? '正在发现 MCP 服务…' : '选择服务，探索更多可能。'));
    }
    return _panel(
      child: SingleChildScrollView(
        controller: _detailScroll,
        padding: const EdgeInsets.all(16),
        child: _switchContent(
          Column(
            key: ValueKey(server.slug),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _avatar(server, size: 64),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                server.displayName,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                server.publisher,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (server.category.isNotEmpty)
                          OhPill(
                            icon: Icons.category_rounded,
                            label: server.category,
                            foregroundColor: colors.primary,
                          ),
                        OhPill(
                          icon: Icons.hub_rounded,
                          label: 'MCP',
                          foregroundColor: colors.tertiary,
                        ),
                        if (server.banned || !server.visible)
                          OhPill(
                            icon: Icons.block_rounded,
                            label: '暂不可添加',
                            foregroundColor: colors.error,
                          ),
                        for (final tag in server.tags)
                          OhPill(icon: Icons.sell_outlined, label: tag),
                      ],
                    ),
                  ],
                ),
              ),
              OpenHandDialogBusyBar(busy: _loadingDetail),
              if (_detailError != null)
                _notice(_detailError!, retry: () => _select(_selected)),
              const SizedBox(height: 14),
              _section(
                '概述',
                Icons.notes_rounded,
                OpenHandStatusColors.info,
                Text(
                  server.summary.isEmpty ? '暂无服务介绍。' : server.summary,
                  style: const TextStyle(height: 1.65),
                ),
              ),
              const SizedBox(height: 14),
              _section(
                '市场数据',
                Icons.insights_rounded,
                colors.tertiary,
                Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    OhPill(
                      icon: Icons.download_rounded,
                      label:
                          '下载 ${NumberFormat.compact(locale: 'zh').format(server.downloads)}',
                      foregroundColor: colors.primary,
                    ),
                    OhPill(
                      icon: Icons.extension_rounded,
                      label:
                          '安装 ${NumberFormat.compact(locale: 'zh').format(server.installs)}',
                      foregroundColor: colors.tertiary,
                    ),
                  ],
                ),
              ),
              if (_detail != null) ...[
                const SizedBox(height: 14),
                _section(
                  '项目来源',
                  Icons.open_in_new_rounded,
                  colors.primary,
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final entry in [
                        ('代码仓库', server.repoUrl),
                        ('项目主页', server.homepage),
                        ('服务来源', server.sourceUrl),
                      ])
                        if (_webLink(entry.$2) != null)
                          OpenHandThemedMarkdownBody(
                            data: '[${entry.$1}](<${_webLink(entry.$2)}>)',
                          ),
                      if ([
                        server.repoUrl,
                        server.homepage,
                        server.sourceUrl,
                      ].every((url) => _webLink(url) == null))
                        const Text('暂无项目链接。'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              OpenHandTintedPanel(
                title: '使用说明',
                icon: Icons.menu_book_rounded,
                accent: colors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadingReadme)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_readmeError != null)
                      _notice(
                        _readmeError!,
                        retry: () => _loadReadme(server.slug, _detailToken),
                      ),
                    if (_readme != null)
                      OpenHandDocumentMarkdownPreview(
                        data: _readme!,
                        backgroundColor: Colors.transparent,
                        maxCharacters: kOpenHandMarketMarkdownMaxCharacters,
                        emptyMessage: '暂无使用说明。',
                        truncationMessage: '\n\n---\n内容较长，已截断预览。完整内容请查看项目来源。',
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 旧文档自然布局，新文档决定滚动范围，避免长文档退场时被压缩。
          sizeToCurrentChild: true,
        ),
      ),
    );
  }

  String? _webLink(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty
        ? uri.toString().replaceAll('>', '%3E').replaceAll('<', '%3C')
        : null;
  }

  Widget _section(String title, IconData icon, Color accent, Widget child) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: .2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _notice(String message, {VoidCallback? retry}) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              retry == null ? Icons.explore_outlined : Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (retry != null)
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
          ],
        ),
      ),
    ),
  );
}

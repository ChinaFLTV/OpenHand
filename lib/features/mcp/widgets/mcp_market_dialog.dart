import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/url_validation.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_document_markdown_preview.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_image_reveal.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../data/mcp_market_client.dart';
import '../model/mcp_market.dart';
import 'mcp_market_labels.dart';

Future<void> showMcpMarketDialog(
  BuildContext context, {
  required Future<void> Function(String name) onConfigure,
  McpMarketClient? client,
  Future<bool> Function(String url)? openHttpUrl,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => _McpMarketDialog(
    onConfigure: onConfigure,
    client: client,
    openHttpUrl: openHttpUrl,
  ),
);

const double _kMcpMarketDialogWidth = 1220;
const double _kMcpMarketDialogHeight = 840;
const double _kMcpMarketListAvatarSize = 46;
const double _kMcpMarketDetailAvatarSize = 64;
const double _kMcpMarketCategoryRowMinHeight = 44;
const double _kMcpMarketCategoryChipMaxWidth = 260;
const double _kMcpMarketSourceIconBox = 40;
const double _kMcpMarketSourceIconGlyph = 20;
const Duration _kMcpMarketSearchDelay = Duration(milliseconds: 320);

class _McpMarketDialog extends StatefulWidget {
  const _McpMarketDialog({
    required this.onConfigure,
    this.client,
    this.openHttpUrl,
  });
  final McpMarketClient? client;
  final Future<void> Function(String name) onConfigure;
  final Future<bool> Function(String url)? openHttpUrl;

  @override
  State<_McpMarketDialog> createState() => _McpMarketDialogState();
}

class _McpMarketDialogState extends State<_McpMarketDialog> {
  late final McpMarketClient _client;
  final _search = TextEditingController();
  final _debounce = OpenHandDebouncer(delay: _kMcpMarketSearchDelay);
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
  String? _openingSourceUrl;

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
    } catch (_) {
      if (mounted) {
        setState(
          () => _categoryError = openHandLocalizedText(
            context,
            zh: '分类加载失败',
            zhHant: '分類載入失敗',
            en: 'Categories failed to load',
            fr: 'Impossible de charger les catégories',
            de: 'Kategorien konnten nicht geladen werden',
            ja: '分類を読み込めませんでした',
          ),
        );
      }
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

  void _clearSearch() {
    if (_search.text.isEmpty) return;
    _search.clear();
    _scheduleSearch();
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
      final selected = result.items
          .where((item) => item.slug == _selected?.slug)
          .firstOrNull;
      _select(selected ?? result.items.firstOrNull);
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _listError = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '市场加载失败，请检查网络后重试。',
            zhHant: '市場載入失敗，請檢查網路後重試。',
            en: 'The marketplace could not be loaded. Check the network and retry.',
            fr: 'Impossible de charger le marché. Vérifiez le réseau, puis réessayez.',
            de: 'Der Markt konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut.',
            ja: 'マーケットを読み込めませんでした。ネットワークを確認して再試行してください。',
          ),
        );
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
      _openingSourceUrl = null;
    });
    if (server != null) {
      unawaited(_loadDetail(server.slug, token));
      unawaited(_loadReadme(server.slug, token));
    }
  }

  Future<void> _loadDetail(String slug, int token) async {
    try {
      final detail = await _client.detail(slug);
      if (!mounted || token != _detailToken) return;
      if (detail.slug != slug) {
        throw FormatException(
          openHandLocalizedText(
            context,
            zh: '服务详情与所选条目不一致。',
            zhHant: '服務詳情與所選項目不一致。',
            en: 'The service details do not match the selected item.',
            fr: 'Les détails du service ne correspondent pas à l’élément sélectionné.',
            de: 'Die Dienstdetails stimmen nicht mit dem ausgewählten Eintrag überein.',
            ja: 'サービスの詳細が選択中の項目と一致しません。',
          ),
        );
      }
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
    } catch (error) {
      if (!mounted || token != _detailToken) return;
      setState(() {
        _loadingDetail = false;
        _detailError = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '服务详情加载失败，请重试。',
            zhHant: '服務詳情載入失敗，請重試。',
            en: 'Service details failed to load. Please retry.',
            fr: 'Impossible de charger les détails du service. Réessayez.',
            de: 'Dienstdetails konnten nicht geladen werden. Bitte erneut versuchen.',
            ja: 'サービスの詳細を読み込めませんでした。再試行してください。',
          ),
        );
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
        _readmeError = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '使用说明加载失败，请重试。',
            zhHant: '使用說明載入失敗，請重試。',
            en: 'The usage guide failed to load. Please retry.',
            fr: 'Impossible de charger le guide d’utilisation. Réessayez.',
            de: 'Die Anleitung konnte nicht geladen werden. Bitte erneut versuchen.',
            ja: '利用案内を読み込めませんでした。再試行してください。',
          ),
        );
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 668;
    return PopScope(
      canPop: !_configuring,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: _kMcpMarketDialogWidth,
        maxHeight: _kMcpMarketDialogHeight,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(kOpenHandRadius18),
                    ),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        Icons.hub_rounded,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  kOpenHandHGap14,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandMcpMarketLabel(context),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap4,
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '发现 SkillHub 服务，连接工具与灵感。',
                            zhHant: '發現 SkillHub 服務，連接工具與靈感。',
                            en: 'Discover SkillHub services and connect tools with ideas.',
                            fr: 'Découvrez les services SkillHub et reliez outils et idées.',
                            de: 'Entdecke SkillHub-Dienste und verbinde Werkzeuge mit Ideen.',
                            ja: 'SkillHub のサービスを見つけ、ツールと発想をつなぎます。',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              kOpenHandGap18,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      final browseLabel = openHandLocalizedText(
                        context,
                        zh: '浏览服务',
                        zhHant: '瀏覽服務',
                        en: 'Browse',
                        fr: 'Parcourir',
                        de: 'Durchsuchen',
                        ja: 'サービスを見る',
                      );
                      final detailLabel = openHandLocalizedText(
                        context,
                        zh: '服务详情',
                        zhHant: '服務詳情',
                        en: 'Details',
                        fr: 'Détails',
                        de: 'Details',
                        ja: 'サービス詳細',
                      );
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Center(
                                  child: OpenHandChoicePill(
                                    selected: !_compactDetail,
                                    onSelected: _compactDetail
                                        ? () => setState(
                                            () => _compactDetail = false,
                                          )
                                        : null,
                                    label: browseLabel,
                                  ),
                                ),
                              ),
                              kOpenHandHGap8,
                              Expanded(
                                child: Center(
                                  child: OpenHandChoicePill(
                                    selected: _compactDetail,
                                    onSelected: _compactDetail
                                        ? null
                                        : () => setState(
                                            () => _compactDetail = true,
                                          ),
                                    label: detailLabel,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          kOpenHandGap12,
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
                        kOpenHandHGap16,
                        Expanded(child: _detailPane()),
                      ],
                    );
                  },
                ),
              ),
              kOpenHandGap16,
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
        openHandLocalizedText(
          context,
          zh: '查看使用说明后，填写连接参数。',
          zhHant: '查看使用說明後，填寫連線參數。',
          en: 'Read the usage guide, then fill in the connection parameters.',
          fr: 'Lisez le guide, puis renseignez les paramètres de connexion.',
          de: 'Lies die Anleitung und fülle danach die Verbindungsparameter aus.',
          ja: '利用案内を確認してから接続パラメータを入力します。',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      final buttons = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OpenHandDialogActionButton.secondary(
            label: openHandCloseLabel(context),
            onPressed: _configuring ? null : () => Navigator.of(context).pop(),
          ),
          kOpenHandHGap12,
          OpenHandDialogActionButton.primary(
            label: openHandLocalizedText(
              context,
              zh: '添加配置',
              zhHant: '新增設定',
              en: 'Add configuration',
              fr: 'Ajouter une configuration',
              de: 'Konfiguration hinzufügen',
              ja: '設定を追加',
            ),
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
        ],
      );
      if (constraints.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hint,
            kOpenHandGap12,
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: buttons),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: hint),
          kOpenHandHGap16,
          FittedBox(fit: BoxFit.scaleDown, child: buttons),
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

  Widget _paneSurface({required Widget child}) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.04),
          colors.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: child,
    );
  }

  Widget _listPane({bool compact = false}) {
    final labelFontSize =
        Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
    final categoryHeight = math.max(
      _kMcpMarketCategoryRowMinHeight,
      MediaQuery.textScalerOf(context).scale(labelFontSize) + 24,
    );
    final items = _result?.items ?? const <McpMarketServer>[];
    return _paneSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            SearchBar(
              controller: _search,
              elevation: const WidgetStatePropertyAll(0),
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              hintText: openHandLocalizedText(
                context,
                zh: '搜索 MCP 服务',
                zhHant: '搜尋 MCP 服務',
                en: 'Search MCP services',
                fr: 'Rechercher des services MCP',
                de: 'MCP-Dienste suchen',
                ja: 'MCPサービスを検索',
              ),
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_search.text.trim().isNotEmpty) ...[
                  Tooltip(
                    message: openHandClearSearchLabel(context),
                    child: IconButton(
                      onPressed: _loading ? null : _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  kOpenHandHGap8,
                ],
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '刷新市场',
                    zhHant: '重新整理市場',
                    en: 'Refresh marketplace',
                    fr: 'Actualiser le marché',
                    de: 'Markt aktualisieren',
                    ja: 'マーケットを更新',
                  ),
                  child: IconButton(
                    onPressed: () {
                      unawaited(_loadCategories());
                      unawaited(_loadList());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
              onChanged: (_) => _scheduleSearch(),
              onSubmitted: (_) => _loadList(resetPage: true),
            ),
            kOpenHandGap12,
            SizedBox(
              height: categoryHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                children: [
                  _categoryChip('', openHandAllLabel(context)),
                  for (final category in _categories)
                    _categoryChip(
                      category.$1,
                      '${mcpMarketCategoryLabel(context, category.$1)} · ${category.$2}',
                    ),
                  if (_categoryError != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 8),
                      child: Center(
                        child: OpenHandCompactActionChip(
                          icon: Icons.refresh_rounded,
                          label: '$_categoryError · ${_retryLabel(context)}',
                          onPressed: _loadCategories,
                        ),
                      ),
                    ),
                  if (_loadingCategories)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            OpenHandDialogBusyBar(busy: _loading, topGap: 8),
            kOpenHandGap8,
            Expanded(
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                child: _listError != null
                    ? _McpMarketStateMessage(
                        key: const ValueKey<String>('mcp-market-list-error'),
                        icon: Icons.cloud_off_outlined,
                        title: openHandLocalizedText(
                          context,
                          zh: '加载失败',
                          zhHant: '載入失敗',
                          en: 'Unable to Load',
                          fr: 'Chargement impossible',
                          de: 'Laden fehlgeschlagen',
                          ja: '読み込めません',
                        ),
                        body: _listError!,
                        actionLabel: _retryLabel(context),
                        onAction: _loadList,
                      )
                    : _loading && _result == null
                    ? const Center(
                        key: ValueKey<String>('mcp-market-list-loading'),
                        child: CircularProgressIndicator(),
                      )
                    : items.isEmpty
                    ? _McpMarketStateMessage(
                        key: const ValueKey<String>('mcp-market-list-empty'),
                        icon: Icons.search_off_rounded,
                        title: openHandLocalizedText(
                          context,
                          zh: '没有找到结果',
                          zhHant: '沒有找到結果',
                          en: 'No Results',
                          fr: 'Aucun résultat',
                          de: 'Keine Ergebnisse',
                          ja: '結果がありません',
                        ),
                        body: openHandLocalizedText(
                          context,
                          zh: '没有找到匹配的服务，试试其他关键词或分类。',
                          zhHant: '沒有找到符合的服務，試試其他關鍵詞或分類。',
                          en: 'No matching services. Try another keyword or category.',
                          fr: 'Aucun service correspondant. Essayez un autre mot-clé ou une autre catégorie.',
                          de: 'Keine passenden Dienste. Versuche ein anderes Stichwort oder eine andere Kategorie.',
                          ja: '一致するサービスがありません。別のキーワードや分類を試してください。',
                        ),
                      )
                    : _McpMarketScrollRegion(
                        key: ValueKey<String>(
                          'mcp-market-results-$_page-$_category',
                        ),
                        resetKey: _result,
                        builder: (controller) => ListView.separated(
                          controller: controller,
                          itemCount: items.length,
                          separatorBuilder: (context, index) => kOpenHandGap8,
                          itemBuilder: (context, index) {
                            final server = items[index];
                            final tile = _McpMarketResultTile(
                              server: server,
                              selected: server.slug == _selected?.slug,
                              onTap: _loading
                                  ? null
                                  : () {
                                      if (server.slug != _selected?.slug) {
                                        _select(server);
                                      }
                                      setState(() => _compactDetail = true);
                                    },
                            );
                            final motion = openHandMotionDuration(
                              context,
                              kOpenHandMotion180,
                            );
                            final key = ValueKey<String>(
                              'mcp-market-${server.slug}',
                            );
                            if (motion == Duration.zero) {
                              return KeyedSubtree(key: key, child: tile);
                            }
                            return AppearOnce(
                              key: key,
                              duration: motion,
                              child: tile,
                            );
                          },
                        ),
                      ),
              ),
            ),
            kOpenHandGap12,
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

  Widget _categoryChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _kMcpMarketCategoryChipMaxWidth,
          ),
          child: OpenHandChoicePill(
            selected: _category == value,
            onSelected: _category == value
                ? null
                : () {
                    setState(() => _category = value);
                    unawaited(_loadList(resetPage: true));
                  },
            label: label,
          ),
        ),
      ),
    );
  }

  Widget _detailPane() {
    final server = _detail ?? _selected;
    if (server == null) {
      return _paneSurface(
        child: _McpMarketStateMessage(
          icon: Icons.auto_awesome_rounded,
          title: openHandLocalizedText(
            context,
            zh: '选择一个服务',
            zhHant: '選擇一個服務',
            en: 'Select a service',
            fr: 'Sélectionner un service',
            de: 'Dienst auswählen',
            ja: 'サービスを選択',
          ),
          body: _loading
              ? openHandLocalizedText(
                  context,
                  zh: '正在发现 MCP 服务…',
                  zhHant: '正在發現 MCP 服務…',
                  en: 'Discovering MCP services…',
                  fr: 'Découverte des services MCP…',
                  de: 'MCP-Dienste werden gesucht…',
                  ja: 'MCPサービスを探しています…',
                )
              : openHandLocalizedText(
                  context,
                  zh: '点击左侧候选项后，这里会展示概述、市场数据、项目来源和使用说明。',
                  zhHant: '點擊左側候選項後，這裡會展示概述、市場資料、專案來源和使用說明。',
                  en: 'Choose a result on the left to view the overview, marketplace stats, project links, and usage guide.',
                  fr: 'Choisissez un résultat à gauche pour voir l’aperçu, les statistiques, les liens du projet et le guide.',
                  de: 'Wähle links ein Ergebnis, um Übersicht, Marktdaten, Projektlinks und die Anleitung zu sehen.',
                  ja: '左側の候補を選ぶと、概要、マーケットデータ、プロジェクトの出典、利用案内を表示します。',
                ),
        ),
      );
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _mcpMarketCategoryAccent(colors, server.category);
    final displayName = server.displayName;
    final summary = mcpMarketSummary(context, server);
    final categoryLabel = server.category.isEmpty
        ? ''
        : mcpMarketCategoryLabel(context, server.category);
    return _paneSurface(
      child: _McpMarketScrollRegion(
        resetKey: server.slug,
        builder: (controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          child: _switchContent(
            Column(
              key: ValueKey(server.slug),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenHandTintedPanel(
                  accent: accent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _McpMarketAvatar(
                        name: displayName,
                        imageUrl: server.iconUrl,
                        size: _kMcpMarketDetailAvatarSize,
                      ),
                      kOpenHandHGap14,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (server.publisher.isNotEmpty) ...[
                              kOpenHandGap6,
                              Text(
                                server.publisher,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            kOpenHandGap10,
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (categoryLabel.isNotEmpty)
                                  OpenHandFactChip(
                                    icon: Icons.category_outlined,
                                    label: categoryLabel,
                                    color: accent,
                                  ),
                                OpenHandFactChip(
                                  icon: Icons.hub_outlined,
                                  label: mcpMarketTypeLabel(context),
                                  color: colors.tertiary,
                                ),
                                if (server.banned || !server.visible)
                                  OpenHandStatusPill(
                                    icon: Icons.block_rounded,
                                    label: mcpMarketUnavailableLabel(context),
                                    color: colors.error,
                                  ),
                                for (final tag in server.tags)
                                  OpenHandFactChip(
                                    icon: Icons.local_offer_outlined,
                                    label: tag,
                                    color: colors.secondary,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                OpenHandDialogBusyBar(busy: _loadingDetail),
                if (_detailError != null)
                  _inlineError(_detailError!, () => _select(_selected)),
                kOpenHandGap14,
                OpenHandTintedPanel(
                  accent: OpenHandStatusColors.info,
                  icon: Icons.notes_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: '概述',
                    zhHant: '概述',
                    en: 'Overview',
                    fr: 'Vue d’ensemble',
                    de: 'Übersicht',
                    ja: '概要',
                  ),
                  child: Text(
                    summary.isEmpty
                        ? openHandLocalizedText(
                            context,
                            zh: '暂无服务介绍。',
                            zhHant: '暫無服務介紹。',
                            en: 'No service overview is available.',
                            fr: 'Aucune présentation du service.',
                            de: 'Keine Dienstübersicht vorhanden.',
                            ja: 'サービスの紹介はありません。',
                          )
                        : summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
                kOpenHandGap14,
                OpenHandMetricsStrip(
                  items: <OpenHandMetricItem>[
                    (
                      label: mcpMarketDownloadsLabel(context),
                      value: _mcpMarketFormatCount(context, server.downloads),
                      accent: OpenHandStatusColors.info,
                    ),
                    (
                      label: mcpMarketInstallsLabel(context),
                      value: _mcpMarketFormatCount(context, server.installs),
                      accent: colors.tertiary,
                    ),
                  ],
                ),
                if (_detail != null) ...[
                  kOpenHandGap14,
                  OpenHandTintedPanel(
                    accent: colors.primary,
                    icon: Icons.open_in_new_rounded,
                    title: openHandLocalizedText(
                      context,
                      zh: '项目来源',
                      zhHant: '專案來源',
                      en: 'Project sources',
                      fr: 'Sources du projet',
                      de: 'Projektquellen',
                      ja: 'プロジェクトの出典',
                    ),
                    child: _projectLinks(server),
                  ),
                ],
                kOpenHandGap14,
                OpenHandTintedPanel(
                  title: openHandLocalizedText(
                    context,
                    zh: '使用说明',
                    zhHant: '使用說明',
                    en: 'Usage guide',
                    fr: 'Guide d’utilisation',
                    de: 'Anleitung',
                    ja: '利用案内',
                  ),
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
                        _inlineError(
                          _readmeError!,
                          () => _loadReadme(server.slug, _detailToken),
                        ),
                      if (_readme != null)
                        OpenHandDocumentMarkdownPreview(
                          data: _readme!,
                          backgroundColor: Colors.transparent,
                          maxCharacters: kOpenHandMarketMarkdownMaxCharacters,
                          emptyMessage: openHandLocalizedText(
                            context,
                            zh: '暂无使用说明。',
                            zhHant: '暫無使用說明。',
                            en: 'No usage guide is available.',
                            fr: 'Aucun guide d’utilisation.',
                            de: 'Keine Anleitung vorhanden.',
                            ja: '利用案内はありません。',
                          ),
                          truncationMessage: _mcpMarketTruncationMessage(
                            context,
                          ),
                          onTapLink: (text, href, title) {
                            unawaited(_openProjectSource(href ?? text));
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
            sizeToCurrentChild: true,
          ),
        ),
      ),
    );
  }

  Widget _projectLinks(McpMarketServer server) {
    final tiles = <Widget>[
      for (final item in _mcpMarketSourceItems(context, server))
        _McpMarketSourceTile(
          title: item.title,
          uri: item.uri,
          icon: item.icon,
          accent: item.accent,
          busy: _openingSourceUrl == item.uri.toString(),
          onOpen: _openingSourceUrl == null
              ? () => unawaited(_openProjectSource(item.uri.toString()))
              : null,
        ),
    ];
    if (tiles.isEmpty) {
      return OpenHandInlineEmptyState.compact(
        message: openHandLocalizedText(
          context,
          zh: '暂无项目链接。',
          zhHant: '暫無專案連結。',
          en: 'No project links are available.',
          fr: 'Aucun lien de projet.',
          de: 'Keine Projektlinks vorhanden.',
          ja: 'プロジェクトのリンクはありません。',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) kOpenHandGap8,
          tiles[i],
        ],
      ],
    );
  }

  Future<void> _openProjectSource(String url) async {
    if (_openingSourceUrl != null) return;
    final uri = tryParseValidHttpUrl(url);
    if (uri == null) {
      if (!mounted) return;
      showOpenHandErrorSnack(context, _mcpMarketOpenLinkFailedLabel(context));
      return;
    }
    final target = uri.toString();
    _openingSourceUrl = target;
    if (mounted) setState(() {});
    try {
      final opener = widget.openHttpUrl;
      final opened = opener != null
          ? await opener(target)
          : await openHttpUrlWithSystemBrowser(
              target,
              tag: 'mcp_market.open_url',
            );
      if (!mounted || opened) return;
      showOpenHandErrorSnack(context, _mcpMarketOpenLinkFailedLabel(context));
    } catch (error, stack) {
      silentLog('mcp_market', '打开项目来源', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(context, _mcpMarketOpenLinkFailedLabel(context));
      }
    } finally {
      if (_openingSourceUrl == target) _openingSourceUrl = null;
      if (mounted) setState(() {});
    }
  }

  Widget _inlineError(String message, VoidCallback retry) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
          kOpenHandGap8,
          OpenHandCompactActionChip(
            icon: Icons.refresh_rounded,
            label: _retryLabel(context),
            onPressed: retry,
          ),
        ],
      ),
    );
  }
}

/// 退场面板仍挂载时，控制器随各自滚动区域独立存活。
class _McpMarketScrollRegion extends StatefulWidget {
  const _McpMarketScrollRegion({
    super.key,
    required this.resetKey,
    required this.builder,
  });

  final Object? resetKey;
  final Widget Function(ScrollController controller) builder;

  @override
  State<_McpMarketScrollRegion> createState() => _McpMarketScrollRegionState();
}

class _McpMarketScrollRegionState extends State<_McpMarketScrollRegion> {
  final _controller = ScrollController(keepScrollOffset: false);

  @override
  void didUpdateWidget(_McpMarketScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OpenHandSafeScrollbar(
    controller: _controller,
    child: widget.builder(_controller),
  );
}

class _McpMarketSourceTile extends StatelessWidget {
  const _McpMarketSourceTile({
    required this.title,
    required this.uri,
    required this.icon,
    required this.accent,
    required this.busy,
    required this.onOpen,
  });

  final String title;
  final Uri uri;
  final IconData icon;
  final Color accent;
  final bool busy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(kOpenHandRadius14);
    final caption = _mcpMarketSourceCaption(uri);
    final tooltip = openHandLocalizedText(
      context,
      zh: '在系统浏览器中打开',
      zhHant: '在系統瀏覽器中開啟',
      en: 'Open in the system browser',
      fr: 'Ouvrir dans le navigateur système',
      de: 'Im Systembrowser öffnen',
      ja: 'システムのブラウザで開く',
    );
    return Tooltip(
      message: '$tooltip\n$caption',
      child: MouseRegion(
        cursor: onOpen == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: MicroPressFeedback(
          enabled: onOpen != null,
          child: Material(
            color: Colors.transparent,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              splashColor: accent.withValues(alpha: 0.10),
              highlightColor: accent.withValues(alpha: 0.06),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: AnimatedContainer(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                curve: kOpenHandSwitchInCurve,
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.10),
                    colorScheme.surface,
                  ),
                  borderRadius: radius,
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: 0.18),
                          colorScheme.surface,
                        ),
                        borderRadius: BorderRadius.circular(kOpenHandRadius12),
                      ),
                      child: SizedBox(
                        width: _kMcpMarketSourceIconBox,
                        height: _kMcpMarketSourceIconBox,
                        child: Icon(
                          icon,
                          size: _kMcpMarketSourceIconGlyph,
                          color: accent,
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap3,
                          Text(
                            caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    kOpenHandHGap8,
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                              color: accent,
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
}

class _McpMarketResultTile extends StatelessWidget {
  const _McpMarketResultTile({
    required this.server,
    required this.selected,
    required this.onTap,
  });

  final McpMarketServer server;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _mcpMarketCategoryAccent(colorScheme, server.category);
    final displayName = server.displayName;
    final summary = mcpMarketSummary(context, server);
    final categoryLabel = server.category.isEmpty
        ? ''
        : mcpMarketCategoryLabel(context, server.category);
    final radius = BorderRadius.circular(kOpenHandRadius18);

    return MicroPressFeedback(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: Colors.transparent,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      accent.withValues(alpha: 0.16),
                      colorScheme.surface,
                    )
                  : colorScheme.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? accent
                    : colorScheme.outlineVariant.withValues(alpha: 0.78),
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: kOpenHandAccentBarWidth,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _McpMarketAvatar(
                          name: displayName,
                          imageUrl: server.iconUrl,
                          size: _kMcpMarketListAvatarSize,
                        ),
                        kOpenHandHGap12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (server.publisher.isNotEmpty) ...[
                                kOpenHandGap3,
                                Text(
                                  server.publisher,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (summary.isNotEmpty) ...[
                                kOpenHandGap8,
                                Text(
                                  summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              kOpenHandGap10,
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OpenHandFactChip(
                                    icon: Icons.download_rounded,
                                    label: _mcpMarketFormatCount(
                                      context,
                                      server.downloads,
                                    ),
                                    color: OpenHandStatusColors.info,
                                  ),
                                  OpenHandFactChip(
                                    icon: Icons.extension_rounded,
                                    label: _mcpMarketFormatCount(
                                      context,
                                      server.installs,
                                    ),
                                    color: colorScheme.tertiary,
                                  ),
                                  if (categoryLabel.isNotEmpty)
                                    OpenHandFactChip(
                                      icon: Icons.category_outlined,
                                      label: categoryLabel,
                                      color: accent,
                                    ),
                                ],
                              ),
                            ],
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
    );
  }
}

class _McpMarketAvatar extends StatelessWidget {
  const _McpMarketAvatar({
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  final String name;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = _McpMarketAvatarFallback(name: name);
    final uri = Uri.tryParse(imageUrl);
    final hasImage = uri?.scheme == 'https' && uri!.host.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(math.min(18, size / 3)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: OpenHandImageRevealSwitcher(
        compact: true,
        stateKey: hasImage ? imageUrl : 'fallback',
        child: hasImage
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                width: size,
                height: size,
                cacheWidth: (size * 3).round(),
                cacheHeight: (size * 3).round(),
                gaplessPlayback: true,
                frameBuilder: openHandCompactImageRevealFrameBuilder,
                errorBuilder: (context, error, stackTrace) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class _McpMarketAvatarFallback extends StatelessWidget {
  const _McpMarketAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? 'M'
        : trimmed.characters.first.toUpperCase();
    return Text(
      initial,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _McpMarketStateMessage extends StatelessWidget {
  const _McpMarketStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius22),
                ),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(icon, size: 34, color: colorScheme.primary),
                ),
              ),
              kOpenHandGap16,
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap8,
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                kOpenHandGap16,
                OpenHandDialogActionButton.primary(
                  onPressed: onAction,
                  icon: Icons.refresh_rounded,
                  label: actionLabel!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _mcpMarketOpenLinkFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '无法用系统浏览器打开该链接。',
    zhHant: '無法用系統瀏覽器開啟該連結。',
    en: 'Could not open this link in the system browser.',
    fr: 'Impossible d’ouvrir ce lien dans le navigateur système.',
    de: 'Der Link konnte nicht im Systembrowser geöffnet werden.',
    ja: 'システムのブラウザでこのリンクを開けませんでした。',
  );
}

String _mcpMarketSourceCaption(Uri uri) {
  final path = uri.path;
  if (path.isEmpty || path == '/') {
    return uri.host;
  }
  return '${uri.host}$path';
}

List<({String title, Uri uri, IconData icon, Color accent})>
_mcpMarketSourceItems(BuildContext context, McpMarketServer server) {
  final colors = Theme.of(context).colorScheme;
  final specs = <({String title, String raw, IconData icon, Color accent})>[
    (
      title: openHandLocalizedText(
        context,
        zh: '代码仓库',
        zhHant: '程式碼倉庫',
        en: 'Repository',
        fr: 'Dépôt',
        de: 'Repository',
        ja: 'リポジトリ',
      ),
      raw: server.repoUrl,
      icon: Icons.account_tree_rounded,
      accent: OpenHandStatusColors.info,
    ),
    (
      title: openHandLocalizedText(
        context,
        zh: '项目主页',
        zhHant: '專案首頁',
        en: 'Homepage',
        fr: 'Page d’accueil',
        de: 'Startseite',
        ja: 'プロジェクトページ',
      ),
      raw: server.homepage,
      icon: Icons.language_rounded,
      accent: colors.primary,
    ),
    (
      title: openHandLocalizedText(
        context,
        zh: '服务来源',
        zhHant: '服務來源',
        en: 'Service source',
        fr: 'Source du service',
        de: 'Dienstquelle',
        ja: 'サービス出典',
      ),
      raw: server.sourceUrl,
      icon: Icons.travel_explore_rounded,
      accent: colors.tertiary,
    ),
  ];
  return [
    for (final spec in specs)
      if (tryParseValidHttpUrl(spec.raw) case final uri?)
        (title: spec.title, uri: uri, icon: spec.icon, accent: spec.accent),
  ];
}

String _retryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重试',
    zhHant: '重試',
    en: 'Retry',
    fr: 'Réessayer',
    de: 'Erneut versuchen',
    ja: '再試行',
  );
}

String _mcpMarketFormatCount(BuildContext context, int value) {
  final safe = value < 0 ? 0 : value;
  try {
    return NumberFormat.compact(
      locale: Localizations.localeOf(context).toString(),
    ).format(safe);
  } catch (_) {
    return '$safe';
  }
}

String _mcpMarketTruncationMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '\n\n---\n内容较长，已截断预览。完整内容请查看项目来源。',
    zhHant: '\n\n---\n內容較長，已截斷預覽。完整內容請查看專案來源。',
    en: '\n\n---\nPreview truncated. See the project sources for the full document.',
    fr: '\n\n---\nAperçu tronqué. Consultez les sources du projet pour le document complet.',
    de: '\n\n---\nVorschau gekürzt. Die vollständige Datei findest du in den Projektquellen.',
    ja: '\n\n---\nプレビューを切り詰めました。全文はプロジェクトの出典をご覧ください。',
  );
}

Color _mcpMarketCategoryAccent(ColorScheme colorScheme, String category) {
  return switch (category.trim().toLowerCase()) {
    '腾讯产品mcp' => colorScheme.primary,
    '搜索与信息检索' => OpenHandStatusColors.info,
    '开发者工具' => colorScheme.secondary,
    '文档工具' => colorScheme.tertiary,
    '支付与交易' => OpenHandStatusColors.warning,
    '数据库与文件' => OpenHandStatusColors.info,
    '位置服务' => OpenHandStatusColors.success,
    '内容抓取' => OpenHandStatusColors.caution,
    '浏览器自动化' => colorScheme.secondary,
    '社交媒体' => colorScheme.tertiary,
    '设计与创意' => colorScheme.primary,
    _ => colorScheme.primary,
  };
}

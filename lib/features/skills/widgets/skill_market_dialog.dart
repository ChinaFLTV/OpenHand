import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/market/market_provider.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_expandable.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/market_provider_selector.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_code_editor.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_document_markdown_preview.dart';
import '../../../shared/ui/openhand_file_icons.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_image_reveal.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../data/skill_market_providers.dart';
import '../model/skill_market.dart';
import '../model/skill_market_provider.dart';
import '../skills_controller.dart';
import 'skill_market_labels.dart';

Future<void> showSkillMarketDialog(
  BuildContext context, {
  MarketProviderRegistry<SkillMarketProvider>? providers,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SkillMarketDialog(providers: providers ?? skillMarketProviders),
  );
}

/// 技能市场是 expandToMax 的固定尺寸弹窗（左右分栏 + 预览），不套用统一档位：
/// 档位是上限语义，套上去会把这里的固定尺寸一起改掉。
const double _kSkillMarketDialogWidth = 1220;
const double _kSkillMarketDialogHeight = 840;
const double _kSkillMarketListAvatarSize = 46;
const double _kSkillMarketDetailAvatarSize = 64;
const double _kSkillMarketConfirmAvatarSize = 52;
const int _kSkillMarketMaxPreviewVersions = 12;
const double _kSkillMarketFileTreeMaxHeight = 420;
const double _kSkillMarketFileTreeRowMinHeight = 36;
const double _kSkillMarketFileTreeRowGap = 8;
const double _kSkillMarketFileTreeIndent = 20;
const double _kSkillMarketFileTreeChevronSize = 16;
const int _kSkillMarketFileTreeMaxSegments = 16;
const int _kSkillMarketMaxPreviewSubcategories = 3;
const double _kSkillMarketFilePreviewEditorHeight = 560;
const int _kSkillMarketFilePreviewMaxBytes = 4 * kBytesPerMiB;

class _SkillMarketDialog extends StatefulWidget {
  const _SkillMarketDialog({required this.providers});
  final MarketProviderRegistry<SkillMarketProvider> providers;

  @override
  State<_SkillMarketDialog> createState() => _SkillMarketDialogState();
}

class _SkillMarketDialogState extends State<_SkillMarketDialog> {
  static const Duration _searchDebounceDuration = Duration(milliseconds: 320);

  final TextEditingController _searchController = TextEditingController();
  final OpenHandDebouncer _searchDebounce = OpenHandDebouncer(
    delay: _searchDebounceDuration,
  );
  late final MarketProviderSession<SkillMarketProvider> _session;
  SkillMarketProvider get _marketClient => _session.provider!;

  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;
  int _searchToken = 0;
  String _keyword = '';
  String _searchInput = '';
  bool _isSearching = false;
  bool _isInstalling = false;
  String? _searchError;
  String? _installError;
  SkillMarketSearchResult? _searchResult;
  SkillMarketSummary? _selectedSkill;
  Future<SkillMarketBundle>? _selectedBundleFuture;
  final Map<String, String> _selectedPreviewVersions = <String, String>{};
  final ValueNotifier<int> _installSuccessSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> _installErrorSignal = ValueNotifier<int>(0);
  bool _filePreviewOpen = false;

  @override
  void initState() {
    super.initState();
    _session = MarketProviderSession(widget.providers);
    if (_session.provider != null) unawaited(_runSearch(keepSelection: false));
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _session.close();
    _searchController.dispose();
    _installSuccessSignal.dispose();
    _installErrorSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compactViewport = size.width < 668 || size.height < 608;
    final viewportMargin = compactViewport ? 24.0 : 48.0;
    final safeAreaPadding = compactViewport ? 12.0 : 24.0;

    return PopScope(
      canPop: !_isInstalling,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: _kSkillMarketDialogWidth,
        maxHeight: _kSkillMarketDialogHeight,
        minAvailableWidth: 320,
        minAvailableHeight: 420,
        horizontalMargin: viewportMargin,
        verticalMargin: viewportMargin,
        safeAreaMinimum: EdgeInsets.all(safeAreaPadding),
        expandToMax: true,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  kOpenHandGap18,
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760;
                        if (compact) {
                          return Column(
                            children: [
                              SizedBox(
                                height: math.min(
                                  300,
                                  constraints.maxHeight * 0.44,
                                ),
                                child: _buildSearchPane(context),
                              ),
                              kOpenHandGap16,
                              Expanded(
                                child: KeyedSubtree(
                                  key: ValueKey(_session.info?.id),
                                  child: _buildDetailPane(context),
                                ),
                              ),
                            ],
                          );
                        }

                        final leftWidth = constraints.maxWidth < 980
                            ? 340.0
                            : 392.0;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: leftWidth,
                              child: _buildSearchPane(context),
                            ),
                            kOpenHandHGap16,
                            Expanded(
                              child: KeyedSubtree(
                                key: ValueKey(_session.info?.id),
                                child: _buildDetailPane(context),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  kOpenHandGap18,
                  _buildActions(context),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _installSuccessSignal,
                  color: OpenHandStatusColors.success,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _installErrorSignal,
                  color: OpenHandStatusColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(kOpenHandRadius18),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.storefront_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        kOpenHandHGap14,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandSkillMarketLabel(context),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap4,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '搜索市场技能，查看详情后安装到当前全局技能目录。',
                  zhHant: '搜尋市場技能，查看詳情後安裝到目前全域技能目錄。',
                  en: 'Search marketplace skills, inspect details, and install into the current global skills directory.',
                  fr: 'Recherchez des compétences du marché, consultez les détails, puis installez-les dans le dossier global actuel.',
                  de: 'Suche Skills im Marktplatz, prüfe Details und installiere sie in das aktuelle globale Skill-Verzeichnis.',
                  ja: 'マーケットのスキルを検索し、詳細を確認して現在のグローバルスキルディレクトリへインストールします。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        kOpenHandHGap12,
        MarketProviderSelector(
          providers: widget.providers.providers
              .map((entry) => entry.info)
              .toList(growable: false),
          selected: _session.info,
          enabled: !_isInstalling && !_filePreviewOpen,
          onSelected: _switchProvider,
        ),
      ],
    );
  }

  Widget _buildSearchPane(BuildContext context) {
    final installedSkillKeys = _installedSkillKeys(
      context.watch<SkillsController>(),
    );
    final result = _searchResult;
    final skills = result?.skills ?? const <SkillMarketSummary>[];

    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.04),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchBar(
              controller: _searchController,
              elevation: const WidgetStatePropertyAll(0),
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              hintText: openHandLocalizedText(
                context,
                zh: '搜索市场技能',
                zhHant: '搜尋市場技能',
                en: 'Search market skills',
                fr: 'Rechercher des compétences',
                de: 'Skills suchen',
                ja: 'マーケットスキルを検索',
              ),
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_searchInput.trim().isNotEmpty) ...[
                  Tooltip(
                    message: openHandClearSearchLabel(context),
                    child: IconButton(
                      onPressed: _isSearching ? null : _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  kOpenHandHGap8,
                ],
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '刷新搜索',
                    zhHant: '重新整理搜尋',
                    en: 'Refresh search',
                    fr: 'Actualiser la recherche',
                    de: 'Suche aktualisieren',
                    ja: '検索を更新',
                  ),
                  child: IconButton(
                    onPressed: _isSearching ? null : _refreshCurrentSearch,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
              onChanged: _handleSearchChanged,
              onSubmitted: _handleSearchSubmitted,
            ),
            kOpenHandGap12,
            if (_isSearching && result != null)
              const LinearProgressIndicator(minHeight: 2),
            if (_isSearching && result != null) kOpenHandGap10,
            Expanded(
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                child: _searchError != null || _session.provider == null
                    ? _MarketStateMessage(
                        key: const ValueKey<String>('market-search-error'),
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
                        body:
                            _searchError ?? marketProviderUnavailable(context),
                        actionLabel: _skillMarketDiaRetryLabel(context),
                        onAction: () => _runSearch(keepSelection: false),
                      )
                    : _isSearching && result == null
                    ? const Center(
                        key: ValueKey<String>('market-search-loading'),
                        child: CircularProgressIndicator(),
                      )
                    : skills.isEmpty
                    ? _MarketStateMessage(
                        key: const ValueKey<String>('market-search-empty'),
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
                          zh: '换个关键词再试试，或清空搜索查看热门技能。',
                          zhHant: '換個關鍵詞再試試，或清空搜尋查看熱門技能。',
                          en: 'Try another keyword, or clear the search to browse popular skills.',
                          fr: 'Essayez un autre mot-clé ou effacez la recherche pour voir les compétences populaires.',
                          de: 'Versuche ein anderes Stichwort oder leere die Suche, um beliebte Skills zu sehen.',
                          ja: '別のキーワードを試すか、検索をクリアして人気スキルを表示してください。',
                        ),
                      )
                    : ListView.separated(
                        key: ValueKey<String>(
                          'market-results-${result?.page}-$_keyword',
                        ),
                        itemCount: skills.length,
                        separatorBuilder: (context, index) => kOpenHandGap8,
                        itemBuilder: (context, index) {
                          final skill = skills[index];
                          return AppearOnce(
                            key: ValueKey<String>('skill-market-${skill.slug}'),
                            child: _SkillMarketResultTile(
                              skill: skill,
                              installed: _isMarketSkillInstalled(
                                skill,
                                installedSkillKeys,
                              ),
                              selected: _selectedSkill?.slug == skill.slug,
                              onTap: () => _selectSkill(skill),
                            ),
                          );
                        },
                      ),
              ),
            ),
            kOpenHandGap12,
            OpenHandTablePagination(
              total: result?.total ?? 0,
              page: result?.page ?? _page,
              pageSize: result?.pageSize ?? _pageSize,
              enabled: !_isSearching && result != null,
              onPageChanged: _goToPage,
              onPageSizeChanged: (size) {
                if (_isSearching || size == _pageSize) return;
                setState(() {
                  _pageSize = size;
                  _page = 1;
                });
                unawaited(_runSearch(keepSelection: false));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedSkill = _selectedSkill;
    final bundleFuture = _selectedBundleFuture;
    final pane = selectedSkill == null || bundleFuture == null
        ? _MarketStateMessage(
            icon: Icons.auto_awesome_rounded,
            title: openHandLocalizedText(
              context,
              zh: '选择一个技能',
              zhHant: '選擇一個技能',
              en: 'Select a skill',
              fr: 'Sélectionner une compétence',
              de: 'Skill auswählen',
              ja: 'スキルを選択',
            ),
            body: openHandLocalizedText(
              context,
              zh: '点击左侧候选项后，这里会展示概述、版本、安全报告和详情。',
              zhHant: '點擊左側候選項後，這裡會展示概述、版本、安全報告和詳情。',
              en: 'Choose a result on the left to view the summary, versions, security reports, and details.',
              fr: 'Choisissez un résultat à gauche pour voir le résumé, les versions, les rapports de sécurité et les détails.',
              de: 'Wähle links ein Ergebnis, um Übersicht, Versionen, Sicherheitsberichte und Details zu sehen.',
              ja: '左側の候補を選ぶと、概要、バージョン、セキュリティレポート、詳細を表示します。',
            ),
          )
        : FutureBuilder<SkillMarketBundle>(
            future: bundleFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _MarketStateMessage(
                  icon: Icons.error_outline_rounded,
                  title: openHandLocalizedText(
                    context,
                    zh: '详情加载失败',
                    zhHant: '詳情載入失敗',
                    en: 'Details failed',
                    fr: 'Échec des détails',
                    de: 'Details fehlgeschlagen',
                    ja: '詳細の読み込みに失敗',
                  ),
                  body: openHandLocalizedText(
                    context,
                    zh: '无法加载该技能详情，请重试。',
                    zhHant: '無法載入該技能詳情，請重試。',
                    en: 'Unable to load this skill detail. Try again.',
                    fr: 'Impossible de charger les détails de cette compétence. Réessayez.',
                    de: 'Skill-Details konnten nicht geladen werden. Erneut versuchen.',
                    ja: 'このスキルの詳細を読み込めません。再試行してください。',
                  ),
                  actionLabel: _skillMarketDiaRetryLabel(context),
                  onAction: () =>
                      _selectSkill(selectedSkill, forceReload: true),
                );
              }
              return _SkillMarketDetailView(
                summary: selectedSkill,
                bundle: snapshot.data!,
                onVersionSelected: _selectSkillVersion,
                onFileOpen: (path, size) {
                  final bundle = snapshot.data!;
                  final slug = bundle.detail.skill.slug.isNotEmpty
                      ? bundle.detail.skill.slug
                      : selectedSkill.slug;
                  final version = bundle.resolvedVersion.isNotEmpty
                      ? bundle.resolvedVersion
                      : selectedSkill.version;
                  unawaited(
                    _openSkillMarketFile(
                      slug: slug,
                      version: version,
                      path: path,
                      size: size,
                    ),
                  );
                },
              );
            },
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.tertiary.withValues(alpha: 0.05),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: pane,
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final skillsController = context.watch<SkillsController>();
    final storagePath = skillsController.storagePath;
    final installedSkillKeys = _installedSkillKeys(skillsController);
    final selectedSkill = _selectedSkill;
    final selectedSkillInstalled =
        selectedSkill != null &&
        _isMarketSkillInstalled(selectedSkill, installedSkillKeys);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: '安装目录：${OpenHandPaths.shortenHomePath(storagePath)}',
                  zhHant: '安裝目錄：${OpenHandPaths.shortenHomePath(storagePath)}',
                  en: 'Install path: ${OpenHandPaths.shortenHomePath(storagePath)}',
                  fr: 'Chemin d’installation : ${OpenHandPaths.shortenHomePath(storagePath)}',
                  de: 'Installationspfad: ${OpenHandPaths.shortenHomePath(storagePath)}',
                  ja: 'インストール先：${OpenHandPaths.shortenHomePath(storagePath)}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_installError != null) ...[
                kOpenHandGap4,
                Text(
                  _installError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        kOpenHandHGap16,
        OpenHandDialogActionButton.secondary(
          onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        kOpenHandHGap12,
        OpenHandDialogActionButton.primary(
          onPressed:
              selectedSkill == null || selectedSkillInstalled || _isInstalling
              ? null
              : _installSelectedSkill,
          icon: selectedSkillInstalled
              ? Icons.check_rounded
              : Icons.download_rounded,
          busy: _isInstalling,
          label: _isInstalling
              ? openHandLocalizedText(
                  context,
                  zh: '安装中',
                  zhHant: '安裝中',
                  en: 'Installing',
                  fr: 'Installation',
                  de: 'Wird installiert',
                  ja: 'インストール中',
                )
              : selectedSkillInstalled
              ? openHandInstalledLabel(context)
              : openHandInstallLabel(context),
        ),
      ],
    );
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchInput = value;
    });
    _searchDebounce.schedule(() {
      if (!mounted) {
        return;
      }
      _keyword = value.trim();
      _page = 1;
      unawaited(_runSearch(keepSelection: false));
    });
  }

  void _handleSearchSubmitted(String value) {
    _searchDebounce.cancel();
    setState(() {
      _searchInput = value;
      _keyword = value.trim();
      _page = 1;
    });
    unawaited(_runSearch(keepSelection: false));
  }

  void _switchProvider(String id) {
    if (_isInstalling || _filePreviewOpen || !_session.select(id)) return;
    _searchDebounce.cancel();
    ++_searchToken;
    setState(() {
      _page = 1;
      _selectedPreviewVersions.clear();
      _searchResult = null;
      _selectedSkill = null;
      _selectedBundleFuture = null;
      _searchError = _installError = null;
      _keyword = _searchInput.trim();
    });
    unawaited(_runSearch(keepSelection: false));
  }

  void _clearSearch() {
    _searchDebounce.cancel();
    _searchController.clear();
    setState(() {
      _searchInput = '';
      _keyword = '';
      _page = 1;
    });
    unawaited(_runSearch(keepSelection: false));
  }

  void _refreshCurrentSearch() {
    _searchDebounce.cancel();
    _session.provider?.clearSearchCache();
    unawaited(_runSearch(keepSelection: true));
  }

  Future<void> _runSearch({required bool keepSelection}) async {
    final token = ++_searchToken;
    if (_session.provider == null) {
      setState(() => _searchError = marketProviderUnavailable(context));
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
      _installError = null;
    });

    try {
      final result = await _marketClient.searchSkills(
        keyword: _keyword,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted || token != _searchToken) {
        return;
      }

      final previousSlug = keepSelection ? _selectedSkill?.slug : null;
      var nextSelected = previousSlug == null
          ? null
          : _findSkillBySlug(result.skills, previousSlug);
      nextSelected ??= result.skills.isEmpty ? null : result.skills.first;

      setState(() {
        _searchResult = result;
        _isSearching = false;
        _selectedSkill = nextSelected;
        _selectedBundleFuture = nextSelected == null
            ? null
            : _marketClient.loadSkillBundle(
                nextSelected.slug,
                version: _selectedPreviewVersions[nextSelected.slug],
              );
      });
    } catch (error, stackTrace) {
      if (isHttpRequestAborted(error)) {
        if (mounted && token == _searchToken) {
          setState(() => _isSearching = false);
        }
        return;
      }
      silentLog('skill_market_dialog', '搜索技能', error, stackTrace);
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() {
        _isSearching = false;
        _searchError = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '技能市场搜索失败，请稍后重试。',
            zhHant: '技能市場搜尋失敗，請稍後再試。',
            en: 'Skill marketplace search failed. Try again later.',
            fr: 'La recherche a échoué. Réessayez plus tard.',
            de: 'Marktplatzsuche fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: 'スキルマーケットの検索に失敗しました。後でもう一度お試しください。',
          ),
        );
        if (_searchResult == null) {
          _selectedSkill = null;
          _selectedBundleFuture = null;
        }
      });
    }
  }

  void _goToPage(int page) {
    if (_isSearching) {
      return;
    }
    setState(() {
      _page = page < 1 ? 1 : page;
    });
    unawaited(_runSearch(keepSelection: false));
  }

  void _selectSkill(SkillMarketSummary skill, {bool forceReload = false}) {
    if (!(_searchResult?.skills.contains(skill) ?? false)) return;
    if (!forceReload &&
        _selectedSkill?.slug == skill.slug &&
        _selectedBundleFuture != null) {
      return;
    }
    setState(() {
      _selectedSkill = skill;
      _selectedBundleFuture = _marketClient.loadSkillBundle(
        skill.slug,
        version: _selectedPreviewVersions[skill.slug],
      );
      _installError = null;
    });
  }

  void _selectSkillVersion(String version) {
    final skill = _selectedSkill;
    if (skill == null || version.trim().isEmpty) {
      return;
    }
    final normalizedVersion = version.trim();
    if (_selectedPreviewVersions[skill.slug] == normalizedVersion &&
        _selectedBundleFuture != null) {
      return;
    }
    setState(() {
      _selectedPreviewVersions[skill.slug] = normalizedVersion;
      _selectedBundleFuture = _marketClient.loadSkillBundle(
        skill.slug,
        version: normalizedVersion,
      );
      _installError = null;
    });
  }

  Future<void> _openSkillMarketFile({
    required String slug,
    required String version,
    required String path,
    required int size,
  }) async {
    if (_filePreviewOpen) return;
    final normalizedSlug = slug.trim();
    final normalizedVersion = version.trim();
    final normalizedPath = path.trim();
    if (normalizedSlug.isEmpty ||
        normalizedVersion.isEmpty ||
        normalizedPath.isEmpty) {
      return;
    }
    _filePreviewOpen = true;
    try {
      if (!mounted) return;
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) => _SkillMarketFilePreviewDialog(
          client: _marketClient,
          slug: normalizedSlug,
          version: normalizedVersion,
          path: normalizedPath,
          size: size < 0 ? 0 : size,
        ),
      );
    } finally {
      _filePreviewOpen = false;
    }
  }

  Future<void> _installSelectedSkill() async {
    final skill = _selectedSkill;
    if (skill == null || _isInstalling) {
      return;
    }
    final skillsController = context.read<SkillsController>();
    final provider = _marketClient;
    final providerInfo = _session.info!;
    final previewVersion = _selectedPreviewVersions[skill.slug];
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _SkillMarketInstallConfirmDialog(
          skill: skill,
          storagePath: skillsController.storagePath,
          previewVersion: previewVersion,
          providerInfo: providerInfo,
        );
      },
    );
    if (!mounted ||
        confirmed != true ||
        !identical(provider, _session.provider)) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isInstalling = true;
      _installError = null;
    });

    try {
      final archiveBytes = await provider.downloadSkillArchive(skill.slug);
      final installedSkill = await skillsController.installSkillArchive(
        preferredSlug: skill.slug,
        archiveBytes: archiveBytes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isInstalling = false;
        _installError = null;
      });
      flashOpenHandSnack(
        context,
        '${openHandLocalizedText(context, zh: '已安装技能', zhHant: '已安裝技能', en: 'Skill installed', fr: 'Compétence installée', de: 'Skill installiert', ja: 'スキルをインストールしました')}: ${installedSkill.name}',
        kind: OpenHandSnackKind.success,
      );
      _installSuccessSignal.value++;
    } catch (error, stackTrace) {
      if (isHttpRequestAborted(error)) {
        if (mounted) {
          setState(() => _isInstalling = false);
        }
        return;
      }
      silentLog('skill_market_dialog', '安装技能 ${skill.slug}', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _isInstalling = false;
        _installError = openHandLocalizedText(
          context,
          zh: '安装失败，请检查网络、磁盘权限或技能压缩包内容。',
          zhHant: '安裝失敗，請檢查網路、磁碟權限或技能壓縮包內容。',
          en: 'Install failed. Check the network, disk permission, or archive contents.',
          fr: 'Installation échouée. Vérifiez le réseau, les permissions disque ou l’archive.',
          de: 'Installation fehlgeschlagen. Prüfe Netzwerk, Dateirechte oder Archivinhalt.',
          ja: 'インストールに失敗しました。ネットワーク、ディスク権限、アーカイブ内容を確認してください。',
        );
      });
      _installErrorSignal.value++;
    }
  }

  SkillMarketSummary? _findSkillBySlug(
    List<SkillMarketSummary> skills,
    String slug,
  ) {
    for (final skill in skills) {
      if (skill.slug == slug) {
        return skill;
      }
    }
    return null;
  }
}

class _SkillMarketInstallConfirmDialog extends StatelessWidget {
  const _SkillMarketInstallConfirmDialog({
    required this.skill,
    required this.storagePath,
    required this.providerInfo,
    this.previewVersion,
  });

  final SkillMarketSummary skill;
  final String storagePath;
  final MarketProviderInfo providerInfo;
  final String? previewVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayName = skillMarketDisplayName(context, skill.displayName);
    final publisher = skillMarketPublisherLabel(
      publisherName: skill.publisherName,
      ownerName: skill.ownerName,
      slug: skill.slug,
    );
    final normalizedPreviewVersion = previewVersion?.trim() ?? '';
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthStandard,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OpenHandTintedPanel(
              accent: colorScheme.primary,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkillMarketAvatar(
                    name: displayName,
                    imageUrl: skill.iconUrl,
                    size: _kSkillMarketConfirmAvatarSize,
                  ),
                  kOpenHandHGap14,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '确认安装技能',
                            zhHant: '確認安裝技能',
                            en: 'Confirm install',
                            fr: 'Confirmer l’installation',
                            de: 'Installation bestätigen',
                            ja: 'インストール確認',
                          ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap6,
                        Text(
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandGap16,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (publisher.isNotEmpty)
                  OpenHandFactChip(
                    icon: Icons.badge_outlined,
                    label: publisher,
                    color: colorScheme.primary,
                  ),
                if (skill.source.isNotEmpty)
                  OpenHandFactChip(
                    icon: Icons.hub_outlined,
                    label: skillMarketSourceValueLabel(context, skill.source),
                    color: colorScheme.tertiary,
                  ),
                OpenHandFactChip(
                  icon: Icons.folder_open_rounded,
                  label: OpenHandPaths.shortenHomePath(storagePath),
                  color: OpenHandStatusColors.info,
                ),
                if (normalizedPreviewVersion.isNotEmpty)
                  OpenHandFactChip(
                    icon: Icons.sell_outlined,
                    label: normalizedPreviewVersion,
                    color: colorScheme.secondary,
                  ),
              ],
            ),
            kOpenHandGap16,
            Text(
              openHandLocalizedText(
                context,
                zh: '将从 ${marketProviderName(context, providerInfo)} 下载技能压缩包，并解压到当前全局技能目录。',
                zhHant:
                    '將從 ${marketProviderName(context, providerInfo)} 下載技能壓縮包，並解壓到目前全域技能目錄。',
                en: 'OpenHand will download the skill archive from ${marketProviderName(context, providerInfo)} and extract it into the current global skills directory.',
                fr: 'OpenHand téléchargera l’archive depuis ${marketProviderName(context, providerInfo)} et l’extraira dans le dossier global actuel.',
                de: 'OpenHand lädt das Skill-Archiv von ${marketProviderName(context, providerInfo)} und entpackt es in das aktuelle globale Skill-Verzeichnis.',
                ja: 'OpenHand は ${marketProviderName(context, providerInfo)} からスキルアーカイブをダウンロードし、現在のグローバルスキルディレクトリへ展開します。',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            kOpenHandGap22,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(false),
                  label: l10n.commonCancel,
                ),
                kOpenHandHGap12,
                OpenHandDialogActionButton.primary(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icons.download_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '确认安装',
                    zhHant: '確認安裝',
                    en: 'Install',
                    fr: 'Installer',
                    de: 'Installieren',
                    ja: 'インストール',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillMarketResultTile extends StatelessWidget {
  const _SkillMarketResultTile({
    required this.skill,
    required this.installed,
    required this.selected,
    required this.onTap,
  });

  final SkillMarketSummary skill;
  final bool installed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _skillMarketCategoryAccent(colorScheme, skill.category);
    final displayName = skillMarketDisplayName(context, skill.displayName);
    final publisher = skillMarketPublisherLabel(
      publisherName: skill.publisherName,
      ownerName: skill.ownerName,
      slug: skill.slug,
    );
    final summary = _localizedSummary(
      context,
      zh: skill.descriptionZh,
      en: skill.description,
    );
    final categoryLabel = skill.category.isEmpty
        ? ''
        : skillMarketCategoryLabel(context, skill.category);
    final radius = BorderRadius.circular(kOpenHandRadius18);

    return MicroPressFeedback(
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
                        _SkillMarketAvatar(
                          name: displayName,
                          imageUrl: skill.iconUrl,
                          size: _kSkillMarketListAvatarSize,
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
                              if (publisher.isNotEmpty) ...[
                                kOpenHandGap3,
                                Text(
                                  publisher,
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
                                    label: _formatCount(
                                      context,
                                      skill.downloads,
                                    ),
                                    color: OpenHandStatusColors.info,
                                  ),
                                  OpenHandFactChip(
                                    icon: Icons.star_rounded,
                                    label: _formatCount(context, skill.stars),
                                    color: OpenHandStatusColors.caution,
                                  ),
                                  if (installed)
                                    OpenHandStatusPill(
                                      icon: Icons.check_circle_rounded,
                                      label: openHandInstalledLabel(context),
                                      color: OpenHandStatusColors.success,
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

class _SkillMarketDetailView extends StatelessWidget {
  const _SkillMarketDetailView({
    required this.summary,
    required this.bundle,
    required this.onVersionSelected,
    required this.onFileOpen,
  });

  final SkillMarketSummary summary;
  final SkillMarketBundle bundle;
  final ValueChanged<String> onVersionSelected;
  final void Function(String path, int size) onFileOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final detail = bundle.detail;
    final skill = detail.skill;
    final rawName = skill.displayName.isNotEmpty
        ? skill.displayName
        : summary.displayName;
    final displayName = skillMarketDisplayName(context, rawName);
    final publisher = skillMarketPublisherLabel(
      publisherName: detail.publisherName.isNotEmpty
          ? detail.publisherName
          : summary.publisherName,
      ownerName: detail.owner.displayName.isNotEmpty
          ? detail.owner.displayName
          : summary.ownerName,
      ownerHandle: detail.owner.handle,
      slug: skill.slug,
    );
    final categoryKey = skill.category.isNotEmpty
        ? skill.category
        : summary.category;
    final accent = _skillMarketCategoryAccent(colorScheme, categoryKey);
    final detailOverview = _localizedSummary(
      context,
      zh: skill.summaryZh,
      en: skill.summary,
    );
    final overview = detailOverview.isNotEmpty
        ? detailOverview
        : _localizedSummary(
            context,
            zh: summary.descriptionZh,
            en: summary.description,
          );
    final version = bundle.resolvedVersion.isEmpty
        ? summary.version
        : bundle.resolvedVersion;
    final downloads = skill.stats.downloads == 0
        ? summary.downloads
        : skill.stats.downloads;
    final installs = skill.stats.installs == 0
        ? summary.installs
        : skill.stats.installs;
    final stars = skill.stats.stars == 0 ? summary.stars : skill.stats.stars;
    final subCategories = skill.subCategories.isNotEmpty
        ? skill.subCategories
        : summary.subCategories;
    final source = skill.source.isNotEmpty ? skill.source : summary.source;
    final files = bundle.files?.files ?? const <SkillMarketFileEntry>[];
    final requiresApiKey = skill.requiresApiKey || summary.requiresApiKey;

    return ClipRRect(
      borderRadius: BorderRadius.circular(kOpenHandRadius22),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OpenHandTintedPanel(
            accent: accent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkillMarketAvatar(
                  name: displayName,
                  imageUrl: skill.iconUrl ?? summary.iconUrl,
                  size: _kSkillMarketDetailAvatarSize,
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
                      if (publisher.isNotEmpty) ...[
                        kOpenHandGap6,
                        Text(
                          publisher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      kOpenHandGap10,
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (version.isNotEmpty)
                            OpenHandStatusPill(
                              icon: Icons.sell_outlined,
                              label: version,
                              color: accent,
                            ),
                          if (categoryKey.isNotEmpty)
                            OpenHandFactChip(
                              icon: Icons.category_outlined,
                              label: skillMarketCategoryLabel(
                                context,
                                categoryKey,
                              ),
                              color: accent,
                            ),
                          if (source.isNotEmpty)
                            OpenHandFactChip(
                              icon: Icons.hub_outlined,
                              label: skillMarketSourceValueLabel(
                                context,
                                source,
                              ),
                              color: colorScheme.tertiary,
                            ),
                          OpenHandFactChip(
                            icon: Icons.key_outlined,
                            label:
                                '${skillMarketApiKeyLabel(context)} · ${requiresApiKey ? skillMarketApiKeyRequiredLabel(context) : skillMarketApiKeyOptionalLabel(context)}',
                            color: requiresApiKey
                                ? OpenHandStatusColors.warning
                                : OpenHandStatusColors.success,
                          ),
                          for (final sub in subCategories.take(
                            _kSkillMarketMaxPreviewSubcategories,
                          ))
                            OpenHandFactChip(
                              icon: Icons.local_offer_outlined,
                              label: skillMarketCategoryLabel(
                                context,
                                sub.key,
                                fallbackName: sub.name,
                              ),
                              color: colorScheme.secondary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (overview.isNotEmpty) ...[
            kOpenHandGap14,
            OpenHandTintedPanel(
              accent: colorScheme.tertiary,
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
                overview,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
          kOpenHandGap14,
          OpenHandMetricsStrip(
            items: <OpenHandMetricItem>[
              (
                label: skillMarketDownloadsLabel(context),
                value: _formatCount(context, downloads),
                accent: OpenHandStatusColors.info,
              ),
              (
                label: skillMarketInstallsLabel(context),
                value: _formatCount(context, installs),
                accent: colorScheme.tertiary,
              ),
              (
                label: skillMarketStarsLabel(context),
                value: _formatCount(context, stars),
                accent: OpenHandStatusColors.caution,
              ),
            ],
          ),
          if (detail.securityReports.isNotEmpty) ...[
            kOpenHandGap14,
            OpenHandTintedPanel(
              accent: OpenHandStatusColors.success,
              icon: Icons.verified_user_outlined,
              title: openHandLocalizedText(
                context,
                zh: '安全报告',
                zhHant: '安全報告',
                en: 'Security reports',
                fr: 'Rapports de sécurité',
                de: 'Sicherheitsberichte',
                ja: 'セキュリティレポート',
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: detail.securityReports.entries
                    .map((entry) {
                      final benign =
                          entry.value.status.toLowerCase() == 'benign';
                      final color = benign
                          ? OpenHandStatusColors.success
                          : OpenHandStatusColors.error;
                      return OpenHandStatusPill(
                        icon: benign
                            ? Icons.verified_user_outlined
                            : Icons.warning_amber_rounded,
                        label:
                            '${skillMarketScannerLabel(context, entry.key)} · ${skillMarketSecurityStatusLabel(context, status: entry.value.status, statusText: entry.value.statusText)}',
                        color: color,
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
          if (bundle.versions.isNotEmpty) ...[
            kOpenHandGap14,
            OpenHandTintedPanel(
              accent: colorScheme.primary,
              icon: Icons.history_rounded,
              title: openHandLocalizedText(
                context,
                zh: '预览版本',
                zhHant: '預覽版本',
                en: 'Preview version',
                fr: 'Version d’aperçu',
                de: 'Vorschauversion',
                ja: 'プレビューバージョン',
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: bundle.versions
                    .where((version) => version.version.isNotEmpty)
                    .take(_kSkillMarketMaxPreviewVersions)
                    .map((item) {
                      final selected = item.version == bundle.resolvedVersion;
                      final tooltip = item.changelog.isEmpty
                          ? item.version
                          : item.changelog;
                      return Tooltip(
                        message: tooltip,
                        child: OpenHandChoicePill(
                          selected: selected,
                          onSelected: selected
                              ? null
                              : () => onVersionSelected(item.version),
                          label: item.version,
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
          if (files.isNotEmpty) ...[
            kOpenHandGap14,
            OpenHandTintedPanel(
              accent: colorScheme.secondary,
              icon: Icons.folder_open_rounded,
              title: openHandLocalizedText(
                context,
                zh: '包含文件',
                zhHant: '包含檔案',
                en: 'Included files',
                fr: 'Fichiers inclus',
                de: 'Enthaltene Dateien',
                ja: '含まれるファイル',
              ),
              child: _SkillMarketIncludedFilesPanel(
                key: ValueKey<String>(
                  '${summary.slug}|${bundle.resolvedVersion}|${files.length}',
                ),
                files: files,
                accent: accent,
                onFileOpen: onFileOpen,
              ),
            ),
          ],
          kOpenHandGap14,
          OpenHandTintedPanel(
            accent: colorScheme.primary,
            icon: Icons.menu_book_rounded,
            title: openHandDetailsLabel(context),
            child: OpenHandDocumentMarkdownPreview(
              data: bundle.skillMarkdown ?? '',
              backgroundColor: Colors.transparent,
              maxCharacters: kOpenHandMarketMarkdownMaxCharacters,
              truncationMessage: _skillMarketTruncationMessage(context),
              emptyMessage: openHandLocalizedText(
                context,
                zh: '未找到技能说明内容。',
                zhHant: '未找到技能說明內容。',
                en: 'No skill description was found.',
                fr: 'Aucune description de compétence trouvée.',
                de: 'Keine Skill-Beschreibung gefunden.',
                ja: 'スキル説明が見つかりません。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillMarketIncludedFilesPanel extends StatefulWidget {
  const _SkillMarketIncludedFilesPanel({
    super.key,
    required this.files,
    required this.accent,
    required this.onFileOpen,
  });

  final List<SkillMarketFileEntry> files;
  final Color accent;
  final void Function(String path, int size) onFileOpen;

  @override
  State<_SkillMarketIncludedFilesPanel> createState() =>
      _SkillMarketIncludedFilesPanelState();
}

class _SkillMarketIncludedFilesPanelState
    extends State<_SkillMarketIncludedFilesPanel> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedPaths = <String>{};
  late _SkillMarketFileTreeNode _root = _skillMarketFileTree(widget.files);

  @override
  void didUpdateWidget(covariant _SkillMarketIncludedFilesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_filesChanged(oldWidget.files, widget.files)) return;
    _root = _skillMarketFileTree(widget.files);
    _expandedPaths.clear();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _filesChanged(
    List<SkillMarketFileEntry> previous,
    List<SkillMarketFileEntry> next,
  ) {
    if (identical(previous, next)) return false;
    if (previous.length != next.length) return true;
    if (previous.isEmpty) return false;
    return previous.first.path != next.first.path ||
        previous.last.path != next.last.path;
  }

  void _toggleDirectory(String path) {
    if (path.isEmpty) return;
    setState(() {
      if (!_expandedPaths.add(path)) {
        _expandedPaths.remove(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final roots = _root.sortedChildren;
    if (roots.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Text(
        openHandLocalizedText(
          context,
          zh: '没有可展示的文件路径。',
          zhHant: '沒有可展示的檔案路徑。',
          en: 'No file paths to display.',
          fr: 'Aucun chemin de fichier à afficher.',
          de: 'Keine Dateipfade vorhanden.',
          ja: '表示できるファイルパスがありません。',
        ),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      );
    }
    final panelMotion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.panel,
    );
    return ClipRect(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: _kSkillMarketFileTreeMaxHeight,
        ),
        child: OpenHandSafeScrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            primary: false,
            physics: openHandDialogAwareScrollPhysics(context),
            child: _buildTreeList(
              nodes: roots,
              depth: 0,
              revealDuration: panelMotion.entranceDuration,
              revealReverseDuration: panelMotion.exitDuration,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeList({
    required List<_SkillMarketFileTreeNode> nodes,
    required int depth,
    required Duration revealDuration,
    required Duration revealReverseDuration,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < nodes.length; i++) ...[
          if (i > 0) const SizedBox(height: _kSkillMarketFileTreeRowGap),
          _buildTreeEntry(
            node: nodes[i],
            depth: depth,
            revealDuration: revealDuration,
            revealReverseDuration: revealReverseDuration,
          ),
        ],
      ],
    );
  }

  Widget _buildTreeEntry({
    required _SkillMarketFileTreeNode node,
    required int depth,
    required Duration revealDuration,
    required Duration revealReverseDuration,
  }) {
    final children = node.sortedChildren;
    final canExpand = node.isDirectory && children.isNotEmpty;
    final expanded = canExpand && _expandedPaths.contains(node.path);
    return Column(
      key: ValueKey<String>(node.path),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTreeRow(
          node: node,
          depth: depth,
          canExpand: canExpand,
          expanded: expanded,
          childCount: children.length,
          revealDuration: revealDuration,
        ),
        if (canExpand)
          OpenHandVerticalRevealSwitcher(
            duration: revealDuration,
            reverseDuration: revealReverseDuration,
            slideBeginOffsetY: -0.04,
            presentKey: ValueKey<String>('expand-${node.path}'),
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: _kSkillMarketFileTreeRowGap,
                    ),
                    child: _buildTreeList(
                      nodes: children,
                      depth: depth + 1,
                      revealDuration: revealDuration,
                      revealReverseDuration: revealReverseDuration,
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  Widget _buildTreeRow({
    required _SkillMarketFileTreeNode node,
    required int depth,
    required bool canExpand,
    required bool expanded,
    required int childCount,
    required Duration revealDuration,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final indent =
        math.min(depth, _kSkillMarketFileTreeMaxSegments) *
        _kSkillMarketFileTreeIndent;
    final isDirectory = node.isDirectory;
    final openPath = node.sourcePath.trim().isEmpty
        ? node.path
        : node.sourcePath;
    final canOpenFile = !isDirectory && openPath.trim().isNotEmpty;
    final onTap = canExpand
        ? () => _toggleDirectory(node.path)
        : canOpenFile
        ? () => widget.onFileOpen(openPath, node.size)
        : null;
    final icon = isDirectory
        ? (expanded ? Icons.folder_open_rounded : Icons.folder_rounded)
        : openHandFileNameIcon(node.name);
    final iconColor = isDirectory
        ? widget.accent
        : colorScheme.onSurfaceVariant;
    final tooltip = node.path.isEmpty
        ? node.name
        : isDirectory
        ? openHandLocalizedText(
            context,
            zh: expanded ? '折叠 ${node.path}' : '展开 ${node.path}',
            zhHant: expanded ? '摺疊 ${node.path}' : '展開 ${node.path}',
            en: expanded ? 'Collapse ${node.path}' : 'Expand ${node.path}',
            fr: expanded ? 'Réduire ${node.path}' : 'Développer ${node.path}',
            de: expanded
                ? '${node.path} einklappen'
                : '${node.path} ausklappen',
            ja: expanded ? '${node.path} を折りたたむ' : '${node.path} を展開',
          )
        : openHandLocalizedText(
            context,
            zh: '预览 ${node.path}',
            zhHant: '預覽 ${node.path}',
            en: 'Preview ${node.path}',
            fr: 'Aperçu ${node.path}',
            de: '${node.path} Vorschau',
            ja: '${node.path} をプレビュー',
          );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: _kSkillMarketFileTreeRowMinHeight,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8 + indent, 7, 10, 7),
        child: Row(
          children: [
            SizedBox(
              width: _kSkillMarketFileTreeChevronSize,
              height: _kSkillMarketFileTreeChevronSize,
              child: canExpand
                  ? AnimatedExpandChevron(
                      expanded: expanded,
                      size: _kSkillMarketFileTreeChevronSize,
                      color: colorScheme.onSurfaceVariant,
                      duration: revealDuration,
                    )
                  : null,
            ),
            kOpenHandHGap6,
            Icon(icon, size: 16, color: iconColor),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isDirectory ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isDirectory && childCount > 0) ...[
              kOpenHandHGap8,
              Text(
                _skillMarketFileTreeItemCount(context, childCount),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
                ),
              ),
            ],
            kOpenHandHGap8,
            Text(
              formatLocalizedByteSizeOf(context, node.size),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      expanded: canExpand ? expanded : null,
      label: node.name,
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 420),
        child: MicroPressFeedback(
          enabled: onTap != null,
          child: Material(
            color: Colors.transparent,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: kOpenHandBorderRadius10,
              mouseCursor: onTap == null
                  ? SystemMouseCursors.basic
                  : WidgetStateMouseCursor.clickable,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.accent.withValues(alpha: 0.10);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return colorScheme.onSurface.withValues(alpha: 0.05);
                }
                return Colors.transparent;
              }),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillMarketFileTreeNode {
  _SkillMarketFileTreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sourcePath = '',
  });

  final String name;
  final String path;
  final String sourcePath;
  bool isDirectory;
  int size = 0;
  final Map<String, _SkillMarketFileTreeNode> children =
      <String, _SkillMarketFileTreeNode>{};
  List<_SkillMarketFileTreeNode>? _sortedChildren;

  List<_SkillMarketFileTreeNode> get sortedChildren {
    final cached = _sortedChildren;
    if (cached != null) return cached;
    final list = children.values.toList();
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return _sortedChildren = list;
  }
}

List<String> _skillMarketPathSegments(String raw) {
  var normalized = raw.trim().replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized.isEmpty) return const <String>[];
  final parts = <String>[];
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return const <String>[];
    parts.add(part);
  }
  if (parts.isEmpty) return const <String>[];
  if (parts.length <= _kSkillMarketFileTreeMaxSegments) return parts;
  return <String>[
    ...parts.take(_kSkillMarketFileTreeMaxSegments - 1),
    parts.skip(_kSkillMarketFileTreeMaxSegments - 1).join('/'),
  ];
}

_SkillMarketFileTreeNode _skillMarketFileTree(
  List<SkillMarketFileEntry> files,
) {
  final root = _SkillMarketFileTreeNode(name: '', path: '', isDirectory: true);
  final seen = <String>{};
  for (final file in files) {
    final parts = _skillMarketPathSegments(file.path);
    if (parts.isEmpty) continue;
    final key = parts.join('/');
    if (!seen.add(key)) continue;
    final fileSize = file.size < 0 ? 0 : file.size;
    var current = root;
    final pathBuffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final isLeaf = i == parts.length - 1;
      final part = parts[i];
      if (pathBuffer.isNotEmpty) pathBuffer.write('/');
      pathBuffer.write(part);
      final childPath = pathBuffer.toString();
      final child = current.children.putIfAbsent(
        part,
        () => _SkillMarketFileTreeNode(
          name: part,
          path: childPath,
          isDirectory: !isLeaf,
          sourcePath: isLeaf ? file.path : '',
        ),
      );
      if (!isLeaf) {
        child.isDirectory = true;
        child.size += fileSize;
      } else if (child.isDirectory) {
        child.size += fileSize;
      } else {
        child.size = fileSize;
      }
      current = child;
    }
    root.size += fileSize;
  }
  return root;
}

enum _SkillMarketFilePreviewKind { loading, ready, error, binary, tooLarge }

class _SkillMarketFilePreviewDialog extends StatefulWidget {
  const _SkillMarketFilePreviewDialog({
    required this.client,
    required this.slug,
    required this.version,
    required this.path,
    required this.size,
  });

  final SkillMarketProvider client;
  final String slug;
  final String version;
  final String path;
  final int size;

  @override
  State<_SkillMarketFilePreviewDialog> createState() =>
      _SkillMarketFilePreviewDialogState();
}

class _SkillMarketFilePreviewDialogState
    extends State<_SkillMarketFilePreviewDialog> {
  int _loadToken = 0;
  _SkillMarketFilePreviewKind _kind = _SkillMarketFilePreviewKind.loading;
  String _content = '';
  String? _errorMessage;

  String get _fileName {
    final normalized = widget.path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash < 0 || slash >= normalized.length - 1) return normalized;
    return normalized.substring(slash + 1);
  }

  @override
  void initState() {
    super.initState();
    if (openHandFileNameLooksLikeBinary(_fileName)) {
      _kind = _SkillMarketFilePreviewKind.binary;
      return;
    }
    if (widget.size > _kSkillMarketFilePreviewMaxBytes) {
      _kind = _SkillMarketFilePreviewKind.tooLarge;
      return;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _loadToken += 1;
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    if (_kind != _SkillMarketFilePreviewKind.loading || _errorMessage != null) {
      setState(() {
        _kind = _SkillMarketFilePreviewKind.loading;
        _errorMessage = null;
      });
    }
    try {
      final content = await widget.client.fetchSkillFileContent(
        slug: widget.slug,
        path: widget.path,
        version: widget.version,
      );
      if (!mounted || token != _loadToken) return;
      if (content.contains('\u0000')) {
        setState(() => _kind = _SkillMarketFilePreviewKind.binary);
        return;
      }
      setState(() {
        _kind = _SkillMarketFilePreviewKind.ready;
        _content = content;
      });
    } catch (error, stack) {
      if (isHttpRequestAborted(error)) return;
      if (error is StateError && error.message.contains('已关闭')) return;
      silentLog(
        'skill_market_dialog',
        '读取技能文件 ${widget.slug}/${widget.path}',
        error,
        stack,
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _kind = _SkillMarketFilePreviewKind.error;
        _errorMessage = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '无法加载该文件内容，请稍后重试。',
            zhHant: '無法載入該檔案內容，請稍後重試。',
            en: 'Unable to load this file. Try again later.',
            fr: 'Impossible de charger ce fichier. Réessayez plus tard.',
            de: 'Datei konnte nicht geladen werden. Später erneut versuchen.',
            ja: 'このファイルを読み込めません。しばらくして再試行してください。',
          ),
          detailResolver: (value) {
            if (value is SkillMarketException) return value.message;
            return null;
          },
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandEditorDialogScaffold(
      title: _fileName,
      subtitle: widget.version.isEmpty
          ? widget.path
          : '${widget.path} · ${widget.version}',
      icon: openHandFileNameIcon(_fileName),
      iconColor: colorScheme.primary,
      maxWidth: kOpenHandDialogWidthExtraWide,
      body: OpenHandContentStateSwitcher(
        stateKey: _kind.name,
        child: _buildBody(context),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (_kind) {
      case _SkillMarketFilePreviewKind.loading:
        return SizedBox(
          height: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OpenHandBusyStatusIcon(
                busy: true,
                icon: Icons.description_rounded,
                size: 28,
                color: colorScheme.primary,
              ),
              kOpenHandGap14,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '正在加载文件内容…',
                  zhHant: '正在載入檔案內容…',
                  en: 'Loading file content…',
                  fr: 'Chargement du fichier…',
                  de: 'Dateiinhalt wird geladen…',
                  ja: 'ファイル内容を読み込み中…',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      case _SkillMarketFilePreviewKind.binary:
        return OpenHandInlineEmptyState(
          icon: Icons.perm_media_outlined,
          message: openHandLocalizedText(
            context,
            zh: '该文件不是文本内容，无法在编辑器中预览。',
            zhHant: '此檔案不是文字內容，無法在編輯器中預覽。',
            en: 'This file is not text and cannot be previewed in the editor.',
            fr: 'Ce fichier n’est pas du texte et ne peut pas être prévisualisé.',
            de: 'Diese Datei ist kein Text und kann im Editor nicht angezeigt werden.',
            ja: 'このファイルはテキストではないため、エディタでプレビューできません。',
          ),
        );
      case _SkillMarketFilePreviewKind.tooLarge:
        final limitLabel = formatLocalizedByteSizeOf(
          context,
          _kSkillMarketFilePreviewMaxBytes,
        );
        return OpenHandInlineEmptyState(
          icon: Icons.sd_storage_outlined,
          message: openHandLocalizedText(
            context,
            zh: '文件过大，无法在编辑器中预览（上限 $limitLabel）。',
            zhHant: '檔案過大，無法在編輯器中預覽（上限 $limitLabel）。',
            en: 'This file is too large to preview (limit $limitLabel).',
            fr: 'Fichier trop volumineux pour l’aperçu (limite $limitLabel).',
            de: 'Datei ist zu groß für die Vorschau (Limit $limitLabel).',
            ja: 'ファイルが大きすぎてプレビューできません（上限 $limitLabel）。',
          ),
        );
      case _SkillMarketFilePreviewKind.error:
        return Column(
          children: [
            OpenHandInlineEmptyState(
              icon: Icons.error_outline_rounded,
              message:
                  _errorMessage ??
                  openHandLocalizedText(
                    context,
                    zh: '无法加载该文件内容，请稍后重试。',
                    zhHant: '無法載入該檔案內容，請稍後重試。',
                    en: 'Unable to load this file. Try again later.',
                    fr: 'Impossible de charger ce fichier. Réessayez plus tard.',
                    de: 'Datei konnte nicht geladen werden. Später erneut versuchen.',
                    ja: 'このファイルを読み込めません。しばらくして再試行してください。',
                  ),
            ),
            kOpenHandGap12,
            OpenHandCompactActionChip(
              icon: Icons.refresh_rounded,
              label: openHandRetryLabel(context),
              onPressed: _load,
            ),
          ],
        );
      case _SkillMarketFilePreviewKind.ready:
        return OpenHandCodeEditor(
          value: _content,
          language:
              openHandEditorLanguageFromFileName(_fileName) ?? 'plaintext',
          fileName: _fileName,
          icon: openHandFileNameIcon(_fileName),
          height: _kSkillMarketFilePreviewEditorHeight,
          borderRadius: kOpenHandBorderRadius16,
          readOnly: true,
          onChanged: (_) {},
        );
    }
  }
}

class _SkillMarketAvatar extends StatelessWidget {
  const _SkillMarketAvatar({
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = _SkillMarketAvatarFallback(name: name);
    final imageUrl = this.imageUrl;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;
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

class _SkillMarketAvatarFallback extends StatelessWidget {
  const _SkillMarketAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? 'S'
        : trimmed.characters.first.toUpperCase();
    return Text(
      initial,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: colorScheme.onPrimaryContainer),
    );
  }
}

class _MarketStateMessage extends StatelessWidget {
  const _MarketStateMessage({
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

String _localizedSummary(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final zhText = zh.trim();
  final enText = en.trim();
  if (enText.isEmpty) return zhText;
  if (zhText.isEmpty) return enText;
  return openHandLocalizedText(context, zh: zhText, zhHant: zhText, en: enText);
}

Set<String> _installedSkillKeys(SkillsController controller) {
  final keys = <String>{};
  for (final skill in controller.skills) {
    keys.add(normalizeAsciiSlugKey(skill.name));
    keys.add(
      normalizeAsciiSlugKey(OpenHandPaths.basename(skill.directoryPath)),
    );
    keys.add(
      normalizeAsciiSlugKey(
        OpenHandPaths.basename(skill.relativeDirectoryPath),
      ),
    );
  }
  keys.remove('');
  return keys;
}

bool _isMarketSkillInstalled(
  SkillMarketSummary skill,
  Set<String> installedSkillKeys,
) {
  return installedSkillKeys.contains(normalizeAsciiSlugKey(skill.slug)) ||
      installedSkillKeys.contains(normalizeAsciiSlugKey(skill.name));
}

String _formatCount(BuildContext context, int value) {
  final safe = value < 0 ? 0 : value;
  try {
    return NumberFormat.compact(
      locale: Localizations.localeOf(context).toString(),
    ).format(safe);
  } catch (_) {
    return '$safe';
  }
}

String _skillMarketFileTreeItemCount(BuildContext context, int count) {
  final safe = count < 0 ? 0 : count;
  return openHandLocalizedText(
    context,
    zh: '$safe 项',
    zhHant: '$safe 項',
    en: safe == 1 ? '1 item' : '$safe items',
    fr: safe == 1 ? '1 élément' : '$safe éléments',
    de: safe == 1 ? '1 Element' : '$safe Elemente',
    ja: '$safe 件',
  );
}

Color _skillMarketCategoryAccent(ColorScheme colorScheme, String category) {
  return switch (category.trim().toLowerCase()) {
    'office-efficiency' => colorScheme.primary,
    'dev-programming' => OpenHandStatusColors.info,
    'content-creation' => colorScheme.tertiary,
    'data-analysis' => OpenHandStatusColors.caution,
    'design-media' => colorScheme.secondary,
    'ai-agent' => colorScheme.primary,
    'knowledge-management' => OpenHandStatusColors.info,
    'business-ops' => OpenHandStatusColors.warning,
    'education' => colorScheme.tertiary,
    'professional' => colorScheme.secondary,
    'it-ops-security' => OpenHandStatusColors.info,
    'life-service' => OpenHandStatusColors.success,
    'pay-skill' => OpenHandStatusColors.warning,
    _ => colorScheme.primary,
  };
}

String _skillMarketTruncationMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '\n\n---\n内容较长，已截断预览。安装后可在本地 SKILL.md 查看完整内容。',
    zhHant: '\n\n---\n內容較長，已截斷預覽。安裝後可在本機 SKILL.md 查看完整內容。',
    en: '\n\n---\nPreview truncated. Install the skill to inspect the full local SKILL.md.',
    fr: '\n\n---\nAperçu tronqué. Installez la compétence pour consulter le SKILL.md complet.',
    de: '\n\n---\nVorschau gekürzt. Installiere den Skill, um die vollständige lokale SKILL.md zu lesen.',
    ja: '\n\n---\nプレビューを切り詰めました。インストール後、ローカルの SKILL.md で全文を確認できます。',
  );
}

String _skillMarketDiaRetryLabel(BuildContext context) {
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

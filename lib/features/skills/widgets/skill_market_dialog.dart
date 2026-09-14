import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/net/abortable_http_request.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/markdown_ast_sanitizer.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../data/skill_market_client.dart';
import '../model/skill_market.dart';
import '../skills_controller.dart';
import 'skill_markdown_preview.dart';
import 'skill_market_labels.dart';

Future<void> showSkillMarketDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => const _SkillMarketDialog(),
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
const int _kSkillMarketMaxPreviewFiles = 12;
const int _kSkillMarketMaxPreviewSubcategories = 3;

class _SkillMarketDialog extends StatefulWidget {
  const _SkillMarketDialog();

  @override
  State<_SkillMarketDialog> createState() => _SkillMarketDialogState();
}

class _SkillMarketDialogState extends State<_SkillMarketDialog> {
  static const int _maxMarkdownChars = 80000;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 320);

  final TextEditingController _searchController = TextEditingController();
  final OpenHandDebouncer _searchDebounce = OpenHandDebouncer(
    delay: _searchDebounceDuration,
  );
  late final SkillMarketClient _marketClient;

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

  @override
  void initState() {
    super.initState();
    _marketClient = SkillMarketClient();
    unawaited(_runSearch(keepSelection: false));
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _marketClient.close();
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
                              Expanded(child: _buildDetailPane(context)),
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
                            Expanded(child: _buildDetailPane(context)),
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
            borderRadius: BorderRadius.circular(kOpenHandRadius18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.primaryContainer,
                Color.alphaBlend(
                  colorScheme.tertiaryContainer.withValues(alpha: 0.82),
                  colorScheme.primaryContainer,
                ),
              ],
            ),
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
                  zh: '搜索 SkillHub 技能，查看详情后安装到当前全局技能目录。',
                  zhHant: '搜尋 SkillHub 技能，查看詳情後安裝到目前全域技能目錄。',
                  en: 'Search SkillHub skills, inspect details, and install into the current global skills directory.',
                  fr: 'Recherchez des compétences SkillHub, consultez les détails, puis installez-les dans le dossier global actuel.',
                  de: 'Suche SkillHub-Skills, prüfe Details und installiere sie in das aktuelle globale Skill-Verzeichnis.',
                  ja: 'SkillHub のスキルを検索し、詳細を確認して現在のグローバルスキルディレクトリへインストールします。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
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
                child: _searchError != null
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
                        body: openHandLocalizedText(
                          context,
                          zh: '无法连接技能市场，请稍后重试。',
                          zhHant: '無法連線技能市場，請稍後重試。',
                          en: 'The skill market could not be reached. Try again later.',
                          fr: 'Impossible de joindre le marché des compétences. Réessayez plus tard.',
                          de: 'Der Skill-Markt ist nicht erreichbar. Versuche es später erneut.',
                          ja: 'スキルマーケットに接続できません。後でもう一度お試しください。',
                        ),
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
                maxMarkdownChars: _maxMarkdownChars,
                onVersionSelected: _selectSkillVersion,
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
    _marketClient.clearSearchCache();
    unawaited(_runSearch(keepSelection: true));
  }

  Future<void> _runSearch({required bool keepSelection}) async {
    final token = ++_searchToken;
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

  Future<void> _installSelectedSkill() async {
    final skill = _selectedSkill;
    if (skill == null || _isInstalling) {
      return;
    }
    final skillsController = context.read<SkillsController>();
    final previewVersion = _selectedPreviewVersions[skill.slug];
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _SkillMarketInstallConfirmDialog(
          skill: skill,
          storagePath: skillsController.storagePath,
          previewVersion: previewVersion,
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isInstalling = true;
      _installError = null;
    });

    try {
      final archiveBytes = await _marketClient.downloadSkillArchive(skill.slug);
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
    this.previewVersion,
  });

  final SkillMarketSummary skill;
  final String storagePath;
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
                zh: '将从 SkillHub 下载技能压缩包，并解压到当前全局技能目录。',
                zhHant: '將從 SkillHub 下載技能壓縮包，並解壓到目前全域技能目錄。',
                en: 'OpenHand will download the skill archive from SkillHub and extract it into the current global skills directory.',
                fr: 'OpenHand téléchargera l’archive depuis SkillHub et l’extraira dans le dossier global actuel.',
                de: 'OpenHand lädt das Skill-Archiv von SkillHub und entpackt es in das aktuelle globale Skill-Verzeichnis.',
                ja: 'OpenHand は SkillHub からスキルアーカイブをダウンロードし、現在のグローバルスキルディレクトリへ展開します。',
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
    required this.maxMarkdownChars,
    required this.onVersionSelected,
  });

  final SkillMarketSummary summary;
  final SkillMarketBundle bundle;
  final int maxMarkdownChars;
  final ValueChanged<String> onVersionSelected;

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
    final strippedMarkdown = bundle.skillMarkdown == null
        ? ''
        : stripOpenHandMarkdownFrontMatter(bundle.skillMarkdown!).trim();
    final markdown = strippedMarkdown.isEmpty
        ? null
        : _truncateMarkdown(strippedMarkdown, maxMarkdownChars, context);
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
    final previewFiles = files.take(_kSkillMarketMaxPreviewFiles).toList();
    final hiddenFileCount = files.length - previewFiles.length;
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
          if (previewFiles.isNotEmpty) ...[
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
              child: Column(
                children: [
                  for (var i = 0; i < previewFiles.length; i++) ...[
                    if (i > 0) kOpenHandGap8,
                    _SkillMarketFileRow(file: previewFiles[i], accent: accent),
                  ],
                  if (hiddenFileCount > 0) ...[
                    kOpenHandGap10,
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OpenHandFactChip(
                        icon: Icons.more_horiz_rounded,
                        label: skillMarketFilesMoreLabel(
                          context,
                          hiddenFileCount,
                        ),
                        color: colorScheme.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          kOpenHandGap14,
          OpenHandTintedPanel(
            accent: colorScheme.primary,
            icon: Icons.menu_book_rounded,
            title: openHandDetailsLabel(context),
            child: markdown == null || markdown.trim().isEmpty
                ? Text(
                    openHandLocalizedText(
                      context,
                      zh: '未找到技能说明内容。',
                      zhHant: '未找到技能說明內容。',
                      en: 'No skill description was found.',
                      fr: 'Aucune description de compétence trouvée.',
                      de: 'Keine Skill-Beschreibung gefunden.',
                      ja: 'スキル説明が見つかりません。',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : OpenHandSkillMarkdownPreview(
                    data: markdown,
                    backgroundColor: Colors.transparent,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SkillMarketFileRow extends StatelessWidget {
  const _SkillMarketFileRow({required this.file, required this.accent});

  final SkillMarketFileEntry file;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.insert_drive_file_outlined, size: 16, color: accent),
        kOpenHandHGap8,
        Expanded(
          child: Text(
            file.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        kOpenHandHGap8,
        Text(
          formatByteSize(file.size),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(math.min(18, size / 3)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: imageUrl == null || imageUrl.trim().isEmpty
          ? fallback
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              // 按约 3 倍像素比解码，兼顾高分屏清晰度与内存占用。
              cacheWidth: (size * 3).round(),
              cacheHeight: (size * 3).round(),
              errorBuilder: (context, error, stackTrace) => fallback,
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
                  borderRadius: BorderRadius.circular(kOpenHandRadius22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      colorScheme.primaryContainer,
                      Color.alphaBlend(
                        colorScheme.tertiaryContainer.withValues(alpha: 0.78),
                        colorScheme.secondaryContainer,
                      ),
                    ],
                  ),
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
  return openHandLocalizedText(context, zh: zhText, en: enText);
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

String _truncateMarkdown(String markdown, int maxChars, BuildContext context) {
  if (markdown.length <= maxChars) {
    return markdown;
  }
  final suffix = openHandLocalizedText(
    context,
    zh: '\n\n---\n内容较长，已截断预览。安装后可在本地 SKILL.md 查看完整内容。',
    zhHant: '\n\n---\n內容較長，已截斷預覽。安裝後可在本機 SKILL.md 查看完整內容。',
    en: '\n\n---\nPreview truncated. Install the skill to inspect the full local SKILL.md.',
    fr: '\n\n---\nAperçu tronqué. Installez la compétence pour consulter le SKILL.md complet.',
    de: '\n\n---\nVorschau gekürzt. Installiere den Skill, um die vollständige lokale SKILL.md zu lesen.',
    ja: '\n\n---\nプレビューを切り詰めました。インストール後、ローカルの SKILL.md で全文を確認できます。',
  );
  return clipTextByCodeUnits(markdown, maxChars, suffix: suffix);
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

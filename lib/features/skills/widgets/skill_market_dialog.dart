import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../data/skill_market_client.dart';
import '../model/skill_market.dart';
import '../skills_controller.dart';

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
                            kOpenHandHGap18,
                            VerticalDivider(
                              width: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                            kOpenHandHGap18,
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
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(kOpenHandRadius16),
          ),
          child: Icon(
            Icons.storefront_rounded,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        kOpenHandHGap14,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandSkillMarketLabel(context),
                style: theme.textTheme.headlineSmall,
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

    return Column(
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
            if (_searchInput.trim().isNotEmpty)
              Tooltip(
                message: openHandClearSearchLabel(context),
                child: IconButton(
                  onPressed: _isSearching ? null : _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
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
                    separatorBuilder: (context, index) => kOpenHandGap10,
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
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final selectedSkill = _selectedSkill;
    final bundleFuture = _selectedBundleFuture;
    if (selectedSkill == null || bundleFuture == null) {
      return _MarketStateMessage(
        icon: Icons.touch_app_outlined,
        title: openHandLocalizedText(
          context,
          zh: '选择一个技能',
          zhHant: '選擇一個技能',
          en: 'Select a Skill',
          fr: 'Sélectionner une compétence',
          de: 'Skill auswählen',
          ja: 'スキルを選択',
        ),
        body: openHandLocalizedText(
          context,
          zh: '点击左侧候选项后，这里会展示概述、版本、安全报告和 SKILL.md 详情。',
          zhHant: '點擊左側候選項後，這裡會展示概述、版本、安全報告和 SKILL.md 詳情。',
          en: 'Choose a result on the left to view the summary, versions, security reports, and SKILL.md details.',
          fr: 'Choisissez un résultat à gauche pour voir le résumé, les versions, les rapports de sécurité et SKILL.md.',
          de: 'Wähle links ein Ergebnis, um Übersicht, Versionen, Sicherheitsberichte und SKILL.md zu sehen.',
          ja: '左側の候補を選ぶと、概要、バージョン、セキュリティレポート、SKILL.md の詳細を表示します。',
        ),
      );
    }

    return FutureBuilder<SkillMarketBundle>(
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
              en: 'Details Failed',
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
            onAction: () => _selectSkill(selectedSkill, forceReload: true),
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
    final normalizedPreviewVersion = previewVersion?.trim() ?? '';
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthStandard,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkillMarketAvatar(
                  name: skill.displayName,
                  imageUrl: skill.iconUrl,
                  size: 52,
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
                          en: 'Confirm Install',
                          fr: 'Confirmer l’installation',
                          de: 'Installation bestätigen',
                          ja: 'インストール確認',
                        ),
                        style: theme.textTheme.headlineSmall,
                      ),
                      kOpenHandGap6,
                      Text(
                        skill.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            kOpenHandGap18,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.person_outline_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '作者',
                    zhHant: '作者',
                    en: 'Owner',
                    fr: 'Auteur',
                    de: 'Autor',
                    ja: '作者',
                  ),
                  value: skill.ownerName.isEmpty ? '-' : skill.ownerName,
                ),
                if (skill.source.isNotEmpty)
                  _InfoChip(
                    icon: Icons.hub_outlined,
                    label: openHandSourceLabel(context),
                    value: skill.source,
                  ),
                _InfoChip(
                  icon: Icons.folder_open_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '目录',
                    zhHant: '目錄',
                    en: 'Directory',
                    fr: 'Dossier',
                    de: 'Verzeichnis',
                    ja: 'ディレクトリ',
                  ),
                  value: OpenHandPaths.shortenHomePath(storagePath),
                ),
                if (normalizedPreviewVersion.isNotEmpty)
                  _InfoChip(
                    icon: Icons.sell_outlined,
                    label: openHandLocalizedText(
                      context,
                      zh: '预览版本',
                      zhHant: '預覽版本',
                      en: 'Preview',
                      fr: 'Aperçu',
                      de: 'Vorschau',
                      ja: 'プレビュー',
                    ),
                    value: normalizedPreviewVersion,
                  ),
              ],
            ),
            kOpenHandGap18,
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
    final summary = _localizedSummary(
      context,
      zh: skill.descriptionZh,
      en: skill.description,
    );

    return HoverLift(
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.52)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kOpenHandRadius20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kOpenHandRadius20),
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkillMarketAvatar(
                  name: skill.displayName,
                  imageUrl: skill.iconUrl,
                  size: 44,
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skill.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      kOpenHandGap3,
                      Text(
                        skill.ownerName.isEmpty
                            ? skill.slug
                            : '${skill.ownerName} / ${skill.slug}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        kOpenHandGap8,
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      kOpenHandGap10,
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OpenHandInlineIconLabel(
                            icon: Icons.download_rounded,
                            label: _formatCount(skill.downloads),
                            iconSize: 16,
                          ),
                          OpenHandInlineIconLabel(
                            icon: Icons.star_rounded,
                            label: _formatCount(skill.stars),
                            iconSize: 16,
                          ),
                          if (installed)
                            _TinyTextChip(
                              label: openHandInstalledLabel(context),
                            ),
                          if (skill.category.isNotEmpty)
                            _TinyTextChip(label: skill.category),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
    final displayName = skill.displayName.isNotEmpty
        ? skill.displayName
        : summary.displayName;
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
    final markdown = bundle.skillMarkdown == null
        ? null
        : _truncateMarkdown(bundle.skillMarkdown!, maxMarkdownChars, context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(kOpenHandRadius22),
      child: ColoredBox(
        color: colorScheme.surfaceContainerLow,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkillMarketAvatar(
                  name: displayName,
                  imageUrl: skill.iconUrl ?? summary.iconUrl,
                  size: 58,
                ),
                kOpenHandHGap14,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.headlineSmall),
                      kOpenHandGap6,
                      Text(
                        detail.owner.handle.isEmpty
                            ? skill.slug
                            : '${detail.owner.handle} / ${skill.slug}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                kOpenHandHGap12,
                _TinyTextChip(
                  label: bundle.resolvedVersion.isEmpty
                      ? summary.version
                      : bundle.resolvedVersion,
                ),
              ],
            ),
            if (overview.isNotEmpty) ...[
              kOpenHandGap18,
              _SectionTitle(
                text: openHandLocalizedText(
                  context,
                  zh: '概述',
                  zhHant: '概述',
                  en: 'Overview',
                  fr: 'Vue d’ensemble',
                  de: 'Übersicht',
                  ja: '概要',
                ),
              ),
              kOpenHandGap8,
              Text(
                overview,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            kOpenHandGap18,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.download_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '下载',
                    zhHant: '下載',
                    en: 'Downloads',
                    fr: 'Téléchargements',
                    de: 'Downloads',
                    ja: 'ダウンロード',
                  ),
                  value: _formatCount(
                    skill.stats.downloads == 0
                        ? summary.downloads
                        : skill.stats.downloads,
                  ),
                ),
                _InfoChip(
                  icon: Icons.install_desktop_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '安装',
                    zhHant: '安裝',
                    en: 'Installs',
                    fr: 'Installations',
                    de: 'Installationen',
                    ja: 'インストール',
                  ),
                  value: _formatCount(
                    skill.stats.installs == 0
                        ? summary.installs
                        : skill.stats.installs,
                  ),
                ),
                _InfoChip(
                  icon: Icons.star_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '收藏',
                    zhHant: '收藏',
                    en: 'Stars',
                    fr: 'Étoiles',
                    de: 'Sterne',
                    ja: 'スター',
                  ),
                  value: _formatCount(
                    skill.stats.stars == 0 ? summary.stars : skill.stats.stars,
                  ),
                ),
                if (skill.category.isNotEmpty)
                  _InfoChip(
                    icon: Icons.category_outlined,
                    label: openHandLocalizedText(
                      context,
                      zh: '分类',
                      zhHant: '分類',
                      en: 'Category',
                      fr: 'Catégorie',
                      de: 'Kategorie',
                      ja: 'カテゴリ',
                    ),
                    value: skill.category,
                  ),
                if (skill.source.isNotEmpty)
                  _InfoChip(
                    icon: Icons.hub_outlined,
                    label: openHandSourceLabel(context),
                    value: skill.source,
                  ),
                _InfoChip(
                  icon: Icons.key_outlined,
                  label: openHandLocalizedText(
                    context,
                    zh: 'API Key',
                    en: 'API Key',
                  ),
                  value: skill.requiresApiKey
                      ? openHandLocalizedText(
                          context,
                          zh: '需要',
                          zhHant: '需要',
                          en: 'Required',
                          fr: 'Requise',
                          de: 'Erforderlich',
                          ja: '必要',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '无需',
                          zhHant: '不需要',
                          en: 'Not required',
                          fr: 'Non requise',
                          de: 'Nicht erforderlich',
                          ja: '不要',
                        ),
                ),
              ],
            ),
            if (detail.securityReports.isNotEmpty) ...[
              kOpenHandGap20,
              _SectionTitle(
                text: openHandLocalizedText(
                  context,
                  zh: '安全报告',
                  zhHant: '安全報告',
                  en: 'Security Reports',
                  fr: 'Rapports de sécurité',
                  de: 'Sicherheitsberichte',
                  ja: 'セキュリティレポート',
                ),
              ),
              kOpenHandGap10,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: detail.securityReports.entries
                    .map(
                      (entry) =>
                          _SecurityChip(name: entry.key, report: entry.value),
                    )
                    .toList(growable: false),
              ),
            ],
            if (bundle.versions.isNotEmpty) ...[
              kOpenHandGap20,
              _SectionTitle(
                text: openHandLocalizedText(
                  context,
                  zh: '预览版本',
                  zhHant: '預覽版本',
                  en: 'Preview Version',
                  fr: 'Version d’aperçu',
                  de: 'Vorschauversion',
                  ja: 'プレビューバージョン',
                ),
              ),
              kOpenHandGap10,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: bundle.versions
                    .where((version) => version.version.isNotEmpty)
                    .take(12)
                    .map((version) {
                      final selected =
                          version.version == bundle.resolvedVersion;
                      final tooltip = version.changelog.isEmpty
                          ? version.version
                          : version.changelog;
                      return Tooltip(
                        message: tooltip,
                        child: ChoiceChip(
                          label: Text(version.version),
                          selected: selected,
                          onSelected: selected
                              ? null
                              : (_) => onVersionSelected(version.version),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
            if (bundle.files != null && bundle.files!.files.isNotEmpty) ...[
              kOpenHandGap20,
              _SectionTitle(
                text: openHandLocalizedText(
                  context,
                  zh: '包含文件',
                  zhHant: '包含檔案',
                  en: 'Files',
                  fr: 'Fichiers',
                  de: 'Dateien',
                  ja: 'ファイル',
                ),
              ),
              kOpenHandGap10,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: bundle.files!.files
                    .take(12)
                    .map((file) {
                      return _TinyTextChip(
                        label: '${file.path} · ${formatByteSize(file.size)}',
                      );
                    })
                    .toList(growable: false),
              ),
            ],
            kOpenHandGap20,
            _SectionTitle(text: openHandDetailsLabel(context)),
            kOpenHandGap10,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(kOpenHandRadius18),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: markdown == null || markdown.trim().isEmpty
                  ? Text(
                      openHandLocalizedText(
                        context,
                        zh: '未找到 SKILL.md 内容。',
                        zhHant: '未找到 SKILL.md 內容。',
                        en: 'No SKILL.md content was found.',
                        fr: 'Aucun contenu SKILL.md trouvé.',
                        de: 'Kein SKILL.md-Inhalt gefunden.',
                        ja: 'SKILL.md の内容が見つかりません。',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : MarkdownBody(data: markdown, selectable: true),
            ),
          ],
        ),
      ),
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
              // Avatar rendered at `size` logical px; decode at ~3x DPR
              // to keep retina sharpness while skipping full resolution.
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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colorScheme.primary),
            kOpenHandGap14,
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            kOpenHandGap8,
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          kOpenHandHGap8,
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SecurityChip extends StatelessWidget {
  const _SecurityChip({required this.name, required this.report});

  final String name;
  final SkillMarketSecurityReport report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final benign = report.status.toLowerCase() == 'benign';
    return Chip(
      avatar: Icon(
        benign ? Icons.verified_user_outlined : Icons.warning_amber_rounded,
        size: 18,
        color: benign ? colorScheme.primary : colorScheme.error,
      ),
      label: Text(
        '${name.toUpperCase()}: ${report.statusText.isEmpty ? report.status : report.statusText}',
      ),
      side: BorderSide(
        color: benign
            ? colorScheme.primary.withValues(alpha: 0.42)
            : colorScheme.error.withValues(alpha: 0.42),
      ),
    );
  }
}

class _TinyTextChip extends StatelessWidget {
  const _TinyTextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
    keys.add(_normalizeSkillKey(skill.name));
    keys.add(_normalizeSkillKey(OpenHandPaths.basename(skill.directoryPath)));
    keys.add(
      _normalizeSkillKey(OpenHandPaths.basename(skill.relativeDirectoryPath)),
    );
  }
  keys.remove('');
  return keys;
}

bool _isMarketSkillInstalled(
  SkillMarketSummary skill,
  Set<String> installedSkillKeys,
) {
  return installedSkillKeys.contains(_normalizeSkillKey(skill.slug)) ||
      installedSkillKeys.contains(_normalizeSkillKey(skill.name));
}

String _normalizeSkillKey(String value) {
  return normalizeAsciiSlugKey(value);
}

String _formatCount(int value) {
  if (value >= 1000000) {
    final compact = value / 1000000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final compact = value / 1000;
    return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}K';
  }
  return '$value';
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

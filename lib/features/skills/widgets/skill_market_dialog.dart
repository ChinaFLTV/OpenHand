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
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../data/skill_market_client.dart';
import '../model/skill_market.dart';
import '../skills_controller.dart';

Future<void> showSkillMarketDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => const _SkillMarketDialog(),
  );
}

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
        maxWidth: 1220,
        maxHeight: 840,
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
                  const SizedBox(height: 18),
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
                              const SizedBox(height: 16),
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
                            const SizedBox(width: 18),
                            VerticalDivider(
                              width: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                            const SizedBox(width: 18),
                            Expanded(child: _buildDetailPane(context)),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
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
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.storefront_rounded,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(context, zh: '技能市场', en: 'Skill Market'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  context,
                  zh: '搜索 SkillHub 技能，查看详情后安装到当前全局技能目录。',
                  en: 'Search SkillHub skills, inspect details, and install into the current global skills directory.',
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final installedSkillKeys = _installedSkillKeys(
      context.watch<SkillsController>(),
    );
    final result = _searchResult;
    final skills = result?.skills ?? const <SkillMarketSummary>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchBar(
          controller: _searchController,
          hintText: _t(context, zh: '搜索市场技能', en: 'Search market skills'),
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (_searchInput.trim().isNotEmpty)
              Tooltip(
                message: _t(context, zh: '清空搜索', en: 'Clear search'),
                child: IconButton(
                  onPressed: _isSearching ? null : _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            Tooltip(
              message: _t(context, zh: '刷新搜索', en: 'Refresh search'),
              child: IconButton(
                onPressed: _isSearching ? null : _refreshCurrentSearch,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ],
          onChanged: _handleSearchChanged,
          onSubmitted: _handleSearchSubmitted,
        ),
        const SizedBox(height: 12),
        if (_isSearching && result != null)
          const LinearProgressIndicator(minHeight: 2),
        if (_isSearching && result != null) const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: _searchError != null
                ? _MarketStateMessage(
                    key: const ValueKey<String>('market-search-error'),
                    icon: Icons.cloud_off_outlined,
                    title: _t(context, zh: '加载失败', en: 'Unable to Load'),
                    body: _t(
                      context,
                      zh: '无法连接技能市场，请稍后重试。',
                      en: 'The skill market could not be reached. Try again later.',
                    ),
                    actionLabel: _t(context, zh: '重试', en: 'Retry'),
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
                    title: _t(context, zh: '没有找到结果', en: 'No Results'),
                    body: _t(
                      context,
                      zh: '换个关键词再试试，或清空搜索查看热门技能。',
                      en: 'Try another keyword, or clear the search to browse popular skills.',
                    ),
                  )
                : ListView.separated(
                    key: ValueKey<String>(
                      'market-results-${result?.page}-$_keyword',
                    ),
                    itemCount: skills.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  result == null
                      ? _t(context, zh: '准备加载', en: 'Ready')
                      : _t(
                          context,
                          zh: '共 ${_formatCount(result.total)} 个，第 ${result.page}/${result.totalPages} 页',
                          en: '${_formatCount(result.total)} total, page ${result.page}/${result.totalPages}',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: _t(context, zh: '第一页', en: 'First page'),
                onPressed: result == null || _isSearching || _page <= 1
                    ? null
                    : () => _goToPage(1),
                icon: const Icon(Icons.first_page_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _t(context, zh: '上一页', en: 'Previous page'),
                onPressed: result == null || _isSearching || _page <= 1
                    ? null
                    : () => _goToPage(_page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _t(context, zh: '下一页', en: 'Next page'),
                onPressed:
                    result == null || _isSearching || _page >= result.totalPages
                    ? null
                    : () => _goToPage(_page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _t(context, zh: '最后一页', en: 'Last page'),
                onPressed:
                    result == null || _isSearching || _page >= result.totalPages
                    ? null
                    : () => _goToPage(result.totalPages),
                icon: const Icon(Icons.last_page_rounded),
              ),
            ],
          ),
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
        title: _t(context, zh: '选择一个技能', en: 'Select a Skill'),
        body: _t(
          context,
          zh: '点击左侧候选项后，这里会展示概述、版本、安全报告和 SKILL.md 详情。',
          en: 'Choose a result on the left to view the summary, versions, security reports, and SKILL.md details.',
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
            title: _t(context, zh: '详情加载失败', en: 'Details Failed'),
            body: _t(
              context,
              zh: '无法加载该技能详情，请重试。',
              en: 'Unable to load this skill detail. Try again.',
            ),
            actionLabel: _t(context, zh: '重试', en: 'Retry'),
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
                _t(
                  context,
                  zh: '安装目录：${OpenHandPaths.shortenHomePath(storagePath)}',
                  en: 'Install path: ${OpenHandPaths.shortenHomePath(storagePath)}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_installError != null) ...[
                const SizedBox(height: 4),
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
        const SizedBox(width: 16),
        OpenHandDialogActionButton.secondary(
          onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
        const SizedBox(width: 12),
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
              ? _t(context, zh: '安装中', en: 'Installing')
              : selectedSkillInstalled
              ? _t(context, zh: '已安装', en: 'Installed')
              : _t(context, zh: '安装', en: 'Install'),
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
      silentLog('skill_market_dialog', 'search skills', error, stackTrace);
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() {
        _isSearching = false;
        _searchError = '$error';
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
      _showMarketSnackBar(
        context,
        '${_t(context, zh: '已安装技能', en: 'Skill installed')}: ${installedSkill.name}',
        kind: _MarketSnackKind.success,
      );
      _installSuccessSignal.value++;
    } catch (error, stackTrace) {
      silentLog(
        'skill_market_dialog',
        'install ${skill.slug}',
        error,
        stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isInstalling = false;
        _installError = _t(
          context,
          zh: '安装失败，请检查网络、磁盘权限或技能压缩包内容。',
          en: 'Install failed. Check the network, disk permission, or archive contents.',
        );
      });
      _installErrorSignal.value++;
    }
  }

  void _showMarketSnackBar(
    BuildContext context,
    String message, {
    _MarketSnackKind kind = _MarketSnackKind.info,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      switch (kind) {
        case _MarketSnackKind.success:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.success(context, message),
          );
        case _MarketSnackKind.error:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.error(context, message),
          );
        case _MarketSnackKind.info:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.info(context, message),
          );
      }
    });
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
      maxWidth: 620,
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t(context, zh: '确认安装技能', en: 'Confirm Install'),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
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
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.person_outline_rounded,
                  label: _t(context, zh: '作者', en: 'Owner'),
                  value: skill.ownerName.isEmpty ? '-' : skill.ownerName,
                ),
                if (skill.source.isNotEmpty)
                  _InfoChip(
                    icon: Icons.hub_outlined,
                    label: _t(context, zh: '来源', en: 'Source'),
                    value: skill.source,
                  ),
                _InfoChip(
                  icon: Icons.folder_open_rounded,
                  label: _t(context, zh: '目录', en: 'Directory'),
                  value: OpenHandPaths.shortenHomePath(storagePath),
                ),
                if (normalizedPreviewVersion.isNotEmpty)
                  _InfoChip(
                    icon: Icons.sell_outlined,
                    label: _t(context, zh: '预览版本', en: 'Preview'),
                    value: normalizedPreviewVersion,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _t(
                context,
                zh: '将从 SkillHub 下载技能压缩包，并解压到当前全局技能目录。',
                en: 'OpenHand will download the skill archive from SkillHub and extract it into the current global skills directory.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(context).pop(false),
                  label: l10n.commonCancel,
                ),
                const SizedBox(width: 12),
                OpenHandDialogActionButton.primary(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icons.download_rounded,
                  label: _t(context, zh: '确认安装', en: 'Install'),
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
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
                const SizedBox(width: 12),
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
                      const SizedBox(height: 3),
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
                        const SizedBox(height: 8),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _TinyMetric(
                            icon: Icons.download_rounded,
                            value: _formatCount(skill.downloads),
                          ),
                          _TinyMetric(
                            icon: Icons.star_rounded,
                            value: _formatCount(skill.stars),
                          ),
                          if (installed)
                            _TinyTextChip(
                              label: _t(context, zh: '已安装', en: 'Installed'),
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
      borderRadius: BorderRadius.circular(22),
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
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
                const SizedBox(width: 12),
                _TinyTextChip(
                  label: bundle.resolvedVersion.isEmpty
                      ? summary.version
                      : bundle.resolvedVersion,
                ),
              ],
            ),
            if (overview.isNotEmpty) ...[
              const SizedBox(height: 18),
              _SectionTitle(
                text: _t(context, zh: '概述', en: 'Overview'),
              ),
              const SizedBox(height: 8),
              Text(
                overview,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.download_rounded,
                  label: _t(context, zh: '下载', en: 'Downloads'),
                  value: _formatCount(
                    skill.stats.downloads == 0
                        ? summary.downloads
                        : skill.stats.downloads,
                  ),
                ),
                _InfoChip(
                  icon: Icons.install_desktop_rounded,
                  label: _t(context, zh: '安装', en: 'Installs'),
                  value: _formatCount(
                    skill.stats.installs == 0
                        ? summary.installs
                        : skill.stats.installs,
                  ),
                ),
                _InfoChip(
                  icon: Icons.star_rounded,
                  label: _t(context, zh: '收藏', en: 'Stars'),
                  value: _formatCount(
                    skill.stats.stars == 0 ? summary.stars : skill.stats.stars,
                  ),
                ),
                if (skill.category.isNotEmpty)
                  _InfoChip(
                    icon: Icons.category_outlined,
                    label: _t(context, zh: '分类', en: 'Category'),
                    value: skill.category,
                  ),
                if (skill.source.isNotEmpty)
                  _InfoChip(
                    icon: Icons.hub_outlined,
                    label: _t(context, zh: '来源', en: 'Source'),
                    value: skill.source,
                  ),
                _InfoChip(
                  icon: Icons.key_outlined,
                  label: _t(context, zh: 'API Key', en: 'API Key'),
                  value: skill.requiresApiKey
                      ? _t(context, zh: '需要', en: 'Required')
                      : _t(context, zh: '无需', en: 'Not required'),
                ),
              ],
            ),
            if (detail.securityReports.isNotEmpty) ...[
              const SizedBox(height: 20),
              _SectionTitle(
                text: _t(context, zh: '安全报告', en: 'Security Reports'),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 20),
              _SectionTitle(
                text: _t(context, zh: '预览版本', en: 'Preview Version'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: bundle.versions
                    .where((version) => version.version.trim().isNotEmpty)
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
              const SizedBox(height: 20),
              _SectionTitle(
                text: _t(context, zh: '包含文件', en: 'Files'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: bundle.files!.files
                    .take(12)
                    .map((file) {
                      return _TinyTextChip(
                        label: '${file.path} · ${_formatBytes(file.size)}',
                      );
                    })
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 20),
            _SectionTitle(
              text: _t(context, zh: '详情', en: 'Details'),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: markdown == null || markdown.trim().isEmpty
                  ? Text(
                      _t(
                        context,
                        zh: '未找到 SKILL.md 内容。',
                        en: 'No SKILL.md content was found.',
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
        : trimmed.substring(0, 1).toUpperCase();
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
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
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

class _TinyMetric extends StatelessWidget {
  const _TinyMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
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
        borderRadius: BorderRadius.circular(999),
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

String _t(BuildContext context, {required String zh, required String en}) {
  return openHandLocalizedText(context, zh: zh, en: en);
}

String _localizedSummary(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  if (openHandIsChineseLocale(context) && zh.trim().isNotEmpty) {
    return zh.trim();
  }
  return en.trim().isNotEmpty ? en.trim() : zh.trim();
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
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
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

String _formatBytes(int bytes) => formatByteSize(bytes);

String _truncateMarkdown(String markdown, int maxChars, BuildContext context) {
  if (markdown.length <= maxChars) {
    return markdown;
  }
  final suffix = _t(
    context,
    zh: '\n\n---\n内容较长，已截断预览。安装后可在本地 SKILL.md 查看完整内容。',
    en: '\n\n---\nPreview truncated. Install the skill to inspect the full local SKILL.md.',
  );
  return '${markdown.substring(0, maxChars)}$suffix';
}

enum _MarketSnackKind { info, success, error }

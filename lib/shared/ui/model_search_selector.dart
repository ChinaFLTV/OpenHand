import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../l10n/app_localizations.dart';
import '../util/text_normalization.dart';
import 'animated_dialog.dart';
import 'oh_pill.dart';
import 'openhand_inline_empty_state.dart';
import 'openhand_safe_scrollbar.dart';

const double _kModelSearchDialogRadius = 16;
const double _kModelSearchScrollbarThickness = 6;
const Radius _kModelSearchScrollbarRadius = kOpenHandPillRadius;

class _ModelEntry {
  const _ModelEntry({
    required this.configId,
    required this.modelId,
    required this.providerLabel,
    required this.protocolLabel,
  });

  final String configId;
  final String modelId;
  final String providerLabel;
  final String protocolLabel;

  String get searchableText =>
      '$modelId $providerLabel $protocolLabel'.toLowerCase();

  (String, String) get selectionKey => (configId, modelId);
}

/// 显示按服务商分组并支持实时筛选的模型选择弹窗。
Future<(String, String)?> showModelSearchSelector({
  required BuildContext context,
  required List<AiModelConfig> models,
  String? selectedConfigId,
  String? selectedModelId,
  List<RecentModelSelection> recentSelections = const <RecentModelSelection>[],
  bool Function(AiModelConfig config, String modelId)? modelFilter,
}) async {
  final entries = <_ModelEntry>[];
  final entriesBySelection = <(String, String), _ModelEntry>{};
  for (final config in models) {
    final configId = config.id.trim();
    if (configId.isEmpty) continue;
    final providerLabel = config.providerLabel.trim().isEmpty
        ? configId
        : config.providerLabel.trim();
    final protocolLabel = config.protocolType.storageValue;
    final allIds = config.allModelIds;
    if (allIds.isEmpty) {
      continue;
    }
    for (final modelId in allIds) {
      final normalizedModelId = modelId.trim();
      if (normalizedModelId.isEmpty) continue;
      if (modelFilter != null && !modelFilter(config, normalizedModelId)) {
        continue;
      }
      final entry = _ModelEntry(
        configId: configId,
        modelId: normalizedModelId,
        providerLabel: providerLabel,
        protocolLabel: protocolLabel,
      );
      if (entriesBySelection.containsKey(entry.selectionKey)) continue;
      entriesBySelection[entry.selectionKey] = entry;
      entries.add(entry);
    }
  }

  // 仅保留当前配置仍可用的最近选择。
  final recentEntries = <_ModelEntry>[];
  final seenRecentSelections = <(String, String)>{};
  for (final recent in recentSelections) {
    final selectionKey = (recent.configId.trim(), recent.modelId.trim());
    final entry = entriesBySelection[selectionKey];
    if (entry != null && seenRecentSelections.add(selectionKey)) {
      recentEntries.add(entry);
    }
  }

  return showAnimatedDialog<(String, String)>(
    context: context,
    builder: (_) => _ModelSearchDialog(
      entries: entries,
      recentEntries: recentEntries,
      selectedConfigId: selectedConfigId,
      selectedModelId: selectedModelId,
    ),
  );
}

class _ModelSearchDialog extends StatefulWidget {
  const _ModelSearchDialog({
    required this.entries,
    required this.recentEntries,
    this.selectedConfigId,
    this.selectedModelId,
  });

  final List<_ModelEntry> entries;
  final List<_ModelEntry> recentEntries;
  final String? selectedConfigId;
  final String? selectedModelId;

  @override
  State<_ModelSearchDialog> createState() => _ModelSearchDialogState();
}

class _ModelSearchDialogState extends State<_ModelSearchDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  List<_ModelEntry> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.entries;
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.entries;
      } else {
        final terms = query.split(kInlineWhitespacePattern);
        _filtered = widget.entries.where((e) {
          final text = e.searchableText;
          return terms.every((t) => text.contains(t));
        }).toList();
      }
    });
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final grouped = <String, List<_ModelEntry>>{};
    for (final entry in _filtered) {
      final key = '${entry.providerLabel}  (${entry.protocolLabel})';
      (grouped[key] ??= []).add(entry);
    }
    final isSearching = _searchController.text.trim().isNotEmpty;
    // 「最近使用」按 _filtered 过滤：先建集合再查，避免每条 recent 都线性扫一遍
    // _filtered——模型目录动辄数百条时那是 O(n·m)。
    final filteredKeys = <String>{
      for (final item in _filtered) '${item.configId}\u0000${item.modelId}',
    };
    final recentFiltered = isSearching
        ? const <_ModelEntry>[]
        : widget.recentEntries
              .where(
                (entry) => filteredKeys.contains(
                  '${entry.configId}\u0000${entry.modelId}',
                ),
              )
              .toList(growable: false);
    final hasAnyModels = widget.entries.isNotEmpty;
    // 分组结构拍平成一维行清单，交给 ListView.builder 按需构建：此前是
    // ListView(children: [...])，一次性把全部候选建成 widget，多 provider
    // 场景下每敲一个字符就要重建几百个条目。
    final rows = <_ModelPickerRow>[
      if (recentFiltered.isNotEmpty) ...[
        _ModelPickerRow.header(l10n.modelSearchRecent),
        for (final entry in recentFiltered)
          _ModelPickerRow.entry(entry, showProviderSubtitle: true),
        const _ModelPickerRow.gap(),
      ],
      for (final group in grouped.entries) ...[
        _ModelPickerRow.header(group.key),
        for (final entry in group.value) _ModelPickerRow.entry(entry),
      ],
    ];

    return buildOpenHandDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kModelSearchDialogRadius),
      ),
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: l10n.modelSearchHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _searchController.clear(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      )
                    : null,
              ),
              style: theme.textTheme.bodyMedium,
              onSubmitted: (_) {
                if (_filtered.isNotEmpty) {
                  final first = _filtered.first;
                  Navigator.of(context).pop((first.configId, first.modelId));
                }
              },
            ),
          ),
          if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.modelSearchResultCount(
                    _filtered.length,
                    widget.entries.length,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          kOpenHandGap4,
          Flexible(
            child: !hasAnyModels
                ? OpenHandInlineEmptyState(
                    message: l10n.modelSearchNoAvailableModels,
                  )
                : _filtered.isEmpty
                ? OpenHandInlineEmptyState(
                    message: l10n.modelSearchNoMatchingModels,
                  )
                : OpenHandSafeScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: _kModelSearchScrollbarThickness,
                    radius: _kModelSearchScrollbarRadius,
                    interactive: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.vertical,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _scrollController,
                        primary: false,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final entry = row.entry;
                          if (entry == null) {
                            final label = row.headerLabel;
                            if (label == null) {
                              return kOpenHandGap4;
                            }
                            return _ModelSectionHeader(label: label);
                          }
                          return _ModelTile(
                            entry: entry,
                            isActive:
                                entry.configId == widget.selectedConfigId &&
                                entry.modelId == widget.selectedModelId,
                            showProviderSubtitle: row.showProviderSubtitle,
                            onTap: () => Navigator.of(
                              context,
                            ).pop((entry.configId, entry.modelId)),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 模型选择列表拍平后的一行：分组标题、模型条目或分隔空白。
class _ModelPickerRow {
  const _ModelPickerRow.header(this.headerLabel)
    : entry = null,
      showProviderSubtitle = false;

  const _ModelPickerRow.entry(this.entry, {this.showProviderSubtitle = false})
    : headerLabel = null;

  const _ModelPickerRow.gap()
    : headerLabel = null,
      entry = null,
      showProviderSubtitle = false;

  final String? headerLabel;
  final _ModelEntry? entry;
  final bool showProviderSubtitle;
}

class _ModelSectionHeader extends StatelessWidget {
  const _ModelSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.entry,
    required this.isActive,
    required this.onTap,
    this.showProviderSubtitle = false,
  });

  final _ModelEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  /// 「最近使用」分组下显示 provider+protocol 副标题，
  /// 避免不同服务商的同名模型在视觉上无法区分。
  final bool showProviderSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = entry.protocolLabel.isEmpty
        ? entry.providerLabel
        : '${entry.providerLabel}  (${entry.protocolLabel})';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: isActive ? colorScheme.primary : colorScheme.outline,
            ),
            kOpenHandHGap12,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.modelId,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isActive ? colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showProviderSubtitle)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

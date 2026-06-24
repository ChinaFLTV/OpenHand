import 'package:flutter/material.dart';

import '../../app/model/app_settings_snapshot.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'openhand_safe_scrollbar.dart';

const double _kModelSearchDialogMaxWidth = 420;
const double _kModelSearchDialogMaxHeight = 520;
const double _kModelSearchDialogRadius = 16;
const double _kModelSearchScrollbarThickness = 6;
const Radius _kModelSearchScrollbarRadius = Radius.circular(999);

/// Entry representing a single selectable model inside a provider group.
class ModelEntry {
  const ModelEntry({
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

/// A searchable model selection dialog.
///
/// Groups models by provider, with real-time filtering. Call
/// [showModelSearchSelector] to display it.
Future<(String, String)?> showModelSearchSelector({
  required BuildContext context,
  required List<AiModelConfig> models,
  String? selectedConfigId,
  String? selectedModelId,
  List<RecentModelSelection> recentSelections = const <RecentModelSelection>[],
  bool Function(AiModelConfig config, String modelId)? modelFilter,
}) async {
  // Build flat list of entries grouped by provider.
  // Skip providers that have no models at all (empty allModelIds).
  final entries = <ModelEntry>[];
  final entriesBySelection = <(String, String), ModelEntry>{};
  for (final config in models) {
    final configId = config.id.trim();
    if (configId.isEmpty) continue;
    final providerLabel = config.providerLabel.trim().isEmpty
        ? configId
        : config.providerLabel.trim();
    final protocolLabel = config.protocolType.storageValue;
    final allIds = config.allModelIds;
    if (allIds.isEmpty) {
      // Provider has no models — hide from the selector.
      continue;
    }
    for (final modelId in allIds) {
      final normalizedModelId = modelId.trim();
      if (normalizedModelId.isEmpty) continue;
      if (modelFilter != null && !modelFilter(config, normalizedModelId)) {
        continue;
      }
      final entry = ModelEntry(
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

  // Build recent entries from persisted selections, validating against current
  // provider configs to prune stale entries.
  final recentEntries = <ModelEntry>[];
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

  final List<ModelEntry> entries;
  final List<ModelEntry> recentEntries;
  final String? selectedConfigId;
  final String? selectedModelId;

  @override
  State<_ModelSearchDialog> createState() => _ModelSearchDialogState();
}

class _ModelSearchDialogState extends State<_ModelSearchDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  List<ModelEntry> _filtered = const [];

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
        final terms = query.split(RegExp(r'\s+'));
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
    final isZh = openHandIsChineseLocale(context);

    // Group filtered entries by provider.
    final grouped = <String, List<ModelEntry>>{};
    for (final entry in _filtered) {
      final key = '${entry.providerLabel}  (${entry.protocolLabel})';
      (grouped[key] ??= []).add(entry);
    }
    final isSearching = _searchController.text.trim().isNotEmpty;
    final recentFiltered = isSearching
        ? const <ModelEntry>[]
        : widget.recentEntries
              .where(
                (entry) => _filtered.any(
                  (item) =>
                      item.configId == entry.configId &&
                      item.modelId == entry.modelId,
                ),
              )
              .toList(growable: false);
    final hasAnyModels = widget.entries.isNotEmpty;

    return buildOpenHandDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kModelSearchDialogRadius),
      ),
      maxWidth: _kModelSearchDialogMaxWidth,
      maxHeight: _kModelSearchDialogMaxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Search field ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: isZh ? '搜索模型…' : 'Search models…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
                // Select the first filtered result on Enter.
                if (_filtered.isNotEmpty) {
                  final first = _filtered.first;
                  Navigator.of(context).pop((first.configId, first.modelId));
                }
              },
            ),
          ),
          // ─── Result count ───
          if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isZh
                      ? '${_filtered.length} / ${widget.entries.length} 个模型'
                      : '${_filtered.length} / ${widget.entries.length} models',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          // ─── Model list ───
          Flexible(
            child: !hasAnyModels
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isZh ? '暂无可用模型' : 'No available models',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        isZh ? '无匹配模型' : 'No matching models',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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
                      child: ListView(
                        controller: _scrollController,
                        primary: false,
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          if (recentFiltered.isNotEmpty) ...[
                            _ModelSectionHeader(
                              label: isZh ? '最近使用' : 'Recent',
                            ),
                            for (final entry in recentFiltered)
                              _ModelTile(
                                entry: entry,
                                isActive:
                                    entry.configId == widget.selectedConfigId &&
                                    entry.modelId == widget.selectedModelId,
                                showProviderSubtitle: true,
                                onTap: () {
                                  Navigator.of(
                                    context,
                                  ).pop((entry.configId, entry.modelId));
                                },
                              ),
                            const SizedBox(height: 4),
                          ],
                          for (final group in grouped.entries) ...[
                            _ModelSectionHeader(label: group.key),
                            for (final entry in group.value)
                              _ModelTile(
                                entry: entry,
                                isActive:
                                    entry.configId == widget.selectedConfigId &&
                                    entry.modelId == widget.selectedModelId,
                                onTap: () {
                                  Navigator.of(
                                    context,
                                  ).pop((entry.configId, entry.modelId));
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
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

  final ModelEntry entry;
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
            const SizedBox(width: 12),
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
